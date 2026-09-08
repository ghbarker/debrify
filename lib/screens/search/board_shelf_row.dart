import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../models/stremio_addon.dart';
import 'board_cell.dart';

/// One horizontal row of Home board cards — the exact same [BoardCell]
/// widget (poster art, [CardFocusRise] scale/shadow/focus-ring, hover-grow,
/// title-less card grammar) and row gutter (13px outer, 11px per card) Home's
/// own catalog rails paint, packaged as a standalone widget for a screen
/// outside the board that wants to read as an actual Home row rather than
/// approximate one — currently the collection folder screen's rails.
///
/// Deliberately just the row: it owns its own per-item [FocusNode] pool
/// (grown/shrunk to match [items], the same bookkeeping
/// `SeeAllPosterGridState` does for the Discover grid) so a host doesn't have
/// to manage per-rail node lists, but every other piece of state — the item
/// list itself, pagination — stays with the host, same as
/// [BoardCell]/Home's board. A host lands DPAD focus on the row from outside
/// (e.g. a rail header's DPAD-down) through [BoardShelfRowState.focusFirst].
class BoardShelfRow extends StatefulWidget {
  const BoardShelfRow({
    super.key,
    required this.items,
    required this.isTelevision,
    required this.posterW,
    required this.cellH,
    required this.onOpen,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.loadingMore = false,
    this.onLoadMore,
    this.onExitTop,
    this.onExitBottom,
  });

  final List<StremioMeta> items;
  final bool isTelevision;

  /// Poster width/height — 2:3, matching [BoardCell]'s default card shape.
  final double posterW;
  final double cellH;

  final void Function(StremioMeta item) onOpen;
  final void Function(StremioMeta item)? onQuickPlay;
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;

  /// Trailing paging spinner, matching Home's own catalog row.
  final bool loadingMore;

  /// Fetch the next page — called both near the row's right edge (scroll
  /// threshold, matching Home's [_kRowLoadMoreThreshold]) and as DPAD focus
  /// nears the last few cards (matching [BoardCell.onNearEnd]).
  final VoidCallback? onLoadMore;

  /// DPAD-up from any card leaves the row (e.g. to the rail's own header).
  final VoidCallback? onExitTop;

  /// DPAD-down from any card leaves the row (e.g. to the next rail's
  /// header). Null swallows it, matching a Home row with nothing below.
  final VoidCallback? onExitBottom;

  @override
  State<BoardShelfRow> createState() => BoardShelfRowState();
}

/// Distance from the row's right edge (px) at which the next page is
/// prefetched — Home's own catalog-row threshold (search_screen.dart's
/// `_kRowLoadMoreThreshold`), so a collection rail paginates on the same
/// runway a Home row does.
const double _kBoardShelfLoadMoreThreshold = 900;

class BoardShelfRowState extends State<BoardShelfRow> {
  final List<FocusNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant BoardShelfRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != _nodes.length) _syncNodes();
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _syncNodes() {
    while (_nodes.length < widget.items.length) {
      _nodes.add(FocusNode(debugLabel: 'board_shelf_row_${_nodes.length}'));
    }
    if (_nodes.length > widget.items.length) {
      final keep = widget.items.length;
      // Hand focus to the last survivor before disposing the shrinking tail,
      // same reasoning as SeeAllPosterGridState._syncNodes — never leave
      // DPAD focus sitting on a node about to be torn down.
      final focusedHidden = _nodes.skip(keep).any((n) => n.hasFocus);
      if (focusedHidden && keep > 0) {
        _nodes[keep - 1].requestFocus();
      }
      while (_nodes.length > keep) {
        _nodes.removeLast().dispose();
      }
    }
  }

  /// Land DPAD focus on the row's first card — a Home row is always entered
  /// from its header, so there is no "remembered column" to restore here.
  /// No-op with nothing to focus.
  void focusFirst() {
    if (_nodes.isEmpty) return;
    _nodes.first.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final rowH = widget.cellH + 14;
    return SizedBox(
      height: rowH,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (widget.onLoadMore != null &&
              n.metrics.axis == Axis.horizontal &&
              n.metrics.pixels >=
                  n.metrics.maxScrollExtent - _kBoardShelfLoadMoreThreshold) {
            widget.onLoadMore!();
          }
          return false;
        },
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          scrollCacheExtent: const ScrollCacheExtent.pixels(400),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          itemCount: items.length + (widget.loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            final col = index;
            if (col >= items.length) {
              return SizedBox(
                width: 52,
                height: widget.cellH,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final item = items[col];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                child: SizedBox(
                  width: widget.posterW,
                  height: widget.cellH,
                  child: BoardCell(
                    item: item,
                    isTelevision: widget.isTelevision,
                    focusNode: _nodes[col],
                    column: col,
                    rowNodes: _nodes,
                    hasBoundSource: widget.isBound?.call(item) ?? false,
                    onQuickPlay: widget.onQuickPlay == null
                        ? null
                        : () => widget.onQuickPlay!(item),
                    onFocused: () => widget.onItemFocused?.call(item),
                    onUp: () => widget.onExitTop?.call(),
                    onDown: () => widget.onExitBottom?.call(),
                    onOpen: () => widget.onOpen(item),
                    onNearEnd: widget.onLoadMore,
                    // This row has no sidebar to hand off to at column 0
                    // (unlike the Home board) — swallow LEFT there instead of
                    // BoardCell's default of reaching for one.
                    onLeft: col == 0 ? () {} : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
