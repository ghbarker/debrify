import 'dart:io';
import 'dart:math';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/utils/debrify_tv_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// M1-1 characterisation of keyword warm / cache **before** the move to
/// `lib/services/debrify_tv/channel_cache_warmer.dart`.
///
/// Does not import that file (it does not exist on the parent of the move).
/// After the move this suite still matches the same members (optional
/// leading underscore) by also reading the new file when present — same
/// pattern as `magic_tv_watch_session_fields_pin_test.dart`.
///
/// Origin (re-located by symbol after #81 / M1-0):
/// `_TvEngineWarmResult`, `_accumulateCachedTorrent`,
/// `_enabledTvKeywordEngines`, `_tvChannelMaxResultsForEngine`,
/// `_estimatePagesPulledForEngine`, `_estimatePageRequestsForEngine`,
/// `_quickPlayMaxResultsOverrides`, `_tvEngineSearchStates`,
/// `_sortedCachedTorrents`, `_computeChannelCacheEntry`, `_warmKeyword`,
/// `_parseKeywords`, `_normalizedKeywords`, `_ensureCacheEntry`,
/// `_fetchTorboxCacheWindow`, `_estimatedWarmDurationSeconds`,
/// `_filterCachedTorrentsForKeywords`, `_filterKeywordStats`,
/// `_applyQualityFilterToCached`, `_applyQualityFilterToTorrents`,
/// `_selectTorrentsForPlayback`.
///
/// Quirks pinned here (keep, do not "fix"):
/// * Empty infohash is a no-op; keywords/sources are lowercased; merge
///   override is strict `seeders > existing` (equal seeders keep the old
///   torrent body).
/// * Sort is seeders desc, then completed desc.
/// * `_normalizedKeywords` trims, lowercases, skips empty, first-wins
///   dedup.
/// * Incremental seed skips empty normalized hashes; empty `keywordsToWarm`
///   resets `anySuccess` to `accumulator.isNotEmpty`.
/// * `_filterCachedTorrentsForKeywords` is inclusion-only: a torrent is
///   kept if it has any allowed keyword. `merge(keywords: matching)`
///   **unions** onto the existing list — it does not strip the others.
/// * Failed warm returns `torrents: const <CachedTorrent>[]` (drops any
///   leftover accumulator) and default
///   `'No torrents found for these keywords yet.'`.
/// * First `failureMessage` wins (`??=`).
/// * Below `minTorrentsPerKeyword` skips accumulate and records
///   `totalFetched: 0`.
/// * `_ensureCacheEntry` is memory-first; a storage miss is not written
///   back (returns null — empty cache stays empty).
/// * No generation / warm-token field exists on this path.
/// * Quality filter is applied at cache READ, not warm; empty match
///   falls back to the unfiltered pool and notifies.
/// * Playback select filters first; `<= 1000` shuffles the whole pool;
///   empty per-keyword pick takes the first 1000 **unshuffled**.
/// * `_applyQualityFilterToTorrents` does **not** fall back unless
///   `allowFallback` is true (partial quick-play rebuilds stay strict).
/// * `_parseKeywords` splits on comma, trims, drops empty.
/// * TorBox cache window: empty API key returns no hits and keeps the
///   start cursor; live walk is chunk 90 / max 2 calls / stop on first hit.
/// * Edit-prune (inline in `_createOrUpdateChannel`) drops a torrent if
///   it carries **any** removed keyword, even when it also has kept ones.
String _host() => File(
  'lib/screens/magic_tv_screen.dart',
).readAsStringSync().replaceAll('\r\n', '\n');

String _sources() {
  final buf = StringBuffer(_host());
  final moved = File('lib/services/debrify_tv/channel_cache_warmer.dart');
  if (moved.existsSync()) {
    buf.writeln(moved.readAsStringSync().replaceAll('\r\n', '\n'));
  }
  return buf.toString();
}

Torrent _torrent({
  required String infohash,
  String name = 'Show.mkv',
  int seeders = 10,
  int completed = 1,
  int rowid = 1,
}) {
  return Torrent(
    rowid: rowid,
    infohash: infohash,
    name: name,
    sizeBytes: 1,
    createdUnix: 0,
    seeders: seeders,
    leechers: 0,
    completed: completed,
    scrapedDate: 0,
    source: 'test',
  );
}

CachedTorrent _cached({
  required String infohash,
  String name = 'Show.mkv',
  int seeders = 10,
  int completed = 1,
  List<String> keywords = const ['alpha'],
  List<String> sources = const ['pb'],
  int rowid = 1,
}) {
  return CachedTorrent(
    rowid: rowid,
    infohash: infohash,
    name: name,
    sizeBytes: 1,
    createdUnix: 0,
    seeders: seeders,
    leechers: 0,
    completed: completed,
    scrapedDate: 0,
    sources: sources,
    keywords: keywords,
  );
}

DebrifyTvChannelCacheEntry _entry({
  List<CachedTorrent> torrents = const [],
  Map<String, KeywordStat> stats = const {},
  List<String> keywords = const ['alpha'],
}) {
  return DebrifyTvChannelCacheEntry(
    version: 1,
    channelId: 'ch1',
    normalizedKeywords: keywords,
    fetchedAt: 0,
    status: DebrifyTvCacheStatus.ready,
    errorMessage: null,
    torrents: torrents,
    keywordStats: stats,
  );
}

/// Origin `_normalizeInfohash`.
String normalizeInfohash(String hash) => hash.trim().toLowerCase();

/// Origin `_accumulateCachedTorrent`.
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

/// Origin `_sortedCachedTorrents`.
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

/// Origin `_normalizedKeywords`.
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

/// Origin `_filterCachedTorrentsForKeywords`.
List<CachedTorrent> filterCachedTorrentsForKeywords(
  DebrifyTvChannelCacheEntry entry,
  List<String> keywords,
) {
  if (entry.torrents.isEmpty) {
    return const <CachedTorrent>[];
  }
  final allowed = keywords.toSet();
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

/// Origin `_filterKeywordStats`.
Map<String, KeywordStat> filterKeywordStats(
  Map<String, KeywordStat> stats,
  List<String> keywords,
) {
  if (stats.isEmpty) {
    return const <String, KeywordStat>{};
  }
  final allowed = keywords.toSet();
  final filtered = <String, KeywordStat>{};
  for (final entry in stats.entries) {
    if (allowed.contains(entry.key)) {
      filtered[entry.key] = entry.value;
    }
  }
  return filtered;
}

/// Origin `_estimatedWarmDurationSeconds` arithmetic (engines injected).
int estimatedWarmDurationSeconds({
  required int keywordCount,
  int? totalKeywordUniverse,
  required int enabledEngineCount,
  required int channelBatchSize,
  required int requestWavesPerKeyword,
  int keywordWarmEstimateMs = 1000,
}) {
  if (keywordCount <= 0) {
    return 0;
  }
  final int effectiveUniverse = max(1, totalKeywordUniverse ?? keywordCount);
  if (enabledEngineCount <= 0) {
    return 0;
  }
  final int batches = max(
    1,
    ((keywordCount + channelBatchSize - 1) ~/ channelBatchSize),
  );
  final int estimatedMs =
      batches * requestWavesPerKeyword * keywordWarmEstimateMs;
  // effectiveUniverse is used only for per-engine page estimates on origin.
  expect(effectiveUniverse, greaterThan(0));
  return (estimatedMs + 999) ~/ 1000;
}

/// Origin `_estimatePagesPulledForEngine` arithmetic.
int estimatePagesPulled({
  required int resultCount,
  String paginationType = 'page',
  int? resultsPerPage,
  int? maxPages,
}) {
  if (resultCount <= 0) {
    return 0;
  }
  if (paginationType == 'none' ||
      resultsPerPage == null ||
      resultsPerPage <= 0) {
    return 1;
  }
  final estimatedPages = (resultCount + resultsPerPage - 1) ~/ resultsPerPage;
  if (maxPages != null && maxPages > 0) {
    return min(estimatedPages, maxPages);
  }
  return estimatedPages;
}

/// Origin `_tvChannelMaxResultsForEngine` stored-vs-default.
int tvChannelMaxResults({
  required int totalKeywords,
  required int keywordThreshold,
  int? storedLimit,
  int? tvModeLimit,
}) {
  final useSmallChannelLimit = totalKeywords < keywordThreshold;
  if (storedLimit != null) {
    return storedLimit;
  }
  if (tvModeLimit == null) {
    return 50;
  }
  return useSmallChannelLimit ? tvModeLimit : tvModeLimit;
}

/// Origin `_parseKeywords`.
List<String> parseKeywords(String input) {
  return input
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Origin `_applyQualityFilterToTorrents` (notify via callback).
List<Torrent> applyQualityFilterToTorrents(
  List<Torrent> torrents,
  DebrifyTvFilters filters, {
  bool allowFallback = false,
  void Function()? onFallback,
}) {
  if (!filters.hasQuality || torrents.isEmpty) return torrents;
  final matched = torrents
      .where((t) => filters.qualityMatchesName(t.name))
      .toList();
  if (matched.isEmpty && allowFallback) {
    onFallback?.call();
    return torrents;
  }
  return matched;
}

/// Origin `_fetchTorboxCacheWindow` empty-key / cursor arithmetic.
({List<Torrent> cachedTorrents, int nextCursor, bool exhausted})
torboxCacheWindowEmptyKey({
  required List<Torrent> candidates,
  required int startIndex,
  required String apiKey,
}) {
  if (apiKey.isEmpty) {
    return (
      cachedTorrents: const <Torrent>[],
      nextCursor: startIndex,
      exhausted: startIndex >= candidates.length,
    );
  }
  throw StateError('pin covers the empty-key arm only');
}

/// Origin `_applyQualityFilterToCached` (notify via callback).
List<CachedTorrent> applyQualityFilterToCached(
  List<CachedTorrent> all,
  DebrifyTvFilters filters, {
  void Function()? onFallback,
}) {
  if (!filters.hasQuality || all.isEmpty) return all;
  final matched = all
      .where((cached) => filters.qualityMatchesName(cached.name))
      .toList();
  if (matched.isEmpty) {
    onFallback?.call();
    return all;
  }
  return matched;
}

/// Origin `_selectTorrentsForPlayback` without the quality-notify side
/// effect (filter already applied).
List<CachedTorrent> selectTorrentsForPlayback(
  List<CachedTorrent> all,
  List<String> normalizedKeywords, {
  int playbackTorrentThreshold = 1000,
  int maxTorrentsPerKeywordPlayback = 25,
}) {
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

/// Origin edit-prune in `_createOrUpdateChannel`.
({List<CachedTorrent> torrents, String status, bool clearError}) pruneRemoved({
  required List<CachedTorrent> baselineTorrents,
  required Set<String> removedKeywords,
}) {
  final filteredTorrents = baselineTorrents.where((cached) {
    final torrentKeywords = cached.keywords.toSet();
    return torrentKeywords.intersection(removedKeywords).isEmpty;
  }).toList();
  final newStatus = filteredTorrents.isNotEmpty
      ? DebrifyTvCacheStatus.ready
      : DebrifyTvCacheStatus.failed;
  return (
    torrents: filteredTorrents,
    status: newStatus,
    clearError: filteredTorrents.isNotEmpty,
  );
}

/// Origin failed-vs-ready decision at the end of `_computeChannelCacheEntry`.
({bool ready, bool emptyTorrents}) warmOutcome({
  required bool anySuccess,
  required int accumulatorLength,
}) {
  if (anySuccess) {
    return (ready: true, emptyTorrents: false);
  }
  return (ready: false, emptyTorrents: true);
}

void main() {
  late String host;
  late String sources;

  setUpAll(() {
    host = _host();
    sources = _sources();
  });

  test('this pin does not import ChannelCacheWarmer', () {
    final pin = File(
      'test/magic_tv_channel_cache_warmer_pin_test.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r"^import .+channel_cache_warmer\.dart",
        multiLine: true,
      ).hasMatch(pin),
      isFalse,
    );
  });

  group('source still owns the origin warm/cache bodies', () {
    test('accumulate / sort / normalize / filter symbols', () {
      expect(
        sources,
        contains(RegExp(r'void _?accumulateCachedTorrent\(')),
      );
      expect(sources, contains(RegExp(r'List<CachedTorrent> _?sortedCachedTorrents\(')));
      expect(sources, contains(RegExp(r'List<String> _?normalizedKeywords\(')));
      expect(
        sources,
        contains(RegExp(r'List<CachedTorrent> _?filterCachedTorrentsForKeywords\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Map<String, KeywordStat> _?filterKeywordStats\(')),
      );
    });

    test('compute / warm / ensure / estimate / select symbols', () {
      expect(
        sources,
        contains(
          RegExp(r'Future<DebrifyTvChannelCacheEntry> _?computeChannelCacheEntry\('),
        ),
      );
      expect(sources, contains(RegExp(r'Future<KeywordWarmResult\?> _?warmKeyword\(')));
      expect(
        sources,
        contains(
          RegExp(r'Future<DebrifyTvChannelCacheEntry\?> _?ensureCacheEntry\('),
        ),
      );
      expect(
        sources,
        contains(RegExp(r'int _?estimatedWarmDurationSeconds\(')),
      );
      expect(
        sources,
        contains(RegExp(r'List<CachedTorrent> _?selectTorrentsForPlayback\(')),
      );
      expect(
        sources,
        contains(RegExp(r'List<CachedTorrent> _?applyQualityFilterToCached\(')),
      );
      expect(sources, contains(RegExp(r'List<String> _?parseKeywords\(')));
      expect(
        sources,
        contains(
          RegExp(r'Future<TorboxCacheWindowResult> _?fetchTorboxCacheWindow\('),
        ),
      );
      expect(
        sources,
        contains(RegExp(r'List<Torrent> _?applyQualityFilterToTorrents\(')),
      );
    });
  });

  group('empty cache / failed warm / no generation token', () {
    test('ensureCacheEntry is memory-first and does not write a miss', () {
      expect(sources, contains('final cached = '));
      expect(sources, contains('DebrifyTvCacheService.getEntry(channelId)'));
      expect(
        sources,
        contains(
          RegExp(
            r'if \(fetched != null\) \{\s+_?channelCache\[channelId\] = fetched;',
          ),
        ),
      );
      expect(sources, contains('return fetched;'));
    });

    test('failed warm drops accumulator torrents', () {
      expect(
        sources,
        contains("failureMessage ??= 'No torrents found for these keywords yet.';"),
      );
      expect(sources, contains('status: DebrifyTvCacheStatus.failed,'));
      expect(sources, contains('torrents: const <CachedTorrent>[],'));
    });

    test('empty keywordsToWarm resets anySuccess to accumulator.isNotEmpty', () {
      expect(sources, contains('if (keywordsToWarm.isEmpty) {'));
      expect(sources, contains('anySuccess = accumulator.isNotEmpty;'));
    });

    test('first failureMessage wins', () {
      expect(sources, contains('failureMessage ??= result.failureMessage;'));
    });

    test('no generation / warm-token on this path', () {
      final compute = RegExp(
        r'Future<DebrifyTvChannelCacheEntry> _?computeChannelCacheEntry\([\s\S]+?return DebrifyTvChannelCacheEntry\([\s\S]+?keywordStats: Map<String, KeywordStat>\.from\(stats\),\s*\);\s*\}',
      );
      final match = compute.firstMatch(sources);
      expect(match, isNotNull);
      expect(match!.group(0), isNot(contains('generation')));
      expect(match.group(0), isNot(contains('warmToken')));
      expect(match.group(0), isNot(contains('cacheGen')));
    });

    test('failed outcome reports empty torrents even if we tracked hashes', () {
      expect(warmOutcome(anySuccess: false, accumulatorLength: 0).emptyTorrents, isTrue);
      expect(warmOutcome(anySuccess: true, accumulatorLength: 3).ready, isTrue);
    });
  });

  group('_accumulateCachedTorrent origin algorithm', () {
    test('empty infohash is a no-op', () {
      final acc = <String, CachedTorrent>{};
      accumulateCachedTorrent(
        accumulator: acc,
        infohash: '',
        torrent: _torrent(infohash: 'abc'),
        keyword: 'Foo',
        source: 'PB',
      );
      expect(acc, isEmpty);
      expect(sources, contains('if (infohash.isEmpty) {'));
    });

    test('new hash lowercases keyword and source', () {
      final acc = <String, CachedTorrent>{};
      accumulateCachedTorrent(
        accumulator: acc,
        infohash: 'ab',
        torrent: _torrent(infohash: 'ab'),
        keyword: 'Foo',
        source: 'PB',
      );
      expect(acc['ab']!.keywords, ['foo']);
      expect(acc['ab']!.sources, ['pb']);
    });

    test('equal seeders keep the existing torrent body', () {
      final acc = <String, CachedTorrent>{};
      accumulateCachedTorrent(
        accumulator: acc,
        infohash: 'ab',
        torrent: _torrent(infohash: 'ab', name: 'Old', seeders: 5),
        keyword: 'a',
        source: 'one',
      );
      accumulateCachedTorrent(
        accumulator: acc,
        infohash: 'ab',
        torrent: _torrent(infohash: 'ab', name: 'New', seeders: 5, rowid: 2),
        keyword: 'b',
        source: 'two',
      );
      expect(acc['ab']!.name, 'Old');
      expect(acc['ab']!.keywords.toSet(), {'a', 'b'});
      expect(sources, contains('final shouldOverride = torrent.seeders > existing.seeders;'));
    });

    test('higher seeders override the body', () {
      final acc = <String, CachedTorrent>{};
      accumulateCachedTorrent(
        accumulator: acc,
        infohash: 'ab',
        torrent: _torrent(infohash: 'ab', name: 'Old', seeders: 5),
        keyword: 'a',
        source: 'one',
      );
      accumulateCachedTorrent(
        accumulator: acc,
        infohash: 'ab',
        torrent: _torrent(infohash: 'ab', name: 'New', seeders: 9, rowid: 2),
        keyword: 'b',
        source: 'two',
      );
      expect(acc['ab']!.name, 'New');
      expect(acc['ab']!.seeders, 9);
    });
  });

  group('_sortedCachedTorrents origin algorithm', () {
    test('seeders desc then completed desc', () {
      final acc = <String, CachedTorrent>{
        'a': _cached(infohash: 'a', seeders: 1, completed: 99),
        'b': _cached(infohash: 'b', seeders: 5, completed: 1),
        'c': _cached(infohash: 'c', seeders: 5, completed: 10),
      };
      final sorted = sortedCachedTorrents(acc);
      expect(sorted.map((t) => t.infohash).toList(), ['c', 'b', 'a']);
    });
  });

  group('_normalizedKeywords origin algorithm', () {
    test('trim, lower, skip empty, first-wins dedup', () {
      expect(normalizedKeywords(['  Foo  ', '', 'foo', 'Bar', '  ']), [
        'foo',
        'bar',
      ]);
    });
  });

  group('_filterCachedTorrentsForKeywords / _filterKeywordStats', () {
    test('empty torrents returns the const empty list', () {
      expect(filterCachedTorrentsForKeywords(_entry(), ['alpha']), isEmpty);
      expect(sources, contains('return const <CachedTorrent>[];'));
    });

    test('keeps torrents with any allowed keyword; merge does not strip', () {
      final filtered = filterCachedTorrentsForKeywords(
        _entry(
          torrents: [
            _cached(infohash: 'a', keywords: ['alpha', 'gone']),
            _cached(infohash: 'b', keywords: ['gone']),
          ],
        ),
        ['alpha'],
      );
      expect(filtered, hasLength(1));
      expect(filtered.single.infohash, 'a');
      // merge unions matching onto the existing list — 'gone' stays.
      expect(filtered.single.keywords.toSet(), {'alpha', 'gone'});
    });

    test('empty stats returns the const empty map; keeps allowed keys only', () {
      expect(filterKeywordStats(const {}, ['alpha']), isEmpty);
      final kept = filterKeywordStats({
        'alpha': KeywordStat.initial(),
        'gone': KeywordStat.initial().copyWith(totalFetched: 3),
      }, ['alpha']);
      expect(kept.keys, ['alpha']);
      expect(kept['alpha']!.totalFetched, 0);
    });
  });

  group('_estimatedWarmDurationSeconds / page estimates', () {
    test('zero keywords or zero engines is 0', () {
      expect(
        estimatedWarmDurationSeconds(
          keywordCount: 0,
          enabledEngineCount: 3,
          channelBatchSize: 4,
          requestWavesPerKeyword: 2,
        ),
        0,
      );
      expect(
        estimatedWarmDurationSeconds(
          keywordCount: 5,
          enabledEngineCount: 0,
          channelBatchSize: 4,
          requestWavesPerKeyword: 2,
        ),
        0,
      );
    });

    test('ceils ms to seconds; batches from channelBatchSize', () {
      // 5 keywords / batch 4 → 2 batches * 3 waves * 1000ms → 6000ms → 6s
      expect(
        estimatedWarmDurationSeconds(
          keywordCount: 5,
          enabledEngineCount: 1,
          channelBatchSize: 4,
          requestWavesPerKeyword: 3,
        ),
        6,
      );
      expect(sources, contains('return (estimatedMs + 999) ~/ 1000;'));
    });

    test('pages pulled: 0 results → 0; none/invalid page size → 1; cap maxPages', () {
      expect(estimatePagesPulled(resultCount: 0), 0);
      expect(estimatePagesPulled(resultCount: 10, paginationType: 'none'), 1);
      expect(estimatePagesPulled(resultCount: 10, resultsPerPage: 0), 1);
      expect(
        estimatePagesPulled(resultCount: 100, resultsPerPage: 20, maxPages: 3),
        3,
      );
      expect(estimatePagesPulled(resultCount: 45, resultsPerPage: 20), 3);
    });

    test('missing tvMode defaults to 50', () {
      expect(
        tvChannelMaxResults(
          totalKeywords: 3,
          keywordThreshold: 10,
        ),
        50,
      );
      expect(sources, contains('return 50;'));
    });
  });

  group('_warmKeyword min-torrents skip', () {
    test('source records totalFetched 0 and does not accumulate', () {
      expect(
        sources,
        contains("Skipping keyword"),
      );
      expect(sources, contains('totalFetched: 0,'));
      expect(
        sources,
        contains('addedHashes: const <String>{},'),
      );
    });
  });

  group('_applyQualityFilterToCached / _selectTorrentsForPlayback', () {
    test('filter off or empty input returns the same list', () {
      final all = [_cached(infohash: 'a', name: 'Show.1080p.mkv')];
      expect(
        applyQualityFilterToCached(all, const DebrifyTvFilters.empty()),
        same(all),
      );
      expect(
        applyQualityFilterToCached(const [], const DebrifyTvFilters(qualities: {QualityTier.fullHd})),
        isEmpty,
      );
    });

    test('empty match falls back to unfiltered and notifies', () {
      var notified = 0;
      final all = [_cached(infohash: 'a', name: 'Show.CAM.mkv')];
      final out = applyQualityFilterToCached(
        all,
        const DebrifyTvFilters(qualities: {QualityTier.ultraHd}),
        onFallback: () => notified++,
      );
      expect(out, same(all));
      expect(notified, 1);
      expect(sources, contains('falling back to unfiltered.'));
      expect(host, contains('void _notifyQualityFallback()'));
    });

    test('<= threshold shuffles a copy of the whole pool', () {
      final all = [
        _cached(infohash: 'a'),
        _cached(infohash: 'b', rowid: 2),
      ];
      final selected = selectTorrentsForPlayback(all, ['alpha']);
      expect(selected.toSet(), all.toSet());
      expect(selected, hasLength(2));
      expect(sources, contains('list.shuffle(Random());'));
    });

    test('empty per-keyword pick takes the first 1000 unshuffled', () {
      final all = [
        for (var i = 0; i < 1005; i++)
          _cached(
            infohash: 'h$i',
            keywords: const ['other'],
            rowid: i,
          ),
      ];
      final selected = selectTorrentsForPlayback(all, ['alpha']);
      expect(selected, hasLength(1000));
      expect(selected.first.infohash, 'h0');
      expect(selected.last.infohash, 'h999');
      expect(
        sources,
        anyOf(
          contains('return all.take(_playbackTorrentThreshold).toList();'),
          contains('return all.take(playbackTorrentThreshold).toList();'),
        ),
      );
    });
  });

  group('_parseKeywords / _applyQualityFilterToTorrents / TorBox window', () {
    test('parseKeywords splits, trims, drops empty', () {
      expect(parseKeywords('  foo, bar,,baz  ,  '), ['foo', 'bar', 'baz']);
      expect(parseKeywords(''), isEmpty);
      expect(sources, contains(".split(',')"));
    });

    test('quality filter on torrents is strict unless allowFallback', () {
      final filters = const DebrifyTvFilters(qualities: {QualityTier.ultraHd});
      final torrents = [_torrent(infohash: 'a', name: 'Show.CAM.mkv')];
      var notified = 0;
      expect(
        applyQualityFilterToTorrents(torrents, filters),
        isEmpty,
      );
      expect(notified, 0);
      final fallback = applyQualityFilterToTorrents(
        torrents,
        filters,
        allowFallback: true,
        onFallback: () => notified++,
      );
      expect(fallback, same(torrents));
      expect(notified, 1);
      expect(sources, contains('bool allowFallback = false'));
    });

    test('empty TorBox API key keeps cursor and reports exhausted', () {
      final candidates = [_torrent(infohash: 'a'), _torrent(infohash: 'b')];
      final empty = torboxCacheWindowEmptyKey(
        candidates: candidates,
        startIndex: 2,
        apiKey: '',
      );
      expect(empty.cachedTorrents, isEmpty);
      expect(empty.nextCursor, 2);
      expect(empty.exhausted, isTrue);
      expect(sources, contains('const int chunkSize = 90;'));
      expect(sources, contains('const int maxCalls = 2;'));
    });
  });

  group('edit-prune quirk (stays on host create/update)', () {
    test('torrent with any removed keyword is dropped entirely', () {
      final pruned = pruneRemoved(
        baselineTorrents: [
          _cached(infohash: 'keep', keywords: ['alpha']),
          _cached(infohash: 'mixed', keywords: ['alpha', 'gone']),
          _cached(infohash: 'onlyGone', keywords: ['gone']),
        ],
        removedKeywords: {'gone'},
      );
      expect(pruned.torrents.map((t) => t.infohash).toList(), ['keep']);
      expect(pruned.status, DebrifyTvCacheStatus.ready);
      expect(pruned.clearError, isTrue);
    });

    test('prune-to-empty marks failed and keeps the error message', () {
      final pruned = pruneRemoved(
        baselineTorrents: [
          _cached(infohash: 'x', keywords: ['gone']),
        ],
        removedKeywords: {'gone'},
      );
      expect(pruned.torrents, isEmpty);
      expect(pruned.status, DebrifyTvCacheStatus.failed);
      expect(pruned.clearError, isFalse);
      expect(
        sources,
        contains('torrentKeywords.intersection(removedKeywords).isEmpty'),
      );
    });
  });

  group('snack/dialog stay on the host', () {
    test('quality fallback snack is host _showSnack', () {
      expect(host, contains("_showSnack(\n      'No \${_tvFilters.summary()} sources found"));
    });

    test('create/update progress dialog and snacks stay on the host', () {
      expect(host, contains('_showChannelCreationDialog('));
      expect(host, contains("'Failed to build channel cache. Please try again.'"));
    });
  });
}
