part of '../../search_screen.dart';

/// ATRIUM: details on the left, art and two poster rows on the right.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _AtriumBoardStage extends StatelessWidget {
  const _AtriumBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildAtriumBoard();
}

extension on _SearchScreenState {
  /// ATRIUM: a hard vertical cut. Left is a flat ink column carrying the
  /// title's dossier and never taking focus; right is the art (and the
  /// trailer, in the same rect — the hole simply follows the layer's box)
  /// with a two-row poster wall standing on its lower half.
  Widget _buildAtriumBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    final rails = view.rails;
    final active = view.index;
    final hasSecondRow = active + 1 < rails.length;

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        final double splitX = boardW * _kAtriumSplit;
        // ONE row height for every rail kind, filled two ways — reserving the
        // caption band on catalog rows too would cost 45px PER ROW here and
        // push the wall over three quarters of the art.
        //
        // The wall gets a BUDGET (a share of the board) and the row box is
        // derived from what fits inside it, so two scaled labels and a large
        // text scale can shrink the rows instead of running off the board.
        final labelWidth = boardW - splitX - _kAtriumWallPad * 2;
        final topLabel = _atriumRailLabel(rails, active);
        final bottomLabel = hasSecondRow ? _atriumRailLabel(rails, active + 1) : null;
        final topLabelH = _measureAtriumRailLabel(context, topLabel, labelWidth);
        final bottomLabelH = bottomLabel == null
            ? 0.0
            : _measureAtriumRailLabel(context, bottomLabel, labelWidth);
        // The wall gets a BUDGET. If two rows at the accessibility floor
        // (scaled caption + a recognisable poster) don't fit inside it, show
        // ONE row rather than two clipped ones — the second rail is still one
        // DOWN away.
        final floorH = _homeArtPosterCaptionBand + _kStageMinPosterH;
        double chromeFor(int rows) =>
            topLabelH + (rows == 2 ? bottomLabelH : 0) +
            rows * _kAtriumLabelGap +
            (rows - 1) * _kAtriumRowGap +
            _kAtriumWallTail;
        final wallBudget = boardH * _kAtriumWallBudget;
        final twoRowsFit =
            hasSecondRow && wallBudget - chromeFor(2) >= floorH * 2;
        final showSecondRow = hasSecondRow && twoRowsFit;
        final rows = showSecondRow ? 2 : 1;
        final budget = wallBudget - chromeFor(rows);
        final rowBoxH = _stageRailBoxH(
          context,
          min(boardH * 0.22, budget / rows),
          maxH: max(budget / rows, floorH),
        );
        final topRowUnit = topLabelH + _kAtriumLabelGap + rowBoxH;
        final bottomRowUnit = bottomLabelH + _kAtriumLabelGap + rowBoxH;
        final wallH =
            (showSecondRow ? topRowUnit + bottomRowUnit + _kAtriumRowGap : topRowUnit) +
            _kAtriumWallTail;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ART COLUMN — the right side only. The trailer layer is laid out
            // in the same rect, so the punch hole is exactly this box and the
            // video replaces the art in place with no geometry jump.
            Positioned(
              left: splitX,
              top: 0,
              right: 0,
              bottom: 0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CanvasArtLayer(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    fav: _canvasFavFocus,
                    cacheWidth: _tvHeroArtworkCacheWidth,
                    cacheHeight: _tvHeroArtworkCacheHeight,
                  ),
                  if (_heroTrailerActive)
                    _HeroTrailerLayer(
                      trailer: _heroTrailer,
                      isTelevision: widget.isTelevision,
                      heroHeight: boardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      loading: _heroTrailerLoading,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      takeover: _heroTrailerTakeover,
                    ),
                  if (_heroTrailerActive)
                    _HeroLiveLayer(
                      channel: _heroLiveChannel,
                      streamUrl: _heroLiveUrl,
                      heroHeight: boardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      onPlaybackFailed: _onHeroLivePlaybackFailed,
                    ),
                  const IgnorePointer(
                    child: _CanvasScrims(variant: _StageScrimVariant.seam),
                  ),
                ],
              ),
            ),
            // THE INK PANEL. Opaque: the board's own scaffold turns
            // transparent while a trailer plays (the shell glass stage), so
            // the column has to carry its own ground.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: splitX,
              child: ColoredBox(color: app.home.bg),
            ),
            // The seam itself — one hairline, so the cut reads as deliberate.
            Positioned(
              left: splitX,
              top: 0,
              bottom: 0,
              width: 1,
              child: ColoredBox(color: app.fade(app.core.tx, 0.09)),
            ),
            // THE DOSSIER. Never focusable; vertically centred in the column.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: splitX,
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _kAtriumPanelPad,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<String?>(
                        valueListenable: _atriumFocusedRailKey,
                        builder: (context, key, _) {
                          final i = key == null
                              ? active
                              : rails.indexWhere(
                                  (r) => _canvasRailKeyOf(r) == key,
                                );
                          final title = _canvasTabTitle(
                            rails,
                            i < 0 ? active : i,
                          );
                          return Text(
                            title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.6,
                              color: kCardFocusRing,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      ValueListenableBuilder<CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? StageFavIdentity(fav: fav)
                            : CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                                // Drop the synopsis rather than clip it when
                                // the column is short (small board / large
                                // text scale).
                                variant:
                                    boardH - 64 >=
                                        stageNarrowIdentityH(context) + 90
                                    ? StageIdentityVariant.narrow
                                    : StageIdentityVariant.headline,
                                maxWidth: (splitX - _kAtriumPanelPad * 2).clamp(
                                  120.0,
                                  520.0,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // THE WALL — two rails, stacked, over the art's lower half.
            Positioned(
              left: splitX + _kAtriumWallPad,
              right: _kAtriumWallPad,
              bottom: 0,
              height: wallH,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _atriumRow(
                    rails,
                    active,
                    rowBoxH,
                    isTopRow: true,
                    hasRowBelow: showSecondRow,
                    label: topLabel,
                  ),
                  if (showSecondRow) ...[
                    const SizedBox(height: _kAtriumRowGap),
                    _atriumRow(
                      rails,
                      active + 1,
                      rowBoxH,
                      isTopRow: false,
                      hasRowBelow: false,
                      label: bottomLabel!,
                    ),
                  ],
                  const SizedBox(height: _kAtriumWallTail),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
