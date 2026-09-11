import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/focus_expression.dart';

/// Violet-300 focus ring — a light ring over dark art pops at 10ft, while the
/// deep accent stays for chrome (tags, sidebar). Pairs with the calm 1.045
/// scale below.
const Color kCardFocusRing = Color(0xFFA78BFA);

/// Shared focus "rise" chrome for 2:3 poster cards: scale, shadow and
/// selection ring animate together on ONE duration + curve — mismatched timing
/// (scale tweening while ring/shadow snapped) is what read as cheap.
///
/// The scale is a transform; the two shadows keep fixed geometry while their
/// colours animate, and the ring fades via opacity. The decoration still
/// repaints during its colour tween. Collections can opt into
/// [CollectionCardFocusRise] to retain separate shadow and artwork layers.
///
/// Lives here, outside the board, because the Discover stage's shelf wears the
/// same grammar — focus-feel tuning has to land ONCE for every poster the user
/// walks with a remote.
class CardFocusRise extends StatelessWidget {
  final bool active;
  final bool isTelevision;

  /// Focus ring colour override (the Canvas board and the Discover stage use
  /// white). Null keeps the classic grammar: violet on TV, soft white on
  /// hover elsewhere.
  final Color? ringColor;

  /// Card shape. Defaults to the 2:3 poster every board row uses; the
  /// Promenade strip and Tonight's queue pass 16/9 for wide stills. Only the
  /// AspectRatio changes — scale, shadow, ring and timing stay identical, so
  /// every shape shares one focus feel.
  final double aspectRatio;

  /// Painted OVER the card's content while it is NOT focused — Promenade's
  /// strip uses it so the centre cell reads as the lit one. A colour-animated
  /// rect inside the existing clip: no Opacity, no saveLayer, so dimming a
  /// whole strip costs one fill per card.
  final Color? restVeil;

  /// The card's content layers, stacked (StackFit.expand) inside the rounded
  /// clip; the selection ring draws above all of them.
  final List<Widget> children;

  const CardFocusRise({
    super.key,
    required this.active,
    required this.isTelevision,
    this.ringColor,
    this.aspectRatio = 2 / 3,
    this.restVeil,
    required this.children,
  });

  /// The cursor, off legacy.
  ///
  /// Sits inside the AspectRatio so the theme's ring hugs the card rather than
  /// whatever slot the shelf handed us, and takes no `on:` — a poster's
  /// background is its artwork, which this widget never sees.
  Widget _cursor(bool ownCursor, Widget child) => ownCursor
      ? child
      : FocusExpressionBox(focused: active, radius: 10, child: child);

  @override
  Widget build(BuildContext context) {
    final focusFx = isTelevision
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 160);
    // Legacy keeps the whole rise — scale, lift shadow and ring — because that
    // trio IS this widget's cursor, and it is tuned as one: the ring is 2.5 on
    // TV but 1.5 elsewhere, and `FocusTokens.legacy` is 2.5 with no width
    // override to hand a site. Every other theme gets one cursor, the one it
    // asked for, instead of the theme's expression stacked on this one.
    final ownCursor = AppThemeScope.of(context).isLegacy;
    return AnimatedScale(
      duration: focusFx,
      curve: Curves.easeOutCubic,
      // TV pop calmed from 1.09 to the Nuvio-class 1.045: with the lighter
      // ring the smaller lift reads premium, and neighbours shift less.
      scale: active && ownCursor ? (isTelevision ? 1.045 : 1.05) : 1.0,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _cursor(ownCursor, AnimatedContainer(
          duration: focusFx,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              // Resting shadow — constant, keeps the card grounded.
              const BoxShadow(
                color: Color(0x59000000),
                blurRadius: 12,
                offset: Offset(0, 10),
              ),
              // Lift shadow — same geometry always, only its alpha animates
              // (transparent at rest, so Skia skips the draw entirely). Off
              // legacy it stays transparent: the rise belongs to the theme's
              // expression, and `lift` brings its own elevation ramp.
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: active && ownCursor ? 0.6 : 0.0),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ...children,
                // Rest veil — dims everything that isn't the focused cell.
                // A colour tween on a plain fill: no saveLayer, and fully
                // transparent (so Skia skips it) on the focused card.
                if (restVeil != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: focusFx,
                        curve: Curves.easeOutCubic,
                        color: active ? Colors.transparent : restVeil,
                      ),
                    ),
                  ),
                // Selection ring — accent on TV focus, subtle white on hover.
                // Legacy only; elsewhere the theme's expression draws it (and
                // the caller's [ringColor] has nothing to override, because a
                // theme's cursor colour is the theme's to pick).
                if (ownCursor)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: active ? 1.0 : 0.0,
                        duration: focusFx,
                        curve: Curves.easeOutCubic,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  ringColor ??
                                  (isTelevision
                                      ? kCardFocusRing
                                      : Colors.white.withValues(alpha: 0.6)),
                              width: isTelevision ? 2.5 : 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

/// Collection's TV legacy chrome, with static paint retained across focus
/// frames. Geometry, colours, curve and duration match [CardFocusRise]. Other
/// platforms and themes continue through the shared implementation.
///
/// Separate boundaries keep the resting shadow and clipped content out of the
/// lift/ring fade's paint traversal. This trades a few retained layers per
/// mounted card for fewer paint recordings; raster caching remains the
/// renderer's decision, rather than a guarantee of cheaper GPU frames.
class CollectionCardFocusRise extends CardFocusRise {
  const CollectionCardFocusRise({
    super.key,
    required super.active,
    required super.isTelevision,
    super.ringColor,
    super.aspectRatio,
    super.restVeil,
    required super.children,
  });

  static const _duration = Duration(milliseconds: 120);
  static const _radius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    if (!isTelevision || !AppThemeScope.of(context).isLegacy) {
      return super.build(context);
    }
    return AnimatedScale(
      scale: active ? 1.045 : 1,
      duration: _duration,
      curve: Curves.easeOutCubic,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            const RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: _radius,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 12,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: _duration,
              curve: Curves.easeOutCubic,
              child: const RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: _radius,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.6),
                        blurRadius: 28,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            RepaintBoundary(
              child: ClipRRect(
                borderRadius: _radius,
                child: Stack(fit: StackFit.expand, children: children),
              ),
            ),
            if (restVeil != null)
              IgnorePointer(
                child: ClipRRect(
                  borderRadius: _radius,
                  child: AnimatedContainer(
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    color: active ? Colors.transparent : restVeil,
                  ),
                ),
              ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: _duration,
                curve: Curves.easeOutCubic,
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: _radius,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: _radius,
                        border: Border.all(
                          color: ringColor ?? kCardFocusRing,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
