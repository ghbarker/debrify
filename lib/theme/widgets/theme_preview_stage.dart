import 'package:flutter/material.dart';

import '../app_surface.dart';
import '../app_theme.dart';
import '../app_theme_scope.dart';
import 'app_scrim.dart';
import 'focus_expression.dart';
import 'glass_surface.dart';

/// A representative mini-screen drawn under a GIVEN theme.
///
/// One of each thing a theme decides, on the real token consumers rather than
/// mock rectangles: a hero with the theme's scrim grammar and display type, a
/// shelf of poster tiles with the focus expression on one of them, a primary
/// button in the accent with its resolved ink, and a sheet in the theme's
/// separation model. Pushes its own [AppThemeScope] so `GlassSurface`,
/// `AppScrim` and `FocusExpressionBox` read [theme], not the ambient one —
/// which is the whole point when [theme] is a candidate the app is not
/// running.
///
/// Nothing here animates on a loop (no skeleton shimmer), so a settings page
/// that hosts it still settles in widget tests and costs nothing at idle on a
/// TV.
class ThemePreviewStage extends StatelessWidget {
  final AppTheme theme;

  /// Which poster wears the focus cursor. Fixed rather than interactive: the
  /// stage is a picture of the theme, not a control.
  final int focusedTile;

  const ThemePreviewStage({
    super.key,
    required this.theme,
    this.focusedTile = 1,
  });

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      theme: theme,
      child: _Stage(theme: theme, focusedTile: focusedTile),
    );
  }
}

class _Stage extends StatelessWidget {
  final AppTheme theme;
  final int focusedTile;

  const _Stage({required this.theme, required this.focusedTile});

  @override
  Widget build(BuildContext context) {
    final app = theme;
    // Fixed-height bands grow with the system text scale (capped: a 2x
    // setting doubles the copy, not the picture) so the hero's three lines
    // and the shelf's button never overflow a 320dp phone at 200%.
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final grow = scale.clamp(1.0, 2.0);
    return Container(
      decoration: BoxDecoration(
        color: app.core.ground,
        borderRadius: app.shape.br(12),
        border: Border.all(color: app.core.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 300;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _hero(app, height: 96 * grow),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _shelf(app, tiles: narrow ? 2 : 3, height: 64 * grow),
                    const SizedBox(height: 10),
                    _sheet(app, narrow: narrow),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Artwork, the theme's scrim over it, and copy in the theme's display face.
  Widget _hero(AppTheme app, {required double height}) {
    return SizedBox(
      height: height,
      child: AppScrim(
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color.lerp(app.core.accent, app.core.ground, 0.5)!,
                app.core.railBg,
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONTINUE WATCHING',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: app.core.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The Long Night',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: app.type.display(
                  TextStyle(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: app.core.tx,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'S02 · E04 — 48 min left',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: app.type.body(
                  TextStyle(fontSize: 10.5, color: app.core.tx2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Poster tiles in the card separation model, one under the focus cursor,
  /// with the primary action beside them.
  Widget _shelf(AppTheme app, {required int tiles, required double height}) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles; i++) ...[
            SizedBox(
              width: 44,
              child: FocusExpressionBox(
                focused: i == focusedTile,
                radius: 8,
                on: app.core.pane,
                inverted: (c, ink) => _tile(app, i, ink: ink),
                child: _tile(app, i),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Scales down rather than overflowing when large text meets a
          // narrow card — the button is a swatch of the accent, not a target.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: _button(app),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppTheme app, int i, {Color? ink}) {
    final model = app.surface.modelFor(SurfaceFamily.card);
    final filled =
        model == SeparationModel.fill || model == SeparationModel.glass;
    // Each tile is a different mix of the accent and the pane, so the shelf
    // reads as artwork rather than three identical swatches.
    final art = Color.lerp(app.core.accent, app.core.pane, 0.45 + i * 0.2)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? app.core.pane : Colors.transparent,
        borderRadius: app.shape.brImg(8),
        border: model == SeparationModel.space
            ? null
            : Border.all(color: app.core.hair),
      ),
      child: ClipRRect(
        borderRadius: app.shape.brImg(8),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [art, app.core.railBg],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ink ?? app.core.tx3,
                    borderRadius: app.shape.brPill,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The primary button: accent fill, resolved ink, the theme's pill.
  Widget _button(AppTheme app) {
    final ink = app.inkOn(app.core.accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: app.core.accent,
        borderRadius: app.shape.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 16, color: ink),
          const SizedBox(width: 4),
          Text(
            'Resume',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  /// A sheet row in the theme's separation model — glass where the look says
  /// glass, a filled panel otherwise — with a badge in the accent.
  Widget _sheet(AppTheme app, {required bool narrow}) {
    return GlassSurface(
      family: SurfaceFamily.sheet,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.subtitles_rounded, color: app.core.tx2, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              narrow ? 'Subtitles · English' : 'Subtitles · English (SDH)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: app.type.body(
                TextStyle(color: app.core.tx, fontSize: 11.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: app.core.accent,
              borderRadius: app.shape.brPill,
            ),
            child: Text(
              '4K',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: app.inkOn(app.core.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
