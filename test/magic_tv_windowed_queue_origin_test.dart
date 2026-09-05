import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:io';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
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

// Actual pre-WindowedWatchRun origin: b5f8b7c26f5a97dcbcbfe6b6cadd331106877291.
// Real host/storage/engine/registry; only external provider responses are held.
// Later route-next refill, distinct from initial cache-window coverage.
// No private queue/timestamp or native playback claim.
class _WindowProvider extends FakeCloudProvider {
  _WindowProvider(CloudProviderId id) : super(id: id);
  final queries = <List<String>>[];
  final releases = <Completer<bool>>[];
  final prepares = <MagicTvPrepareRequest>[];
  final prepared = Completer<MagicTvPrepared?>();
  final nextPrepared = Completer<MagicTvPrepared?>();
  Future<bool> _hold(List<String> hashes) {
    queries.add(List.of(hashes));
    final release = Completer<bool>();
    releases.add(release);
    return release.future;
  }

  @override
  Future<Set<String>> checkCachedHashes(List<String> hashes) async =>
      await _hold(hashes) ? {hashes.first} : {};
  @override
  Future<List<bool>> checkCache(List<String> hashes) async {
    final hit = await _hold(hashes);
    return List.generate(hashes.length, (i) => hit && i == 0);
  }

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) {
    prepares.add(request);
    return prepares.length == 1 ? prepared.future : nextPrepared.future;
  }

  void releaseAll() {
    for (final r in releases) {
      if (!r.isCompleted) r.complete(false);
    }
    if (!prepared.isCompleted) prepared.complete(null);
    if (!nextPrepared.isCompleted) nextPrepared.complete(null);
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  bool interceptPlayer = false;
  VideoPlayerScreen? playerRequest;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    if (interceptPlayer && route is FrozenLegacyPageRoute) {
      final context = navigator!.context;
      final boundary = route.builder(context) as LegacyThemeBoundary;
      playerRequest =
          (boundary.child as Builder).builder(context) as VideoPlayerScreen;
      // Inspect actual route arguments and invoke its actual next callback below;
      // do not mount a native decoder or substitute host orchestration.
      scheduleMicrotask(() => navigator!.removeRoute(route));
    }
  }
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

String _hash(int i) => i.toRadixString(16).padLeft(40, '0');
final _pool = List.generate(
  201,
  (i) => _torrent(_hash(i + 1), ['keep'], 'Window.$i.1080p.mkv'),
);

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

Future<void> _mount(
  WidgetTester tester,
  _Routes routes, {
  int expectedPaintDiagnostics = 0,
}) async {
  final diagnostics = <String>[];
  final original = FlutterError.onError!;
  FlutterError.onError = (details) {
    if (details.exception is FlutterError &&
        details.exceptionAsString() == _editorPaintDiagnostic) {
      diagnostics.add(details.exceptionAsString());
      if (const bool.fromEnvironment('WINDOWED_UNFILTERED')) original(details);
    } else {
      original(details);
    }
  };
  addTearDown(() {
    FlutterError.onError = original;
    expect(
      diagnostics,
      List.filled(expectedPaintDiagnostics, _editorPaintDiagnostic),
    );
  });
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
  await _until(tester, () => _view(tester).channels.isNotEmpty);
  _view(tester).onChannelFocused(_view(tester).channels.single);
  await _until(tester, () => _view(tester).stats != null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _WindowProvider torbox;
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
    await StorageService.setPikPakAccessToken('fixture-access');
    await StorageService.setPikPakRefreshToken('fixture-refresh');
    await StorageService.saveDebrifyTvProvider('torbox');
    await StorageService.setDefaultPlayerMode('external');
    torbox = _WindowProvider(CloudProviderId.torbox);
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    routes = _Routes();
  });
  tearDown(() async {
    torbox.releaseAll();
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
    for (final quick in [false, true]) {
      for (final outcome in ['cancel', 'error']) {
        testWidgets(
          'origin ${id.name} ${quick ? "quick" : "cached"}: LATER route-next refill $outcome',
          (tester) async {
            torbox = _WindowProvider(id);
            routes.interceptPlayer = true;
            await StorageService.setDefaultPlayerMode('internal');
            CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
            await StorageService.saveDebrifyTvProvider(id.magicTvId);
            await tester.runAsync(_seed);
            await _mount(
              tester,
              routes,
              expectedPaintDiagnostics: quick ? 1 : 0,
            );
            await _focus(tester);
            var engineRequests = 0;
            if (quick) {
              await tester.runAsync(() async {
                await LocalEngineStorage.instance.saveEngine(
                  engineId: 'origin_success',
                  fileName: 'origin_success.yaml',
                  yamlContent: _engineYaml,
                  displayName: 'Origin Success',
                );
                await EngineRegistry.instance.reload();
              });
              _view(tester).onQuickPlay();
              await _until(
                tester,
                () => find.text('Play now').evaluate().isNotEmpty,
              );
              await tester.enterText(
                find.descendant(
                  of: find.byType(DebrifyTvSpotlightDialog),
                  matching: find.byType(TextField),
                ),
                'keep0, keep1, keep2, keep3, keep4',
              );
            }
            await http.runWithClient(
              () async {
                if (quick) {
                  await tester.tap(find.text('Play now'));
                } else {
                  _view(tester).onWatch(_view(tester).channels.single);
                }
                final sizes = id == CloudProviderId.torbox
                    ? [90, 90, 21]
                    : [100, 100, 1];
                for (var i = 0; i < 3; i++) {
                  await _until(tester, () => torbox.queries.length == i + 1);
                  expect(torbox.queries[i], hasLength(sizes[i]));
                  expect(torbox.prepares, isEmpty);
                  torbox.releases[i].complete(i == 2);
                }
                await _until(tester, () => torbox.prepares.length == 1);
                // Actual mounted-dialog callback retained after dismissal. This
                // exercises host cancellation, NOT a visible player cancel action.
                final cancel = tester
                    .widget<CachedLoadingDialog>(
                      find.byType(CachedLoadingDialog),
                    )
                    .onCancel!;
                final hit = torbox.queries.last.first;
                expect(torbox.prepares.single.infohash, hit);
                torbox.prepared.complete(
                  const MagicTvPrepared(
                    streamUrl: 'https://fixture.invalid/first.mkv',
                    title: 'First stream',
                    hasMore: true,
                  ),
                );
                await _until(
                  tester,
                  () => routes.playerRequest != null && !_view(tester).busy,
                );
                await tester.pumpAndSettle();
                final player = routes.playerRequest!;
                expect(player.videoUrl, 'https://fixture.invalid/first.mkv');
                expect(player.title, 'First stream');
                expect(player.requestMagicNext, isNotNull);
                expect(find.byType(CachedLoadingDialog), findsNothing);
                final routeCount = routes.pushes;
                var completed = false;
                final next = player.requestMagicNext!().then((value) {
                  completed = true;
                  return value;
                });
                await _until(tester, () => torbox.queries.length == 4);
                expect(torbox.queries.last, [hit]);
                expect(torbox.prepares, hasLength(1));
                await tester.pump(const Duration(milliseconds: 200));
                expect(completed, isFalse);
                expect(torbox.queries, hasLength(4));
                if (outcome == 'cancel') {
                  cancel();
                  await tester.pump();
                  expect(completed, isFalse);
                  expect(torbox.prepares, hasLength(1));
                  torbox.releases.last.complete(true);
                  if (quick) {
                    await _until(tester, () => completed);
                    expect(await next, isNull);
                    expect(torbox.prepares, hasLength(1));
                    // No public queue accessor: item consumption/dequeue-before-
                    // cancel ordering remains unproven by these wire assertions.
                  } else {
                    await _until(tester, () => torbox.prepares.length == 2);
                    expect(torbox.prepares.last.infohash, hit);
                    expect(completed, isFalse);
                    torbox.nextPrepared.complete(
                      const MagicTvPrepared(
                        streamUrl: 'https://fixture.invalid/late.mkv',
                        title: 'Late cached stream',
                        hasMore: false,
                      ),
                    );
                    await _until(tester, () => completed);
                    expect(await next, {
                      'url': 'https://fixture.invalid/late.mkv',
                      'title': 'Late cached stream',
                    });
                  }
                } else {
                  torbox.releases.last.completeError(
                    Exception('later refill failure'),
                  );
                  await _until(tester, () => completed);
                  expect(await next, isNull);
                  expect(torbox.prepares, hasLength(1));
                  expect(
                    find.textContaining('cache check failed:'),
                    findsOneWidget,
                  );
                  expect(
                    find.textContaining('later refill failure'),
                    findsOneWidget,
                  );
                }
                if (outcome == 'error') {
                  final retry = player.requestMagicNext!();
                  await _until(tester, () => torbox.queries.length == 5);
                  expect(torbox.queries.last, [hit]);
                  expect(torbox.prepares, hasLength(1));
                  torbox.releases.last.complete(false);
                  expect(await retry, isNull);
                }
                expect(await player.requestMagicNext!(), isNull);
                expect(torbox.queries, hasLength(outcome == 'error' ? 5 : 4));
                expect(routes.pushes, routeCount);
                expect(engineRequests, quick ? 5 : 0);
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pumpAndSettle();
              },
              () => MockClient((request) async {
                engineRequests++;
                expect(
                  request.url.origin + request.url.path,
                  'https://origin-success.invalid/search',
                );
                final query = request.url.queryParameters['q']!;
                expect(
                  query,
                  isIn(['keep0', 'keep1', 'keep2', 'keep3', 'keep4']),
                );
                final part = int.parse(query.substring(4));
                return http.Response(
                  jsonEncode({
                    'results': _pool
                        .skip(part * 50)
                        .take(50)
                        .map(
                          (t) => {
                            'infohash': t.infohash,
                            'name': t.name,
                            'seeders': 20,
                            'size_bytes': t.sizeBytes,
                          },
                        )
                        .toList(),
                  }),
                  200,
                );
              }),
            );
          },
        );
      }
    }
  }
}

const _engineYaml = '''
id: origin_success
display_name: Origin Success
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://origin-success.invalid/search
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
field_mappings:
  infohash: infohash
  name: name
  seeders: seeders
  size_bytes: size_bytes
tv_mode:
  enabled_default: true
  limits:
    small: 20
    large: 20
    quick_play: 20
''';

// Exact Flutter3.44.8 origin diagnostic; unfiltered failure retained in evidence.
const _editorPaintDiagnostic =
    'ListTile background color or ink splashes may be invisible.\n'
    'The ListTile is wrapped in a DecoratedBox that has a background color. '
    'Because ListTile paints its background and ink splashes on the nearest '
    'Material ancestor, this DecoratedBox will hide those effects.\n'
    'To fix this, wrap the ListTile in its own Material widget, or remove the '
    'background color from the intermediate DecoratedBox.';
