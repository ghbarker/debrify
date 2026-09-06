import 'dart:math';
import 'package:flutter/material.dart';
import '../../../widgets/skeleton_poster.dart';
import 'tonight_stage_content.dart';
import 'tonight_stage_widgets.dart';

/// Tonight's resume-first geometry, borrowing its eager content/state owner.
class TonightStage extends StatelessWidget {
  const TonightStage({
    super.key,
    required this.content,
    required this.isTelevision,
  });
  final TonightStageContent content;
  final bool isTelevision;
  @override
  Widget build(BuildContext context) {
    final queue = content.queue;
    final rails = content.bindings.readStageRails();
    if (queue.isEmpty && rails.isEmpty) {
      return BrandLoadingStage(isTelevision: isTelevision);
    }
    // A zone that no longer exists can't hold focus.
    if (content.zoneIsQueue && queue.isEmpty) content.zoneIsQueue = false;
    if (!content.zoneIsQueue && rails.isEmpty) content.zoneIsQueue = true;
    final view = rails.isEmpty ? null : content.bindings.resolveStageRail();
    content.bindings.seedFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;

        // ── Geometry, derived bottom-up. The rail zone is reserved FIRST,
        // then the main zone takes what is left, then the card and the queue
        // rows are sized from that — so nothing can overlap on a short board.
        final labelH = content.bindings.atriumLabelHeight(context);
        final double railBoxH = rails.isEmpty
            ? 0
            : content.bindings.railBoxHeight(
                context,
                boardH * 0.21,
                maxH: boardH * 0.30,
              );
        final double railZoneH = rails.isEmpty
            ? 0
            : labelH + content.bindings.labelGap + railBoxH + kTonightRailTail;
        final headerH = content.headerHeight(context);
        // The TRUE remainder: clamping this up would re-spend the header's and
        // the rail's reserved height and push them off the board.
        final mainH = max(0.0, boardH - headerH - railZoneH - kTonightZoneGap);

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
              boardW - kTonightPadX * 2 - kTonightZoneGap - kTonightQueueMinW;
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
        final rowMinH = content.rowMinHeight(context);
        // Zero rows is allowed — but never when the queue is the ONLY thing
        // that could hold focus, or the board would have nothing focusable.
        final minRows = (rails.isEmpty && queue.isNotEmpty) ? 1 : 0;
        final visibleRows = (mainH / (rowMinH + kTonightRowGap)).floor().clamp(
          minRows,
          4,
        );
        final queueW = (boardW - cardW - kTonightPadX * 2 - kTonightZoneGap)
            .clamp(0.0, boardW);
        // Never leave the board with nothing focusable: if the queue can't be
        // drawn and there is no rail either, draw it anyway.
        // With no rail beneath it the queue is the ONLY focusable zone, so
        // it takes the whole board and the card steps aside entirely rather
        // than squeezing it to nothing.
        final queueOnly = rails.isEmpty && queue.isNotEmpty;
        final effQueueW = queueOnly
            ? max(1.0, boardW - kTonightPadX * 2)
            : queueW;
        final showQueue =
            queue.isNotEmpty &&
            visibleRows > 0 &&
            (queueOnly || effQueueW >= kTonightQueueMinW) &&
            effQueueW > 0;
        // A zone that isn't on screen must not be the one holding focus.
        if (!showQueue && rails.isNotEmpty) content.zoneIsQueue = false;
        // Never taller than the share it actually has: the row height is the
        // MIN of what looks right and what fits.
        final rowH = visibleRows == 0
            ? 0.0
            : min(
                max(
                  (mainH - (visibleRows - 1) * kTonightRowGap) / visibleRows,
                  rowMinH,
                ),
                kTonightRowMaxH,
              );
        final queueBoxH = visibleRows == 0
            ? 0.0
            : (rowH * visibleRows + kTonightRowGap * (visibleRows - 1)).clamp(
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
              left: kTonightPadX,
              right: kTonightPadX,
              top: 0,
              height: headerH,
              child: content.header(context, queue.length),
            ),
            // THE CARD — art, trailer and live all in this rect, so the punch
            // hole is exactly the card. Stood down in queue-only mode, where
            // the queue owns the board.
            if (!(queueOnly && showQueue))
              Positioned(
                left: kTonightPadX,
                top: headerH,
                width: cardW,
                height: cardH,
                child: content.bindings.buildCardLayers(cardH),
              ),
            // THE QUEUE.
            if (showQueue)
              Positioned(
                left: queueOnly
                    ? kTonightPadX
                    : kTonightPadX + cardW + kTonightZoneGap,
                top: headerH,
                width: effQueueW,
                height: max(rowH, queueBoxH),
                child: content.queueList(
                  queue,
                  rowH,
                  effQueueW,
                  rails.isNotEmpty,
                ),
              ),
            // THE RAIL.
            if (view != null)
              Positioned(
                left: kTonightPadX,
                right: 0,
                bottom: 0,
                child: content.rail(
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
