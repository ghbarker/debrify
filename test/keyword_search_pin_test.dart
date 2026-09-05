import 'dart:io';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/screens/search/search_screen_shells.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/torrent_filter_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// G1'-3 characterisation of the in-tab keyword search **before**
/// the move out of `search_screen.dart`.
///
/// Pin commit must stay green on its own and must not import
/// `keyword_search_controller.dart` or `keyword_search_screen.dart`.
/// After the move this file still matches the same bodies (it reads the
/// new files when they exist).
///
/// Quirks pinned here (keep, do not "fix"):
/// * Streamed batches merge through `TorrentService.mergeSearchResults`
///   so a provisional list cannot drift from the awaited result.
/// * A late batch after `_kwSearching` clears is dropped (timed-out
///   engine futures must not mutate the authoritative set).
/// * First real interaction freezes live reshuffles; later arrivals
///   park in `_kwPending` behind a SET-difference pill count (not a
///   length delta).
/// * Toolbar / tab / select / Sources fold parked arrivals in first
///   (`_kwFreezeAndAdopt`) so the user always acts on the complete set.
/// * Adopt is identity-preserving: DPAD stays on the same torrent, not
///   the same index. A tab whose source vanished in the adopt clears.
/// * Empty `Torrent.source` buckets as `'unknown'`.
/// * Provider selection is additive (`d:src` / `t:src` seen-keys);
///   vanished sources prune from both the ticks and the seen set.
/// * Cached-only: rows without a real infohash but with a torrent URL
///   stay; cache lookup is `infohash.toLowerCase()` with no trim.
/// * Cached-only mode is decided only in the completion sweep, and
///   only when TorBox ran successfully and no other provider is active.
/// * Relevance keeps engine order; name sorts A→Z (natural asc);
///   seeders/size/date default descending. Name compare is case-insensitive.
/// * Selectable rows exclude direct/external streams. Dismissing the
///   bulk-add chooser stays in selection mode.
/// * Snapshot only for a COMPLETED keyword search (query + results,
///   not mid-stream). Pending is folded into the snapshot in dispose.
/// * Home TV skips keyword restore (`searchScreenRestoresKeyword`).
/// * `_handleKwTabKey`: activate / space; up → search field; down →
///   toolbar; left edge → sidebar; right walks tabs.
/// * No-engine-ran vs all-engines-errored copy is distinct.
///
/// Origin: `lib/screens/search_screen.dart` `_KwPreservedState`,
/// keyword fields, `_restoreKeywordState` / dispose snapshot,
/// `_runKeyword`…`_openKeywordSources`, `_buildKeyword`…`_sortLabel`,
/// `_handleKwTabKey` / `_handleKwToolbarKey`.
String _origin() {
  final controller = File('lib/screens/search/keyword_search_controller.dart')
      .existsSync()
      ? File('lib/screens/search/keyword_search_controller.dart')
      : File('lib/services/search/keyword_search_controller.dart');
  final screen = File('lib/screens/search/keyword_search_screen.dart');
  if (controller.existsSync() && screen.existsSync()) {
    return '${controller.readAsStringSync()}\n${screen.readAsStringSync()}';
  }
  return File('lib/screens/search_screen.dart').readAsStringSync();
}

Torrent _t({
  required String hash,
  required String name,
  int seeders = 0,
  int size = 0,
  int date = 0,
  String source = 'tb',
  StreamType type = StreamType.torrent,
  String? url,
  String? torrentUrl,
  bool realHash = true,
}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: name,
  sizeBytes: size,
  createdUnix: date,
  seeders: seeders,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
  streamType: type,
  directUrl: url,
  torrentUrl: torrentUrl,
  hasRealInfoHash: realHash,
);

/// Origin `_kwRowKey`.
String kwRowKey(Torrent t) => t.hasRealInfoHash && t.infohash.isNotEmpty
    ? 'h:${t.infohash.toLowerCase()}'
    : 'n:${t.name}|${t.directUrl ?? ''}';

/// Origin `_kwSourceOf`.
String kwSourceOf(Torrent t) => t.source.isNotEmpty ? t.source : 'unknown';

/// Origin `_kwPendingNewCount` — SET difference, not a length delta.
int kwPendingNewCount(List<Torrent> shown, List<Torrent>? pending) {
  if (pending == null) return 0;
  final keys = {for (final t in shown) kwRowKey(t)};
  var count = 0;
  for (final t in pending) {
    if (!keys.contains(kwRowKey(t))) count++;
  }
  return count;
}

/// Origin `_kwIsDirect`.
bool kwIsDirect(Torrent t) => t.isDirectStream || t.isExternalStream;

/// Origin `_kwIsTorboxCached`.
bool kwIsTorboxCached(Torrent t, Map<String, List<String>> cache) {
  if (!t.hasRealInfoHash && t.torrentUrl != null) return true;
  final labels = cache[t.infohash.toLowerCase()];
  return labels != null && labels.contains('TB');
}

/// Origin `_naturalAscFor`.
bool naturalAscFor(String field) => field == 'name';

/// Origin `_sortKeyword`.
List<Torrent> sortKeyword(
  List<Torrent> list, {
  required String sort,
  required bool sortAsc,
}) {
  final l = [...list];
  final int dir = sortAsc ? 1 : -1;
  switch (sort) {
    case 'seeders':
      l.sort((a, b) => dir * a.seeders.compareTo(b.seeders));
      break;
    case 'size':
      l.sort((a, b) => dir * a.sizeBytes.compareTo(b.sizeBytes));
      break;
    case 'date':
      l.sort((a, b) => dir * a.createdUnix.compareTo(b.createdUnix));
      break;
    case 'name':
      l.sort(
        (a, b) =>
            dir *
            a.displayTitle.toLowerCase().compareTo(
              b.displayTitle.toLowerCase(),
            ),
      );
      break;
    default:
      break;
  }
  return l;
}

/// Origin `_recomputeKeyword` filter stack (without focus-node sync).
List<Torrent> recomputeKeyword({
  required List<Torrent> all,
  required bool cachedOnly,
  required Map<String, List<String>> cache,
  required Map<String, int> directCounts,
  required Map<String, int> torrentCounts,
  required Set<String> selectedDirect,
  required Set<String> selectedTorrent,
  required String? sourceTab,
  required TorrentFilterState filters,
  required String sort,
  required bool sortAsc,
}) {
  Iterable<Torrent> base = all;
  if (cachedOnly) {
    base = base.where((t) => kwIsTorboxCached(t, cache));
  }
  if (directCounts.isNotEmpty || torrentCounts.isNotEmpty) {
    base = base.where((t) {
      final src = kwSourceOf(t);
      if (kwIsDirect(t)) {
        return directCounts.isEmpty || selectedDirect.contains(src);
      }
      return torrentCounts.isEmpty || selectedTorrent.contains(src);
    });
  }
  final tab = sourceTab;
  if (tab != null) {
    base = base.where((t) => kwSourceOf(t) == tab);
  }
  final filtered = TorrentFilterMatcher.apply(base.toList(), filters);
  return sortKeyword(filtered, sort: sort, sortAsc: sortAsc);
}

class _ProviderSnap {
  _ProviderSnap(
    this.direct,
    this.torrent,
    this.selectedDirect,
    this.selectedTorrent,
    this.seen,
  );
  final Map<String, int> direct;
  final Map<String, int> torrent;
  final Set<String> selectedDirect;
  final Set<String> selectedTorrent;
  final Set<String> seen;
}

/// Origin `_computeKwProviders`.
_ProviderSnap _computeKwProviders(
  List<Torrent> torrents, {
  required Set<String> seen,
  required Set<String> selectedDirect,
  required Set<String> selectedTorrent,
}) {
  final direct = <String, int>{};
  final torrent = <String, int>{};
  for (final t in torrents) {
    final src = kwSourceOf(t);
    final bucket = kwIsDirect(t) ? direct : torrent;
    bucket[src] = (bucket[src] ?? 0) + 1;
  }
  for (final s in direct.keys) {
    if (seen.add('d:$s')) selectedDirect.add(s);
  }
  for (final s in torrent.keys) {
    if (seen.add('t:$s')) selectedTorrent.add(s);
  }
  selectedDirect.removeWhere((s) => !direct.containsKey(s));
  selectedTorrent.removeWhere((s) => !torrent.containsKey(s));
  seen.removeWhere(
    (k) => k.startsWith('d:')
        ? !direct.containsKey(k.substring(2))
        : !torrent.containsKey(k.substring(2)),
  );
  return _ProviderSnap(direct, torrent, selectedDirect, selectedTorrent, seen);
}

/// Origin `_friendlyKeywordError`.
String friendlyKeywordError(Object e) {
  final msg = e.toString().replaceAll('Exception: ', '');
  if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
    return 'Network error. Please check your connection.';
  }
  if (msg.contains('TimeoutException')) {
    return 'Search timed out. Please try again.';
  }
  if (msg.length > 100) return 'Search failed. Please try again.';
  return msg;
}

/// Origin `_loadKwCacheConfig` gating (TB on = pref AND integration AND key).
({bool tbOn, bool pmOn, bool otherActive}) kwCacheGating({
  required bool tbCheck,
  required bool tbIntegration,
  required String? tbKey,
  required bool pmCheck,
  required bool pmIntegration,
  required String? pmKey,
  required bool rdIntegration,
  required String? rdKey,
  required bool adIntegration,
  required String? adKey,
  required bool pikpakActive,
}) {
  final tbOn = tbCheck && tbIntegration && (tbKey?.isNotEmpty ?? false);
  final pmOn = pmCheck && pmIntegration && (pmKey?.isNotEmpty ?? false);
  final rdActive = rdIntegration && (rdKey?.isNotEmpty ?? false);
  final pmActive = pmIntegration && (pmKey?.isNotEmpty ?? false);
  final adActive = adIntegration && (adKey?.isNotEmpty ?? false);
  return (
    tbOn: tbOn,
    pmOn: pmOn,
    otherActive: rdActive || pmActive || adActive || pikpakActive,
  );
}

/// Origin cached-only settle: `_kwTbRan && !_kwOtherProviderActive`.
bool kwCachedOnlySettle({required bool tbRan, required bool otherActive}) =>
    tbRan && !otherActive;

/// Origin snapshot eligibility (dispose): completed keyword search only.
bool kwShouldPreserve({
  required bool modeIsKeyword,
  required String query,
  required List<Torrent> results,
  required bool searching,
}) => modeIsKeyword && query.isNotEmpty && results.isNotEmpty && !searching;

/// Origin `_handleKwTabKey` direction table (activate handled by caller).
enum KwTabNav { activate, up, down, leftPrev, leftSidebar, right, ignore }

KwTabNav kwTabNav({
  required String logicalKey,
  required int index,
  required int total,
}) {
  switch (logicalKey) {
    case 'select':
    case 'enter':
    case 'space':
      return KwTabNav.activate;
    case 'arrowUp':
      return KwTabNav.up;
    case 'arrowDown':
      return KwTabNav.down;
    case 'arrowLeft':
      return index > 0 ? KwTabNav.leftPrev : KwTabNav.leftSidebar;
    case 'arrowRight':
      return index < total - 1 ? KwTabNav.right : KwTabNav.ignore;
    default:
      return KwTabNav.ignore;
  }
}

/// Origin `_sortLabel`.
String sortLabel(String s) =>
    const {
      'relevance': 'Relevance',
      'seeders': 'Seeders',
      'size': 'Size',
      'date': 'Date',
      'name': 'Name',
    }[s] ??
    s;

void main() {
  late String origin;

  setUpAll(() {
    origin = _origin();
  });

  group('origin source (G1\'-3 pin)', () {
    test('KwPreservedState snapshot fields stay', () {
      expect(origin, contains(RegExp(r'class _?KwPreservedState')));
      for (final field in [
        'final String variant',
        'final String query',
        'final List<Torrent> all',
        'final List<Torrent> results',
        'final TorrentFilterState filters',
        'final String sort',
        'final bool sortAsc',
        'final Map<String, List<String>> cache',
        'final bool cachedOnly',
        'final Map<String, int> directCounts',
        'final Map<String, int> torrentCounts',
        'final Set<String> selectedDirect',
        'final Set<String> selectedTorrent',
        'final String? sourceTab',
        'final double scrollOffset',
      ]) {
        expect(
          origin,
          contains(field),
          reason: 'missing snapshot field $field',
        );
      }
    });

    test('freeze / adopt / pending-count quirks stay', () {
      expect(origin, contains('TorrentService.mergeSearchResults'));
      expect(origin, contains(RegExp(r'if \(!_?kwSearching\) return')));
      expect(origin, contains(RegExp(r'_?kwStreamFrozen')));
      expect(origin, contains(RegExp(r'_?kwPending')));
      expect(origin, contains('a SET difference, not a'));
      expect(origin, contains('Identity-preserving refocus'));
      expect(origin, contains(RegExp(r'_?kwSourceOf\(')));
      expect(origin, contains("'unknown'"));
      expect(origin, contains("h:\${t.infohash.toLowerCase()}"));
    });

    test('filter + sort + cached-only quirks stay', () {
      expect(origin, contains("case 'seeders':"));
      expect(origin, contains("case 'size':"));
      expect(origin, contains("case 'date':"));
      expect(origin, contains("case 'name':"));
      expect(origin, contains("default: // 'relevance'"));
      expect(origin, contains("field == 'name'"));
      expect(origin, contains('infohash.toLowerCase()'));
      expect(origin, contains('labels.contains(\'TB\')'));
      expect(origin, contains('!t.hasRealInfoHash && t.torrentUrl != null'));
      expect(
        origin,
        contains(RegExp(r'_?kwTbRan && !_?kwOtherProviderActive')),
      );
      expect(
        origin,
        contains(RegExp(r"if \(_?kwProviderSeen\.add\('d:\$s'\)\)")),
      );
      expect(
        origin,
        contains(RegExp(r"if \(_?kwProviderSeen\.add\('t:\$s'\)\)")),
      );
    });

    test('selection + sources + tab-key quirks stay', () {
      expect(origin, contains('!t.isDirectStream && !t.isExternalStream'));
      expect(
        origin,
        contains('Stay in selection mode if the user just dismissed'),
      );
      expect(
        origin,
        contains('No sources enabled. Turn on at least one source'),
      );
      expect(origin, contains('Search failed on all sources.'));
      expect(origin, contains('Network error. Please check your connection.'));
      expect(origin, contains('Search timed out. Please try again.'));
      expect(origin, contains('Still searching sources…'));
      expect(origin, contains('Showing Torbox cached results only.'));
      expect(origin, contains('LogicalKeyboardKey.arrowUp'));
      expect(origin, contains('LogicalKeyboardKey.arrowDown'));
      expect(origin, contains('LogicalKeyboardKey.arrowLeft'));
      expect(origin, contains('MainPageBridge.focusTvSidebar'));
    });

    test('snapshot only preserves a completed keyword search', () {
      expect(origin, contains('A still-streaming search is NOT preserved'));
      expect(origin, contains(RegExp(r'!_?kwSearching')));
      expect(origin, contains('Fold a parked (pill) final set'));
    });
  });

  group('pure origin algorithms (G1\'-3 pin)', () {
    test('row key prefers real infohash; else name+url', () {
      expect(kwRowKey(_t(hash: 'AbC', name: 'A')), 'h:abc');
      expect(
        kwRowKey(
          _t(
            hash: '',
            name: 'Direct',
            realHash: false,
            type: StreamType.directUrl,
            url: 'https://x',
          ),
        ),
        'n:Direct|https://x',
      );
    });

    test('empty source buckets as unknown', () {
      expect(kwSourceOf(_t(hash: 'a', name: 'A', source: 'TB')), 'tb');
      expect(kwSourceOf(_t(hash: 'a', name: 'A', source: '')), 'unknown');
    });

    test('pending count is a set difference, not a length delta', () {
      final a = _t(hash: 'a', name: 'A');
      final b = _t(hash: 'b', name: 'B');
      final c = _t(hash: 'c', name: 'C');
      expect(kwPendingNewCount([a, b], [a, b, c]), 1);
      expect(kwPendingNewCount([a, b, c], [a, b]), 0);
      expect(kwPendingNewCount([a, b], [a, b]), 0);
      expect(kwPendingNewCount([a], null), 0);
    });

    test('streamed merge is mergeSearchResults; freeze parks arrivals', () {
      final fast = [_t(hash: 'a', name: 'A', seeders: 10, source: 'one')];
      final slow = [_t(hash: 'b', name: 'B', seeders: 5, source: 'two')];
      final live = TorrentService.mergeSearchResults([fast, slow]);
      expect(live.map((t) => t.infohash).toList(), ['a', 'b']);

      List<Torrent> shown = TorrentService.mergeSearchResults([fast]);
      // First interaction freezes live reshuffles; later arrivals park.
      final pending = TorrentService.mergeSearchResults([fast, slow]);
      expect(shown.map((t) => t.infohash).toList(), ['a']);
      expect(kwPendingNewCount(shown, pending), 1);

      shown = pending;
      expect(shown.map((t) => t.infohash).toList(), ['a', 'b']);
    });

    test('adopt clears a vanished source tab', () {
      final kept = _t(hash: 'a', name: 'A', source: 'alpha');
      final pending = [kept];
      String? tab = 'beta';
      if (!pending.any((t) => kwSourceOf(t) == tab)) {
        tab = null;
      }
      expect(tab, isNull);
    });

    test('filter + sort stack: cached-only, providers, tab, relevance', () {
      final tb = _t(hash: 'aa', name: 'Zed 1080p', seeders: 1, source: 'tb');
      final pm = _t(hash: 'bb', name: 'Aye 720p', seeders: 9, source: 'pm');
      final direct = _t(
        hash: '',
        name: 'Stream',
        source: 'addon',
        type: StreamType.directUrl,
        url: 'https://x',
        realHash: false,
      );
      final cache = {
        'aa': ['TB'],
      };
      final all = [tb, pm, direct];

      final cached = recomputeKeyword(
        all: all,
        cachedOnly: true,
        cache: cache,
        directCounts: const {},
        torrentCounts: const {},
        selectedDirect: {},
        selectedTorrent: {},
        sourceTab: null,
        filters: const TorrentFilterState.empty(),
        sort: 'relevance',
        sortAsc: false,
      );
      expect(cached.map((t) => t.infohash).toList(), ['aa']);

      final providers = recomputeKeyword(
        all: all,
        cachedOnly: false,
        cache: cache,
        directCounts: {'addon': 1},
        torrentCounts: {'tb': 1, 'pm': 1},
        selectedDirect: {},
        selectedTorrent: {'tb'},
        sourceTab: null,
        filters: const TorrentFilterState.empty(),
        sort: 'seeders',
        sortAsc: false,
      );
      expect(providers.map((t) => t.infohash).toList(), ['aa']);

      final tabbed = recomputeKeyword(
        all: all,
        cachedOnly: false,
        cache: cache,
        directCounts: const {},
        torrentCounts: const {},
        selectedDirect: {},
        selectedTorrent: {},
        sourceTab: 'pm',
        filters: const TorrentFilterState.empty(),
        sort: 'name',
        sortAsc: true,
      );
      expect(tabbed.single.infohash, 'bb');

      final byName = sortKeyword([tb, pm], sort: 'name', sortAsc: true);
      expect(byName.map((t) => t.displayTitle).toList(), [
        'Aye 720p',
        'Zed 1080p',
      ]);
      expect(naturalAscFor('name'), isTrue);
      expect(naturalAscFor('seeders'), isFalse);
      expect(naturalAscFor('relevance'), isFalse);
    });

    test('sizeless torrent URL without real hash stays in cached-only', () {
      final link = _t(
        hash: '',
        name: 'Direct torrent file',
        realHash: false,
        torrentUrl: 'https://x/file.torrent',
      );
      expect(kwIsTorboxCached(link, const {}), isTrue);
      final hashed = _t(hash: 'cc', name: 'Nope');
      expect(kwIsTorboxCached(hashed, const {}), isFalse);
      expect(
        kwIsTorboxCached(hashed, {
          'cc': ['TB'],
        }),
        isTrue,
      );
    });

    test('provider ticks are additive and prune vanished sources', () {
      final seen = <String>{};
      final selectedDirect = <String>{};
      final selectedTorrent = <String>{};
      final first = _computeKwProviders(
        [_t(hash: 'a', name: 'A', source: 'alpha')],
        seen: seen,
        selectedDirect: selectedDirect,
        selectedTorrent: selectedTorrent,
      );
      expect(first.selectedTorrent, {'alpha'});
      selectedTorrent.remove('alpha');
      final second = _computeKwProviders(
        [
          _t(hash: 'a', name: 'A', source: 'alpha'),
          _t(hash: 'b', name: 'B', source: 'beta'),
        ],
        seen: seen,
        selectedDirect: selectedDirect,
        selectedTorrent: selectedTorrent,
      );
      expect(second.selectedTorrent, {'beta'});
      expect(second.seen, {'t:alpha', 't:beta'});

      final pruned = _computeKwProviders(
        [_t(hash: 'b', name: 'B', source: 'beta')],
        seen: seen,
        selectedDirect: selectedDirect,
        selectedTorrent: selectedTorrent,
      );
      expect(pruned.selectedTorrent, {'beta'});
      expect(pruned.seen, {'t:beta'});
    });

    test('selection excludes direct/external; toggle is by infohash', () {
      final torrent = _t(hash: 'aa', name: 'A');
      final direct = _t(
        hash: 'dd',
        name: 'D',
        type: StreamType.directUrl,
        url: 'https://x',
      );
      final external = _t(
        hash: 'ee',
        name: 'E',
        type: StreamType.externalUrl,
        url: 'https://y',
      );
      final results = [torrent, direct, external];
      final selectable = results
          .where((t) => !t.isDirectStream && !t.isExternalStream)
          .toList();
      expect(selectable, [torrent]);

      final selected = <String>{};
      void toggle(Torrent t) {
        if (selected.contains(t.infohash)) {
          selected.remove(t.infohash);
        } else {
          selected.add(t.infohash);
        }
      }

      toggle(torrent);
      expect(selected, {'aa'});
      toggle(torrent);
      expect(selected, isEmpty);
      selected
        ..clear()
        ..addAll(selectable.map((t) => t.infohash));
      expect(selected, {'aa'});
    });

    test('friendly keyword errors bucket network / timeout / long', () {
      // replaceAll('Exception: ', '') also strips the suffix of
      // "SocketException: ", so the SocketException token itself is
      // not a reliable probe — Failed host lookup is the surviving arm.
      expect(
        friendlyKeywordError('Failed host lookup'),
        'Network error. Please check your connection.',
      );
      expect(
        friendlyKeywordError('TimeoutException after 0:00:20'),
        'Search timed out. Please try again.',
      );
      expect(
        friendlyKeywordError('x' * 120),
        'Search failed. Please try again.',
      );
      expect(friendlyKeywordError(Exception('boom')), 'boom');
    });

    test(
      'cache gating requires pref + integration + key; PM counts as other',
      () {
        final off = kwCacheGating(
          tbCheck: true,
          tbIntegration: true,
          tbKey: '',
          pmCheck: false,
          pmIntegration: false,
          pmKey: null,
          rdIntegration: false,
          rdKey: null,
          adIntegration: false,
          adKey: null,
          pikpakActive: false,
        );
        expect(off.tbOn, isFalse);
        expect(off.otherActive, isFalse);

        final tbOnly = kwCacheGating(
          tbCheck: true,
          tbIntegration: true,
          tbKey: 'tb',
          pmCheck: false,
          pmIntegration: false,
          pmKey: null,
          rdIntegration: false,
          rdKey: null,
          adIntegration: false,
          adKey: null,
          pikpakActive: false,
        );
        expect(tbOnly.tbOn, isTrue);
        expect(tbOnly.otherActive, isFalse);
        expect(
          kwCachedOnlySettle(tbRan: true, otherActive: tbOnly.otherActive),
          isTrue,
        );

        final withPm = kwCacheGating(
          tbCheck: true,
          tbIntegration: true,
          tbKey: 'tb',
          pmCheck: true,
          pmIntegration: true,
          pmKey: 'pm',
          rdIntegration: false,
          rdKey: null,
          adIntegration: false,
          adKey: null,
          pikpakActive: false,
        );
        expect(withPm.pmOn, isTrue);
        expect(withPm.otherActive, isTrue);
        expect(
          kwCachedOnlySettle(tbRan: true, otherActive: withPm.otherActive),
          isFalse,
        );
        expect(kwCachedOnlySettle(tbRan: false, otherActive: false), isFalse);
      },
    );

    test('snapshot only for a completed keyword search', () {
      expect(
        kwShouldPreserve(
          modeIsKeyword: true,
          query: 'foo',
          results: [_t(hash: 'a', name: 'A')],
          searching: false,
        ),
        isTrue,
      );
      expect(
        kwShouldPreserve(
          modeIsKeyword: true,
          query: 'foo',
          results: [_t(hash: 'a', name: 'A')],
          searching: true,
        ),
        isFalse,
      );
      expect(
        kwShouldPreserve(
          modeIsKeyword: true,
          query: 'foo',
          results: const [],
          searching: false,
        ),
        isFalse,
      );
      expect(
        kwShouldPreserve(
          modeIsKeyword: false,
          query: 'foo',
          results: [_t(hash: 'a', name: 'A')],
          searching: false,
        ),
        isFalse,
      );
    });

    test('Home TV is the only variant that skips keyword restore', () {
      expect(
        searchScreenRestoresKeyword(
          isTelevision: true,
          searchMode: false,
          discoverMode: false,
        ),
        isFalse,
      );
      expect(
        searchScreenRestoresKeyword(
          isTelevision: false,
          searchMode: false,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenRestoresKeyword(
          isTelevision: true,
          searchMode: true,
          discoverMode: false,
        ),
        isTrue,
      );
    });

    test('DPAD tab key table: activate, up, down, left-edge sidebar', () {
      expect(
        kwTabNav(logicalKey: 'select', index: 1, total: 3),
        KwTabNav.activate,
      );
      expect(
        kwTabNav(logicalKey: 'space', index: 1, total: 3),
        KwTabNav.activate,
      );
      expect(kwTabNav(logicalKey: 'arrowUp', index: 1, total: 3), KwTabNav.up);
      expect(
        kwTabNav(logicalKey: 'arrowDown', index: 1, total: 3),
        KwTabNav.down,
      );
      expect(
        kwTabNav(logicalKey: 'arrowLeft', index: 0, total: 3),
        KwTabNav.leftSidebar,
      );
      expect(
        kwTabNav(logicalKey: 'arrowLeft', index: 2, total: 3),
        KwTabNav.leftPrev,
      );
      expect(
        kwTabNav(logicalKey: 'arrowRight', index: 2, total: 3),
        KwTabNav.ignore,
      );
      expect(
        kwTabNav(logicalKey: 'arrowRight', index: 1, total: 3),
        KwTabNav.right,
      );
      expect(sortLabel('relevance'), 'Relevance');
      expect(sortLabel('date'), 'Date');
      expect(sortLabel('mystery'), 'mystery');
    });
  });
}
