import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Pin of IPTV zap ring + catch-up *before* `IptvZapController`.
///
/// Origin: `lib/screens/video_player_screen.dart`
/// `IptvCatchupRequestGate` (~138–163), `_cancelPendingIptvCatchup` (~940),
/// `_effectiveIptvChannels` / `_iptvZapBannerOwnsIdentity` (~705–711),
/// `_parseIptvZapPage` / `_zapIptvChannel` / `_prefetchIptvZapPage`
/// / page cache (~5053–5663), `_playIptvCatchup` (~5668–5724),
/// zap banner raise/hide/ticker (~9807–9945).
///
/// This file must not import `iptv_zap_controller.dart`.
///
/// Decision ladders are transcribed from the origin and source-locked. After
/// the move the same bodies live on the extracted file; this pin must keep
/// passing without edits (gate h).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final origin = _zapOriginSource();

  group('catch-up request gate (origin IptvCatchupRequestGate)', () {
    test(
      'begin strands the previous ticket; cancel strands the active one',
      () {
        final gate = _OriginCatchupGate();
        final first = gate.begin();
        final second = gate.begin();
        expect(gate.isCurrent(first), isFalse);
        expect(gate.isCurrent(second), isTrue);
        expect(gate.cancel(), isTrue);
        expect(gate.isCurrent(second), isFalse);
        expect(gate.complete(second), isFalse);
        expect(gate.cancel(), isFalse);

        final third = gate.begin();
        expect(gate.complete(third), isTrue);
        expect(gate.isCurrent(third), isFalse);
        expect(origin, contains('class IptvCatchupRequestGate'));
        expect(
          origin,
          contains('_activeTicket == ticket && _generation == ticket'),
        );
      },
    );
  });

  group('effective list + identity (origin _effectiveIptvChannels)', () {
    test('override wins; launch list is the fallback', () {
      expect(
        _originEffectiveChannels(override: const ['a'], launch: const ['b']),
        const ['a'],
      );
      expect(
        _originEffectiveChannels(override: null, launch: const ['b']),
        const ['b'],
      );
      expect(_originEffectiveChannels(override: null, launch: null), isNull);
      expect(origin, contains('_iptvChannelsOverride ?? widget.iptvChannels'));
    });

    test('banner owns identity only for a live current channel', () {
      expect(_originBannerOwnsIdentity(isLive: true), isTrue);
      expect(_originBannerOwnsIdentity(isLive: false), isFalse);
      expect(_originBannerOwnsIdentity(isLive: null), isFalse);
      expect(origin, contains('_currentIptvChannel?.isLive == true'));
    });

    test('can zap when live and (ring > 1 or paging is active)', () {
      expect(
        _originCanZap(isLive: true, ringLength: 2, pagingActive: false),
        isTrue,
      );
      expect(
        _originCanZap(isLive: true, ringLength: 1, pagingActive: true),
        isTrue,
      );
      expect(
        _originCanZap(isLive: true, ringLength: 1, pagingActive: false),
        isFalse,
      );
      expect(
        _originCanZap(isLive: false, ringLength: 8, pagingActive: true),
        isFalse,
      );
      expect(origin, contains('_iptvZapPagingActive'));
    });
  });

  group('zap page parse (origin _parseIptvZapPage)', () {
    test('missing channels list is a miss', () {
      expect(_originParseZapPage({'pageOffset': 0}), isNull);
      expect(origin, contains("final raw = result['channels']"));
      expect(origin, contains('if (raw is! List) return null'));
    });

    test('total covers the page; empty source/category become null', () {
      final page = _originParseZapPage({
        'channels': [
          {'name': 'One', 'url': 'http://a'},
        ],
        'pageOffset': 10,
        'totalChannels': 4,
        'sourceId': '  ',
        'selectedCategory': '',
        'categories': ['News', '', 'Sports'],
      });
      expect(page, isNotNull);
      expect(page!.offset, 10);
      expect(page.total, 11);
      expect(page.sourceId, isNull);
      expect(page.category, isNull);
      expect(page.categories, const ['News', 'Sports']);
      expect(origin, contains("result['pageOffset']"));
      expect(origin, contains("result['totalChannels']"));
      expect(origin, contains("result['selectedCategory']"));
      expect(origin, contains('math.max(total, offset + channels.length)'));
    });

    test('absent totals fall back to the parsed channel count', () {
      final page = _originParseZapPage({
        'channels': [
          {'name': 'A', 'url': 'http://a'},
          {'name': 'B', 'url': 'http://b'},
        ],
      });
      expect(page!.offset, 0);
      expect(page.total, 2);
    });
  });

  group('zap ladder (origin _zapIptvChannel)', () {
    test('no-ops without a live ring', () {
      expect(
        _originZapDecision(channels: 0, isLive: true),
        _OriginZapPath.noop,
      );
      expect(
        _originZapDecision(channels: 3, isLive: false),
        _OriginZapPath.noop,
      );
      expect(
        _originZapDecision(channels: 1, isLive: true, pagingActive: false),
        _OriginZapPath.noop,
      );
    });

    test('unpaged ring wraps by modulo and arms paging', () {
      expect(
        _originZapDecision(
          channels: 4,
          index: 0,
          delta: -1,
          pagingActive: false,
        ),
        _OriginZapPath.wrapAndArm,
      );
      expect(_originZapIndex(from: 0, delta: -1, length: 4), 3);
      expect(_originZapIndex(from: 3, delta: 1, length: 4), 0);
      expect(origin, contains('(next + channels.length) % channels.length'));
      expect(origin, contains('_ensureIptvZapPagingArmed()'));
    });

    test('in-window step switches and prefetches both ways', () {
      expect(
        _originZapDecision(
          channels: 20,
          index: 5,
          delta: 1,
          pagingActive: true,
        ),
        _OriginZapPath.switchAndPrefetch,
      );
      expect(origin, contains('unawaited(_prefetchIptvZapPage(delta))'));
      expect(
        origin,
        contains('unawaited(_prefetchAdjacentIptvCategory(delta))'),
      );
    });

    test('window edge with another page queues and prefetches', () {
      expect(
        _originZapDecision(
          channels: 10,
          index: 9,
          delta: 1,
          pagingActive: true,
          windowOffset: 0,
          categoryTotal: 40,
        ),
        _OriginZapPath.queueAndPrefetch,
      );
      expect(
        _originZapDecision(
          channels: 10,
          index: 0,
          delta: -1,
          pagingActive: true,
          windowOffset: 20,
          categoryTotal: 40,
        ),
        _OriginZapPath.queueAndPrefetch,
      );
      expect(origin, contains('_queuePendingIptvZapInput(delta)'));
    });

    test('category end consumes cache or requests the neighbour', () {
      expect(
        _originZapDecision(
          channels: 10,
          index: 9,
          delta: 1,
          pagingActive: true,
          windowOffset: 0,
          categoryTotal: 10,
          cacheHit: true,
        ),
        _OriginZapPath.consumeCache,
      );
      expect(
        _originZapDecision(
          channels: 10,
          index: 9,
          delta: 1,
          pagingActive: true,
          windowOffset: 0,
          categoryTotal: 10,
          cacheHit: false,
        ),
        _OriginZapPath.requestAdjacent,
      );
      expect(origin, contains('_consumeCachedAdjacentIptvCategory(delta)'));
      expect(origin, contains('_requestAdjacentIptvCategory(delta)'));
    });
  });

  group('prefetch + cache (origin _prefetchIptvZapPage)', () {
    test('edge margin is 12 and page size is 1500', () {
      expect(origin, contains('static const int _kIptvZapPageSize = 1500'));
      expect(origin, contains('static const int _kIptvZapEdgeMargin = 12'));
    });

    test('page prefetch only near the window edge that still has catalog', () {
      // Forward: length 20, margin 12 → index >= 8 and more catalog past the window.
      expect(
        _originShouldPrefetchPage(
          delta: 1,
          index: 7,
          length: 20,
          windowOffset: 0,
          categoryTotal: 40,
        ),
        isFalse,
      );
      expect(
        _originShouldPrefetchPage(
          delta: 1,
          index: 8,
          length: 20,
          windowOffset: 0,
          categoryTotal: 40,
        ),
        isTrue,
      );
      expect(
        _originShouldPrefetchPage(
          delta: 1,
          index: 19,
          length: 20,
          windowOffset: 0,
          categoryTotal: 20,
        ),
        isFalse,
      );
      // Backward: firstAbsolute > 0 and index < 12.
      expect(
        _originShouldPrefetchPage(
          delta: -1,
          index: 12,
          length: 20,
          windowOffset: 10,
          categoryTotal: 40,
        ),
        isFalse,
      );
      expect(
        _originShouldPrefetchPage(
          delta: -1,
          index: 11,
          length: 20,
          windowOffset: 10,
          categoryTotal: 40,
        ),
        isTrue,
      );
      expect(
        _originShouldPrefetchPage(
          delta: -1,
          index: 5,
          length: 20,
          windowOffset: 0,
          categoryTotal: 40,
        ),
        isFalse,
      );
      expect(
        origin,
        contains('_currentIptvIndex >= channels.length - _kIptvZapEdgeMargin'),
      );
      expect(origin, contains('_currentIptvIndex < _kIptvZapEdgeMargin'));
    });

    test('adjacent-category prefetch is only at the catalog boundary', () {
      expect(
        _originNearCategoryBoundary(
          delta: 1,
          index: 10,
          length: 20,
          windowOffset: 0,
          categoryTotal: 20,
        ),
        isTrue,
      );
      expect(
        _originNearCategoryBoundary(
          delta: 1,
          index: 5,
          length: 20,
          windowOffset: 0,
          categoryTotal: 20,
        ),
        isFalse,
      );
      expect(
        _originNearCategoryBoundary(
          delta: -1,
          index: 5,
          length: 20,
          windowOffset: 0,
          categoryTotal: 40,
        ),
        isTrue,
      );
      expect(
        _originNearCategoryBoundary(
          delta: -1,
          index: 5,
          length: 20,
          windowOffset: 8,
          categoryTotal: 40,
        ),
        isFalse,
      );
    });

    test('cached adjacent page only answers its origin and direction', () {
      expect(
        _originCacheUsable(
          hasPage: true,
          empty: false,
          originMatches: true,
          directionMatches: true,
        ),
        isTrue,
      );
      expect(
        _originCacheUsable(
          hasPage: true,
          empty: true,
          originMatches: true,
          directionMatches: true,
        ),
        isFalse,
      );
      expect(
        _originCacheUsable(
          hasPage: true,
          empty: false,
          originMatches: false,
          directionMatches: true,
        ),
        isFalse,
      );
      expect(
        _originCacheUsable(
          hasPage: true,
          empty: false,
          originMatches: true,
          directionMatches: false,
        ),
        isFalse,
      );
      expect(
        origin,
        contains('_iptvZapCachedOriginCategory != _iptvZapCategory'),
      );
      expect(origin, contains('_iptvZapCachedDirection != delta'));
    });

    test('pending inputs cap at 24 and collapse to ±1', () {
      expect(_originQueuedDelta(3), 1);
      expect(_originQueuedDelta(-4), -1);
      expect(_originQueuedDelta(0), 1);
      expect(_originCanQueue(23), isTrue);
      expect(_originCanQueue(24), isFalse);
      expect(origin, contains('_iptvZapPendingInputs.length >= 24'));
      expect(origin, contains('delta >= 0 ? 1 : -1'));
    });

    test('entering a category tunes first-or-last then prefetches', () {
      expect(_originEnterIndex(delta: 1, length: 12), 0);
      expect(_originEnterIndex(delta: -1, length: 12), 11);
      expect(origin, contains('delta > 0 ? 0 : page.channels.length - 1'));
    });

    test('install preserves the playing channel by url+name', () {
      expect(
        _originInstallIndex(
          urls: const ['http://a', 'http://b', 'http://c'],
          names: const ['A', 'B', 'C'],
          playingUrl: 'http://c',
          playingName: 'C',
          preserve: true,
        ),
        2,
      );
      expect(
        _originInstallIndex(
          urls: const ['http://a', 'http://b'],
          names: const ['A', 'B'],
          playingUrl: 'http://z',
          playingName: 'Z',
          preserve: true,
        ),
        0,
      );
      expect(
        _originInstallIndex(
          urls: const ['http://a', 'http://b'],
          names: const ['A', 'B'],
          playingUrl: 'http://b',
          playingName: 'B',
          preserve: false,
        ),
        0,
      );
      expect(
        origin,
        contains(
          'candidate.url == playing.url && candidate.name == playing.name',
        ),
      );
    });
  });

  group('catch-up replay (origin _playIptvCatchup)', () {
    test('replay is a single VOD item named after the programme', () {
      final replay = _originCatchupReplay(
        channelName: 'BBC One',
        channelUrl: 'http://live/1',
        logoUrl: 'http://logo',
        programmeTitle: 'News at Ten',
        replayUrl: 'http://replay/1',
        sourcePlaylistId: 'live-a',
        guideSourceId: 'guide-b',
        launchSourceId: 'launch-c',
      );
      expect(replay.name, 'News at Ten');
      expect(replay.url, 'http://replay/1');
      expect(replay.logoUrl, 'http://logo');
      expect(replay.group, 'BBC One');
      expect(replay.contentType, 'vod');
      expect(replay.sourceId, 'live-a');
      expect(
        _originCatchupSourceId(
          sourcePlaylistId: null,
          guideSourceId: 'guide-b',
          launchSourceId: 'launch-c',
        ),
        'guide-b',
      );
      expect(
        _originCatchupSourceId(
          sourcePlaylistId: null,
          guideSourceId: null,
          launchSourceId: 'launch-c',
        ),
        'launch-c',
      );
      expect(origin, contains("contentType: 'vod'"));
      expect(
        origin,
        contains("Text('Preparing replay of \"\${programme.title}\"…')"),
      );
      expect(origin, contains("'Replay is not available'"));
      expect(origin, contains('_resetIptvZapPaging()'));
      expect(origin, contains('_iptvChannelsOverride = [replay]'));
      expect(origin, contains('await _switchToIptvChannel(0)'));
    });
  });

  group('zap banner (origin _raiseIptvZapBanner / _syncIptvBannerTicker)', () {
    test('raise is skipped when a sheet, guide, or the dock is up', () {
      expect(
        _originShouldRaiseBanner(
          hasChannel: true,
          showSheet: false,
          showSources: false,
          showGuide: false,
          controlsVisible: false,
        ),
        isTrue,
      );
      expect(
        _originShouldRaiseBanner(
          hasChannel: false,
          showSheet: false,
          showSources: false,
          showGuide: false,
          controlsVisible: false,
        ),
        isFalse,
      );
      expect(
        _originShouldRaiseBanner(
          hasChannel: true,
          showSheet: true,
          showSources: false,
          showGuide: false,
          controlsVisible: false,
        ),
        isFalse,
      );
      expect(
        _originShouldRaiseBanner(
          hasChannel: true,
          showSheet: false,
          showSources: true,
          showGuide: false,
          controlsVisible: false,
        ),
        isFalse,
      );
      expect(
        _originShouldRaiseBanner(
          hasChannel: true,
          showSheet: false,
          showSources: false,
          showGuide: true,
          controlsVisible: false,
        ),
        isFalse,
      );
      expect(
        _originShouldRaiseBanner(
          hasChannel: true,
          showSheet: false,
          showSources: false,
          showGuide: false,
          controlsVisible: true,
        ),
        isFalse,
      );
      expect(origin, contains('const Duration(milliseconds: 4500)'));
      expect(origin, contains('_showIptvChannelSheet ||'));
    });

    test('ticker runs while floating or while the dock owns identity', () {
      expect(
        _originBannerTickerOnScreen(
          hasChannel: true,
          showBanner: true,
          controlsVisible: false,
          ownsIdentity: false,
        ),
        isTrue,
      );
      expect(
        _originBannerTickerOnScreen(
          hasChannel: true,
          showBanner: false,
          controlsVisible: true,
          ownsIdentity: true,
        ),
        isTrue,
      );
      expect(
        _originBannerTickerOnScreen(
          hasChannel: true,
          showBanner: false,
          controlsVisible: true,
          ownsIdentity: false,
        ),
        isFalse,
      );
      expect(
        _originBannerTickerOnScreen(
          hasChannel: false,
          showBanner: true,
          controlsVisible: true,
          ownsIdentity: true,
        ),
        isFalse,
      );
      expect(
        origin,
        contains('_controlsVisible.value && _iptvZapBannerOwnsIdentity'),
      );
    });

    test('EPG refresh waits until the current programme has stopped', () {
      final now = DateTime(2026, 9, 5, 12);
      expect(
        _originShouldRefreshEpg(
          loading: false,
          hasChannel: true,
          stop: now.add(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        _originShouldRefreshEpg(
          loading: false,
          hasChannel: true,
          stop: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
      expect(
        _originShouldRefreshEpg(
          loading: true,
          hasChannel: true,
          stop: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(origin, contains('current.stop.isAfter(DateTime.now())'));
    });
  });

  group('guide switch + reset (origin _switchToIptvGuideChannel)', () {
    test('out-of-range index is a no-op; in-range resets paging first', () {
      expect(_originGuideSwitchInRange(index: -1, length: 3), isFalse);
      expect(_originGuideSwitchInRange(index: 3, length: 3), isFalse);
      expect(_originGuideSwitchInRange(index: 0, length: 3), isTrue);
      expect(origin, contains('_resetIptvZapPaging()'));
      expect(
        origin,
        contains('_iptvChannelsOverride = List<IptvChannel>.from(channels)'),
      );
      expect(origin, contains('unawaited(_reanchorIptvRingToCategory('));
    });

    test('reset bumps the request ticket and drops the boundary cache', () {
      expect(origin, contains('_iptvZapRequestTicket++'));
      expect(origin, contains('_iptvZapPendingInputs.clear()'));
      expect(origin, contains('_clearIptvZapBoundaryCache()'));
    });
  });
}

/// Bodies live on the god file until the move; after the move they live on
/// the controller. The pin must keep passing without edits (gate h).
String _zapOriginSource() {
  for (final path in [
    'lib/screens/video_player/iptv_zap_controller.dart',
    'lib/services/playback/iptv_zap_controller.dart',
  ]) {
    final moved = File(path);
    if (moved.existsSync()) return moved.readAsStringSync();
  }
  return File('lib/screens/video_player_screen.dart').readAsStringSync();
}

class _OriginCatchupGate {
  int _generation = 0;
  int? _activeTicket;

  int begin() {
    final ticket = ++_generation;
    _activeTicket = ticket;
    return ticket;
  }

  bool isCurrent(int ticket) =>
      _activeTicket == ticket && _generation == ticket;

  bool complete(int ticket) {
    if (!isCurrent(ticket)) return false;
    _activeTicket = null;
    return true;
  }

  bool cancel() {
    if (_activeTicket == null) return false;
    _generation++;
    _activeTicket = null;
    return true;
  }
}

List<String>? _originEffectiveChannels({
  required List<String>? override,
  required List<String>? launch,
}) => override ?? launch;

bool _originBannerOwnsIdentity({required bool? isLive}) => isLive == true;

bool _originCanZap({
  required bool isLive,
  required int ringLength,
  required bool pagingActive,
}) => isLive && (ringLength > 1 || pagingActive);

class _OriginZapPage {
  final int offset;
  final int total;
  final String? sourceId;
  final String? category;
  final List<String> categories;

  const _OriginZapPage({
    required this.offset,
    required this.total,
    required this.sourceId,
    required this.category,
    required this.categories,
  });
}

_OriginZapPage? _originParseZapPage(Map<String, dynamic> result) {
  final raw = result['channels'];
  if (raw is! List) return null;
  final channels = [
    for (final entry in raw.whereType<Map>()) Map<String, dynamic>.from(entry),
  ];
  final rawOffset = result['pageOffset'];
  final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
  final rawTotal = result['totalChannels'];
  final total = rawTotal is num ? rawTotal.toInt() : channels.length;
  final rawSourceId = (result['sourceId'] as String?)?.trim();
  final rawCategory = (result['selectedCategory'] as String?)?.trim();
  final rawCategories = result['categories'];
  return _OriginZapPage(
    offset: offset,
    total: math.max(total, offset + channels.length),
    sourceId: (rawSourceId == null || rawSourceId.isEmpty) ? null : rawSourceId,
    category: (rawCategory == null || rawCategory.isEmpty) ? null : rawCategory,
    categories: rawCategories is List
        ? [
            for (final entry in rawCategories.whereType<String>())
              if (entry.isNotEmpty) entry,
          ]
        : const [],
  );
}

enum _OriginZapPath {
  noop,
  wrapAndArm,
  switchAndPrefetch,
  queueAndPrefetch,
  consumeCache,
  requestAdjacent,
}

_OriginZapPath _originZapDecision({
  required int channels,
  bool isLive = true,
  int index = 0,
  int delta = 1,
  bool pagingActive = false,
  int windowOffset = 0,
  int categoryTotal = 0,
  bool cacheHit = false,
}) {
  if (channels <= 0 || !isLive) return _OriginZapPath.noop;
  if (!pagingActive && channels < 2) return _OriginZapPath.noop;
  final from = index.clamp(0, channels - 1);
  final next = from + delta;
  if (!pagingActive) return _OriginZapPath.wrapAndArm;
  if (next >= 0 && next < channels) return _OriginZapPath.switchAndPrefetch;
  final firstAbsolute = windowOffset;
  final lastAbsolute = windowOffset + channels - 1;
  final hasAnotherPage = delta > 0
      ? lastAbsolute + 1 < categoryTotal
      : firstAbsolute > 0;
  if (hasAnotherPage) return _OriginZapPath.queueAndPrefetch;
  if (cacheHit) return _OriginZapPath.consumeCache;
  return _OriginZapPath.requestAdjacent;
}

int _originZapIndex({
  required int from,
  required int delta,
  required int length,
}) => (from + delta + length) % length;

bool _originShouldPrefetchPage({
  required int delta,
  required int index,
  required int length,
  required int windowOffset,
  required int categoryTotal,
}) {
  final firstAbsolute = windowOffset;
  final lastAbsolute = firstAbsolute + length - 1;
  return delta > 0
      ? lastAbsolute + 1 < categoryTotal && index >= length - 12
      : firstAbsolute > 0 && index < 12;
}

bool _originNearCategoryBoundary({
  required int delta,
  required int index,
  required int length,
  required int windowOffset,
  required int categoryTotal,
}) {
  return delta > 0
      ? windowOffset + length >= categoryTotal && index >= length - 12
      : windowOffset == 0 && index < 12;
}

bool _originCacheUsable({
  required bool hasPage,
  required bool empty,
  required bool originMatches,
  required bool directionMatches,
}) {
  if (!hasPage || empty || !originMatches || !directionMatches) return false;
  return true;
}

int _originQueuedDelta(int delta) => delta >= 0 ? 1 : -1;

bool _originCanQueue(int length) => length < 24;

int _originEnterIndex({required int delta, required int length}) =>
    delta > 0 ? 0 : length - 1;

int _originInstallIndex({
  required List<String> urls,
  required List<String> names,
  required String playingUrl,
  required String playingName,
  required bool preserve,
}) {
  var index = 0;
  if (preserve) {
    for (var i = 0; i < urls.length; i++) {
      if (urls[i] == playingUrl && names[i] == playingName) {
        index = i;
        break;
      }
    }
  }
  return index;
}

class _OriginCatchupReplay {
  final String name;
  final String url;
  final String? logoUrl;
  final String group;
  final String contentType;
  final String? sourceId;

  const _OriginCatchupReplay({
    required this.name,
    required this.url,
    required this.logoUrl,
    required this.group,
    required this.contentType,
    required this.sourceId,
  });
}

String? _originCatchupSourceId({
  required String? sourcePlaylistId,
  required String? guideSourceId,
  required String? launchSourceId,
}) => sourcePlaylistId ?? guideSourceId ?? launchSourceId;

_OriginCatchupReplay _originCatchupReplay({
  required String channelName,
  required String channelUrl,
  required String? logoUrl,
  required String programmeTitle,
  required String replayUrl,
  required String? sourcePlaylistId,
  required String? guideSourceId,
  required String? launchSourceId,
}) {
  final sourceId = _originCatchupSourceId(
    sourcePlaylistId: sourcePlaylistId,
    guideSourceId: guideSourceId,
    launchSourceId: launchSourceId,
  );
  return _OriginCatchupReplay(
    name: programmeTitle,
    url: replayUrl,
    logoUrl: logoUrl,
    group: channelName,
    contentType: 'vod',
    sourceId: sourceId,
  );
}

bool _originShouldRaiseBanner({
  required bool hasChannel,
  required bool showSheet,
  required bool showSources,
  required bool showGuide,
  required bool controlsVisible,
}) {
  if (!hasChannel) return false;
  if (showSheet || showSources || showGuide || controlsVisible) return false;
  return true;
}

bool _originBannerTickerOnScreen({
  required bool hasChannel,
  required bool showBanner,
  required bool controlsVisible,
  required bool ownsIdentity,
}) {
  return hasChannel && (showBanner || (controlsVisible && ownsIdentity));
}

bool _originShouldRefreshEpg({
  required bool loading,
  required bool hasChannel,
  required DateTime stop,
  required DateTime now,
}) {
  if (loading || !hasChannel) return false;
  return !stop.isAfter(now);
}

bool _originGuideSwitchInRange({required int index, required int length}) =>
    index >= 0 && index < length;
