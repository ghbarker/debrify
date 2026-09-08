import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import '../app_focus.dart';
import '../app_motion.dart';
import '../app_theme_scope.dart';
import 'hover_grow.dart';
import 'parallax_focus.dart';

// Callers pick their lift shape at the same site they build the box.
export 'parallax_focus.dart' show ParallaxShape;

/// The cursor, as the theme expresses it.
///
/// On a TV this is what the user looks at essentially all of the time, and
/// every theme currently expresses it identically — a ring, sometimes with a
/// glow. Seven expressions is the single highest feel-per-line change in the
/// vocabulary, and it is cheap because focus is already centralised in a
/// handful of widgets.
///
/// Stateless about focus itself: the caller passes [focused], the way
/// `DetailFocusRing` and `CardFocusRise` already do. Three different
/// focus-detection mechanisms exist in the tree (`onFocusChange`,
/// `node.addListener`, `hasFocus` polling), so this widget deliberately knows
/// about none of them.
class FocusExpressionBox extends StatelessWidget {
  final Widget child;
  final bool focused;

  /// The site's own corner radius, before the theme's scale.
  final double radius;

  /// The surface this cursor sits ON. Used to rescue a ring that would vanish
  /// into what it is drawn over — Noir's white on a white button was the
  /// original case, and `DetailTheme.focusOn` is the rule.
  final Color? on;

  /// For [FocusExpression.invert]: what the content becomes when inverted.
  /// Supplied by the caller because only it knows which of its children are
  /// ink.
  final Widget Function(BuildContext, Color ink)? inverted;

  /// What KIND of thing this cursor lifts, under the parallax expression —
  /// it sets how far the lift may scale. The poster default suits cards that
  /// grow into their rail gap; a FULL-WIDTH row must pass
  /// [ParallaxShape.settingsRow], or the 1.10 poster lift pushes 5% of the
  /// row past BOTH screen edges and the focused row reads as cut off.
  final ParallaxShape shape;

  /// Whether this is a POSTER TILE or CARD with its own gap to grow into —
  /// the "hovered box gets bigger" feedback, by [FocusTokens.hoverScaleFor]
  /// through [HoverGrow], on top of whatever the expression draws.
  ///
  /// Off (the default) the box is the theme's CURSOR and nothing more: a
  /// settings row or a pill under `ring` gets a ring, and under `scale` the
  /// small [FocusTokens.scale] that every focusable can afford. On, the tile
  /// grows by the shared tile figure whatever the expression: `ring`,
  /// `underline`, `invert` and `flood` keep their decoration and gain the
  /// grow, while `scale` and `lift` hand their own scale OVER to it — the
  /// cursor's 1.06 / 1.02 is replaced, not stacked, so a tile carries exactly
  /// one scale transform under every expression. `parallax` is untouched:
  /// `ParallaxFocus` owns that lift at its own per-shape peak.
  ///
  /// The point is that a pointer on Windows gets the same answer from every
  /// poster, whichever look is running — a theme's cursor decides what is
  /// DRAWN on the tile, and the tile figure decides how much it grows.
  final bool grow;

  const FocusExpressionBox({
    super.key,
    required this.child,
    required this.focused,
    required this.radius,
    this.on,
    this.inverted,
    this.shape = ParallaxShape.poster,
    this.grow = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = PlatformUtil.isTelevision;
    final f = app.focus;
    final motion = AppMotion.of(context);
    final ring = on == null ? app.core.focus : app.core.focusOn(on!);
    // One tempo for the cursor leaving and the cursor arriving. On TV that is
    // the shared `tvFocus` beat — a SNAPPED cursor (the policy this replaced)
    // read as the old control flashing off in the frame the new one lit, and
    // 120ms is short enough that a held key still never sees the ring trail
    // the keypress. Everything below that is expensive per frame — the bloom,
    // the lift shadow — is gated on the platform separately; what animates
    // here on TV is a border colour, an alpha and a transform.
    final duration = tv ? motion.tvFocus : motion.fast;

    // `flood` and `invert` REPLACE the surface, and this widget paints behind
    // its child — so over an opaque card (artwork, a gradient, a tinted row)
    // neither would be visible at all. The caller opts in by supplying
    // [inverted], which is the only thing that knows which of its children are
    // ink; without it the expression degrades to the ring, which is a cursor
    // that always works rather than one that silently does nothing.
    final replacesSurface = f.expression == FocusExpression.flood ||
        f.expression == FocusExpression.invert;
    final expression = replacesSurface && inverted == null
        ? FocusExpression.ring
        : f.expression;

    // Parallax owns the whole treatment — lift, tilt, shift, shadow and glare,
    // on its own spring — so it returns BEFORE this widget's ring/bloom/scale
    // stack rather than composing with it. Composing would give the card two
    // cursors and two scales: `FocusTokens.scale` is applied at the bottom of
    // this method, and the per-shape scale already lives in ParallaxFocus.
    //
    // Without this arm the expression would fall through every branch below
    // and paint NOTHING — the theme would silently have no cursor at
    // `card_focus_rise` and `source_row`, which both route through here.
    if (f.expression == FocusExpression.parallax) {
      return ParallaxFocus(
        focused: focused,
        shape: shape,
        radius: app.shape.br(radius),
        child: child,
      );
    }

    Widget body = child;

    // The inverted face fades IN over the resting one rather than replacing
    // it: swapping the child on focus remounts the subtree — the flash no
    // duration can hide — and the two faces cross-dissolving on the cursor's
    // own tempo is the whole point of the tempo. Kept out of focus and hit
    // testing: the resting child underneath stays the one thing that acts,
    // so the tree never carries a second button.
    if (replacesSurface && inverted != null) {
      body = Stack(
        fit: StackFit.passthrough,
        children: [
          body,
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeFocus(
                child: AnimatedOpacity(
                  opacity: focused ? 1 : 0,
                  duration: duration,
                  curve: motion.standard,
                  child: ColoredBox(
                    color: app.core.accent,
                    child: inverted!(context, app.inkOn(app.core.accent)),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // The ring, where the expression draws one.
    if (expression == FocusExpression.ring) {
      body = AnimatedContainer(
        duration: duration,
        curve: motion.standard,
        foregroundDecoration: BoxDecoration(
          borderRadius: app.shape.br(radius),
          border: Border.all(
            color: focused ? ring : Colors.transparent,
            width: f.widthFor(tv),
          ),
        ),
        child: body,
      );
    }

    // Underline: a bar beneath, nothing around.
    if (expression == FocusExpression.underline) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: body),
          AnimatedContainer(
            duration: duration,
            height: f.widthFor(tv),
            color: focused ? ring : Colors.transparent,
          ),
        ],
      );
    }

    // The bloom. Off on TV — a blurred shadow that re-rasters on every focus
    // move is the most expensive thing a cursor can do on a weak GPU. Always
    // in the tree where it is on, so gaining focus never remounts the child:
    // fixed geometry, colour fades (transparent at rest costs nothing).
    final bloom = app.light.bloomFor(tv);
    if (bloom > 0) {
      body = AnimatedContainer(
        duration: duration,
        curve: motion.standard,
        decoration: BoxDecoration(
          borderRadius: app.shape.br(radius),
          boxShadow: [
            BoxShadow(
              color: ring.withValues(alpha: focused ? 0.28 : 0),
              blurRadius: bloom,
              spreadRadius: 1,
            ),
          ],
        ),
        child: body,
      );
    }

    // Lift: rises with the theme's elevation.
    if (expression == FocusExpression.lift) {
      body = AnimatedContainer(
        duration: duration,
        curve: motion.standard,
        transform: Matrix4.translationValues(0, focused ? -f.lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: app.shape.br(radius),
          boxShadow: focused
              ? app.surface.shadowFor(app.surface.floatingShadow, tv)
              : app.surface.shadowFor(app.surface.restShadow, tv),
        ),
        child: body,
      );
    }

    // A poster tile grows by the shared tile figure — the one every catalog
    // grid and the detail's recommendation row grow by — on the grow's own
    // tempo (`motion.base` off TV; `tvFocus` on it, as the rest of this
    // cursor does). It REPLACES the cursor scale below rather than stacking on it,
    // so `scale` and `lift` tiles carry one transform, not 1.12 × 1.06.
    if (grow) {
      return HoverGrow(active: focused, isTelevision: tv, child: body);
    }

    // Scale, for both `scale` and `lift`. A transform, so it is affordable on
    // TV — unlike the shadow it usually travels with.
    final scale = f.scaleFor(tv);
    if (scale != 1) {
      body = AnimatedScale(
        scale: focused ? scale : 1,
        duration: duration,
        // A transform: the one place in this stack the smooth profile's
        // overshooting curve is safe. The ring, bloom and lift above lerp
        // decorations and stay on `standard` — see [AppMotion.tvFocusCurve].
        curve: motion.focusCurve(tv, motion.standard),
        child: body,
      );
    }

    return body;
  }
}
