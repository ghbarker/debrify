import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';
import 'dart:io';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_layout.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_cloud_provider.dart';

// M1-4 live origin: 39f31d37. Actual host callbacks and real cache/storage.
// Test fixtures repeat setup mechanics only; no production implementation copy.

class _HeldTorbox extends FakeCloudProvider {
  _HeldTorbox([CloudProviderId provider = CloudProviderId.torbox])
    : super(
        id: provider,
        cacheFlags: [true, true, true],
        cachedHashes: {
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'cccccccccccccccccccccccccccccccccccccccc',
        },
      );

  Completer<MagicTvPrepared?>? pending;
  final requests = <MagicTvPrepareRequest>[];
  MagicTvPrepared? prepared;

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    requests.add(request);
    return pending != null ? pending!.future : prepared;
  }
}

class _LockedProvider extends FakeCloudProvider {
  _LockedProvider(CloudProviderId id) : super(id: id);
  Completer<MagicTvLockedBatch?> pending = Completer<MagicTvLockedBatch?>();
  final requests = <MagicTvPrepareRequest>[];
  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) async {
    requests.add(request);
    return pending.future;
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  VideoPlayerScreen? playerRequest;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    if (route is FrozenLegacyPageRoute) {
      final context = navigator!.context;
      final boundary = route.builder(context) as LegacyThemeBoundary;
      playerRequest =
          (boundary.child as Builder).builder(context) as VideoPlayerScreen;
      // Intercept the outgoing player route, not the host or its callbacks.
      // The native player is outside this watch-orchestration pin.
      scheduleMicrotask(() => navigator!.removeRoute(route));
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

DebrifyTvView _view(WidgetTester tester) =>
    tester.widget<SpotlightLayout>(find.byType(SpotlightLayout)).view;

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Real screen did not reach the expected state',
  );
}

CachedTorrent _torrent(String hash, List<String> keywords, String name) =>
    CachedTorrent(
      rowid: 0,
      infohash: hash,
      name: name,
      sizeBytes: 1000000000,
      createdUnix: 1,
      seeders: 20,
      leechers: 0,
      completed: 2,
      scrapedDate: 3,
      sources: const ['fixture'],
      keywords: keywords,
    );

final _pool = [
  _torrent('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'keep',
  ], 'Kept.1080p.mkv'),
  _torrent('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', [
    'keep',
    'drop',
  ], 'Shared.720p.mkv'),
  _torrent('cccccccccccccccccccccccccccccccccccccccc', [
    'drop',
  ], 'Removed.1080p.mkv'),
];

Future<DebrifyTvChannelCacheEntry> _seed(
  String id,
  String name,
  int number,
) async {
  final now = DateTime.utc(2026, 9, 5);
  await DebrifyTvRepository.instance.upsertChannel(
    DebrifyTvChannelRecord(
      channelId: id,
      name: name,
      keywords: ['Keep', 'Drop'],
      avoidNsfw: true,
      channelNumber: number,
      createdAt: now,
      updatedAt: now,
    ),
  );
  final cache = DebrifyTvChannelCacheEntry(
    version: 1,
    channelId: id,
    normalizedKeywords: ['keep', 'drop'],
    fetchedAt: 123,
    status: DebrifyTvCacheStatus.ready,
    errorMessage: 'Baseline diagnostic',
    torrents: [_pool.first],
    keywordStats: const {
      'keep': KeywordStat(
        totalFetched: 2,
        lastSearchedAt: 111,
        pagesPulled: 1,
        pirateBayHits: 0,
      ),
      'drop': KeywordStat(
        totalFetched: 0,
        lastSearchedAt: 112,
        pagesPulled: 1,
        pirateBayHits: 0,
      ),
    },
  );
  await DebrifyTvCacheService.saveEntry(cache);
  return cache;
}

Future<void> _mount(WidgetTester tester, _Routes routes) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [routes],
      builder: (_, child) =>
          AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
      home: const Scaffold(body: DebrifyTVScreen()),
    ),
  );
  await _until(
    tester,
    () => find.byType(SpotlightLayout).evaluate().isNotEmpty,
  );
  // Settings/channel loading is asynchronous; warm its actual callbacks before
  // capturing a view, rather than constructing a test-local view/controller.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _HeldTorbox torbox;
  late _Routes routes;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    PlatformUtil.debugSetAndroidTvCached(false);
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'm1-origin-fixture');
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('m1-cache-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance
        .initialize(); // Empty fixture engine directory.
    await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
    await StorageService.saveApiKey('captured-key');
    await StorageService.saveAllDebridApiKey('captured-key');
    await StorageService.saveTorboxApiKey('fixture-key');
    await StorageService.savePremiumizeApiKey('fixture-key');
    await ProviderCredentialPrefs.setPikPakAccessToken('fixture-access');
    await ProviderCredentialPrefs.setPikPakRefreshToken('fixture-refresh');
    await DebrifyTvPrefs.saveDebrifyTvProvider('torbox');
    await StorageService.setDefaultPlayerMode('internal');
    torbox = _HeldTorbox();
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    routes = _Routes();
  });
  tearDown(() async {
    if (torbox.pending != null && !torbox.pending!.isCompleted) {
      torbox.pending!.complete(null);
    }
    PlatformUtil.debugSetAndroidTvCached(null);
    CloudProviderRegistry.debugReset();
    await DebrifyTvDatabase.instance.debugResetScopeState();
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    StorageService.resetProfileCaches();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    await root.delete(recursive: true);
  });

  for (final provider in [CloudProviderId.torbox, CloudProviderId.pikpak]) {
    for (final cachedTvOverride in [false, true]) {
      testWidgets(
        'origin ${provider.name} desktop switch and host launcher rejection cachedTvOverride=$cachedTvOverride',
        (tester) async {
          PlatformUtil.debugSetAndroidTvCached(cachedTvOverride);
          torbox = _HeldTorbox(provider);
          CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
          await DebrifyTvPrefs.saveDebrifyTvProvider(provider.magicTvId);
          await tester.runAsync(() async {
            await _seed('first', 'First channel', 1);
            await _seed('second', 'Second channel', 7);
          });
          torbox.pending = Completer<MagicTvPrepared?>();
          const initial = MagicTvPrepared(
            streamUrl: 'https://fixture.invalid/first.mkv',
            title: 'First stream',
            hasMore: false,
          );
          const switched = MagicTvPrepared(
            streamUrl: 'https://fixture.invalid/second.mkv',
            title: 'Second stream',
            hasMore: false,
          );
          await _mount(tester, routes);
          await _until(tester, () => _view(tester).channels.length == 2);
          final first = _view(
            tester,
          ).channels.firstWhere((c) => c.id == 'first');
          _view(tester).onChannelFocused(first);
          await _until(tester, () => _view(tester).stats != null);
          _view(tester).onWatch(first);
          await _until(
            tester,
            () =>
                torbox.requests.length == 1 &&
                find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
          );
          await tester.pump(const Duration(milliseconds: 300));
          torbox.pending!.complete(initial);
          await _until(tester, () => routes.playerRequest != null);
          final player = routes.playerRequest!;
          expect(player.videoUrl, initial.streamUrl);
          expect(player.channelName, 'First channel');
          expect(player.channelNumber, 1);
          expect(player.requestChannelById, isNotNull);
          expect(player.requestNextChannel, isNotNull);
          // Both cached overrides leave the desktop host TV flag false; the host
          // guard rejects launch before the bridge. Host-true/native paths are unproven.
          expect(await player.requestChannelById!('missing'), isNull);
          expect(torbox.requests, hasLength(1));
          torbox.pending = Completer<MagicTvPrepared?>();
          Map<String, dynamic>? result;
          var done = false;
          final request = player.requestChannelById!('second').then((value) {
            result = value;
            done = true;
          });
          await tester.pump(const Duration(seconds: 4));
          expect(torbox.requests, hasLength(1));
          expect(done, isFalse);
          await _until(tester, () => torbox.requests.length == 2);
          expect(done, isFalse);
          torbox.pending!.complete(switched);
          await _until(tester, () => done);
          await request;
          expect(result, {
            'channelId': 'second',
            'channelName': 'Second channel',
            'channelNumber': 7,
            'firstUrl': switched.streamUrl,
            'firstTitle': switched.title,
          });
          torbox.pending = null;
          torbox.prepared = switched;
          // The original outgoing player's callback observes the switched queue.
          expect(await player.requestMagicNext!(), isNull);
          expect(torbox.requests, hasLength(2));
          done = false;
          result = null;
          final next = player.requestNextChannel!().then((value) {
            result = value;
            done = true;
          });
          await _until(tester, () => done);
          await next;
          expect(result, {
            'channelId': 'first',
            'channelName': 'First channel',
            'channelNumber': 1,
            'firstUrl': switched.streamUrl,
            'firstTitle': switched.title,
          });
          expect(torbox.requests, hasLength(3));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  for (final provider in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
    testWidgets(
      'origin ${provider.name} switch retains credentials captured before held preparation completes',
      (tester) async {
        PlatformUtil.debugSetAndroidTvCached(true);
        final port = _LockedProvider(provider);
        CloudProviderRegistry.instance = CloudProviderRegistry([port]);
        await DebrifyTvPrefs.saveDebrifyTvProvider(provider.magicTvId);
        await tester.runAsync(() async {
          await _seed('first', 'First channel', 1);
          await _seed('second', 'Second channel', 7);
        });
        final unlocks = <http.Request>[];
        const batch = MagicTvLockedBatch(
          remoteId: 'remote-1',
          name: 'pack',
          lockedLinks: ['https://locked.invalid/file'],
        );
        await http.runWithClient(
          () async {
            await _mount(tester, routes);
            await _until(tester, () => _view(tester).channels.length == 2);
            final first = _view(
              tester,
            ).channels.firstWhere((c) => c.id == 'first');
            _view(tester).onChannelFocused(first);
            await _until(tester, () => _view(tester).stats != null);
            _view(tester).onWatch(first);
            await _until(
              tester,
              () =>
                  port.requests.length == 1 &&
                  find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
            );
            await tester.pump(const Duration(milliseconds: 300));
            port.pending.complete(batch);
            await _until(tester, () => routes.playerRequest != null);
            final player = routes.playerRequest!;
            expect(unlocks, hasLength(1));
            expect(
              unlocks.single.headers['Authorization'],
              'Bearer captured-key',
            );
            expect(player.requestChannelById, isNotNull);
            port.pending = Completer<MagicTvLockedBatch?>();
            Map<String, dynamic>? result;
            var done = false;
            final request = player.requestChannelById!('second').then((value) {
              result = value;
              done = true;
            });
            // New channel captures storage after its original cooldown, not at launch.
            await tester.runAsync(() async {
              await StorageService.saveApiKey('switch-key');
              await StorageService.saveAllDebridApiKey('switch-key');
            });
            await _until(tester, () => port.requests.length == 2);
            expect(done, isFalse);
            await tester.runAsync(() async {
              await StorageService.saveApiKey('too-late-key');
              await StorageService.saveAllDebridApiKey('too-late-key');
            });
            port.pending.complete(batch);
            await _until(tester, () => done);
            await request;
            expect(result, {
              'channelId': 'second',
              'channelName': 'Second channel',
              'channelNumber': 7,
              'firstUrl': 'https://fixture.invalid/resolved.mkv',
              'firstTitle': 'resolved.mkv',
            });
            expect(unlocks, hasLength(2));
            expect(unlocks.last.headers['Authorization'], 'Bearer switch-key');
            expect(unlocks.last.bodyFields, {
              'link': 'https://locked.invalid/file',
            });
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            unlocks.add(request);
            return http.Response(
              jsonEncode(
                provider == CloudProviderId.debrid
                    ? {
                        'download': 'https://fixture.invalid/resolved.mkv',
                        'filesize': 1000000000,
                      }
                    : {
                        'status': 'success',
                        'data': {
                          'link': 'https://fixture.invalid/resolved.mkv',
                        },
                      },
              ),
              200,
            );
          }),
        );
      },
    );
  }
}
