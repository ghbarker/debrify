import 'dart:async';
import 'dart:io';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/magic_tv_screen.dart';
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
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/engine/settings_manager.dart';
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

// Actual unchanged origin 25fbc2611792d93c28b5a5f608cd252606f3f0ff.
// Mounted public Home-style view callback returns the original host Future;
// only the provider transport is held. No copied flow or private host state.
// The cached finally-return suppresses errors after disposal; it is pinned,
// not fixed. Empty/disabled/missing-key leaf guards remain source-only debt.
const _hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Provider extends FakeCloudProvider {
  _Provider(CloudProviderId id)
    : super(id: id, cacheFlags: [true], cachedHashes: {_hash});
  final requests = <MagicTvPrepareRequest>[];
  final pending = Completer<MagicTvPrepared?>();
  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    requests.add(request);
    return pending.future;
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
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
  expect(ready(), isTrue, reason: 'Actual host did not reach expected phase');
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _seed() async {
  final now = DateTime.utc(2026, 9, 5);
  await DebrifyTvRepository.instance.upsertChannel(
    DebrifyTvChannelRecord(
      channelId: 'fixture',
      name: 'Cached origin',
      keywords: ['keep'],
      avoidNsfw: true,
      channelNumber: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await DebrifyTvCacheService.saveEntry(
    DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: 'fixture',
      normalizedKeywords: ['keep'],
      fetchedAt: 123,
      status: DebrifyTvCacheStatus.ready,
      errorMessage: null,
      torrents: [
        CachedTorrent(
          rowid: 0,
          infohash: _hash,
          name: 'Held 1080p.mkv',
          sizeBytes: 1000000000,
          createdUnix: 1,
          seeders: 20,
          leechers: 0,
          completed: 2,
          scrapedDate: 3,
          sources: const ['fixture'],
          keywords: const ['keep'],
        ),
      ],
      keywordStats: const {
        'keep': KeywordStat(
          totalFetched: 1,
          lastSearchedAt: 111,
          pagesPulled: 1,
          pirateBayHits: 0,
        ),
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Provider provider;
  late _Routes routes;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(
      deviceIdOverride: 'm17-cached-programme-origin-fixture',
    );
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('m17-cached-programme-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
    await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
    await StorageService.savePremiumizeApiKey('fixture-key');
    await StorageService.saveTorboxApiKey('fixture-key');
    await StorageService.setDefaultPlayerMode('internal');
    await StorageService.setDebrifyTvFilterQualities(['fullHd']);
    routes = _Routes();
  });
  tearDown(() async {
    if (!provider.pending.isCompleted) provider.pending.complete(null);
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

  for (final id in [CloudProviderId.torbox, CloudProviderId.premiumize]) {
    for (final dispose in [false, true]) {
      testWidgets('origin ${id.name} cached prepare error disposed=$dispose', (
        tester,
      ) async {
        provider = _Provider(id);
        CloudProviderRegistry.instance = CloudProviderRegistry([provider]);
        await StorageService.saveDebrifyTvProvider(id.magicTvId);
        await tester.runAsync(_seed);
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            builder: (_, child) => AppThemeScope(
              theme: AppThemes.byId('spotlight'),
              child: child!,
            ),
            home: const Scaffold(body: DebrifyTVScreen()),
          ),
        );
        await _until(
          tester,
          () => find.byType(SpotlightLayout).evaluate().isNotEmpty,
        );
        await _until(tester, () => _view(tester).channels.length == 1);
        await _drain(tester);
        final view = _view(tester);
        // Preserve the actual asynchronous method's Future, not a test-local flow.
        final watch = view.onWatch as Future<void> Function(DebrifyTvChannel);
        var completed = false;
        final completion = watch(view.channels.single)
            .then<Object?>(
              (_) => null,
              onError: (Object error, StackTrace stack) => error,
            )
            .whenComplete(() => completed = true);
        await _until(tester, () => provider.requests.length == 1);
        await tester.pump(const Duration(milliseconds: 300));
        expect(provider.requests.single.infohash, _hash);
        expect(_view(tester).busy, isTrue);
        expect(find.byType(CachedLoadingDialog), findsOneWidget);
        expect(completed, isFalse);
        expect(routes.pushes, 2); // Host plus actual cached loading dialog.
        if (dispose) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(find.byType(DebrifyTVScreen), findsNothing);
          expect(
            completed,
            isFalse,
            reason: 'Disposal alone does not finish held prepare',
          );
        }
        final failure = StateError('held cached prepare failure');
        provider.pending.completeError(failure);
        await _until(tester, () => completed);
        expect(await completion, dispose ? isNull : same(failure));
        await _drain(tester);
        expect(provider.requests, hasLength(1));
        expect(find.byType(CachedLoadingDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(routes.pushes, 2); // No external/native/Flutter player route.
        if (!dispose) {
          expect(find.byType(DebrifyTVScreen), findsOneWidget);
          expect(_view(tester).busy, isFalse);
          expect(routes.pops, 1);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
