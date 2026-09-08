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
/// On a TV the grow runs on [AppMotion.tvFocus], the one tempo every focus
/// treatment shares there, so the tile losing the cursor shrinks over exactly
/// the beat the tile gaining it grows — a snapped TV grow (the shipped
/// policy before this) read as the old tile flashing off.
///
/// Stateless about focus itself, like `FocusExpressionBox`: the caller ORs
/// its focus and hover flags into [active].
class HoverGrow extends StatelessWidget {
  final bool active;
  final bool isTelevision;

  /// Set false where something else already owns the growth — `ParallaxFocus`
  /// under the parallax expression lifts a poster 1.10 on its own spring, and
  /// stacking this on top would scale the card twice. Returns [child] as is.
  final bool enabled;

  final Widget child;

  const HoverGrow({
    super.key,
    required this.active,
    required this.isTelevision,
    this.enabled = true,
    required this.child,
  });

  /// The tempo the grow — and anything animating beside it — runs at.
  ///
  /// TV: the shared [AppMotion.tvFocus] (legacy 120ms — the board rise's
  /// shipped figure, now every TV tile's). Elsewhere the theme's `base`: a
  /// 12% grow wants a beat longer than the 150–180ms the smaller pops used.
  /// Both go through [AppMotion], so reduced motion collapses them to zero.
  static Duration durationFor(AppMotion motion, bool isTelevision) =>
      isTelevision ? motion.tvFocus : motion.base;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // Resolved in build, hoisted above the animated widget — never inside a
    // transition callback. See the rules on [AppMotion].
    final app = AppThemeScope.of(context);
    final motion = AppMotion.of(context);
    return AnimatedScale(
      scale: active ? app.focus.hoverScaleFor(isTelevision) : 1.0,
      duration: durationFor(motion, isTelevision),
      // The TV profile's curve on a TV (`emphasized` under smooth — a
      // transform, so the overshoot is safe); the theme's `standard` off it.
      curve: motion.focusCurve(isTelevision, motion.standard),
      child: child,
    );
  }
}
