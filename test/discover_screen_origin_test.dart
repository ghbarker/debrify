import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/search/search_content_data.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/screens/see_all/catalog_see_all_screen.dart';
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
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
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
  testWidgets(
    'origin Discover integration refresh changes eligibility but skips local CW',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await ProviderCredentialPrefs.setPikPakEnabled(false);
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'origin-before-integration',
        title: 'Before integration',
        contentType: 'movie',
      );
      await mountDiscover(tester, tv: true);
      ContinueWatchingSeeAllScreen panel() =>
          tester.widget<ContinueWatchingSeeAllScreen>(
            find.byType(ContinueWatchingSeeAllScreen),
          );
      final host = tester.state(find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_DiscoverComposition'));
      final sourceNode = discoverSource(tester).focusNode!;
      sourceNode.requestFocus();
      await tester.pump();
      expect(panel().items.map((m) => m.id), ['origin-before-integration']);
      expect(panel().onQuickPlay, isNotNull);

      // Change real persisted CW after startup. A forbidden integration reload
      // would expose this title; the eligibility change proves the listener ran.
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'origin-after-integration',
        title: 'After integration',
        contentType: 'movie',
      );
      await ProviderCredentialPrefs.setPikPakEnabled(true);
      MainPageBridge.notifyIntegrationChanged();
      await pumpFavourites(tester);
      expect(
        identical(tester.state(find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_DiscoverComposition')), host),
        isTrue,
      );
      expect(panel().onQuickPlay, isNull);
      expect(panel().items.map((m) => m.id), ['origin-before-integration']);
      expect(sourceNode.hasFocus, isTrue);

      await ProviderCredentialPrefs.setPikPakEnabled(false);
      MainPageBridge.notifyIntegrationChanged();
      await pumpFavourites(tester);
      expect(panel().onQuickPlay, isNotNull);
      expect(panel().items.map((m) => m.id), ['origin-before-integration']);
      // Positive reload control through the existing real widget callback:
      // the pending title is readable and was not merely an ineffective write.
      final reloaded = await panel().onReload!();
      await pumpFavourites(tester);
      expect(reloaded.map((m) => m.id), contains('origin-after-integration'));
      expect(
        panel().items.map((m) => m.id),
        contains('origin-after-integration'),
      );
      expect(sourceNode.hasFocus, isTrue);
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'origin Discover first frame uses warm layout before fresh preference',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverLayout('grid');
      await mountDiscover(tester, tv: true);
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.rail,
      );
      await closeFavourites(tester);
      await StorageService.setDiscoverLayout('stage');
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(discoverMode: true, isTelevision: true),
        ),
      );
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.rail,
      );
      await pumpFavourites(tester);
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.stage,
      );
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'origin Discover layout change resets signals before async layout',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverLayout('grid');
      await mountDiscover(tester, tv: true);
      final stage = tester.widget<DiscoverTrailerStage>(
        find.byType(DiscoverTrailerStage),
      );
      final rail = tester.widget<DiscoverDetailRail>(
        find.byType(DiscoverDetailRail),
      );
      final theater = tester
          .widgetList<ValueListenableBuilder<bool>>(
            find.ancestor(
              of: find.byType(DiscoverDetailRail),
              matching: find.byWidgetPredicate(
                (w) => w is ValueListenableBuilder<bool>,
              ),
            ),
          )
          .first
          .valueListenable;
      stage.showing!.value = true;
      await tester.pump(const Duration(seconds: 5));
      expect(theater.value, isTrue);
      rail.trailerMeta.value = const StremioMeta(
        id: 'origin',
        type: 'movie',
        name: 'Origin',
      );
      stage.loading.value = true;
      stage.takeover!.value = 0.7;
      final order = <String>[];
      rail.trailerMeta.addListener(() => order.add('meta'));
      stage.loading.addListener(() => order.add('loading'));
      theater.addListener(() => order.add('theater'));
      stage.showing!.addListener(() => order.add('showing'));
      stage.takeover!.addListener(() => order.add('takeover'));
      await StorageService.setDiscoverLayout('stage');
      MainPageBridge.discoverLayoutChanged!();
      expect(order, ['meta', 'loading', 'theater', 'showing', 'takeover']);
      expect(rail.trailerStreams.value, isNull);
      expect(rail.trailerMeta.value, isNull);
      expect(stage.loading.value, isFalse);
      expect(MainPageBridge.tvChromeDim.value, 0);
      // The rendered layout is still the old one until the asynchronous read
      // commits and a frame builds; signal teardown happened synchronously first.
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.rail,
      );
      await pumpFavourites(tester);
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.stage,
      );
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'origin old Discover disposal retains newer settings bridge owner',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      Widget hosts({required bool old, required bool newer}) => MaterialApp(
        home: Stack(
          children: [
            if (old)
              const SearchScreen(
                key: ValueKey('old'),
                discoverMode: true,
                isTelevision: true,
              ),
            if (newer)
              const SearchScreen(
                key: ValueKey('new'),
                discoverMode: true,
                isTelevision: true,
              ),
          ],
        ),
      );
      await tester.pumpWidget(hosts(old: true, newer: false));
      await pumpFavourites(tester);
      final oldLayout = MainPageBridge.discoverLayoutChanged;
      final oldCards = MainPageBridge.discoverCardSettingsChanged;
      await tester.pumpWidget(hosts(old: true, newer: true));
      await pumpFavourites(tester);
      final newLayout = MainPageBridge.discoverLayoutChanged;
      final newCards = MainPageBridge.discoverCardSettingsChanged;
      expect(newLayout, isNot(oldLayout));
      expect(newCards, isNot(oldCards));
      await tester.pumpWidget(hosts(old: false, newer: true));
      await pumpFavourites(tester);
      expect(MainPageBridge.discoverLayoutChanged, newLayout);
      expect(MainPageBridge.discoverCardSettingsChanged, newCards);
      newLayout!();
      newCards!();
      await pumpFavourites(tester);
      await closeFavourites(tester);
      expect(MainPageBridge.discoverLayoutChanged, isNull);
      expect(MainPageBridge.discoverCardSettingsChanged, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  // New helper contract, not an invocation of the original private host method.
  // Origin _refreshBoundSources only awaited inside its eligible-ID loop, so
  // empty/all-ineligible snapshots reached the clear synchronously.
  for (final allInvalid in [false, true]) {
    test('bound reader returns a synchronous map: allInvalid=$allInvalid', () {
      final data = SearchContentData();
      final result = data.readBoundCounts([
        if (allInvalid) ...[
          const StremioMeta(id: 'addon:one', type: 'movie', name: 'One'),
          const StremioMeta(
            id: 'tt1234567',
            imdbId: '',
            type: 'movie',
            name: 'Two',
          ),
        ],
      ]);
      expect(result, isNot(isA<Future<Map<String, int>>>()));
      expect(result, isA<Map<String, int>>());
      expect(result, isEmpty);
    });
  }
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
      try {
        await prepareFavourites(tester);
        StremioService.instance.invalidateCache();
        addTearDown(StremioService.instance.invalidateCache);
        await StorageService.setDiscoverDefaultSource('cw');
        await StorageService.setHomeContinueWatchingEnabled(true);
        await PlaybackProgressStore.saveContinueWatchingItem(
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
      } finally {
        debugPrint = previousPrint;
      }
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
      final renderedAddon = tester
          .widget<CatalogSeeAllScreen>(find.byType(CatalogSeeAllScreen))
          .addon;
      MainPageBridge.notifyIntegrationChanged();
      await pumpFavourites(tester);
      expect(discoverSource(tester).value, hold.source);
      expect(
        identical(
          tester
              .widget<CatalogSeeAllScreen>(find.byType(CatalogSeeAllScreen))
              .addon,
          renderedAddon,
        ),
        isTrue,
      );
      // This is the actual rendered addon reference across integration refresh,
      // not evidence of private map identity or later manifest replacement.
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
