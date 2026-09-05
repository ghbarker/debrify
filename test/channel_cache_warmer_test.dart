import 'dart:io';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/debrify_tv/channel_cache_warmer.dart';
import 'package:debrify/utils/debrify_tv_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live tests of the moved [ChannelCacheWarmer] body. The origin pin
/// (`magic_tv_channel_cache_warmer_pin_test.dart`) stays import-free and
/// unedited. Quirks match that pin — do not "fix".
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

ChannelCacheWarmer _warmer({
  bool viewerForcesNsfw = false,
  DebrifyTvFilters filters = const DebrifyTvFilters.empty(),
  void Function()? onQualityFallback,
}) {
  return ChannelCacheWarmer(
    viewerForcesNsfw: () => viewerForcesNsfw,
    filters: () => filters,
    minVideoSizeBytes: 50 * 1024 * 1024,
    onQualityFallback: onQualityFallback,
  );
}

void main() {
  test('normalizeInfohash trims and lowercases', () {
    expect(ChannelCacheWarmer.normalizeInfohash('  AbC  '), 'abc');
  });

  test('empty infohash accumulate is a no-op', () {
    final warmer = _warmer();
    final acc = <String, CachedTorrent>{};
    warmer.accumulateCachedTorrent(
      accumulator: acc,
      infohash: '',
      torrent: _torrent(infohash: 'abc'),
      keyword: 'Foo',
      source: 'PB',
    );
    expect(acc, isEmpty);
  });

  test('equal seeders keep the existing torrent body', () {
    final warmer = _warmer();
    final acc = <String, CachedTorrent>{};
    warmer.accumulateCachedTorrent(
      accumulator: acc,
      infohash: 'ab',
      torrent: _torrent(infohash: 'ab', name: 'Old', seeders: 5),
      keyword: 'a',
      source: 'one',
    );
    warmer.accumulateCachedTorrent(
      accumulator: acc,
      infohash: 'ab',
      torrent: _torrent(infohash: 'ab', name: 'New', seeders: 5, rowid: 2),
      keyword: 'b',
      source: 'two',
    );
    expect(acc['ab']!.name, 'Old');
    expect(acc['ab']!.keywords.toSet(), {'a', 'b'});
  });

  test('sort is seeders desc then completed desc', () {
    final warmer = _warmer();
    final sorted = warmer.sortedCachedTorrents({
      'a': _cached(infohash: 'a', seeders: 1, completed: 99),
      'b': _cached(infohash: 'b', seeders: 5, completed: 1),
      'c': _cached(infohash: 'c', seeders: 5, completed: 10),
    });
    expect(sorted.map((t) => t.infohash).toList(), ['c', 'b', 'a']);
  });

  test('normalizedKeywords trims, lowers, first-wins dedup', () {
    expect(_warmer().normalizedKeywords(['  Foo  ', '', 'foo', 'Bar', '  ']), [
      'foo',
      'bar',
    ]);
  });

  test('keyword filter is inclusion-only; merge does not strip', () {
    final filtered = _warmer().filterCachedTorrentsForKeywords(
      _entry(
        torrents: [
          _cached(infohash: 'a', keywords: ['alpha', 'gone']),
          _cached(infohash: 'b', keywords: ['gone']),
        ],
      ),
      ['alpha'],
    );
    expect(filtered, hasLength(1));
    expect(filtered.single.keywords.toSet(), {'alpha', 'gone'});
  });

  test('ensureCacheEntry is memory-first and does not write a miss', () async {
    final warmer = _warmer();
    final entry = _entry();
    warmer.channelCache['ch1'] = entry;
    expect(await warmer.ensureCacheEntry('ch1'), same(entry));
  });

  test('quality filter empty match falls back and notifies', () {
    var notified = 0;
    final warmer = _warmer(
      filters: const DebrifyTvFilters(qualities: {QualityTier.ultraHd}),
      onQualityFallback: () => notified++,
    );
    final all = [_cached(infohash: 'a', name: 'Show.CAM.mkv')];
    expect(warmer.applyQualityFilterToCached(all), same(all));
    expect(notified, 1);
  });

  test('select empty per-keyword pick takes the first 1000 unshuffled', () {
    final all = [
      for (var i = 0; i < 1005; i++)
        _cached(infohash: 'h$i', keywords: const ['other'], rowid: i),
    ];
    final selected = _warmer().selectTorrentsForPlayback(
      _entry(torrents: all, keywords: ['alpha']),
      ['alpha'],
    );
    expect(selected, hasLength(1000));
    expect(selected.first.infohash, 'h0');
    expect(selected.last.infohash, 'h999');
  });

  test('estimatedWarmDurationSeconds is 0 when keywordCount is 0', () {
    expect(_warmer().estimatedWarmDurationSeconds(0), 0);
  });

  test('parseKeywords splits, trims, drops empty', () {
    expect(_warmer().parseKeywords('  foo, bar,,baz  ,  '), [
      'foo',
      'bar',
      'baz',
    ]);
    expect(_warmer().parseKeywords(''), isEmpty);
  });

  test('quality filter on torrents is strict unless allowFallback', () {
    var notified = 0;
    final warmer = _warmer(
      filters: const DebrifyTvFilters(qualities: {QualityTier.ultraHd}),
      onQualityFallback: () => notified++,
    );
    final torrents = [_torrent(infohash: 'a', name: 'Show.CAM.mkv')];
    expect(warmer.applyQualityFilterToTorrents(torrents), isEmpty);
    expect(notified, 0);
    expect(
      warmer.applyQualityFilterToTorrents(torrents, allowFallback: true),
      same(torrents),
    );
    expect(notified, 1);
  });

  test('empty TorBox API key keeps cursor and reports exhausted', () async {
    final candidates = [_torrent(infohash: 'a'), _torrent(infohash: 'b')];
    final empty = await _warmer().fetchTorboxCacheWindow(
      candidates: candidates,
      startIndex: 2,
      apiKey: '',
    );
    expect(empty.cachedTorrents, isEmpty);
    expect(empty.nextCursor, 2);
    expect(empty.exhausted, isTrue);
  });

  test('edit-prune drops a torrent that carries any removed keyword', () {
    final pruned = _warmer().pruneRemovedKeywords(
      baseline: _entry(
        torrents: [
          _cached(infohash: 'keep', keywords: ['alpha']),
          _cached(infohash: 'mixed', keywords: ['alpha', 'gone']),
          _cached(infohash: 'onlyGone', keywords: ['gone']),
        ],
      ),
      normalizedKeywords: const ['alpha'],
      removedKeywords: {'gone'},
    );
    expect(pruned.torrents.map((t) => t.infohash).toList(), ['keep']);
    expect(pruned.status, DebrifyTvCacheStatus.ready);
  });

  test('rd size filter relaxes after consecutive rejections', () {
    var snacks = 0;
    final warmer = ChannelCacheWarmer(
      viewerForcesNsfw: () => false,
      filters: () => const DebrifyTvFilters(sizes: {SizeBucket.gb2p5to4}),
      minVideoSizeBytes: 50 * 1024 * 1024,
      onSizeFallback: () => snacks++,
    );
    // 80 MiB is above the trailer floor and outside the 2.5–4 GB bucket.
    final unrestrict = {'filesize': 80 * 1024 * 1024};
    for (var i = 0; i < ChannelCacheWarmer.rdSizeRejectionLimit - 1; i++) {
      expect(warmer.rdLinkPassesSizeRules(unrestrict), isFalse);
    }
    expect(warmer.rdLinkPassesSizeRules(unrestrict), isTrue);
    expect(snacks, 1);
    expect(warmer.sizeFilterRelaxed, isTrue);
  });

  test('no part of / extension on the host State', () {
    final source = File('lib/services/debrify_tv/channel_cache_warmer.dart')
        .readAsStringSync();
    expect(source, isNot(contains('part of')));
    expect(source, isNot(contains('extension on _DebrifyTVScreenState')));
    expect(source, isNot(contains('_queue')));
    expect(source, isNot(contains('_isBusy')));
    expect(source, isNot(contains('_showSnack')));
  });
}
