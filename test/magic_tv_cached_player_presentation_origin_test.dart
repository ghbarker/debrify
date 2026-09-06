import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_cloud_provider.dart';

// Cached presentation origin: 7d0b52f9a419b0b82b62a525ab354367b1f05d79.
// Real mounted host callbacks, existing public provider boundary, real storage.
// Four persisted nondefaults plus two hardcoded load quirks; not six configurable options.
// Route builder inspected at push, not a live-builder-time mutation or native proof.

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

Future<DebrifyTvChannelCacheEntry> _seed({bool keepOnlyTorrent = true}) async {
  final now = DateTime.utc(2026, 9, 5);
  await DebrifyTvRepository.instance.upsertChannel(
    DebrifyTvChannelRecord(
      channelId: 'fixture',
      name: 'Origin News',
      keywords: ['Keep', 'Drop'],
      avoidNsfw: true,
      channelNumber: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );
  final cache = DebrifyTvChannelCacheEntry(
    version: 1,
    channelId: 'fixture',
    normalizedKeywords: ['keep', 'drop'],
    fetchedAt: 123,
    status: DebrifyTvCacheStatus.ready,
    errorMessage: 'Baseline diagnostic',
    torrents: keepOnlyTorrent ? _pool : _pool.skip(1).toList(),
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

Future<void> _focus(WidgetTester tester) async {
  await _until(tester, () => _view(tester).channels.length == 2);
  _view(tester).onChannelFocused(
    _view(tester).channels.singleWhere((c) => c.id == 'fixture'),
  );
  await _until(tester, () => _view(tester).stats != null);
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
    await StorageService.setDefaultPlayerMode('external');
    torbox = _HeldTorbox();
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    routes = _Routes();
  });
  tearDown(() async {
    if (torbox.pending != null && !torbox.pending!.isCompleted) {
      torbox.pending!.complete(null);
    }
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

  for (final provider in [
    CloudProviderId.torbox,
    CloudProviderId.premiumize,
    CloudProviderId.pikpak,
  ]) {
    testWidgets(
      'origin ${provider.name} cached presentation preserves options and two-channel metadata',
      (tester) async {
        torbox = _HeldTorbox(provider);
        torbox.pending = Completer<MagicTvPrepared?>();
        CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
        await DebrifyTvPrefs.saveDebrifyTvProvider(provider.magicTvId);
        await StorageService.setDefaultPlayerMode('internal');
        await DebrifyTvPrefs.saveDebrifyTvStartRandom(false);
        await DebrifyTvPrefs.saveDebrifyTvRandomStartPercent(37);
        await DebrifyTvPrefs.saveDebrifyTvShowChannelName(false);
        await DebrifyTvPrefs.saveDebrifyTvShowVideoTitle(false);
        // These stored values are deliberately ignored by the origin load path.
        await DebrifyTvPrefs.saveDebrifyTvHideSeekbar(true);
        await DebrifyTvPrefs.saveDebrifyTvHideOptions(true);
        await tester.runAsync(() async {
          await _seed();
          final now = DateTime.utc(2026, 9, 5);
          await DebrifyTvRepository.instance.upsertChannel(
            DebrifyTvChannelRecord(
              channelId: 'other',
              name: 'Other News',
              keywords: ['other'],
              avoidNsfw: true,
              channelNumber: 7,
              createdAt: now,
              updatedAt: now,
            ),
          );
        });
        await _mount(tester, routes);
        await _focus(tester);
        _view(
          tester,
        ).onWatch(_view(tester).channels.singleWhere((c) => c.id == 'fixture'));
        await _until(
          tester,
          () =>
              torbox.requests.length == 1 &&
              find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
        );
        expect(routes.playerRequest, isNull);
        torbox.pending!.complete(
          const MagicTvPrepared(
            streamUrl: 'https://fixture.invalid/presentation.mkv',
            title: 'Prepared presentation',
            hasMore: false,
          ),
        );
        await _until(tester, () => routes.playerRequest != null);
        final player = routes.playerRequest!;
        expect(player.videoUrl, 'https://fixture.invalid/presentation.mkv');
        expect(player.title, 'Prepared presentation');
        expect(player.startFromRandom, isFalse);
        expect(player.randomStartMaxPercent, 37);
        expect(player.showChannelName, isFalse);
        expect(player.showVideoTitle, isFalse);
        expect(
          player.hideSeekbar,
          isFalse,
        ); // Origin assigns hardcoded hideOptions.
        expect(
          player.hideOptions,
          isFalse,
        ); // Origin hardcodes false despite storedtrue.
        expect(player.channelName, 'Origin News');
        expect(player.channelNumber, 1);
        expect(player.channelDirectory, [
          {
            'id': 'fixture',
            'name': 'Origin News',
            'channelNumber': 1,
            'isCurrent': true,
          },
          {
            'id': 'other',
            'name': 'Other News',
            'channelNumber': 7,
            'isCurrent': false,
          },
        ]);
        expect(player.requestMagicNext, isNotNull);
        expect(player.requestNextChannel, isNotNull);
        expect(player.requestChannelById, isNotNull);
        expect(await player.requestChannelById!('missing'), isNull);
        for (var i = 0; i < 2; i++) {
          expect(await player.requestMagicNext!(), {
            'url': 'https://fixture.invalid/presentation.mkv',
            'title': 'Prepared presentation',
            if (provider == CloudProviderId.pikpak) 'provider': 'pikpak',
          });
        }
        expect(await player.requestMagicNext!(), isNull);
        expect(torbox.requests, hasLength(3));
        expect(
          torbox.requests.map((r) => r.infohash).toSet(),
          _pool.map((t) => t.infohash).toSet(),
        );
        await _until(tester, () => !_view(tester).busy);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
