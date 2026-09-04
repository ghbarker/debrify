part of '../../search_screen.dart';

/// CANVAS home: full-bleed stage with one bottom shelf and rail tabs.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _CanvasBoardStage extends StatelessWidget {
  const _CanvasBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildCanvasBoard();
}

extension on _SearchScreenState {
  /// The CANVAS home: full-bleed stage (idle art → ambient trailer via the
  /// same underlay engine, whose hole simply gets the whole canvas) with ONE
  /// shelf of large posters at the bottom and quiet rail tabs above it. No
  /// vertical scrolling, nothing clips at a fold, no row headers.
  Widget _buildCanvasBoard() {
    final view = _resolveStageRail();
    if (view == null) {
      // First batch still streaming (or every loaded row is empty) — hold
      // the brand stage rather than an empty black canvas.
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    final rails = view.rails;
    final railIndex = view.index;
    final rail = view.rail;
    final railKey = view.key;
    final bool favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;

    _seedStageFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final double cardH = (boardH * 0.30).clamp(150.0, 220.0);
        // Title cards follow the Home Cards orientation (full shelf height
        // either way — the same grammar as Promenade's strip); favourites
        // keep their portrait cell whatever the setting says.
        final cardW = cardH * _titleCardAspect;
        final favCardW = cardH * 2 / 3;
        // ONE height for the whole bottom column, measured bottom-up, so the
        // identity block above can reserve exactly what the tabs and shelf
        // actually occupy — at any text scale, and whatever the shelf box
        // grows to next.
        final shelfBoxH =
            cardH + _homeArtPosterCaptionBand + _kCanvasShelfSlack;
        final shelfColumnH =
            _kCanvasShelfTail +
            shelfBoxH +
            _kCanvasTabsGap +
            _canvasTabsHeight(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art. Sits BELOW the punch hole,
            // so the video replaces it in place when the trailer starts.
            // While a favourites cell has focus, the favourite's own art
            // overrides the hero pipeline's.
            _CanvasArtLayer(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              cacheWidth: _tvHeroArtworkCacheWidth,
              cacheHeight: _tvHeroArtworkCacheHeight,
            ),
            // Full-bleed ambient trailer: same engine, whole-canvas region.
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
            // A focused IPTV favourite's live feed, full-bleed in the SAME
            // region — above the catalog trailer layer so it simply wins
            // whenever a channel has focus (shrinks to nothing otherwise),
            // exactly like the classic board's boxed version.
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
            // ONE scrim set painted above art AND video — identical in both
            // states so trailer start never swaps the lighting. Plain
            // gradient draws over the hole: the proven feather pattern. In
            // theater the BOTTOM ramp fades with the shelf it exists for.
            IgnorePointer(child: _CanvasScrims(theater: _canvasTheater)),
            // Identity (logo art + meta line), settle-driven like the hero.
            // THEATER: the logo glides to the top-left and shrinks — Netflix
            // billboard style — so the clean full-bleed video still carries a
            // quiet signature. Meta + synopsis are already faded by then
            // (they go with trailerShowing, before the dwell), so what
            // travels is effectively just the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: _canvasTheater ? 36 : 0,
                    bottom: _canvasTheater
                        ? 0
                        : shelfColumnH + _kCanvasIdentityGap,
                  ),
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: _canvasTheater
                        ? Alignment.topLeft
                        : Alignment.bottomLeft,
                    duration: _canvasTheater
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedScale(
                      scale: _canvasTheater ? 0.7 : 1.0,
                      alignment: Alignment.topLeft,
                      duration: _canvasTheater
                          ? const Duration(milliseconds: 900)
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      // Favourites focus: the favourite's own name replaces
                      // the hero identity (favourites aren't StremioMeta, so
                      // the logo/meta pipeline has nothing true to say).
                      // Notifier-driven, so a fav scrub repaints only this.
                      child: ValueListenableBuilder<_CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? _StageFavIdentity(fav: fav)
                            : _CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail tabs + the shelf. Theater recede: slide down a touch +
            // fade out (house cadence — slow lights-down, instant lights-up).
            // Opacity/slide only, cells stay MOUNTED: focus survives, and the
            // wake keypress still performs its normal move.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _canvasTheater ? const Offset(0, 0.12) : Offset.zero,
                duration: _canvasTheater
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _canvasTheater ? 0.0 : 1.0,
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kCanvasTabsGap,
                        ),
                        child: _canvasTabs(rails, railIndex),
                      ),
                      SizedBox(
                        // ONE height for every rail (favourites cells carry a
                        // caption band; meta cells centre in the extra slack):
                        // a per-rail height made the tabs row jump ~45px on
                        // every fav↔meta switch and squeezed the outgoing fav
                        // list into a RenderFlex overflow mid-crossfade.
                        // Whatever this becomes, [shelfColumnH] measures it — the
                        // identity block's clearance is derived, never guessed.
                        height: shelfBoxH,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: favRail
                              ? ListView.builder(
                                  // Keyed by rail IDENTITY, like the meta shelf.
                                  key: ValueKey('canvas-rail-$railKey'),
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  cacheExtent: 400,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                  ),
                                  itemCount: _canvasFavItemCount(rail.favKind!),
                                  itemBuilder: (context, col) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    // Centred like the meta cells: splits the
                                    // vertical slack so the focus scale's lift
                                    // isn't clipped at the viewport's top edge.
                                    child: Center(
                                      child: SizedBox(
                                        width: favCardW,
                                        child: _canvasFavCell(
                                          rail.favKind!,
                                          railKey,
                                          col,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  // Keyed by rail IDENTITY: insertions above the active
                                  // rail must never read as a content swap.
                                  key: ValueKey('canvas-rail-$railKey'),
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  cacheExtent: 400,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                  ),
                                  itemCount: items.length,
                                  itemBuilder: (context, col) {
                                    final item = items[col];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: cardW,
                                          height: cardH,
                                          child: _BoardCell(
                                            item: item,
                                            isTelevision: true,
                                            focusNode: nodes[col],
                                            column: col,
                                            rowNodes: nodes,
                                            hasBoundSource: _isBound(item),
                                            // Canvas focus grammar: white ring (the
                                            // violet stays with classic chrome).
                                            ringColor: Colors.white,
                                            aspectRatio: _titleCardAspect,
                                            artUrl: _titleArtUrl(item),
                                            progress: rail.cw?.progressOf(item),
                                            episodeLabel: rail.cw?.episodeOf(
                                              item,
                                            ),
                                            onQuickPlay:
                                                rail.cw != null || _pikpakOnly
                                                ? null
                                                : () => _sectionQuickPlay(
                                                    _sections[rail
                                                        .sectionIndex!],
                                                    item,
                                                  ),
                                            onLongPress: rail.cw == null
                                                ? null
                                                : () => _openCwCardMenu(
                                                    rail.cw!,
                                                    item,
                                                    rail.cwIndex,
                                                    col,
                                                  ),
                                            onFocused: () {
                                              _setHero(item);
                                              _canvasCols[railKey] = col;
                                            },
                                            onUp: () => _stageSwitchRail(-1),
                                            onDown: () => _stageSwitchRail(1),
                                            onOpen: () {
                                              if (rail.cw != null) {
                                                rail.cw!.onOpen(item);
                                              } else {
                                                _sectionOpenItem(
                                                  _sections[rail.sectionIndex!],
                                                  item,
                                                );
                                              }
                                            },
                                            onNearEnd: rail.sectionIndex == null
                                                ? null
                                                : () => _loadMoreRow(
                                                    rail.sectionIndex!,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: _kCanvasShelfTail),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
