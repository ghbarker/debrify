import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search/catalog_search_controller.dart';

StremioAddon _addon(
  String id,
  List<StremioAddonCatalog> catalogs, {
  String name = 'Addon',
}) => StremioAddon(
  id: id,
  name: name,
  manifestUrl: 'https://example/$id/manifest.json',
  baseUrl: 'https://example/$id',
  catalogs: catalogs,
);

StremioAddonCatalog _searchable(
  String id, {
  String type = 'movie',
  String name = 'Top',
}) => StremioAddonCatalog(
  id: id,
  type: type,
  name: name,
  extraSupported: const ['search'],
);

StremioAddonCatalog _browseOnly(String id) =>
    StremioAddonCatalog(id: id, type: 'movie', name: 'Browse');

StremioMeta _meta(String id) =>
    StremioMeta(id: id, type: 'movie', name: 'Title $id');

void main() {
  group('run / query / searching', () {
    test('bumps token, sets query, searching, and zeroes failures', () async {
      final started = Completer<void>();
      final gate = Completer<List<StremioMeta>>();
      final cine = _addon('cine', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) =>
                gate.future,
        onStarted: started.complete,
      );
      addTearDown(c.dispose);
      c.failures = 3;
      final future = c.run('matrix');
      await started.future;
      expect(c.searchToken, 1);
      expect(c.query, 'matrix');
      expect(c.searching, isTrue);
      expect(c.failures, 0);
      expect(c.active, isTrue);
      gate.complete([_meta('tt1')]);
      await future;
      expect(c.searching, isFalse);
      expect(c.query, 'matrix');
      expect(c.active, isTrue);
    });

    test('empty disabled set queries every searchable catalog', () async {
      final seen = <String>[];
      final cine = _addon('cine', [
        _searchable('movies'),
        _searchable('series', type: 'series', name: 'Series'),
        _browseOnly('hidden'),
      ]);
      final extra = _addon('extra', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine, extra],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) async {
              seen.add('${addon.id}:${catalog.id}');
              return [_meta('${addon.id}-${catalog.id}')];
            },
      );
      addTearDown(c.dispose);
      await c.run('q');
      expect(seen, ['cine:movies', 'cine:series', 'extra:top']);
    });
  });

  group('cancel / stale generation', () {
    test(
      'cancel bumps token, clears query/searching, leaves failures',
      () async {
        final c = CatalogSearchController(
          getDisabledAddons: () async => <String>{},
          getSearchableAddons: () async => const [],
          searchCatalog:
              (
                addon,
                catalog,
                query, {
                required throwOnError,
                onRawCount,
              }) async => const [],
        );
        addTearDown(c.dispose);
        c.searchToken = 4;
        c.query = 'old';
        c.searching = true;
        c.failures = 2;
        c.cancel();
        expect(c.searchToken, 5);
        expect(c.query, '');
        expect(c.searching, isFalse);
        expect(c.failures, 2, reason: '_restoreHome did not zero failures');
        expect(c.active, isFalse);
      },
    );

    test('stale search does not apply or increment failures', () async {
      final gate = Completer<List<StremioMeta>>();
      final inFlight = Completer<void>();
      final applied = <List<CatalogSection>>[];
      final streamed = <CatalogSection>[];
      final cine = _addon('cine', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) {
              if (query == 'old') {
                if (!inFlight.isCompleted) inFlight.complete();
                return gate.future;
              }
              return Future.value([_meta('tt-new')]);
            },
        onApplyFirst: streamed.add,
        onAppend: streamed.add,
        onTelevisionApply: applied.add,
      );
      addTearDown(c.dispose);

      final stale = c.run('old');
      await inFlight.future;
      expect(c.searchToken, 1);
      c.cancel();
      expect(c.searchToken, 2);
      gate.completeError(StateError('timeout'));
      await stale;
      expect(c.failures, 0);
      expect(streamed, isEmpty);
      expect(applied, isEmpty);
      expect(c.searching, isFalse);
      expect(c.query, '');

      await c.run('new');
      expect(c.query, 'new');
      expect(c.searching, isFalse);
      expect(streamed.map((s) => s.items.first.id), ['tt-new']);
    });

    test('newer run drops the older generation\'s rows', () async {
      final gates = <String, Completer<List<StremioMeta>>>{
        'one': Completer<List<StremioMeta>>(),
        'two': Completer<List<StremioMeta>>(),
      };
      final streamed = <String>[];
      final cine = _addon('cine', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) =>
                gates[query]!.future,
        onApplyFirst: (s) => streamed.add('first:${s.items.first.id}'),
        onAppend: (s) => streamed.add('append:${s.items.first.id}'),
      );
      addTearDown(c.dispose);

      final older = c.run('one');
      final newer = c.run('two');
      expect(c.searchToken, 2);
      expect(c.query, 'two');
      gates['one']!.complete([_meta('tt-old')]);
      gates['two']!.complete([_meta('tt-new')]);
      await older;
      await newer;
      expect(streamed, ['first:tt-new']);
      expect(c.query, 'two');
      expect(c.searching, isFalse);
    });

    test('disposed / not-live run does not apply after fetch', () async {
      final gate = Completer<List<StremioMeta>>();
      final streamed = <CatalogSection>[];
      final cine = _addon('cine', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) =>
                gate.future,
        onApplyFirst: streamed.add,
        isLive: () => false,
      );
      addTearDown(c.dispose);
      final future = c.run('q');
      gate.complete([_meta('tt1')]);
      await future;
      expect(streamed, isEmpty);
      // Quirk: a not-live run returns before clearing [searching], matching
      // origin's `if (!mounted) return` after the fetch.
      expect(c.searching, isTrue);
    });
  });

  group('disabled addons / per-catalog rows', () {
    test('skips disabled addon ids; empty set means all queried', () async {
      final seen = <String>[];
      final a = _addon('a', [_searchable('top')]);
      final b = _addon('b', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => {'b'},
        getSearchableAddons: () async => [a, b],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) async {
              seen.add(addon.id);
              return [_meta(addon.id)];
            },
      );
      addTearDown(c.dispose);
      await c.run('q');
      expect(seen, ['a']);
    });

    test(
      'one row per searchable catalog, not one merged row per addon',
      () async {
        final tvSections = <CatalogSection>[];
        final addon = _addon('cine', [
          _searchable('movies', name: 'Popular'),
          _searchable('series', type: 'series', name: 'Popular'),
        ]);
        final c = CatalogSearchController(
          getDisabledAddons: () async => <String>{},
          getSearchableAddons: () async => [addon],
          searchCatalog:
              (
                addon,
                catalog,
                query, {
                required throwOnError,
                onRawCount,
              }) async {
                return [_meta(catalog.id)];
              },
          onTelevisionApply: tvSections.addAll,
          isTelevision: () => true,
        );
        addTearDown(c.dispose);
        await c.run('q');
        expect(tvSections.map((s) => s.catalog.id), ['movies', 'series']);
        expect(tvSections.map((s) => s.title), [
          'Popular Movies',
          'Popular Series',
        ]);
      },
    );
  });

  group('failures vs empty', () {
    test('throw increments failures; empty results do not', () async {
      final addon = _addon('cine', [
        _searchable('ok'),
        _searchable('empty'),
        _searchable('dead'),
      ]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [addon],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) async {
              expect(throwOnError, isTrue);
              if (catalog.id == 'dead') throw StateError('timeout');
              if (catalog.id == 'empty') return const [];
              return [_meta('tt1')];
            },
      );
      addTearDown(c.dispose);
      await c.run('q');
      expect(c.failures, 1);
      expect(c.searching, isFalse);
    });

    test('outer throw clears searching and calls onAborted', () async {
      var aborted = 0;
      final c = CatalogSearchController(
        getDisabledAddons: () async => throw StateError('prefs'),
        getSearchableAddons: () async => const [],
        searchCatalog:
            (
              addon,
              catalog,
              query, {
              required throwOnError,
              onRawCount,
            }) async => const [],
        onAborted: () => aborted++,
      );
      addTearDown(c.dispose);
      await c.run('q');
      expect(aborted, 1);
      expect(c.searching, isFalse);
      expect(c.query, 'q');
    });
  });

  group('TV batch vs non-TV stream', () {
    test(
      'non-TV streams first apply then appends in completion order',
      () async {
        final slow = Completer<List<StremioMeta>>();
        final fast = Completer<List<StremioMeta>>();
        final events = <String>[];
        final addon = _addon('cine', [
          _searchable('slow'),
          _searchable('fast'),
        ]);
        final c = CatalogSearchController(
          getDisabledAddons: () async => <String>{},
          getSearchableAddons: () async => [addon],
          searchCatalog:
              (addon, catalog, query, {required throwOnError, onRawCount}) {
                return catalog.id == 'slow' ? slow.future : fast.future;
              },
          onApplyFirst: (s) => events.add('apply:${s.catalog.id}'),
          onAppend: (s) => events.add('append:${s.catalog.id}'),
          onTelevisionApply: (_) => events.add('tv'),
          isTelevision: () => false,
        );
        addTearDown(c.dispose);
        final future = c.run('q');
        fast.complete([_meta('tt-fast')]);
        await Future<void>.delayed(Duration.zero);
        expect(events, ['apply:fast']);
        slow.complete([_meta('tt-slow')]);
        await future;
        expect(events, ['apply:fast', 'append:slow']);
      },
    );

    test('TV applies all rows once, in input order, not streamed', () async {
      final slow = Completer<List<StremioMeta>>();
      final fast = Completer<List<StremioMeta>>();
      final events = <String>[];
      final addon = _addon('cine', [_searchable('slow'), _searchable('fast')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [addon],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) {
              return catalog.id == 'slow' ? slow.future : fast.future;
            },
        onApplyFirst: (s) => events.add('apply:${s.catalog.id}'),
        onAppend: (s) => events.add('append:${s.catalog.id}'),
        onTelevisionApply: (sections) =>
            events.add('tv:${sections.map((s) => s.catalog.id).join(',')}'),
        onTelevisionSettled: () => events.add('settled'),
        isTelevision: () => true,
      );
      addTearDown(c.dispose);
      final future = c.run('q');
      fast.complete([_meta('tt-fast')]);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty, reason: 'TV must not stream as catalogs arrive');
      expect(c.searching, isTrue);
      slow.complete([_meta('tt-slow')]);
      await future;
      expect(events, ['tv:slow,fast', 'settled']);
      expect(c.searching, isFalse);
    });
  });

  group('section query / nextSkip', () {
    test('carries the query and seeds nextSkip from rawCount', () async {
      CatalogSection? first;
      final cine = _addon('cine', [_searchable('top', name: 'Popular')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) async {
              onRawCount?.call(7);
              return [_meta('tt1'), _meta('tt2')];
            },
        onApplyFirst: (s) => first = s,
      );
      addTearDown(c.dispose);
      await c.run('matrix');
      expect(first, isNotNull);
      expect(first!.query, 'matrix');
      expect(first!.nextSkip, 7);
      expect(first!.title, 'Popular Movies');
      expect(first!.items.map((m) => m.id), ['tt1', 'tt2']);
    });

    test('nextSkip falls back to items.length when rawCount is 0', () async {
      CatalogSection? first;
      final cine = _addon('cine', [_searchable('top')]);
      final c = CatalogSearchController(
        getDisabledAddons: () async => <String>{},
        getSearchableAddons: () async => [cine],
        searchCatalog:
            (addon, catalog, query, {required throwOnError, onRawCount}) async {
              onRawCount?.call(0);
              return [_meta('tt1'), _meta('tt2')];
            },
        onApplyFirst: (s) => first = s,
      );
      addTearDown(c.dispose);
      await c.run('q');
      expect(first!.nextSkip, 2);
    });
  });
}
