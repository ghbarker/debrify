import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search/home_board_controller.dart';
import 'package:debrify/services/filtered_catalog_pager.dart';
import 'package:debrify/services/home/home_row_ids.dart';
import 'package:debrify/services/home/home_row_registry.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';

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

StremioAddonCatalog _catalog(
  String id, {
  String type = 'movie',
  String name = 'Top',
  bool searchOnly = false,
}) => StremioAddonCatalog(
  id: id,
  type: type,
  name: name,
  extras: [
    if (searchOnly) const StremioExtraParam(name: 'search', isRequired: true),
  ],
);

StremioMeta _meta(String id) =>
    StremioMeta(id: id, type: 'movie', name: 'Title $id');

FilteredPage _page(List<String> ids, {int? nextSkip, bool exhausted = false}) =>
    FilteredPage(
      items: [for (final id in ids) _meta(id)],
      nextSkip: nextSkip ?? ids.length,
      exhausted: exhausted,
      fetches: 1,
    );

HomeCollection _collection(
  String id, {
  bool pinToTop = false,
  bool enabled = true,
  int folders = 1,
}) => HomeCollection(
  id: id,
  title: id,
  pinToTop: pinToTop,
  enabled: enabled,
  folders: [
    for (var i = 0; i < folders; i++)
      HomeCollectionFolder(id: '$id-f$i', title: 'Folder $i'),
  ],
);

HomeBoardSettingsSnapshot _snap({
  Set<String> disabled = const {},
  List<HomeExtraRow> extras = const [],
  List<String> rowOrder = const [],
  HomeHeroSource heroSource = (mode: HomeHeroSourceMode.random, ids: const []),
  List<HomeCollection> collections = const [],
  bool hideWatched = false,
}) => HomeBoardSettingsSnapshot(
  disabled: disabled,
  extras: extras,
  rowOrder: rowOrder,
  heroSource: heroSource,
  collections: collections,
  hideWatched: hideWatched,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'assembleHomeSections (H1-fix: pinned collections lead tracker lists)',
    () {
      test(
        'pinned collections, then list rows, then unpinned, then catalogs',
        () {
          final pinned = HomeCollectionSection(
            collection: _collection('pinned', pinToTop: true),
          );
          final unpinned = HomeCollectionSection(
            collection: _collection('unpinned'),
          );
          final list = HomeListSection(
            rowId: 'traktlist:watchlist',
            title: 'Watchlist',
            items: [_meta('tt1')],
            traktChoice: const TraktListChoice.builtin(
              TraktSeeAllList.watchlist,
            ),
          );
          final addon = _addon('cinemeta', [_catalog('top')]);
          final catalog = CatalogSection(
            title: 'Top Movies',
            addon: addon,
            catalog: addon.catalogs.first,
            items: [_meta('tt2')],
          );

          final sections = HomeBoardController.assembleHomeSections(
            collectionRows: [pinned, unpinned],
            listRows: [list],
            firstBatch: [catalog],
          );

          expect(sections, [pinned, list, unpinned, catalog]);
          expect(
            sections.map((s) {
              if (s is HomeCollectionSection) return s.rowId;
              if (s is HomeListSection) return s.rowId;
              return HomeRowIds.catalog(
                s.addon.id,
                s.catalog.type,
                s.catalog.id,
              );
            }),
            [
              'collection:pinned',
              'traktlist:watchlist',
              'collection:unpinned',
              'cinemeta:movie:top',
            ],
          );

          // The section band keeps `_sections` order so pinned collections still
          // lead tracker lists — do not regroup by family canonicalIndex.
          expect(
            HomeRowRegistry.instance.canonicalBoardRailIds(
              visibleIds: [
                'cw:movies',
                'fav:playlist',
                ...sections.map((s) {
                  if (s is HomeCollectionSection) return s.rowId;
                  if (s is HomeListSection) return s.rowId;
                  return HomeRowIds.catalog(
                    s.addon.id,
                    s.catalog.type,
                    s.catalog.id,
                  );
                }),
              ],
            ),
            [
              'cw:movies',
              'fav:playlist',
              'collection:pinned',
              'traktlist:watchlist',
              'collection:unpinned',
              'cinemeta:movie:top',
            ],
          );
        },
      );
    },
  );

  group('buildCollectionSections / enumerateBoardRefs', () {
    test('skips disabled, empty, and disabled-row collections', () {
      final rows = HomeBoardController.buildCollectionSections(
        collections: [
          _collection('on'),
          _collection('off', enabled: false),
          _collection('empty', folders: 0),
          _collection('hidden'),
        ],
        disabled: {'collection:hidden'},
      );
      expect(rows.map((s) => s.rowId), ['collection:on']);
    });

    test('drops search-only, hidden, and collection-claimed catalogs', () {
      final claimedAddon = _addon('cine', [
        _catalog('top'),
        _catalog('search', searchOnly: true),
        _catalog('hidden'),
      ]);
      final collection = HomeCollection(
        id: 'pack',
        title: 'Pack',
        folders: [
          HomeCollectionFolder(
            id: 'f',
            title: 'F',
            sources: [
              CollectionCatalogSource(
                addonId: 'cine',
                type: 'movie',
                catalogId: 'top',
              ),
            ],
          ),
        ],
      );
      final refs = HomeBoardController.enumerateBoardRefs(
        addons: [claimedAddon],
        disabled: {HomeRowIds.catalog('cine', 'movie', 'hidden')},
        collections: [collection],
      );
      expect(
        refs,
        isEmpty,
        reason: 'top is claimed, search is not browsable, hidden is disabled',
      );
    });
  });

  group('fetchBoardBatch / fetchBoardBatchUntilNonEmpty', () {
    late Map<String, Completer<FilteredPage>> pending;
    late HomeBoardController board;

    StremioAddon catalogAddon() {
      final catalogs = [
        _catalog('empty'),
        _catalog('a', name: 'A'),
        _catalog('b', name: 'B'),
        _catalog('c', name: 'C'),
      ];
      return _addon('x', catalogs);
    }

    setUp(() {
      pending = {};
      final addon = catalogAddon();
      board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) {
              final key = catalog.id;
              final c = pending[key] ?? Completer<FilteredPage>();
              pending[key] = c;
              return c.future;
            },
      );
      board.replaceBoardRefs([
        for (final c in addon.catalogs) (addon, c),
      ], applySavedOrder: false);
    });

    tearDown(() => board.dispose());

    test('stale gen returns empty without advancing the cursor', () async {
      board.boardLoadGen = 2;
      final out = await board.fetchBoardBatch(8, 1);
      expect(out, isEmpty);
      expect(board.boardCursor, 0);
    });

    test('advances the cursor before the fetches land', () async {
      final gen = board.beginLoad();
      expect(gen, 1);
      final future = board.fetchBoardBatch(2, gen);
      expect(board.boardCursor, 2, reason: 'cursor advances before await');
      pending['empty']!.complete(_page(const []));
      pending['a']!.complete(_page(const ['tt-a']));
      final out = await future;
      expect(out, hasLength(1));
      expect(out.single.catalog.id, 'a');
      expect(out.single.items.single.id, 'tt-a');
    });

    test('preserves order and drops empty / throwing catalogs', () async {
      final addon = catalogAddon();
      board.dispose();
      board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) async {
              if (catalog.id == 'empty') return _page(const []);
              if (catalog.id == 'b') throw StateError('dead');
              return _page(['tt-${catalog.id}']);
            },
      );
      board.replaceBoardRefs([
        for (final c in addon.catalogs) (addon, c),
      ], applySavedOrder: false);
      final gen = board.beginLoad();
      final out = await board.fetchBoardBatch(4, gen);
      expect(out.map((s) => s.catalog.id), ['a', 'c']);
    });

    test(
      'untilNonEmpty skips empty batches and can return an in-flight stale batch',
      () async {
        final gen = board.beginLoad();
        final future = board.fetchBoardBatchUntilNonEmpty(gen);
        // First batch of 8 covers every ref. empty+a+b+c.
        pending['empty']!.complete(_page(const []));
        pending['a']!.complete(_page(const []));
        pending['b']!.complete(_page(const ['tt-b']));
        pending['c']!.complete(_page(const []));
        final out = await future;
        expect(out.map((s) => s.catalog.id), ['b']);
      },
    );

    test(
      'untilNonEmpty stops when gen goes stale before the next batch',
      () async {
        final addon = _addon('x', [
          for (var i = 0; i < 10; i++) _catalog('r$i'),
        ]);
        board.dispose();
        final gates = <String, Completer<FilteredPage>>{};
        board = HomeBoardController(
          fetchCatalog:
              (addon, catalog, {required skip, seenIds, minItems = 12}) {
                final c = gates[catalog.id] ?? Completer<FilteredPage>();
                gates[catalog.id] = c;
                return c.future;
              },
        );
        board.replaceBoardRefs([
          for (final c in addon.catalogs) (addon, c),
        ], applySavedOrder: false);
        final gen = board.beginLoad();
        final future = board.fetchBoardBatchUntilNonEmpty(gen);
        expect(board.boardCursor, 8, reason: 'first batch already advanced');
        // Bump gen while the empty batch is in flight so the while condition
        // fails before a second batch can start.
        board.beginLoad();
        for (var i = 0; i < 8; i++) {
          gates['r$i']!.complete(_page(const []));
        }
        final out = await future;
        expect(out, isEmpty);
        expect(board.boardCursor, 8);
      },
    );
  });

  group('loadMoreRow', () {
    CatalogSection sectionWith(List<String> ids) {
      final addon = _addon('x', [_catalog('top')]);
      return CatalogSection(
        title: 'Top',
        addon: addon,
        catalog: addon.catalogs.first,
        items: [for (final id in ids) _meta(id)],
        nextSkip: ids.length,
      );
    }

    test('no-ops while a catalog search is showing results', () async {
      final board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) {
              fail('must not fetch during search');
            },
      );
      addTearDown(board.dispose);
      final section = sectionWith(['tt1']);
      final result = await board.loadMoreRow(
        sections: [section],
        rowIndex: 0,
        catalogSearchActive: true,
      );
      expect(result.skipped, isTrue);
      expect(section.loadingMore, isFalse);
    });

    test('no-ops out of range and when already loading or exhausted', () async {
      final board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) {
              fail('must not fetch');
            },
      );
      addTearDown(board.dispose);
      final loading = sectionWith(['tt1'])..loadingMore = true;
      final done = sectionWith(['tt1'])..exhausted = true;
      expect(
        (await board.loadMoreRow(
          sections: [loading],
          rowIndex: 0,
          catalogSearchActive: false,
        )).skipped,
        isTrue,
      );
      expect(
        (await board.loadMoreRow(
          sections: [done],
          rowIndex: 0,
          catalogSearchActive: false,
        )).skipped,
        isTrue,
      );
      expect(
        (await board.loadMoreRow(
          sections: [done],
          rowIndex: 3,
          catalogSearchActive: false,
        )).skipped,
        isTrue,
      );
    });

    test('identity swap mid-fetch does not append', () async {
      final gate = Completer<FilteredPage>();
      final board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) =>
                gate.future,
      );
      addTearDown(board.dispose);
      final original = sectionWith(['tt1']);
      final sections = [original];
      final future = board.loadMoreRow(
        sections: sections,
        rowIndex: 0,
        catalogSearchActive: false,
      );
      expect(original.loadingMore, isTrue);
      sections[0] = sectionWith(['tt-search']);
      gate.complete(_page(const ['tt2']));
      final result = await future;
      expect(result.fresh, isEmpty);
      expect(original.items.map((m) => m.id), ['tt1']);
      expect(original.loadingMore, isFalse);
    });

    test('empty / duplicate page exhausts the row', () async {
      final board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) async =>
                _page(const []),
      );
      addTearDown(board.dispose);
      final section = sectionWith(['tt1']);
      final result = await board.loadMoreRow(
        sections: [section],
        rowIndex: 0,
        catalogSearchActive: false,
      );
      expect(result.fresh, isEmpty);
      expect(section.exhausted, isTrue);
      expect(section.loadingMore, isFalse);
    });

    test('appends fresh items and clears loadingMore', () async {
      final board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) async {
              expect(skip, 1);
              expect(seenIds, {'tt1'});
              return _page(
                const ['tt2', 'tt3'],
                nextSkip: 10,
                exhausted: false,
              );
            },
      );
      addTearDown(board.dispose);
      final section = sectionWith(['tt1']);
      final result = await board.loadMoreRow(
        sections: [section],
        rowIndex: 0,
        catalogSearchActive: false,
      );
      expect(result.fresh.map((m) => m.id), ['tt2', 'tt3']);
      expect(section.items.map((m) => m.id), ['tt1', 'tt2', 'tt3']);
      expect(section.nextSkip, 10);
      expect(section.exhausted, isFalse);
      expect(section.loadingMore, isFalse);
    });

    test('fetch throw leaves the row retryable', () async {
      final board = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) async {
              throw StateError('timeout');
            },
      );
      addTearDown(board.dispose);
      final section = sectionWith(['tt1']);
      await board.loadMoreRow(
        sections: [section],
        rowIndex: 0,
        catalogSearchActive: false,
      );
      expect(section.exhausted, isFalse);
      expect(section.loadingMore, isFalse);
      expect(section.items, hasLength(1));
    });
  });

  group('hero source pref resolution', () {
    test('random drops live types; custom keeps an explicit live pick', () {
      final live = _addon('iptv', [
        _catalog('channels', type: 'tv', name: 'TV'),
      ]);
      final movies = _addon('cine', [_catalog('top')]);
      final radio = _addon('radio', [
        _catalog('all', type: 'RADIO', name: 'Radio'),
      ]);
      final random = HomeBoardController.heroCandidates(
        source: (mode: HomeHeroSourceMode.random, ids: const []),
        addons: [live, movies, radio],
      );
      expect(random.map((r) => r.$2.id), ['top']);

      final custom = HomeBoardController.heroCandidates(
        source: (
          mode: HomeHeroSourceMode.custom,
          ids: const ['iptv:tv:channels', 'missing:movie:x', 'cine:movie:top'],
        ),
        addons: [live, movies, radio],
      );
      expect(
        custom.map((r) => HomeRowIds.catalog(r.$1.id, r.$2.type, r.$2.id)),
        ['iptv:tv:channels', 'cine:movie:top'],
        reason: 'unresolved ids drop out; live custom picks stay',
      );
    });

    test('auto has no candidates so the override is cleared', () {
      expect(
        HomeBoardController.heroCandidates(
          source: (mode: HomeHeroSourceMode.auto, ids: const []),
          addons: [
            _addon('cine', [_catalog('top')]),
          ],
        ),
        isEmpty,
      );
    });

    test(
      'first non-empty candidate wins; gen cancel drops a stale commit',
      () async {
        final a = _addon('a', [_catalog('one')]);
        final b = _addon('b', [_catalog('two')]);
        final first = Completer<FilteredPage>();
        final second = Completer<FilteredPage>();
        var calls = 0;
        final board = HomeBoardController(
          random: Random(1),
          fetchCatalog:
              (addon, catalog, {required skip, seenIds, minItems = 12}) {
                expect(minItems, 8);
                calls++;
                return calls == 1 ? first.future : second.future;
              },
        );
        addTearDown(board.dispose);
        board.heroSource = (
          mode: HomeHeroSourceMode.custom,
          ids: const ['a:movie:one', 'b:movie:two'],
        );
        board.spotlightHeroOverride = CatalogSection(
          title: 'stale',
          addon: a,
          catalog: a.catalogs.first,
          items: [_meta('old')],
        );

        final run = board.resolveSpotlightHeroSource([a, b]);
        // Bump gen so the in-flight run must not commit.
        board.heroSourceResolveGen++;
        first.complete(_page(const ['tt-new']));
        await run;
        expect(board.spotlightHeroOverride?.items.single.id, 'old');

        // A fresh auto run clears the stale override.
        board.heroSource = (mode: HomeHeroSourceMode.auto, ids: const []);
        await board.resolveSpotlightHeroSource([a, b]);
        expect(board.spotlightHeroOverride, isNull);
      },
    );

    test('attempts are capped at 8 even when more candidates exist', () async {
      var fetches = 0;
      final addons = [
        for (var i = 0; i < 12; i++) _addon('a$i', [_catalog('c$i')]),
      ];
      final board = HomeBoardController(
        random: Random(0),
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) async {
              fetches++;
              return _page(const []);
            },
      );
      addTearDown(board.dispose);
      board.heroSource = (
        mode: HomeHeroSourceMode.custom,
        ids: [for (var i = 0; i < 12; i++) 'a$i:movie:c$i'],
      );
      await board.resolveSpotlightHeroSource(addons);
      expect(fetches, kHomeHeroMaxAttempts);
      expect(board.spotlightHeroOverride, isNull);
    });
  });

  group('reload diffing', () {
    HomeBoardController board() {
      final c = HomeBoardController(
        fetchCatalog:
            (addon, catalog, {required skip, seenIds, minItems = 12}) async =>
                _page(const []),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('unchanged snapshot is a no-op', () {
      final b = board();
      expect(
        b.diffAndApplySettings(_snap(), isHomeBoard: true).nothingChanged,
        isTrue,
      );
    });

    test(
      'disabled / board extras / collections / hide-watched reload the board',
      () {
        final b = board();
        expect(
          b
              .diffAndApplySettings(
                _snap(disabled: {'cw:movies'}),
                isHomeBoard: true,
              )
              .requestBoardReload,
          isTrue,
        );

        final b2 = board();
        expect(
          b2
              .diffAndApplySettings(
                _snap(extras: const [(id: 'traktlist:watchlist', title: '')]),
                isHomeBoard: true,
              )
              .requestBoardReload,
          isTrue,
        );

        final b3 = board();
        expect(
          b3
              .diffAndApplySettings(
                _snap(collections: [_collection('x')]),
                isHomeBoard: true,
              )
              .requestBoardReload,
          isTrue,
        );

        final b4 = board();
        expect(
          b4
              .diffAndApplySettings(_snap(hideWatched: true), isHomeBoard: true)
              .requestBoardReload,
          isTrue,
        );
      },
    );

    test('iptv extras reload IPTV lists without refetching catalogs', () {
      final b = board();
      final action = b.diffAndApplySettings(
        _snap(extras: const [(id: 'iptvlist:sports', title: 'Sports')]),
        isHomeBoard: true,
      );
      expect(action.requestBoardReload, isFalse);
      expect(action.rerollHero, isFalse);
      expect(action.reloadIptvLists, isTrue);
    });

    test('an extras title rename is a change (same id is not enough)', () {
      final b = board();
      b.diffAndApplySettings(
        _snap(extras: const [(id: 'traktlist:watchlist', title: 'Old')]),
        isHomeBoard: true,
      );
      final action = b.diffAndApplySettings(
        _snap(extras: const [(id: 'traktlist:watchlist', title: 'New')]),
        isHomeBoard: true,
      );
      expect(action.nothingChanged, isFalse);
      expect(action.requestBoardReload, isTrue);
    });

    test('hero-only change rerolls the reel on Home, not Search/Discover', () {
      final home = board();
      final action = home.diffAndApplySettings(
        _snap(heroSource: (mode: HomeHeroSourceMode.auto, ids: const [])),
        isHomeBoard: true,
      );
      expect(action.requestBoardReload, isFalse);
      expect(action.rerollHero, isTrue);

      final search = board();
      final searchAction = search.diffAndApplySettings(
        _snap(heroSource: (mode: HomeHeroSourceMode.auto, ids: const [])),
        isHomeBoard: false,
      );
      expect(searchAction.requestBoardReload, isFalse);
      expect(searchAction.rerollHero, isFalse);
    });

    test('row-order change reloads Home only', () {
      final home = board();
      expect(
        home
            .diffAndApplySettings(
              _snap(rowOrder: const ['cw:movies']),
              isHomeBoard: true,
            )
            .requestBoardReload,
        isTrue,
      );
      final search = board();
      expect(
        search
            .diffAndApplySettings(
              _snap(rowOrder: const ['cw:movies']),
              isHomeBoard: false,
            )
            .requestBoardReload,
        isFalse,
      );
    });

    test('hero + disabled takes the full reload, not a hero-only reroll', () {
      final b = board();
      final action = b.diffAndApplySettings(
        _snap(
          disabled: {'cw:movies'},
          heroSource: (mode: HomeHeroSourceMode.auto, ids: const []),
        ),
        isHomeBoard: true,
      );
      expect(action.requestBoardReload, isTrue);
      expect(action.rerollHero, isFalse);
    });
  });
}
