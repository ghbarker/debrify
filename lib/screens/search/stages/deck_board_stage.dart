part of '../../search_screen.dart';

/// DECK: trailer plays in a rounded card, next titles stacked behind it.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _DeckBoardStage extends StatelessWidget {
  const _DeckBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildDeckBoard();
}

extension on _SearchScreenState {
  // ── DECK view ────────────────────────────────────────────────────────────

  /// DECK: the trailer stops being wallpaper and becomes an OBJECT — a
  /// rounded 16:9 card floating on ink with the next two titles stacked
  /// behind it. The hole follows the card's laid-out rect (Canvas proved that
  /// needs no native work); the rounded corners are four ink wedges painted
  /// ABOVE the layers, because a clip would put a saveLayer over the hole.
  Widget _buildDeckBoard() {
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
        // RESERVE THE RAIL FIRST, then let the card have what is left — the
        // other way round, a tall card on a short board silently pushes the
        // rail off the bottom edge.
        final railBoxH = _stageRailBoxH(
          context,
          boardH * 0.24,
          maxH: boardH * 0.34,
        );
        final railZoneH =
            _atriumLabelHeight(context) +
            _kAtriumLabelGap +
            railBoxH +
            _kDeckRailTail;
        final cardTop = boardH * 0.11;
        // The TRUE remainder — never clamped up, which would hand the card
        // height the rail has already been promised.
        var cardH = max(0.0, boardH - cardTop - railZoneH - _kDeckRailGap);
        var cardW = cardH * 16 / 9;
        final maxCardW = boardW * 0.56;
        if (cardW > maxCardW) {
          cardW = maxCardW;
          cardH = cardW * 9 / 16;
        }
        final cardLeft = boardW - cardW - _kDeckCardRightPad;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Constant ground — a single radial, never tweened.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.55, -0.35),
                    radius: 1.15,
                    colors: [
                      Color(0xFF1B1730),
                      Color(0xFF0C0A16),
                      Color(0xFF08070F),
                    ],
                    stops: [0.0, 0.62, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            // The deck's two peek cards — STATIC art of the next two titles
            // on this rail. Never a second video: one engine, one card.
            // Listens to the focused column so the stack DEALS as you move;
            // only this subtree rebuilds.
            ValueListenableBuilder<int>(
              valueListenable: _stageCol,
              builder: (context, focusedCol, _) => Stack(
                children: _deckPeeks(
                  items: items,
                  favRail: favRail,
                  focused: focusedCol,
                  left: cardLeft,
                  top: cardTop,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
            // THE CARD.
            Positioned(
              left: cardLeft,
              top: cardTop,
              width: cardW,
              height: cardH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CanvasArtLayer(
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
                      heroHeight: cardH,
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
                      heroHeight: cardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      onPlaybackFailed: _onHeroLivePlaybackFailed,
                    ),
                  // Rounded corners WITHOUT a clip: four ink wedges painted
                  // over the layers. A ClipRRect here would wrap the punch
                  // hole in a saveLayer and break the blend.
                  IgnorePointer(
                    child: CustomPaint(
                      painter: const _CornerWedges(
                        radius: _kDeckCardRadius,
                        color: Color(0xFF0C0A16),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // A hairline inside the wedges reads as the card's edge.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_kDeckCardRadius),
                        border: Border.all(
                          color: app.fade(app.core.tx, 0.10),
                          width: 1,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            // IDENTITY column, left of the card.
            Positioned(
              left: _kDeckPanelPad,
              top: 0,
              width: (cardLeft - _kDeckPanelPad - 40).clamp(140.0, 560.0),
              bottom: railZoneH,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<_CanvasFavFocus?>(
                    valueListenable: _canvasFavFocus,
                    builder: (context, fav, _) => fav != null
                        ? _StageFavIdentity(fav: fav)
                        : _CanvasIdentity(
                            item: _heroItem,
                            enriched: _heroEnriched,
                            trailerShowing: _heroTrailerShowing,
                            variant:
                                boardH - railZoneH >=
                                    _stageNarrowIdentityH(context)
                                ? _StageIdentityVariant.narrow
                                : _StageIdentityVariant.headline,
                            maxWidth: (cardLeft - _kDeckPanelPad - 40).clamp(
                              140.0,
                              560.0,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            // The rail. Recedes with the lights in theater, cells still
            // MOUNTED so focus survives.
            Positioned(
              left: _kDeckPanelPad,
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
                        padding: const EdgeInsets.only(right: _kDeckPanelPad),
                        child: _deckRailLabel(view),
                      ),
                      const SizedBox(height: _kAtriumLabelGap),
                      SizedBox(
                        height: railBoxH,
                        child: ListView.builder(
                          key: ValueKey('deck-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          itemCount: count,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: favRail
                                    ? _stageFavW(context, railBoxH)
                                    : _stagePosterW(railBoxH),
                                child: favRail
                                    ? _canvasFavCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: railBoxH,
                                        child: _stageShelf.cell(
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
                      const SizedBox(height: _kDeckRailTail),
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
