import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/home/home_row_registry.dart';
import '../../services/home_collection_rows.dart';
import '../../services/home_list_rows.dart';
import '../../services/home_row_order.dart';
import '../../utils/platform_util.dart';
import 'fav_row_ref.dart';
import 'catalog_search_controller.dart';
import 'continue_watching_controller.dart';
import 'fav_rows_controller.dart';
import 'home_board_controller.dart';

/// One Canvas rail — a Continue Watching row ([cw] non-null, with its
/// position among the CW rows in [cwIndex]), a favourites-family rail
/// ([favKind] non-null: IPTV / Debrify TV / Stremio TV / Playlist / an IPTV
/// custom-list row), or a catalog section ([sectionIndex] into
/// `_sections`/`_rowNodes`).
class CanvasRail {
  final CwRow? cw;
  final int cwIndex;
  final FavRowRef? favKind;
  final int? sectionIndex;
  final int traktSkeletonIndex;
  const CanvasRail({
    this.cw,
    this.cwIndex = -1,
    this.favKind,
    this.sectionIndex,
    this.traktSkeletonIndex = -1,
  });
}

/// Shared board navigation and paging state. The screen retains rendering,
/// hero effects and stage-specific completion; collaborators retain their own
/// lifetimes. No State/context is stored here. Fav types still belong to the
/// legacy host library until its public-type migration.
class SearchBoardRuntime {
  List<CatalogSection> sections = [];
  final List<List<FocusNode>> rowNodes = [];
  final Map<int, int> rowCol = {};
  bool boardLoadingMore = false;
  final ScrollController boardScroll = ScrollController();

  // Wired at the original collaborators' construction points; no eager reads.
  late HomeBoardController board;
  late CatalogSearchController catalogSearch;
  late FavRowsController favourites;
  late ContinueWatchingController cw;
  late bool Function() isLive;
  late void Function(VoidCallback) commit;
  late ({bool searchMode, bool discoverMode, bool isTraktAuthenticated})
  Function()
  environment;
  late Future<void> Function() refreshBoundSources;
  late VoidCallback leaveBoardTop;
  bool get mounted => isLive();

  List<CwRow> get cwRows => cw.buildRows(homeDisabled: board.homeDisabled);
  bool get cwVisible => cw.visible(
    homeDisabled: board.homeDisabled,
    catalogQuery: catalogSearch.query,
    catalogSearching: catalogSearch.searching,
  );
  bool get traktReserving => cw.traktReserving(
    searchMode: environment().searchMode,
    discoverMode: environment().discoverMode,
    isTraktAuthenticated: environment().isTraktAuthenticated,
    catalogQuery: catalogSearch.query,
    catalogSearching: catalogSearch.searching,
  );

  void disposeNodes() {
    for (final row in rowNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    rowNodes.clear();
    // Row indices now remap to different content — drop stale column memory.
    rowCol.clear();
  }

  void syncBoardRowNodes() {
    for (var i = 0; i < sections.length && i < rowNodes.length; i++) {
      final items = sections[i].items;
      final nodes = rowNodes[i];
      final base = nodes.length;
      for (var j = base; j < items.length; j++) {
        nodes.add(FocusNode(debugLabel: 'search_r${i}_c$j'));
      }
    }
  }

  void maybeAutoFillBoard() {
    if (!boardHasMore || boardLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !boardHasMore || boardLoadingMore) return;
      if (!boardScroll.hasClients) return;
      final pos = boardScroll.position;
      if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 600) {
        loadMoreBoard();
      }
    });
  }

  void onBoardScroll() {
    if (!boardHasMore || boardLoadingMore) return;
    if (!boardScroll.hasClients) return;
    final pos = boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      loadMoreBoard();
    }
  }

  Future<bool> loadMoreBoard() async {
    if (boardLoadingMore || board.boardCursor >= board.boardRefs.length) {
      return false;
    }
    // Bind this append to the load generation that owns the current cursor —
    // if a full reload lands mid-fetch, the stale batch must not append onto
    // (or advance) the fresh board.
    final gen = board.boardLoadGen;
    var appended = false;
    commit(() => boardLoadingMore = true);
    try {
      final more = await board.fetchBoardBatchUntilNonEmpty(gen);
      if (!mounted || gen != board.boardLoadGen) return false;
      if (more.isNotEmpty) {
        // Always keep the board cache growing so nothing is lost…
        board.homeSections = [...board.homeSections, ...more];
        // …but only fold into the live view when the board is still what's
        // shown. If a catalog search started while this batch was in flight,
        // `sections`/`rowNodes` now hold search results — appending board rows
        // there would corrupt the search view. They'll reappear on _restoreHome.
        if (catalogSearch.query.isEmpty && !catalogSearch.searching) {
          appendSections(more);
          appended = true;
          // A DPAD-down past the last row may be waiting on this batch —
          // classic's deferred move, and the stage layouts' rail advance.
          maybeCompleteDeferredDown();
          completeStageAdvance();
        }
      }
    } finally {
      if (mounted) commit(() => boardLoadingMore = false);
      maybeAutoFillBoard();
    }
    return appended;
  }

  void appendSections(List<CatalogSection> more) {
    for (final section in more) {
      rowNodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(debugLabel: 'search_r${rowNodes.length}_c$i'),
        ),
      );
    }
    commit(() => sections = [...sections, ...more]);
    unawaited(refreshBoundSources());
  }

  Future<void> loadMoreRow(int rowIndex) async {
    final result = await board.loadMoreRow(
      sections: sections,
      rowIndex: rowIndex,
      catalogSearchActive:
          catalogSearch.query.isNotEmpty || catalogSearch.searching,
      notifyLoadingGuard: !PlatformUtil.isAndroidTvCached,
    );
    if (!mounted || result.skipped || result.fresh.isEmpty) return;
    // A DPAD-right that ran off the end of this row may be waiting on it.
    completeStageRight();
    unawaited(refreshBoundSources());
  }

  bool focusRow(int row, int column) {
    if (row >= rowNodes.length) {
      // DPAD-down past the last loaded row on TV: pull the next board batch.
      if (boardHasMore) loadMoreBoard();
      return false;
    }
    if (row < 0) return false;
    final nodes = rowNodes[row];
    if (nodes.isEmpty) return false;
    // Land on the row's own remembered column, not the source column, so
    // returning to a row you'd scrolled right goes back where you left it (that
    // cell is still mounted). First visit falls back to the incoming column.
    final desired = (rowCol[row] ?? column).clamp(0, nodes.length - 1);
    requestRowFocus(nodes, desired);
    return true;
  }

  void requestRowFocus(List<FocusNode> nodes, int desired, {int hops = 0}) {
    // NB: FocusNode.context stays non-null after the owning Focus unmounts
    // (detach() doesn't clear it), so the element's own `mounted` flag — which
    // flips false on unmount — is the reliable "can this node take focus" test.
    bool isMounted(FocusNode n) => n.context?.mounted ?? false;
    if (isMounted(nodes[desired])) {
      nodes[desired].requestFocus();
      return;
    }
    for (var d = 1; d < nodes.length; d++) {
      final lo = desired - d;
      final hi = desired + d;
      if (lo >= 0 && isMounted(nodes[lo])) {
        nodes[lo].requestFocus();
        return;
      }
      if (hi < nodes.length && isMounted(nodes[hi])) {
        nodes[hi].requestFocus();
        return;
      }
    }
    // The whole row is unmounted: it sits beyond the board's deliberately
    // small vertical cacheExtent (300) — the live case is DPAD-down off the
    // last Continue Watching row while TWO Trakt skeleton rows (~380px of
    // focusless shimmer) separate it from the favourites/catalog row below.
    // requestFocus on a detached node would only latch a focus grab for
    // whenever that cell happens to build (a later yank, not a move — the old
    // "blocked DOWN"), so instead nudge the board forward and retry until the
    // row builds. Down-only on purpose: an unmounted target ABOVE can't
    // happen from row-by-row DPAD moves (the row above was just on screen,
    // still inside the cache). Bounded so the total travel stays within the
    // cache above the origin cell — it can't unmount mid-journey — and a
    // settled miss just leaves focus where it was.
    //
    // Glides (was jumpTo — a visible 45%-viewport teleport). The retry MUST
    // wait for the glide to land, not the next frame: per-frame retries would
    // spend all 3 hops inside one animation before the row could ever build.
    if (hops >= 3 || !boardScroll.hasClients) return;
    final pos = boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent) return;
    boardScroll
        .animateTo(
          (pos.pixels + pos.viewportDimension * 0.45).clamp(
            0.0,
            pos.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) requestRowFocus(nodes, desired, hops: hops + 1);
          });
        });
  }

  List<CanvasRail> get canonicalCanvasRails {
    final railsById = <String, CanvasRail>{};
    if (cwVisible) {
      final cwRows = this.cwRows;
      for (var i = 0; i < cwRows.length; i++) {
        if (cwRows[i].items.isEmpty) continue;
        railsById[cwRows[i].rowId] = CanvasRail(cw: cwRows[i], cwIndex: i);
      }
    }
    for (final ref in favourites.favRowKinds) {
      if (canvasFavItemCount(ref) == 0) continue;
      railsById[favourites.favRowId(ref)] = CanvasRail(favKind: ref);
    }
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].items.isEmpty || i >= rowNodes.length) continue;
      railsById[sectionRowId(sections[i])] = CanvasRail(sectionIndex: i);
    }
    final ordered = HomeRowRegistry.instance.canonicalBoardRailIds(
      visibleIds: railsById.keys,
    );
    return [
      for (final id in ordered)
        if (railsById[id] != null) railsById[id]!,
    ];
  }

  List<CanvasRail> get canvasRails {
    final rails = canonicalCanvasRails;
    return homeRowOrderActive
        ? HomeRowOrder.apply(rails, effectiveHomeRowOrder, canvasRailRowId)
        : rails;
  }

  List<CanvasRail> get classicHomeRails {
    var rails = canonicalCanvasRails;
    if (traktReserving) {
      final skeletons = <CanvasRail>[];
      if (!board.homeDisabled.contains('trakt:movies')) {
        skeletons.add(const CanvasRail(traktSkeletonIndex: 0));
      }
      // Merged Trakt renders one combined row, so reserve one slot, not two.
      if (!cw.cwMergeTrakt && !board.homeDisabled.contains('trakt:shows')) {
        skeletons.add(const CanvasRail(traktSkeletonIndex: 1));
      }
      // In the built-in order placeholders belong after the real CW block and
      // before favourites/sections. Build that canonical sequence first, then
      // let a saved order move the placeholders wherever the user requested.
      rails = HomeRowOrder.insertAfterLeadingRun(
        rails,
        skeletons,
        (rail) => rail.cw != null,
      );
    }
    return homeRowOrderActive
        ? HomeRowOrder.apply(rails, effectiveHomeRowOrder, canvasRailRowId)
        : rails;
  }

  String canvasRailRowId(CanvasRail rail) {
    if (rail.cw != null) return rail.cw!.rowId;
    if (rail.favKind != null) return favourites.favRowId(rail.favKind!);
    if (rail.traktSkeletonIndex >= 0) {
      return rail.traktSkeletonIndex == 0 ? 'trakt:movies' : 'trakt:shows';
    }
    return sectionRowId(sections[rail.sectionIndex!]);
  }

  List<FocusNode> canvasRailNodes(CanvasRail rail) {
    if (rail.cw != null) return rail.cw!.nodes;
    if (rail.favKind != null) return favourites.favNodesFor(rail.favKind!);
    return rowNodes[rail.sectionIndex!];
  }

  bool focusHomeRailAt(int index, int column) {
    final rails = canvasRails;
    if (index < 0 || index >= rails.length) return false;
    final nodes = canvasRailNodes(rails[index]);
    if (nodes.isEmpty) return false;
    requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  void focusRelativeHomeRail(String rowId, int delta, int column) {
    final rails = canvasRails;
    final current = rails.indexWhere((rail) => canvasRailRowId(rail) == rowId);
    if (current < 0) return;
    for (var i = current + delta; i >= 0 && i < rails.length; i += delta) {
      if (focusHomeRailAt(i, column)) return;
    }
    if (delta < 0) {
      leaveBoardTop();
      return;
    }
    if (boardHasMore) loadMoreBoard();
    deferDownMove(homeRowId: rowId, column: column);
  }

  String sectionRowId(CatalogSection section) => HomeRowRegistry.sectionRowId(
    listRowId: section is HomeListSection ? section.rowId : null,
    collectionRowId: section is HomeCollectionSection ? section.rowId : null,
    addonId: section.addon.id,
    catalogType: section.catalog.type,
    catalogId: section.catalog.id,
  );

  int canvasFavItemCount(FavRowRef ref) {
    if (ref.isIptvList) {
      return favourites.iptvListRows[ref.list].channels.length;
    }
    switch (ref.kind) {
      case FavKind.watchlistMovies:
        return favourites.watchlistMovieItems.length;
      case FavKind.watchlistSeries:
        return favourites.watchlistSeriesItems.length;
      case FavKind.iptv:
        return favourites.iptvFavChannels.length;
      case FavKind.debrify:
        return favourites.tvFavChannels.length;
      case FavKind.stremio:
        return favourites.stvFavChannels.length;
      case FavKind.playlist:
        return favourites.playlistItems.length;
    }
  }

  bool get homeRowOrderActive =>
      !environment().searchMode &&
      !environment().discoverMode &&
      catalogSearch.query.isEmpty &&
      !catalogSearch.searching;

  List<String> get effectiveHomeRowOrder => HomeRowOrder.insertMissingAfter(
    board.homeRowOrder,
    additions: const ['mdblist:movies', 'mdblist:shows'],
    anchors: const ['simkl:movies', 'simkl:shows'],
  );

  bool get boardHasMore =>
      catalogSearch.query.isEmpty &&
      !catalogSearch.searching &&
      board.boardCursor < board.boardRefs.length;

  // A DPAD-down pressed while everything below was still loading (Trakt row a
  // focusless skeleton, favourites absent, first catalog batch in flight) used
  // to be swallowed with focus frozen in place — the cell handler had already
  // reported the key handled. Instead the press is remembered briefly and
  // completed the moment a row below lands. Origin node is compared by
  // IDENTITY only (never dereferenced — it may be disposed by then): if focus
  // moved elsewhere meanwhile, the deferred move is dropped, so a late load
  // can never yank focus away from the user.
  FocusNode? pendingDownOrigin;
  int pendingDownRowIndex = -1; // set when pressed on a catalog row
  String? pendingDownHomeRowId; // stable id on the globally ordered Home
  int pendingDownCol = 0;
  DateTime? pendingDownAt;
  static const Duration pendingDownMaxAge = Duration(seconds: 3);

  void deferDownMove({
    int rowIndex = -1,
    String? homeRowId,
    required int column,
  }) {
    pendingDownOrigin = FocusManager.instance.primaryFocus;
    if (pendingDownOrigin == null) return;
    pendingDownRowIndex = rowIndex;
    pendingDownHomeRowId = homeRowId;
    pendingDownCol = column;
    pendingDownAt = DateTime.now();
  }

  void clearDeferredDown() {
    pendingDownOrigin = null;
    pendingDownAt = null;
    pendingDownHomeRowId = null;
  }

  /// Complete a recent deferred DPAD-down, called whenever a row load settles.
  /// Post-frame: the freshly-loaded row's cells only mount on the next build,
  /// and [requestRowFocus] needs mounted cells.
  void maybeCompleteDeferredDown() {
    if (pendingDownAt == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final at = pendingDownAt;
      final origin = pendingDownOrigin;
      if (at == null || origin == null) return;
      if (DateTime.now().difference(at) > pendingDownMaxAge) {
        clearDeferredDown();
        return;
      }
      if (!identical(FocusManager.instance.primaryFocus, origin)) {
        clearDeferredDown();
        return;
      }
      final col = pendingDownCol;
      final bool moved;
      final homeRowId = pendingDownHomeRowId;
      if (homeRowId != null) {
        final rowIds = [for (final rail in canvasRails) canvasRailRowId(rail)];
        final current = rowIds.indexWhere((id) => id == homeRowId);
        moved = current >= 0 && focusHomeRailAt(current + 1, col);
      } else if (pendingDownRowIndex >= 0) {
        moved = focusRow(pendingDownRowIndex + 1, col);
      } else {
        // From the last favourites row.
        moved = focusRow(0, col);
      }
      if (moved) clearDeferredDown();
    });
  }
  // Only a mounted Home stage can arm these requests. Discover executes the
  // same null-pending guards; it needs no fake stage renderer or no-op hook.
  String? pendingStageAdvanceKey;
  DateTime? pendingStageAdvanceAt;
  FocusNode? pendingStageOrigin;
  bool pendingStageAdvanceFillsLower = false;
  String? pendingStageRightKey;
  int pendingStageRightCol = -1;
  DateTime? pendingStageRightAt;
  FocusNode? pendingStageRightOrigin;
  late bool Function() stageActive;
  late String? Function() stageRailKey;
  late void Function(String key, int col, FocusNode? origin) continueStageRight;
  late void Function(String key, bool fillLower, FocusNode? origin) continueStageAdvance;

  void deferStageRight(String railKey, int col) {
    final origin = FocusManager.instance.primaryFocus;
    if (origin == null) return;
    pendingStageRightKey = railKey;
    pendingStageRightCol = col;
    pendingStageRightAt = DateTime.now();
    pendingStageRightOrigin = origin;
  }

  void deferStageAdvance(String railKey, {bool fillsLower = false}) {
    final origin = FocusManager.instance.primaryFocus;
    if (origin == null) return;
    pendingStageAdvanceKey = railKey;
    pendingStageAdvanceAt = DateTime.now();
    pendingStageAdvanceFillsLower = fillsLower;
    pendingStageOrigin = origin;
  }

  bool stageDeferralStillValid(DateTime at, FocusNode? origin) =>
      stageActive() &&
      origin != null &&
      identical(FocusManager.instance.primaryFocus, origin) &&
      DateTime.now().difference(at) <= SearchBoardRuntime.pendingDownMaxAge;

  void completeStageRight() {
    final key = pendingStageRightKey;
    final at = pendingStageRightAt;
    final col = pendingStageRightCol;
    final origin = pendingStageRightOrigin;
    if (key == null || at == null) return;
    pendingStageRightKey = null;
    pendingStageRightAt = null;
    pendingStageRightCol = -1;
    pendingStageRightOrigin = null;
    if (stageRailKey() != key) return;
    if (!stageDeferralStillValid(at, origin)) return;
    continueStageRight(key, col, origin);
  }

  void completeStageAdvance() {
    final key = pendingStageAdvanceKey;
    final at = pendingStageAdvanceAt;
    final fillLower = pendingStageAdvanceFillsLower;
    final origin = pendingStageOrigin;
    if (key == null || at == null) return;
    pendingStageAdvanceKey = null;
    pendingStageAdvanceAt = null;
    pendingStageAdvanceFillsLower = false;
    pendingStageOrigin = null;
    if (!stageDeferralStillValid(at, origin)) return;
    continueStageAdvance(key, fillLower, origin);
  }

}
