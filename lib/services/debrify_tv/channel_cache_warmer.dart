import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/debrify_tv/cache_results.dart';
import '../../models/debrify_tv/channel.dart';
import '../../models/debrify_tv/channel_stats.dart';
import '../../models/debrify_tv_cache.dart';
import '../../models/torrent.dart';
import '../../models/torrent_filter_state.dart';
import '../../utils/debrify_tv_filters.dart';
import '../../utils/nsfw_filter.dart';
import '../cloud/cloud_provider_registry.dart';
import '../debrify_tv_cache_service.dart';
import '../engine/dynamic_engine.dart';
import '../engine/engine_registry.dart';

/// Per-engine warm result. Origin `_TvEngineWarmResult` in
/// `lib/screens/magic_tv_screen.dart`.
class TvEngineWarmResult {
  final DynamicEngine engine;
  final List<Torrent> torrents;
  final int pagesPulled;
  final String? failureMessage;

  const TvEngineWarmResult({
    required this.engine,
    required this.torrents,
    required this.pagesPulled,
    this.failureMessage,
  });
}

/// Keyword warm / cache extracted from `lib/screens/magic_tv_screen.dart`
/// (M1-1). Seam is [EngineRegistry] + [DebrifyTvCacheService]; snacks and
/// progress dialogs stay on the host ([onQualityFallback] / [onSizeFallback]).
///
/// Method bodies are copied from origin. Underscores dropped; host
/// viewer-NSFW / playback-filters / quality-fallback snack become
/// [viewerForcesNsfw] / [filters] / [onQualityFallback].
class ChannelCacheWarmer {
  ChannelCacheWarmer({
    required this.viewerForcesNsfw,
    required this.filters,
    required this.minVideoSizeBytes,
    this.onQualityFallback,
    this.onSizeFallback,
  });

  final bool Function() viewerForcesNsfw;
  final DebrifyTvFilters Function() filters;
  final int minVideoSizeBytes;
  final VoidCallback? onQualityFallback;
  final VoidCallback? onSizeFallback;

  final Map<String, DebrifyTvChannelCacheEntry> channelCache = {};
  final Map<String, bool> tvEngineStates = <String, bool>{};
  final Map<String, int> tvSmallChannelMaxByEngine = <String, int>{};
  final Map<String, int> tvLargeChannelMaxByEngine = <String, int>{};
  final Map<String, int> tvQuickPlayMaxByEngine = <String, int>{};
  int channelBatchSize = 4;
  int keywordThreshold = 10;
  int minTorrentsPerKeyword = 5;

  static const int playbackTorrentThreshold = 1000;
  static const int maxTorrentsPerKeywordPlayback = 25;
  static const int keywordWarmEstimateMs = 1000;
  static const int rdSizeRejectionLimit = 12;

  int rdSizeRejections = 0;
  bool sizeFilterRelaxed = false;

  static String normalizeInfohash(String hash) {
    return hash.trim().toLowerCase();
  }

  void resetSizeFilterSession() {
    rdSizeRejections = 0;
    sizeFilterRelaxed = false;
  }

  DebrifyTvChannelStats classifySpotlightStats({
    required String channelId,
    required DebrifyTvChannelCacheEntry? entry,
    required QualityTier Function(String name) tierForName,
  }) {
    final torrents = entry?.torrents ?? const <CachedTorrent>[];

    // ONE pass classifies every name: the quality count and the mix buckets
    // share it. Quality only — size is a per-file rule the pool rows cannot
    // answer, and counting it here would promise what playback can't keep.
    final hasQuality = filters().hasQuality;
    int uhd = 0, fhd = 0, rest = 0, atQuality = 0;
    for (final t in torrents) {
      switch (tierForName(t.name)) {
        case QualityTier.ultraHd:
          uhd++;
        case QualityTier.fullHd:
          fhd++;
        case QualityTier.hd:
        case QualityTier.sd:
          rest++;
      }
      if (!hasQuality || filters().qualityMatchesName(t.name)) {
        atQuality++;
      }
    }

    final keywordYield = <String, int>{
      for (final kw in entry?.normalizedKeywords ?? const <String>[])
        kw: entry?.keywordStats[kw]?.totalFetched ?? 0,
    };
    final dead = [
      for (final e in keywordYield.entries)
        if (e.value == 0) e.key,
    ];

    final sample = [...torrents]..shuffle(Random());

    return DebrifyTvChannelStats(
      channelId: channelId,
      pooled: torrents.length,
      atYourQuality: atQuality,
      qualityMix: [uhd, fhd, rest],
      deadKeywords: dead,
      keywordYield: keywordYield,
      fetchedAt: (entry?.fetchedAt ?? 0) > 0
          ? DateTime.fromMillisecondsSinceEpoch(entry!.fetchedAt)
          : null,
      status: entry?.status ?? DebrifyTvCacheStatus.warming,
      sample: sample.take(4).toList(),
    );
  }

  void accumulateCachedTorrent({
    required Map<String, CachedTorrent> accumulator,
    required String infohash,
    required Torrent torrent,
    required String keyword,
    required String source,
  }) {
    if (infohash.isEmpty) {
      return;
    }
    final normalizedKeyword = keyword.toLowerCase();
    final normalizedSource = source.toLowerCase();
    final existing = accumulator[infohash];
    if (existing == null) {
      accumulator[infohash] = CachedTorrent.fromTorrent(
        torrent,
        keywords: [normalizedKeyword],
        sources: [normalizedSource],
      );
      return;
    }

    final shouldOverride = torrent.seeders > existing.seeders;
    accumulator[infohash] = existing.merge(
      keywords: [normalizedKeyword],
      sources: [normalizedSource],
      override: shouldOverride ? torrent : null,
    );
  }

  List<DynamicEngine> enabledTvKeywordEngines(EngineRegistry registry) {
    final engines = registry
        .getTvModeEngines()
        .where(
          (engine) =>
              engine.supportsKeywordSearch &&
              (tvEngineStates[engine.name] ??
                  engine.tvModeConfig?.enabledDefault ??
                  false),
        )
        .toList();
    engines.sort((a, b) => a.name.compareTo(b.name));
    return engines;
  }

  int tvChannelMaxResultsForEngine(DynamicEngine engine, int totalKeywords) {
    final useSmallChannelLimit = totalKeywords < keywordThreshold;
    final storedLimit = useSmallChannelLimit
        ? tvSmallChannelMaxByEngine[engine.name]
        : tvLargeChannelMaxByEngine[engine.name];
    if (storedLimit != null) {
      return storedLimit;
    }

    final tvMode = engine.tvModeConfig;
    if (tvMode == null) {
      return 50;
    }
    return useSmallChannelLimit
        ? tvMode.smallChannel.maxResults
        : tvMode.largeChannel.maxResults;
  }

  int estimatePagesPulledForEngine(DynamicEngine engine, int resultCount) {
    if (resultCount <= 0) {
      return 0;
    }

    final pagination = engine.config.pagination;
    final resultsPerPage = pagination.resultsPerPage;
    if (pagination.type == 'none' ||
        resultsPerPage == null ||
        resultsPerPage <= 0) {
      return 1;
    }

    final estimatedPages = (resultCount + resultsPerPage - 1) ~/ resultsPerPage;
    final maxPages = pagination.maxPages;
    if (maxPages != null && maxPages > 0) {
      return min(estimatedPages, maxPages);
    }
    return estimatedPages;
  }

  int estimatePageRequestsForEngine(DynamicEngine engine, int totalKeywords) {
    final maxResults = tvChannelMaxResultsForEngine(engine, totalKeywords);
    final pagination = engine.config.pagination;
    final resultsPerPage = pagination.resultsPerPage;
    if (pagination.type == 'none' ||
        resultsPerPage == null ||
        resultsPerPage <= 0) {
      return 1;
    }

    final estimatedPages = max(
      1,
      (maxResults + resultsPerPage - 1) ~/ resultsPerPage,
    );
    final maxPages = pagination.maxPages;
    if (maxPages != null && maxPages > 0) {
      return min(estimatedPages, maxPages);
    }
    return estimatedPages;
  }

  Map<String, int> quickPlayMaxResultsOverrides() {
    return Map<String, int>.from(tvQuickPlayMaxByEngine);
  }

  Future<Map<String, bool>> tvEngineSearchStates() async {
    final registry = EngineRegistry.instance;
    await registry.initialize();
    return <String, bool>{
      for (final engine in registry.getKeywordSearchEngines())
        engine.name:
            tvEngineStates[engine.name] ??
            engine.tvModeConfig?.enabledDefault ??
            false,
    };
  }

  List<CachedTorrent> sortedCachedTorrents(
    Map<String, CachedTorrent> accumulator,
  ) {
    final list = accumulator.values.toList();
    list.sort((a, b) {
      final seedCompare = b.seeders.compareTo(a.seeders);
      if (seedCompare != 0) {
        return seedCompare;
      }
      return b.completed.compareTo(a.completed);
    });
    return list;
  }

  Future<DebrifyTvChannelCacheEntry> computeChannelCacheEntry(
    DebrifyTvChannel channel,
    List<String> normalizedKeywords, {
    DebrifyTvChannelCacheEntry? baseline,
    Set<String>? keywordsToSearch,
  }) async {
    // The channel's own NSFW setting, FLOORED by the viewer: filtering is
    // role-locked for a child profile no matter who authored the channel or
    // what its stored flag says (the rail is viewer-scoped, evaluated at
    // search/play — never only at creation).
    final channelAvoidNsfw = channel.avoidNsfw || viewerForcesNsfw();
    final registry = EngineRegistry.instance;
    await registry.initialize();
    final enabledTvEngines = enabledTvKeywordEngines(registry);
    final now = DateTime.now().millisecondsSinceEpoch;

    final accumulator = <String, CachedTorrent>{};
    final stats = <String, KeywordStat>{};

    if (baseline != null) {
      for (final cached in filterCachedTorrentsForKeywords(
        baseline,
        normalizedKeywords,
      )) {
        final normalizedHash = normalizeInfohash(cached.infohash);
        if (normalizedHash.isEmpty) {
          continue;
        }
        accumulator[normalizedHash] = cached;
      }
      stats.addAll(
        filterKeywordStats(baseline.keywordStats, normalizedKeywords),
      );
      debugPrint(
        'DebrifyTV: Starting incremental warm for "${channel.name}" – seeded cache with ${accumulator.length} torrent(s).',
      );
    }

    final Set<String> keywordsToWarm = keywordsToSearch != null
        ? keywordsToSearch.map((kw) => kw.toLowerCase()).toSet()
        : normalizedKeywords.toSet();

    if (keywordsToWarm.isEmpty) {
      debugPrint('DebrifyTV: No keywords to warm for "${channel.name}".');
    }
    if (enabledTvEngines.isEmpty && keywordsToWarm.isNotEmpty) {
      debugPrint(
        'DebrifyTV: No enabled TV search engines for "${channel.name}".',
      );
    }

    bool anySuccess = accumulator.isNotEmpty;
    String? failureMessage;

    List<String> pendingKeywords = List<String>.from(keywordsToWarm);
    while (pendingKeywords.isNotEmpty) {
      final batch = pendingKeywords.take(channelBatchSize).toList();
      pendingKeywords = pendingKeywords.skip(batch.length).toList();

      final futures = batch.map((keyword) async {
        return await warmKeyword(
          keyword: keyword,
          enabledEngines: enabledTvEngines,
          accumulator: accumulator,
          stats: stats,
          now: now,
          totalKeywords: normalizedKeywords.length,
          avoidNsfw: channelAvoidNsfw, // Use channel's NSFW setting
          minTorrentsPerKeyword: minTorrentsPerKeyword,
        );
      }).toList();

      final results = await Future.wait(futures);

      for (final result in results) {
        if (result == null) {
          continue;
        }
        final keyword = result.keyword;
        debugPrint(
          'DebrifyTV: Warmed keyword "$keyword" – added ${result.addedHashes.length} new torrent(s).',
        );
        anySuccess = anySuccess || result.addedHashes.isNotEmpty;
        stats[keyword] = result.stat;
        failureMessage ??= result.failureMessage;
      }
    }

    if (keywordsToWarm.isEmpty) {
      anySuccess = accumulator.isNotEmpty;
    }

    if (anySuccess) {
      return DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channel.id,
        normalizedKeywords: normalizedKeywords,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: sortedCachedTorrents(accumulator),
        keywordStats: Map<String, KeywordStat>.from(stats),
      );
    }

    failureMessage ??= 'No torrents found for these keywords yet.';
    return DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: channel.id,
      normalizedKeywords: normalizedKeywords,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      status: DebrifyTvCacheStatus.failed,
      errorMessage: failureMessage,
      torrents: const <CachedTorrent>[],
      keywordStats: Map<String, KeywordStat>.from(stats),
    );
  }

  Future<KeywordWarmResult?> warmKeyword({
    required String keyword,
    required List<DynamicEngine> enabledEngines,
    required Map<String, CachedTorrent> accumulator,
    required Map<String, KeywordStat> stats,
    required int now,
    required int totalKeywords,
    required bool avoidNsfw, // Use channel's NSFW setting
    required int minTorrentsPerKeyword,
  }) async {
    final searchResults = await Future.wait(
      enabledEngines.map((engine) async {
        final maxResults = tvChannelMaxResultsForEngine(engine, totalKeywords);
        try {
          final torrents = await engine.executeSearch(
            query: keyword,
            maxResults: maxResults,
          );
          return TvEngineWarmResult(
            engine: engine,
            torrents: torrents,
            pagesPulled: estimatePagesPulledForEngine(engine, torrents.length),
          );
        } catch (e) {
          debugPrint(
            'DebrifyTV: Cache warm ${engine.displayName} failed for "$keyword": $e',
          );
          return TvEngineWarmResult(
            engine: engine,
            torrents: const <Torrent>[],
            pagesPulled: 0,
            failureMessage:
                '${engine.displayName} search failed. Some torrents may be missing.',
          );
        }
      }),
    );

    // Apply NSFW filter to search results before caching
    final filteredByEngine = <DynamicEngine, List<Torrent>>{};
    int totalBefore = 0;
    int totalAfter = 0;
    int pagesPulled = 0;
    final failureMessages = <String>[];

    for (final result in searchResults) {
      pagesPulled += result.pagesPulled;
      if (result.failureMessage != null) {
        failureMessages.add(result.failureMessage!);
      }

      final before = result.torrents.length;
      totalBefore += before;
      if (avoidNsfw) {
        final filtered = result.torrents.where((torrent) {
          if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
            return false;
          }
          return true;
        }).toList();
        totalAfter += filtered.length;
        filteredByEngine[result.engine] = filtered;
      } else {
        totalAfter += before;
        filteredByEngine[result.engine] = result.torrents;
      }
    }

    if (avoidNsfw && totalBefore != totalAfter) {
      debugPrint(
        'DebrifyTV: Cache NSFW filter for "$keyword": $totalBefore → $totalAfter torrents',
      );
    }

    // Check minimum torrents per keyword threshold
    final totalTorrents = filteredByEngine.values.fold<int>(
      0,
      (total, torrents) => total + torrents.length,
    );
    if (totalTorrents < minTorrentsPerKeyword) {
      debugPrint(
        'DebrifyTV: Skipping keyword "$keyword" – only $totalTorrents torrent(s), minimum is $minTorrentsPerKeyword',
      );
      final stat = (stats[keyword] ?? KeywordStat.initial())
          .copyWith(
            totalFetched: 0,
            lastSearchedAt: now,
            pagesPulled: pagesPulled,
          )
          .clearLegacySourceHits();
      return KeywordWarmResult(
        keyword: keyword,
        addedHashes: const <String>{},
        stat: stat,
        failureMessage: enabledEngines.isEmpty
            ? 'No enabled TV search engines.'
            : 'Too few torrents for "$keyword" (found $totalTorrents, need $minTorrentsPerKeyword)',
      );
    }

    final keywordHashes = <String>{};

    for (final entry in filteredByEngine.entries) {
      final source = entry.key.name;
      for (final torrent in entry.value) {
        final hash = normalizeInfohash(torrent.infohash);
        if (hash.isEmpty) {
          continue;
        }
        keywordHashes.add(hash);
        accumulateCachedTorrent(
          accumulator: accumulator,
          infohash: hash,
          torrent: torrent,
          keyword: keyword,
          source: source,
        );
      }
    }

    final updatedStats = stats[keyword] ?? KeywordStat.initial();
    final stat = updatedStats
        .copyWith(
          totalFetched: keywordHashes.length,
          lastSearchedAt: now,
          pagesPulled: pagesPulled,
        )
        .clearLegacySourceHits();

    String? failureMessage;
    if (failureMessages.isNotEmpty) {
      failureMessage = failureMessages.first;
    } else if (filteredByEngine.values.every((torrents) => torrents.isEmpty)) {
      failureMessage = 'No torrents found for "$keyword" yet.';
    }

    return KeywordWarmResult(
      keyword: keyword,
      addedHashes: keywordHashes,
      stat: stat,
      failureMessage: failureMessage,
    );
  }

  List<String> normalizedKeywords(List<String> keywords) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final keyword in keywords) {
      final value = keyword.trim().toLowerCase();
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      normalized.add(value);
    }
    return normalized;
  }

  Future<DebrifyTvChannelCacheEntry?> ensureCacheEntry(String channelId) async {
    final cached = channelCache[channelId];
    if (cached != null) {
      return cached;
    }
    final fetched = await DebrifyTvCacheService.getEntry(channelId);
    if (fetched != null) {
      channelCache[channelId] = fetched;
    }
    return fetched;
  }

  int estimatedWarmDurationSeconds(
    int keywordCount, {
    int? totalKeywordUniverse,
  }) {
    if (keywordCount <= 0) {
      return 0;
    }

    final int effectiveUniverse = max(1, totalKeywordUniverse ?? keywordCount);
    final enabledEngines = enabledTvKeywordEngines(EngineRegistry.instance);
    if (enabledEngines.isEmpty) {
      return 0;
    }

    final int batches = max(
      1,
      ((keywordCount + channelBatchSize - 1) ~/ channelBatchSize),
    );

    final int requestWavesPerKeyword = enabledEngines.fold<int>(
      1,
      (current, engine) => max(
        current,
        estimatePageRequestsForEngine(engine, effectiveUniverse),
      ),
    );
    final int estimatedMs =
        batches * requestWavesPerKeyword * keywordWarmEstimateMs;

    return (estimatedMs + 999) ~/ 1000;
  }

  List<CachedTorrent> filterCachedTorrentsForKeywords(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    if (entry.torrents.isEmpty) {
      return const <CachedTorrent>[];
    }
    final allowed = normalizedKeywords.toSet();
    final filtered = <CachedTorrent>[];
    for (final cached in entry.torrents) {
      final matching = cached.keywords.where(allowed.contains).toList();
      if (matching.isEmpty) {
        continue;
      }
      filtered.add(cached.merge(keywords: matching));
    }
    return filtered;
  }

  Map<String, KeywordStat> filterKeywordStats(
    Map<String, KeywordStat> stats,
    List<String> normalizedKeywords,
  ) {
    if (stats.isEmpty) {
      return const <String, KeywordStat>{};
    }
    final allowed = normalizedKeywords.toSet();
    final filtered = <String, KeywordStat>{};
    for (final entry in stats.entries) {
      if (allowed.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }

  /// Narrows a channel's cached torrents to the user's quality filter.
  /// Applied at cache READ time (not warm time) so changing the filter takes
  /// effect immediately instead of forcing a full channel rebuild the way the
  /// NSFW toggle does. Returns the input untouched when the filter is off, and
  /// falls back to the unfiltered pool (with a snackbar) when a channel has
  /// nothing at the requested quality — a filtered channel that plays nothing
  /// reads as broken, so it degrades instead of failing.
  List<CachedTorrent> applyQualityFilterToCached(List<CachedTorrent> all) {
    if (!filters().hasQuality || all.isEmpty) return all;
    final matched = all
        .where((cached) => filters().qualityMatchesName(cached.name))
        .toList();
    if (matched.isEmpty) {
      debugPrint(
        'DebrifyTV: Quality filter matched 0/${all.length} cached torrents — '
        'falling back to unfiltered.',
      );
      onQualityFallback?.call();
      return all;
    }
    if (matched.length != all.length) {
      debugPrint(
        'DebrifyTV: Quality filter on cached: ${all.length} → ${matched.length} torrents',
      );
    }
    return matched;
  }

  List<CachedTorrent> selectTorrentsForPlayback(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    // Filter BEFORE the per-keyword/threshold narrowing below, so the
    // selection draws from the full matching pool rather than from a
    // pre-narrowed sample that the filter then guts.
    final all = applyQualityFilterToCached(entry.torrents);
    if (all.length <= playbackTorrentThreshold) {
      final list = List<CachedTorrent>.from(all);
      list.shuffle(Random());
      return list;
    }

    final selected = <CachedTorrent>[];
    final seenHashes = <String>{};

    if (normalizedKeywords.isNotEmpty) {
      for (final keyword in normalizedKeywords) {
        int count = 0;
        for (final cached in all) {
          if (!cached.keywords.contains(keyword)) continue;
          final hash = normalizeInfohash(cached.infohash);
          if (hash.isEmpty || seenHashes.contains(hash)) {
            continue;
          }
          selected.add(cached);
          seenHashes.add(hash);
          count++;
          if (count >= maxTorrentsPerKeywordPlayback) {
            break;
          }
        }
      }
    }

    if (selected.isEmpty) {
      return all.take(playbackTorrentThreshold).toList();
    }

    if (selected.length < playbackTorrentThreshold) {
      for (final cached in all) {
        final hash = normalizeInfohash(cached.infohash);
        if (hash.isEmpty || seenHashes.contains(hash)) {
          continue;
        }
        selected.add(cached);
        seenHashes.add(hash);
        if (selected.length >= playbackTorrentThreshold) {
          break;
        }
      }
    }

    final random = Random();
    selected.shuffle(random);
    return selected;
  }

  List<String> parseKeywords(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<TorboxCacheWindowResult> fetchTorboxCacheWindow({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  }) async {
    if (apiKey.isEmpty) {
      return TorboxCacheWindowResult(
        cachedTorrents: const <Torrent>[],
        nextCursor: startIndex,
        exhausted: startIndex >= candidates.length,
      );
    }
    const int chunkSize = 90;
    const int maxCalls = 2;

    int cursor = startIndex;
    int calls = 0;
    final List<Torrent> hits = <Torrent>[];

    while (cursor < candidates.length && calls < maxCalls && hits.isEmpty) {
      final int end = min(cursor + chunkSize, candidates.length);
      final List<Torrent> chunk = candidates.sublist(cursor, end);
      cursor = end;

      final List<String> hashes = chunk
          .map((torrent) => normalizeInfohash(torrent.infohash))
          .where((hash) => hash.isNotEmpty)
          .toList();

      if (hashes.isEmpty) {
        continue;
      }

      calls += 1;
      final Set<String> cachedHashes = await CloudProviderRegistry.instance
          .checkCachedHashes(hashes);

      if (cachedHashes.isEmpty) {
        continue;
      }

      final Set<String> normalized = cachedHashes
          .map((hash) => hash.trim().toLowerCase())
          .where((hash) => hash.isNotEmpty)
          .toSet();

      hits.addAll(
        chunk.where(
          (torrent) => normalized.contains(normalizeInfohash(torrent.infohash)),
        ),
      );
    }

    final bool exhausted = cursor >= candidates.length;
    return TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: exhausted,
    );
  }

  /// Quick-play twin of [applyQualityFilterToCached], for the live search
  /// results each provider accumulates.
  ///
  /// [allowFallback] must stay false while a search is still streaming in.
  /// Quick play rebuilds this list on every engine that reports, and the RD
  /// flow launches the player from the first rebuild that yields something
  /// playable — so falling back on a partial result set would start playing an
  /// off-filter source just because the fastest engine happened to return
  /// none. Strict here means the queue simply stays empty until a matching
  /// result arrives. Pass true only once the result set is final, where an
  /// empty match genuinely means "this search has nothing".
  List<Torrent> applyQualityFilterToTorrents(
    List<Torrent> torrents, {
    bool allowFallback = false,
  }) {
    if (!filters().hasQuality || torrents.isEmpty) return torrents;
    final matched = torrents
        .where((t) => filters().qualityMatchesName(t.name))
        .toList();
    if (matched.isEmpty && allowFallback) {
      onQualityFallback?.call();
      return torrents;
    }
    return matched;
  }

  /// Edit-prune: a torrent that carries **any** removed keyword is dropped
  /// entirely (even if it also has kept ones). Prune-to-empty marks `failed`
  /// and keeps the baseline error (`clearErrorMessage` only when torrents
  /// remain).
  DebrifyTvChannelCacheEntry pruneRemovedKeywords({
    required DebrifyTvChannelCacheEntry baseline,
    required List<String> normalizedKeywords,
    required Set<String> removedKeywords,
  }) {
    final filteredTorrents = baseline.torrents.where((cached) {
      final torrentKeywords = cached.keywords.toSet();
      return torrentKeywords.intersection(removedKeywords).isEmpty;
    }).toList();

    final filteredStats = Map<String, KeywordStat>.from(baseline.keywordStats)
      ..removeWhere((key, _) => removedKeywords.contains(key));

    final newStatus = filteredTorrents.isNotEmpty
        ? DebrifyTvCacheStatus.ready
        : DebrifyTvCacheStatus.failed;

    return baseline.copyWith(
      normalizedKeywords: normalizedKeywords,
      torrents: filteredTorrents,
      keywordStats: filteredStats,
      status: newStatus,
      clearErrorMessage: filteredTorrents.isNotEmpty,
    );
  }

  /// Incremental / full warm used by create-or-update. Progress dialog stays
  /// on the host via [ensureProgressDialog].
  Future<DebrifyTvChannelCacheEntry?> buildWorkingCacheForSave({
    required DebrifyTvChannel channel,
    required List<String> normalizedKeywords,
    required bool isEdit,
    DebrifyTvChannelCacheEntry? baseline,
    required void Function({int? countdownSeconds}) ensureProgressDialog,
  }) async {
    DebrifyTvChannelCacheEntry? workingEntry = baseline;
    final currentKeywordSet = normalizedKeywords.toSet();
    Set<String> addedKeywords = const <String>{};
    Set<String> removedKeywords = const <String>{};

    if (isEdit && baseline != null) {
      final previousKeywords = baseline.normalizedKeywords.toSet();
      removedKeywords = previousKeywords.difference(currentKeywordSet);
      addedKeywords = currentKeywordSet.difference(previousKeywords);

      debugPrint(
        'DebrifyTV: Detected keyword changes for "${channel.name}" – added: ${addedKeywords.join(', ')}, removed: ${removedKeywords.join(', ')}',
      );

      if (removedKeywords.isNotEmpty) {
        ensureProgressDialog();
        workingEntry = pruneRemovedKeywords(
          baseline: baseline,
          normalizedKeywords: normalizedKeywords,
          removedKeywords: removedKeywords,
        );

        debugPrint(
          'DebrifyTV: Pruned ${baseline.torrents.length - workingEntry.torrents.length} torrent(s) after removing keywords. Remaining: ${workingEntry.torrents.length}.',
        );
      } else if (baseline.normalizedKeywords.length !=
          normalizedKeywords.length) {
        workingEntry = baseline.copyWith(
          normalizedKeywords: normalizedKeywords,
        );
      }

      if (addedKeywords.isNotEmpty) {
        ensureProgressDialog(
          countdownSeconds: estimatedWarmDurationSeconds(
            addedKeywords.length,
            totalKeywordUniverse: normalizedKeywords.length,
          ),
        );
        debugPrint(
          'DebrifyTV: Warming new keywords for "${channel.name}": ${addedKeywords.join(', ')}',
        );
        workingEntry = await computeChannelCacheEntry(
          channel,
          normalizedKeywords,
          baseline: workingEntry,
          keywordsToSearch: addedKeywords,
        );
        debugPrint(
          'DebrifyTV: After warming new keywords, cache has ${workingEntry.torrents.length} torrent(s).',
        );
      }

      if (addedKeywords.isEmpty && removedKeywords.isEmpty) {
        debugPrint(
          'DebrifyTV: No keyword changes for "${channel.name}" – reusing existing cache.',
        );
        workingEntry = baseline.copyWith(
          normalizedKeywords: normalizedKeywords,
        );
      }
    } else {
      ensureProgressDialog();
      debugPrint('DebrifyTV: Running full warm-up for "${channel.name}"');
      workingEntry = await computeChannelCacheEntry(
        channel,
        normalizedKeywords,
      );
      debugPrint(
        'DebrifyTV: Initial warm-up complete for "${channel.name}" with ${workingEntry.torrents.length} torrent(s).',
      );
    }

    return workingEntry;
  }

  List<CachedTorrent> prependLeadTorrent({
    required List<CachedTorrent> playbackSelection,
    required CachedTorrent leadWith,
    required List<CachedTorrent> pool,
  }) {
    playbackSelection.removeWhere((t) => t.infohash == leadWith.infohash);
    playbackSelection.insert(0, leadWith);
    if (playbackSelection.length == 1 && pool.length > 1) {
      // The filter narrowed the selection to the pick alone while the pool
      // holds more: refill behind it from the wider pool (same cap the
      // selector uses), or an uncached pick would have nothing to fall
      // through to — the single-element queue the plan forbids.
      final rest = pool.where((t) => t.infohash != leadWith.infohash).toList()
        ..shuffle(Random());
      playbackSelection.addAll(rest.take(playbackTorrentThreshold));
    }
    return playbackSelection;
  }

  /// Whether an unrestricted Real-Debrid link may be played, per the size
  /// rules. RD is the one provider that hands back a flat list of links with
  /// no per-file metadata, so a file's size is only knowable AFTER
  /// unrestricting it — hence the check here rather than up front like the
  /// others. Links whose size RD doesn't report are accepted.
  ///
  /// Because RD can't pre-filter, a strict size choice could otherwise walk
  /// the entire queue rejecting everything. After
  /// [rdSizeRejectionLimit] consecutive size-only rejections the size filter
  /// is relaxed for the rest of the session (snack stays on the host via
  /// [onSizeFallback]) — the same degrade-don't-fail contract the other
  /// providers get per torrent.
  bool rdLinkPassesSizeRules(Map<String, dynamic> unrestrict) {
    final bytes = (unrestrict['filesize'] as num?)?.toInt() ?? 0;
    if (bytes <= 0) return true; // RD didn't report a size — don't guess.
    // Trailer/sample guard, matching Torbox/Premiumize/PikPak/AllDebrid.
    if (bytes < minVideoSizeBytes) return false;
    if (sizeFilterRelaxed || !filters().hasSize) return true;
    if (filters().sizeMatchesBytes(bytes)) {
      rdSizeRejections = 0;
      return true;
    }
    rdSizeRejections++;
    if (rdSizeRejections >= rdSizeRejectionLimit) {
      sizeFilterRelaxed = true;
      onSizeFallback?.call();
      return true;
    }
    return false;
  }
}
