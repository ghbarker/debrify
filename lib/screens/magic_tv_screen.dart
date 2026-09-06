import '../services/cloud/rd_cloud_provider.dart';
import '../services/cloud/alldebrid_cloud_provider.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import '../services/debrify_tv/queue_prefetcher.dart';
import 'debrify_tv/watch/provider_watch_flow.dart';
import 'debrify_tv/watch/torbox_watch_flow.dart';
import 'debrify_tv/watch/pikpak_watch_flow.dart';
import 'debrify_tv/watch/premiumize_watch_flow.dart';
import 'debrify_tv/watch/alldebrid_watch_flow.dart';
import 'debrify_tv/watch/cached_locked_watch_programme.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';

import '../models/torrent.dart';
import '../widgets/torrent_result_row.dart' show qualityTierForName;
import '../models/debrify_tv_cache.dart';
import '../models/torbox_file.dart';
import '../models/debrify_tv/channel.dart';
import '../models/debrify_tv/channel_stats.dart';
import '../models/debrify_tv/prepared_torrents.dart';
import '../models/debrify_tv/cache_results.dart';
import '../services/analytics_service.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/cloud/cloud_provider_id.dart';
import '../services/cloud/cloud_provider_port.dart';
import '../services/cloud/cloud_provider_registry.dart';
import '../services/cloud/magic_tv_playable.dart';
import '../services/cloud/magic_tv_prepare_args.dart';
import '../services/cloud/magic_tv_provider.dart';
import '../services/debrid_service.dart';
import '../services/pikpak_tv_service.dart';
import '../services/storage_service.dart';
import '../services/video_player_launcher.dart';
import '../services/debrify_tv_cache_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/engine/engine_registry.dart';
import '../services/engine/settings_manager.dart';
import 'debrify_tv/channel_import_export_flow.dart';
import '../services/main_page_bridge.dart';
import '../models/profiles/profile_policy.dart';
import '../services/profiles/profile_policy_guard.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme_scope.dart';
import '../theme/overlay_theme.dart';
import '../utils/debrify_tv_filters.dart';
import '../utils/tv_keys.dart';
import '../widgets/tv_text_field.dart';
import 'video_player_screen.dart';
import 'debrify_tv/watch_session.dart';
import 'debrify_tv/channel_switch_flow.dart';
import '../services/debrify_tv/channel_cache_warmer.dart';
import 'debrify_tv/layouts/debrify_tv_view.dart';
import 'debrify_tv/layouts/spotlight_layout.dart';
import 'debrify_tv/widgets/switch_row.dart';
import 'debrify_tv/widgets/tv_focusable_button.dart';
import 'debrify_tv/widgets/tv_focusable_card.dart';
import 'debrify_tv/dialogs/cached_loading_dialog.dart';
import 'debrify_tv/dialogs/channel_creation_dialog.dart';
import 'debrify_tv/dialogs/external_player_notice_dialog.dart';
import 'debrify_tv/dialogs/spotlight_dialog.dart';
import 'debrify_tv/dialogs/channel_editor_dialog.dart';
import 'debrify_tv/dialogs/channel_playback_settings.dart';
import 'debrify_tv/channel_playback_settings_state.dart';

/// Magic TV provider-string dispatch. Persisted chip ids stay
/// [CloudProviderId.magicTvId] (`real_debrid`, not playback `debrid`).
///
/// Production adapters are routed with capability `is` checks. Fat-port
/// [FakeCloudProvider] (P1) does not implement those types, so [supports]
/// is the fallback — same dual path as [CloudProviderRegistry.prepareMagicTv].
class MagicTvDispatch {
  MagicTvDispatch._();

  static CloudProviderPort? portFor(String magicTvId) {
    final id = CloudProviderId.fromMagicTvId(magicTvId);
    if (id == null) return null;
    return CloudProviderRegistry.instance[id];
  }

  /// Unknown chip ids fall through to Real-Debrid, matching the old `else`.
  static CloudProviderId watchId(String magicTvId) =>
      CloudProviderId.fromMagicTvId(magicTvId) ?? CloudProviderId.debrid;

  static bool usesPrepare(String magicTvId) {
    final port = portFor(magicTvId);
    if (port == null) return false;
    if (port is CloudMagicTvPrepare) return true;
    return port.supports(CloudPortFeature.magicTvPrepare);
  }

  static bool usesLockedLinks(String magicTvId) {
    final port = portFor(magicTvId);
    if (port == null) return false;
    if (port is CloudMagicTvLockedLinks) return true;
    return port.supports(CloudPortFeature.magicTvLockedLinks);
  }

  /// TorBox `checkcached` window during channel switch. Not Premiumize
  /// [CloudCheckCache].
  static bool usesCachedHashes(String magicTvId) {
    final port = portFor(magicTvId);
    if (port == null) return false;
    if (port is CloudCachedHashes) return true;
    return port.supports(CloudPortFeature.cachedHashes);
  }

  static bool isSelectable(
    String magicTvId, {
    required bool realDebrid,
    required bool torbox,
    required bool pikpak,
    required bool premiumize,
    required bool allDebrid,
  }) {
    return switch (watchId(magicTvId)) {
      CloudProviderId.torbox => torbox,
      CloudProviderId.pikpak => pikpak,
      CloudProviderId.premiumize => premiumize,
      CloudProviderId.alldebrid => allDebrid,
      CloudProviderId.debrid => realDebrid,
    };
  }

  /// Next-channel button allowlists. These lists disagree on purpose
  /// (Premiumize / AllDebrid omitted on some player launches). Do not unify.
  static bool allowsNextChannel(
    String magicTvId,
    MagicTvNextChannelQuirk quirk,
  ) {
    final id = CloudProviderId.fromMagicTvId(magicTvId);
    if (id == null) return false;
    switch (quirk) {
      case MagicTvNextChannelQuirk.exceptAllDebrid:
        return id != CloudProviderId.alldebrid;
      case MagicTvNextChannelQuirk.rdTorboxPikPak:
        return id == CloudProviderId.debrid ||
            id == CloudProviderId.torbox ||
            id == CloudProviderId.pikpak;
      case MagicTvNextChannelQuirk.allKnown:
        return true;
    }
  }
}

/// Player `requestNextChannel` gates copied from the pre-P2a string ORs.
enum MagicTvNextChannelQuirk {
  /// RD|TB|PP|PM. Channel RD/TB/PP/PM and quick RD-early / PM.
  exceptAllDebrid,

  /// RD|TB|PP. Quick RD-late / TB / PP. Excludes Premiumize and AllDebrid.
  rdTorboxPikPak,

  /// All five Magic TV ids. Channel AllDebrid and quick AllDebrid.
  allKnown,
}

const int _randomStartPercentDefault =
    ChannelPlaybackSettingsState.randomStartPercentDefault;
const int _randomStartPercentMin = 10;
const int _randomStartPercentMax = 90;

int _clampRandomStartPercent(int? value) {
  final candidate = value ?? _randomStartPercentDefault;
  if (candidate < _randomStartPercentMin) {
    return _randomStartPercentMin;
  }
  if (candidate > _randomStartPercentMax) {
    return _randomStartPercentMax;
  }
  return candidate;
}

int _parseRandomStartPercent(dynamic value) {
  if (value is int) {
    return _clampRandomStartPercent(value);
  }
  if (value is double) {
    return _clampRandomStartPercent(value.round());
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return _clampRandomStartPercent(parsed);
    }
  }
  return _randomStartPercentDefault;
}

enum _DebrifyTvTopMenuAction { import, export, add, deleteAll, settings }

class DebrifyTVScreen extends StatefulWidget {
  const DebrifyTVScreen({super.key});

  @override
  State<DebrifyTVScreen> createState() => _DebrifyTVScreenState();
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen>
    implements ProgressSink, ChannelImportExportHost {
  static const String _torboxFileEntryType = 'torbox_file';
  static const int _torboxMinVideoSizeBytes =
      50 * 1024 * 1024; // 50 MB filter threshold

  final SettingsManager _settingsManager = SettingsManager();
  final TextEditingController _keywordsController = TextEditingController();
  final WatchSession _watchSession = WatchSession();
  late final ChannelCacheWarmer _cacheWarmer = ChannelCacheWarmer(
    viewerForcesNsfw: () => _viewerForcesNsfw,
    filters: () => _playbackSettings.tvFilters,
    minVideoSizeBytes: _torboxMinVideoSizeBytes,
    onQualityFallback: _notifyQualityFallback,
    onSizeFallback: () {
      _showSnack(
        'Few ${_playbackSettings.tvFilters.summary()} files here — playing other sizes too.',
        color: Colors.orange,
      );
    },
  );

  late final _queuePrefetcher = QueuePrefetcher(
    queue: _queue,
    seenRestrictedLinks: _seenRestrictedLinks,
    seenLinkWithTorrentId: _seenLinkWithTorrentId,
    settingsManager: _settingsManager,
    isMounted: () => mounted,
    buildLockedRequest: _magicTvLockedRequest,
  );

  // M1-3 retained host bindings; review at M1-5, expire/review-remove in M1-6.
  late final _watchBindings = WatchFlowBindings(
    allDebridAvailable: WatchValue(() => _allDebridAvailable),
    hideOptions: WatchValue(() => _playbackSettings.hideOptions),
    hideSeekbar: WatchValue(() => _playbackSettings.hideSeekbar),
    isAndroidTv: WatchValue(() => _isAndroidTv),
    getChannelKeywords: _getChannelKeywords,
    isBusy: WatchValue(() => _isBusy, (value) => _isBusy = value),
    launchedPlayer: WatchValue(() => _launchedPlayer, (value) => _launchedPlayer = value),
    pikpakAvailable: WatchValue(() => _pikpakAvailable),
    prefetchStopRequested: WatchValue(() => _queuePrefetcher.stopRequested, (value) => _queuePrefetcher.stopRequested = value),
    premiumizeAvailable: WatchValue(() => _premiumizeAvailable),
    progressOpen: WatchValue(() => _progressOpen, (value) => _progressOpen = value),
    qualityFallbackNotified: WatchValue(() => _qualityFallbackNotified, (value) => _qualityFallbackNotified = value),
    quickAvoidNsfw: WatchValue(() => _playbackSettings.quickAvoidNsfw),
    quickHideOptions: WatchValue(() => _playbackSettings.quickHideOptions),
    quickHideSeekbar: WatchValue(() => _playbackSettings.quickHideSeekbar),
    quickShowChannelName: WatchValue(() => _playbackSettings.quickShowChannelName),
    quickShowVideoTitle: WatchValue(() => _playbackSettings.quickShowVideoTitle),
    quickStartRandom: WatchValue(() => _playbackSettings.quickStartRandom),
    rdAvailable: WatchValue(() => _rdAvailable),
    rdSkipBlockedTorrents: WatchValue(() => _rdSkipBlockedTorrents),
    showChannelName: WatchValue(() => _playbackSettings.showChannelName),
    showVideoTitle: WatchValue(() => _playbackSettings.showVideoTitle),
    startRandom: WatchValue(() => _playbackSettings.startRandom),
    torboxAvailable: WatchValue(() => _torboxAvailable),
    viewerForcesNsfw: WatchValue(() => _viewerForcesNsfw),
    watchCancelled: WatchValue(() => _watchCancelled, (value) => _watchCancelled = value),
    activeProvider: WatchValue(() => _queuePrefetcher.activeProvider, (value) => _queuePrefetcher.activeProvider = value),
    provider: WatchValue(() => _playbackSettings.provider),
    quickProvider: WatchValue(() => _playbackSettings.quickProvider),
    status: WatchValue(() => _watchSession.status, (value) => _watchSession.status = value),
    torboxFileEntryType: WatchValue(() => _torboxFileEntryType),
    activeApiKey: WatchValue(() => _queuePrefetcher.activeApiKey, (value) => _queuePrefetcher.activeApiKey = value),
    currentWatchingChannelId: WatchValue(() => _currentWatchingChannelId, (value) => _currentWatchingChannelId = value),
    lastQueueSize: WatchValue(() => _lastQueueSize, (value) => _lastQueueSize = value),
    quickPlayMaxKeywords: WatchValue(() => _quickPlayMaxKeywords),
    quickRandomStartPercent: WatchValue(() => _playbackSettings.quickRandomStartPercent),
    randomStartPercent: WatchValue(() => _playbackSettings.randomStartPercent),
    originalMaxCap: WatchValue(() => _originalMaxCap, (value) => _originalMaxCap = value),
    lastSearchAt: WatchValue(() => _lastSearchAt, (value) => _lastSearchAt = value),
    cacheWarmer: WatchValue(() => _cacheWarmer),
    channels: WatchValue(() => _channels),
    keywordsController: WatchValue(() => _keywordsController),
    pikpakCandidatePool: WatchValue(() => _pikpakCandidatePool, (value) => _pikpakCandidatePool = value),
    progress: WatchValue(() => _progress),
    progressSheetContext: WatchValue(() => _progressSheetContext, (value) => _progressSheetContext = value),
    queue: WatchValue(() => _queue),
    seenLinkWithTorrentId: WatchValue(() => _seenLinkWithTorrentId),
    seenRestrictedLinks: WatchValue(() => _seenRestrictedLinks),
    tvFilters: WatchValue(() => _playbackSettings.tvFilters),
    mounted: WatchValue(() => mounted),
    androidTvChannelMetadata: _androidTvChannelMetadata,
    cancelActiveWatch: _cancelActiveWatch,
    closeProgressDialog: _closeProgressDialog,
    fetchPremiumizeCacheWindow: _fetchPremiumizeCacheWindow,
    formatTorboxError: _formatTorboxError,
    handOffToExternalPlayer: _handOffToExternalPlayer,
    launchPikPakOnAndroidTv: _launchPikPakOnAndroidTv,
    launchRealDebridOnAndroidTv: _launchRealDebridOnAndroidTv,
    launchTorboxOnAndroidTv: _launchTorboxOnAndroidTv,
    normalizeInfohash: _normalizeInfohash,
    notifyQualityFallback: _notifyQualityFallback,
    preparePikPakTorrent: _preparePikPakTorrent,
    preparePremiumizeTorrent: _preparePremiumizeTorrent,
    prepareTorboxTorrent: _prepareTorboxTorrent,
    providerDisplay: _providerDisplay,
    requestChannelById: _requestChannelById,
    requestNextChannel: _requestNextChannel,
    resolveAllDebridLinks: _queuePrefetcher.resolveAllDebridLinks,
    resolveChannelNumber: _resolveChannelNumber,
    resolveRdLockedLinks: _resolveRdLockedLinks,
    resolveTorboxQueuedFile: _resolveTorboxQueuedFile,
    showCachedPlaybackDialog: _showCachedPlaybackDialog,
    showSnack: _showSnack,
    startPrefetch: _queuePrefetcher.startPrefetch,
    stopPrefetch: _queuePrefetcher.stopPrefetch,
    syncProviderAvailability: _syncProviderAvailability,
    navigator: () => Navigator.of(context),
    messenger: () => ScaffoldMessenger.of(context),
    showProgressDialog: ({required builder, required barrierDismissible}) => showDialog<void>(context: context, builder: builder, barrierDismissible: barrierDismissible),
    setState: setState,
    rdUnlock: const RealDebridCloudProvider(),
    adUnlock: const AllDebridCloudProvider(),
  );
  late final _channelSwitch = ChannelSwitchFlow(_watchBindings);
  late final _providerWatch = ProviderWatchFlow(
    _watchBindings,
    watchWithTorbox: _torboxWatch.watchWithTorbox,
    watchWithPikPak: _pikpakWatch.watchWithPikPak,
    watchWithPremiumize: _premiumizeWatch.watchWithPremiumize,
    watchWithAllDebrid: _alldebridWatch.watchWithAllDebrid,
  );
  late final _torboxWatch = TorboxWatchFlow(_watchBindings);
  late final _pikpakWatch = PikpakWatchFlow(_watchBindings);
  late final _premiumizeWatch = PremiumizeWatchFlow(_watchBindings);
  /// AllDebrid Quick Play. Self-contained like [PremiumizeWatchFlow.watchWithPremiumize] for the
  /// search phase, but follows Real-Debrid's resolve model (sequential
  /// add-and-probe + background prefetcher) since AllDebrid has no cache-check
  /// API. Each candidate is added trusting the `ready` flag (no polling) and
  /// links are unlocked lazily on demand.
  late final _alldebridWatch = AlldebridWatchFlow(_watchBindings);

  late final ChannelImportExport _importExport = ChannelImportExport(host: this);
  // Mixed queue: can contain Torrent items or RD-restricted link maps
  List<dynamic> get _queue => _watchSession.queue;
  bool get _isBusy => _watchSession.isBusy;
  set _isBusy(bool value) => _watchSession.isBusy = value;
  set _status(String value) => _watchSession.status = value;
  List<DebrifyTvChannel> _channels = <DebrifyTvChannel>[];

  /// `debrify_tv_style`, read once per mount from the mirror warmed in
  /// `main()`: tabs are keyed by index and rebuilt on switch, so a picker
  /// change is picked up on the next entry — no bridge, like `iptv_style`.
  final String _debrifyTvStyle = StorageService.debrifyTvStyleCached;

  // ── Spotlight stage data (rail cheap, stage lazy — plan §7) ─────────
  Map<String, DebrifyTvRailHealth> _spotlightRailHealth = const {};
  final Map<String, DebrifyTvChannelStats> _spotlightStats = {};
  Timer? _spotlightStatsDebounce;
  String? _spotlightFocusedId;
  Map<String, DebrifyTvChannelCacheEntry> get _channelCache =>
      _cacheWarmer.channelCache;
  List<Torrent>? get _pikpakCandidatePool => _watchSession.pikpakCandidatePool;
  set _pikpakCandidatePool(List<Torrent>? value) =>
      _watchSession.pikpakCandidatePool = value;

  // Quick Play limits
  int _quickPlayMaxKeywords = 5;

  static const int _minimumTorrentsForChannel = 1;
  static const int _maxChannelKeywords = 1000;
  final TextEditingController _channelSearchController =
      TextEditingController();
  String _channelSearchTerm = '';
  String? get _currentWatchingChannelId =>
      _watchSession.currentWatchingChannelId;
  set _currentWatchingChannelId(String? value) =>
      _watchSession.currentWatchingChannelId = value;

  final ChannelPlaybackSettingsState _playbackSettings =
      ChannelPlaybackSettingsState();

  // Advanced options

  // Quick play options

  /// The viewer-scoped, role-locked NSFW rail: forced for a child profile
  /// regardless of any channel's stored flag or dialog toggle. Evaluated
  /// live so a profile switch retunes filtering without a rebuild dance.
  bool get _viewerForcesNsfw =>
      !ProfilePolicyGuard.allowsSync(ProfileFeature.allowAdultContent);
  bool _rdSkipBlockedTorrents = true;

  // Debrify TV playback filters. Shared by channels and quick play (one
  // Debrify TV feed preference, unlike provider/NSFW which are per-scope).
  // Quality narrows torrents by release name; size narrows FILES once a
  // provider has returned them. See DebrifyTvFilters for why they split.
  // Rate-limits the "filter relaxed" snackbar to once per playback session.
  bool _qualityFallbackNotified = false;
  // Real-Debrid only: consecutive links rejected purely on size, and the
  // resulting session-wide relaxation. See ChannelCacheWarmer.rdLinkPassesSizeRules.

  bool _rdAvailable = false;
  bool _torboxAvailable = false;
  bool _pikpakAvailable = false;
  bool _premiumizeAvailable = false;
  bool _allDebridAvailable = false;
  // De-dupe sets for RD-restricted entries
  final Set<String> _seenRestrictedLinks = {};
  final Set<String> _seenLinkWithTorrentId = {};
  bool _isAndroidTv = false;
  bool _showSearchBar = false;
  Set<String> _favoriteChannelIds = {};
  late final FocusNode _channelSearchFocusNode;
  final FocusNode _quickPlayFocusNode = FocusNode(
    debugLabel: 'DebrifyTVQuickPlay',
  );
  final FocusNode _channelSearchButtonFocusNode = FocusNode(
    debugLabel: 'DebrifyTVChannelSearchButton',
  );
  final FocusNode _channelSearchClearFocusNode = FocusNode(
    debugLabel: 'DebrifyTVChannelSearchClear',
  );
  final FocusNode _channelMenuFocusNode = FocusNode(
    debugLabel: 'DebrifyTVChannelMenu',
  );
  final MenuController _channelMenuController = MenuController();

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  // Progress UI state
  ValueNotifier<List<String>> get _progress => _watchSession.progress;
  BuildContext? get _progressSheetContext => _watchSession.progressSheetContext;
  set _progressSheetContext(BuildContext? value) =>
      _watchSession.progressSheetContext = value;
  bool get _progressOpen => _watchSession.progressOpen;
  set _progressOpen(bool value) => _watchSession.progressOpen = value;
  int _lastQueueSize = 0;
  DateTime? _lastSearchAt;
  bool _launchedPlayer = false;
  bool _watchCancelled = false;
  int? _originalMaxCap;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('magic_tv');
    _channelSearchFocusNode = FocusNode(debugLabel: 'DebrifyTVChannelSearch');
    _loadSettings();
    _loadChannels(); // also warms the Spotlight rail health, once per reload
    _loadFavoriteChannels();

    // Register watch channel handler for external calls (e.g., from home screen)
    MainPageBridge.watchDebrifyTvChannel = _watchChannelById;

    // Register TV sidebar focus handler (tab index 3 = Debrify TV)
    _tvContentFocusHandler = () {
      _quickPlayFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(3, _tvContentFocusHandler!);

    // Check for pending auto-play from home screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingAutoPlay();
    });
  }

  @override
  void dispose() {
    _spotlightStatsDebounce?.cancel();
    // Clear watch channel handler
    MainPageBridge.watchDebrifyTvChannel = null;
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        3,
        _tvContentFocusHandler!,
      );
    }
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _queuePrefetcher.stopRequested = true;
    _queuePrefetcher.stopPrefetch();
    // Clean up dialog state to avoid dangling context references
    _progressSheetContext = null;
    _progressOpen = false;
    _progress.dispose();
    _keywordsController.dispose();
    _channelSearchController.dispose();
    _channelSearchFocusNode.dispose();
    _quickPlayFocusNode.dispose();
    _channelSearchButtonFocusNode.dispose();
    _channelSearchClearFocusNode.dispose();
    _channelMenuFocusNode.dispose();
    AndroidTvPlayerBridge.clearTorboxProvider();
    super.dispose();
  }

  /// Back/Escape ladder for the channel search bar: clear text first, then
  /// close the bar. Sits on an ancestor Focus of the search field so it runs
  /// when the TvTextField shell lets the key bubble.
  KeyEventResult _handleChannelSearchBarBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_channelSearchController.text.isNotEmpty) {
        _channelSearchController.clear();
        setState(() {
          _channelSearchTerm = '';
        });
        // Clearing unmounts the suffix ✕ — if IT held focus, focus would be
        // stranded; parking on the field covers both cases.
        _channelSearchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_showSearchBar) {
        setState(() {
          _showSearchBar = false;
        });
        _channelSearchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _closeProgressDialog() {
    if (!_progressOpen) {
      return;
    }
    if (_progressSheetContext != null) {
      try {
        Navigator.of(_progressSheetContext!).pop();
      } catch (_) {}
      _progressSheetContext = null;
      _progressOpen = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_progressOpen) {
        return;
      }
      if (_progressSheetContext != null) {
        _closeProgressDialog();
        return;
      }
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      _progressSheetContext = null;
      _progressOpen = false;
    });
  }

  @override
  void closeProgressDialog() {
    _closeProgressDialog();
  }

  @override
  void updateProgress(Iterable<String> messages, {bool replace = false}) {
    _updateProgress(messages, replace: replace);
  }

  void _updateProgress(Iterable<String> messages, {bool replace = false}) {
    _watchSession.updateProgress(messages, replace: replace);
  }

  void _cancelActiveWatch({
    BuildContext? dialogContext,
    bool clearQueue = true,
  }) {
    debugPrint(
      '[MagicTV] _cancelActiveWatch called, dialogContext=$dialogContext, clearQueue=$clearQueue, _watchCancelled=$_watchCancelled',
    );
    if (_watchCancelled) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Already cancelled, just popping dialog',
      );
      if (dialogContext != null) {
        try {
          Navigator.of(dialogContext).pop();
        } catch (e) {
          debugPrint('[MagicTV] _cancelActiveWatch: Error popping dialog: $e');
        }
      }
      return;
    }
    _watchCancelled = true;
    _queuePrefetcher.stopRequested = true;
    debugPrint(
      '[MagicTV] _cancelActiveWatch: Set _watchCancelled=true, stopping prefetch',
    );
    unawaited(_queuePrefetcher.stopPrefetch());
    if (clearQueue) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Clearing queue (had ${_queue.length} items)',
      );
      _queue.clear();
    }
    _progress.value = [];
    if (dialogContext != null) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Popping dialog via dialogContext',
      );
      try {
        Navigator.of(dialogContext).pop();
      } catch (e) {
        debugPrint('[MagicTV] _cancelActiveWatch: Error popping dialog: $e');
      }
      _progressOpen = false;
      _progressSheetContext = null;
    } else if (_progressOpen) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: No dialogContext, calling _closeProgressDialog',
      );
      _closeProgressDialog();
    }
    if (mounted) {
      setState(() {
        _isBusy = false;
        _status = '';
      });
    }
    debugPrint('[MagicTV] _cancelActiveWatch: Done');
  }

  String _determineDefaultProvider(
    String? preferred,
    bool rdAvailable,
    bool torboxAvailable,
    bool pikpakAvailable,
    bool premiumizeAvailable,
    bool allDebridAvailable,
  ) {
    return MagicTvProvider.pickDefault(
      preferred: preferred,
      available: MagicTvProvider.availability(
        realDebrid: rdAvailable,
        torbox: torboxAvailable,
        pikpak: pikpakAvailable,
        premiumize: premiumizeAvailable,
        allDebrid: allDebridAvailable,
      ),
    );
  }

  bool _isProviderSelectable(String provider) {
    return MagicTvDispatch.isSelectable(
      provider,
      realDebrid: _rdAvailable,
      torbox: _torboxAvailable,
      pikpak: _pikpakAvailable,
      premiumize: _premiumizeAvailable,
      allDebrid: _allDebridAvailable,
    );
  }

  Future<void> _loadSettings() async {
    final startRandom = await StorageService.getDebrifyTvStartRandom();
    final randomStartPercent =
        await StorageService.getDebrifyTvRandomStartPercent();
    // Hardcoded to false - no longer loading from storage
    const hideOptions = false;
    final showChannelName = await StorageService.getDebrifyTvShowChannelName();
    final showVideoTitle = await StorageService.getDebrifyTvShowVideoTitle();
    // hideBackButton is hardcoded to false - no longer loading from storage
    final avoidNsfw = await _settingsManager.getGlobalAvoidNsfw(true);
    final rdSkipBlocked = await ProviderCredentialPrefs.getRdSkipBlockedTorrents();
    final tvFilters = await DebrifyTvFilters.load();
    final storedProvider = await StorageService.getDebrifyTvProvider();
    final hasStoredProvider = await StorageService.hasDebrifyTvProvider();
    final rdIntegrationEnabled =
        await ProviderCredentialPrefs.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final torboxIntegrationEnabled =
        await ProviderCredentialPrefs.getTorboxIntegrationEnabled();
    final torboxKey = await StorageService.getTorboxApiKey();

    final registry = EngineRegistry.instance;
    await registry.initialize();
    final keywordEngines = registry.getKeywordSearchEngines();
    final tvEngines = registry
        .getTvModeEngines()
        .where((engine) => engine.supportsKeywordSearch)
        .toList();
    final tvEngineStates = <String, bool>{
      for (final engine in keywordEngines) engine.name: false,
    };
    final tvSmallChannelMaxByEngine = <String, int>{};
    final tvLargeChannelMaxByEngine = <String, int>{};
    final tvQuickPlayMaxByEngine = <String, int>{};

    for (final engine in tvEngines) {
      final tvMode = engine.tvModeConfig;
      if (tvMode == null) {
        continue;
      }
      final engineId = engine.name;
      tvEngineStates[engineId] = await _settingsManager.getTvEnabled(
        engineId,
        tvMode.enabledDefault,
      );
      tvSmallChannelMaxByEngine[engineId] = await _settingsManager
          .getTvSmallChannelMax(engineId, tvMode.smallChannel.maxResults);
      tvLargeChannelMaxByEngine[engineId] = await _settingsManager
          .getTvLargeChannelMax(engineId, tvMode.largeChannel.maxResults);
      tvQuickPlayMaxByEngine[engineId] = await _settingsManager
          .getTvQuickPlayMax(engineId, tvMode.quickPlay.maxResults);
    }

    // Global TV settings
    final channelBatchSize = await _settingsManager.getGlobalBatchSize(4);
    final keywordThreshold = await _settingsManager.getGlobalKeywordThreshold(
      10,
    );
    final minTorrentsPerKeyword = await _settingsManager
        .getGlobalMinTorrentsPerKeyword(5);
    final quickPlayMaxKeywords = await _settingsManager.getGlobalMaxKeywords(5);

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final premiumizeIntegrationEnabled =
        await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final premiumizeAvailable =
        premiumizeIntegrationEnabled &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridIntegrationEnabled =
        await ProviderCredentialPrefs.getAllDebridIntegrationEnabled();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final allDebridAvailable =
        allDebridIntegrationEnabled &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;
    final defaultProvider = _determineDefaultProvider(
      hasStoredProvider ? storedProvider : null,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );
    final isTv = await AndroidNativeDownloader.isTelevision();

    if (mounted) {
      setState(() {
        _playbackSettings.startRandom = startRandom;
        _playbackSettings.randomStartPercent = _clampRandomStartPercent(randomStartPercent);
        _playbackSettings.hideSeekbar = hideOptions;
        _playbackSettings.showChannelName = showChannelName;
        _playbackSettings.showVideoTitle = showVideoTitle;
        _playbackSettings.hideOptions = false; // Hardcoded to false
        _playbackSettings.hideBackButton = false; // Hardcoded to false
        _rdAvailable = rdAvailable;
        _torboxAvailable = torboxAvailable;
        _pikpakAvailable = pikpakAvailable;
        _premiumizeAvailable = premiumizeAvailable;
        _allDebridAvailable = allDebridAvailable;
        _playbackSettings.provider = defaultProvider;
        _isAndroidTv = isTv;

        _playbackSettings.quickStartRandom = startRandom;
        _playbackSettings.quickRandomStartPercent = _clampRandomStartPercent(randomStartPercent);
        _playbackSettings.quickHideSeekbar = hideOptions;
        _playbackSettings.quickShowChannelName = showChannelName;
        _playbackSettings.quickShowVideoTitle = showVideoTitle;
        _playbackSettings.quickHideOptions = false; // Hardcoded to false
        _playbackSettings.quickHideBackButton = false; // Hardcoded to false
        _playbackSettings.quickAvoidNsfw = avoidNsfw;
        _rdSkipBlockedTorrents = rdSkipBlocked;
        _playbackSettings.quickProvider = defaultProvider;
        _playbackSettings.tvFilters = tvFilters;
        // The filter is an INPUT to the memoised stage numbers: anything
        // computed before this load landed used the empty default.
        _spotlightStats.clear();

        // Update search settings
        _cacheWarmer.tvEngineStates
          ..clear()
          ..addAll(tvEngineStates);
        _cacheWarmer.tvSmallChannelMaxByEngine
          ..clear()
          ..addAll(tvSmallChannelMaxByEngine);
        _cacheWarmer.tvLargeChannelMaxByEngine
          ..clear()
          ..addAll(tvLargeChannelMaxByEngine);
        _cacheWarmer.tvQuickPlayMaxByEngine
          ..clear()
          ..addAll(tvQuickPlayMaxByEngine);
        _cacheWarmer.channelBatchSize = channelBatchSize;
        _cacheWarmer.keywordThreshold = keywordThreshold;
        _cacheWarmer.minTorrentsPerKeyword = minTorrentsPerKeyword;
        _quickPlayMaxKeywords = quickPlayMaxKeywords;
      });
      // Outside the setState callback: recomputing the focused channel's
      // numbers schedules its own rebuild.
      _refreshSpotlightStatsIfFocused(_spotlightFocusedId);
    }

    if (await StorageService.getDebrifyTvHideSeekbar() != hideOptions) {
      unawaited(StorageService.saveDebrifyTvHideSeekbar(hideOptions));
    }

    if (defaultProvider != storedProvider) {
      await StorageService.saveDebrifyTvProvider(defaultProvider);
    }
  }

  Future<void> _loadChannels() async {
    final records = await DebrifyTvRepository.instance.fetchAllChannels();
    if (!mounted) return;
    setState(() {
      _channels = records
          .map(DebrifyTvChannel.fromRecord)
          .toList(growable: false);
    });
    // Every path that reloads channels (create, edit, delete-all, ZIP/YAML/
    // community imports) has fresh pools too, so the rail's pips ride along
    // here rather than each call site remembering to refresh them.
    if (_debrifyTvStyle == 'spotlight') {
      await _loadSpotlightRailHealth();
    }
  }

  Future<void> _loadFavoriteChannels() async {
    final favoriteIds = await StorageService.getDebrifyTvFavoriteChannelIds();
    if (!mounted) return;
    setState(() {
      _favoriteChannelIds = favoriteIds;
    });
  }

  Future<void> _toggleChannelFavorite(DebrifyTvChannel channel) async {
    final isFavorited = _favoriteChannelIds.contains(channel.id);
    final newState = !isFavorited;

    await StorageService.setDebrifyTvChannelFavorited(channel.id, newState);

    if (!mounted) return;
    setState(() {
      if (newState) {
        _favoriteChannelIds = {..._favoriteChannelIds, channel.id};
      } else {
        _favoriteChannelIds = _favoriteChannelIds
            .where((id) => id != channel.id)
            .toSet();
      }
    });
  }

  /// Watch a channel by ID (called from external sources like home screen)
  Future<void> _watchChannelById(String channelId) async {
    final channel = _channels.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null) {
      _watchChannel(channel);
    } else {
      debugPrint('DebrifyTVScreen: Channel with ID $channelId not found');
    }
  }

  /// Check for pending auto-play channel from home screen
  Future<void> _checkPendingAutoPlay() async {
    final channelId = MainPageBridge.getAndClearDebrifyTvChannelToAutoPlay();
    if (channelId == null) return;

    // Wait for channels to load
    int attempts = 0;
    const maxAttempts = 50; // 5 seconds max wait
    while (_channels.isEmpty && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
      if (!mounted) return;
    }

    if (_channels.isEmpty) {
      debugPrint('DebrifyTVScreen: Channels not loaded for auto-play');
      return;
    }

    _watchChannelById(channelId);
  }


  Future<void> _deleteChannel(String id) async {
    setState(() {
      _channels = _channels.where((c) => c.id != id).toList();
    });
    await DebrifyTvRepository.instance.deleteChannel(id);
    setState(() {
      _channelCache.remove(id);
      _spotlightStats.remove(id);
      _spotlightRailHealth = Map.of(_spotlightRailHealth)..remove(id);
      // The layout's staged-channel repair fires onChannelFocused for its
      // replacement; a dangling id here would make that look like a no-move.
      if (_spotlightFocusedId == id) _spotlightFocusedId = null;
    });
  }

  Future<void> _syncProviderAvailability() async {
    final rdIntegrationEnabled =
        await ProviderCredentialPrefs.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final torboxIntegrationEnabled =
        await ProviderCredentialPrefs.getTorboxIntegrationEnabled();
    final torboxKey = await StorageService.getTorboxApiKey();
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final premiumizeIntegrationEnabled =
        await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final premiumizeAvailable =
        premiumizeIntegrationEnabled &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridIntegrationEnabled =
        await ProviderCredentialPrefs.getAllDebridIntegrationEnabled();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final allDebridAvailable =
        allDebridIntegrationEnabled &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;

    final nextChannelProvider = _determineDefaultProvider(
      _playbackSettings.provider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );
    final nextQuickProvider = _determineDefaultProvider(
      _playbackSettings.quickProvider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );

    if (!mounted) return;
    final providerChanged = nextChannelProvider != _playbackSettings.provider;
    setState(() {
      _rdAvailable = rdAvailable;
      _torboxAvailable = torboxAvailable;
      _pikpakAvailable = pikpakAvailable;
      _premiumizeAvailable = premiumizeAvailable;
      _allDebridAvailable = allDebridAvailable;
      _playbackSettings.provider = nextChannelProvider;
      _playbackSettings.quickProvider = nextQuickProvider;
    });

    if (providerChanged) {
      await StorageService.saveDebrifyTvProvider(nextChannelProvider);
    }
  }

  Future<List<String>> _getChannelKeywords(String channelId) async {
    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index == -1) {
      return const <String>[];
    }
    final existing = _channels[index];
    if (existing.keywords.isNotEmpty) {
      return existing.keywords;
    }
    final fetched = await DebrifyTvRepository.instance.fetchChannelKeywords(
      channelId,
    );
    if (!mounted) {
      return fetched;
    }
    final updated = existing.copyWith(keywords: fetched);
    setState(() {
      final next = List<DebrifyTvChannel>.from(_channels);
      next[index] = updated;
      _channels = next;
    });
    return fetched;
  }

  /// Tells the user once per playback session that the quality filter was
  /// relaxed. Rate-limited because the quick-play queue is rebuilt per engine
  /// and channel switches re-enter the same path.
  void _notifyQualityFallback() {
    if (_qualityFallbackNotified) return;
    _qualityFallbackNotified = true;
    _showSnack(
      'No ${_playbackSettings.tvFilters.summary()} sources found — playing anything available.',
      color: Colors.orange,
    );
  }

  String _providerDisplay(String provider) => MagicTvProvider.display(provider);

  /// Quality + size pickers for Debrify TV playback. One shared setting for
  /// both channels and quick play, so the same feed rules apply wherever you
  /// start watching. Nothing selected in a row = that facet is off.
  Future<DebrifyTvChannel?> _openChannelDialog({
    DebrifyTvChannel? existing,
  }) => ChannelEditorDialog.open(
    context,
    existing: existing,
    isAndroidTv: () => _isAndroidTv,
    viewerForcesNsfw: () => _viewerForcesNsfw,
    isMounted: () => mounted,
    parseKeywords: _cacheWarmer.parseKeywords,
    maxChannelKeywords: _maxChannelKeywords,
  );

  Future<void> _handleAddChannel() async {
    await _syncProviderAvailability();
    final channel = await _openChannelDialog();
    if (channel != null) {
      await _createOrUpdateChannel(channel, isEdit: false);
    }
  }


  Future<void> _handleEditChannel(DebrifyTvChannel channel) async {
    await _syncProviderAvailability();

    // Store current channel's NSFW setting before dialog
    final nsfwBeforeEdit = channel.avoidNsfw;

    final keywords = await _getChannelKeywords(channel.id);
    final hydrated = channel.copyWith(keywords: keywords);
    final updated = await _openChannelDialog(existing: hydrated);
    if (updated != null) {
      // Check if channel's NSFW setting changed
      final nsfwAfterEdit = updated.avoidNsfw;
      final nsfwChanged = nsfwBeforeEdit != nsfwAfterEdit;

      if (nsfwChanged) {
        // NSFW setting changed for this channel - rebuild cache with new filter
        debugPrint(
          'DebrifyTV: Channel NSFW filter changed. Forcing full cache rebuild...',
        );

        // Clear existing cache to force full rebuild
        _channelCache.remove(updated.id);

        // Rebuild cache with new NSFW filter setting (isEdit: false forces full rebuild)
        await _createOrUpdateChannel(updated, isEdit: false);

        _showSnack(
          'Channel cache rebuilt with updated NSFW filter.',
          color: Colors.green,
        );
      } else {
        // No NSFW change, just normal update
        await _createOrUpdateChannel(updated, isEdit: true);
      }
    }
  }

  Future<bool> _showDebrifyTvConfirmation({
    required String eyebrow,
    required String title,
    required String message,
    required String confirmLabel,
    IconData icon = Icons.warning_amber_rounded,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.of(dialogContext).pop(false);
        },
        child: DebrifyTvSpotlightDialog(
          eyebrow: eyebrow,
          title: title,
          subtitle: message,
          icon: icon,
          maxWidth: 580,
          child: const SizedBox.shrink(),
          actions: [
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Cancel',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            DebrifyTvDialogButton(
              label: confirmLabel,
              icon: danger ? Icons.delete_outline_rounded : Icons.check_rounded,
              tone: danger
                  ? DebrifyTvDialogButtonTone.danger
                  : DebrifyTvDialogButtonTone.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _handleDeleteChannel(DebrifyTvChannel channel) async {
    // Set busy immediately to block any other interactions
    setState(() {
      _isBusy = true;
    });

    final confirmed = await _showDebrifyTvConfirmation(
      eyebrow: 'Channel library · destructive action',
      title: 'Delete ${channel.name}?',
      message:
          'This removes the channel, its saved keywords, and its cached title pool. This cannot be undone.',
      confirmLabel: 'Delete channel',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );

    // Wait for TWO frames to ensure UI has fully updated and touch events are processed
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (confirmed == true && mounted) {
      await _deleteChannel(channel.id);
      _showSnack('Channel deleted', color: Colors.orange);
    }

    // Release busy state
    if (mounted) {
      setState(() {
        _isBusy = false;
      });
    }
  }


  Future<void> _createOrUpdateChannel(
    DebrifyTvChannel channel, {
    required bool isEdit,
  }) async {
    final normalizedKeywords = _cacheWarmer.normalizedKeywords(channel.keywords);
    if (normalizedKeywords.isEmpty) {
      _showSnack(
        'Add at least one keyword before saving.',
        color: Colors.orange,
      );
      return;
    }

    debugPrint(
      'DebrifyTV: ${isEdit ? 'Updating' : 'Creating'} channel "${channel.name}" with ${normalizedKeywords.length} keyword(s): ${normalizedKeywords.join(', ')}',
    );

    final int estimatedSeconds = _cacheWarmer.estimatedWarmDurationSeconds(
      normalizedKeywords.length,
      totalKeywordUniverse: normalizedKeywords.length,
    );
    bool progressShown = false;
    void ensureProgressDialog({int? countdownSeconds}) {
      if (!progressShown) {
        _showChannelCreationDialog(
          channel.name,
          countdownSeconds: countdownSeconds ?? estimatedSeconds,
        );
        progressShown = true;
      }
    }

    try {
      final baseline = isEdit ? await _cacheWarmer.ensureCacheEntry(channel.id) : null;
      if (normalizedKeywords.length > _maxChannelKeywords) {
        _showSnack(
          'Channels support up to $_maxChannelKeywords keywords. Remove some and try again.',
          color: Colors.orange,
        );
        debugPrint(
          'DebrifyTV: Aborting save for "${channel.name}" – keyword cap exceeded.',
        );
        return;
      }

      final workingEntry = await _cacheWarmer.buildWorkingCacheForSave(
        channel: channel,
        normalizedKeywords: normalizedKeywords,
        isEdit: isEdit,
        baseline: baseline,
        ensureProgressDialog: ensureProgressDialog,
      );

      final entry = workingEntry;
      if (entry == null) {
        _showSnack(
          'Failed to build channel cache. Please try again.',
          color: Colors.red,
        );
        return;
      }

      if (!mounted) {
        return;
      }

      if (!entry.isReady ||
          entry.torrents.length < _minimumTorrentsForChannel) {
        final message = entry.isReady
            ? 'Need at least $_minimumTorrentsForChannel torrents to save this channel. Try different keywords.'
            : (entry.errorMessage ??
                  'Unable to find torrents for these keywords. Try again later.');

        debugPrint(
          'DebrifyTV: Cache validation failed for "${channel.name}" – ready=${entry.isReady}, torrents=${entry.torrents.length}.',
        );

        if (isEdit && baseline != null) {
          setState(() {
            _channelCache[channel.id] = baseline;
            _spotlightStats.remove(channel.id);
          });
          _refreshSpotlightStatsIfFocused(channel.id);
          await DebrifyTvCacheService.saveEntry(baseline);
        } else {
          setState(() {
            _channelCache.remove(channel.id);
            _spotlightStats.remove(channel.id);
          });
          await DebrifyTvCacheService.removeEntry(channel.id);
        }

        _showSnack(message, color: Colors.orange);
        return;
      }

      final updatedChannel = channel.copyWith(updatedAt: DateTime.now());

      final displayChannel = updatedChannel.copyWith(
        keywords: const <String>[],
      );

      setState(() {
        final index = _channels.indexWhere((c) => c.id == displayChannel.id);
        if (index == -1) {
          _channels = <DebrifyTvChannel>[..._channels, displayChannel];
        } else {
          final next = List<DebrifyTvChannel>.from(_channels);
          next[index] = displayChannel;
          _channels = next;
        }
        _channelCache[displayChannel.id] = entry;
        _spotlightStats.remove(displayChannel.id);
      });

      await DebrifyTvRepository.instance.upsertChannel(
        updatedChannel.toRecord(),
      );
      await DebrifyTvCacheService.saveEntry(entry);
      await _loadChannels();
      // Memo removal alone would leave the stage on its placeholder: only a
      // focus MOVE computes, and editing from the stage doesn't move focus.
      _refreshSpotlightStatsIfFocused(displayChannel.id);

      final successMsg = isEdit
          ? 'Channel "${updatedChannel.name}" updated'
          : 'Channel "${updatedChannel.name}" saved';
      _showSnack(successMsg, color: Colors.green);
      debugPrint(
        'DebrifyTV: $successMsg (torrents cached: ${entry.torrents.length})',
      );
    } catch (e) {
      debugPrint('DebrifyTV: Channel creation failed for ${channel.name}: $e');
      _showSnack(
        'Failed to build channel cache. Please try again.',
        color: Colors.red,
      );
    } finally {
      if (progressShown) {
        _closeProgressDialog();
      }
    }
  }

  /// [leadWith] (the Spotlight stage's play-one-title): that torrent plays
  /// FIRST, with the rest of the shuffled selection behind it. NEVER a
  /// single-element queue — the pick may not be cached at the provider, and
  /// a one-item queue has nothing to fall back to, which would make a
  /// deliberate choice fail exactly where Tune in would have succeeded.
  Future<void> _watchChannel(
    DebrifyTvChannel channel, {
    CachedTorrent? leadWith,
  }) async {
    debugPrint('🎬 [WATCH] Starting for channel: ${channel.name}');
    _qualityFallbackNotified = false;
    _cacheWarmer.resetSizeFilterSession();

    final keywords = await _getChannelKeywords(channel.id);
    if (keywords.isEmpty) {
      debugPrint('❌ [WATCH] No keywords');
      MainPageBridge.notifyAutoLaunchFailed('Channel has no keywords');
      _showSnack('Channel has no keywords yet', color: Colors.orange);
      return;
    }
    debugPrint('✅ [WATCH] Keywords: ${keywords.length}');

    await _syncProviderAvailability();
    final bool providerReady = _isProviderSelectable(_playbackSettings.provider);
    if (!providerReady) {
      debugPrint('❌ [WATCH] Provider not ready: $_playbackSettings.provider');
      MainPageBridge.notifyAutoLaunchFailed('Provider not configured');
      final providerName = _providerDisplay(_playbackSettings.provider);
      _showSnack(
        'Enable $providerName in Settings to watch this channel',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Provider ready: $_playbackSettings.provider');

    final cacheEntry = await _cacheWarmer.ensureCacheEntry(channel.id);
    if (cacheEntry == null) {
      debugPrint('❌ [WATCH] Cache entry is null');
      MainPageBridge.notifyAutoLaunchFailed('Cache entry not found');
      _showSnack(
        'Channel cache not found. Edit the channel to rebuild it.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache entry loaded, status: ${cacheEntry.status}');

    if (!cacheEntry.isReady) {
      debugPrint('❌ [WATCH] Cache not ready, status: ${cacheEntry.status}');
      MainPageBridge.notifyAutoLaunchFailed(
        'Cache not ready: ${cacheEntry.status}',
      );
      final message =
          cacheEntry.errorMessage ??
          'Channel cache failed to build. Try editing and saving again.';
      _showSnack(message, color: Colors.orange);
      return;
    }

    if (cacheEntry.torrents.isEmpty) {
      debugPrint('❌ [WATCH] Cache has no torrents');
      MainPageBridge.notifyAutoLaunchFailed('Cache has no torrents');
      _showSnack(
        'No torrents cached yet. Try editing the channel keywords.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache has ${cacheEntry.torrents.length} torrents');

    final previousKeywords = _keywordsController.text;

    final int resolvedChannelNumber = _resolveChannelNumber(channel);

    setState(() {
      _currentWatchingChannelId = channel.id; // Track for channel switching
    });
    _keywordsController.text = keywords.join(', ');

    final normalizedKeywords = _cacheWarmer.normalizedKeywords(keywords);
    final playbackSelection = _cacheWarmer.selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );
    if (leadWith != null) {
      // The chosen title to the front; behaviour after it ends is unchanged.
      _cacheWarmer.prependLeadTorrent(
        playbackSelection: playbackSelection,
        leadWith: leadWith,
        pool: cacheEntry.torrents,
      );
    }
    final cachedTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    debugPrint(
      '✅ [WATCH] Selected ${cachedTorrents.length} torrents for playback',
    );

    switch (MagicTvDispatch.watchId(_playbackSettings.provider)) {
      case CloudProviderId.torbox:
        debugPrint('🎬 [WATCH] Launching Torbox flow...');
        await _torboxWatch.watchTorboxWithCachedTorrents(
          cachedTorrents,
          channelName: channel.name,
          channelId: channel.id,
          channelNumber: resolvedChannelNumber,
        );
      case CloudProviderId.pikpak:
        debugPrint('🎬 [WATCH] Launching PikPak flow...');
        await _pikpakWatch.watchPikPakWithCachedTorrents(
          cachedTorrents,
          channelName: channel.name,
          channelId: channel.id,
          channelNumber: resolvedChannelNumber,
        );
      case CloudProviderId.premiumize:
        debugPrint('🎬 [WATCH] Launching Premiumize flow...');
        await _premiumizeWatch.watchPremiumizeWithCachedTorrents(
          cachedTorrents,
          channelName: channel.name,
          channelId: channel.id,
          channelNumber: resolvedChannelNumber,
        );
      case CloudProviderId.alldebrid:
        debugPrint('🎬 [WATCH] Launching AllDebrid flow...');
        // AllDebrid channel playback. Mirrors the Real-Debrid cached flow
        // (sequential add-and-probe, no cache-check API) but resolves each candidate
        // through AllDebrid's `ready`-flag add (no polling) and lazily unlocks links
        // on demand. The background prefetcher keeps upcoming items prepared.
        await runCachedLockedWatch(
          _watchBindings,
          cachedTorrents,
          provider: CachedLockedProvider.allDebrid,
          applyNsfwFilter: channel.avoidNsfw || _viewerForcesNsfw,
          channelName: channel.name,
          channelId: channel.id,
          channelNumber: resolvedChannelNumber,
        );
      case CloudProviderId.debrid:
        debugPrint('🎬 [WATCH] Launching RealDebrid flow...');
        await runCachedLockedWatch(
          _watchBindings,
          cachedTorrents,
          provider: CachedLockedProvider.realDebrid,
          applyNsfwFilter: channel.avoidNsfw || _viewerForcesNsfw,
          channelName: channel.name,
          channelId: channel.id,
          channelNumber: resolvedChannelNumber,
        );
    }

    if (!mounted) {
      return;
    }

    _keywordsController.text = previousKeywords;
  }






  Future<bool> _launchTorboxOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) => _channelSwitch.launchTorboxOnAndroidTv(firstStream: firstStream, requestNext: requestNext, channelName: channelName, showChannelNameOverride: showChannelNameOverride, channelId: channelId, channelNumber: channelNumber, channelDirectory: channelDirectory);

  /// Handle channel switching on Android TV - cycles to next channel with looping
  Future<Map<String, dynamic>?> _requestNextChannel() => _channelSwitch.requestNextChannel();

  Future<Map<String, dynamic>?> _requestChannelById(String channelId) => _channelSwitch.requestChannelById(channelId);

  int _resolveChannelNumber(DebrifyTvChannel channel) => _channelSwitch.resolveChannelNumber(channel);

  List<Map<String, dynamic>> _androidTvChannelMetadata({
    String? activeChannelId,
  }) => _channelSwitch.androidTvChannelMetadata(activeChannelId: activeChannelId);

  Future<bool> _launchRealDebridOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) => _channelSwitch.launchRealDebridOnAndroidTv(firstStream: firstStream, requestNext: requestNext, channelName: channelName, showChannelNameOverride: showChannelNameOverride, channelId: channelId, channelNumber: channelNumber, channelDirectory: channelDirectory);



  Future<bool> _launchPikPakOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) => _channelSwitch.launchPikPakOnAndroidTv(firstStream: firstStream, requestNext: requestNext, channelName: channelName, showChannelNameOverride: showChannelNameOverride, channelId: channelId, channelNumber: channelNumber, channelDirectory: channelDirectory);

  void _showChannelCreationDialog(String channelName, {int? countdownSeconds}) {
    if (_progressOpen || !mounted) {
      return;
    }
    _progress.value = [];
    _progressOpen = true;
    Future.microtask(() {
      if (!mounted || !_progressOpen) {
        return;
      }
      // showGeneralDialog skips InheritedTheme capture; snapshot this frozen
      // screen's themes so the dialog stays legacy under any app theme.
      final capturedThemes = captureAppThemes(context);
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          return capturedThemes.wrap(
            ChannelCreationDialog(
              channelName: channelName,
              countdownSeconds: countdownSeconds,
              onReady: (dialogCtx) {
                _progressSheetContext = dialogCtx;
              },
            ),
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
      );
    });
  }

  void _showCachedPlaybackDialog() {
    debugPrint(
      '[MagicTV] _showCachedPlaybackDialog called, _progressOpen=$_progressOpen, mounted=$mounted, _watchCancelled=$_watchCancelled',
    );
    if (_progressOpen || !mounted) {
      return;
    }

    // Reset cancellation flag for new playback session.
    // This must happen before the auto-launch check so that playback can proceed
    // even when the dialog is skipped (auto-launch has its own overlay UI).
    _watchCancelled = false;
    debugPrint(
      '[MagicTV] _showCachedPlaybackDialog: Reset _watchCancelled to false',
    );

    _progress.value = [];
    _progressOpen = true;
    Future.microtask(() {
      if (!mounted || !_progressOpen) {
        return;
      }
      // Same snapshot rule as the channel-creation dialog above.
      final capturedThemes = captureAppThemes(context);
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          // Use pageBuilder context directly - simpler and avoids race conditions
          _progressSheetContext = ctx;
          return capturedThemes.wrap(
            CachedLoadingDialog(
              onCancel: () {
                debugPrint('[MagicTV] onCancel callback triggered');
                _cancelActiveWatch(dialogContext: ctx);
              },
            ),
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
      );
    });
  }

  Future<void> _playNextFromQueue() async {
    if (_isBusy) return;
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add your Real Debrid API key in Settings first!',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Finding a playable stream...';
    });

    try {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        final magnetLink = 'magnet:?xt=urn:btih:${next.infohash}';
        try {
          final result = await DebridService.addTorrentToDebridPreferVideos(
            apiKey,
            magnetLink,
          );
          final videoUrl = result['downloadLink'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _status = 'Playing: ${next.name}';
            });

            if (await _handOffToExternalPlayer(videoUrl, next.name)) {
              break;
            }

            // Hide auto-launch overlay before launching player
            MainPageBridge.notifyPlayerLaunching();

            await Navigator.of(context).push(
              FrozenLegacyPageRoute(
                builder: (_) => VideoPlayerScreen(
                  videoUrl: videoUrl,
                  title: next.name,
                  startFromRandom: _playbackSettings.quickStartRandom,
                  randomStartMaxPercent: _playbackSettings.quickRandomStartPercent,
                  hideSeekbar: _playbackSettings.quickHideSeekbar,
                  showChannelName: _playbackSettings.quickShowChannelName,
                  channelName: null,
                  channelNumber: null,
                  showVideoTitle: _playbackSettings.quickShowVideoTitle,
                  hideOptions: _playbackSettings.quickHideOptions,
                ),
              ),
            );
            break;
          }
        } catch (_) {
          // Skip not readily available / failed items and continue
          continue;
        }
      }

      if (_queue.isEmpty) {
        // Close popup and show user-friendly message
        if (_progressOpen && _progressSheetContext != null) {
          Navigator.of(_progressSheetContext!).pop();
          _progressOpen = false;
          _progressSheetContext = null;
        }

        if (mounted) {
          setState(() {
            _isBusy = false;
            _status = 'No playable torrents found. Try different keywords.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'All torrents failed to process. Try different keywords or check your internet connection.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _status = 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (_debrifyTvStyle == 'spotlight') {
      return SpotlightLayout(
        view: _buildSpotlightView(),
        bottomInset: bottomInset,
        entryFocusNode: _quickPlayFocusNode,
      );
    }
    // The historical layout, byte-identical under `grid` — the branch calls
    // it unchanged, never a re-implementation.
    return _buildTvGridLayout(bottomInset);
  }

  /// The Spotlight layout's window onto this state. Paint only: every
  /// callback is an existing method, every playback path is shared verbatim.
  DebrifyTvView _buildSpotlightView() {
    return DebrifyTvView(
      channels: _channels,
      favoriteIds: _favoriteChannelIds,
      railHealth: _spotlightRailHealth,
      stats: _spotlightFocusedId == null
          ? null
          : _spotlightStats[_spotlightFocusedId],
      busy: _isBusy,
      onQuickPlay: _showQuickPlayDialog,
      onAdd: _handleAddChannel,
      onImport: _importExport.handleImportChannels,
      onExport: _importExport.handleExportChannels,
      onSettings: _showGlobalSettingsDialog,
      onWatch: _watchChannel,
      onEdit: _handleEditChannel,
      onShare: _importExport.handleShareChannelAsMagnet,
      onDelete: _handleDeleteChannel,
      onToggleFavorite: _toggleChannelFavorite,
      onChannelFocused: _onSpotlightChannelFocused,
      onWatchOne: (channel, torrent) =>
          _watchChannel(channel, leadWith: torrent),
    );
  }

  Future<void> _loadSpotlightRailHealth() async {
    final health = await DebrifyTvCacheService.loadRailHealth();
    if (!mounted) return;
    setState(() => _spotlightRailHealth = health);
  }

  /// Focus moved to a channel row. The stage's numbers need a per-row name
  /// classify over the pool, so: debounced (a DPAD glide crosses many rows),
  /// computed only for the channel that focus RESTS on, and memoised — a
  /// pool does not change while you are looking at it.
  void _onSpotlightChannelFocused(DebrifyTvChannel channel) {
    // Cancel FIRST, unconditionally: a memo hit must still kill a pending
    // timer for the previous channel, or gliding B→A (A memoised) classifies
    // B off-focus.
    _spotlightStatsDebounce?.cancel();
    _spotlightFocusedId = channel.id;
    // Rebuild NOW either way. On a miss the view's stats go null and the
    // stage draws placeholders — never another channel's numbers, which a
    // plate press would turn into another channel's torrent.
    setState(() {});
    if (_spotlightStats.containsKey(channel.id)) return;
    _spotlightStatsDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _computeSpotlightStats(channel),
    );
  }

  /// Wipe every memoised stage snapshot and recompute the focused channel's.
  /// For when the numbers' INPUTS change — the quality filter — rather than
  /// one channel's pool.
  void _invalidateSpotlightStats() {
    if (_debrifyTvStyle != 'spotlight') return;
    _spotlightStats.clear();
    _refreshSpotlightStatsIfFocused(_spotlightFocusedId);
  }

  /// A channel's pool (or the filter over it) changed; if it is the one the
  /// stage is showing, schedule fresh numbers — memo removal alone leaves
  /// the stage on its placeholder forever, since only a focus MOVE computes.
  void _refreshSpotlightStatsIfFocused(String? channelId) {
    if (_debrifyTvStyle != 'spotlight' || channelId == null) return;
    if (_spotlightFocusedId != channelId) return;
    final channel = _channels.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null) _onSpotlightChannelFocused(channel);
  }

  Future<void> _computeSpotlightStats(DebrifyTvChannel channel) async {
    if (!mounted || _spotlightStats.containsKey(channel.id)) return;
    final entry = await _cacheWarmer.ensureCacheEntry(channel.id);
    // Focus may have moved during the read; bail rather than classify an
    // off-focus pool. The entry stays in _channelCache, so a return visit
    // pays only the classify.
    if (!mounted || _spotlightFocusedId != channel.id) return;
    final stats = _cacheWarmer.classifySpotlightStats(
      channelId: channel.id,
      entry: entry,
      tierForName: qualityTierForName,
    );
    setState(() {
      _spotlightStats[channel.id] = stats;
    });
  }

  void _toggleChannelSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _channelSearchFocusNode.requestFocus();
          }
        });
      } else {
        _channelSearchController.clear();
        _channelSearchTerm = '';
      }
    });
  }

  void _clearChannelSearchAndRefocus() {
    _channelSearchController.clear();
    setState(() {
      _channelSearchTerm = '';
    });
    _channelSearchFocusNode.requestFocus();
  }

  void _focusBelowChannelSearch() {
    final fieldContext = _channelSearchFocusNode.context;
    if (fieldContext != null) {
      FocusScope.of(fieldContext).nextFocus();
    }
  }

  void _handleTopMenuAction(_DebrifyTvTopMenuAction action) {
    switch (action) {
      case _DebrifyTvTopMenuAction.import:
        _importExport.handleImportChannels();
        break;
      case _DebrifyTvTopMenuAction.export:
        _importExport.handleExportChannels();
        break;
      case _DebrifyTvTopMenuAction.add:
        _handleAddChannel();
        break;
      case _DebrifyTvTopMenuAction.deleteAll:
        _importExport.handleDeleteAllChannels();
        break;
      case _DebrifyTvTopMenuAction.settings:
        _showGlobalSettingsDialog();
        break;
    }
  }

  Widget _buildTopActionButton({
    required FocusNode focusNode,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color activeColor,

    /// Defaults to the surface's resting control fill (`controlBg`). Nullable
    /// rather than a const default because a token is not a constant.
    Color? inactiveColor,
    bool isActive = false,
    FocusNode? leftFocusNode,
    FocusNode? rightFocusNode,
    bool leftToSidebar = false,
    bool upToSearch = false,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowLeft) {
          if (leftToSidebar) {
            MainPageBridge.focusTvSidebar?.call();
          } else {
            leftFocusNode?.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          rightFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (upToSearch && _showSearchBar) {
            _channelSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          onPressed?.call();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final app = AppThemeScope.of(context);
          final tv = app.debrifyTv;
          final disabled = onPressed == null;
          final focused = focusNode.hasFocus;
          final highlighted = !disabled && (focused || isActive);

          return Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  // LEFT LITERAL: the disabled greys. No role holds
                  // `Colors.grey` / grey-at-0.3, and a disabled tone is not
                  // one of this surface's fills.
                  color: disabled
                      ? Colors.grey.withValues(alpha: 0.3)
                      : (focused
                            ? activeColor
                            : (inactiveColor ?? tv.controlBg)),
                  borderRadius: app.shape.br(20),
                  border: focused && !disabled
                      ? Border.all(
                          color: tv.focusRing.withValues(alpha: 0.6),
                          width: 2,
                        )
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: disabled
                      ? Colors.grey
                      : (highlighted
                            ? app.core.tx
                            : app.core.tx.withValues(alpha: 0.5)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopMenuButton() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final itemStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? tv.textFaint
            : states.contains(WidgetState.focused)
            ? app.inkOn(app.core.tx)
            : tv.textDim,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? app.core.tx
            : Colors.transparent,
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: app.shape.br(12)),
      ),
    );
    return Focus(
      focusNode: _channelMenuFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (_channelMenuController.isOpen) {
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            _channelMenuController.close();
            _channelMenuFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          _channelSearchButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_showSearchBar) {
            _channelSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          _channelMenuController.open();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _channelMenuFocusNode,
        builder: (context, _) => MenuAnchor(
          controller: _channelMenuController,
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(tv.noticeBg),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(18),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: app.shape.br(18),
                side: BorderSide(color: tv.hairline),
              ),
            ),
          ),
          menuChildren: [
            MenuItemButton(
              autofocus: true,
              style: itemStyle,
              leadingIcon: const Icon(Icons.cloud_download_rounded),
              onPressed: _isBusy
                  ? null
                  : () => _handleTopMenuAction(_DebrifyTvTopMenuAction.import),
              child: const Text('Import'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.folder_zip_rounded),
              onPressed: _isBusy || _channels.isEmpty
                  ? null
                  : () => _handleTopMenuAction(_DebrifyTvTopMenuAction.export),
              child: const Text('Export Channels'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.add_rounded),
              onPressed: _isBusy
                  ? null
                  : () => _handleTopMenuAction(_DebrifyTvTopMenuAction.add),
              child: const Text('Add Channel'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.delete_outline_rounded),
              onPressed: _isBusy || _channels.isEmpty
                  ? null
                  : () =>
                        _handleTopMenuAction(_DebrifyTvTopMenuAction.deleteAll),
              child: const Text('Delete All'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.settings_rounded),
              onPressed: () =>
                  _handleTopMenuAction(_DebrifyTvTopMenuAction.settings),
              child: const Text('Settings'),
            ),
          ],
          builder: (context, controller, child) {
            final focused = _channelMenuFocusNode.hasFocus;

            return Tooltip(
              message: 'Options',
              child: GestureDetector(
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: focused ? tv.fillStrong : tv.controlBg,
                    borderRadius: app.shape.br(20),
                    border: focused
                        ? Border.all(
                            color: tv.focusRing.withValues(alpha: 0.6),
                            width: 2,
                          )
                        : null,
                  ),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: focused
                        ? app.core.tx
                        : app.core.tx.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopActions() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTopActionButton(
          focusNode: _quickPlayFocusNode,
          icon: Icons.play_arrow_rounded,
          tooltip: 'Play',
          onPressed: _isBusy ? null : _showQuickPlayDialog,
          activeColor: tv.fillStrong,
          leftToSidebar: true,
          rightFocusNode: _channelSearchButtonFocusNode,
        ),
        const SizedBox(width: 10),
        _buildTopActionButton(
          focusNode: _channelSearchButtonFocusNode,
          icon: Icons.search_rounded,
          tooltip: _showSearchBar ? 'Close search' : 'Search channels',
          onPressed: _toggleChannelSearchBar,
          activeColor: tv.fillStrong,
          isActive: _showSearchBar || _channelSearchTerm.isNotEmpty,
          leftFocusNode: _quickPlayFocusNode,
          rightFocusNode: _channelMenuFocusNode,
          upToSearch: true,
        ),
        const SizedBox(width: 10),
        _buildTopMenuButton(),
      ],
    );
  }

  // Grid Layout for all devices (responsive)
  Widget _buildTvGridLayout(double bottomInset) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final searchTerm = _channelSearchTerm.trim().toLowerCase();
    final filteredChannels = searchTerm.isEmpty
        ? _channels
        : _channels
              .where(
                (channel) => channel.name.toLowerCase().contains(searchTerm),
              )
              .toList();

    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive padding: smaller on mobile, larger on TV/tablet
    final horizontalPadding = screenWidth < 600 ? 16.0 : 40.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24,
        horizontalPadding,
        24 + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered top controls: Play, Search, and overflow.
          _buildTopActions(),
          // Search field for TV (only show when toggled)
          if (_showSearchBar) ...[
            const SizedBox(height: 16),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _handleChannelSearchBarBack,
              child: TvTextField(
                focusNode: _channelSearchFocusNode,
                controller: _channelSearchController,
                style: TextStyle(color: app.core.tx),
                // Shared TV shell/keyboard chrome — settings.accent, with the
                // keyboard's own panel ground and ink.
                accent: app.settings.accent,
                keyboardGround: app.youtube.keyboardPanel,
                keyboardInk: app.core.tx,
                keyboardInkOnAccent: app.inkOn(app.settings.accent),
                onLeftArrow: () => MainPageBridge.focusTvSidebar?.call(),
                onRightArrow: () {
                  if (_channelSearchController.text.isNotEmpty) {
                    _channelSearchClearFocusNode.requestFocus();
                  }
                },
                onUpArrow: () => _channelSearchButtonFocusNode.requestFocus(),
                onSubmitted: (_) => _focusBelowChannelSearch(),
                onDownArrow: _focusBelowChannelSearch,
                decoration: InputDecoration(
                  hintText: 'Search channels...',
                  hintStyle: TextStyle(
                    color: app.core.tx.withValues(alpha: 0.3),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: app.core.tx.withValues(alpha: 0.35),
                  ),
                  suffixIcon: _channelSearchTerm.isNotEmpty
                      ? Focus(
                          focusNode: _channelSearchClearFocusNode,
                          skipTraversal: true,
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.arrowLeft) {
                              _channelSearchFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowRight) {
                              _channelMenuFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _channelSearchButtonFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (isActivateKey(key) ||
                                key == LogicalKeyboardKey.space) {
                              _clearChannelSearchAndRefocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (context) {
                              final ink = AppThemeScope.of(context).core.tx;
                              final focused = Focus.of(context).hasFocus;
                              return Container(
                                decoration: focused
                                    ? BoxDecoration(
                                        borderRadius: app.shape.br(20),
                                        border: Border.all(
                                          color: ink.withValues(alpha: 0.3),
                                          width: 1.5,
                                        ),
                                      )
                                    : null,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: focused
                                        ? ink
                                        : ink.withValues(alpha: 0.5),
                                  ),
                                  onPressed: _clearChannelSearchAndRefocus,
                                ),
                              );
                            },
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide(
                      // The search field's focused border is `fillStrong` by
                      // design — see the token's own doc.
                      color: tv.fillStrong,
                      width: 1,
                    ),
                  ),
                  filled: true,
                  fillColor: app.core.tx.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _channelSearchTerm = value;
                  });
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Favorite channels section (only shows if there are favorites)
          _buildFavoriteChannelsSection(),
          // "All" section header (only show when there are favorites to distinguish)
          if (_favoriteChannelIds.isNotEmpty && filteredChannels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 18,
                    color: app.core.tx.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All Channels',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: app.core.tx.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          // Channel grid (responsive)
          Expanded(
            child: filteredChannels.isEmpty
                ? _buildTvEmptyState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Responsive grid: 2 cols on mobile, 3 on tablet, 4 on TV/desktop
                      final width = constraints.maxWidth;
                      int crossAxisCount;
                      double spacing;
                      double childAspectRatio;

                      if (width < 500) {
                        crossAxisCount = 2;
                        spacing = 12;
                        childAspectRatio = 1.4;
                      } else if (width < 800) {
                        crossAxisCount = 3;
                        spacing = 16;
                        childAspectRatio = 1.45;
                      } else {
                        crossAxisCount = 4;
                        spacing = 24;
                        childAspectRatio = 1.5;
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount:
                            filteredChannels.length +
                            1, // +1 for "Add Channel" card
                        itemBuilder: (context, index) {
                          if (index == filteredChannels.length) {
                            // "Add Channel" card at the end
                            return KeyedSubtree(
                              key: const ValueKey('add_channel_card'),
                              child: _buildTvAddChannelCard(),
                            );
                          }
                          final channel = filteredChannels[index];
                          return KeyedSubtree(
                            key: ValueKey('channel_${channel.id}'),
                            child: _buildTvChannelCard(channel),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TV Empty State
  Widget _buildTvEmptyState() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv_rounded, size: 120, color: app.core.tx.withAlpha(51)),
          const SizedBox(height: 24),
          Text(
            'No channels yet',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: tv.textDim,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Import channels or create your first channel to get started',
            style: TextStyle(fontSize: 16, color: tv.textFaint),
          ),
          const SizedBox(height: 32),
          TvFocusableButton(
            onPressed: _handleAddChannel,
            icon: Icons.add_rounded,
            label: 'Add Channel',
            backgroundColor: tv.accent,
            width: 200,
          ),
        ],
      ),
    );
  }

  // Favorite Channels Section (horizontal row)
  Widget _buildFavoriteChannelsSection() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    // Get favorite channels from the channels list
    final favoriteChannels = _channels
        .where((channel) => _favoriteChannelIds.contains(channel.id))
        .toList();

    // Don't show if no favorites
    if (favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.star_rounded,
                size: 18,
                color: tv.favorite.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'Favorites',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: app.core.tx.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Horizontal scrolling favorites
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: favoriteChannels.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = favoriteChannels[index];
              return _buildFavoriteChannelCard(channel);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Favorite Channel Card (compact horizontal card)
  Widget _buildFavoriteChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return SizedBox(
      width: 160,
      height: 100,
      child: TvFocusableCard(
        onPressed: () => _watchChannel(channel),
        onLongPress: () => _showTvChannelOptionsMenu(channel),
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Channel number badge (smaller)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tv.accent,
                      borderRadius: app.shape.br(6),
                    ),
                    child: Text(
                      'CH ${channel.channelNumber > 0 ? channel.channelNumber : _channels.indexOf(channel) + 1}',
                      style: TextStyle(
                        color: app.inkOn(tv.accent),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Channel name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      channel.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: app.core.tx,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Star indicator
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.star_rounded,
                size: 14,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TV Channel Card (Grid item)
  Widget _buildTvChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final isFavorited = _favoriteChannelIds.contains(channel.id);

    return TvFocusableCard(
      onPressed: () {
        _watchChannel(channel);
      },
      onLongPress: () {
        _showTvChannelOptionsMenu(channel);
      },
      showLongPressHint: _isAndroidTv, // Only show hint on Android TV
      child: Stack(
        children: [
          // Favorite star indicator (top-left)
          if (isFavorited)
            Positioned(
              top: 6,
              left: 6,
              child: Icon(
                Icons.star_rounded,
                size: 20,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          // Main card content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tv.accent,
                    borderRadius: app.shape.br(8),
                  ),
                  child: Text(
                    'CH ${channel.channelNumber > 0 ? channel.channelNumber : _channels.indexOf(channel) + 1}',
                    style: TextStyle(
                      color: app.inkOn(tv.accent),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Channel name - centered
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    channel.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: app.core.tx,
                      height: 1.2,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 3-dot menu for non-Android TV devices
          if (!_isAndroidTv)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: app.shape.br(6),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    // Sits on the black plate above, so it takes glass ink.
                    color: app.onGlass.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Options',
                  color: tv.noticeBg,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: app.shape.br(18),
                    side: BorderSide(color: tv.hairline),
                  ),
                  onSelected: (value) {
                    if (value == 'favorite') {
                      _toggleChannelFavorite(channel);
                    } else if (value == 'edit') {
                      _handleEditChannel(channel);
                    } else if (value == 'share') {
                      _importExport.handleShareChannelAsMagnet(channel);
                    } else if (value == 'delete') {
                      _handleDeleteChannel(channel);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(
                        children: [
                          Icon(
                            isFavorited
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 18,
                            color: tv.favorite,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isFavorited
                                ? 'Remove Favorite'
                                : 'Add to Favorites',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Share Channel'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // TV Channel Options Menu (Edit/Delete)
  Future<void> _showTvChannelOptionsMenu(DebrifyTvChannel channel) async {
    final isFavorited = _favoriteChannelIds.contains(channel.id);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return DebrifyTvSpotlightDialog(
          eyebrow:
              'Channel actions · ${channel.channelNumber.toString().padLeft(2, '0')}',
          title: channel.name,
          subtitle: 'Manage this channel without leaving the current view.',
          icon: Icons.tune_rounded,
          maxWidth: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DebrifyTvDialogOptionCard(
                autofocus: true,
                icon: isFavorited
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                title: isFavorited ? 'Remove pin' : 'Pin channel',
                subtitle: isFavorited
                    ? 'Return this channel to the main list.'
                    : 'Keep this channel at the top of the rail.',
                tag: isFavorited ? 'Pinned' : 'Pin',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _toggleChannelFavorite(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.edit_rounded,
                title: 'Edit channel',
                subtitle: 'Change its name, keywords, or content filter.',
                tag: 'Edit',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _handleEditChannel(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.share_rounded,
                title: 'Share channel',
                subtitle: 'Create a portable Debrify link for this pool.',
                tag: 'Link',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _importExport.handleShareChannelAsMagnet(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.delete_outline_rounded,
                title: 'Delete channel',
                subtitle: 'Remove this channel and its cached title pool.',
                tag: 'Careful',
                danger: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _handleDeleteChannel(channel);
                },
              ),
            ],
          ),
          actions: [
            DebrifyTvDialogButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  // TV "Add Channel" Card
  Widget _buildTvAddChannelCard() {
    final tv = AppThemeScope.of(context).debrifyTv;
    return TvFocusableCard(
      onPressed: _handleAddChannel,
      child: SizedBox(
        height: double.infinity, // Ensures consistent height
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: tv.fillWeak,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, size: 32, color: tv.textDim),
            ),
            const SizedBox(height: 12),
            Text(
              'Add Channel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tv.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickPlayDialog() async {
    if (_isBusy) {
      return;
    }

    bool avoidNsfw = _playbackSettings.quickAvoidNsfw;
    String? error;
    // Create a separate controller for Quick Play to avoid sharing state with edit dialog
    final TextEditingController controller = TextEditingController();
    final FocusNode keywordFocusNode = FocusNode(
      debugLabel: 'QuickPlayKeywordsField',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final app = AppThemeScope.of(context);
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Quick play · no channel needed',
              title: 'Play anything',
              subtitle:
                  'Enter up to $_quickPlayMaxKeywords search terms. Nothing is saved when playback ends.',
              icon: Icons.play_arrow_rounded,
              maxWidth: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvTextField(
                    controller: controller,
                    autofocus: true,
                    focusNode: keywordFocusNode,
                    textInputAction: TextInputAction.search,
                    // Shared TV shell/keyboard chrome — settings.accent,
                    // with the keyboard's own panel ground and ink.
                    accent: app.settings.accent,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.settings.accent),
                    decoration: const InputDecoration(
                      labelText: 'Keywords',
                      hintText: 'Comma separated keywords',
                    ),
                    onDownArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).nextFocus();
                      }
                    },
                    onUpArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).previousFocus();
                      }
                    },
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchRow(
                    title: 'Avoid NSFW content',
                    subtitle: _viewerForcesNsfw
                        ? 'Always on for this profile'
                        : 'Best-effort filter while searching',
                    value: _viewerForcesNsfw || avoidNsfw,
                    onChanged: (value) {
                      // Role-locked: a child session cannot loosen it.
                      if (_viewerForcesNsfw) return;
                      setDialogState(() => avoidNsfw = value);
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
              actions: [
                DebrifyTvDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                DebrifyTvDialogButton(
                  label: 'Play now',
                  icon: Icons.play_arrow_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () async {
                    final keywords = controller.text.trim();
                    if (keywords.isEmpty) {
                      setDialogState(
                        () => error = 'Enter one or more keywords to continue.',
                      );
                      return;
                    }

                    if (mounted) {
                      setState(() {
                        _playbackSettings.quickStartRandom = _playbackSettings.startRandom;
                        _playbackSettings.quickRandomStartPercent = _playbackSettings.randomStartPercent;
                        _playbackSettings.quickHideSeekbar = _playbackSettings.hideSeekbar;
                        _playbackSettings.quickShowChannelName = _playbackSettings.showChannelName;
                        _playbackSettings.quickShowVideoTitle = _playbackSettings.showVideoTitle;
                        _playbackSettings.quickHideOptions = false; // Always false now
                        _playbackSettings.quickHideBackButton = false; // Always false now
                        _playbackSettings.quickAvoidNsfw = avoidNsfw;
                        _playbackSettings.quickProvider = _playbackSettings.provider;
                      });
                      // Copy keywords from Quick Play controller to main controller for _providerWatch.watch()
                      _keywordsController.text = keywords;
                    }

                    Navigator.of(dialogContext).pop();
                    // Wait for frames to ensure UI has updated and touch events are processed
                    await Future.delayed(const Duration(milliseconds: 100));
                    await WidgetsBinding.instance.endOfFrame;
                    await WidgetsBinding.instance.endOfFrame;
                    if (mounted) {
                      await _providerWatch.watch();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    keywordFocusNode.dispose();
    controller.dispose();
  }

  Future<void> _showGlobalSettingsDialog() => showChannelPlaybackSettings(
    context,
    _playbackSettings,
    rebuildHost: setState,
    invalidateStats: _invalidateSpotlightStats,
    showResetSuccess: () {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset to defaults successful'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    },
    isBusy: () => _isBusy,
    isAndroidTv: () => _isAndroidTv,
    readAvailability: () => MagicTvProvider.availability(
      realDebrid: _rdAvailable,
      torbox: _torboxAvailable,
      pikpak: _pikpakAvailable,
      premiumize: _premiumizeAvailable,
      allDebrid: _allDebridAvailable,
    ),
  );

  Future<Map<String, String>?> _resolveTorboxQueuedFile({
    required Map<String, dynamic> entry,
    required void Function(String message) log,
  }) async {
    final torrentId = entry['torrentId'] as int?;
    final TorboxFile? file = entry['file'] as TorboxFile?;
    final String? title = entry['title'] as String?;
    if (torrentId == null || file == null) {
      return null;
    }
    try {
      final streamUrl = await CloudProviderRegistry.instance.fileDownloadLink(
        torrentId,
        file.id,
      );
      final resolvedTitle = title ?? MagicTvPlayable.torboxDisplayName(file);
      log('➡️ Torbox: streaming $resolvedTitle');
      return {'url': streamUrl, 'title': resolvedTitle};
    } catch (e) {
      log('❌ Torbox stream failed: $e');
      return null;
    }
  }

  Future<TorboxPreparedTorrent?> _prepareTorboxTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final prepared = await CloudProviderRegistry.instance.prepareMagicTv(
      provider: CloudProviderId.torbox.magicTvId,
      request: _magicTvPrepareRequest(candidate, log),
    );
    if (prepared == null) return null;
    return TorboxPreparedTorrent(
      streamUrl: prepared.streamUrl,
      title: prepared.title,
      hasMore: prepared.hasMore,
    );
  }

  Future<PikPakPreparedTorrent?> _preparePikPakTorrent({
    required Torrent candidate,
    required void Function(String message) log,
  }) async {
    final prepared = await CloudProviderRegistry.instance.prepareMagicTv(
      provider: CloudProviderId.pikpak.magicTvId,
      request: _magicTvPrepareRequest(candidate, log),
    );
    if (prepared == null) return null;
    return PikPakPreparedTorrent(
      streamUrl: prepared.streamUrl,
      title: prepared.title,
      hasMore: prepared.hasMore,
    );
  }

  // ── Premiumize helpers ──────────────────────────────────────────────────────

  Future<TorboxCacheWindowResult> _fetchPremiumizeCacheWindow({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  }) async {
    if (apiKey.isEmpty) {
      return TorboxCacheWindowResult(
        cachedTorrents: const [],
        nextCursor: startIndex,
        exhausted: startIndex >= candidates.length,
      );
    }
    const int chunkSize = 100;
    const int maxCalls = 2;

    int cursor = startIndex;
    int calls = 0;
    final List<Torrent> hits = [];

    while (cursor < candidates.length && calls < maxCalls && hits.isEmpty) {
      final int end = min(cursor + chunkSize, candidates.length);
      final List<Torrent> chunk = candidates.sublist(cursor, end);
      cursor = end;

      final List<Torrent> validChunk = chunk
          .where((t) => _normalizeInfohash(t.infohash).isNotEmpty)
          .toList();
      final List<String> hashes = validChunk
          .map((t) => _normalizeInfohash(t.infohash))
          .toList();

      if (hashes.isEmpty) continue;

      calls++;
      final List<bool> cached = await CloudProviderRegistry.instance.checkCache(
        hashes,
      );

      for (int i = 0; i < validChunk.length; i++) {
        if (i < cached.length && cached[i]) {
          hits.add(validChunk[i]);
        }
      }
    }

    return TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: cursor >= candidates.length,
    );
  }

  Future<PremiumizePreparedTorrent?> _preparePremiumizeTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final prepared = await CloudProviderRegistry.instance.prepareMagicTv(
      provider: CloudProviderId.premiumize.magicTvId,
      request: _magicTvPrepareRequest(candidate, log),
    );
    if (prepared == null) return null;
    return PremiumizePreparedTorrent(
      streamUrl: prepared.streamUrl,
      title: prepared.title,
      hasMore: prepared.hasMore,
    );
  }

  MagicTvPrepareRequest _magicTvPrepareRequest(
    Torrent candidate,
    void Function(String message) log,
  ) => MagicTvPrepareRequest(
    torrent: candidate,
    log: log,
    seenKeys: _seenLinkWithTorrentId,
    sizeMatchesBytes: _playbackSettings.tvFilters.sizeMatchesBytes,
    hasSizeFilter: _playbackSettings.tvFilters.hasSize,
    minVideoSizeBytes: _torboxMinVideoSizeBytes,
  );

  MagicTvPrepareRequest _magicTvLockedRequest(
    Torrent candidate, {
    Set<String>? seenKeys,
  }) => MagicTvPrepareRequest(
    torrent: candidate,
    log: (message) => debugPrint(message),
    seenKeys: seenKeys ?? _seenRestrictedLinks,
    sizeMatchesBytes: _playbackSettings.tvFilters.sizeMatchesBytes,
    hasSizeFilter: _playbackSettings.tvFilters.hasSize,
    minVideoSizeBytes: _torboxMinVideoSizeBytes,
  );

  Future<MagicTvLockedBatch?> _resolveRdLockedLinks(
    Torrent candidate, {
    Set<String>? seenKeys,
  }) => CloudProviderRegistry.instance.prepareMagicTvLockedLinks(
    provider: CloudProviderId.debrid.magicTvId,
    request: _magicTvLockedRequest(candidate, seenKeys: seenKeys),
  );




  String _normalizeInfohash(String hash) =>
      ChannelCacheWarmer.normalizeInfohash(hash);

  void _showSnack(String message, {Color color = Colors.blueGrey}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void showSnack(String message, {Color color = Colors.blueGrey}) {
    _showSnack(message, color: color);
  }

  @override
  bool get importExportMounted => mounted;

  @override
  BuildContext get importExportContext => context;

  @override
  bool get isAndroidTv => _isAndroidTv;

  @override
  bool get isBusy => _isBusy;

  @override
  set isBusy(bool value) => _isBusy = value;

  @override
  set status(String value) => _status = value;

  @override
  List<DebrifyTvChannel> get channels => _channels;

  @override
  set channels(List<DebrifyTvChannel> value) => _channels = value;

  @override
  Map<String, DebrifyTvChannelCacheEntry> get channelCache => _channelCache;

  @override
  void applyImportState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void showImportProgress(String title) {
    _showChannelCreationDialog(title);
  }

  @override
  Future<void> reloadImportedChannels() => _loadChannels();

  @override
  Future<void> createImportedTextChannel(DebrifyTvChannel channel) {
    return _createOrUpdateChannel(channel, isEdit: false);
  }

  @override
  Future<bool> confirmDeleteAll({required int channelCount}) {
    return _showDebrifyTvConfirmation(
      eyebrow: 'Channel library · $channelCount channels',
      title: 'Delete every channel?',
      message:
          'This removes all $channelCount channels and every cached title pool. This cannot be undone.',
      confirmLabel: 'Delete all',
      icon: Icons.delete_sweep_outlined,
      danger: true,
    );
  }

  String _formatTorboxError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  // ===================== External player hand-off =====================

  /// Hands one resolved stream to the user's external player when that is
  /// their default, after warning them what external playback costs here.
  ///
  /// Returns true when the caller must abandon its own launch — either the
  /// stream is now playing in another app, or the user backed out of the
  /// warning. False means "carry on unchanged": the in-app player is the
  /// default, or the external launch failed and the built-in player is the
  /// fallback (same policy as [VideoPlayerLauncher.push]).
  ///
  /// Channel rotation dies with the hand-off — nothing outside Debrify can
  /// call back into `requestMagicNext` — so on any outcome that ends the flow
  /// this also stops the prefetcher that exists purely to feed it. A failed
  /// launch leaves the prefetcher running, because the in-app player that
  /// picks the flow back up still wants it.
  Future<bool> _handOffToExternalPlayer(String url, String title) async {
    if (url.isEmpty || !mounted) return false;
    if (!await VideoPlayerLauncher.isExternalPlayerDefault()) return false;
    if (!mounted) return false;

    _closeProgressDialog();
    // The home-screen auto-launch overlay draws above routes, so drop it
    // before the notice or the notice appears underneath it. Only the overlay
    // — firing notifyPlayerLaunching here would stop other screens' trailers
    // for a launch the user may still decline.
    MainPageBridge.hideAutoLaunchOverlay?.call();
    if (!mounted) return false;

    // Backing out must not silently fall through to the in-app player — that
    // is the very thing the user chose against — so a decline reports
    // "handled" too and every caller stops. Deliberately without touching
    // _watchCancelled: that flag is only reset by the quick-play and cached-
    // dialog entry points, so setting it here would leave channel plays
    // stuck-cancelled on the next attempt.
    if (!await ExternalPlayerNoticeDialog.confirm(context)) {
      await _queuePrefetcher.stopPrefetch();
      return true;
    }
    if (!mounted) return true;

    final launched = await VideoPlayerLauncher.launchExternalIfConfigured(
      context,
      videoUrl: url,
      title: title.trim().isEmpty ? 'Debrify TV' : title.trim(),
    );
    if (launched) {
      _launchedPlayer = true;
      await _queuePrefetcher.stopPrefetch();
      return true;
    }
    return false;
  }

  // ===================== Prefetcher =====================

}
