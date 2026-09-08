import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Drawing primitives for the schematics — every colour is a token of the
/// theme under preview, every radius the theme's shape.
class SchematicKit {
  SchematicKit(this.app);

  final AppTheme app;

  static const double w = 320;
  static const double h = 180;

  /// Place [child] at a rectangle on the canvas.
  Widget at(
    double left,
    double top,
    double width,
    double height,
    Widget child,
  ) => Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: child,
  );

  /// Artwork: a diagonal wash from the accent toward the rail ground.
  /// [seed] varies the mix so a shelf reads as different posters.
  Widget art({int seed = 0, double radius = 0, bool border = false}) {
    final t = (0.35 + (seed % 5) * 0.13).clamp(0.0, 0.92);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(app.core.accent, app.core.pane, t)!,
            app.core.railBg,
          ],
        ),
        borderRadius: radius > 0 ? app.shape.brImg(radius) : null,
        border: border ? Border.all(color: app.core.hair) : null,
      ),
      // A DecoratedBox with no child collapses to its smallest constraint;
      // every primitive fills whatever box it is given instead.
      child: const SizedBox.expand(),
    );
  }

  /// A poster/still with the focus cursor drawn as the theme's focus ring.
  Widget tile({int seed = 0, bool focused = false, double radius = 6}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: app.shape.brImg(radius),
        border: Border.all(
          color: focused ? app.core.focus : app.core.hair,
          width: focused ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(focused ? 1 : 0),
        child: ClipRRect(
          borderRadius: app.shape.brImg(radius),
          child: art(seed: seed),
        ),
      ),
    );
  }

  /// A filled surface in the theme's pane colour.
  Widget panel({double radius = 8, bool glass = false, Widget? child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass ? app.fade(app.core.pane, 0.72) : app.core.pane,
        borderRadius: app.shape.br(radius),
        border: Border.all(color: app.core.hair),
      ),
      child: child ?? const SizedBox.expand(),
    );
  }

  /// Fade from transparent at the top to the ground at the bottom — the
  /// scrim every art-first layout dissolves into.
  Widget scrim({
    AlignmentGeometry begin = Alignment.topCenter,
    AlignmentGeometry end = Alignment.bottomCenter,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [
            app.core.ground.withValues(alpha: 0),
            app.core.ground.withValues(alpha: 0.85),
            app.core.ground,
          ],
          stops: const [0, 0.65, 1],
        ),
      ),
    );
  }

  /// Text as bars. [widths] are fractions of the available width; the
  /// first bar is the heavier title line when [title] is set.
  Widget lines(
    List<double> widths, {
    bool title = false,
    double gap = 3,
    double height = 3,
    Color? color,
    CrossAxisAlignment align = CrossAxisAlignment.start,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final full = c.maxWidth.isFinite ? c.maxWidth : 100.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: align,
          children: [
            for (var i = 0; i < widths.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              Container(
                width: full * widths[i],
                height: title && i == 0 ? height * 2.4 : height,
                decoration: BoxDecoration(
                  color:
                      color ?? (title && i == 0 ? app.core.tx : app.core.tx3),
                  borderRadius: app.shape.brPill,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// The primary action: accent fill, resolved ink, the theme's pill.
  Widget button({double width = 40, double height = 9}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: app.core.accent,
        borderRadius: app.shape.brPill,
      ),
      alignment: Alignment.center,
      child: Container(
        width: height * 0.4,
        height: height * 0.4,
        decoration: BoxDecoration(
          color: app.inkOn(app.core.accent),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// A ghost (secondary) action beside the primary.
  Widget ghost({double width = 28, double height = 9}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, 0.08),
        borderRadius: app.shape.brPill,
        border: Border.all(color: app.core.hair),
      ),
    );
  }

  /// A horizontal shelf of [count] tiles filling the given box.
  Widget shelf(
    int count, {
    int focused = -1,
    double gap = 5,
    double radius = 5,
    int seed = 0,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: tile(seed: seed + i, focused: i == focused, radius: radius),
          ),
        ],
      ],
    );
  }

  /// A vertical list of [count] rows, each a thumb beside two text lines —
  /// the episode list.
  Widget list(
    int count, {
    int focused = -1,
    bool thumbs = true,
    bool numbered = false,
  }) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  if (numbered)
                    SizedBox(
                      width: 10,
                      child: lines(const [0.6], color: app.core.tx2),
                    ),
                  if (thumbs) ...[
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: tile(
                        seed: i + 2,
                        focused: i == focused,
                        radius: 3,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: lines(
                      [0.7, 0.45],
                      gap: 2,
                      height: 2.4,
                      color: i == focused ? app.core.tx : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// A grid of [cols] × [rows] tiles filling the box.
  Widget grid(
    int cols,
    int rows, {
    int focused = -1,
    double gap = 5,
    double radius = 4,
  }) {
    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) SizedBox(height: gap),
          Expanded(
            child: shelf(
              cols,
              focused: focused - r * cols,
              gap: gap,
              radius: radius,
              seed: r * cols,
            ),
          ),
        ],
      ],
    );
  }

  /// A row of tab pills, one lit.
  Widget tabs(int count, {int active = 0}) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: 22,
            height: 6,
            decoration: BoxDecoration(
              color: i == active ? app.core.accent : app.fade(app.core.tx, 0.1),
              borderRadius: app.shape.brPill,
            ),
          ),
        ],
      ],
    );
  }

  /// Hero page dots, one lit.
  Widget dots(int count, {int active = 0}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == active ? app.core.tx : app.fade(app.core.tx, 0.3),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }

  /// A round avatar / cast portrait.
  Widget circle({int seed = 0, bool focused = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Color.lerp(
              app.core.accent,
              app.core.pane,
              0.3 + (seed % 4) * 0.15,
            )!,
            app.core.railBg,
          ],
        ),
        border: Border.all(
          color: focused ? app.core.focus : app.core.hair,
          width: focused ? 2 : 1,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  /// The TV sidebar at rest: a column of icon dots down the left edge.
  Widget rail({bool coin = true}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == 1 && coin
                    ? app.core.tx
                    : app.fade(app.core.tx, 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  /// A fallback picture: a hero with a title and one shelf.
  List<Widget> generic() => [
    at(0, 0, w, 100, art()),
    at(0, 40, w, 60, scrim()),
    at(14, 62, 150, 30, lines(const [0.8, 0.5, 0.35], title: true)),
    at(14, 112, w - 28, 54, shelf(5, focused: 1)),
  ];
}
