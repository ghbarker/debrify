import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_collection_inventory.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/collection_folder_loader.dart';
import 'package:debrify/services/collection_catalog_pager.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/screens/settings/home_sections_filter_page.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_ui_refresh.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';

const source = CollectionCatalogSource(
  addonId: 'addon',
  type: 'movie',
  catalogId: 'popular',
);
const folder = HomeCollectionFolder(
  id: 'netflix',
  title: 'Netflix',
  sources: [source],
);
const collection = HomeCollection(
  id: 'streaming',
  title: 'Streaming',
  folders: [folder],
);
StremioAddon addon({String id = 'addon', String catalog = 'popular'}) =>
    StremioAddon(
      id: id,
      name: id,
      manifestUrl: 'https://example.invalid/$id/manifest.json',
      baseUrl: 'https://example.invalid/$id',
      resources: ['catalog'],
      catalogs: [
        StremioAddonCatalog(id: catalog, type: 'movie', name: catalog),
      ],
    );
StremioMeta meta(String id) => StremioMeta(id: id, type: 'movie', name: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
    SharedPreferences.setMockInitialValues({});
    StremioService.instance.invalidateCache();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
  });

  test(
    'URL import must not write to a different profile after download',
    () async {
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
      );
      final started = Completer<void>(), reply = Completer<http.Response>();
      final store = HomeCollectionsStore(
        httpClientFactory: () => MockClient((_) {
          started.complete();
          return reply.future;
        }),
      );
      final pending = store.importFromUrl(
        'https://example.invalid/collections.json',
      );
      await started.future;
      ProfileRuntime.publish(
        ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
      );
      reply.complete(http.Response(jsonEncode([collection.toJson()]), 200));
      try {
        await pending;
      } catch (_) {}
      expect(
        await store.getCollections(),
        isEmpty,
        reason: 'Profile two must not receive profile one import',
      );
    },
  );

  test('refused tvOS preference save must not report import success', () async {
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
    final store = HomeCollectionsStore();
    await expectLater(store.importCollections([collection]), throwsA(anything));
  });

  test('concurrent local imports must preserve both collections', () async {
    final store = HomeCollectionsStore();
    await Future.wait([
      store.importCollections([collection]),
      store.importCollections([
        const HomeCollection(id: 'genres', title: 'Genres', folders: [folder]),
      ]),
    ]);
    expect((await store.getCollections()).map((c) => c.id).toSet(), {
      'streaming',
      'genres',
    });
  });

  test(
    'missing catalog must not silently switch providers',
    () {
      final wrong = addon(catalog: 'other');
      final right = addon(id: 'fork');
      expect(
        HomeCollectionsStore.resolveAddon(source, [wrong, right]),
        isNull,
      );
    },
  );

  test('import must report missing catalog on an installed addon', () async {
    final result = await HomeCollectionsStore().importCollections(
      [collection],
      installedAddons: [addon(catalog: 'other')],
    );
    expect(result.unresolvedAddonIds, contains('addon'));
  });

  test(
    'merged pagination must continue through cross-catalog duplicates',
    () async {
      final a = StremioAddon(
        id: 'addon',
        name: 'Addon',
        manifestUrl: 'https://example.invalid/manifest.json',
        baseUrl: 'https://example.invalid',
        resources: ['catalog'],
        catalogs: [
          const StremioAddonCatalog(
            id: 'popular',
            type: 'movie',
            name: 'Popular',
          ),
          const StremioAddonCatalog(id: 'top', type: 'movie', name: 'Top'),
        ],
      );
      final loader = CollectionFolderLoader(
        folder: folder.copyWith(
          sources: [
            source,
            const CollectionCatalogSource(
              addonId: 'addon',
              type: 'movie',
              catalogId: 'top',
            ),
          ],
        ),
        installedAddons: [a],
        fetch: (a, c, {skip = 0, genre, onRawCount}) async {
          onRawCount?.call(1);
          return c.id == 'popular'
              ? switch (skip) {
                  0 => [meta('tt1')],
                  1 => [meta('tt2')],
                  2 => [meta('tt3')],
                  _ => [],
                }
              : switch (skip) {
                  0 => [meta('tt2')],
                  1 => [meta('tt1')],
                  2 => [meta('tt4')],
                  _ => [],
                };
        },
      );
      expect((await loader.nextPage()).map((m) => m.id), ['tt1', 'tt2']);
      expect((await loader.nextPage()).map((m) => m.id), ['tt3', 'tt4']);
      expect(loader.exhausted, false);
    },
  );

  test(
    'merged pagination must continue through a raw page filtered to empty',
    () async {
      final loader = CollectionFolderLoader(
        folder: folder,
        installedAddons: [addon()],
        fetch: (a, c, {skip = 0, genre, onRawCount}) async {
          onRawCount?.call(1);
          return skip == 0 ? [] : [meta('tt2')];
        },
      );
      expect((await loader.nextPage()).map((m) => m.id), ['tt2']);
      expect(loader.exhausted, false);
    },
  );

  testWidgets('TV tabs Down from folder chip must focus a title', (
    tester,
  ) async {
    final a = addon(id: 'widget-tabs');
    const s = CollectionCatalogSource(
      addonId: 'widget-tabs',
      type: 'movie',
      catalogId: 'popular',
    );
    const c = HomeCollection(
      id: 'widget',
      title: 'Streaming',
      folders: [
        HomeCollectionFolder(id: 'f', title: 'Netflix', sources: [s]),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([a.toJson()]),
      HomeCollectionsStore.folderLayoutKey: 'tabs',
      HomeCollectionsStore.prefsKey: jsonEncode([c.toJson()]),
    });
    await tester.runAsync(() async {
      await StremioService.instance.getCatalogAddons();
      await http.runWithClient(
        () => StremioService.instance.fetchCatalog(a, a.catalogs.single),
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'metas': [
                for (var i = 0; i < 100; i++)
                  {'id': 'tt$i', 'type': 'movie', 'name': 'Title $i'},
              ],
            }),
            200,
          ),
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: c,
          isTelevision: true,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SeeAllPosterGrid), findsOneWidget);
    final chip = tester
        .widgetList<StremioDropdown<int>>(find.byType(StremioDropdown<int>))
        .firstWhere((w) => w.label == 'Folder');
    chip.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('seeall_grid_'),
    );
    final focused = FocusManager.instance.primaryFocus;
    final grid = tester.state(find.byType(SeeAllPosterGrid));
    MainPageBridge.notifyHomeSettingsChanged();
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(SeeAllPosterGrid)), grid), true);
    expect(identical(FocusManager.instance.primaryFocus, focused), true);
    // A real definition change rebuilds content but returns focus to a usable
    // filter control instead of leaving it attached to a disposed poster.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(HomeCollectionsStore.folderLayoutKey, 'rows');
    MainPageBridge.notifyHomeSettingsChanged();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'collection_folder');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Home Rows must preserve hidden addon flag while catalog lives in a folder',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final a = addon();
      await StorageService.setHomeDisabledSections({'addon:movie:popular'});
      await tester.pumpWidget(
        MaterialApp(
          home: HomeSectionsFilterPage(
            catalogTree: [(addon: a, catalogs: a.catalogs)],
            collections: [collection],
            disabled: {'addon:movie:popular'},
            isTelevision: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies').first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(
        await StorageService.getHomeDisabledSections(),
        contains('addon:movie:popular'),
      );
    },
  );

  testWidgets('Retry in tab B must remain on tab B', (tester) async {
    final a = StremioAddon(
      id: 'retry-addon',
      name: 'Retry',
      manifestUrl: 'https://example.invalid/retry/manifest.json',
      baseUrl: 'https://example.invalid/retry',
      resources: ['catalog'],
      catalogs: [
        const StremioAddonCatalog(id: 'a', type: 'movie', name: 'A'),
        const StremioAddonCatalog(id: 'b', type: 'movie', name: 'B'),
      ],
    );
    final c = HomeCollection(
      id: 'retry',
      title: 'Retry',
      folders: [
        HomeCollectionFolder(
          id: 'f',
          title: 'Folder',
          sources: [
            for (final cat in a.catalogs)
              CollectionCatalogSource(
                addonId: a.id,
                type: 'movie',
                catalogId: cat.id,
              ),
          ],
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([a.toJson()]),
      HomeCollectionsStore.folderLayoutKey: 'tabs',
    });
    await tester.runAsync(() async {
      await StremioService.instance.getCatalogAddons();
      for (final cat in a.catalogs) {
        await http.runWithClient(
          () => StremioService.instance.fetchCatalog(a, cat),
          () => MockClient(
            (_) async => http.Response(
              jsonEncode({
                'metas': cat.id == 'a'
                    ? [
                        for (var i = 0; i < 100; i++)
                          {'id': 'tt$i', 'type': 'movie', 'name': 'Title $i'},
                      ]
                    : [],
              }),
              200,
            ),
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: c,
          isTelevision: true,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    StremioDropdown<int> listChip() => tester
        .widgetList<StremioDropdown<int>>(find.byType(StremioDropdown<int>))
        .firstWhere((w) => w.label == 'List');
    listChip().onSelected(1);
    await tester.pumpAndSettle();
    expect(find.text('Nothing in this list'), findsOneWidget);
    final retry = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Retry'),
    );
    retry.focusNode!.requestFocus();
    await tester.pump();
    await http.runWithClient(
      () async {
        await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
        await tester.pumpAndSettle();
      },
      () => MockClient(
        (request) async => http.Response(
          jsonEncode({
            'metas': [
              for (var i = 0; i < 100; i++)
                {'id': 'recovered$i', 'type': 'movie', 'name': 'Recovered $i'},
            ],
          }),
          200,
        ),
      ),
    );
    expect(listChip().value, 1);
    expect(find.byType(SeeAllPosterGrid), findsOneWidget);
    expect(
      tester
          .widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid))
          .items
          .first
          .id,
      'recovered0',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('seeall_grid_'),
    );
    await tester.runAsync(() async {
      await http.runWithClient(
        () => StremioService.instance.fetchCatalog(a, a.catalogs[1], skip: 100),
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'metas': [
                for (var i = 0; i < 100; i++)
                  {'id': 'cached$i', 'type': 'movie', 'name': 'Cached $i'},
              ],
            }),
            200,
          ),
        ),
      );
    });
    tester.widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid)).onLoadMore();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid))
          .items
          .last
          .id,
      'cached99',
    );
  });

  test(
    'clearing last collection must remain empty after merging a peer',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([collection]);
      final prefs = await SharedPreferences.getInstance();
      final old = hot('peer', {
        HomeCollectionsStore.prefsKey: prefs.getString(
          HomeCollectionsStore.prefsKey,
        )!,
      }, 1);
      await store.clear();
      final current = hot('local', {
        if (prefs.containsKey(HomeCollectionsStore.prefsKey))
          HomeCollectionsStore.prefsKey: prefs.getString(
            HomeCollectionsStore.prefsKey,
          )!,
      }, 2);
      final merged = WebDavSyncHotMerge.merge(
        local: current,
        peers: [old],
        tombstoneDocuments: [],
        nowMs: 3,
      );
      final inventory = inventoryOf(merged.document);
      expect(inventory.collections, isEmpty);
      expect(inventory.records.containsKey(collection.id), false);
      expect(
        merged.tombstones,
        contains(WebDavSyncRecordKey.homeCollection(collection.id)),
      );
    },
  );

  test('sync must merge independent collections from different devices', () {
    final one = hot('one', {
      HomeCollectionsStore.prefsKey: jsonEncode([collection.toJson()]),
    }, 1);
    final two = hot('two', {
      HomeCollectionsStore.prefsKey: jsonEncode([
        const HomeCollection(
          id: 'genres',
          title: 'Genres',
          folders: [folder],
        ).toJson(),
      ]),
    }, 2);
    final merged = WebDavSyncHotMerge.merge(
      local: one,
      peers: [two],
      tombstoneDocuments: [],
      nowMs: 3,
    ).document;
    expect(inventoryOf(merged).collections.map((c) => c.id).toSet(), {
      'streaming',
      'genres',
    });
  });

  test('HTTP 200 with wrongly typed metas remains retryable and is not cached', () async {
    final a = addon(id: 'malformed-response');
    final pager = CollectionCatalogPager(
      addon: a,
      catalog: a.catalogs.single,
      fetch: (a, c, {skip = 0, genre, onRawCount}) => StremioService.instance
          .fetchCatalog(a, c, skip: skip, genre: genre, onRawCount: onRawCount),
    );
    await http.runWithClient(
      () => pager.nextPage(),
      () => MockClient((_) async => http.Response('{"metas":{}}', 200)),
    );
    expect(pager.exhausted, false);
    expect(pager.error, isNotNull);
    await http.runWithClient(
      () => pager.nextPage(),
      () => MockClient((_) async => http.Response('{"metas":[]}', 200)),
    );
    expect(pager.exhausted, true);
    expect(pager.error, isNull);
  });

  for (final body in ['{}', '{"metas":null}', '{"metas":[]}']) {
    test('catalog end response $body exhausts a folder without Retry', () async {
      StremioService.instance.invalidateCache();
      final a = addon(id: 'empty-response');
      var calls = 0;
      final pager = CollectionCatalogPager(
        addon: a, catalog: a.catalogs.single,
        fetch: (a, c, {skip = 0, genre, onRawCount}) => StremioService.instance
            .fetchCatalog(a, c, skip: skip, genre: genre, onRawCount: onRawCount),
      );
      await http.runWithClient(() async {
        expect(await pager.nextPage(), isEmpty);
        expect(await pager.nextPage(), isEmpty);
      }, () => MockClient((_) async {
        calls++;
        return http.Response(body, 200);
      }));
      expect(calls, 1);
      expect(pager.exhausted, true);
      expect(pager.error, isNull);
    });
  }

  test('hidden collection rows and non-Home modes do not claim catalogs', () {
    final installed = [addon()];
    expect(
      HomeCollectionsStore.claimedCatalogKeys([collection], installed),
      isNotEmpty,
    );
    expect(
      HomeCollectionsStore.claimedCatalogKeys(
        [collection],
        installed,
        disabledRows: {collection.rowId},
      ),
      isEmpty,
    );
    expect(
      HomeCollectionsStore.claimedCatalogKeys(
        [collection],
        installed,
        showsCollectionRows: false,
      ),
      isEmpty,
    );
  });

  test('corrupt local collections do not block other hot preferences', () {
    final document = hot('local', {
      HomeCollectionsStore.prefsKey: '{broken',
      'theme': 'dark',
    }, 1);
    expect(document.scalars.values['theme'], 'dark');
    expect(inventoryOf(document).collections, isEmpty);
  });

  test('bad peer collection records cannot block materialization', () {
    final base = hot('peer', {'theme': 'light'}, 1);
    final stamp = base.watchState.stamp;
    final records = <String, WebDavSyncStampedValue>{
      WebDavSyncRecordKey.homeCollection(collection.id): WebDavSyncStampedValue(
        stamp: stamp,
        value: collection.toJson(),
      ),
      WebDavSyncRecordKey.homeCollection('bad'): WebDavSyncStampedValue(
        stamp: stamp,
        value: 123,
      ),
      'homecollection/%': WebDavSyncStampedValue(stamp: stamp, value: 123),
    };
    final document = WebDavSyncHotDocument(
      circleProfileId: base.circleProfileId,
      scalars: base.scalars,
      watchState: WebDavSyncWatchPart(
        stamp: stamp,
        semanticDigest: '',
        records: records,
        orders: const {},
      ),
    );
    expect(inventoryOf(document).collections.single.id, collection.id);
  });

  test('collection tombstones expire with the shared retention policy', () {
    final deleted = HomeCollectionInventory(
      records: {'old': null},
      order: ['old'],
    );
    final first = WebDavSyncHotMerge.merge(
      local: hot('one', {HomeCollectionsStore.prefsKey: deleted.encode()}, 1),
      peers: [],
      tombstoneDocuments: [],
      nowMs: 2,
    );
    final key = WebDavSyncRecordKey.homeCollection('old');
    expect(first.tombstones, contains(key));
    expect(inventoryOf(first.document).records, isEmpty);
    final expired = WebDavSyncHotMerge.merge(
      local: first.document,
      peers: [],
      nowMs: const Duration(days: 91).inMilliseconds,
      tombstoneDocuments: [
        WebDavSyncTombstoneDocument(
          circleProfileId: first.document.circleProfileId,
          items: {key: first.tombstones[key]!.copyWith(firstPublishedAtMs: 2)},
        ),
      ],
    );
    expect(expired.tombstones, isEmpty);
    final dormant = WebDavSyncHotMerge.merge(
      local: hot('offline', {
        HomeCollectionsStore.prefsKey: jsonEncode([
          const HomeCollection(id: 'old', title: 'Old').toJson(),
        ]),
      }, 1),
      peers: [expired.document],
      tombstoneDocuments: [],
      nowMs: const Duration(days: 91).inMilliseconds,
      dormantSinceMs: 1,
    );
    expect(inventoryOf(dormant.document).collections, isEmpty);
  });

  test('incoming collection sync must notify Home', () {
    var calls = 0;
    void listener() => calls++;
    MainPageBridge.addHomeSettingsListener(listener);
    addTearDown(() => MainPageBridge.removeHomeSettingsListener(listener));
    WebDavSyncUiRefresh.dispatch({HomeCollectionsStore.prefsKey});
    expect(calls, 1);
  });

  test(
    'local import waiting on sync must retain the applied remote collection',
    () async {
      final entered = Completer<void>(), resume = Completer<void>();
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await resume.future;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          HomeCollectionsStore.prefsKey,
          jsonEncode([
            const HomeCollection(
              id: 'remote',
              title: 'Remote',
              folders: [folder],
            ).toJson(),
          ]),
        );
      });
      await entered.future;
      final store = HomeCollectionsStore();
      final pending = store.importCollections([collection]);
      await Future<void>.delayed(Duration.zero);
      resume.complete();
      await Future.wait([barrier, pending]);
      expect((await store.getCollections()).map((c) => c.id).toSet(), {
        'remote',
        'streaming',
      });
    },
  );

  test('accepted imports must fit the sync hot-document size budget', () async {
    final store = HomeCollectionsStore();
    final large = HomeCollection(
      id: 'large',
      title: 'Large',
      folders: [
        for (var i = 0; i < 4000; i++)
          HomeCollectionFolder(
            id: 'f$i',
            title: 'Folder $i',
            sources: [source],
            coverImageUrl: 'https://example.invalid/art/folder-$i.jpg',
          ),
      ],
    );
    final input = jsonEncode([large.toJson()]);
    expect(
      utf8.encode(input).length,
      lessThan(HomeCollectionsStore.maxImportBytes),
    );
    await expectLater(store.importJson(input), throwsFormatException);
    expect(await store.getCollections(), isEmpty);
  });
}

WebDavSyncHotDocument hot(
  String device,
  Map<String, Object?> prefs,
  int time,
) => WebDavSyncHotMerge.build(
  WebDavSyncBuildInput(
    circleProfileId: 'profile-circle',
    deviceId: device,
    rawPreferences: prefs,
    portablePreferences: prefs,
    identityMaps: WebDavSyncIdentityMaps(
      circleToLocalProfiles: {'profile-circle': 'local-profile'},
      circleToLocalResources: {},
    ),
    localNowMs: time,
    clockOffsetMs: 0,
    serverNowMs: time,
  ),
).document;

HomeCollectionInventory inventoryOf(WebDavSyncHotDocument document) =>
    HomeCollectionInventory.decode(
      WebDavSyncHotMerge.materializePreferences(
        document: document,
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: {'profile-circle': 'local-profile'},
          circleToLocalResources: {},
        ),
      )[HomeCollectionsStore.prefsKey],
    );
