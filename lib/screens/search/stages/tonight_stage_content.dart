import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_theme_scope.dart';
import '../continue_watching_controller.dart';
import '../fav_row_ref.dart';
import '../search_board_runtime.dart';
import 'tonight_stage_widgets.dart';
import 'stage_shelf_content.dart';

/// Common-stage operations retained until the remaining G1'-8 callers migrate.
/// Neither State nor context is stored; closures preserve live host reads.
typedef TonightContentBindings = ({
  List<CanvasRail> Function() readStageRails,
  int Function(List<CanvasRail>) resolveRailIndex,
  FocusNode? Function(List<FocusNode>, int) nearestMountedNode,
  String Function(CanvasRail) railKeyOf,
  StageRailView? Function() resolveStageRail,
  VoidCallback seedFocusOnce,
  void Function(int) switchRail,
  bool Function(LogicalKeyboardKey) holdSwallow,
  void Function(LogicalKeyboardKey, bool Function()) holdJump,
  void Function(StremioMeta) setHero,
  bool Function(StremioMeta) isBound,
  Future<void> Function(CwRow, StremioMeta, int, int) openCwMenu,
  String? Function(StremioMeta) wideArtUrl,
  double Function(BuildContext) atriumLabelHeight,
  double Function(BuildContext, double, {required double maxH}) railBoxHeight,
  double Function(double) posterWidth,
  double Function(BuildContext, double) favouriteWidth,
  Widget Function(
    FavRowRef,
    String,
    int, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onUpHold,
  })
  buildFavCell,
  Widget Function(StageRailView) buildRailLabel,
  Widget Function(double) buildCardLayers,
  double labelGap,
});

/// Tonight's state and actual queue/rail assembly. Nodes and board data are
/// borrowed; the card notifier is owned here at its original eager lifetime.
class TonightStageContent {
  /// Tonight splits focus into two zones stacked vertically: the Continue
  /// Watching QUEUE (a vertical list) above, and the usual horizontal rail
  /// below. UP/DOWN walks the two as one column, so this is simply "which
  /// zone currently owns focus".
  bool zoneIsQueue = true;
  /// Remembered row within the queue — the INDEX is only a fallback. CW rows
  /// stream in and prepend (Trakt/Simkl land seconds after a cold start), so
  /// the identity below is what actually restores the user's place.
  int queueCol = 0;
  /// Identity of the remembered queue row: `<rail key>#<column>`. Resolved
  /// against the rebuilt queue every time, exactly like the shared rail key.
  String? queueKey;
  /// What the big card should say about whatever currently has focus — the
  /// OK hint in particular, which is 'Resume' only for a part-watched title
  /// and 'Play'/'Open' otherwise. A notifier, so a focus move repaints the
  /// caption alone rather than the board.
  final ValueNotifier<TonightCardInfo?> card = ValueNotifier(null);
  late SearchBoardRuntime board;
  late Map<String, int> columns;
  late TonightContentBindings bindings;
  late StageShelfContent shelf;

  void dispose() => card.dispose();

  /// The queue: every Continue Watching row flattened to (row, column) pairs
  /// in board order. Nodes come from the CW rows themselves — which is why
  /// the stage rail projection drops CW rails on Tonight (a node may be mounted once).
  List<TonightQueueEntry> get queue {
    final out = <TonightQueueEntry>[];
    if (!board.cwVisible) return out;
    for (final rail in board.canvasRails) {
      final cw = rail.cw;
      if (cw == null) continue;
      final n = min(cw.items.length, cw.nodes.length);
      for (var col = 0; col < n; col++) {
        out.add(TonightQueueEntry(rail: rail, col: col));
      }
    }
    return out;
  }

  String queueKeyOf(TonightQueueEntry e) =>
      '${bindings.railKeyOf(e.rail)}#${e.col}';

  /// Where the remembered queue row sits NOW. Identity first (CW rows stream
  /// in and prepend, so a raw index would silently point at another title),
  /// the remembered index only as a fallback.
  int resolveQueueIndex(List<TonightQueueEntry> queue) {
    if (queue.isEmpty) return 0;
    final key = queueKey;
    if (key != null) {
      final i = queue.indexWhere((e) => queueKeyOf(e) == key);
      if (i >= 0) return i;
    }
    return queueCol.clamp(0, queue.length - 1);
  }

  bool focusQueue() {
    final queue = this.queue;
    if (queue.isEmpty) return false;
    final e = queue[resolveQueueIndex(queue)];
    var node = bindings.nearestMountedNode(e.rail.cw!.nodes, e.col);
    // The remembered row may have scrolled out of the lazy list's mounted
    // range (CW rows stream in and prepend). Fall back to the FIRST queue
    // entry, which is always built, rather than failing the jump.
    if (node == null && queue.isNotEmpty) {
      final first = queue.first;
      node = bindings.nearestMountedNode(first.rail.cw!.nodes, first.col);
      if (node != null) {
        queueCol = 0;
        queueKey = queueKeyOf(first);
      }
    }
    if (node == null) return false;
    zoneIsQueue = true;
    node.requestFocus();
    return true;
  }

  bool focusRail() {
    final node = () {
      final rails = bindings.readStageRails();
      if (rails.isEmpty) return null;
      final rail = rails[bindings.resolveRailIndex(rails)];
      return bindings.nearestMountedNode(
        board.canvasRailNodes(rail),
        columns[bindings.railKeyOf(rail)] ?? 0,
      );
    }();
    if (node == null) return false;
    zoneIsQueue = false;
    node.requestFocus();
    return true;
  }

  /// A queue row's true minimum at the current text scale: title + episode +
  /// their gaps + the progress bar + the row's vertical padding.
  double rowMinHeight(BuildContext context) {
    final t = MediaQuery.textScalerOf(context);
    return t.scale(13.5) * 1.25 + 5 + t.scale(11.5) * 1.25 + 9 + 4 + 20 + 4;
  }

  double headerHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(kTonightTitleSize) * 1.35 +
      kTonightHeaderPad;

  Widget header(BuildContext context, int inProgress) {
    final app = AppThemeScope.of(context);
    final now = DateTime.now();
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    // A weekday word, not a clock: a minute-accurate label would need a timer
    // ticking on the home board for the whole session.
    final day = days[(now.weekday - 1).clamp(0, 6)];
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Tonight',
              style: TextStyle(
                color: app.core.tx,
                fontSize: kTonightTitleSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              day,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.40),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            const Spacer(),
            if (inProgress > 0)
              Text(
                '$inProgress IN PROGRESS',
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.40),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget queueList(
    List<TonightQueueEntry> queue,
    double rowH,
    double queueW,
    bool hasRail,
  ) {
    // The thumb is capped by the row's WIDTH, not just its height. Sized
    // purely as `rowH * 16/9` it ate two thirds of a narrow queue and left
    // the title about ten characters — "Orange Is t…". Whatever is left of
    // 16:9 after this cap, BoxFit.cover crops.
    final thumbW = min(rowH * 16 / 9, queueW * kTonightThumbShare);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ListView.builder(
            key: const ValueKey('tonight-queue'),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            itemCount: queue.length,
            itemExtent: rowH + kTonightRowGap,
            itemBuilder: (context, i) {
              final e = queue[i];
              final cw = e.rail.cw!;
              final item = cw.items[e.col];
              return Padding(
                padding: const EdgeInsets.only(bottom: kTonightRowGap),
                child: TonightQueueRow(
                  artUrlOf: bindings.wideArtUrl,
                  item: item,
                  height: rowH,
                  thumbWidth: thumbW,
                  focusNode: cw.nodes[e.col],
                  episode: cw.episodeOf(item),
                  progress: cw.progressOf(item),
                  hasBoundSource: bindings.isBound(item),
                  onFocused: () {
                    zoneIsQueue = true;
                    queueCol = i;
                    queueKey = queueKeyOf(e);
                    card.value = TonightCardInfo(
                      // OK opens the detail page for a Continue Watching card
                      // everywhere in the app; the HOLD menu is what resumes.
                      action: 'Open',
                      // HOLD opens the card menu (Play / Remove) — not a
                      // direct resume, so it is named for what it is.
                      holdAction: 'Options',
                      episode: cw.episodeOf(item),
                      progress: cw.progressOf(item),
                    );
                    bindings.setHero(item);
                  },
                  onOpen: () => cw.onOpen(item),
                  onLongPress: () =>
                      bindings.openCwMenu(cw, item, e.rail.cwIndex, e.col),
                  onUp: () {
                    if (bindings.holdSwallow(LogicalKeyboardKey.arrowUp)) {
                      return;
                    }
                    if (i > 0) {
                      bindings
                          .nearestMountedNode(
                            queue[i - 1].rail.cw!.nodes,
                            queue[i - 1].col,
                          )
                          ?.requestFocus();
                    }
                  },
                  onDown: () {
                    if (bindings.holdSwallow(LogicalKeyboardKey.arrowDown)) {
                      return;
                    }
                    if (i + 1 < queue.length) {
                      bindings
                          .nearestMountedNode(
                            queue[i + 1].rail.cw!.nodes,
                            queue[i + 1].col,
                          )
                          ?.requestFocus();
                    } else if (hasRail) {
                      focusRail();
                    }
                  },
                  // HELD down: leave the queue for the rail in one gesture.
                  // The queue is every Continue Watching item from every
                  // source flattened into one column, so stepping past it a
                  // row at a time can be a long walk.
                  onDownHold: hasRail
                      ? () => bindings.holdJump(
                          LogicalKeyboardKey.arrowDown,
                          focusRail,
                        )
                      : null,
                  onLeft: () => MainPageBridge.focusTvSidebar?.call(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget rail(StageRailView view, double boxH, {required bool queueAbove}) {
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail
        ? board.canvasFavItemCount(rail.favKind!)
        : items.length;
    // UP walks back through the rails and then into the queue — the two zones
    // are one vertical column.
    void up() {
      if (bindings.holdSwallow(LogicalKeyboardKey.arrowUp)) return;
      if (view.index > 0) {
        bindings.switchRail(-1);
      } else if (queueAbove) {
        focusQueue();
      }
    }

    void down() {
      if (bindings.holdSwallow(LogicalKeyboardKey.arrowDown)) return;
      bindings.switchRail(1);
    }

    // HELD up: back to the Continue queue from any rail, the mirror of the
    // queue's held DOWN.
    final upHold = queueAbove
        ? () => bindings.holdJump(LogicalKeyboardKey.arrowUp, focusQueue)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: kTonightPadX),
          child: bindings.buildRailLabel(view),
        ),
        SizedBox(height: bindings.labelGap),
        SizedBox(
          height: boxH,
          child: ListView.builder(
            key: ValueKey('tonight-rail-$railKey'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 400,
            itemCount: count,
            itemBuilder: (context, col) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Center(
                child: SizedBox(
                  width: favRail
                      ? bindings.favouriteWidth(context, boxH)
                      : bindings.posterWidth(boxH),
                  child: favRail
                      ? bindings.buildFavCell(
                          rail.favKind!,
                          railKey,
                          col,
                          onUp: up,
                          onDown: down,
                          onUpHold: upHold,
                        )
                      : SizedBox(
                          height: boxH,
                          child: shelf.cell(
                            rail,
                            railKey,
                            items,
                            nodes,
                            col,
                            onUp: up,
                            onDown: down,
                            onUpHold: upHold,
                            onFocusedExtra: () {
                              zoneIsQueue = false;
                              card.value = TonightCardInfo(
                                action: 'Open',
                                // Only Continue Watching cards arm hold-OK on
                                // TV (they are the ones with a menu); catalog
                                // cards have no hold action, so no hint.
                                holdAction: rail.cw != null ? 'Options' : null,
                                episode: rail.cw?.episodeOf(items[col]),
                                progress: rail.cw?.progressOf(items[col]),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: kTonightRailTail),
      ],
    );
  }
}
