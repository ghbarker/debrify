import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/app_theme_scope.dart';
import 'layout_preview_chrome.dart';
import 'layout_preview_detail.dart';
import 'layout_preview_live_tv.dart';
import 'layout_preview_player.dart';
import 'layout_preview_tv_home.dart';
import 'schematic_kit.dart';

/// A mini-screen showing one Screen-layouts option, drawn under [theme].
///
/// Every layout is a SCHEMATIC of the real screen — the same blocks in the
/// same proportions (hero, title, shelf, list, rail), in the theme's own
/// tokens — rather than the real widget at reduced scale. The real layouts
/// need a live `DetailModel`, home data, `MainPageBridge` and network art,
/// none of which belongs on a settings pane; a schematic renders for every
/// option with fixture geometry and settles in a widget test.
///
/// Geometry is fixed: everything is composed on a [canvasWidth] ×
/// [canvasHeight] stage and scaled to fit by a FittedBox, so no option can
/// overflow at a compact phone width, the TV frame or a wide desktop pane.
/// Pushes its own [AppThemeScope] so the schematic follows the Look the card
/// is previewing, not the ambient one.
class LayoutPreviewStage extends StatelessWidget {
  const LayoutPreviewStage({
    super.key,
    required this.theme,
    required this.rowId,
    required this.optionId,
    this.variant,
  });

  final AppTheme theme;
  final String rowId;
  final String optionId;

  /// Secondary settings the picture honours — see
  /// `LayoutPreviewTarget.variant`.
  final String? variant;

  static const double canvasWidth = 320;
  static const double canvasHeight = 180;

  /// Tallest the stage gets when nothing bounds it. In the Appearance card
  /// the slot is the theme stage's height (bounded), and the canvas is
  /// fitted inside it.
  static const double maxHeight = 200;

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      theme: theme,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : canvasWidth;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : math.min(w * canvasHeight / canvasWidth, maxHeight);
          return SizedBox(
            height: h,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: LayoutSchematic(
                  rowId: rowId,
                  optionId: optionId,
                  variant: variant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The unscaled 320×180 picture. Split out so a test can pump every option
/// at canvas size and assert that nothing overflows.
class LayoutSchematic extends StatelessWidget {
  const LayoutSchematic({
    super.key,
    required this.rowId,
    required this.optionId,
    this.variant,
  });

  final String rowId;
  final String optionId;
  final String? variant;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final kit = SchematicKit(app);
    return Container(
      decoration: BoxDecoration(
        color: app.core.ground,
        borderRadius: app.shape.br(12),
        border: Border.all(color: app.core.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: layoutSchematicChildren(kit, rowId, optionId, variant),
      ),
    );
  }
}

/// Dispatches to the per-row schematic. An unknown row or option gets the
/// generic picture rather than nothing, so a new pref value never blanks
/// the card.
List<Widget> layoutSchematicChildren(
  SchematicKit kit,
  String rowId,
  String optionId, [
  String? variant,
]) {
  switch (rowId) {
    case 'detailPageStyle':
      return detailPageSchematic(kit, optionId);
    case 'tvHomeStyle':
      return tvHomeSchematic(kit, optionId);
    case 'discoverLayout':
      return discoverSchematic(kit, optionId);
    case 'tvSidebarStyle':
      return tvSidebarSchematic(kit, optionId);
    case 'desktopSidebarStyle':
      return desktopSidebarSchematic(kit, optionId);
    case 'navigationStyleAppearance':
      return phoneNavSchematic(kit, optionId);
    case 'profileAppearance':
      return profilePickerSchematic(kit, optionId);
    case 'iptvAppearance':
      return iptvSchematic(kit, optionId);
    case 'debrifyTvAppearance':
      return debrifyTvSchematic(kit, optionId);
    case 'playerGuideStyle':
      return playerGuideSchematic(kit, optionId);
    case 'playLoaderStyle':
      return playLoaderSchematic(kit, optionId);
    case 'parentsGuideStyle':
      return parentsGuideSchematic(kit, optionId);
    case 'playerDock':
      return playerDockPreview(kit, optionId, variant);
  }
  return kit.generic();
}
