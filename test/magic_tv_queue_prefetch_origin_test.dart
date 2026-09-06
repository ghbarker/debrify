import 'package:debrify/services/storage/debrify_tv_prefs.dart';
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

// M1-6 live origin: 6e16377990e05ca0c4dd7407365ac3186454d51f.
// Actual host, real storage and outgoing route callbacks. No native video proof.
// Test fixtures repeat setup mechanics only; no production implementation copy.

class _LockedProvider extends FakeCloudProvider {
  _LockedProvider(CloudProviderId id) : super(id: id);
  final pending = Completer<MagicTvLockedBatch?>();
  final requests = <MagicTvPrepareRequest>[];
  final additionalReplies = <Future<MagicTvLockedBatch?>>[];
  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const MagicTvLockedBatch(
        remoteId: 'initial',
        name: 'initial',
        lockedLinks: ['https://locked.invalid/initial'],
      );
    }
    if (requests.length > 2 && additionalReplies.isNotEmpty) {
      return additionalReplies.removeAt(0);
    }
    return pending.future;
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  VideoPlayerScreen? playerRequest;
  bool playerRouteRemoved = false;
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
      scheduleMicrotask(() {
        navigator!.removeRoute(route);
        playerRouteRemoved = true;
      });
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
  int number, {
  int torrentCount = 2,
}) async {
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
    torrents: _pool.take(torrentCount).toList(),
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
  late _LockedProvider port;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    PlatformUtil.debugSetAndroidTvCached(false);
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'm16-origin-fixture');
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('m16-prefetch-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
    await SettingsManager().setGlobalBackgroundPrefetchEnabled(true);
    await StorageService.saveApiKey('captured-key');
    await StorageService.saveAllDebridApiKey('captured-key');
    await StorageService.setDefaultPlayerMode('internal');
  });
  tearDown(() async {
    if (!port.pending.isCompleted) port.pending.complete(null);
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
  for (final provider in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
    testWidgets(
      'origin ${provider.name} held background preparation completes after outgoing route return',
      (tester) async {
        port = _LockedProvider(provider);
        CloudProviderRegistry.instance = CloudProviderRegistry([port]);
        await DebrifyTvPrefs.saveDebrifyTvProvider(provider.magicTvId);
        await tester.runAsync(() => _seed('first', 'First channel', 1));
        final routes = _Routes();
        final unlocks = <http.Request>[];
        await http.runWithClient(
          () async {
            await _mount(tester, routes);
            await _until(tester, () => _view(tester).channels.length == 1);
            final channel = _view(tester).channels.single;
            _view(tester).onChannelFocused(channel);
            await _until(tester, () => _view(tester).stats != null);
            _view(tester).onWatch(channel);
            await _until(
              tester,
              () => routes.playerRequest != null && port.requests.length == 2,
            );
            final player = routes.playerRequest!;
            expect(player.requestMagicNext, isNotNull);
            expect(unlocks, hasLength(1));
            expect(
              port.requests[0].torrent.infohash,
              isNot(port.requests[1].torrent.infohash),
            );
            await tester.pump(const Duration(seconds: 2));
            expect(routes.playerRouteRemoved, isTrue);
            expect(
              _view(tester).busy,
              isTrue,
              reason: 'Route-return stop awaits held background work',
            );
            expect(port.requests, hasLength(2));
            expect(
              unlocks,
              hasLength(1),
              reason: 'Background preparation must not unlock eagerly',
            );
            port.pending.complete(
              const MagicTvLockedBatch(
                remoteId: 'prefetched',
                name: 'prefetched',
                lockedLinks: ['https://locked.invalid/prefetched'],
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(seconds: 2));
            await _until(tester, () => !_view(tester).busy);
            Map<String, String>? next;
            var done = false;
            player.requestMagicNext!().then((value) {
              next = value;
              done = true;
            });
            await _until(tester, () => done);
            expect(next, {
              'url': 'https://fixture.invalid/prefetched.mkv',
              'title': 'prefetched.mkv',
            });
            expect(
              port.requests,
              hasLength(2),
              reason:
                  'Next must consume real prepared queue entry, not prepare again',
            );
            expect(unlocks.map((r) => r.bodyFields['link']), [
              'https://locked.invalid/initial',
              'https://locked.invalid/prefetched',
            ]);
            expect(
              unlocks.last.headers['Authorization'],
              'Bearer captured-key',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            unlocks.add(request);
            final name = Uri.parse(
              request.bodyFields['link']!,
            ).pathSegments.last;
            final url = 'https://fixture.invalid/$name.mkv';
            return http.Response(
              jsonEncode(
                provider == CloudProviderId.debrid
                    ? {'download': url, 'filesize': 1000000000}
                    : {
                        'status': 'success',
                        'data': {'link': url},
                      },
              ),
              200,
            );
          }),
        );
      },
    );
  }
  for (final provider in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
    testWidgets(
      'origin ${provider.name} failed held prefetch rotates same torrent to tail and stops',
      (tester) async {
        port = _LockedProvider(provider);
        CloudProviderRegistry.instance = CloudProviderRegistry([port]);
        await DebrifyTvPrefs.saveDebrifyTvProvider(provider.magicTvId);
        await tester.runAsync(
          () => _seed('first', 'First channel', 1, torrentCount: 3),
        );
        final routes = _Routes();
        final unlocks = <http.Request>[];
        port.additionalReplies.addAll([
          Future.value(_batch('after-failure')),
          Future.value(_batch('retry-failed')),
        ]);
        await http.runWithClient(() async {
          await _mount(tester, routes);
          await _until(tester, () => _view(tester).channels.length == 1);
          _view(tester).onWatch(_view(tester).channels.single);
          await _until(
            tester,
            () => routes.playerRequest != null && port.requests.length == 2,
          );
          await tester.pump(const Duration(seconds: 2));
          expect(routes.playerRouteRemoved, isTrue);
          expect(_view(tester).busy, isTrue);
          final initialHash = port.requests[0].torrent.infohash;
          final failedHash = port.requests[1].torrent.infohash;
          expect(failedHash, isNot(initialHash));
          expect(unlocks, hasLength(1));
          port.pending.completeError(StateError('fixture prepare failure'));
          await _until(tester, () => !_view(tester).busy);
          await tester.pump(const Duration(seconds: 2));
          expect(
            port.requests,
            hasLength(2),
            reason: 'Stopped loop must not retry after failure',
          );
          expect(unlocks, hasLength(1));
          final firstNext = await _next(tester, routes.playerRequest!);
          expect(firstNext, {
            'url': 'https://fixture.invalid/after-failure.mkv',
            'title': 'after-failure.mkv',
          });
          expect(port.requests, hasLength(3));
          expect(
            port.requests[2].torrent.infohash,
            isNot(isIn([initialHash, failedHash])),
            reason: 'Untouched queued torrent precedes failed torrent',
          );
          final secondNext = await _next(tester, routes.playerRequest!);
          expect(secondNext, {
            'url': 'https://fixture.invalid/retry-failed.mkv',
            'title': 'retry-failed.mkv',
          });
          expect(port.requests, hasLength(4));
          expect(
            port.requests[3].torrent.infohash,
            failedHash,
            reason: 'Failed torrent must remain available at tail',
          );
          expect(unlocks.map((r) => r.bodyFields['link']), [
            'https://locked.invalid/initial',
            'https://locked.invalid/after-failure',
            'https://locked.invalid/retry-failed',
          ]);
          expect(await _next(tester, routes.playerRequest!), isNull);
          expect(port.requests, hasLength(4));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }, () => _unlockClient(provider, unlocks));
      },
    );

    testWidgets(
      'origin ${provider.name} channel restart waits for held old preparation then starts new prefetch',
      (tester) async {
        port = _LockedProvider(provider);
        CloudProviderRegistry.instance = CloudProviderRegistry([port]);
        await DebrifyTvPrefs.saveDebrifyTvProvider(provider.magicTvId);
        await tester.runAsync(() async {
          await _seed('first', 'First channel', 1);
          await _seed('second', 'Second channel', 7);
        });
        final restarted = Completer<MagicTvLockedBatch?>();
        port.additionalReplies.addAll([
          Future.value(_batch('new-channel')),
          restarted.future,
        ]);
        final routes = _Routes();
        final unlocks = <http.Request>[];
        await http.runWithClient(() async {
          await _mount(tester, routes);
          await _until(tester, () => _view(tester).channels.length == 2);
          _view(
            tester,
          ).onWatch(_view(tester).channels.firstWhere((c) => c.id == 'first'));
          await _until(
            tester,
            () => routes.playerRequest != null && port.requests.length == 2,
          );
          final player = routes.playerRequest!;
          expect(player.requestChannelById, isNotNull);
          var switched = false;
          Map<String, dynamic>? switchResult;
          player.requestChannelById!('second').then((value) {
            switchResult = value;
            switched = true;
          });
          // Real cache read must settle before advancing the original cooldown.
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump(const Duration(seconds: 1));
          }
          expect(routes.playerRouteRemoved, isTrue);
          expect(switched, isFalse);
          expect(
            port.requests,
            hasLength(2),
            reason:
                'New channel cannot prepare while old stop awaits its held task',
          );
          expect(unlocks, hasLength(1));
          port.pending.complete(_batch('old-prefetch'));
          await _until(tester, () => switched && port.requests.length == 4);
          expect(switchResult, {
            'channelId': 'second',
            'channelName': 'Second channel',
            'channelNumber': 7,
            'firstUrl': 'https://fixture.invalid/new-channel.mkv',
            'firstTitle': 'new-channel.mkv',
          });
          expect(
            port.requests[2].torrent.infohash,
            isNot(port.requests[3].torrent.infohash),
          );
          expect(unlocks.map((r) => r.bodyFields['link']), [
            'https://locked.invalid/initial',
            'https://locked.invalid/new-channel',
          ]);
          // Stop the restarted task through actual host disposal while it is held.
          // Its original late completion still updates the shared queue.
          await tester.pumpWidget(const SizedBox.shrink());
          restarted.complete(_batch('new-prefetch'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(await _next(tester, player), {
            'url': 'https://fixture.invalid/new-prefetch.mkv',
            'title': 'new-prefetch.mkv',
          });
          expect(
            port.requests,
            hasLength(4),
            reason:
                'Restarted prefetch, not a fresh synchronous preparation, supplied next',
          );
          expect(
            unlocks.last.bodyFields['link'],
            'https://locked.invalid/new-prefetch',
          );
          await tester.pumpAndSettle();
        }, () => _unlockClient(provider, unlocks));
      },
    );
  }
}

MagicTvLockedBatch _batch(String id) => MagicTvLockedBatch(
  remoteId: id,
  name: id,
  lockedLinks: ['https://locked.invalid/$id'],
);

MockClient _unlockClient(
  CloudProviderId provider,
  List<http.Request> unlocks,
) => MockClient((request) async {
  unlocks.add(request);
  final name = Uri.parse(request.bodyFields['link']!).pathSegments.last;
  final url = 'https://fixture.invalid/$name.mkv';
  return http.Response(
    jsonEncode(
      provider == CloudProviderId.debrid
          ? {'download': url, 'filesize': 1000000000}
          : {
              'status': 'success',
              'data': {'link': url},
            },
    ),
    200,
  );
});

Future<Map<String, String>?> _next(
  WidgetTester tester,
  VideoPlayerScreen player,
) async {
  Map<String, String>? result;
  var done = false;
  player.requestMagicNext!().then((value) {
    result = value;
    done = true;
  });
  await _until(tester, () => done);
  return result;
}
