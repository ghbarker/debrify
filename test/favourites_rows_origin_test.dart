import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/stremio_tv_prefs.dart';
import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'origin favourites split watchlist and sort playlist before menus',
    (tester) async {
      await prepareFavourites(tester);
      await MyWatchlistStore.setMyWatchlistItem(
        const StremioMeta(
          id: 'movie',
          type: 'movie',
          name: 'Saved Movie',
          poster: '',
        ),
        true,
      );
      await MyWatchlistStore.setMyWatchlistItem(
        const StremioMeta(
          id: 'series',
          type: 'series',
          name: 'Saved Series',
          poster: '',
        ),
        true,
      );
      await PlaybackProgressStore.savePlaylistItemsRaw([
        {
          'title': 'Older Playlist',
          'kind': 'single',
          'addedAt': 1,
          'id': 'old',
        },
        {
          'title': 'Newer Playlist',
          'kind': 'single',
          'addedAt': 2,
          'id': 'new',
        },
      ]);
      await mountFavourites(tester);
      final posters = tester
          .widgetList<ArtPoster>(find.byType(ArtPoster))
          .toList();
      expect(posters.map((p) => p.title), [
        'Saved Movie',
        'Saved Series',
        'Newer Playlist',
        'Older Playlist',
      ]);
      expect(posters.map((p) => p.focusNode.debugLabel), [
        'search_watchlist_movie_0',
        'search_watchlist_series_0',
        'search_playlistfav_0',
        'search_playlistfav_1',
      ]);
      posters[2].onOpen();
      await tester.pumpAndSettle();
      expect(find.text('Saved item. Choose your next step.'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Play Random'), findsNothing);
      Navigator.of(tester.element(find.text('Play'))).pop();
      await tester.pumpAndSettle();
      await closeFavourites(tester);
    },
  );
  testWidgets(
    'origin TV favourites retain provider order and bridge before tab handoff',
    (tester) async {
      await prepareFavourites(tester);
      await tester.runAsync(() async {
        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        await db.execute(
          'CREATE TABLE tv_channels (channel_id TEXT, name TEXT, channel_number INTEGER, created_at INTEGER, updated_at INTEGER)',
        );
        await db.execute(
          'CREATE TABLE tv_channel_keywords (channel_id TEXT, position INTEGER, keyword TEXT)',
        );
        await db.insert('tv_channels', {
          'channel_id': 'second',
          'name': 'TV Second',
          'channel_number': 2,
          'created_at': 0,
          'updated_at': 0,
        });
        await db.insert('tv_channels', {
          'channel_id': 'first',
          'name': 'TV First',
          'channel_number': 1,
          'created_at': 0,
          'updated_at': 0,
        });
        await DebrifyTvPrefs.setDebrifyTvChannelFavorited('second', true);
        await DebrifyTvPrefs.setDebrifyTvChannelFavorited('first', true);
      });
      await StremioTvPrefs.setStremioTvLocalCatalogs([
        {
          'id': 'local-first',
          'name': 'Local First',
          'type': 'movie',
          'items': [
            {'id': 'one', 'name': 'One', 'type': 'movie', 'poster': ''},
          ],
        },
        {
          'id': 'local-second',
          'name': 'Local Second',
          'type': 'movie',
          'items': [
            {'id': 'two', 'name': 'Two', 'type': 'movie', 'poster': ''},
          ],
        },
      ]);
      await StremioTvPrefs.setStremioTvChannelFavorited(
        'local:local-second:movie',
        true,
      );
      await StremioTvPrefs.setStremioTvChannelFavorited(
        'local:local-first:movie',
        true,
      );
      final previousTv = MainPageBridge.watchDebrifyTvChannel;
      final previousStv = MainPageBridge.watchStremioTvChannel;
      final previousSwitch = MainPageBridge.switchTab;
      addTearDown(() {
        MainPageBridge.watchDebrifyTvChannel = previousTv;
        MainPageBridge.watchStremioTvChannel = previousStv;
        MainPageBridge.switchTab = previousSwitch;
        MainPageBridge.getAndClearDebrifyTvChannelToAutoPlay();
        MainPageBridge.getAndClearStremioTvChannelToAutoPlay();
      });
      await mountFavourites(tester);
      final posters = tester
          .widgetList<ArtPoster>(find.byType(ArtPoster))
          .toList();
      expect(posters.map((p) => p.title), [
        'TV First',
        'TV Second',
        'Local: Local First',
        'Local: Local Second',
      ]);
      expect(posters.take(2).map((p) => p.badge), ['1', '2']);
      final calls = <String>[];
      MainPageBridge.watchDebrifyTvChannel = (id) async => calls.add('tv:$id');
      MainPageBridge.watchStremioTvChannel = (id) async => calls.add('stv:$id');
      MainPageBridge.switchTab = (tab) => calls.add('unexpected:$tab');
      posters[0].onOpen();
      posters[2].onOpen();
      expect(calls, ['tv:first', 'stv:local:local-first:movie']);
      calls.clear();
      MainPageBridge.watchDebrifyTvChannel = null;
      MainPageBridge.watchStremioTvChannel = null;
      MainPageBridge.switchTab = (tab) {
        if (tab == MainTab.debrifyTv) {
          calls.add(
            'tv:${MainPageBridge.getAndClearDebrifyTvChannelToAutoPlay()}',
          );
        } else if (tab == MainTab.stremioTv) {
          calls.add(
            'stv:${MainPageBridge.getAndClearStremioTvChannelToAutoPlay()}',
          );
        } else {
          fail('Unexpected tab $tab');
        }
      };
      posters[1].onOpen();
      posters[3].onOpen();
      expect(calls, ['tv:second', 'stv:local:local-second:movie']);
      await closeFavourites(tester);
    },
  );

  testWidgets(
    'origin IPTV custom list keeps saved order and surviving focus nodes',
    (tester) async {
      await prepareFavourites(tester);
      late String listId;
      await tester.runAsync(() async {
        await StorageService.setIptvChannelFavorited(
          'https://first.invalid/live',
          true,
          channelName: 'Favourite Live',
        );
        listId = await IptvPrefs.createIptvList('Mixed List');
        await StorageService.setIptvChannelInList(
          listId,
          'xtream-series://gone/42',
          true,
          channelName: 'Missing Series',
          contentType: 'series',
          duration: 0,
        );
        await StorageService.setIptvChannelInList(
          listId,
          'https://second.invalid/live',
          true,
          channelName: 'List Live',
          duration: -1,
        );
        await HomePrefs.setHomeExtraRows([
          (id: 'iptvlist:$listId', title: 'Mixed List'),
        ]);
      });
      await mountFavourites(tester);
      List<ArtPoster> posters() =>
          tester.widgetList<ArtPoster>(find.byType(ArtPoster)).toList();
      expect(posters().map((p) => p.title), [
        'Favourite Live',
        'Missing Series',
        'List Live',
      ]);
      final nodes = posters().map((p) => p.focusNode).toList();
      nodes[1].requestFocus();
      await pumpFavourites(tester);
      await tester.runAsync(
        () => IptvPrefs.renameIptvList(listId, 'Renamed List'),
      );
      await pumpFavourites(tester);
      expect(find.text('Renamed List'), findsOneWidget);
      expect(posters().map((p) => p.focusNode), nodes);
      expect(nodes[1].hasFocus, isTrue);
      posters()[1].onOpen();
      await pumpFavourites(tester);
      expect(
        find.text("This series' provider is no longer available"),
        findsOneWidget,
      );
      await tester.runAsync(() => HomePrefs.setHomeExtraRows([]));
      MainPageBridge.notifyHomeSettingsChanged();
      await pumpFavourites(tester);
      expect(posters().map((p) => p.title), ['Favourite Live']);
      expect(tester.takeException(), isNull);
      await closeFavourites(tester);
    },
  );
  testWidgets(
    'origin unavailable watchlist series keeps then removes saved item',
    (tester) async {
      await prepareFavourites(tester);
      final item = StremioMeta(
        id: 'invalid-saved-series',
        type: 'series',
        name: 'Unavailable',
        poster: '',
        sourceAddon: StremioAddon(
          id: 'xtream-iptv',
          name: 'IPTV',
          baseUrl: '',
          manifestUrl: '',
        ),
      );
      await MyWatchlistStore.setMyWatchlistItem(item, true);
      await mountFavourites(tester);
      tester.widget<ArtPoster>(find.byType(ArtPoster)).onOpen();
      await tester.pumpAndSettle();
      expect(find.text('Series unavailable'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(await MyWatchlistStore.isInMyWatchlist(item), isTrue);
      tester.widget<ArtPoster>(find.byType(ArtPoster)).onOpen();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await pumpFavourites(tester);
      expect(await MyWatchlistStore.isInMyWatchlist(item), isFalse);
      expect(find.byType(ArtPoster), findsNothing);
      expect(find.text('Removed from My Watchlist'), findsOneWidget);
      await closeFavourites(tester);
    },
  );

  testWidgets(
    'origin playlist favorite and confirmed deletion persist through row reload',
    (tester) async {
      await prepareFavourites(tester);
      final item = <String, dynamic>{
        'title': 'Managed Playlist',
        'kind': 'single',
        'id': 'managed',
        'addedAt': 1,
      };
      await PlaybackProgressStore.savePlaylistItemsRaw([item]);
      await mountFavourites(tester);
      Future<void> open() async {
        tester.widget<ArtPoster>(find.byType(ArtPoster)).onOpen();
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Favorite'));
      await pumpFavourites(tester);
      expect(
        await PlaybackProgressStore.getPlaylistFavoriteKeys(),
        contains(PlaybackProgressStore.computePlaylistDedupeKey(item)),
      );
      await open();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await PlaybackProgressStore.getPlaylistItemsRaw(), hasLength(1));
      await open();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await pumpFavourites(tester);
      expect(await PlaybackProgressStore.getPlaylistItemsRaw(), isEmpty);
      expect(find.byType(ArtPoster), findsNothing);
      await closeFavourites(tester);
    },
  );

  testWidgets(
    'origin missing Stremio IPTV addon reports unavailable without launching',
    (tester) async {
      await prepareFavourites(tester);
      await tester.runAsync(
        () => StorageService.setIptvChannelFavorited(
          'stremio-tv://missing/tv1',
          true,
          channelName: 'Gone Channel',
        ),
      );
      await mountFavourites(tester);
      final poster = tester.widget<ArtPoster>(find.byType(ArtPoster));
      poster.onOpen();
      poster.onOpen();
      await pumpFavourites(tester);
      expect(
        find.text('The addon behind Gone Channel is no longer installed'),
        findsOneWidget,
      );
      expect(find.byType(SearchScreenHost), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeFavourites(tester);
    },
  );
}

Future<void> prepareFavourites(WidgetTester tester) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('cw-rebuild-'),
  ))!;
  final previousFonts = GoogleFonts.config.allowRuntimeFetching;
  final previousRebuild = debugOnRebuildDirtyWidget;
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({});
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  ProfileSessionMemory.clearAll();
  StorageService.resetProfileCaches();
  SecretVault.debugReset(deviceIdOverride: 'cw-rebuild-test');
  AppStorage.debugOverride(documents: root, support: root, cache: root);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => root.path,
  );
  // Typography is outside this pin; satisfy the loading screen's font from
  // the bundled regular face without fetching a font from the network.
  await tester.runAsync(() async {
    final data = await rootBundle.load('AssetManifest.bin');
    final manifest = Map<Object?, Object?>.from(
      const StandardMessageCodec().decodeMessage(data) as Map,
    );
    final aliases = [
      for (final weight in ['SemiBold', 'ExtraBold', 'Bold', 'Medium'])
        'assets/fonts/Poppins-$weight.ttf',
    ];
    final font = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
    for (final alias in aliases) {
      manifest[alias] = [
        {'asset': alias},
      ];
    }
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (aliases.contains(key)) return font;
      return messenger.delegate.send('flutter/assets', message);
    });
    rootBundle.evict('AssetManifest.bin');
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(() async {
    debugOnRebuildDirtyWidget = previousRebuild;
    messenger.setMockMessageHandler('flutter/assets', null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    rootBundle.evict('AssetManifest.bin');
    GoogleFonts.config.allowRuntimeFetching = previousFonts;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    SecretVault.debugReset();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await tester.runAsync(() => root.delete(recursive: true));
  });
  sqfliteFfiInit();
  IptvMediaStore.debugResetMigration();
  await tester.runAsync(() async {
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
  });
  addTearDown(() async {
    await tester.runAsync(() async {
      await DebrifyTvDatabase.debugDatabaseOverride?.close();
      DebrifyTvDatabase.debugDatabaseOverride = null;
      IptvMediaStore.debugResetMigration();
    });
  });
  await StorageService.setTvHomeStyle('classic');
  await HomePrefs.setHomeHeroTrailerEnabled(false);
  await HomePrefs.setHomeContinueWatchingEnabled(false);
}

Future<void> pumpFavourites(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mountFavourites(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(0.8)),
        child: child!,
      ),
      home: const SearchScreen(isTelevision: true),
    ),
  );
  await pumpFavourites(tester);
}

Future<void> closeFavourites(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpFavourites(tester);
  await tester.pump(const Duration(seconds: 11));
}
