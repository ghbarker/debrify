import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

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
}
