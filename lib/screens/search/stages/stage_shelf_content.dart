import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../board_cell.dart';
import '../continue_watching_controller.dart';
import '../search_board_runtime.dart';

typedef StageShelfBindings = ({
  bool Function(StremioMeta) isBound,
  bool Function() pikpakOnly,
  double Function() titleAspect,
  String? Function(StremioMeta) titleArt,
  void Function(StremioMeta) setHero,
  void Function(int) switchRail,
  void Function(CatalogSection, StremioMeta) quickPlay,
  void Function(CatalogSection, StremioMeta) openItem,
  Future<void> Function(CwRow, StremioMeta, int, int) openCwMenu,
  String Function(StageRailView) railTitle,
});

/// Shared Deck/Tonight shelf policy and label. All state is borrowed.
/// Host retains node, map and notifier disposal; this owner disposes nothing.
class StageShelfContent {
  const StageShelfContent({
    required this.board,
    required this.columns,
    required this.focusedColumn,
    required this.bindings,
  });

  final SearchBoardRuntime board;
  final Map<String, int> columns;
  final ValueNotifier<int> focusedColumn;
  final StageShelfBindings bindings;

  Widget label(BuildContext context, StageRailView view) {
    final app = AppThemeScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 13,
              color: app.fade(app.core.tx, 0.45),
            ),
            Transform.translate(
              offset: const Offset(0, -5),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: app.fade(app.core.tx, 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            bindings.railTitle(view).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: app.fade(app.core.tx, 0.86),
            ),
          ),
        ),
      ],
    );
  }

  Widget cell(
    CanvasRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
    VoidCallback? onFocusedExtra,
  }) {
    final item = items[col];
    return BoardCell(
      item: item,
      isTelevision: true,
      focusNode: nodes[col],
      column: col,
      rowNodes: nodes,
      hasBoundSource: bindings.isBound(item),
      ringColor: Colors.white,
      aspectRatio: bindings.titleAspect(),
      artUrl: bindings.titleArt(item),
      progress: rail.cw?.progressOf(item),
      episodeLabel: rail.cw?.episodeOf(item),
      onQuickPlay: rail.cw != null || bindings.pikpakOnly()
          ? null
          : () => bindings.quickPlay(board.sections[rail.sectionIndex!], item),
      onLongPress: rail.cw == null
          ? null
          : () => bindings.openCwMenu(rail.cw!, item, rail.cwIndex, col),
      onFocused: () {
        bindings.setHero(item);
        columns[railKey] = col;
        focusedColumn.value = col;
        onFocusedExtra?.call();
      },
      onUp: onUp ?? () => bindings.switchRail(-1),
      onDown: onDown ?? () => bindings.switchRail(1),
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onOpen: () {
        if (rail.cw != null) {
          rail.cw!.onOpen(item);
        } else {
          bindings.openItem(board.sections[rail.sectionIndex!], item);
        }
      },
      onNearEnd: rail.sectionIndex == null
          ? null
          : () => board.loadMoreRow(rail.sectionIndex!),
    );
  }
}
