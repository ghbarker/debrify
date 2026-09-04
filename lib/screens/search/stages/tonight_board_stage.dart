part of '../../search_screen.dart';

/// TONIGHT: resume-first — Continue card, Up Next queue, one rail below.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _TonightBoardStage extends StatelessWidget {
  const _TonightBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildTonightBoard();
}

extension on _SearchScreenState {
  /// TONIGHT: resume-first. A large card carries whatever has focus, a
  /// vertical Continue queue stands beside it, and one rail runs underneath.
  /// UP/DOWN walks the two zones as a single column, so the Continue rows sit
  /// "above" the first rail exactly as they read.
  Widget _buildTonightBoard() {
    final queue = _tonightQueue;
    final rails = _stageRails;
    if (queue.isEmpty && rails.isEmpty) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    // A zone that no longer exists can't hold focus.
    if (_tonightZoneIsQueue && queue.isEmpty) _tonightZoneIsQueue = false;
    if (!_tonightZoneIsQueue && rails.isEmpty) _tonightZoneIsQueue = true;
    final view = rails.isEmpty ? null : _resolveStageRail();
    _seedStageFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;

        // ── Geometry, derived bottom-up. The rail zone is reserved FIRST,
        // then the main zone takes what is left, then the card and the queue
        // rows are sized from that — so nothing can overlap on a short board.
        final labelH = _atriumLabelHeight(context);
        final double railBoxH = rails.isEmpty
            ? 0
            : _stageRailBoxH(context, boardH * 0.21, maxH: boardH * 0.30);
        final double railZoneH = rails.isEmpty
            ? 0
            : labelH + _kAtriumLabelGap + railBoxH + _kTonightRailTail;
        final headerH = _tonightHeaderHeight(context);
        // The TRUE remainder: clamping this up would re-spend the header's and
        // the rail's reserved height and push them off the board.
        final mainH = max(0.0, boardH - headerH - railZoneH - _kTonightZoneGap);

        var cardH = mainH;
        var cardW = cardH * 16 / 9;
        final maxCardW = boardW * 0.58;
        if (cardW > maxCardW) {
          cardW = maxCardW;
          cardH = cardW * 9 / 16;
        }
        // The queue is the whole point of Tonight, so a board too narrow to
        // hold both shrinks the CARD, never the queue. Only a board narrower
        // than roughly a card floor plus the queue's minimum drops it — and
        // then only when there is a rail left to hold focus.
        if (queue.isNotEmpty) {
          final maxWithQueue =
              boardW -
              _kTonightPadX * 2 -
              _kTonightZoneGap -
              _kTonightQueueMinW;
          if (cardW > maxWithQueue) {
            // Shrink toward the queue, but NEVER widen past what the vertical
            // remainder allows — a wider card is a taller card, and that
            // height belongs to the rail.
            cardW = min(max(maxWithQueue, boardW * 0.34), mainH * 16 / 9);
            cardH = cardW * 9 / 16;
          }
        }
        // How many rows actually FIT — never a fixed four.
        // What a row actually needs at this text scale: two lines of type,
        // the progress bar, their gaps and the row's own padding. Below one
        // of these the queue simply isn't drawn — a 1px row would overflow.
        final rowMinH = _tonightRowMinHeight(context);
        // Zero rows is allowed — but never when the queue is the ONLY thing
        // that could hold focus, or the board would have nothing focusable.
        final minRows = (rails.isEmpty && queue.isNotEmpty) ? 1 : 0;
        final visibleRows = (mainH / (rowMinH + _kTonightRowGap)).floor().clamp(
          minRows,
          4,
        );
        final queueW = (boardW - cardW - _kTonightPadX * 2 - _kTonightZoneGap)
            .clamp(0.0, boardW);
        // Never leave the board with nothing focusable: if the queue can't be
        // drawn and there is no rail either, draw it anyway.
        // With no rail beneath it the queue is the ONLY focusable zone, so
        // it takes the whole board and the card steps aside entirely rather
        // than squeezing it to nothing.
        final queueOnly = rails.isEmpty && queue.isNotEmpty;
        final effQueueW = queueOnly
            ? max(1.0, boardW - _kTonightPadX * 2)
            : queueW;
        final showQueue =
            queue.isNotEmpty &&
            visibleRows > 0 &&
            (queueOnly || effQueueW >= _kTonightQueueMinW) &&
            effQueueW > 0;
        // A zone that isn't on screen must not be the one holding focus.
        if (!showQueue && rails.isNotEmpty) _tonightZoneIsQueue = false;
        // Never taller than the share it actually has: the row height is the
        // MIN of what looks right and what fits.
        final rowH = visibleRows == 0
            ? 0.0
            : min(
                max(
                  (mainH - (visibleRows - 1) * _kTonightRowGap) / visibleRows,
                  rowMinH,
                ),
                _kTonightRowMaxH,
              );
        final queueBoxH = visibleRows == 0
            ? 0.0
            : (rowH * visibleRows + _kTonightRowGap * (visibleRows - 1)).clamp(
                0.0,
                mainH,
              );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Constant ground — one gradient, never tweened.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF161227),
                      Color(0xFF0E0C1B),
                      Color(0xFF0A0813),
                    ],
                    stops: [0.0, 0.46, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            Positioned(
              left: _kTonightPadX,
              right: _kTonightPadX,
              top: 0,
              height: headerH,
              child: _tonightHeader(queue.length),
            ),
            // THE CARD — art, trailer and live all in this rect, so the punch
            // hole is exactly the card. Stood down in queue-only mode, where
            // the queue owns the board.
            if (!(queueOnly && showQueue))
              Positioned(
                left: _kTonightPadX,
                top: headerH,
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
                    // Legibility ramp + the caption block, painted ABOVE the
                    // hole (plain draws only).
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xF00A0810),
                              Color(0xA00A0810),
                              Color(0x000A0810),
                            ],
                            stops: [0.0, 0.30, 0.68],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: const _CornerWedges(
                          radius: _kTonightCardRadius,
                          color: Color(0xFF100D1F),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 20,
                      child: IgnorePointer(
                        child: _TonightCardCaption(
                          item: _heroItem,
                          enriched: _heroEnriched,
                          fav: _canvasFavFocus,
                          info: _tonightCard,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // THE QUEUE.
            if (showQueue)
              Positioned(
                left: queueOnly
                    ? _kTonightPadX
                    : _kTonightPadX + cardW + _kTonightZoneGap,
                top: headerH,
                width: effQueueW,
                height: max(rowH, queueBoxH),
                child: _tonightQueueList(
                  queue,
                  rowH,
                  effQueueW,
                  rails.isNotEmpty,
                ),
              ),
            // THE RAIL.
            if (view != null)
              Positioned(
                left: _kTonightPadX,
                right: 0,
                bottom: 0,
                child: _tonightRail(
                  view,
                  railBoxH,
                  queueAbove: queue.isNotEmpty && showQueue,
                ),
              ),
          ],
        );
      },
    );
  }
}
