part of '../../search_screen.dart';

/// PROMENADE: Canvas's stage with a centre-locked strip.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _PromenadeBoardStage extends StatelessWidget {
  const _PromenadeBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildPromenadeBoard();
}

extension on _SearchScreenState {
  // ── PROMENADE view ───────────────────────────────────────────────────────

  /// PROMENADE: Canvas's stage, symmetric. The identity sits centred in the
  /// lower third and the rail becomes a CENTRE-LOCKED strip — the focused
  /// cell is pinned to the middle of the board and the strip travels under
  /// it. Centre-lock is free: board cards already
  /// `ensureVisible(alignment: 0.5)`; the half-viewport pads below simply let
  /// the FIRST and LAST cell reach the middle too, which a plain list can't.
  Widget _buildPromenadeBoard() {
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    _seedStageFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        // ONE box height for every rail kind; the kinds fill it differently
        // (see [_stageFavW]) so neither wastes the other's space.
        final double stripBoxH = _stageRailBoxH(
          context,
          boardH * 0.27,
          maxH: boardH * 0.42,
        );
        final double cellW = favRail
            ? _stageFavW(context, stripBoxH)
            : stripBoxH * 16 / 9;
        // Measured bottom-up, exactly like Canvas's shelfColumnH, so the
        // identity's clearance is DERIVED and can never drift into the strip.
        final columnH =
            _kPromStripTail +
            stripBoxH +
            _kPromLabelGap +
            _promenadeLabelHeight(context);
        // Half-viewport pads: without them the list clamps at its ends and
        // the first/last cell can never reach the centre lock.
        final double sidePad = ((boardW - cellW) / 2).clamp(0.0, boardW / 2);
        final itemCount = favRail
            ? _canvasFavItemCount(rail.favKind!)
            : items.length;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art, BELOW the punch hole so the
            // video replaces it in place when the trailer starts.
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
            IgnorePointer(
              child: _CanvasScrims(
                theater: _canvasTheater,
                variant: _StageScrimVariant.centered,
              ),
            ),
            // Centred identity — which glides to the TOP-LEFT in theater, the
            // Netflix billboard move Canvas already makes. A logo parked in
            // the middle of a clean full-screen trailer reads as something
            // left behind; in the corner it reads as a signature. Meta and
            // synopsis have already faded by then (they go with
            // trailerShowing, before the dwell), so what travels is the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: _canvasTheater ? 36 : 0,
                    bottom: _canvasTheater ? 0 : columnH + _kPromIdentityGap,
                  ),
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: _canvasTheater
                        ? Alignment.topLeft
                        : Alignment.bottomCenter,
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
                      child: ValueListenableBuilder<CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? StageFavIdentity(fav: fav, centered: true)
                            : CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                                variant: StageIdentityVariant.centered,
                                maxWidth: boardW - 96,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail label + the strip. Theater recede: slide + fade, cells stay
            // MOUNTED so focus survives and the wake keypress still moves.
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
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kPromLabelGap,
                        ),
                        child: _promenadeLabel(view),
                      ),
                      SizedBox(
                        height: stripBoxH,
                        child: ListView.builder(
                          // Keyed by rail IDENTITY: insertions above the
                          // active rail must never read as a content swap.
                          key: ValueKey('prom-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          padding: EdgeInsets.symmetric(horizontal: sidePad),
                          itemCount: itemCount,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: cellW,
                                child: favRail
                                    ? _canvasFavCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: stripBoxH,
                                        child: _promenadeCell(
                                          rail,
                                          railKey,
                                          items,
                                          nodes,
                                          col,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kPromStripTail),
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
