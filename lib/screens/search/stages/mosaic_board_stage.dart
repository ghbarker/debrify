part of '../../search_screen.dart';

/// MOSAIC: a wall of posters, no hero — the lightest layout.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _MosaicBoardStage extends StatelessWidget {
  const _MosaicBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildMosaicBoard();
}

extension on _SearchScreenState {
  // ── MOSAIC view ──────────────────────────────────────────────────────────

  /// MOSAIC: no hero at all. The active rail becomes a WALL of posters on a
  /// heavily veiled wash of the focused title's art, with the identity moved
  /// to a fixed top band. The cheapest layout on the list: one image, one
  /// flat veil, one grid — and no ambient video (see [_stageWantsAmbient]),
  /// which is why it stays smooth on weak TV hardware.
  Widget _buildMosaicBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;
        // Never negative: a board narrower than its own padding would make
        // every derived width negative and trip a layout assertion.
        final gridW = max(1.0, boardW - _kMosaicPadX * 2);
        // A grid only ever shows ONE rail, and a rail is homogeneous — so
        // the whole wall takes one shape: favourites are always portrait,
        // title cells follow the Home Cards orientation.
        final cellAspect = favRail ? 2 / 3 : _titleCardAspect;
        // Aim for a cell about a third of the board's height — landscape a
        // little shorter, or three backdrops swallow the whole wall — then
        // take whatever whole number of columns actually FITS, as few as one.
        final targetH = boardH * (cellAspect > 1 ? 0.24 : 0.30);
        final targetW = max(1.0, targetH * cellAspect);
        final perRow = (gridW / (targetW + _kMosaicGap)).floor().clamp(1, 8);
        final cellW = max(1.0, (gridW - (perRow - 1) * _kMosaicGap) / perRow);
        // The extent is exactly what this rail's kind needs: the art box,
        // plus the caption band only when the cells actually carry one.
        final extent =
            cellW / cellAspect + (favRail ? _homeArtPosterCaptionBand : 0);

        return Stack(
          fit: StackFit.expand,
          children: [
            CanvasArtLayer(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              cacheWidth: _tvHeroArtworkCacheWidth,
              cacheHeight: _tvHeroArtworkCacheHeight,
            ),
            // Constant veil. It SNAPS (no tween): a full-screen gradient
            // tween is the single most expensive thing this board could do.
            // While a favourite CHANNEL is previewing, the veil lifts so the
            // live picture is actually visible behind the wall.
            ValueListenableBuilder<IptvChannel?>(
              valueListenable: _heroLiveChannel,
              builder: (context, live, _) => IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: live == null
                        ? const Color(0xDE0D0B1A)
                        : const Color(0x9E0D0B1A),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // The live feed sits ABOVE the veil (a veiled video is a waste of
            // a decoder) with its own lighter scrim for the grid's sake.
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
            ValueListenableBuilder<IptvChannel?>(
              valueListenable: _heroLiveChannel,
              builder: (context, live, _) => IgnorePointer(
                child: live == null
                    ? const SizedBox.shrink()
                    : const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x8C0D0B1A)),
                        child: SizedBox.expand(),
                      ),
              ),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.85, -0.95),
                    radius: 1.25,
                    colors: [Color(0x2E7B5CFF), Color(0x000D0B1A)],
                    stops: [0.0, 0.62],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kMosaicPadX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: _kMosaicHeadTop),
                  // Identity band: the wall's only chrome. Fixed height so
                  // the grid below it never shifts as titles change.
                  SizedBox(
                    height: _mosaicHeadHeight(context),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<CanvasFavFocus?>(
                            valueListenable: _canvasFavFocus,
                            builder: (context, fav, _) => Align(
                              alignment: Alignment.bottomLeft,
                              child: fav != null
                                  ? StageFavIdentity(fav: fav)
                                  : CanvasIdentity(
                                      item: _heroItem,
                                      enriched: _heroEnriched,
                                      trailerShowing: _heroTrailerShowing,
                                      variant: StageIdentityVariant.headline,
                                      maxWidth: max(1.0, gridW * 0.5),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        // The windowed TAB STRIP needs the full board width
                        // to show useful context; here it shares a row with
                        // the identity and collapses to a single slot, which
                        // is both cramped and (before the window fix) the
                        // wrong rail. The compact label says the same thing
                        // in a fraction of the width and is correct by
                        // construction: it names the ACTIVE rail and its
                        // position among all of them.
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _promenadeLabel(
                                  view,
                                  align: MainAxisAlignment.end,
                                ),
                                if (view.rails.length > 1) ...[
                                  const SizedBox(height: 8),
                                  // The grid can page for as long as the
                                  // catalog has more, so "walk to the last
                                  // line" is not a way out of it. The hold
                                  // gesture is the way out, and a gesture
                                  // nothing announces may as well not exist.
                                  Text(
                                    'HOLD ▲▼ TO CHANGE ROW',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                      color: app.fade(app.core.tx, 0.34),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _kMosaicHeadGap),
                  Expanded(
                    child: GridView.builder(
                      // Keyed by rail IDENTITY: a rail streaming in above the
                      // active one must never swap the wall's contents.
                      key: ValueKey('mosaic-rail-$railKey'),
                      padding: const EdgeInsets.only(bottom: 24),
                      clipBehavior: Clip.hardEdge,
                      cacheExtent: 600,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: perRow,
                        crossAxisSpacing: _kMosaicGap,
                        mainAxisSpacing: _kMosaicGap,
                        mainAxisExtent: extent,
                      ),
                      itemCount: count,
                      itemBuilder: (context, col) => Center(
                        child: SizedBox(
                          width: cellW,
                          child: _mosaicCell(
                            rail,
                            railKey,
                            items,
                            nodes,
                            col,
                            count,
                            perRow,
                            cellW,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
