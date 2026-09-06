import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/stremio_tv_prefs.dart';
import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/debrify_tv/channel.dart';
import '../../models/iptv_playlist.dart';
import '../../models/playlist_view_mode.dart';
import '../../models/stremio_addon.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/home/home_row_ids.dart';
import '../../services/home/my_watchlist_loader.dart';
import '../../services/iptv_media_store.dart';
import '../../services/main_page_bridge.dart';
import '../../services/playlist_player_service.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/video_player_launcher.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/debrid_action_sheet.dart';
import '../iptv/xtream_series_detail.dart';
import '../playlist_content_view_screen.dart';
import '../stremio_tv/stremio_tv_service.dart';
import 'fav_row_ref.dart';

/// Screen-owned favourites state and flows. UI/focus dependencies are explicit;
/// the host supplies its live State boundary and cross-row navigation.
class FavRowsController {
  FavRowsController({
    required this.readContext,
    required this.isLive,
    required this.readIsTelevision,
    required this.commit,
    required this.addonForContinue,
    required this.readCatalogQuery,
    required this.readCatalogSearching,
    required this.focusContent,
    required this.focusRelativeHomeRail,
    required this.readHomeDisabled,
    required this.maybeAutoFocusBoard,
    required this.openItem,
    required this.refreshAfterPlayback,
    required this.requestRowFocus,
  });

  final BuildContext Function() readContext;
  final bool Function() isLive;
  final bool Function() readIsTelevision;
  final void Function(VoidCallback) commit;
  final StremioAddon Function(String?) addonForContinue;
  final String Function() readCatalogQuery;
  final bool Function() readCatalogSearching;
  final VoidCallback focusContent;
  final void Function(String, int, int) focusRelativeHomeRail;
  final Set<String> Function() readHomeDisabled;
  final VoidCallback maybeAutoFocusBoard;
  final void Function(StremioMeta, StremioAddon) openItem;
  final Future<void> Function() refreshAfterPlayback;
  final void Function(List<FocusNode>, int) requestRowFocus;
  bool get mounted => isLive();
  bool get isTelevision => readIsTelevision();

  // Debrify TV favourites — a leading "Debrify TV" row of the user's starred
  // keyword channels, shown between Continue Watching and the catalog rows.
  // Channels have no artwork, so they render as Stremio-shaped cards with a
  // gradient + glyph placeholder (see [ArtPoster]).
  List<DebrifyTvChannel> tvFavChannels = [];
  final List<FocusNode> tvFavNodes = [];

  // Stremio TV favourites — a leading row of the user's starred Stremio
  // "channels" (catalogs treated as TV channels). Each card shows the channel's
  // current now-playing item poster (same time-based rotation as the Home /
  // Stremio TV screens); tapping opens the channel. Loaded once on init.
  List<StremioTvChannel> stvFavChannels = [];
  final List<FocusNode> stvFavNodes = [];
  int stvRotationMinutes = 90;
  int stvSeriesRotationMinutes = 45;

  // IPTV favourites — a leading row of the user's starred live IPTV channels.
  // Cards show the channel logo (glyph fallback); tapping plays the stream
  // directly via VideoPlayerLauncher (no tab switch). Reloaded whenever list
  // membership or manual order changes.
  List<IptvChannel> iptvFavChannels = [];
  final List<FocusNode> iptvFavNodes = [];

  // Debrify's account-independent movie/series watchlist. Full metadata is
  // stored locally and presented as separate movie and series rows, so neither
  // row needs a tracker or catalog network request.
  List<StremioMeta> watchlistMovieItems = [];
  List<StremioMeta> watchlistSeriesItems = [];
  final List<FocusNode> watchlistMovieNodes = [];
  final List<FocusNode> watchlistSeriesNodes = [];

  // Opted-in IPTV custom lists as Home rows (`iptvlist:` extras), rendered
  // through the favourites-row family after the IPTV favourites row. Rebuilt
  // by [loadIptvListRows] on init, on Home Rows saves, and whenever
  // [IptvMediaStore.listsRevision] bumps (any list mutation anywhere in the
  // app). Rows own their FocusNodes, reconciled by list id across reloads.
  List<FavouritesIptvListRow> iptvListRows = [];
  int iptvListRowsLoadToken = 0;

  // Playlist favourites — a leading row of the user's saved playlist items
  // (movies / collections added from search or cloud). Cards show the item
  // poster with resume progress; tapping opens a full action menu (play / play
  // random / view files / favorite / clear progress / launch-on-startup /
  // delete), so this row is a complete playlist manager on its own now that the
  // Home playlist section is being phased out. Loaded once on init.
  List<Map<String, dynamic>> playlistItems = [];
  final List<FocusNode> playlistFavNodes = [];
  Map<String, Map<String, dynamic>> playlistProgress = {};
  Set<String> playlistFavKeys = {};
  // Guards against launching a second concurrent playback while the first is
  // still resolving links (the menu closes immediately, giving no other cue).
  bool playlistLaunching = false;

  bool get iptvFavVisible =>
      iptvFavChannels.isNotEmpty &&
      !readHomeDisabled().contains('fav:iptv') &&
      readCatalogQuery().isEmpty &&
      !readCatalogSearching();
  bool get tvFavVisible =>
      tvFavChannels.isNotEmpty &&
      !readHomeDisabled().contains('fav:debrify') &&
      readCatalogQuery().isEmpty &&
      !readCatalogSearching();
  bool get stvFavVisible =>
      stvFavChannels.isNotEmpty &&
      !readHomeDisabled().contains('fav:stremio') &&
      readCatalogQuery().isEmpty &&
      !readCatalogSearching();
  bool get playlistFavVisible =>
      playlistItems.isNotEmpty &&
      !readHomeDisabled().contains('fav:playlist') &&
      readCatalogQuery().isEmpty &&
      !readCatalogSearching();
  bool get watchlistMoviesVisible =>
      watchlistMovieItems.isNotEmpty &&
      !readHomeDisabled().contains('watchlist:movies') &&
      readCatalogQuery().isEmpty &&
      !readCatalogSearching();
  bool get watchlistSeriesVisible =>
      watchlistSeriesItems.isNotEmpty &&
      !readHomeDisabled().contains('watchlist:series') &&
      readCatalogQuery().isEmpty &&
      !readCatalogSearching();

  /// The visible saved-content rows in render order: Watchlist Movies,
  /// Watchlist Series, Playlist, Debrify TV, Stremio TV, IPTV favourites, then
  /// opted-in IPTV custom lists.
  /// This is the single source of truth for both rendering ([_buildBoard]) and
  /// the index-based DPAD focus wiring below, so the two never drift out of
  /// sync. IPTV list rows share the favourites gates (board only, non-empty)
  /// and are opt-in by construction — [iptvListRows] only ever holds enabled
  /// lists.
  // Reach-sweep rule: a feature that's off drops its Home rows too, not
  // just its tab — the profile should never see a shelf it can't open.
  List<FavRowRef> get favRowKinds => [
    if (watchlistMoviesVisible) const FavRowRef(FavKind.watchlistMovies),
    if (watchlistSeriesVisible) const FavRowRef(FavKind.watchlistSeries),
    if (playlistFavVisible) const FavRowRef(FavKind.playlist),
    if (tvFavVisible && ProfilePolicyGuard.allowsSync(ProfileFeature.debrifyTv))
      const FavRowRef(FavKind.debrify),
    if (stvFavVisible &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.stremioTv))
      const FavRowRef(FavKind.stremio),
    if (iptvFavVisible && ProfilePolicyGuard.allowsSync(ProfileFeature.iptv))
      const FavRowRef(FavKind.iptv),
    if (readCatalogQuery().isEmpty &&
        !readCatalogSearching() &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.iptv))
      for (var i = 0; i < iptvListRows.length; i++)
        if (iptvListRows[i].channels.isNotEmpty) FavRowRef(FavKind.iptv, i),
  ];

  int get favRowCount => favRowKinds.length;
  bool get anyFavVisible => favRowKinds.isNotEmpty;

  String favRowId(FavRowRef ref) {
    if (ref.isIptvList) {
      return HomeExtraRowIds.iptvList(iptvListRows[ref.list].listId);
    }
    return switch (ref.kind) {
      FavKind.watchlistMovies => 'watchlist:movies',
      FavKind.watchlistSeries => 'watchlist:series',
      FavKind.playlist => 'fav:playlist',
      FavKind.debrify => 'fav:debrify',
      FavKind.stremio => 'fav:stremio',
      FavKind.iptv => 'fav:iptv',
    };
  }

  /// The focus-node list backing a favourites row of the given [ref].
  List<FocusNode> favNodesFor(FavRowRef ref) {
    if (ref.isIptvList) return iptvListRows[ref.list].nodes;
    switch (ref.kind) {
      case FavKind.watchlistMovies:
        return watchlistMovieNodes;
      case FavKind.watchlistSeries:
        return watchlistSeriesNodes;
      case FavKind.iptv:
        return iptvFavNodes;
      case FavKind.debrify:
        return tvFavNodes;
      case FavKind.stremio:
        return stvFavNodes;
      case FavKind.playlist:
        return playlistFavNodes;
    }
  }

  /// Focus a card in the favourites row at [favIndex] (index into the visible
  /// favourites rows), clamping the column to that row's length. Returns false
  /// when no such row is focusable (same contract as [_focusCwRow]).
  bool focusFavRowAt(int favIndex, int column) {
    final kinds = favRowKinds;
    if (favIndex < 0 || favIndex >= kinds.length) return false;
    final nodes = favNodesFor(kinds[favIndex]);
    if (nodes.isEmpty) return false;
    requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  VoidCallback favRowOnUp(String rowId, int column) =>
      () => focusRelativeHomeRail(rowId, -1, column);

  VoidCallback favRowOnDown(String rowId, int column) =>
      () => focusRelativeHomeRail(rowId, 1, column);

  /// Load the user's starred Debrify TV channels for the leading favourites row.
  /// Silently leaves the row empty on any error (it just won't render).
  Future<void> loadTvFavorites() async {
    try {
      final ids = await DebrifyTvPrefs.getDebrifyTvFavoriteChannelIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        commit(() => tvFavChannels = const []);
        syncTvFavNodes();
        return;
      }
      final records = await DebrifyTvRepository.instance.fetchAllChannels();
      // fetchAllChannels() is already ordered by channel number; preserve that
      // order (matching the Home row) rather than a redundant, non-stable
      // re-sort that could shuffle channels sharing channelNumber 0.
      final favs = records
          .map(DebrifyTvChannel.fromRecord)
          .where((c) => ids.contains(c.id))
          .toList();
      if (!mounted) return;
      commit(() => tvFavChannels = favs);
      syncTvFavNodes();
      maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  /// Grow/shrink the favourites row's focus nodes to match the channel count.
  void syncTvFavNodes() {
    while (tvFavNodes.length < tvFavChannels.length) {
      tvFavNodes.add(
        FocusNode(debugLabel: 'search_tvfav_${tvFavNodes.length}'),
      );
    }
    while (tvFavNodes.length > tvFavChannels.length) {
      tvFavNodes.removeLast().dispose();
    }
  }

  /// Launch a Debrify TV channel (same path the Home screen uses): hand off to
  /// the live player if it's mounted, else queue an auto-play and switch tabs.
  void playChannel(DebrifyTvChannel channel) {
    if (MainPageBridge.watchDebrifyTvChannel != null) {
      MainPageBridge.watchDebrifyTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(MainTab.debrifyTv);
  }

  /// Load the user's starred Stremio TV channels for the leading favourites row.
  /// Mirrors the Home section: discover all channels, keep the favourited ones
  /// (preserving discovery order), then fetch their items so each card can show
  /// a now-playing poster. Silently leaves the row empty on any error.
  Future<void> loadStremioTvFavorites() async {
    try {
      final ids = await StremioTvPrefs.getStremioTvFavoriteChannelIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        commit(() => stvFavChannels = const []);
        syncStvFavNodes();
        return;
      }
      final rotations = await Future.wait([
        StremioTvPrefs.getStremioTvRotationMinutes(),
        StremioTvPrefs.getStremioTvSeriesRotationMinutes(),
      ]);
      final rotation = rotations[0];
      final seriesRotation = rotations[1];
      final all = await StremioTvService.instance.discoverChannels();
      final favs = all.where((c) => ids.contains(c.id)).toList();
      await StremioTvService.instance.loadAllChannelItems(favs);
      if (!mounted) return;
      commit(() {
        stvRotationMinutes = rotation;
        stvSeriesRotationMinutes = seriesRotation;
        stvFavChannels = favs;
      });
      syncStvFavNodes();
      maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  void syncStvFavNodes() {
    while (stvFavNodes.length < stvFavChannels.length) {
      stvFavNodes.add(
        FocusNode(debugLabel: 'search_stvfav_${stvFavNodes.length}'),
      );
    }
    while (stvFavNodes.length > stvFavChannels.length) {
      stvFavNodes.removeLast().dispose();
    }
  }

  /// First of [a], [b] that is a non-empty string, else null.
  String? firstNonEmpty(String? a, String? b) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  /// The now-playing item for a Stremio TV channel, using the same time-based
  /// rotation as the Home / Stremio TV screens (series rotate on their own
  /// cadence). Null when the channel has no loaded items.
  StremioTvNowPlaying? stvNowPlaying(StremioTvChannel channel) {
    return StremioTvService.instance.getNowPlaying(
      channel,
      rotationMinutes: channel.type == 'series'
          ? stvSeriesRotationMinutes
          : stvRotationMinutes,
    );
  }

  /// Open a Stremio TV channel (same path the Home screen uses): hand off to the
  /// live player if it's mounted, else queue an auto-play and switch tabs.
  void playStremioTvChannel(StremioTvChannel channel) {
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(MainTab.stremioTv);
  }

  /// Load the user's starred IPTV channels for the leading favourites row.
  /// Favourites are stored as a url → {name, logoUrl, group} map, so rebuild
  /// [IptvChannel] objects from it in the store's user-defined order.
  Future<void> loadIptvFavorites() async {
    try {
      final map = await IptvPrefs.getIptvFavoriteChannels();
      if (map.isEmpty) {
        if (!mounted) return;
        commit(() => iptvFavChannels = const []);
        syncIptvFavNodes();
        return;
      }
      final favs = map.entries.map((e) {
        final meta = e.value;
        return IptvChannel(
          name: meta['name'] as String? ?? 'Unknown Channel',
          url: e.key,
          logoUrl: meta['logoUrl'] as String?,
          group: meta['group'] as String?,
          duration: -1, // live stream
          attributes: const {},
          httpHeaders: IptvPrefs.iptvFavoriteHeaders(meta),
        );
      }).toList();
      if (!mounted) return;
      commit(() => iptvFavChannels = favs);
      syncIptvFavNodes();
      maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  void syncIptvFavNodes() {
    while (iptvFavNodes.length < iptvFavChannels.length) {
      iptvFavNodes.add(
        FocusNode(debugLabel: 'search_iptvfav_${iptvFavNodes.length}'),
      );
    }
    while (iptvFavNodes.length > iptvFavChannels.length) {
      iptvFavNodes.removeLast().dispose();
    }
  }

  /// Rebuild the opted-in IPTV custom-list rows from the store.
  ///
  /// Channels are rebuilt from the stored list metadata alone (no provider
  /// fetch), keeping ALL presentation fields — content type and duration
  /// drive play routing and the live-preview gate, so the favourites row's
  /// lossy live-only mapping must not be copied here. Order is the list's
  /// explicit saved channel position.
  ///
  /// Token-guarded: the list picker queues several immediate mutations, each
  /// bumping [IptvMediaStore.listsRevision] — an older multi-list read must
  /// not commit after a newer one (stale channels, node reconciliation
  /// against the wrong rows). Only the newest load applies state.
  ///
  /// Nodes reconcile by list id: surviving rows keep their FocusNodes (grown/
  /// shrunk to the channel count), removed rows' nodes are disposed — if one
  /// held DPAD focus, the board's global dead-focus reclaim re-anchors it.
  Future<void> loadIptvListRows() async {
    final token = ++iptvListRowsLoadToken;
    try {
      // Read the extras store directly rather than [_homeExtras]: on a cold
      // start this runs CONCURRENTLY with _load() (which populates that
      // field), and losing the race would blank the list rows until the next
      // trigger.
      final extras = await StorageService.getHomeExtraRows();
      if (token != iptvListRowsLoadToken || !mounted) return;
      final wanted = <String>{
        for (final r in extras)
          if (HomeExtraRowIds.iptvListId(r.id) != null)
            HomeExtraRowIds.iptvListId(r.id)!,
      }..remove(StorageService.iptvFavoritesListId);
      List<FavouritesIptvListRow> next = const [];
      if (wanted.isNotEmpty) {
        final metas = await IptvPrefs.getIptvLists();
        final rows = <FavouritesIptvListRow>[];
        final prevById = {for (final r in iptvListRows) r.listId: r};
        for (final meta in metas) {
          if (!wanted.contains(meta.id) || meta.isFavorites) continue;
          final map = await IptvPrefs.getIptvListChannels(meta.id);
          if (token != iptvListRowsLoadToken || !mounted) return;
          final channels = <IptvChannel>[];
          map.forEach((url, m) {
            final name = (m['name'] as String?) ?? '';
            final logo = (m['logoUrl'] as String?) ?? '';
            final group = (m['group'] as String?) ?? '';
            channels.add(
              IptvChannel(
                name: name.isEmpty ? 'Unknown Channel' : name,
                url: url,
                logoUrl: logo.isEmpty ? null : logo,
                group: group.isEmpty ? null : group,
                channelNumber: (m['channelNumber'] as num?)?.toInt(),
                duration: (m['duration'] as num?)?.toInt() ?? -1,
                contentType: m['contentType'] as String?,
                attributes: {
                  if ((m['playlistId'] as String?)?.isNotEmpty ?? false)
                    'list_playlist_id': m['playlistId'] as String,
                },
                httpHeaders: IptvPrefs.iptvFavoriteHeaders(m),
              ),
            );
          });
          if (channels.isEmpty) continue;
          final row =
              prevById.remove(meta.id) ?? FavouritesIptvListRow(meta.id, '');
          row
            ..title = meta.name
            ..channels = channels;
          while (row.nodes.length < channels.length) {
            row.nodes.add(
              FocusNode(
                debugLabel: 'search_iptvlist_${meta.id}_${row.nodes.length}',
              ),
            );
          }
          while (row.nodes.length > channels.length) {
            row.nodes.removeLast().dispose();
          }
          rows.add(row);
        }
        // Rows that fell out (list deleted/emptied/de-selected): dispose their
        // nodes. The TV board's global focus watcher reclaims focus if one of
        // them held it.
        for (final gone in prevById.values) {
          for (final n in gone.nodes) {
            n.dispose();
          }
          gone.nodes.clear();
        }
        next = rows;
      } else if (iptvListRows.isEmpty) {
        return; // nothing enabled, nothing shown — no state churn
      } else {
        for (final gone in iptvListRows) {
          for (final n in gone.nodes) {
            n.dispose();
          }
          gone.nodes.clear();
        }
      }
      if (!mounted || token != iptvListRowsLoadToken) return;
      commit(() => iptvListRows = next);
      maybeAutoFocusBoard();
    } catch (_) {
      // List rows just stay as they were (same policy as the favourites row).
    }
  }

  /// [IptvMediaStore.listsRevision] bumped — some list mutated somewhere in
  /// the app (picker, IPTV settings, provider deletion, reconcile, import).
  void onIptvListsRevision() {
    if (!mounted) return;
    unawaited(loadIptvFavorites());
    unawaited(loadIptvListRows());
  }

  /// Play an IPTV custom-list entry by CONTENT TYPE — a list can hold VOD and
  /// collapsed series alongside live channels, and each routes differently
  /// (mirroring [IptvCwRouter]): live → the favourites-row live launch; VOD →
  /// watch-record + direct launch (the player restores resume by URL); an
  /// `xtream-series://` sentinel → the merged Xtream series page.
  Future<void> playIptvListChannel(IptvChannel channel) async {
    if (channel.url.startsWith('xtream-series://')) {
      return openIptvListSeries(channel);
    }
    if (!channel.isLive) {
      // Remember on-demand plays so the IPTV Continue Watching shelf can
      // rebuild the row later — recorded BEFORE the launch (the player
      // process can be killed outright on TV), same as the IPTV page.
      await StorageService.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: channel.attributes['list_playlist_id'],
        httpHeaders: channel.httpHeaders.isEmpty ? null : channel.httpHeaders,
      );
      if (!mounted) return;
    }
    await playIptvChannel(channel);
  }

  /// A collapsed series sentinel stored in a list: resolve its Xtream origin
  /// and open the merged series page (the episode list / Resume plays from
  /// there) — the sentinel URL itself is not a stream.
  Future<void> openIptvListSeries(IptvChannel channel) async {
    // xtream-series://<originId>/<seriesId>
    final rest = channel.url.substring('xtream-series://'.length);
    final slash = rest.indexOf('/');
    final originId = slash < 0
        ? (channel.attributes['list_playlist_id'] ?? '')
        : rest.substring(0, slash);
    final seriesId = slash < 0 ? rest : rest.substring(slash + 1);
    if (seriesId.isEmpty) return;
    final playlists = await IptvPrefs.getIptvPlaylists(forSettings: false);
    if (!mounted) return;
    IptvPlaylist? origin;
    for (final p in playlists) {
      if (p.id == originId && p.isXtreamCodes) {
        origin = p;
        break;
      }
    }
    if (origin == null) {
      ScaffoldMessenger.of(readContext()).showSnackBar(
        const SnackBar(
          content: Text("This series' provider is no longer available"),
        ),
      );
      return;
    }
    await openXtreamSeries(
      readContext(),
      playlist: origin,
      series: IptvChannel(
        name: channel.name,
        url: channel.url,
        logoUrl: channel.logoUrl,
        group: channel.group ?? channel.name,
        contentType: 'series',
        attributes: {
          'series_id': seriesId,
          if (originId.isNotEmpty) 'series_playlist_id': originId,
        },
      ),
      isTelevision: isTelevision,
    );
  }

  /// Play an IPTV favourite. Unlike the TV channels there's no bridge/tab
  /// handoff — the stream launches directly in the player (same as Home).
  /// Stremio-addon favourites carry a stremio-tv:// key instead of a stream
  /// URL — resolve it first, and hand the channel through the IPTV path so
  /// both players can walk the remaining candidates if the first one dies.
  /// Latch across the resolve window — repeated OK presses while a Stremio
  /// favourite resolves must not stack player launches.
  bool iptvFavLaunching = false;

  Future<void> playIptvChannel(IptvChannel channel) async {
    if (iptvFavLaunching) return;
    iptvFavLaunching = true;
    try {
      var videoUrl = channel.url;
      final isStremio = StremioIptvService.isStremioChannelUrl(channel.url);
      if (isStremio) {
        // Explicit play intent: bypass a cached-empty resolve and explain an
        // empty answer specifically (addon unreachable vs. no streams).
        final candidates = await StremioIptvService.instance.resolveCandidates(
          channel.url,
          refreshIfEmpty: true,
        );
        if (!mounted) return;
        if (candidates.isEmpty) {
          ScaffoldMessenger.of(readContext()).showSnackBar(
            SnackBar(
              content: Text(
                StremioIptvService.instance.unplayableMessage(
                  channel.url,
                  channel.name,
                ),
              ),
            ),
          );
          return;
        }
        videoUrl = candidates.first.url;
      }
      VideoPlayerLauncher.push(
        readContext(),
        VideoPlayerLaunchArgs(
          videoUrl: videoUrl,
          title: channel.name,
          subtitle: channel.group ?? 'IPTV',
          viewMode: PlaylistViewMode.sorted,
          // Identify the launch as IPTV for plain channels too (only the
          // Stremio branch used to): it routes playback down the live path
          // and lets the player report a dead stream instead of sitting on a
          // black screen.
          iptvChannels: [channel],
          iptvStartIndex: 0,
          // Playlist-declared headers (+ browser UA fallback) for the launch
          // channel; Stremio-addon links keep the addon's own defaults.
          httpHeaders: isStremio ? null : channel.playbackHeaders,
        ),
      );
    } finally {
      iptvFavLaunching = false;
    }
  }

  Future<void> loadMyWatchlist() async {
    try {
      final items = await MyWatchlistLoader.load();
      if (!mounted) return;
      commit(() {
        watchlistMovieItems = items.movies;
        watchlistSeriesItems = items.series;
      });
      syncMyWatchlistNodes();
      maybeAutoFocusBoard();
    } catch (_) {
      // A local shelf failure is non-fatal; leave it hidden.
    }
  }

  void syncMyWatchlistNodes() {
    syncWatchlistNodes(
      nodes: watchlistMovieNodes,
      itemCount: watchlistMovieItems.length,
      debugLabel: 'search_watchlist_movie',
    );
    syncWatchlistNodes(
      nodes: watchlistSeriesNodes,
      itemCount: watchlistSeriesItems.length,
      debugLabel: 'search_watchlist_series',
    );
  }

  void syncWatchlistNodes({
    required List<FocusNode> nodes,
    required int itemCount,
    required String debugLabel,
  }) {
    while (nodes.length < itemCount) {
      nodes.add(FocusNode(debugLabel: '${debugLabel}_${nodes.length}'));
    }
    var removedFocusedNode = false;
    while (nodes.length > itemCount) {
      final removed = nodes.removeLast();
      removedFocusedNode = removedFocusedNode || removed.hasFocus;
      removed.dispose();
    }
    if (removedFocusedNode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (nodes.isNotEmpty) {
          nodes.last.requestFocus();
        } else {
          focusContent();
        }
      });
    }
  }

  Future<void> offerRemoveUnavailableWatchlistItem(
    StremioMeta item, {
    required String message,
  }) async {
    final remove = await showDialog<bool>(
      context: readContext(),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Series unavailable'),
        content: Text('$message\n\nRemove it from My Watchlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    try {
      await MyWatchlistStore.setMyWatchlistItem(item, false);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await loadMyWatchlist();
      if (!mounted) return;
      ScaffoldMessenger.of(readContext())
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Removed from My Watchlist')),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(readContext()).showSnackBar(
        const SnackBar(content: Text("Couldn't update My Watchlist")),
      );
    }
  }

  Future<void> openMyWatchlistItem(StremioMeta item) async {
    final xtream = parseXtreamSeriesMetaId(item.id);
    if (xtream != null || item.sourceAddon?.id == 'xtream-iptv') {
      if (xtream == null) {
        await offerRemoveUnavailableWatchlistItem(
          item,
          message: "This series' saved source is invalid.",
        );
        return;
      }

      final playlists = await IptvPrefs.getIptvPlaylists(
        forSettings: false,
      );
      if (!mounted) return;
      IptvPlaylist? playlist;
      for (final candidate in playlists) {
        if (candidate.id == xtream.playlistId && candidate.isXtreamCodes) {
          playlist = candidate;
          break;
        }
      }
      if (playlist == null) {
        await offerRemoveUnavailableWatchlistItem(
          item,
          message: "This series' provider is no longer available.",
        );
        return;
      }

      await openXtreamSeries(
        readContext(),
        playlist: playlist,
        series: IptvChannel(
          name: item.name,
          url: 'xtream-series://${xtream.seriesId}',
          logoUrl: item.poster,
          group: item.name,
          contentType: 'series',
          attributes: {
            'series_id': xtream.seriesId,
            'series_playlist_id': xtream.playlistId,
            if (item.background?.isNotEmpty ?? false)
              'backdrop': item.background!,
            if (item.description?.isNotEmpty ?? false)
              'plot': item.description!,
            if (item.year?.isNotEmpty ?? false) 'releaseDate': item.year!,
            if (item.imdbRating != null) 'rating': item.imdbRating!.toString(),
            if (item.genres?.isNotEmpty ?? false)
              'genre': item.genres!.join(', '),
          },
        ),
        isTelevision: isTelevision,
      );
      if (mounted) await refreshAfterPlayback();
      return;
    }

    openItem(item, addonForContinue(item.sourceAddon?.id));
  }

  /// Load the user's saved playlist items for the leading Playlist row. Applies
  /// poster overrides and resume progress (same as the Home playlist section),
  /// newest first. Silently leaves the row empty on any error.
  Future<void> loadPlaylistFavorites() async {
    try {
      final results = await Future.wait([
        PlaybackProgressStore.getPlaylistItemsRaw(),
        PlaybackProgressStore.getPlaylistFavoriteKeys(),
        PlaybackProgressStore.getAllPlaylistPosterOverrides(),
      ]);
      final items = results[0] as List<Map<String, dynamic>>;
      final favKeys = results[1] as Set<String>;
      final overrides = results[2] as Map<String, String>;

      // Newest first (by addedAt), matching the Home playlist section.
      items.sort((a, b) {
        final at = a['addedAt'] as int? ?? 0;
        final bt = b['addedAt'] as int? ?? 0;
        return bt.compareTo(at);
      });
      // Apply any per-item poster override in a single pass.
      for (final item in items) {
        final key = PlaybackProgressStore.getPlaylistItemUniqueKey(item);
        final ov = overrides[key];
        if (ov != null && ov.isNotEmpty) item['posterUrl'] = ov;
      }

      final progress = await PlaybackProgressStore.buildPlaylistProgressMap(items);
      if (!mounted) return;
      commit(() {
        playlistItems = items;
        playlistProgress = progress;
        playlistFavKeys = favKeys;
      });
      syncPlaylistFavNodes();
      maybeAutoFocusBoard();
    } catch (_) {
      // Row just stays hidden.
    }
  }

  void syncPlaylistFavNodes() {
    while (playlistFavNodes.length < playlistItems.length) {
      playlistFavNodes.add(
        FocusNode(debugLabel: 'search_playlistfav_${playlistFavNodes.length}'),
      );
    }
    while (playlistFavNodes.length > playlistItems.length) {
      final removed = playlistFavNodes.removeLast();
      // Unlike the other fav rows, this one deletes items in-row — so the card
      // being trimmed can be the one that currently holds DPAD focus (delete the
      // focused last card). Disposing a focused node strands focus on a disposed
      // object; hand it to the new last card first (or let it fall out cleanly
      // when the row is now empty).
      final hadFocus = removed.hasFocus;
      removed.dispose();
      if (hadFocus && playlistFavNodes.isNotEmpty) {
        playlistFavNodes.last.requestFocus();
      }
    }
  }

  /// Resume fraction (0..1) for a playlist item, or null if it has no progress.
  /// [StorageService.buildPlaylistProgressMap] emits `positionMs`/`durationMs`
  /// (the Home section reads `position`/`duration`, which are never present — so
  /// its bar silently never draws; read the real keys here so ours works).
  double? playlistProgressFor(Map<String, dynamic> item) {
    final key = PlaybackProgressStore.computePlaylistDedupeKey(item);
    final p = playlistProgress[key];
    if (p == null) return null;
    final position = (p['positionMs'] as num?)?.toInt();
    final duration = (p['durationMs'] as num?)?.toInt();
    if (position == null || duration == null || duration <= 0) return null;
    return (position / duration).clamp(0.0, 1.0);
  }

  /// The full action menu for a playlist item — the same set of actions as the
  /// Home playlist section (Home is being phased out, so this row is a complete
  /// playlist manager on its own). Rendered with the post-torrent Neon action
  /// sheet: bottom sheet on phones, centered card on desktop/TV, with the
  /// first three actions as primary pills.
  Future<void> onPlaylistItemTap(Map<String, dynamic> item) async {
    if (!mounted) return;
    final dedupeKey = PlaybackProgressStore.computePlaylistDedupeKey(item);
    final isFavorited = playlistFavKeys.contains(dedupeKey);
    final hasProgress = playlistProgress.containsKey(dedupeKey);
    final isCollection = (item['kind'] as String?) != 'single';
    final title = (item['title'] as String?) ?? 'Unknown';

    // The sheet pops itself before running an action, so route every choice
    // through the handler instead of awaiting a dialog result.
    void run(String choice) =>
        unawaited(handlePlaylistMenuChoice(choice, item, isFavorited));

    final app = AppThemeScope.of(readContext());
    await showDebridActionSheet(
      readContext(),
      providerLabel: 'Playlist',
      torrentName: title,
      gradient: [app.seeAll.accent, app.seeAll.accent2],
      providerIcon: Icons.playlist_play_rounded,
      subtitle: isCollection
          ? 'Saved collection. Choose your next step.'
          : 'Saved item. Choose your next step.',
      actions: [
        DebridActionItem(
          icon: Icons.play_circle_fill_rounded,
          color: const Color(0xFF10B981),
          title: 'Play',
          subtitle: 'Start playback',
          onTap: () => run('play'),
        ),
        if (isCollection)
          DebridActionItem(
            icon: Icons.shuffle_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Play Random',
            subtitle: 'Start a random file from this collection',
            pillLabel: 'Random',
            onTap: () => run('play_random'),
          ),
        DebridActionItem(
          icon: Icons.folder_open_rounded,
          color: const Color(0xFF818CF8),
          title: 'View Files',
          subtitle: 'Browse folder contents',
          pillLabel: 'Files',
          onTap: () => run('view_files'),
        ),
        DebridActionItem(
          icon: isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
          color: const Color(0xFFFFD700),
          title: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
          subtitle: isFavorited
              ? 'Remove from your favorites list'
              : 'Add to your favorites list',
          pillLabel: 'Favorite',
          onTap: () => run('favorite'),
        ),
        if (hasProgress)
          DebridActionItem(
            icon: Icons.replay_rounded,
            color: const Color(0xFF60A5FA),
            title: 'Clear Progress',
            subtitle: 'Reset playback progress',
            onTap: () => run('clear_progress'),
          ),
        DebridActionItem(
          icon: Icons.delete_outline_rounded,
          color: app.home.danger,
          title: 'Delete',
          subtitle: 'Remove from playlist',
          onTap: () => run('delete'),
        ),
      ],
    );
  }

  Future<void> handlePlaylistMenuChoice(
    String choice,
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    if (!mounted) return;
    switch (choice) {
      case 'play':
        playPlaylistItem(item);
        break;
      case 'play_random':
        playPlaylistItem(item, playRandom: true);
        break;
      case 'view_files':
        await Navigator.of(readContext()).push(
          // Both doors are themed now (Search always was, Playlist since
          // phase two), so this screen resolves the same palette either way —
          // which is what the freeze was here to guarantee while they
          // disagreed.
          MaterialPageRoute(
            builder: (_) => PlaylistContentViewScreen(playlistItem: item),
          ),
        );
        // Progress / poster may have changed while browsing.
        loadPlaylistFavorites();
        break;
      case 'favorite':
        await PlaybackProgressStore.setPlaylistItemFavorited(item, !isFavorited);
        HapticFeedback.mediumImpact();
        loadPlaylistFavorites();
        break;
      case 'clear_progress':
        // Empty (not 'Unknown') fallback so a null-titled item clears nothing
        // instead of fuzzy-matching the literal word 'unknown' and wiping an
        // unrelated item's resume point — matches the Home section.
        await PlaybackProgressStore.clearPlaylistProgress(
          title: (item['title'] as String?) ?? '',
        );
        HapticFeedback.mediumImpact();
        loadPlaylistFavorites();
        break;
      case 'delete':
        await confirmDeletePlaylistItem(item);
        break;
    }
  }

  Future<void> playPlaylistItem(
    Map<String, dynamic> item, {
    bool playRandom = false,
  }) async {
    if (playlistLaunching) return;
    playlistLaunching = true;
    try {
      await PlaylistPlayerService.play(
        readContext(),
        item,
        playRandom: playRandom,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        readContext(),
      ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
    } finally {
      if (mounted) playlistLaunching = false;
    }
  }

  Future<void> confirmDeletePlaylistItem(Map<String, dynamic> item) async {
    final title = (item['title'] as String?) ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: readContext(),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Remove "$title" from your playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppThemeScope.of(dialogContext).home.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final dedupeKey = PlaybackProgressStore.computePlaylistDedupeKey(item);
      await PlaybackProgressStore.removePlaylistItemByKey(dedupeKey);
      HapticFeedback.mediumImpact();
      loadPlaylistFavorites();
    }
  }
}

class FavouritesIptvListRow {
  final String listId;
  String title;
  List<IptvChannel> channels;
  final List<FocusNode> nodes = [];
  FavouritesIptvListRow(this.listId, this.title) : channels = const [];
}
