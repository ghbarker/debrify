import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../screens/see_all/continue_watching_see_all_screen.dart';
import '../../screens/see_all/trakt_see_all_screen.dart';
import 'continue_watching_controller.dart';
import '../../services/storage_service.dart';
import '../../widgets/home/cw_card_menu.dart';
import '../../widgets/skeleton_poster.dart';

/// Per-source FocusNode lists for Continue Watching rails. Owned by the
/// row widget (G1'-4 seam); the controller syncs lengths through [sync].
class CwFocusOwner implements CwNodeBank {
  @override
  final List<FocusNode> movieNodes = [];
  @override
  final List<FocusNode> seriesNodes = [];
  @override
  final List<FocusNode> traktMovieNodes = [];
  @override
  final List<FocusNode> traktSeriesNodes = [];
  @override
  final List<FocusNode> simklMovieNodes = [];
  @override
  final List<FocusNode> simklSeriesNodes = [];
  @override
  final List<FocusNode> mdblistMovieNodes = [];
  @override
  final List<FocusNode> mdblistSeriesNodes = [];
  @override
  final List<FocusNode> iptvMovieNodes = [];
  @override
  final List<FocusNode> iptvSeriesNodes = [];

  void Function(List<FocusNode> nodes, int index)? onRequestRowFocus;

  @override
  void sync(List<FocusNode> nodes, int count, String tag) {
    syncCwNodes(
      nodes,
      count,
      tag,
      requestRowFocus: (n, i) => onRequestRowFocus?.call(n, i),
    );
  }

  @override
  void disposeAll() {
    for (final n in [
      ...movieNodes,
      ...seriesNodes,
      ...iptvMovieNodes,
      ...iptvSeriesNodes,
      ...traktMovieNodes,
      ...traktSeriesNodes,
      ...simklMovieNodes,
      ...simklSeriesNodes,
      ...mdblistMovieNodes,
      ...mdblistSeriesNodes,
    ]) {
      n.dispose();
    }
    movieNodes.clear();
    seriesNodes.clear();
    iptvMovieNodes.clear();
    iptvSeriesNodes.clear();
    traktMovieNodes.clear();
    traktSeriesNodes.clear();
    simklMovieNodes.clear();
    simklSeriesNodes.clear();
    mdblistMovieNodes.clear();
    mdblistSeriesNodes.clear();
  }
}

/// Resize a Continue Watching row's focus-node list to [count], preserving
/// the surviving prefix. This used to dispose-and-recreate ALL the row's
/// nodes on any length change — and these re-sync on every return from
/// playback/detail (the CW list almost always changes then), so it destroyed
/// the very node focus was sitting on: primary focus died with it and the
/// remote went dead until app relaunch. Now only a shrinking tail is
/// disposed, and if focus sat in that tail it's handed to the nearest
/// survivor.
void syncCwNodes(
  List<FocusNode> nodes,
  int count,
  String tag, {
  required void Function(List<FocusNode> nodes, int index) requestRowFocus,
}) {
  if (nodes.length == count) return;
  if (count < nodes.length) {
    var tailHadFocus = false;
    for (var i = count; i < nodes.length; i++) {
      if (nodes[i].hasFocus) {
        tailHadFocus = true;
        break;
      }
    }
    while (nodes.length > count) {
      nodes.removeLast().dispose();
    }
    // After the disposal so the dying node can't fight the handoff; a row
    // emptied to zero has no survivor — the dead-focus reclaim listener
    // picks that case up. Mounted-aware move: the last survivor's cell may
    // be virtualized out, and requestFocus on a detached node latches a
    // focus-when-reparented that would yank focus when it scrolls back in.
    if (tailHadFocus && count > 0) {
      requestRowFocus(nodes, count - 1);
    }
  } else {
    for (var i = nodes.length; i < count; i++) {
      nodes.add(FocusNode(debugLabel: 'search_cw_${tag}_$i'));
    }
  }
}

/// A leading Continue Watching row (local or Trakt) — same poster cards as the
/// catalog rows, plus a bottom progress bar and an optional type tag. Vertical
/// navigation resolves [homeRowId] against the live global order.
///
/// The host subscribes to CW changes and rebuilds this row with a fresh [row].
/// Keep notification ownership there: it also updates rail visibility, order,
/// and cross-row focus wiring. This widget does not subscribe independently.
///
/// Host cells pass `showWatchedBadge: false`: a Continue Watching progress bar
/// describes the active viewing session, and a global "watched once" check
/// from another tracker reads as contradictory here, especially during a
/// rewatch.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    super.key,
    required this.row,
    required this.cwIndex,
    required this.homeRowId,
    required this.isTelevision,
    required this.posterW,
    required this.cellH,
    required this.header,
    required this.cellBuilder,
  });

  final CwRow row;
  final int cwIndex;
  final String homeRowId;
  final bool isTelevision;
  final double posterW;
  final double cellH;
  final Widget header;
  final Widget Function(
    BuildContext context,
    int col,
    StremioMeta item,
    FocusNode node,
    List<FocusNode> nodes,
  )
  cellBuilder;

  @override
  Widget build(BuildContext context) {
    final rowH = cellH + 14;
    final items = row.items;
    final nodes = row.nodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: rowH,
          child: Builder(
            builder: (context) {
              // Rows start on the first poster (no leading See-All tile). DPAD-up
              // from the first CW row leaves the board; col-0 DPAD-left drops to
              // the sidebar (handled in _BoardCell when onLeftEdge is null).
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                cacheExtent: 400,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final col = index;
                  final item = items[col];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    child: Center(
                      child: SizedBox(
                        width: posterW,
                        height: cellH,
                        child: cellBuilder(
                          context,
                          col,
                          item,
                          nodes[col],
                          nodes,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A reserved-but-not-yet-loaded Trakt row: a header above a strip of static
/// poster placeholders that hold the Trakt slot open while its fetch runs.
/// Static — nothing animates while the CPU is busy loading (see [ShimmerBox]).
class TraktSkeletonRow extends StatelessWidget {
  final Widget header;
  final double posterW;
  final double cellH;
  final double rowH;

  const TraktSkeletonRow({
    super.key,
    required this.header,
    required this.posterW,
    required this.cellH,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: SizedBox(
                    width: posterW,
                    height: cellH,
                    child: const ShimmerBox(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Long-press (hold-OK on TV) on a Continue Watching card: Play, or take the
/// title off the row. Each row supplies its own removal (see [CwRow.onRemove])
/// because the four sources write to four different places.
/// When Home's Hold to Quick Play preference is on, the same gesture skips
/// this menu and invokes the row's Quick Play action directly.
///
/// [cwIndex]/[col] are the card's board coordinates, used to put TV focus back
/// on a live card once the row rebuilds without the removed one.
Future<void> openCwCardMenu({
  required BuildContext context,
  required CwRow row,
  required StremioMeta item,
  required int cwIndex,
  required int col,
  required bool isTelevision,
  required bool pikpakOnly,
  required bool Function() isMenuOpen,
  required void Function(bool open) setMenuOpen,
  required bool Function() isLive,
  required void Function(int cwIndex, int col) refocusAfterRemoval,
}) async {
  if (isMenuOpen()) return;
  setMenuOpen(true);
  final isSeries = item.type == 'series';
  final playActionAvailable = row.kind == CwKind.iptv || !pikpakOnly;
  final removeActionAvailable = row.canRemove?.call(item) ?? true;
  if (!playActionAvailable && !removeActionAvailable) {
    setMenuOpen(false);
    return;
  }
  // IPTV series use their primary action to open the series page; that is
  // still useful in the menu, but it is not the immediate playback this
  // preference promises.
  final quickPlayAvailable =
      playActionAvailable && !(row.kind == CwKind.iptv && isSeries);
  try {
    final holdToQuickPlay = await StorageService.getHomeCwHoldToQuickPlay();
    if (!isLive()) return;
    if (holdToQuickPlay && quickPlayAvailable) {
      row.onQuickPlay(item);
      return;
    }
  } catch (_) {
    // A preference read must never take the existing action menu away.
  } finally {
    // The dialog path takes ownership of this guard below. Direct Quick Play
    // and failed preference reads release it here.
    setMenuOpen(false);
  }
  if (!isLive() || !context.mounted) return;
  setMenuOpen(true);
  // An IPTV series card routes to its Xtream series page rather than playing
  // outright (see [_openIptvCwItem]) — so name the action for what it does.
  final playLabel = (row.kind == CwKind.iptv && isSeries)
      ? 'Open series'
      : 'Play';
  final String playDescription;
  final String removeDescription;
  switch (row.kind) {
    case CwKind.local:
      playDescription = isSeries
          ? 'Jump back into the episode you stopped on.'
          : 'Resume from where you left off.';
      removeDescription =
          'Takes it off this row and clears the position saved on this '
          'device.';
    case CwKind.trakt:
      playDescription = isSeries
          ? 'Jump back into the episode you stopped on.'
          : 'Resume from where you left off.';
      removeDescription =
          'Deletes this title\'s playback progress (and watch history) on '
          'Trakt, so it leaves the Trakt rows everywhere.';
    case CwKind.simkl:
      playDescription = isSeries
          ? 'Jump back into the episode you stopped on.'
          : 'Resume from where you left off.';
      removeDescription = isSeries
          ? 'Moves the show to On Hold on Simkl and clears the paused '
                'position, so it stops resurfacing as up next.'
          : 'Clears this movie\'s paused position on Simkl.';
    case CwKind.mdblist:
      playDescription = isSeries
          ? 'Jump into the paused or next unwatched episode from MDBList.'
          : 'Resume from the position saved on MDBList.';
      removeDescription = 'Clears this paused playback position from MDBList.';
    case CwKind.iptv:
      playDescription = isSeries
          ? 'Open the series and pick up where you left off.'
          : 'Resume from where you left off.';
      removeDescription = isSeries
          ? 'Clears every watched episode of this series from your IPTV '
                'history.'
          : 'Clears this item from your IPTV watch history and forgets its '
                'position.';
  }

  final episode = row.episodeOf(item);
  CwCardAction? action;
  try {
    action = await showCwCardMenu(
      context,
      title: item.name,
      isTelevision: isTelevision,
      posterUrl: item.poster,
      subtitle: [row.title, if (episode != null) episode].join('  ·  '),
      // Mirrors the card's own long-press-to-play gate: PikPak-only setups
      // have no quick play, so the menu offers the removal alone.
      showPlay: playActionAvailable,
      showRemove: removeActionAvailable,
      playLabel: playLabel,
      playDescription: playDescription,
      removeDescription: removeDescription,
    );
  } finally {
    setMenuOpen(false);
  }
  if (!isLive() || action == null) return;
  switch (action) {
    case CwCardAction.play:
      row.onQuickPlay(item);
    case CwCardAction.remove:
      await row.onRemove(item);
      if (!isLive()) return;
      refocusAfterRemoval(cwIndex, col);
  }
}

/// A tracker's Continue Watching rows just appeared on the board — if the
/// user is already browsing elsewhere, point them at the new rows with a
/// small toast, with the direction worked out from where DPAD focus currently
/// sits. [ownNodes] are the new rows themselves (focus already there → stay
/// quiet), [aboveNodes] / [belowNodes] the other Continue Watching rows they
/// slot between; favourites and catalog rows always render below.
void maybeAnnounceContinueWatchingRows({
  required String label,
  required bool visible,
  required bool isLive,
  required bool isTelevision,
  required bool searchMode,
  required bool discoverMode,
  required bool loading,
  required int? activeTvTabIndex,
  required int tabIndex,
  required bool routeIsCurrent,
  required List<List<FocusNode>> ownNodes,
  required List<List<FocusNode>> aboveNodes,
  required List<List<FocusNode>> belowNodes,
  required Iterable<List<FocusNode>> favNodeLists,
  required List<List<FocusNode>> catalogRowNodes,
  required void Function(String msg) showSnack,
}) {
  if (!isLive || !isTelevision) return;
  if (searchMode || discoverMode) return;
  // Still on the brand loading stage: the rows will simply be there when the
  // board first paints — nothing to announce.
  if (loading) return;
  // Only the board the user is actually looking at announces (not one
  // reloading under a detail page/player or on an inactive tab).
  if (activeTvTabIndex != tabIndex) return;
  if (!routeIsCurrent) return;
  // Rows hidden by the Home Rows manager never reached the screen.
  if (!visible) return;
  final primary = FocusManager.instance.primaryFocus;
  bool onRow(List<FocusNode> nodes) =>
      primary != null && nodes.contains(primary);
  bool onAny(List<List<FocusNode>> rows) => rows.any(onRow);
  if (onAny(ownNodes)) return; // already looking at them
  String? dir;
  if (onAny(aboveNodes)) {
    dir = 'down';
  } else if (onAny(belowNodes)) {
    dir = 'up';
  } else {
    for (final nodes in favNodeLists) {
      if (onRow(nodes)) {
        dir = 'up';
        break;
      }
    }
    if (dir == null) {
      for (final row in catalogRowNodes) {
        if (onRow(row)) {
          dir = 'up';
          break;
        }
      }
    }
  }
  final msg = dir == null
      ? '$label Continue Watching loaded'
      : '$label loaded — scroll $dir to view';
  showSnack(msg);
}

void pushContinueWatchingSeeAll({
  required BuildContext context,
  required Widget Function(Widget child) wrap,
  required String title,
  required String initialCategory,
  required List<StremioMeta> items,
  required double? Function(StremioMeta) progressOf,
  required void Function(StremioMeta) onOpen,
  required void Function(StremioMeta)? onQuickPlay,
  required Future<List<StremioMeta>> Function()? onReload,
  VoidCallback? onReturn,
  required bool Function(StremioMeta) isBound,
  required bool isTelevision,
}) {
  Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => wrap(
            ContinueWatchingSeeAllScreen(
              title: title,
              initialCategory: initialCategory,
              items: List<StremioMeta>.of(items),
              progressOf: progressOf,
              onOpen: onOpen,
              onQuickPlay: onQuickPlay,
              onReload: onReload,
              // CW items are all rail-loaded, so _boundCounts covers them.
              isBound: isBound,
              isTelevision: isTelevision,
            ),
          ),
        ),
      )
      .then((_) => onReturn?.call());
}

void pushTraktContinueWatchingSeeAll({
  required BuildContext context,
  required Widget Function(Widget child) wrap,
  required String initialCategory,
  required List<StremioMeta> cwItems,
  required Map<String, double> cwProgress,
  required void Function(StremioMeta) onOpen,
  required void Function(StremioMeta)? onQuickPlay,
  required bool Function(StremioMeta) isBound,
  required bool isTelevision,
  required VoidCallback onReturn,
}) {
  Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => wrap(
            TraktSeeAllScreen(
              initialCategory: initialCategory,
              cwItems: List<StremioMeta>.of(cwItems),
              // Pass the live progress map (read-only in the screen) so resume
              // bars reflect any refresh while the screen is open, matching the
              // old live-closure behaviour; items stay a snapshot so the grid
              // doesn't shift under the user.
              cwProgress: cwProgress,
              onOpen: onOpen,
              onQuickPlay: onQuickPlay,
              // CW items are all rail-loaded, so _boundCounts covers them.
              isBound: isBound,
              isTelevision: isTelevision,
            ),
          ),
        ),
      )
      .then((_) => onReturn());
}

/// See-all + announce flows that need Navigator / snack / DPAD context.
class ContinueWatchingFlows {
  ContinueWatchingFlows({
    required this.controller,
    required this.contextOf,
    required this.wrap,
    required this.isBound,
    required this.isTelevision,
    required this.pikpakOnly,
    required this.isLive,
    required this.searchMode,
    required this.discoverMode,
    required this.loading,
    required this.activeTvTabIndex,
    required this.tabIndex,
    required this.routeIsCurrent,
    required this.homeDisabled,
    required this.favNodeLists,
    required this.catalogRowNodes,
    required this.showSnack,
    required this.onAfterSeeAllReturn,
    required this.refreshAfterPlayback,
  });

  final ContinueWatchingController controller;
  final BuildContext Function() contextOf;
  final Widget Function(Widget child) wrap;
  final bool Function(StremioMeta) isBound;
  final bool Function() isTelevision;
  final bool Function() pikpakOnly;
  final bool Function() isLive;
  final bool Function() searchMode;
  final bool Function() discoverMode;
  final bool Function() loading;
  final int? Function() activeTvTabIndex;
  final int Function() tabIndex;
  final bool Function() routeIsCurrent;
  final Set<String> Function() homeDisabled;
  final Iterable<List<FocusNode>> Function() favNodeLists;
  final List<List<FocusNode>> Function() catalogRowNodes;
  final void Function(String msg) showSnack;
  final Future<void> Function() onAfterSeeAllReturn;
  final Future<void> Function({bool trackers}) refreshAfterPlayback;

  void openLocalSeeAll([String initialCategory = 'all']) {
    pushContinueWatchingSeeAll(
      context: contextOf(),
      wrap: wrap,
      title: 'Continue Watching',
      initialCategory: initialCategory,
      items: controller.cwAll,
      progressOf: (m) => controller.cwCardProgress(CwKind.local, m),
      onOpen: controller.openLocal,
      onQuickPlay: pikpakOnly() ? null : controller.playLocal,
      onReload: () async {
        await onAfterSeeAllReturn();
        return List<StremioMeta>.of(controller.cwAll);
      },
      isBound: isBound,
      isTelevision: isTelevision(),
    );
  }

  void openTraktSeeAll([String initialCategory = 'all']) {
    pushTraktContinueWatchingSeeAll(
      context: contextOf(),
      wrap: wrap,
      initialCategory: initialCategory,
      cwItems: controller.traktAll,
      cwProgress: controller.cwCardMaps(CwKind.trakt).progress,
      onOpen: controller.openTrakt,
      onQuickPlay: pikpakOnly() ? null : controller.playTrakt,
      isBound: isBound,
      isTelevision: isTelevision(),
      onReturn: () => refreshAfterPlayback(trackers: true),
    );
  }

  void openSimklSeeAll([String initialCategory = 'all']) {
    pushContinueWatchingSeeAll(
      context: contextOf(),
      wrap: wrap,
      title: 'Simkl Continue Watching',
      initialCategory: initialCategory,
      items: controller.simklAll,
      progressOf: (m) => controller.cwCardProgress(CwKind.simkl, m),
      onOpen: controller.openSimkl,
      onQuickPlay: pikpakOnly() ? null : controller.playSimkl,
      onReload: () async {
        await refreshAfterPlayback(trackers: true);
        return List<StremioMeta>.of(controller.simklAll);
      },
      isBound: isBound,
      isTelevision: isTelevision(),
    );
  }

  void openMdblistSeeAll([String initialCategory = 'all']) {
    pushContinueWatchingSeeAll(
      context: contextOf(),
      wrap: wrap,
      title: 'MDBList Continue Watching',
      initialCategory: initialCategory,
      items: controller.mdblistAll,
      progressOf: (m) => controller.cwCardProgress(CwKind.mdblist, m),
      onOpen: controller.openMdblist,
      onQuickPlay: pikpakOnly() ? null : controller.playMdblist,
      onReload: () async {
        await controller.loadMdblistContinueWatching();
        return List<StremioMeta>.of(controller.mdblistAll);
      },
      isBound: isBound,
      isTelevision: isTelevision(),
    );
  }

  void announceTrakt() => _announce(
    'Trakt',
    controller.traktRowsVisible(homeDisabled()),
    ownNodes: [
      controller.nodes.traktMovieNodes,
      controller.nodes.traktSeriesNodes,
    ],
    aboveNodes: [controller.nodes.movieNodes, controller.nodes.seriesNodes],
    belowNodes: [
      controller.nodes.simklMovieNodes,
      controller.nodes.simklSeriesNodes,
      controller.nodes.mdblistMovieNodes,
      controller.nodes.mdblistSeriesNodes,
      controller.nodes.iptvMovieNodes,
      controller.nodes.iptvSeriesNodes,
    ],
  );

  void announceSimkl() => _announce(
    'Simkl',
    controller.simklRowsVisible(homeDisabled()),
    ownNodes: [
      controller.nodes.simklMovieNodes,
      controller.nodes.simklSeriesNodes,
    ],
    aboveNodes: [
      controller.nodes.movieNodes,
      controller.nodes.seriesNodes,
      controller.nodes.traktMovieNodes,
      controller.nodes.traktSeriesNodes,
    ],
    belowNodes: [
      controller.nodes.mdblistMovieNodes,
      controller.nodes.mdblistSeriesNodes,
      controller.nodes.iptvMovieNodes,
      controller.nodes.iptvSeriesNodes,
    ],
  );

  void announceMdblist() => _announce(
    'MDBList',
    controller.mdblistRowsVisible(homeDisabled()),
    ownNodes: [
      controller.nodes.mdblistMovieNodes,
      controller.nodes.mdblistSeriesNodes,
    ],
    aboveNodes: [
      controller.nodes.movieNodes,
      controller.nodes.seriesNodes,
      controller.nodes.traktMovieNodes,
      controller.nodes.traktSeriesNodes,
      controller.nodes.simklMovieNodes,
      controller.nodes.simklSeriesNodes,
    ],
    belowNodes: [
      controller.nodes.iptvMovieNodes,
      controller.nodes.iptvSeriesNodes,
    ],
  );

  void _announce(
    String label,
    bool visible, {
    required List<List<FocusNode>> ownNodes,
    required List<List<FocusNode>> aboveNodes,
    required List<List<FocusNode>> belowNodes,
  }) {
    maybeAnnounceContinueWatchingRows(
      label: label,
      visible: visible,
      isLive: isLive(),
      isTelevision: isTelevision(),
      searchMode: searchMode(),
      discoverMode: discoverMode(),
      loading: loading(),
      activeTvTabIndex: activeTvTabIndex(),
      tabIndex: tabIndex(),
      routeIsCurrent: routeIsCurrent(),
      ownNodes: ownNodes,
      aboveNodes: aboveNodes,
      belowNodes: belowNodes,
      favNodeLists: favNodeLists(),
      catalogRowNodes: catalogRowNodes(),
      showSnack: showSnack,
    );
  }
}
