import 'package:flutter/material.dart';

import '../app_focus.dart';
import '../app_motion.dart';
import '../app_theme_scope.dart';

/// The "hovered box gets bigger" feedback for poster tiles and cards, as ONE
/// widget so every grid, rail and shelf grows by the same amount at the same
/// tempo.
///
/// Reads [FocusTokens.hoverScaleFor] for the figure and [AppMotion] for the
/// tempo, so a theme's character and the platform's reduced-motion setting
/// both reach it — the four sites this replaced each carried their own scale
/// (1.05, 1.05, 1.08) and their own duration (150, 160, 180ms), none of which
/// a theme could touch.
///
/// A transform, not a layout change: the tile paints larger about its centre
/// while its slot stays put, so neighbours never shift. Sites that also lift a
/// shadow keep it on [durationFor], so scale, shadow and ring stay in
/// lockstep — mismatched timing is what read as cheap.
///
/// Stateless about focus itself, like `FocusExpressionBox`: the caller ORs
/// its focus and hover flags into [active].
class HoverGrow extends StatelessWidget {
  final bool active;
  final bool isTelevision;

  /// Whether a TV tweens the pop or snaps it. Off by default — the classic
  /// grids keep the focus highlight instant (no per-frame tweening of large
  /// posters on a weak GPU). The board rise passes true: its trio is shaped
  /// to be cheap enough, and a snapped board card is the "not native" tell.
  final bool animateOnTv;

  /// Set false where something else already owns the growth — `ParallaxFocus`
  /// under the parallax expression lifts a poster 1.10 on its own spring, and
  /// stacking this on top would scale the card twice. Returns [child] as is.
  final bool enabled;

  final Widget child;

  const HoverGrow({
    super.key,
    required this.active,
    required this.isTelevision,
    this.animateOnTv = false,
    this.enabled = true,
    required this.child,
  });

  /// The tempo the grow — and anything animating beside it — runs at.
  ///
  /// TV: instant, or the theme's `fast` when [animateOnTv] (legacy 120ms, the
  /// board rise's shipped figure). Elsewhere the theme's `base`: a 12% grow
  /// wants a beat longer than the 150–180ms the smaller pops used. Both go
  /// through [AppMotion], so reduced motion collapses them to zero.
  static Duration durationFor(
    AppMotion motion,
    bool isTelevision, {
    bool animateOnTv = false,
  }) {
    if (isTelevision) return animateOnTv ? motion.fast : Duration.zero;
    return motion.base;
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // Resolved in build, hoisted above the animated widget — never inside a
    // transition callback. See the rules on [AppMotion].
    final app = AppThemeScope.of(context);
    final motion = AppMotion.of(context);
    return AnimatedScale(
      scale: active ? app.focus.hoverScaleFor(isTelevision) : 1.0,
      duration: durationFor(motion, isTelevision, animateOnTv: animateOnTv),
      curve: motion.standard,
      child: child,
    );
  }
}
