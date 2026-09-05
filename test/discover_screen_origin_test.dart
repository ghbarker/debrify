import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/screens/see_all/mdblist_see_all_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'my_watchlist_loader_origin_test.dart' show HeldWatchlistPreferences;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

// Holds only the actual legacy binding migration write, after the bound reader
// has begun. Other preference reads are not held by this transport.
class HeldBoundMigration extends InMemorySharedPreferencesStore {
  HeldBoundMigration(super.data) : super.withData();
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.series_source_tt1234567') {
      entered.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

// Existing manifest IO seam only. The actual mounted SearchScreen owns source
// revision, preference writes and handoff priority; none is reproduced here.
class DiscoverManifestHold {
  final release = Completer<StremioAddon>();
  final requested = <String>[];
  late String resourceId;
  String get source => 'a:$resourceId';
  static const url = 'https://discover-origin.invalid/manifest.json';

  void complete() => release.complete(
    StremioAddon(
      id: 'origin.catalog',
      name: 'Origin catalog',
      manifestUrl: url,
      baseUrl: 'https://discover-origin.invalid',
      resources: ['catalog'],
      types: ['movie'],
      catalogs: [
        StremioAddonCatalog(id: 'movies', type: 'movie', name: 'Movies'),
      ],
    ),
  );
}

Future<DiscoverManifestHold> prepareDiscoverHydration(
  WidgetTester tester,
) async {
  await prepareFavourites(tester);
  final hold = DiscoverManifestHold();
  final oldFetcher = StremioService.instance.debugManifestFetcher;
  final previousHandoff = MainPageBridge.pendingMdblistListOpen;
  late Directory root;
  late ProfileRegistry registry;
  await tester.runAsync(() async {
    root = await Directory.systemTemp.createTemp('discover-origin-profile-');
    databaseFactory = databaseFactoryFfiNoIsolate;
    registry = await ProfileRegistry.open(path: '${root.path}/profiles.db');
    final profile = await registry.createProfile(
      name: 'Discover origin',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: profile.id,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (i) => i + 11),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profile.id, dataGeneration: 1, sessionEpoch: 1),
    );
    // Exactly the URL-only shape produced by restore; real StremioService
    // hydration must fetch its manifest before the source becomes browsable.
    final resource =
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).create(
          context: await ProfileAuthorizationContext.capture(registry),
          type: ConnectionResourceType.stremioAddon,
          label: 'Restored origin addon',
          publicConfig: const {},
          secretConfig: const {'manifestUrl': DiscoverManifestHold.url},
        );
    hold.resourceId = resource.id;
  });
  StremioService.instance
    ..invalidateCache()
    ..debugManifestFetcher = (url) {
      hold.requested.add(url);
      return hold.release.future;
    };
  addTearDown(() async {
    StremioService.instance
      ..debugManifestFetcher = oldFetcher
      ..invalidateCache();
    MainPageBridge.pendingMdblistListOpen = previousHandoff;
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await tester.runAsync(() async {
      await registry.close();
      await root.delete(recursive: true);
    });
  });
  await StorageService.setHomeHeroTrailerEnabled(false);
  return hold;
}

Finder discoverSourceFinder() => find.byWidgetPredicate(
  (w) => w is StremioDropdown<String> && w.label == 'Source',
);
StremioDropdown<String> discoverSource(WidgetTester tester) =>
    tester.widget<StremioDropdown<String>>(discoverSourceFinder());

Future<void> mountDiscover(WidgetTester tester, {bool tv = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(0.8)),
        child: child!,
      ),
      home: SearchScreen(discoverMode: true, isTelevision: tv),
    ),
  );
  await pumpFavourites(tester);
}

void main() {
  for (final dispose in [false, true]) {
    testWidgets('origin Discover held bound completion dispose=$dispose', (
      tester,
    ) async {
      final previousPrint = debugPrint;
      final messages = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = previousPrint);
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt1234567',
        title: 'Bound origin',
        contentType: 'movie',
      );
      await mountDiscover(tester);
      final item = tester
          .widget<CatalogItemTile>(find.byType(CatalogItemTile))
          .item;
      // This public widget callback closes over the actual host's live bound
      // map. Retaining it lets disposal coverage observe cache writes too.
      final isBound = tester
          .widget<ContinueWatchingSeeAllScreen>(
            find.byType(ContinueWatchingSeeAllScreen),
          )
          .isBound!;
      expect(isBound(item), isFalse);
      final prefs = await SharedPreferences.getInstance();
      final hold = HeldBoundMigration({
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
        'flutter.series_source_tt1234567': jsonEncode({
          'torrentHash': 'origin',
          'torrentName': 'Origin',
          'debridService': 'real_debrid',
          'debridTorrentId': 'origin',
          'boundAt': 1,
        }),
      });
      final previous = SharedPreferencesStorePlatform.instance;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = hold;
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
      });
      MainPageBridge.notifyPlaybackReturned();
      await pumpFavourites(tester);
      expect(hold.entered.isCompleted, isTrue);
      expect(isBound(item), isFalse);
      if (dispose) await tester.pumpWidget(const SizedBox.shrink());
      hold.release.complete();
      await pumpFavourites(tester);
      expect(isBound(item), !dispose);
      // Refresh errors are caught by the host. Observe that channel too so a
      // forbidden setState attempt cannot hide behind the existing catch.
      expect(
        messages.where((m) => m.contains('post-playback refresh failed')),
        isEmpty,
      );
      if (!dispose) {
        expect(
          tester
              .widget<CatalogItemTile>(find.byType(CatalogItemTile))
              .hasBoundSource,
          isTrue,
        );
      }
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
      debugPrint = previousPrint;
    });
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'origin hydrated Discover default applies when no newer intent exists',
    (tester) async {
      final hold = await prepareDiscoverHydration(tester);
      await StorageService.setDiscoverDefaultSource(hold.source);
      await mountDiscover(tester);
      expect(hold.requested, isNotEmpty);
      expect(hold.requested, everyElement(DiscoverManifestHold.url));
      expect(discoverSource(tester).value, 'cw');
      hold.complete();
      await pumpFavourites(tester);
      expect(discoverSource(tester).value, hold.source);
      expect(await StorageService.getDiscoverLastSource(), hold.source);
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('origin explicit Discover source survives held addon hydration', (
    tester,
  ) async {
    final hold = await prepareDiscoverHydration(tester);
    await StorageService.setDiscoverDefaultSource(hold.source);
    await mountDiscover(tester);
    expect(hold.requested, isNotEmpty);
    expect(discoverSource(tester).value, 'cw');
    discoverSource(tester).onSelected('simkl');
    await tester.pump();
    expect(discoverSource(tester).value, 'simkl');
    expect(await StorageService.getDiscoverLastSource(), 'simkl');
    hold.complete();
    await pumpFavourites(tester);
    expect(
      discoverSource(tester).options.map((o) => o.value),
      contains(hold.source),
    );
    expect(discoverSource(tester).value, 'simkl');
    expect(await StorageService.getDiscoverLastSource(), 'simkl');
    await closeFavourites(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'origin Discover handoff beats configured source before and after hydration',
    (tester) async {
      final hold = await prepareDiscoverHydration(tester);
      await StorageService.setDiscoverDefaultSource('trakt');
      MainPageBridge.pendingMdblistListOpen = {
        'id': 91,
        'name': 'Handoff list',
        'liked': true,
      };
      await mountDiscover(tester);
      expect(hold.requested, isNotEmpty);
      expect(MainPageBridge.pendingMdblistListOpen, isNull);
      expect(discoverSource(tester).value, 'mdblist');
      expect(
        tester
            .widget<MdblistSeeAllScreen>(find.byType(MdblistSeeAllScreen))
            .initialList!
            .id,
        91,
      );
      hold.complete();
      await pumpFavourites(tester);
      expect(
        discoverSource(tester).options.map((o) => o.value),
        contains(hold.source),
      );
      expect(discoverSource(tester).value, 'mdblist');
      expect(await StorageService.getDiscoverLastSource(), 'mdblist');
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('origin disposed Discover ignores held startup completion', (
    tester,
  ) async {
    final hold = await prepareDiscoverHydration(tester);
    await StorageService.setDiscoverDefaultSource(hold.source);
    await StorageService.setDiscoverLastSource('cw');
    await mountDiscover(tester);
    expect(hold.requested, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    hold.complete();
    await pumpFavourites(tester);
    expect(await StorageService.getDiscoverLastSource(), 'cw');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'origin Discover playback return waits for preferences then reloads CW and bound data',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await mountDiscover(tester);
      expect(find.byType(CatalogItemTile), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final data = <String, Object>{
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
        'flutter.continue_watching_v1': jsonEncode([
          {
            'imdbId': 'tt1234567',
            'title': 'Returned title',
            'contentType': 'movie',
            'updatedAt': 1,
          },
        ]),
        // A legacy binding read writes its migrated array. The title exists only
        // in the newly read CW data, so this observes real downstream bound IO.
        'flutter.series_source_tt1234567': jsonEncode({
          'torrentHash': 'origin',
          'torrentName': 'Origin',
          'debridService': 'real_debrid',
          'debridTorrentId': 'origin',
          'boundAt': 1,
        }),
      };
      final previous = SharedPreferencesStorePlatform.instance;
      final hold = HeldWatchlistPreferences(data);
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = hold;
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
      });
      MainPageBridge.notifyPlaybackReturned();
      await pumpFavourites(tester);
      expect(hold.events, ['read']);
      expect(find.byType(CatalogItemTile), findsNothing);
      hold.release.complete();
      await pumpFavourites(tester);
      expect(hold.events, ['read', 'read complete', 'bound migration']);
      expect(
        tester.widget<CatalogItemTile>(find.byType(CatalogItemTile)).item.id,
        'tt1234567',
      );
      // Coverage limit: this shared transport hold blocks other preference users
      // too. It does not independently kill removal of the watchlist await.
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
