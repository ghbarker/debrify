import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What the cursor DOES when it lands on something.
///
/// Disproportionately important: on a TV the focus indicator is what the user
/// looks at essentially all of the time. Every theme currently expresses it
/// identically — a ring, optionally with a glow — which is a large part of why
/// they feel like one app.
enum FocusExpression {
  /// A border around the item. Today's app, and the legacy pin.
  ring,

  /// The item grows. No border.
  scale,

  /// The item rises with a shadow.
  lift,

  /// Foreground and background swap — the way a terminal shows selection.
  invert,

  /// The item fills with the accent.
  flood,

  /// A bar under the item only.
  underline,

  /// The item lifts, tilts on a perspective, and catches a specular
  /// highlight — the tvOS focus effect.
  ///
  /// Distinct from [lift], which is a rise and a shadow and nothing else:
  /// this adds rotation about both axes on a 700px perspective, a shift and
  /// shadow that travel with the tilt, and a moving white glare. It is also
  /// the only expression driven by a **spring** rather than a curve, because
  /// its defining property is overshoot-and-settle — a curve decelerates into
  /// its target and stops, which is what reads as mechanical when you hold a
  /// direction down and travel through a row.
  ///
  /// The per-shape scale lives in `ParallaxFocus`, NOT in the theme's
  /// [FocusTokens.scale] — a poster lifts 1.1 and a 432-wide episode still
  /// cannot, or it eats its neighbour.
  parallax,
}

/// The cursor's character.
@immutable
class FocusTokens {
  final FocusExpression expression;

  /// Ring thickness. Read through [widthFor], which keeps the 2.5px floor a
  /// cursor needs to survive at three metres.
  final double width;

  /// How far outside its bounds the ring sits. Requires the site to have room;
  /// see the note on [FocusTokens.legacy].
  final double offset;

  /// Scale factor for [FocusExpression.scale] and [FocusExpression.lift].
  final double scale;

  /// Vertical rise, in logical pixels, for [FocusExpression.lift].
  final double lift;

  /// How far a POSTER TILE or CARD grows when a pointer hovers it or a
  /// non-TV keyboard cursor lands on it — the "hovered box gets bigger"
  /// feedback of the catalog grids, the board rise and the detail's
  /// recommendation row.
  ///
  /// Distinct from [scale] on purpose: that one is the theme's CURSOR, and it
  /// is applied to everything focusable (a settings row, a pill, a button),
  /// so it has to stay small. This is a figure for a tile that has its own
  /// gap to grow into, read through [hoverScaleFor] so TV keeps its calmer
  /// pop whatever a theme asks for. Every shipped theme takes the default —
  /// a theme that wants a different pointer feel sets it here, ONCE, rather
  /// than at the four sites that used to carry their own literal.
  final double hoverScale;

  const FocusTokens({
    required this.expression,
    required this.width,
    required this.offset,
    required this.scale,
    required this.lift,
    this.hoverScale = 1.12,
  });

  /// The TV pop, shared by every tile that grows under DPAD focus. Nuvio-class
  /// 1.045: two cards animate on every DPAD move (loser + gainer), and with
  /// the light ring the small lift reads premium while neighbours shift less.
  /// Not a theme choice — it is the raster budget of the platform.
  static const double tvHoverScale = 1.045;

  /// Today's app: an in-bounds ring at Signal's shipped width, no scale, no
  /// lift.
  ///
  /// `offset: 0` matters — Signal draws its ring IN BOUNDS, and every focus
  /// site in the app assumes that. An outward offset needs each site to make
  /// room for it, which is why `ShapeTokens.focusOffset` shipped
  /// carried-not-adopted.
  static const FocusTokens legacy = FocusTokens(
    expression: FocusExpression.ring,
    width: 2.5,
    offset: 0,
    scale: 1,
    lift: 0,
  );

  /// The cursor must survive at three metres whatever the theme asked for —
  /// the same rule and the same floor as `ShapeTokens.focusWidthFor` and
  /// `DetailTheme.focusWidthFor`.
  double widthFor(bool isTv) => isTv ? math.max(width, 2.5) : width;

  /// Whether this expression paints a border at all.
  ///
  /// `scale` and `lift` deliberately do not: a ring on top of a scale reads as
  /// two cursors, and the whole point of those expressions is that motion,
  /// not decoration, tells you where you are.
  bool get drawsRing => switch (expression) {
    FocusExpression.ring => true,
    // Invert and flood REPLACE the surface; a ring around an already-inverted
    // cell is a second cursor drawn on top of the first. `ThemeSpec` derives
    // width 1 for them for the same reason, and the two must agree.
    FocusExpression.invert ||
    FocusExpression.flood ||
    FocusExpression.scale ||
    FocusExpression.lift ||
    // Borderless by definition: the reference draws no ring on anything, and
    // the lift IS the signal. A ring here would be the second cursor again.
    FocusExpression.parallax ||
    FocusExpression.underline => false,
  };

  /// Scale is honoured on TV — it is a transform, not a raster — but the lift
  /// shadow it usually travels with is filtered by the surface layer.
  double scaleFor(bool isTv) => scale;

  /// The tile-growth figure for [hoverScale], with the TV policy applied: a
  /// TV always gets [tvHoverScale], never the theme's pointer figure. Same
  /// rule shape as [widthFor] — the platform wins over the theme.
  double hoverScaleFor(bool isTv) => isTv ? tvHoverScale : hoverScale;
}
