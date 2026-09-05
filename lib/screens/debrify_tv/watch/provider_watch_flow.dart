import '../../../services/debrify_tv/queue_prefetcher.dart' show WatchAllDebridPrepared;
import '../dialogs/cached_loading_dialog.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../models/debrify_tv/channel.dart';
import '../../../models/debrify_tv/prepared_torrents.dart';
import '../../../models/debrify_tv/cache_results.dart';
import '../../../services/cloud/cloud_provider_id.dart';
import '../../../services/cloud/magic_tv_prepare_args.dart';
import '../../../services/storage_service.dart';
import '../../../services/torrent_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../../utils/nsfw_filter.dart';
import '../../../utils/rd_blocked_filter.dart';
import '../../../utils/debrify_tv_filters.dart';
import '../../video_player_screen.dart';
import '../../../services/debrify_tv/channel_cache_warmer.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;

/// Live bindings keep original host reads and captured-key service calls intact.
/// This is a retained dependency, not completed CloudProviderPort abstraction.
class WatchValue<T> {
  const WatchValue(this.read, [this.write]);
  final T Function() read;
  final void Function(T)? write;
}


class WatchFlowBindings {
  WatchFlowBindings({
    required WatchValue<bool> allDebridAvailable,
    required WatchValue<bool> hideOptions,
    required WatchValue<bool> hideSeekbar,
    required WatchValue<bool> isAndroidTv,
    required this.getChannelKeywords,
    required WatchValue<bool> isBusy,
    required WatchValue<bool> launchedPlayer,
    required WatchValue<bool> pikpakAvailable,
    required WatchValue<bool> prefetchStopRequested,
    required WatchValue<bool> premiumizeAvailable,
    required WatchValue<bool> progressOpen,
    required WatchValue<bool> qualityFallbackNotified,
    required WatchValue<bool> quickAvoidNsfw,
    required WatchValue<bool> quickHideOptions,
    required WatchValue<bool> quickHideSeekbar,
    required WatchValue<bool> quickShowChannelName,
    required WatchValue<bool> quickShowVideoTitle,
    required WatchValue<bool> quickStartRandom,
    required WatchValue<bool> rdAvailable,
    required WatchValue<bool> rdSkipBlockedTorrents,
    required WatchValue<bool> showChannelName,
    required WatchValue<bool> showVideoTitle,
    required WatchValue<bool> startRandom,
    required WatchValue<bool> torboxAvailable,
    required WatchValue<bool> viewerForcesNsfw,
    required WatchValue<bool> watchCancelled,
    required WatchValue<String> activeProvider,
    required WatchValue<String> provider,
    required WatchValue<String> quickProvider,
    required WatchValue<String> status,
    required WatchValue<String> torboxFileEntryType,
    required WatchValue<String?> activeApiKey,
    required WatchValue<String?> currentWatchingChannelId,
    required WatchValue<int> lastQueueSize,
    required WatchValue<int> quickPlayMaxKeywords,
    required WatchValue<int> quickRandomStartPercent,
    required WatchValue<int> randomStartPercent,
    required WatchValue<int?> originalMaxCap,
    required WatchValue<DateTime?> lastSearchAt,
    required WatchValue<ChannelCacheWarmer> cacheWarmer,
    required WatchValue<List<DebrifyTvChannel>> channels,
    required WatchValue<TextEditingController> keywordsController,
    required WatchValue<List<Torrent>?> pikpakCandidatePool,
    required WatchValue<ValueNotifier<List<String>>> progress,
    required WatchValue<BuildContext?> progressSheetContext,
    required WatchValue<List<dynamic>> queue,
    required WatchValue<Set<String>> seenLinkWithTorrentId,
    required WatchValue<Set<String>> seenRestrictedLinks,
    required WatchValue<DebrifyTvFilters> tvFilters,
    required WatchValue<bool> mounted,
    required this.androidTvChannelMetadata,
    required this.cancelActiveWatch,
    required this.closeProgressDialog,
    required this.fetchPremiumizeCacheWindow,
    required this.formatTorboxError,
    required this.handOffToExternalPlayer,
    required this.launchPikPakOnAndroidTv,
    required this.launchRealDebridOnAndroidTv,
    required this.launchTorboxOnAndroidTv,
    required this.normalizeInfohash,
    required this.notifyQualityFallback,
    required this.preparePikPakTorrent,
    required this.preparePremiumizeTorrent,
    required this.prepareTorboxTorrent,
    required this.providerDisplay,
    required this.requestChannelById,
    required this.requestNextChannel,
    required this.resolveAllDebridLinks,
    required this.resolveChannelNumber,
    required this.resolveRdLockedLinks,
    required this.resolveTorboxQueuedFile,
    required this.showCachedPlaybackDialog,
    required this.showSnack,
    required this.startPrefetch,
    required this.stopPrefetch,
    required this.syncProviderAvailability,
    required this.watchWithTorbox,
    required this.watchWithPikPak,
    required this.watchWithPremiumize,
    required this.watchWithAllDebrid,
    required this.navigator,
    required this.messenger,
    required this.showProgressDialog,
    required this.setState,
    required this.unrestrictLink,
    required this.addTorrentPreferVideos,
    required this.unlockLink,
  }) : _allDebridAvailable = allDebridAvailable,
       _hideOptions = hideOptions,
       _hideSeekbar = hideSeekbar,
       _isAndroidTv = isAndroidTv,
       _isBusy = isBusy,
       _launchedPlayer = launchedPlayer,
       _pikpakAvailable = pikpakAvailable,
       _prefetchStopRequested = prefetchStopRequested,
       _premiumizeAvailable = premiumizeAvailable,
       _progressOpen = progressOpen,
       _qualityFallbackNotified = qualityFallbackNotified,
       _quickAvoidNsfw = quickAvoidNsfw,
       _quickHideOptions = quickHideOptions,
       _quickHideSeekbar = quickHideSeekbar,
       _quickShowChannelName = quickShowChannelName,
       _quickShowVideoTitle = quickShowVideoTitle,
       _quickStartRandom = quickStartRandom,
       _rdAvailable = rdAvailable,
       _rdSkipBlockedTorrents = rdSkipBlockedTorrents,
       _showChannelName = showChannelName,
       _showVideoTitle = showVideoTitle,
       _startRandom = startRandom,
       _torboxAvailable = torboxAvailable,
       _viewerForcesNsfw = viewerForcesNsfw,
       _watchCancelled = watchCancelled,
       _activeProvider = activeProvider,
       _provider = provider,
       _quickProvider = quickProvider,
       _status = status,
       _torboxFileEntryType = torboxFileEntryType,
       _activeApiKey = activeApiKey,
       _currentWatchingChannelId = currentWatchingChannelId,
       _lastQueueSize = lastQueueSize,
       _quickPlayMaxKeywords = quickPlayMaxKeywords,
       _quickRandomStartPercent = quickRandomStartPercent,
       _randomStartPercent = randomStartPercent,
       _originalMaxCap = originalMaxCap,
       _lastSearchAt = lastSearchAt,
       _cacheWarmer = cacheWarmer,
       _channels = channels,
       _keywordsController = keywordsController,
       _pikpakCandidatePool = pikpakCandidatePool,
       _progress = progress,
       _progressSheetContext = progressSheetContext,
       _queue = queue,
       _seenLinkWithTorrentId = seenLinkWithTorrentId,
       _seenRestrictedLinks = seenRestrictedLinks,
       _tvFilters = tvFilters,
       _mounted = mounted;
  final WatchValue<bool> _allDebridAvailable;
  bool get allDebridAvailable => _allDebridAvailable.read();
  final WatchValue<bool> _hideOptions;
  bool get hideOptions => _hideOptions.read();
  final WatchValue<bool> _hideSeekbar;
  bool get hideSeekbar => _hideSeekbar.read();
  final WatchValue<bool> _isAndroidTv;
  bool get isAndroidTv => _isAndroidTv.read();
  final Future<List<String>> Function(String channelId) getChannelKeywords;
  final WatchValue<bool> _isBusy;
  bool get isBusy => _isBusy.read();
  set isBusy(bool value) => _isBusy.write!(value);
  final WatchValue<bool> _launchedPlayer;
  bool get launchedPlayer => _launchedPlayer.read();
  set launchedPlayer(bool value) => _launchedPlayer.write!(value);
  final WatchValue<bool> _pikpakAvailable;
  bool get pikpakAvailable => _pikpakAvailable.read();
  final WatchValue<bool> _prefetchStopRequested;
  bool get prefetchStopRequested => _prefetchStopRequested.read();
  set prefetchStopRequested(bool value) => _prefetchStopRequested.write!(value);
  final WatchValue<bool> _premiumizeAvailable;
  bool get premiumizeAvailable => _premiumizeAvailable.read();
  final WatchValue<bool> _progressOpen;
  bool get progressOpen => _progressOpen.read();
  set progressOpen(bool value) => _progressOpen.write!(value);
  final WatchValue<bool> _qualityFallbackNotified;
  bool get qualityFallbackNotified => _qualityFallbackNotified.read();
  set qualityFallbackNotified(bool value) =>
      _qualityFallbackNotified.write!(value);
  final WatchValue<bool> _quickAvoidNsfw;
  bool get quickAvoidNsfw => _quickAvoidNsfw.read();
  final WatchValue<bool> _quickHideOptions;
  bool get quickHideOptions => _quickHideOptions.read();
  final WatchValue<bool> _quickHideSeekbar;
  bool get quickHideSeekbar => _quickHideSeekbar.read();
  final WatchValue<bool> _quickShowChannelName;
  bool get quickShowChannelName => _quickShowChannelName.read();
  final WatchValue<bool> _quickShowVideoTitle;
  bool get quickShowVideoTitle => _quickShowVideoTitle.read();
  final WatchValue<bool> _quickStartRandom;
  bool get quickStartRandom => _quickStartRandom.read();
  final WatchValue<bool> _rdAvailable;
  bool get rdAvailable => _rdAvailable.read();
  final WatchValue<bool> _rdSkipBlockedTorrents;
  bool get rdSkipBlockedTorrents => _rdSkipBlockedTorrents.read();
  final WatchValue<bool> _showChannelName;
  bool get showChannelName => _showChannelName.read();
  final WatchValue<bool> _showVideoTitle;
  bool get showVideoTitle => _showVideoTitle.read();
  final WatchValue<bool> _startRandom;
  bool get startRandom => _startRandom.read();
  final WatchValue<bool> _torboxAvailable;
  bool get torboxAvailable => _torboxAvailable.read();
  final WatchValue<bool> _viewerForcesNsfw;
  bool get viewerForcesNsfw => _viewerForcesNsfw.read();
  final WatchValue<bool> _watchCancelled;
  bool get watchCancelled => _watchCancelled.read();
  set watchCancelled(bool value) => _watchCancelled.write!(value);
  final WatchValue<String> _activeProvider;
  String get activeProvider => _activeProvider.read();
  set activeProvider(String value) => _activeProvider.write!(value);
  final WatchValue<String> _provider;
  String get provider => _provider.read();
  final WatchValue<String> _quickProvider;
  String get quickProvider => _quickProvider.read();
  final WatchValue<String> _status;
  String get status => _status.read();
  set status(String value) => _status.write!(value);
  final WatchValue<String> _torboxFileEntryType;
  String get torboxFileEntryType => _torboxFileEntryType.read();
  final WatchValue<String?> _activeApiKey;
  String? get activeApiKey => _activeApiKey.read();
  set activeApiKey(String? value) => _activeApiKey.write!(value);
  final WatchValue<String?> _currentWatchingChannelId;
  String? get currentWatchingChannelId => _currentWatchingChannelId.read();
  set currentWatchingChannelId(String? value) => _currentWatchingChannelId.write!(value);
  final WatchValue<int> _lastQueueSize;
  int get lastQueueSize => _lastQueueSize.read();
  set lastQueueSize(int value) => _lastQueueSize.write!(value);
  final WatchValue<int> _quickPlayMaxKeywords;
  int get quickPlayMaxKeywords => _quickPlayMaxKeywords.read();
  final WatchValue<int> _quickRandomStartPercent;
  int get quickRandomStartPercent => _quickRandomStartPercent.read();
  final WatchValue<int> _randomStartPercent;
  int get randomStartPercent => _randomStartPercent.read();
  final WatchValue<int?> _originalMaxCap;
  int? get originalMaxCap => _originalMaxCap.read();
  set originalMaxCap(int? value) => _originalMaxCap.write!(value);
  final WatchValue<DateTime?> _lastSearchAt;
  DateTime? get lastSearchAt => _lastSearchAt.read();
  set lastSearchAt(DateTime? value) => _lastSearchAt.write!(value);
  final WatchValue<ChannelCacheWarmer> _cacheWarmer;
  ChannelCacheWarmer get cacheWarmer => _cacheWarmer.read();
  final WatchValue<List<DebrifyTvChannel>> _channels;
  List<DebrifyTvChannel> get channels => _channels.read();
  final WatchValue<TextEditingController> _keywordsController;
  TextEditingController get keywordsController => _keywordsController.read();
  final WatchValue<List<Torrent>?> _pikpakCandidatePool;
  List<Torrent>? get pikpakCandidatePool => _pikpakCandidatePool.read();
  set pikpakCandidatePool(List<Torrent>? value) =>
      _pikpakCandidatePool.write!(value);
  final WatchValue<ValueNotifier<List<String>>> _progress;
  ValueNotifier<List<String>> get progress => _progress.read();
  final WatchValue<BuildContext?> _progressSheetContext;
  BuildContext? get progressSheetContext => _progressSheetContext.read();
  set progressSheetContext(BuildContext? value) =>
      _progressSheetContext.write!(value);
  final WatchValue<List<dynamic>> _queue;
  List<dynamic> get queue => _queue.read();
  final WatchValue<Set<String>> _seenLinkWithTorrentId;
  Set<String> get seenLinkWithTorrentId => _seenLinkWithTorrentId.read();
  final WatchValue<Set<String>> _seenRestrictedLinks;
  Set<String> get seenRestrictedLinks => _seenRestrictedLinks.read();
  final WatchValue<DebrifyTvFilters> _tvFilters;
  DebrifyTvFilters get tvFilters => _tvFilters.read();
  final WatchValue<bool> _mounted;
  bool get mounted => _mounted.read();
  final List<Map<String, dynamic>> Function({String? activeChannelId})
  androidTvChannelMetadata;
  final void Function({BuildContext? dialogContext, bool clearQueue})
  cancelActiveWatch;
  final void Function() closeProgressDialog;
  final Future<TorboxCacheWindowResult> Function({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  })
  fetchPremiumizeCacheWindow;
  final String Function(Object error) formatTorboxError;
  final Future<bool> Function(String url, String title) handOffToExternalPlayer;
  final Future<bool> Function({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  })
  launchPikPakOnAndroidTv;
  final Future<bool> Function({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  })
  launchRealDebridOnAndroidTv;
  final Future<bool> Function({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  })
  launchTorboxOnAndroidTv;
  final String Function(String hash) normalizeInfohash;
  final void Function() notifyQualityFallback;
  final Future<PikPakPreparedTorrent?> Function({
    required Torrent candidate,
    required void Function(String message) log,
  })
  preparePikPakTorrent;
  final Future<PremiumizePreparedTorrent?> Function({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  })
  preparePremiumizeTorrent;
  final Future<TorboxPreparedTorrent?> Function({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  })
  prepareTorboxTorrent;
  final String Function(String provider) providerDisplay;
  final Future<Map<String, dynamic>?> Function(String channelId)
  requestChannelById;
  final Future<Map<String, dynamic>?> Function() requestNextChannel;
  final Future<WatchAllDebridPrepared?> Function(Torrent candidate)
  resolveAllDebridLinks;
  final int Function(DebrifyTvChannel channel) resolveChannelNumber;
  final Future<MagicTvLockedBatch?> Function(
    Torrent candidate, {
    Set<String>? seenKeys,
  })
  resolveRdLockedLinks;
  final Future<Map<String, String>?> Function({
    required Map<String, dynamic> entry,
    required void Function(String message) log,
  })
  resolveTorboxQueuedFile;
  final void Function() showCachedPlaybackDialog;
  final void Function(String message, {Color color}) showSnack;
  final Future<void> Function() startPrefetch;
  final Future<void> Function() stopPrefetch;
  final Future<void> Function() syncProviderAvailability;
  final Future<void> Function(
    List<String> keywords,
    void Function(String message) log,
  )
  watchWithTorbox;
  final Future<void> Function(
    List<String> keywords,
    void Function(String message) log,
  )
  watchWithPikPak;
  final Future<void> Function(
    List<String> keywords,
    void Function(String message) log,
  )
  watchWithPremiumize;
  final Future<void> Function(
    List<String> keywords,
    void Function(String message) log,
  )
  watchWithAllDebrid;
  final NavigatorState Function() navigator;
  final ScaffoldMessengerState Function() messenger;
  final Future<void> Function({
    required WidgetBuilder builder,
    required bool barrierDismissible,
  })
  showProgressDialog;
  final void Function(VoidCallback fn) setState;
  final Future<Map<String, dynamic>> Function(String apiKey, String link)
  unrestrictLink;
  final Future<Map<String, dynamic>> Function(String apiKey, String magnet)
  addTorrentPreferVideos;
  final Future<String> Function(String apiKey, String link) unlockLink;
}

/// Synchronous per-search result accumulation shared by TorBox and PikPak.
/// Leaves retain their awaits, cancellation and terminal fallback boundaries.
class QuickWatchSearchAccumulator {
  QuickWatchSearchAccumulator(
    this.host, {
    required this.providerLabel,
    required this.queueStatus,
  });

  final WatchFlowBindings host;
  final String providerLabel;
  final String queueStatus;
  final Map<String, Torrent> _dedup = <String, Torrent>{};

  List<Torrent> snapshot() => _dedup.values.toList();

  void accept(Map<String, dynamic> result) {
    final torrents =
        (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);
    final Map<String, String> engineErrors = {};
    final rawErrors = result['engineErrors'];
    if (rawErrors is Map) {
      rawErrors.forEach((key, value) {
        engineErrors[key.toString()] = value?.toString() ?? '';
      });
    }
    if (engineErrors.isNotEmpty) {
      engineErrors.forEach((engine, message) {
        debugPrint('$providerLabel: Search engine "$engine" failed: $message');
      });
    }

    // Apply NSFW filter if enabled
    List<Torrent> torrentsToProcess = torrents;
    if (host.quickAvoidNsfw || host.viewerForcesNsfw) {
      final beforeCount = torrents.length;
      torrentsToProcess = torrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          debugPrint('$providerLabel: Filtered NSFW torrent: ${torrent.name}');
          return false;
        }
        return true;
      }).toList();
      if (beforeCount != torrentsToProcess.length) {
        debugPrint(
          '$providerLabel: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
        );
      }
    }

    int added = 0;
    for (final torrent in torrentsToProcess) {
      final normalizedHash = host.normalizeInfohash(torrent.infohash);
      if (normalizedHash.isEmpty) continue;
      if (!_dedup.containsKey(normalizedHash)) {
        _dedup[normalizedHash] = torrent;
        added++;
      }
    }
    if (added > 0) {
      final combined = host.cacheWarmer.applyQualityFilterToTorrents(
        _dedup.values.toList(),
      );
      combined.shuffle(Random());
      host.queue
        ..clear()
        ..addAll(combined);
      host.lastQueueSize = host.queue.length;
      host.lastSearchAt = DateTime.now();
      if (host.mounted) {
        host.setState(() {
          host.status = queueStatus;
        });
      }
    }
  }
}

class ProviderWatchFlow {
  const ProviderWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watch() async {
    host.launchedPlayer = false;
    await host.stopPrefetch();
    host.prefetchStopRequested = false;
    host.watchCancelled = false;
    host.qualityFallbackNotified = false;
    host.cacheWarmer.resetSizeFilterSession();
    host.originalMaxCap = null;
    void _log(String m) {
      final copy = List<String>.from(host.progress.value)..add(m);
      host.progress.value = copy;
      debugPrint('DebrifyTV: ' + m);
    }

    await host.syncProviderAvailability();
    if (!host.rdAvailable &&
        !host.torboxAvailable &&
        !host.pikpakAvailable &&
        !host.premiumizeAvailable &&
        !host.allDebridAvailable) {
      if (host.mounted) {
        host.setState(() {
          host.status =
              'Connect Real Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use Debrify TV.';
        });
      }
      host.showSnack(
        'Connect Real Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use Debrify TV.',
        color: Colors.orange,
      );
      return;
    }
    final text = host.keywordsController.text.trim();
    debugPrint('DebrifyTV: Watch started. Raw input="$text"');
    if (text.isEmpty) {
      host.setState(() {
        host.status = 'Enter one or more keywords, separated by commas';
      });
      debugPrint('DebrifyTV: Aborting. No keywords provided.');
      return;
    }

    final keywords = host.cacheWarmer.parseKeywords(text);
    debugPrint(
      'DebrifyTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}',
    );
    if (keywords.isEmpty) {
      host.setState(() {
        host.status = 'Enter valid keywords';
      });
      debugPrint(
        'DebrifyTV: Aborting. Parsed keywords became empty after trimming.',
      );
      return;
    }
    if (keywords.length > host.quickPlayMaxKeywords) {
      host.setState(() {
        host.status =
            'Quick Play supports up to ${host.quickPlayMaxKeywords} keywords. Create a channel for larger sets.';
      });
      host.showSnack(
        'Quick Play supports up to ${host.quickPlayMaxKeywords} keywords. Create a channel for bigger combos.',
        color: Colors.orange,
      );
      debugPrint(
        'DebrifyTV: Aborting. Too many keywords for Quick Play (${keywords.length}).',
      );
      return;
    }

    host.setState(() {
      host.isBusy = true;
      host.status = 'Searching...';
      host.queue.clear();
    });

    // show non-dismissible loading modal
    host.progress.value = [];
    host.progressOpen = true;
    final providerLabel = host.providerDisplay(host.quickProvider);
    // ignore: unawaited_futures
    host
        .showProgressDialog(
          barrierDismissible: false, // Prevent dismissing by tapping outside
          builder: (ctx) {
            host.progressSheetContext = ctx;
            return CachedLoadingDialog(
              eyebrow: 'Quick play · $providerLabel',
              title: 'Searching for something to play',
              subtitle:
                  'Debrify is searching your keywords, applying filters, and checking $providerLabel.',
              onCancel: () => host.cancelActiveWatch(dialogContext: ctx),
            );
          },
        )
        .whenComplete(() {
          host.progressOpen = false;
          host.progressSheetContext = null;
        });

    switch (MagicTvDispatch.watchId(host.quickProvider)) {
      case CloudProviderId.torbox:
        await host.watchWithTorbox(keywords, _log);
        return;
      case CloudProviderId.pikpak:
        await host.watchWithPikPak(keywords, _log);
        return;
      case CloudProviderId.premiumize:
        await host.watchWithPremiumize(keywords, _log);
        return;
      case CloudProviderId.alldebrid:
        await host.watchWithAllDebrid(keywords, _log);
        return;
      case CloudProviderId.debrid:
        break;
    }

    // Silent approach - no progress logging needed

    try {
      // Require RD API key early so we can prefetch as soon as results arrive
      final String? apiKeyEarlyRaw = await StorageService.getApiKey();
      if (apiKeyEarlyRaw == null || apiKeyEarlyRaw.isEmpty) {
        if (!host.mounted) return;
        _log('❌ Real Debrid API key not found - please add it in Settings');
        host.messenger().showSnackBar(
          const SnackBar(
            content: Text(
              'Please add your Real Debrid API key in Settings first!',
            ),
          ),
        );
        debugPrint('DebrifyTV: Missing Real Debrid API key.');
        return;
      }
      final String apiKeyEarly = apiKeyEarlyRaw;

      // Helper to infer a filename-like title from a URL
      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        if (host.watchCancelled) {
          return null;
        }
        debugPrint(
          'DebrifyTV: requestMagicNext() called. queueSize=${host.queue.length}',
        );
        while (host.queue.isNotEmpty && !host.watchCancelled) {
          final item = host.queue.removeAt(0);
          if (host.watchCancelled) {
            break;
          }
          // Case 1: RD-restricted entry (append-only items)
          if (item is Map && item['type'] == 'rd_restricted') {
            final String link = item['restrictedLink'] as String? ?? '';
            final String rdTid = item['torrentId'] as String? ?? '';
            debugPrint(
              'DebrifyTV: Trying RD link from queue: torrentId=$rdTid',
            );
            if (link.isEmpty) continue;
            try {
              final started = DateTime.now();
              final unrestrict = await host.unrestrictLink(apiKeyEarly, link);
              if (host.watchCancelled) {
                return null;
              }
              if (!host.cacheWarmer.rdLinkPassesSizeRules(unrestrict)) continue;
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint(
                  'DebrifyTV: Success (RD link). Unrestricted in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                if (host.watchCancelled) {
                  return null;
                }
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: RD link failed to unrestrict: $e');
              continue;
            }
          }

          // Case 2: Torrent entry
          if (item is Torrent) {
            debugPrint(
              'DebrifyTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}',
            );
            try {
              final started = DateTime.now();
              final batch = await host.resolveRdLockedLinks(item);
              if (host.watchCancelled) {
                return null;
              }
              final elapsed = DateTime.now().difference(started).inSeconds;
              if (batch == null || batch.lockedLinks.isEmpty) {
                continue;
              }

              final torrentId = batch.remoteId;
              final newLinks = List<String>.from(batch.lockedLinks);

              newLinks.shuffle(Random());
              // Walk THIS torrent's own links until one is playable, rather
              // than re-queuing the torrent after a single reject — that would
              // cost another add+info round trip per sibling file (see the
              // cached-channel flow for the same reasoning).
              while (newLinks.isNotEmpty && !host.watchCancelled) {
                final selectedLink = newLinks.removeAt(0);
                host.seenRestrictedLinks.add(selectedLink);
                host.seenLinkWithTorrentId.add('$torrentId|$selectedLink');

                final unrestrict = await host.unrestrictLink(
                  apiKeyEarly,
                  selectedLink,
                );
                if (host.watchCancelled) {
                  return null;
                }
                if (!host.cacheWarmer.rdLinkPassesSizeRules(unrestrict)) {
                  continue;
                }
                final videoUrl = unrestrict['download'] as String?;
                if (videoUrl == null || videoUrl.isEmpty) continue;

                debugPrint(
                  'DebrifyTV: Success. Got unrestricted URL in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;

                if (!host.watchCancelled && newLinks.isNotEmpty) {
                  host.queue.add(item);
                }

                if (host.watchCancelled) {
                  return null;
                }
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint(
                'DebrifyTV: Debrid add failed for ${item.infohash}: $e',
              );
            }
          }
        }
        debugPrint('DebrifyTV: requestMagicNext() queue exhausted.');
        return null;
      }

      final Map<String, Torrent> dedupByInfohash = {};
      final engineStates = await host.cacheWarmer.tvEngineSearchStates();
      final maxResultsOverrides = host.cacheWarmer
          .quickPlayMaxResultsOverrides();

      // Launch limited batches of per-keyword searches so we don't overwhelm
      List<String> pendingKeywords = List<String>.from(keywords);
      while (pendingKeywords.isNotEmpty && !host.watchCancelled) {
        final batch = pendingKeywords
            .take(host.cacheWarmer.channelBatchSize)
            .toList();
        pendingKeywords = pendingKeywords.skip(batch.length).toList();

        final futures = batch.map((kw) {
          debugPrint('DebrifyTV: Searching engines for "$kw"...');
          return TorrentService.searchAllEngines(
            kw,
            engineStates: engineStates,
            maxResultsOverrides: maxResultsOverrides,
          );
        }).toList();

        await for (final result in Stream.fromFutures(futures)) {
          if (host.watchCancelled) {
            break;
          }
          final List<Torrent> torrents =
              (result['torrents'] as List<Torrent>?) ?? <Torrent>[];
          final engineCounts =
              (result['engineCounts'] as Map<String, int>?) ?? const {};
          final Map<String, String> engineErrors = {};
          final rawErrors = result['engineErrors'];
          if (rawErrors is Map) {
            rawErrors.forEach((key, value) {
              engineErrors[key.toString()] = value?.toString() ?? '';
            });
          }
          if (engineErrors.isNotEmpty) {
            engineErrors.forEach((engine, message) {
              debugPrint('DebrifyTV: Search engine "$engine" failed: $message');
            });
          }
          debugPrint(
            'DebrifyTV: Partial results received: total=${torrents.length}, engineCounts=$engineCounts',
          );

          // Apply NSFW filter if enabled
          List<Torrent> torrentsToProcess = torrents;
          if (host.quickAvoidNsfw || host.viewerForcesNsfw) {
            final beforeCount = torrents.length;
            torrentsToProcess = torrents.where((torrent) {
              if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
                debugPrint('DebrifyTV: Filtered NSFW torrent: ${torrent.name}');
                return false;
              }
              return true;
            }).toList();
            if (beforeCount != torrentsToProcess.length) {
              debugPrint(
                'DebrifyTV: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
              );
            }
          }

          // Filter out RD-blocked torrents
          if (host.rdSkipBlockedTorrents) {
            torrentsToProcess = torrentsToProcess
                .where((t) => !isRdBlockedTorrent(t.name))
                .toList();
          }

          int added = 0;
          for (final t in torrentsToProcess) {
            if (!dedupByInfohash.containsKey(t.infohash)) {
              dedupByInfohash[t.infohash] = t;
              added++;
            }
          }
          if (added > 0) {
            if (host.watchCancelled) {
              break;
            }
            final combined = host.cacheWarmer.applyQualityFilterToTorrents(
              dedupByInfohash.values.toList(),
            );
            combined.shuffle(Random());
            host.queue
              ..clear()
              ..addAll(combined);
            host.lastQueueSize = host.queue.length;
            host.lastSearchAt = DateTime.now();
            // Silent approach - no progress logging needed
            if (host.mounted && !host.watchCancelled) {
              host.setState(() {
                host.status = 'Preparing your content...';
              });
            }

            // Do not start prefetch until player launches

            // Try to launch player as soon as a playable stream is available
            if (!host.launchedPlayer && !host.watchCancelled) {
              final first = await requestMagicNext();
              if (host.watchCancelled) {
                break;
              }
              if (first != null &&
                  host.mounted &&
                  !host.launchedPlayer &&
                  !host.watchCancelled) {
                host.launchedPlayer = true;
                final firstUrl = first['url'] ?? '';
                final firstTitleResolved =
                    (first['title'] ?? firstTitle).trim().isNotEmpty
                    ? (first['title'] ?? firstTitle)
                    : firstTitle;
                if (!host.watchCancelled &&
                    host.progressOpen &&
                    host.progressSheetContext != null) {
                  Navigator.of(host.progressSheetContext!).pop();
                }
                debugPrint(
                  'DebrifyTV: Launching player early. Remaining queue=${host.queue.length}',
                );

                // Start background prefetch only while player is active
                if (!host.watchCancelled) {
                  host.activeApiKey = apiKeyEarly;
                  host.activeProvider = CloudProviderId.debrid.magicTvId;
                  unawaited(host.startPrefetch());

                  final String? activeChannelId = host.currentWatchingChannelId;
                  final int? activeChannelNumber;
                  if (activeChannelId != null) {
                    final int idx = host.channels.indexWhere(
                      (c) => c.id == activeChannelId,
                    );
                    if (idx >= 0) {
                      final int resolvedNumber = host.resolveChannelNumber(
                        host.channels[idx],
                      );
                      activeChannelNumber = resolvedNumber > 0
                          ? resolvedNumber
                          : null;
                    } else {
                      activeChannelNumber = null;
                    }
                  } else {
                    activeChannelNumber = null;
                  }
                  final List<Map<String, dynamic>>? activeChannelDirectory =
                      host.channels.isNotEmpty
                      ? host.androidTvChannelMetadata(
                          activeChannelId: activeChannelId,
                        )
                      : null;

                  // External player set as the default: hand this one title
                  // over and stop the search — nothing rotates past it.
                  if (await host.handOffToExternalPlayer(
                    firstUrl,
                    firstTitleResolved,
                  )) {
                    break; // Exit the search loop
                  }

                  // Try to launch on Android TV first (early launch path)
                  final launchedOnTv = await host.launchRealDebridOnAndroidTv(
                    firstStream: first,
                    requestNext: requestMagicNext,
                    showChannelNameOverride: host.quickShowChannelName,
                    channelId: activeChannelId,
                    channelNumber: activeChannelNumber,
                    channelDirectory: activeChannelDirectory,
                  );

                  if (launchedOnTv) {
                    // Successfully launched on Android TV
                    debugPrint(
                      'DebrifyTV: Early launch - Real-Debrid playback started on Android TV',
                    );
                    // Prefetch will continue in background while TV player is active
                    break; // Exit the search loop
                  }

                  // Hide auto-launch overlay before launching player
                  MainPageBridge.notifyPlayerLaunching();

                  // Fall back to Flutter video player
                  await host.navigator().push(
                    FrozenLegacyPageRoute(
                      builder: (_) => VideoPlayerScreen(
                        videoUrl: firstUrl,
                        title: firstTitleResolved,
                        startFromRandom: host.quickStartRandom,
                        randomStartMaxPercent: host.quickRandomStartPercent,
                        hideSeekbar: host.quickHideSeekbar,
                        showChannelName: host.quickShowChannelName,
                        channelName: null,
                        channelNumber: null,
                        showVideoTitle: host.quickShowVideoTitle,
                        hideOptions: host.quickHideOptions,
                        requestMagicNext: requestMagicNext,
                        requestNextChannel:
                            host.channels.length > 1 &&
                                MagicTvDispatch.allowsNextChannel(
                                  host.quickProvider,
                                  MagicTvNextChannelQuirk.exceptAllDebrid,
                                )
                            ? host.requestNextChannel
                            : null,
                        channelDirectory: activeChannelDirectory,
                        requestChannelById: host.channels.length > 1
                            ? host.requestChannelById
                            : null,
                      ),
                    ),
                  );

                  // Stop prefetch when player exits
                  await host.stopPrefetch();
                }
              }
            }
          }
        }
        if (host.watchCancelled) {
          break;
        }
      }
      // Final queue snapshot (if we didn't launch early)
      if (!host.launchedPlayer) {
        // The per-batch rebuilds above filter strictly, so an empty queue here
        // means nothing in the whole search matched the quality filter. This
        // is the point where that's genuinely known — degrade to unfiltered
        // rather than reporting "no results" for a search that found plenty.
        if (host.queue.isEmpty &&
            host.tvFilters.hasQuality &&
            dedupByInfohash.isNotEmpty &&
            !host.watchCancelled) {
          host.notifyQualityFallback();
          final fallback = dedupByInfohash.values.toList()..shuffle(Random());
          host.queue
            ..clear()
            ..addAll(fallback);
        }
        debugPrint('DebrifyTV: Queue prepared. size=${host.queue.length}');
        host.lastQueueSize = host.queue.length;
        host.lastSearchAt = DateTime.now();
      }
    } catch (e) {
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'Search failed: $e';
      });
      debugPrint('DebrifyTV: Search failed: $e');
    } finally {
      if (host.mounted) {
        host.setState(() {
          host.isBusy = false;
        });
      }
    }

    if (host.watchCancelled) {
      debugPrint('DebrifyTV: Watch was cancelled before completion.');
      return;
    }

    if (!host.mounted) return;
    if (host.queue.isEmpty) {
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'No results found';
      });
      debugPrint('DebrifyTV: No results found after combining.');
      _log('❌ No results found - trying different search strategies');

      // Close popup and show user-friendly message
      if (host.progressOpen && host.progressSheetContext != null) {
        Navigator.of(host.progressSheetContext!).pop();
        host.progressOpen = false;
        host.progressSheetContext = null;
      }

      if (host.mounted) {
        host.setState(() {
          host.isBusy = false;
          host.status = 'No results found. Try different keywords.';
        });
        host.messenger().showSnackBar(
          const SnackBar(
            content: Text(
              'No results found. Try different keywords or check your internet connection.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // If we already launched the player early, we're done here
    if (host.launchedPlayer) {
      if (!host.mounted) return;
      host.setState(() {
        host.status = '';
      });
      return;
    }

    // Helper to infer a filename-like title from a URL
    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
    }

    // Build a provider for "next" requests that reuses the same queue and keywords
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!host.mounted) return;
      host.messenger().showSnackBar(
        const SnackBar(
          content: Text(
            'Please add your Real Debrid API key in Settings first!',
          ),
        ),
      );
      debugPrint('MagicTV: Missing Real Debrid API key.');
      return;
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint(
        'MagicTV: requestMagicNext() called. queueSize=${host.queue.length}',
      );
      while (host.queue.isNotEmpty) {
        final item = host.queue.removeAt(0);
        // Case 1: RD-restricted entry (append-only items)
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('MagicTV: Trying RD link from queue: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await host.unrestrictLink(apiKey, link);
            if (!host.cacheWarmer.rdLinkPassesSizeRules(unrestrict)) continue;
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint(
                'MagicTV: Success (RD link). Unrestricted in ${elapsed}s',
              );
              // Prefer filename inferred from URL; fallback to any stored displayName
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: RD link failed to unrestrict: $e');
            continue;
          }
        }

        // Case 2: Torrent entry
        if (item is Torrent) {
          debugPrint(
            'MagicTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}',
          );
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await host.addTorrentPreferVideos(
              apiKey,
              magnetLink,
            );
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = result['downloadLink'] as String?;
            // Append other RD-restricted links from this torrent to the END of the queue
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<dynamic> rdLinks =
                (result['links'] as List<dynamic>? ?? const []);
            if (rdLinks.isNotEmpty) {
              // We assume we used rdLinks[0] to play; enqueue remaining
              for (int i = 1; i < rdLinks.length; i++) {
                final String link = rdLinks[i]?.toString() ?? '';
                if (link.isEmpty) continue;
                final String combined = '$torrentId|$link';
                if (host.seenRestrictedLinks.contains(link) ||
                    host.seenLinkWithTorrentId.contains(combined)) {
                  continue;
                }
                host.seenRestrictedLinks.add(link);
                host.seenLinkWithTorrentId.add(combined);
                host.queue.add({
                  'type': 'rd_restricted',
                  'restrictedLink': link,
                  'torrentId': torrentId,
                  'displayName': item.name,
                });
              }
              if (rdLinks.length > 1) {
                debugPrint(
                  'MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${host.queue.length}',
                );
              }
            }
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint(
                'MagicTV: Success. Got unrestricted URL in ${elapsed}s',
              );
              // Prefer filename inferred from URL; fallback to torrent name
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: Debrid add failed for ${item.infohash}: $e');
          }
        }
      }
      debugPrint('MagicTV: requestMagicNext() queue exhausted.');
      return null;
    }

    host.setState(() {
      host.status = 'Finding a playable stream...';
      host.isBusy = true;
    });
    _log('🎬 Selecting the best quality stream for you');

    try {
      final first = await requestMagicNext();
      if (first == null) {
        // Close popup and show user-friendly message
        if (host.progressOpen && host.progressSheetContext != null) {
          Navigator.of(host.progressSheetContext!).pop();
          host.progressOpen = false;
          host.progressSheetContext = null;
        }

        if (host.mounted) {
          host.setState(() {
            host.isBusy = false;
            host.status = 'No playable torrents found. Try different keywords.';
          });
          MainPageBridge.notifyAutoLaunchFailed('No playable streams found');
          host.messenger().showSnackBar(
            const SnackBar(
              content: Text(
                'No playable streams found. Try different keywords or check your internet connection.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        debugPrint('MagicTV: No playable stream found.');
        return;
      }
      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      if (!host.mounted) return;
      debugPrint(
        'MagicTV: Launching player. Remaining queue=${host.queue.length}',
      );

      // Start background prefetch while player is active
      host.activeApiKey = apiKey;
      host.activeProvider = CloudProviderId.debrid.magicTvId;
      unawaited(host.startPrefetch());

      if (host.progressOpen && host.progressSheetContext != null) {
        Navigator.of(host.progressSheetContext!).pop();
      }

      final String? activeChannelId = host.currentWatchingChannelId;
      final int? activeChannelNumber;
      if (activeChannelId != null) {
        final int idx = host.channels.indexWhere(
          (c) => c.id == activeChannelId,
        );
        if (idx >= 0) {
          final int resolvedNumber = host.resolveChannelNumber(
            host.channels[idx],
          );
          activeChannelNumber = resolvedNumber > 0 ? resolvedNumber : null;
        } else {
          activeChannelNumber = null;
        }
      } else {
        activeChannelNumber = null;
      }
      final List<Map<String, dynamic>>? quickChannelDirectory =
          host.channels.isNotEmpty
          ? host.androidTvChannelMetadata(activeChannelId: activeChannelId)
          : null;

      if (await host.handOffToExternalPlayer(firstUrl, firstTitle)) {
        return;
      }

      // Try to launch on Android TV first
      final launchedOnTv = await host.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: host.quickShowChannelName,
        channelId: activeChannelId,
        channelNumber: activeChannelNumber,
        channelDirectory: quickChannelDirectory,
      );

      if (launchedOnTv) {
        // Successfully launched on Android TV
        debugPrint('MagicTV: Real-Debrid playback started on Android TV');
        // Prefetch will continue in background while TV player is active
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      // Fall back to Flutter video player
      await host.navigator().push(
        FrozenLegacyPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: host.quickStartRandom,
            randomStartMaxPercent: host.quickRandomStartPercent,
            hideSeekbar: host.quickHideSeekbar,
            showChannelName: host.quickShowChannelName,
            channelName: null,
            channelNumber: null,
            showVideoTitle: host.quickShowVideoTitle,
            hideOptions: host.quickHideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                host.channels.length > 1 &&
                    MagicTvDispatch.allowsNextChannel(
                      host.quickProvider,
                      MagicTvNextChannelQuirk.rdTorboxPikPak,
                    )
                ? host.requestNextChannel
                : null,
            channelDirectory: quickChannelDirectory,
            requestChannelById: host.channels.length > 1
                ? host.requestChannelById
                : null,
          ),
        ),
      );
      // Stop prefetch when player exits
      await host.stopPrefetch();
    } finally {
      if (host.mounted) {
        host.setState(() {
          host.isBusy = false;
          host.status = '';
        });
        debugPrint('MagicTV: Watch flow finished.');
      }
    }
  }
}
