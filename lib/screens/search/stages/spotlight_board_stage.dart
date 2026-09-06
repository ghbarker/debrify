import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../search_board_runtime.dart';

/// Render-only inputs sampled at the original child-build point. The host owns
/// the key/node and trailer layer; this stage never creates or disposes them.
typedef SpotlightStageFrame = ({
  List<CanvasRail> rails,
  GlobalKey<SpotlightBoardState> boardKey,
  List<StremioMeta> hero,
  List<SpotlightShelf> sections,
  FocusNode heroNode,
  StremioAddon? heroAddon,
  bool dpad,
  bool showCardTitlesAndRatings,
  void Function(StremioMeta, StremioAddon) onHeroOpen,
  SearchBoardRuntime board,
  bool trailersEnabled,
  void Function(StremioMeta) onDwell,
  VoidCallback onTrailerStop,
  Widget? trailer,
  void Function(String?, Color?)? onAmbient,
});

/// Actual Spotlight renderer. Empty-shelf fallback remains in Home dispatch.
class SpotlightStage extends StatelessWidget {
  const SpotlightStage({super.key, required this.readFrame});

  final SpotlightStageFrame Function() readFrame;

  @override
  Widget build(BuildContext context) {
    final frame = readFrame();
    return SpotlightBoard(
      key: frame.boardKey,
      hero: frame.hero,
      sections: frame.sections,
      heroNode: frame.heroNode,
      heroAddon: frame.heroAddon,
      dpad: frame.dpad,
      showCardTitlesAndRatings: frame.showCardTitlesAndRatings,
      onHeroOpen: frame.onHeroOpen,
      onLoadMoreRow: (row) {
        if (row < 0 || row >= frame.rails.length) return;
        final catalogRow = frame.rails[row].sectionIndex;
        if (catalogRow != null) unawaited(frame.board.loadMoreRow(catalogRow));
      },
      onLoadMoreShelves: frame.board.loadMoreBoard,
      // The board owns cadence. Do not fold suppression into this flag: the
      // dwell is the event that can lift suppression for the next title.
      trailersEnabled: frame.trailersEnabled,
      onDwell: frame.onDwell,
      onTrailerStop: frame.onTrailerStop,
      trailer: frame.trailer,
      onAmbient: frame.onAmbient,
    );
  }
}
