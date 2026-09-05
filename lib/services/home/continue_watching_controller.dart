import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/advanced_search_selection.dart';
import '../../models/stremio_addon.dart';
import '../../services/episode_artwork_service.dart';
import '../../services/iptv_cw_router.dart';
import '../../services/mdblist/mdblist_continue_watching_service.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/mdblist/mdblist_sync_coordinator.dart';
import '../../services/simkl/simkl_continue_watching_service.dart';
import '../../services/storage_service.dart';
import '../../services/tracking_source_policy.dart';
import '../../services/trakt/trakt_continue_watching_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../../utils/concurrency.dart';
import '../../utils/continue_watching_presentation.dart';

enum CwKind { local, trakt, simkl, mdblist, iptv }

/// A leading "Continue Watching" board row (local or Trakt). Carries its own
/// header, focus nodes, per-item progress lookup, and open / quick-play
/// handlers so the local and Trakt sources render through one row builder.
class CwRow {
  final String rowId;
  final String title; // e.g. 'Continue Watching' or 'Trakt Movies'
  final String? tag; // 'Movies' / 'Series' pill, or null
  final CwKind kind;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final double? Function(StremioMeta) progressOf;

  /// Subtle 'S2 · E5' label for series cards (null for movies / when unknown).
  final String? Function(StremioMeta) episodeOf;

  /// Whole minutes remaining when this provider has a trustworthy duration.
  final int? Function(StremioMeta) remainingMinutesOf;

  /// Episode still for landscape series cards, resolved asynchronously and
  /// null until available. The card keeps its show-art fallback throughout.
  final String? Function(StremioMeta) episodeArtworkOf;
  final void Function(StremioMeta) onOpen;
  final void Function(StremioMeta) onQuickPlay;

  /// Takes the title off THIS row's source and reloads it. Long-press (hold-OK
  /// on TV) offers it next to Play — see [openCwCardMenu].
  final Future<void> Function(StremioMeta) onRemove;
  final bool Function(StremioMeta)? canRemove;

  /// Opens the "See All" grid for this row's source, or null to hide the link.
  final VoidCallback? onSeeAll;

  const CwRow({
    required this.rowId,
    required this.title,
    required this.tag,
    required this.kind,
    required this.items,
    required this.nodes,
    required this.progressOf,
    required this.episodeOf,
    required this.remainingMinutesOf,
    required this.episodeArtworkOf,
    required this.onOpen,
    required this.onQuickPlay,
    required this.onRemove,
    this.canRemove,
    this.onSeeAll,
  });
}

/// Node lists owned by the row widget; the controller only syncs lengths.
abstract class CwNodeBank {
  List<FocusNode> get movieNodes;
  List<FocusNode> get seriesNodes;
  List<FocusNode> get traktMovieNodes;
  List<FocusNode> get traktSeriesNodes;
  List<FocusNode> get simklMovieNodes;
  List<FocusNode> get simklSeriesNodes;
  List<FocusNode> get mdblistMovieNodes;
  List<FocusNode> get mdblistSeriesNodes;
  List<FocusNode> get iptvMovieNodes;
  List<FocusNode> get iptvSeriesNodes;
  void sync(List<FocusNode> nodes, int count, String tag);
  void disposeAll();
}

/// Host callbacks the per-source loaders need when building public [CwRow]s.
class ContinueWatchingBindings {
  const ContinueWatchingBindings({
    required this.openLocal,
    required this.playLocal,
    required this.removeLocal,
    required this.seeAllLocal,
    required this.openTrakt,
    required this.playTrakt,
    required this.removeTrakt,
    required this.seeAllTrakt,
    required this.openSimkl,
    required this.playSimkl,
    required this.removeSimkl,
    required this.seeAllSimkl,
    required this.openMdblist,
    required this.playMdblist,
    required this.removeMdblist,
    required this.canRemoveMdblist,
    required this.seeAllMdblist,
    required this.openIptv,
    required this.removeIptv,
  });

  final void Function(StremioMeta) openLocal;
  final void Function(StremioMeta) playLocal;
  final Future<void> Function(StremioMeta) removeLocal;
  final void Function(String category) seeAllLocal;
  final void Function(StremioMeta) openTrakt;
  final Future<void> Function(StremioMeta) playTrakt;
  final Future<void> Function(StremioMeta) removeTrakt;
  final void Function(String category) seeAllTrakt;
  final void Function(StremioMeta) openSimkl;
  final Future<void> Function(StremioMeta) playSimkl;
  final Future<void> Function(StremioMeta) removeSimkl;
  final void Function(String category) seeAllSimkl;
  final void Function(StremioMeta) openMdblist;
  final Future<void> Function(StremioMeta) playMdblist;
  final Future<void> Function(StremioMeta) removeMdblist;
  final bool Function(StremioMeta) canRemoveMdblist;
  final void Function(String category) seeAllMdblist;
  final void Function(StremioMeta) openIptv;
  final Future<void> Function(StremioMeta) removeIptv;
}

/// Host chrome the per-source open/play/remove paths still need.
class ContinueWatchingActions {
  const ContinueWatchingActions({
    required this.imdbOf,
    required this.addonForContinue,
    required this.openItem,
    required this.onCatalogPlay,
    required this.playSelection,
    required this.popUntilNotDetail,
  });

  final String? Function(StremioMeta item) imdbOf;
  final StremioAddon Function(String? addonId) addonForContinue;
  final void Function(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource,
    bool isMdblistSource,
    int? initialSeason,
    int? initialEpisode,
  })
  openItem;
  final Future<void> Function(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource,
    bool isMdblistSource,
    bool preferTraktResume,
  })
  onCatalogPlay;
  final void Function(AdvancedSearchSelection selection) playSelection;
  final void Function() popUntilNotDetail;
}

/// Format a season/episode as a compact 'S2 · E5' label, or null when unknown.
String? seLabel(int? season, int? episode) {
  if (season == null || episode == null || season <= 0 || episode <= 0) {
    return null;
  }
  return 'S$season · E$episode';
}

/// Per-source Continue Watching loaders extracted from `search_screen.dart`
/// (G1'-4). Outputs public [CwRow]s; node lists are owned by the row widget.
class ContinueWatchingController extends ChangeNotifier {
  ContinueWatchingController({
    required this.nodes,
    bool Function()? isLive,
    this.onMaybeAutoFocusBoard,
    this.onRefreshBoundSources,
    this.onSnack,
    this.onAnnounceTrakt,
    this.onAnnounceSimkl,
    this.onAnnounceMdblist,
  }) : _isLive = isLive;

  final CwNodeBank nodes;
  final bool Function()? _isLive;
  final VoidCallback? onMaybeAutoFocusBoard;
  final Future<void> Function()? onRefreshBoundSources;
  final void Function(String message)? onSnack;
  final VoidCallback? onAnnounceTrakt;
  final VoidCallback? onAnnounceSimkl;
  final VoidCallback? onAnnounceMdblist;

  ContinueWatchingActions? actions;
  ContinueWatchingBindings? bindings;

  bool _disposed = false;

  bool get _live => !_disposed && (_isLive?.call() ?? true);

  void _emit([VoidCallback? fn]) {
    fn?.call();
    if (!_disposed) notifyListeners();
  }

  // LOCAL Continue Watching rows. Reads the SAME local store Home writes to
  // (StorageService `continue_watching_v1`) — read-only here, so Home is never
  // affected. Split into two recency-ordered rows (Movies, then Series), each
  // shown as a leading board row when non-empty. Removal happens only from the
  // detail screen's action.
  bool cwEnabled = true;
  List<StremioMeta> cwMovies = [];
  List<StremioMeta> cwSeries = [];
  // Movies + series merged in last-watched order (newest first) — the source
  // for the Continue Watching "See All" grid, which filters by type itself.
  List<StremioMeta> cwAll = [];
  final Map<String, double> cwProgress = {}; // imdbId → 0..1 watched fraction
  final Map<String, String> cwEpisode = {}; // imdbId → 'S2 · E5' (series only)
  final Map<String, int> cwRemainingMinutes = {};
  final Map<String, String> cwEpisodeArtwork = {};
  final Set<String> cwIds = {}; // imdbIds currently in Continue Watching
  final Map<String, String?> cwAddonId = {}; // imdbId → source addon id

  // Per-provider "one Continue Watching row" preferences. When a provider is
  // merged, its MOVIES slot carries the combined recency-ordered list (the
  // same `_xxxAll` the See-All grid uses) on the movies node list, and its
  // Series row is suppressed — so row ids, saved Home order, and the
  // hide-rows page keep working off the existing `<provider>:movies` id.
  // Loaded once before the first node sync (each CW loader awaits
  // [ensureCwMergeFlags]); [_reloadForHomeSettings] re-reads and re-syncs
  // node counts when a toggle changes.
  bool cwMergeLocal = false;
  bool cwMergeTrakt = false;
  bool cwMergeSimkl = false;
  bool cwMergeMdblist = false;
  Future<void>? cwMergeFlagsLoad;

  Future<void> ensureCwMergeFlags() => cwMergeFlagsLoad ??= () async {
    try {
      final flags = await Future.wait([
        StorageService.getHomeCwMergedRows('local'),
        StorageService.getHomeCwMergedRows('trakt'),
        StorageService.getHomeCwMergedRows('simkl'),
        StorageService.getHomeCwMergedRows('mdblist'),
      ]);
      // Plain assignments: every caller is a CW loader that setStates right
      // after its node sync, so the flags never render stale.
      cwMergeLocal = flags[0];
      cwMergeTrakt = flags[1];
      cwMergeSimkl = flags[2];
      cwMergeMdblist = flags[3];
    } catch (_) {
      // Keep the split-rows defaults: a failed pref read must never become a
      // failed CW load (this memoized future is awaited by every loader).
    }
  }();

  // IPTV Continue Watching (Xtream VOD movies + series), sourced from the
  // player's own watch history via [IptvCwRouter] — kept separate from the
  // metadata-addon rows above because IPTV items aren't IMDb-keyed, so their
  // progress/episode lookups and routing key off the router's routeKey (stored
  // as the synthetic meta id) instead of an imdbId.
  List<StremioMeta> iptvCwMovies = [];
  List<StremioMeta> iptvCwSeries = [];
  final Map<String, double> iptvCwProgress = {}; // routeKey → 0..1
  final Map<String, String> iptvCwEpisode = {}; // routeKey → 'S2 · E5'
  final Map<String, IptvCwEntry> iptvCwByKey = {}; // routeKey → routing entry
  int iptvCwLoadToken = 0;

  /// Monotonic guard so an earlier, slower Continue Watching load (which does
  /// one SharedPreferences round-trip per item) can't finish after a newer one
  /// and dispose the focus nodes / state the newer run just installed.
  int cwLoadToken = 0;

  // TRAKT Continue Watching rows ("Trakt Movies" / "Trakt Shows"), fetched live
  // from the Trakt account (no local store). Shown after the local rows when
  // connected + non-empty. Network-loaded on init / integration change,
  // post-playback, and throttled app resume, then cached in memory.
  List<StremioMeta> traktMovies = [];
  List<StremioMeta> traktSeries = [];
  // Trakt movies + shows merged in last-watched (paused_at) order — the source
  // for the Trakt Continue Watching "See All" grid.
  List<StremioMeta> traktAll = [];
  final Map<String, double> traktProgress = {}; // imdbId → 0..1
  final Map<String, String> traktEpisode = {}; // imdbId → 'S2 · E5' (series)
  final Map<String, int> traktRemainingMinutes = {};
  final Map<String, String> traktEpisodeArtwork = {};
  final Map<String, TraktContinueWatchingItem> traktByImdb = {};

  // SIMKL Continue Watching rows ("Simkl Movies" / "Simkl Shows") — a parallel
  // strip below the Trakt rows, built from the account's paused playback
  // sessions (same `/sync/playback` lists the scrobble resume already fetches).
  // Independent of the Trakt block above so neither can regress the other.
  List<StremioMeta> simklMovies = [];
  List<StremioMeta> simklSeries = [];
  List<StremioMeta> simklAll = []; // paused_at order, for the See-All grid
  final Map<String, double> simklProgress = {}; // imdbId → 0..1
  final Map<String, String> simklEpisode = {}; // imdbId → 'S2 · E5' (series)
  final Map<String, String> simklEpisodeArtwork = {};
  final Map<String, SimklContinueWatchingItem> simklByImdb = {};
  int simklCwToken = 0;
  List<StremioMeta> mdblistMovies = [];
  List<StremioMeta> mdblistSeries = [];
  List<StremioMeta> mdblistAll = [];
  final Map<String, double> mdblistProgress = {};
  final Map<String, String> mdblistEpisode = {};
  final Map<String, MdblistContinueWatchingItem> mdblistByImdb = {};
  int mdblistCwToken = 0;
  int mdblistRevisionRefreshToken = 0;
  // True while a revision-driven delayed CW reload is queued/running, so
  // [_refreshAfterPlayback] can skip its own MDBList reload instead of doing a
  // second full fetch ~1s before the authoritative one lands.
  bool mdblistRevisionRefreshPending = false;
  // When the last FORCED CW load finished. Covers the slow-device case where
  // the delayed reload completes (clearing the pending flag) while
  // [_refreshAfterPlayback] is still awaiting its local loads — without this
  // it would immediately repeat the full fetch it just skipped for.
  DateTime? mdblistCwForcedLoadAt;

  bool get mdblistCwForceFresh {
    final at = mdblistCwForcedLoadAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 3);
  }

  int traktCwToken = 0;

  /// Last Trakt CW network attempt. The row is refreshed when the app returns
  /// from the background (where the user may have changed Trakt in another app
  /// or browser), but lifecycle noise within this window is coalesced.
  DateTime? lastTraktCwRefreshAttemptAt;
  static const Duration traktCwResumeRefreshInterval = Duration(seconds: 30);

  /// Whether a Trakt Continue Watching fetch is currently in flight for a
  /// connected account. While true — and there are no real Trakt rows to show
  /// yet — the Trakt slot is held open with skeleton placeholders (see
  /// [traktReserving]) so the real rows fill in place instead of inserting
  /// mid-board and shoving everything below them down. Set at the start of each
  /// load and cleared on every terminal path, so a mid-session connect (which
  /// re-runs the load) reserves the slot again.
  bool traktCwLoading = false;

  /// The Progress source, mirrored for the CW card lookups below. Smart until
  /// the first load resolves it (Smart = every row keeps its own numbers,
  /// which is also the pre-Tracking behaviour).
  WatchProgressSource cwProgressSource = WatchProgressSource.smart;

  /// Continue Watching cards show the title from whichever row owns it, but
  /// the PROGRESS comes from the selected Progress source — so a card can
  /// never advertise a resume point the detail page and Play button refuse to
  /// honour. In Smart mode each row keeps its own numbers (legacy behaviour);
  /// in a dedicated mode a title the chosen source doesn't know simply renders
  /// as a plain poster. IPTV rows are exempt: they are routeKey-keyed player
  /// history that no tracker can describe.
  double? cwCardProgress(CwKind kind, StremioMeta item) =>
      cwCardMaps(kind).progress[item.imdbId];

  String? cwCardEpisode(CwKind kind, StremioMeta item) =>
      cwCardMaps(kind).episode[item.imdbId];

  int? cwCardRemainingMinutes(CwKind kind, StremioMeta item) =>
      cwCardMaps(kind).remaining?[item.imdbId];

  ({
    Map<String, double> progress,
    Map<String, String> episode,
    Map<String, int>? remaining,
  })
  cwCardMaps(CwKind kind) {
    final effective = kind == CwKind.iptv
        ? kind
        : switch (cwProgressSource) {
            WatchProgressSource.smart => kind,
            WatchProgressSource.local => CwKind.local,
            WatchProgressSource.trakt => CwKind.trakt,
            WatchProgressSource.simkl => CwKind.simkl,
            WatchProgressSource.mdblist => CwKind.mdblist,
          };
    return switch (effective) {
      CwKind.local => (
        progress: cwProgress,
        episode: cwEpisode,
        remaining: cwRemainingMinutes,
      ),
      CwKind.trakt => (
        progress: traktProgress,
        episode: traktEpisode,
        remaining: traktRemainingMinutes,
      ),
      CwKind.simkl => (
        progress: simklProgress,
        episode: simklEpisode,
        remaining: null,
      ),
      CwKind.mdblist => (
        progress: mdblistProgress,
        episode: mdblistEpisode,
        remaining: null,
      ),
      CwKind.iptv => (
        progress: iptvCwProgress,
        episode: iptvCwEpisode,
        remaining: null,
      ),
    };
  }

  /// The leading Continue Watching rows to render, in order: local Movies /
  /// Series (when enabled), then Trakt Movies / Shows (when connected). Only
  /// non-empty groups are included. Each row carries its own progress lookup
  /// and open / quick-play handlers so local and Trakt sources coexist.
  List<CwRow> buildRows({
    required Set<String> homeDisabled,
    ContinueWatchingBindings? bindings,
  }) {
    final b = bindings ?? this.bindings;
    if (b == null) return const [];
    return _rowsFor(homeDisabled, b);
  }

  List<CwRow> _rowsFor(
    Set<String> homeDisabled,
    ContinueWatchingBindings bindings,
  ) => [
    // Merged providers ship their combined list through the MOVIES slot (same
    // row id, same node list — see the merge-pref field comment); the episode
    // and artwork lookups are imdbId-keyed maps that only hold series entries,
    // so passing movies through them is a harmless miss.
    if (cwEnabled &&
        (cwMergeLocal ? cwAll : cwMovies).isNotEmpty &&
        !homeDisabled.contains('cw:movies'))
      CwRow(
        rowId: 'cw:movies',
        title: 'Continue Watching',
        tag: cwMergeLocal ? null : 'Movies',
        kind: CwKind.local,
        items: cwMergeLocal ? cwAll : cwMovies,
        nodes: nodes.movieNodes,
        progressOf: (m) => cwCardProgress(CwKind.local, m),
        episodeOf: cwMergeLocal
            ? (m) => cwCardEpisode(CwKind.local, m)
            : (_) => null,
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.local, m),
        episodeArtworkOf: cwMergeLocal
            ? (m) => cwEpisodeArtwork[m.imdbId]
            : (_) => null,
        onOpen: bindings.openLocal,
        onQuickPlay: bindings.playLocal,
        onRemove: bindings.removeLocal,
        onSeeAll: () => bindings.seeAllLocal(cwMergeLocal ? 'all' : 'movie'),
      ),
    if (!cwMergeLocal &&
        cwEnabled &&
        cwSeries.isNotEmpty &&
        !homeDisabled.contains('cw:series'))
      CwRow(
        rowId: 'cw:series',
        title: 'Continue Watching',
        tag: 'Series',
        kind: CwKind.local,
        items: cwSeries,
        nodes: nodes.seriesNodes,
        progressOf: (m) => cwCardProgress(CwKind.local, m),
        episodeOf: (m) => cwCardEpisode(CwKind.local, m),
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.local, m),
        episodeArtworkOf: (m) => cwEpisodeArtwork[m.imdbId],
        onOpen: bindings.openLocal,
        onQuickPlay: bindings.playLocal,
        onRemove: bindings.removeLocal,
        onSeeAll: () => bindings.seeAllLocal('series'),
      ),
    if ((cwMergeTrakt ? traktAll : traktMovies).isNotEmpty &&
        !homeDisabled.contains('trakt:movies'))
      CwRow(
        rowId: 'trakt:movies',
        title: 'Trakt Continue Watching',
        tag: cwMergeTrakt ? null : 'Movies',
        kind: CwKind.trakt,
        items: cwMergeTrakt ? traktAll : traktMovies,
        nodes: nodes.traktMovieNodes,
        progressOf: (m) => cwCardProgress(CwKind.trakt, m),
        episodeOf: cwMergeTrakt
            ? (m) => cwCardEpisode(CwKind.trakt, m)
            : (_) => null,
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.trakt, m),
        episodeArtworkOf: cwMergeTrakt
            ? (m) => traktEpisodeArtwork[m.imdbId]
            : (_) => null,
        onOpen: bindings.openTrakt,
        onQuickPlay: bindings.playTrakt,
        onRemove: bindings.removeTrakt,
        onSeeAll: () => bindings.seeAllTrakt(cwMergeTrakt ? 'all' : 'movie'),
      ),
    if (!cwMergeTrakt &&
        traktSeries.isNotEmpty &&
        !homeDisabled.contains('trakt:shows'))
      CwRow(
        rowId: 'trakt:shows',
        title: 'Trakt Continue Watching',
        tag: 'Shows',
        kind: CwKind.trakt,
        items: traktSeries,
        nodes: nodes.traktSeriesNodes,
        progressOf: (m) => cwCardProgress(CwKind.trakt, m),
        episodeOf: (m) => cwCardEpisode(CwKind.trakt, m),
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.trakt, m),
        episodeArtworkOf: (m) => traktEpisodeArtwork[m.imdbId],
        onOpen: bindings.openTrakt,
        onQuickPlay: bindings.playTrakt,
        onRemove: bindings.removeTrakt,
        onSeeAll: () => bindings.seeAllTrakt('series'),
      ),
    // Simkl rows come after the Trakt rows. Both trackers fetch over the network
    // on a cold start (Simkl's playback/library caches are only warmed by a
    // scrobble or a prior read, not pre-warmed at launch), but only Trakt holds
    // its slot open with skeletons — so when the Simkl rows land they settle in
    // once, like any other content row. (A dedicated Simkl skeleton could make
    // that zero-shift too, but it isn't worth the board index-math complexity.)
    if ((cwMergeSimkl ? simklAll : simklMovies).isNotEmpty &&
        !homeDisabled.contains('simkl:movies'))
      CwRow(
        rowId: 'simkl:movies',
        title: 'Simkl Continue Watching',
        tag: cwMergeSimkl ? null : 'Movies',
        kind: CwKind.simkl,
        items: cwMergeSimkl ? simklAll : simklMovies,
        nodes: nodes.simklMovieNodes,
        progressOf: (m) => cwCardProgress(CwKind.simkl, m),
        episodeOf: cwMergeSimkl
            ? (m) => cwCardEpisode(CwKind.simkl, m)
            : (_) => null,
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.simkl, m),
        episodeArtworkOf: cwMergeSimkl
            ? (m) => simklEpisodeArtwork[m.imdbId]
            : (_) => null,
        onOpen: bindings.openSimkl,
        onQuickPlay: bindings.playSimkl,
        onRemove: bindings.removeSimkl,
        onSeeAll: () => bindings.seeAllSimkl(cwMergeSimkl ? 'all' : 'movie'),
      ),
    if (!cwMergeSimkl &&
        simklSeries.isNotEmpty &&
        !homeDisabled.contains('simkl:shows'))
      CwRow(
        rowId: 'simkl:shows',
        title: 'Simkl Continue Watching',
        tag: 'Shows',
        kind: CwKind.simkl,
        items: simklSeries,
        nodes: nodes.simklSeriesNodes,
        progressOf: (m) => cwCardProgress(CwKind.simkl, m),
        episodeOf: (m) => cwCardEpisode(CwKind.simkl, m),
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.simkl, m),
        episodeArtworkOf: (m) => simklEpisodeArtwork[m.imdbId],
        onOpen: bindings.openSimkl,
        onQuickPlay: bindings.playSimkl,
        onRemove: bindings.removeSimkl,
        onSeeAll: () => bindings.seeAllSimkl('series'),
      ),
    if ((cwMergeMdblist ? mdblistAll : mdblistMovies).isNotEmpty &&
        !homeDisabled.contains('mdblist:movies'))
      CwRow(
        rowId: 'mdblist:movies',
        title: 'MDBList Continue Watching',
        tag: cwMergeMdblist ? null : 'Movies',
        kind: CwKind.mdblist,
        items: cwMergeMdblist ? mdblistAll : mdblistMovies,
        nodes: nodes.mdblistMovieNodes,
        progressOf: (m) => cwCardProgress(CwKind.mdblist, m),
        episodeOf: cwMergeMdblist
            ? (m) => cwCardEpisode(CwKind.mdblist, m)
            : (_) => null,
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.mdblist, m),
        episodeArtworkOf: (_) => null,
        onOpen: bindings.openMdblist,
        onQuickPlay: bindings.playMdblist,
        onRemove: bindings.removeMdblist,
        canRemove: bindings.canRemoveMdblist,
        onSeeAll: () =>
            bindings.seeAllMdblist(cwMergeMdblist ? 'all' : 'movie'),
      ),
    if (!cwMergeMdblist &&
        mdblistSeries.isNotEmpty &&
        !homeDisabled.contains('mdblist:shows'))
      CwRow(
        rowId: 'mdblist:shows',
        title: 'MDBList Continue Watching',
        tag: 'Shows',
        kind: CwKind.mdblist,
        items: mdblistSeries,
        nodes: nodes.mdblistSeriesNodes,
        progressOf: (m) => cwCardProgress(CwKind.mdblist, m),
        episodeOf: (m) => cwCardEpisode(CwKind.mdblist, m),
        remainingMinutesOf: (m) => cwCardRemainingMinutes(CwKind.mdblist, m),
        episodeArtworkOf: (_) => null,
        onOpen: bindings.openMdblist,
        onQuickPlay: bindings.playMdblist,
        onRemove: bindings.removeMdblist,
        canRemove: bindings.canRemoveMdblist,
        onSeeAll: () => bindings.seeAllMdblist('series'),
      ),
    // IPTV Continue Watching (Xtream VOD). Routes through [IptvCwRouter], not
    // the addon/tracker pipeline — a movie resumes playback, a series opens the
    // merged Xtream series page. Progress/episode key off the synthetic meta id
    // (routeKey) since these metas carry no imdbId.
    if (iptvCwMovies.isNotEmpty && !homeDisabled.contains('iptv:movies'))
      CwRow(
        rowId: 'iptv:movies',
        title: 'IPTV Continue Watching',
        tag: 'Movies',
        kind: CwKind.iptv,
        items: iptvCwMovies,
        nodes: nodes.iptvMovieNodes,
        progressOf: (m) => iptvCwProgress[m.id],
        episodeOf: (_) => null,
        remainingMinutesOf: (m) => iptvRemainingMinutes(m.id),
        episodeArtworkOf: (_) => null,
        onOpen: bindings.openIptv,
        onQuickPlay: bindings.openIptv,
        onRemove: bindings.removeIptv,
      ),
    if (iptvCwSeries.isNotEmpty && !homeDisabled.contains('iptv:series'))
      CwRow(
        rowId: 'iptv:series',
        title: 'IPTV Continue Watching',
        tag: 'Series',
        kind: CwKind.iptv,
        items: iptvCwSeries,
        nodes: nodes.iptvSeriesNodes,
        progressOf: (m) => iptvCwProgress[m.id],
        episodeOf: (m) => iptvCwEpisode[m.id],
        remainingMinutesOf: (m) => iptvRemainingMinutes(m.id),
        episodeArtworkOf: (m) => iptvCwByKey[m.id]?.posterUrl,
        onOpen: bindings.openIptv,
        onQuickPlay: bindings.openIptv,
        onRemove: bindings.removeIptv,
      ),
  ];

  /// Whether any Continue Watching row is currently on-screen (drives focus
  /// wiring between it and the first catalog row). Uses allocation-free field
  /// checks (not `_cwRows`) since it's read on the per-card build hot path —
  /// keep these conditions in lock-step with the `_cwRows` row gates above.
  bool visible({
    required Set<String> homeDisabled,
    required String catalogQuery,
    required bool catalogSearching,
  }) =>
      ((cwEnabled &&
              (((cwMergeLocal ? cwAll : cwMovies).isNotEmpty &&
                      !homeDisabled.contains('cw:movies')) ||
                  (!cwMergeLocal &&
                      cwSeries.isNotEmpty &&
                      !homeDisabled.contains('cw:series')))) ||
          ((cwMergeTrakt ? traktAll : traktMovies).isNotEmpty &&
              !homeDisabled.contains('trakt:movies')) ||
          (!cwMergeTrakt &&
              traktSeries.isNotEmpty &&
              !homeDisabled.contains('trakt:shows')) ||
          ((cwMergeSimkl ? simklAll : simklMovies).isNotEmpty &&
              !homeDisabled.contains('simkl:movies')) ||
          (!cwMergeSimkl &&
              simklSeries.isNotEmpty &&
              !homeDisabled.contains('simkl:shows')) ||
          ((cwMergeMdblist ? mdblistAll : mdblistMovies).isNotEmpty &&
              !homeDisabled.contains('mdblist:movies')) ||
          (!cwMergeMdblist &&
              mdblistSeries.isNotEmpty &&
              !homeDisabled.contains('mdblist:shows')) ||
          (iptvCwMovies.isNotEmpty && !homeDisabled.contains('iptv:movies')) ||
          (iptvCwSeries.isNotEmpty && !homeDisabled.contains('iptv:series'))) &&
      catalogQuery.isEmpty &&
      !catalogSearching;

  /// Whether the Trakt rows should be held open with skeleton placeholders: the
  /// account is connected, its (slow, network) Continue Watching fetch is in
  /// flight, and there are no real Trakt rows on-screen yet. Reserving the slot
  /// keeps the row count stable so the real rows fill in place — nothing below
  /// reflows, and the auto-focus anchor stays put.
  ///
  /// Shown on every platform (the placeholder header omits the phone/desktop
  /// See-All link, which pops in harmlessly when the real row loads). Only on
  /// the homepage board (not the dedicated Search / Discover tabs, and not while
  /// a catalog search is showing its own results). Requiring the real rows to be
  /// empty means a refresh that already has data updates in place — no skeletons
  /// stacked on top of live rows.
  bool traktReserving({
    required bool searchMode,
    required bool discoverMode,
    required bool isTraktAuthenticated,
    required String catalogQuery,
    required bool catalogSearching,
  }) =>
      !searchMode &&
      !discoverMode &&
      isTraktAuthenticated &&
      traktCwLoading &&
      traktMovies.isEmpty &&
      traktSeries.isEmpty &&
      catalogQuery.isEmpty &&
      !catalogSearching;

  bool traktRowsVisible(Set<String> homeDisabled) =>
      ((cwMergeTrakt ? traktAll : traktMovies).isNotEmpty &&
          !homeDisabled.contains('trakt:movies')) ||
      (!cwMergeTrakt &&
          traktSeries.isNotEmpty &&
          !homeDisabled.contains('trakt:shows'));

  bool simklRowsVisible(Set<String> homeDisabled) =>
      ((cwMergeSimkl ? simklAll : simklMovies).isNotEmpty &&
          !homeDisabled.contains('simkl:movies')) ||
      (!cwMergeSimkl &&
          simklSeries.isNotEmpty &&
          !homeDisabled.contains('simkl:shows'));

  bool mdblistRowsVisible(Set<String> homeDisabled) =>
      ((cwMergeMdblist ? mdblistAll : mdblistMovies).isNotEmpty &&
          !homeDisabled.contains('mdblist:movies')) ||
      (!cwMergeMdblist &&
          mdblistSeries.isNotEmpty &&
          !homeDisabled.contains('mdblist:shows'));

  /// Load the Continue Watching row from the shared local store. Mirrors
  /// Home's join (item list + per-title playback progress) but is read-only —
  /// it never writes, so Home's row is untouched. Safe to call repeatedly
  /// (e.g. after returning from a detail/playback).
  Future<void> loadContinueWatching() async {
    final token = ++cwLoadToken;
    // Every CW reload passes through here (init, Home-settings change,
    // integration change, post-playback), so it is the one place the card
    // lookups need their Progress source refreshed.
    final progressSource = await StorageService.getWatchProgressSource();
    final enabled = await StorageService.getHomeContinueWatchingEnabled();
    if (!_live || token != cwLoadToken) return;
    if (progressSource != cwProgressSource) {
      _emit(() => cwProgressSource = progressSource);
    }
    if (!enabled) {
      // Free the focus nodes too — otherwise they linger allocated until
      // dispose while the rows are hidden.
      nodes.sync(nodes.movieNodes, 0, 'movie');
      nodes.sync(nodes.seriesNodes, 0, 'series');
      _emit(() {
        cwEnabled = false;
        cwMovies = [];
        cwSeries = [];
        cwAll = [];
        cwIds.clear();
        cwProgress.clear();
        cwEpisode.clear();
        cwRemainingMinutes.clear();
        cwEpisodeArtwork.clear();
        cwAddonId.clear();
      });
      return;
    }

    final raw = await StorageService.getContinueWatchingItems();
    final items = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final remainingMinutes = <String, int>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final ids = <String>{};
    final addonIds = <String, String?>{};
    for (final m in raw) {
      final imdbId = m['imdbId'] as String?;
      if (imdbId == null || imdbId.isEmpty) continue;
      final type = (m['contentType'] as String?) ?? 'movie';
      items.add(
        StremioMeta(
          id: imdbId,
          imdbId: imdbId,
          type: type,
          name: (m['title'] as String?) ?? 'Untitled',
          poster: m['posterUrl'] as String?,
          year: m['year'] as String?,
        ),
      );
      ids.add(imdbId);
      addonIds[imdbId] = m['addonId'] as String?;

      // Watched fraction — joined from the playback-state store, exactly like
      // HomeContinueWatchingSection (finished episodes count as 100%).
      double? pct;
      if (type == 'series') {
        final lastEp = await StorageService.getLastPlayedEpisodeByImdbId(
          imdbId,
        );
        if (lastEp != null) {
          final finished = lastEp['finished'] == true;
          final posMs = lastEp['positionMs'] as int? ?? 0;
          final durMs = lastEp['durationMs'] as int? ?? 1;
          if (durMs > 0) {
            pct = finished ? 100.0 : (posMs / durMs * 100).clamp(0.0, 100.0);
          }
          final se = seLabel(
            lastEp['season'] as int?,
            lastEp['episode'] as int?,
          );
          if (se != null) episode[imdbId] = se;
          final season = lastEp['season'] as int?;
          final episodeNumber = lastEp['episode'] as int?;
          if (season != null &&
              episodeNumber != null &&
              season > 0 &&
              episodeNumber > 0) {
            episodeRefs[imdbId] = (season: season, episode: episodeNumber);
          }
          final left = continueWatchingMinutesLeft(
            positionMs: posMs,
            durationMs: durMs,
          );
          if (left != null) remainingMinutes[imdbId] = left;
        }
      } else {
        final state = await StorageService.getVideoPlaybackStateByImdbId(
          imdbId,
        );
        if (state != null) {
          final posMs = state['positionMs'] as int? ?? 0;
          final durMs = state['durationMs'] as int? ?? 1;
          if (durMs > 0) pct = (posMs / durMs * 100).clamp(0.0, 100.0);
          final left = continueWatchingMinutesLeft(
            positionMs: posMs,
            durationMs: durMs,
          );
          if (left != null) remainingMinutes[imdbId] = left;
        }
      }
      if (pct != null) progress[imdbId] = pct / 100.0;
    }

    await ensureCwMergeFlags();
    // Bail if a newer load superseded this one while we were awaiting — never
    // dispose/replace nodes or state a later run already committed.
    if (!_live || token != cwLoadToken) return;

    // Split into two recency-ordered rows; `items` is already most-recent-first.
    final movies = items.where((m) => m.type != 'series').toList();
    final series = items.where((m) => m.type == 'series').toList();
    // Keep each row's focus-node list length in sync with its item count. Only
    // rebuild when the count changes (a plain refresh keeps the same nodes so
    // an active TV focus isn't dropped). Merged mode renders the combined list
    // through the movies slot, so its node count follows `items`.
    nodes.sync(
      nodes.movieNodes,
      cwMergeLocal ? items.length : movies.length,
      'movie',
    );
    nodes.sync(nodes.seriesNodes, cwMergeLocal ? 0 : series.length, 'series');

    _emit(() {
      cwEnabled = true;
      cwMovies = movies;
      cwSeries = series;
      cwAll = items;
      cwIds
        ..clear()
        ..addAll(ids);
      cwProgress
        ..clear()
        ..addAll(progress);
      cwEpisode
        ..clear()
        ..addAll(episode);
      cwRemainingMinutes
        ..clear()
        ..addAll(remainingMinutes);
      cwEpisodeArtwork.clear();
      cwAddonId
        ..clear()
        ..addAll(addonIds);
    });
    unawaited(
      enrichCwEpisodeArtwork(
        refs: episodeRefs,
        target: cwEpisodeArtwork,
        isCurrent: () => token == cwLoadToken,
      ),
    );
    onMaybeAutoFocusBoard?.call();
  }

  void onLocalCompletionChanged({
    required bool searchMode,
    required bool discoverMode,
  }) {
    if (!_live || searchMode || discoverMode) return;
    unawaited(loadContinueWatching());
  }

  /// Load the IPTV Continue Watching shelves (Xtream VOD movies + series) from
  /// the player's own watch history. Independent of [loadContinueWatching] —
  /// different data source, different (non-IMDb) identity — but follows the same
  /// token-guard + node-sync discipline so a slow reload can't clobber a newer
  /// one or drop the focus node the user is sitting on.
  Future<void> loadIptvContinueWatching({required bool searchMode}) async {
    // Never rendered on the dedicated Search tab (mirrors the tracker rows).
    if (searchMode) return;
    final token = ++iptvCwLoadToken;
    final rows = await IptvCwRouter.load();
    if (!_live || token != iptvCwLoadToken) return;

    StremioMeta metaFor(IptvCwEntry e) => StremioMeta(
      // routeKey as the id (no imdbId → all addon enrichment / bound-source /
      // hero-trailer lookups no-op, which is what we want for IPTV).
      id: e.routeKey,
      type: e.isSeries ? 'series' : 'movie',
      name: e.title,
      poster: e.posterUrl,
    );

    final movies = [for (final e in rows.movies) metaFor(e)];
    final series = [for (final e in rows.series) metaFor(e)];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final byKey = <String, IptvCwEntry>{};
    for (final e in [...rows.movies, ...rows.series]) {
      byKey[e.routeKey] = e;
      progress[e.routeKey] = e.progress;
      if (e.seLabel != null) episode[e.routeKey] = e.seLabel!;
    }

    nodes.sync(nodes.iptvMovieNodes, movies.length, 'iptv-movie');
    nodes.sync(nodes.iptvSeriesNodes, series.length, 'iptv-series');

    _emit(() {
      iptvCwMovies = movies;
      iptvCwSeries = series;
      iptvCwProgress
        ..clear()
        ..addAll(progress);
      iptvCwEpisode
        ..clear()
        ..addAll(episode);
      iptvCwByKey
        ..clear()
        ..addAll(byKey);
    });
    onMaybeAutoFocusBoard?.call();
  }

  int? iptvRemainingMinutes(String routeKey) {
    final raw = iptvCwByKey[routeKey]?.raw;
    if (raw == null) return null;
    return continueWatchingMinutesLeft(
      positionMs: (raw['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Resolve episode stills away from the build path, at TV-safe concurrency.
  /// A provider refresh owns the result through [isCurrent], so an older batch
  /// can never paint the episode that preceded a newly-resumed one.
  Future<void> enrichCwEpisodeArtwork({
    required Map<String, ({int season, int episode})> refs,
    required Map<String, String> target,
    required bool Function() isCurrent,
  }) async {
    if (refs.isEmpty) return;
    final resolved = await mapWithConcurrency(refs.entries, (entry) async {
      final art = await EpisodeArtworkService.instance.resolve(
        imdbId: entry.key,
        season: entry.value.season,
        episode: entry.value.episode,
      );
      return (id: entry.key, art: art);
    }, concurrency: 3);
    if (!_live || !isCurrent()) return;
    final artwork = <String, String>{
      for (final item in resolved)
        if (item.art != null && item.art!.isNotEmpty) item.id: item.art!,
    };
    if (artwork.isEmpty) return;
    _emit(() => target.addAll(artwork));
  }

  // ── Trakt Continue Watching ───────────────────────────────────────────────

  /// Fetch the Trakt "Continue Watching" rows (in-progress movies + up-next
  /// episodes) from the connected account. Uses Trakt's intent-aware Up Next
  /// feed plus paged playback checkpoints. Runs on init / integration change,
  /// post-playback, and a throttled app resume — never on every rebuild.
  /// Token-guarded against overlap; hides the rows when Trakt isn't connected.
  /// [refreshBound] runs a bound-source refresh at the end; pass false when the
  /// caller already refreshes bound sources itself (avoids a double pass).
  Future<void> loadTraktContinueWatching({bool refreshBound = true}) async {
    lastTraktCwRefreshAttemptAt = DateTime.now();
    final token = ++traktCwToken;
    // Mark the fetch in flight so the skeleton slot reserves while it runs (only
    // reserves when there are no real rows yet — see [traktReserving]). Plain
    // assignment, not setState: the sync prefix runs during initState on cold
    // start, and the first build reads the field anyway.
    traktCwLoading = true;
    final List<TraktContinueWatchingItem> movies;
    final List<TraktContinueWatchingItem> shows;
    try {
      final authed = await TraktService.instance.isAuthenticated();
      if (!_live || token != traktCwToken) return;
      if (!authed) {
        nodes.sync(nodes.traktMovieNodes, 0, 'tmovie');
        nodes.sync(nodes.traktSeriesNodes, 0, 'tseries');
        _emit(() {
          traktCwLoading = false;
          traktMovies = [];
          traktSeries = [];
          traktAll = [];
          traktProgress.clear();
          traktEpisode.clear();
          traktRemainingMinutes.clear();
          traktEpisodeArtwork.clear();
          traktByImdb.clear();
        });
        return;
      }
      final cw = TraktContinueWatchingService.instance;
      final reads = await Future.wait<Object?>([
        cw.fetchMoviesOrNull(),
        cw.fetchShowsOrNull(),
      ]);
      final movieRead = reads[0] as List<TraktContinueWatchingItem>?;
      final showRead = reads[1] as List<TraktContinueWatchingItem>?;
      if (movieRead == null || showRead == null) {
        throw StateError('Trakt Continue Watching read failed');
      }
      movies = movieRead;
      shows = showRead;
    } catch (e) {
      // Leave any existing rows in place on a transient Trakt/network error,
      // but stop reserving the skeleton slot so it doesn't shimmer forever.
      debugPrint('SearchScreen: Trakt continue-watching load failed: $e');
      if (_live && token == traktCwToken) {
        _emit(() => traktCwLoading = false);
      }
      return;
    }
    await ensureCwMergeFlags();
    if (!_live || token != traktCwToken) return;

    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final remainingMinutes = <String, int>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byImdb = <String, TraktContinueWatchingItem>{};
    void ingest(List<TraktContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = it.id;
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = seLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
        if (it.season != null &&
            it.episode != null &&
            it.season! > 0 &&
            it.episode! > 0) {
          episodeRefs[id] = (season: it.season!, episode: it.episode!);
        }
        final left = continueWatchingMinutesLeftFromProgress(
          progress: it.progress,
          runtimeMinutes: it.runtime,
        );
        if (left != null) remainingMinutes[id] = left;
      }
    }

    ingest(movies, movieMetas);
    ingest(shows, showMetas);
    // Merge into one last-watched-ordered list for the See-All grid: sort by
    // Trakt's paused_at / last_watched_at (newest first). Items without either
    // sort last. Ties use the original movies-then-shows order so the sort is
    // deterministic (Dart's List.sort isn't stable).
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[a.imdbId]?.pausedAtMs;
      final pb = byImdb[b.imdbId]?.pausedAtMs;
      if (pa != null && pb != null) {
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      } else if (pa == null && pb != null) {
        return 1;
      } else if (pa != null && pb == null) {
        return -1;
      }
      return origIndex[a]!.compareTo(origIndex[b]!);
    });
    // Whether the board already showed Trakt rows before this load — only a
    // fresh appearance (skeleton → content) announces itself below; a refresh
    // of rows the user can already see stays quiet.
    final hadTraktRows = traktMovies.isNotEmpty || traktSeries.isNotEmpty;
    nodes.sync(
      nodes.traktMovieNodes,
      cwMergeTrakt ? allMetas.length : movieMetas.length,
      'tmovie',
    );
    nodes.sync(
      nodes.traktSeriesNodes,
      cwMergeTrakt ? 0 : showMetas.length,
      'tseries',
    );
    _emit(() {
      traktCwLoading = false;
      traktMovies = movieMetas;
      traktSeries = showMetas;
      traktAll = allMetas;
      traktProgress
        ..clear()
        ..addAll(progress);
      traktEpisode
        ..clear()
        ..addAll(episode);
      traktRemainingMinutes
        ..clear()
        ..addAll(remainingMinutes);
      traktEpisodeArtwork.clear();
      traktByImdb
        ..clear()
        ..addAll(byImdb);
    });
    unawaited(
      enrichCwEpisodeArtwork(
        refs: episodeRefs,
        target: traktEpisodeArtwork,
        isCurrent: () => token == traktCwToken,
      ),
    );
    onMaybeAutoFocusBoard?.call();
    if (!hadTraktRows) onAnnounceTrakt?.call();
    if (refreshBound) {
      unawaited(onRefreshBoundSources?.call() ?? Future.value());
    }
  }

  Future<void> loadSimklContinueWatching({bool refreshBound = true}) async {
    final token = ++simklCwToken;
    final result = await SimklContinueWatchingService.instance.fetchItems();
    await ensureCwMergeFlags();
    if (!_live || token != simklCwToken) return;
    // Null = a transient fetch failure — leave any existing rows in place (a
    // real disconnect returns empty lists, which fall through and clear them).
    if (result == null) return;

    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byImdb = <String, SimklContinueWatchingItem>{};
    void ingest(List<SimklContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = it.id;
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        // "Up next" entries have no paused position — no progress bar for them.
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = seLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
        if (it.season != null &&
            it.episode != null &&
            it.season! > 0 &&
            it.episode! > 0) {
          episodeRefs[id] = (season: it.season!, episode: it.episode!);
        }
      }
    }

    ingest(result.movies, movieMetas);
    ingest(result.shows, showMetas);
    // Merge into one paused-order list for the See-All grid: newest paused_at
    // first, timestamp-less items last, ties fall back to movies-then-shows.
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[a.imdbId]?.pausedAtMs;
      final pb = byImdb[b.imdbId]?.pausedAtMs;
      if (pa != null && pb != null) {
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      } else if (pa == null && pb != null) {
        return 1;
      } else if (pa != null && pb == null) {
        return -1;
      }
      return origIndex[a]!.compareTo(origIndex[b]!);
    });

    // Whether the board already showed Simkl rows before this load — only a
    // fresh appearance announces itself below; a refresh of rows the user can
    // already see stays quiet.
    final hadSimklRows = simklMovies.isNotEmpty || simklSeries.isNotEmpty;
    nodes.sync(
      nodes.simklMovieNodes,
      cwMergeSimkl ? allMetas.length : movieMetas.length,
      'smovie',
    );
    nodes.sync(
      nodes.simklSeriesNodes,
      cwMergeSimkl ? 0 : showMetas.length,
      'sseries',
    );
    _emit(() {
      simklMovies = movieMetas;
      simklSeries = showMetas;
      simklAll = allMetas;
      simklProgress
        ..clear()
        ..addAll(progress);
      simklEpisode
        ..clear()
        ..addAll(episode);
      simklEpisodeArtwork.clear();
      simklByImdb
        ..clear()
        ..addAll(byImdb);
    });
    unawaited(
      enrichCwEpisodeArtwork(
        refs: episodeRefs,
        target: simklEpisodeArtwork,
        isCurrent: () => token == simklCwToken,
      ),
    );
    onMaybeAutoFocusBoard?.call();
    if (!hadSimklRows) onAnnounceSimkl?.call();
    if (refreshBound) {
      unawaited(onRefreshBoundSources?.call() ?? Future.value());
    }
  }

  Future<void> loadMdblistContinueWatching({
    bool refreshBound = true,
    bool force = false,
  }) async {
    final token = ++mdblistCwToken;
    debugPrint(
      '[MDBListDiag] Home CW load start token=$token '
      'refreshBound=$refreshBound force=$force flag=$kMdblistEnabled',
    );
    if (!kMdblistEnabled) {
      if (!_live) return;
      _emit(() {
        mdblistMovies = [];
        mdblistSeries = [];
        mdblistAll = [];
        mdblistByImdb.clear();
      });
      return;
    }
    await MdblistSyncCoordinator.instance.synchronizeInvalidations();
    if (!_live || token != mdblistCwToken) return;
    final result = await MdblistContinueWatchingService.instance.fetch(
      force: force,
    );
    await ensureCwMergeFlags();
    if (!_live || token != mdblistCwToken || !result.isUsable) {
      debugPrint(
        '[MDBListDiag] Home CW load discarded token=$token mounted=$_live '
        'currentToken=$mdblistCwToken kind=${result.kind.name}',
      );
      return;
    }
    final snapshot = result.data!;
    final movies = <StremioMeta>[];
    final shows = <StremioMeta>[];
    final progress = <String, double>{};
    final episodes = <String, String>{};
    final byImdb = <String, MdblistContinueWatchingItem>{};
    StremioMeta metaFor(MdblistContinueWatchingItem item) {
      final selection = item.selection;
      return StremioMeta(
        id: selection.imdbId,
        imdbId: selection.imdbId,
        type: selection.isSeries ? 'series' : 'movie',
        name: selection.title,
        poster: selection.posterUrl,
        background:
            'https://images.metahub.space/background/medium/${selection.imdbId}/img',
        year: selection.year,
      );
    }

    void ingest(
      Iterable<MdblistContinueWatchingItem> items,
      List<StremioMeta> target,
    ) {
      for (final item in items) {
        final id = item.selection.imdbId;
        if (byImdb.containsKey(id)) continue;
        target.add(metaFor(item));
        byImdb[id] = item;
        final pct = item.selection.mdblistProgressPercent;
        if (pct != null) progress[id] = (pct / 100).clamp(0, 1);
        final se = seLabel(item.selection.season, item.selection.episode);
        if (se != null) episodes[id] = se;
      }
    }

    ingest(snapshot.movies, movies);
    ingest(snapshot.shows, shows);
    debugPrint(
      '[MDBListDiag] Home CW ingest token=$token movies=${movies.length} '
      'shows=${shows.length}',
    );
    final all = [...movies, ...shows]
      ..sort((a, b) {
        final aa = byImdb[a.imdbId]?.updatedAt;
        final bb = byImdb[b.imdbId]?.updatedAt;
        return (bb ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aa ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
    final hadRows = mdblistMovies.isNotEmpty || mdblistSeries.isNotEmpty;
    nodes.sync(
      nodes.mdblistMovieNodes,
      cwMergeMdblist ? all.length : movies.length,
      'mdbmovie',
    );
    nodes.sync(
      nodes.mdblistSeriesNodes,
      cwMergeMdblist ? 0 : shows.length,
      'mdbseries',
    );
    _emit(() {
      mdblistMovies = movies;
      mdblistSeries = shows;
      mdblistAll = all;
      mdblistProgress
        ..clear()
        ..addAll(progress);
      mdblistEpisode
        ..clear()
        ..addAll(episodes);
      mdblistByImdb
        ..clear()
        ..addAll(byImdb);
    });
    if (force) mdblistCwForcedLoadAt = DateTime.now();
    onMaybeAutoFocusBoard?.call();
    if (!hadRows) onAnnounceMdblist?.call();
    if (refreshBound) {
      unawaited(onRefreshBoundSources?.call() ?? Future.value());
    }
  }

  void onMdblistPlaybackRevision({
    required bool searchMode,
    required bool discoverMode,
    required bool Function() isRouteCurrent,
  }) {
    if (searchMode || discoverMode) return;
    MdblistContinueWatchingService.instance.invalidate();
    final token = ++mdblistRevisionRefreshToken;
    mdblistRevisionRefreshPending = true;
    unawaited(
      refreshMdblistAfterMutation(token, isRouteCurrent: isRouteCurrent),
    );
  }

  Future<void> refreshMdblistAfterMutation(
    int token, {
    required bool Function() isRouteCurrent,
  }) async {
    try {
      // The stop response can arrive during the final frames of the player pop.
      // Wait until Home is visible, then allow MDBList's watched snapshot a
      // short propagation window before replacing the row with authoritative
      // data.
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!_live || token != mdblistRevisionRefreshToken) return;
        if (isRouteCurrent()) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!_live || token != mdblistRevisionRefreshToken) return;
      if (!isRouteCurrent()) return;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (!_live || token != mdblistRevisionRefreshToken) return;
      await loadMdblistContinueWatching(refreshBound: false, force: true);
    } finally {
      // Only the newest queued refresh owns the pending flag; a superseded one
      // must not clear it while its successor is still due to run.
      if (token == mdblistRevisionRefreshToken) {
        mdblistRevisionRefreshPending = false;
      }
    }
  }

  Future<void> reloadMergeFlags() async {
    final mergeFlags = await Future.wait([
      StorageService.getHomeCwMergedRows('local'),
      StorageService.getHomeCwMergedRows('trakt'),
      StorageService.getHomeCwMergedRows('simkl'),
      StorageService.getHomeCwMergedRows('mdblist'),
    ]);
    if (!_live) return;
    if (mergeFlags[0] != cwMergeLocal ||
        mergeFlags[1] != cwMergeTrakt ||
        mergeFlags[2] != cwMergeSimkl ||
        mergeFlags[3] != cwMergeMdblist) {
      _emit(() {
        cwMergeLocal = mergeFlags[0];
        cwMergeTrakt = mergeFlags[1];
        cwMergeSimkl = mergeFlags[2];
        cwMergeMdblist = mergeFlags[3];
        nodes.sync(
          nodes.movieNodes,
          cwMergeLocal ? cwAll.length : cwMovies.length,
          'movie',
        );
        nodes.sync(
          nodes.seriesNodes,
          cwMergeLocal ? 0 : cwSeries.length,
          'series',
        );
        nodes.sync(
          nodes.traktMovieNodes,
          cwMergeTrakt ? traktAll.length : traktMovies.length,
          'tmovie',
        );
        nodes.sync(
          nodes.traktSeriesNodes,
          cwMergeTrakt ? 0 : traktSeries.length,
          'tseries',
        );
        nodes.sync(
          nodes.simklMovieNodes,
          cwMergeSimkl ? simklAll.length : simklMovies.length,
          'smovie',
        );
        nodes.sync(
          nodes.simklSeriesNodes,
          cwMergeSimkl ? 0 : simklSeries.length,
          'sseries',
        );
        nodes.sync(
          nodes.mdblistMovieNodes,
          cwMergeMdblist ? mdblistAll.length : mdblistMovies.length,
          'mdbmovie',
        );
        nodes.sync(
          nodes.mdblistSeriesNodes,
          cwMergeMdblist ? 0 : mdblistSeries.length,
          'mdbseries',
        );
      });
    }
  }

  Future<void> removeLocalCwItem(
    StremioMeta item, {
    required String? Function(StremioMeta) imdbOf,
  }) async {
    final imdbId = imdbOf(item) ?? item.id;
    if (imdbId.isEmpty) return;
    await StorageService.removeContinueWatchingItem(imdbId);
    await StorageService.clearPlaybackStateByImdbId(imdbId);
    if (!_live) return;
    onSnack?.call('Removed from Continue Watching');
    await loadContinueWatching();
  }

  Future<void> removeIptvCwItem(StremioMeta item) async {
    final entry = iptvCwByKey[item.id];
    if (entry == null) return;
    if (entry.isSeries) {
      final seriesId = (entry.raw['seriesId'] as String?) ?? '';
      if (seriesId.isEmpty) return;
      await StorageService.removeIptvContinueWatchingSeries(
        playlistId: (entry.raw['playlistId'] as String?) ?? '',
        seriesId: seriesId,
      );
    } else {
      final url = (entry.raw['url'] as String?) ?? entry.routeKey;
      if (url.isEmpty) return;
      await StorageService.removeIptvContinueWatchingItem(url);
    }
    if (!_live) return;
    onSnack?.call('Removed from Continue Watching');
    await loadIptvContinueWatching(searchMode: false);
  }

  Future<void> removeMdblistCwItem(
    StremioMeta item, {
    required String? Function(StremioMeta) imdbOf,
  }) async {
    final cw = mdblistByImdb[imdbOf(item)];
    if (cw == null || !cw.paused) return;
    final removed = await MdblistContinueWatchingService.instance.clear(cw);
    if (!_live || !removed) return;
    onSnack?.call('Removed from MDBList Continue Watching');
    await loadMdblistContinueWatching();
  }

  bool canRemoveMdblistCwItem(
    StremioMeta item, {
    required String? Function(StremioMeta) imdbOf,
  }) => mdblistByImdb[imdbOf(item)]?.paused == true;

  bool maybeRefreshTraktOnResume({
    required bool searchMode,
    required bool isTraktAuthenticated,
    required bool playedSinceRefresh,
    required bool routeIsCurrent,
  }) {
    if (searchMode ||
        !isTraktAuthenticated ||
        playedSinceRefresh ||
        !routeIsCurrent) {
      return false;
    }
    final lastAttempt = lastTraktCwRefreshAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < traktCwResumeRefreshInterval) {
      return false;
    }
    return true;
  }

  Future<void> reloadAfterPlayback({
    required bool searchMode,
    required bool withTrackers,
  }) async {
    await loadContinueWatching();
    if (!_live) return;
    await loadIptvContinueWatching(searchMode: searchMode);
    if (!_live) return;
    if (withTrackers && !searchMode) {
      await Future.wait([
        loadTraktContinueWatching(refreshBound: false),
        loadSimklContinueWatching(refreshBound: false),
        if (!mdblistRevisionRefreshPending && !mdblistCwForceFresh)
          loadMdblistContinueWatching(refreshBound: false, force: true),
      ]);
    }
  }

  void openLocal(StremioMeta item) {
    final a = actions;
    if (a == null) return;
    a.openItem(item, a.addonForContinue(cwAddonId[item.imdbId]));
  }

  void playLocal(StremioMeta item) {
    final a = actions;
    if (a == null) return;
    a.onCatalogPlay(item, a.addonForContinue(cwAddonId[item.imdbId]));
  }

  void openTrakt(StremioMeta item) {
    final a = actions;
    if (a == null) return;
    a.openItem(
      item,
      a.addonForContinue(item.sourceAddon?.id),
      isTraktSource: true,
    );
  }

  Future<void> playTrakt(StremioMeta item) async {
    final a = actions;
    if (a == null) return;
    final cwItem = traktByImdb[a.imdbOf(item)];
    if (cwItem == null) {
      await a.onCatalogPlay(
        item,
        a.addonForContinue(item.sourceAddon?.id),
        isTraktSource: true,
        preferTraktResume: true,
      );
      return;
    }
    final sel = await TraktContinueWatchingService.instance.selectionForItem(
      cwItem,
    );
    if (!_live) return;
    if (sel == null) {
      onSnack?.call("Couldn't resolve where to resume \"${item.name}\".");
      return;
    }
    a.playSelection(sel);
  }

  void openSimkl(StremioMeta item) {
    final a = actions;
    if (a == null) return;
    final cw = simklByImdb[a.imdbOf(item)];
    a.openItem(
      item,
      a.addonForContinue(item.sourceAddon?.id),
      initialSeason: (cw != null && !cw.isMovie) ? cw.season : null,
      initialEpisode: (cw != null && !cw.isMovie) ? cw.episode : null,
    );
  }

  Future<void> playSimkl(StremioMeta item) async {
    final a = actions;
    if (a == null) return;
    final cw = simklByImdb[a.imdbOf(item)];
    if (cw == null) {
      await a.onCatalogPlay(item, a.addonForContinue(item.sourceAddon?.id));
      return;
    }
    a.playSelection(SimklContinueWatchingService.instance.selectionForItem(cw));
  }

  void openMdblist(StremioMeta item) {
    final a = actions;
    if (a == null) return;
    final cw = mdblistByImdb[a.imdbOf(item)];
    a.openItem(
      item,
      a.addonForContinue(item.sourceAddon?.id),
      initialSeason: cw?.selection.season,
      initialEpisode: cw?.selection.episode,
      isMdblistSource: true,
    );
  }

  Future<void> playMdblist(StremioMeta item) async {
    final a = actions;
    if (a == null) return;
    final cw = mdblistByImdb[a.imdbOf(item)];
    if (cw == null) {
      await a.onCatalogPlay(
        item,
        a.addonForContinue(item.sourceAddon?.id),
        isMdblistSource: true,
      );
      return;
    }
    a.playSelection(cw.selection);
  }

  Future<void> handleContinueDetailAction({
    required String imdbId,
    required void Function() popDetail,
  }) async {
    await StorageService.removeContinueWatchingItem(imdbId);
    await StorageService.clearPlaybackStateByImdbId(imdbId);
    if (!_live) return;
    popDetail();
    onSnack?.call('Removed from Continue Watching');
  }

  Future<void> removeFromTraktContinueWatching(
    String imdbId, {
    bool popDetail = true,
  }) async {
    final cwItem = traktByImdb[imdbId];
    if (cwItem == null) return;
    final removed = await TraktContinueWatchingService.instance.removeItem(
      cwItem,
    );
    if (!_live) return;
    if (!removed) {
      onSnack?.call('Failed to remove from Trakt Continue Watching');
      return;
    }
    if (popDetail) {
      actions?.popUntilNotDetail();
    }
    onSnack?.call('Removed from Trakt Continue Watching');
    await loadTraktContinueWatching(refreshBound: false);
  }

  Future<void> removeTraktCwItem(StremioMeta item) async {
    final imdbId = actions?.imdbOf(item) ?? imdbOfFallback(item);
    if (imdbId == null) return;
    await removeFromTraktContinueWatching(imdbId, popDetail: false);
  }

  static String? imdbOfFallback(StremioMeta item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  @override
  void dispose() {
    _disposed = true;
    mdblistRevisionRefreshToken++;
    nodes.disposeAll();
    super.dispose();
  }
}
