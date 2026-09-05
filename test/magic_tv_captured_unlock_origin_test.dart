import 'package:debrify/services/storage/provider_credential_prefs.dart';
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

// Captured-unlock live origin: 93eb1e3ec7703caacbe738b3ff75969f34230563.
// Real mounted host callbacks, existing public provider boundary, real storage.
// Actual host route/callback and HTTP credential observation, not native playback.

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
  final pending = Completer<MagicTvLockedBatch?>();
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
    await StorageService.saveDebrifyTvProvider('torbox');
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

  for (final provider in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
    for (final quick in [false, true]) {
      for (final removeKey in [false, true]) {
        testWidgets(
          'origin ${provider.name} ${quick ? "quick" : "cached"} wire retains captured key remove=$removeKey',
          (tester) async {
            final port = _LockedProvider(provider);
            CloudProviderRegistry.instance = CloudProviderRegistry([port]);
            await StorageService.saveDebrifyTvProvider(provider.magicTvId);
            await StorageService.setDefaultPlayerMode('internal');
            await tester.runAsync(_seed);
            final unlocks = <http.Request>[];
            await http.runWithClient(
              () async {
                await _mount(
                  tester,
                  routes,
                  expectedPaintDiagnostics: quick ? 1 : 0,
                );
                await _focus(tester);
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
                    'keep',
                  );
                  await tester.tap(find.text('Play now'));
                } else {
                  _view(tester).onWatch(_view(tester).channels.single);
                }
                await _until(
                  tester,
                  () =>
                      port.requests.length == 1 &&
                      find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
                );
                await tester.pump(const Duration(milliseconds: 300));
                // The real host has already captured its key before this held prepare.
                await tester.runAsync(() async {
                  if (removeKey) {
                    await StorageService.deleteApiKey();
                    await StorageService.deleteAllDebridApiKey();
                    expect(await StorageService.getApiKey(), isNull);
                    expect(await StorageService.getAllDebridApiKey(), isNull);
                  } else {
                    await StorageService.saveApiKey('new-key');
                    await StorageService.saveAllDebridApiKey('new-key');
                    expect(await StorageService.getApiKey(), 'new-key');
                    expect(
                      await StorageService.getAllDebridApiKey(),
                      'new-key',
                    );
                  }
                });
                port.pending.complete(
                  const MagicTvLockedBatch(
                    remoteId: 'remote-1',
                    name: 'pack',
                    lockedLinks: ['https://locked.invalid/file'],
                  ),
                );
                await _until(tester, () => routes.playerRequest != null);
                final launched = routes.playerRequest!;
                expect(
                  launched.videoUrl,
                  'https://fixture.invalid/resolved.mkv',
                );
                expect(launched.title, 'resolved.mkv');
                expect(await launched.requestMagicNext!(), {
                  'url': 'https://fixture.invalid/resolved.mkv',
                  'title': 'resolved.mkv',
                });
                expect(await launched.requestMagicNext!(), {
                  'url': 'https://fixture.invalid/resolved.mkv',
                  'title': 'resolved.mkv',
                });
                expect(await launched.requestMagicNext!(), isNull);
                expect(port.requests, hasLength(3));
                expect(unlocks, hasLength(3));
                expect(
                  unlocks.map((r) => r.headers['Authorization']),
                  everyElement('Bearer captured-key'),
                );
                expect(
                  unlocks.map((r) => r.bodyFields),
                  everyElement({'link': 'https://locked.invalid/file'}),
                );
                await _until(tester, () => !_view(tester).busy);
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pumpAndSettle();
              },
              () => MockClient((request) async {
                if (request.url.host == 'origin-success.invalid') {
                  return http.Response(
                    jsonEncode({
                      'results': _pool
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
                }
                expect(request.method, 'POST');
                expect(
                  request.url.path,
                  provider == CloudProviderId.debrid
                      ? '/rest/1.0/unrestrict/link'
                      : '/v4/link/unlock',
                );
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
  }
  for (final removeKey in [false, true]) {
    testWidgets(
      'origin RD PreferVideos public quality fallback retains captured key remove=$removeKey',
      (tester) async {
        final port = _LockedProvider(CloudProviderId.debrid);
        CloudProviderRegistry.instance = CloudProviderRegistry([port]);
        await StorageService.saveDebrifyTvProvider('debrid');
        await StorageService.setDefaultPlayerMode('internal');
        await StorageService.setDebrifyTvFilterQualities(['ultraHd']);
        await tester.runAsync(_seed);
        final wire = <http.Request>[];
        final add = Completer<http.Response>();
        addTearDown(() {
          if (!add.isCompleted) add.complete(http.Response('failed', 400));
        });
        await http.runWithClient(
          () async {
            await _mount(tester, routes, expectedPaintDiagnostics: 1);
            await _focus(tester);
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
              'keep',
            );
            await tester.tap(find.text('Play now'));
            await _until(tester, () => wire.length == 1);
            expect(
              port.requests,
              isEmpty,
            ); // Strict quality prevented early locked prepare.
            expect(wire.single.url.path, '/rest/1.0/torrents/addMagnet');
            expect(wire.single.bodyFields, {
              'magnet': 'magnet:?xt=urn:btih:${_pool.first.infohash}',
            });
            expect(wire.single.headers['Authorization'], 'Bearer captured-key');
            // Final fallback has captured its key before this held add response.
            await tester.runAsync(() async {
              if (removeKey) {
                await StorageService.deleteApiKey();
              } else {
                await StorageService.saveApiKey('new-key');
              }
              expect(
                await StorageService.getApiKey(),
                removeKey ? isNull : 'new-key',
              );
            });
            expect(wire, hasLength(1));
            add.complete(http.Response(jsonEncode({'id': 'prefer-1'}), 201));
            await _until(tester, () => routes.playerRequest != null);
            final player = routes.playerRequest!;
            expect(player.videoUrl, 'https://fixture.invalid/First%20File.mkv');
            expect(player.title, 'First File.mkv');
            expect(wire.map((r) => r.url.path).toList(), [
              '/rest/1.0/torrents/addMagnet',
              '/rest/1.0/torrents/info/prefer-1',
              '/rest/1.0/torrents/selectFiles/prefer-1',
              '/rest/1.0/torrents/info/prefer-1',
              '/rest/1.0/unrestrict/link',
            ]);
            expect(wire[2].bodyFields, {'files': '1,2'});
            expect(wire[4].bodyFields, {
              'link': 'https://locked.invalid/first',
            });
            expect(await player.requestMagicNext!(), {
              'url': 'https://fixture.invalid/Second%20File.mkv',
              'title': 'Second File.mkv',
            });
            expect(await player.requestMagicNext!(), isNull);
            expect(wire, hasLength(6));
            expect(wire.last.bodyFields, {
              'link': 'https://locked.invalid/second',
            });
            expect(
              wire.map((r) => r.headers['Authorization']),
              everyElement('Bearer captured-key'),
            );
            expect(port.requests, isEmpty);
            await _until(tester, () => !_view(tester).busy);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            if (request.url.host == 'origin-success.invalid') {
              expect(request.url.queryParameters, {'q': 'keep'});
              return http.Response(
                jsonEncode({
                  'results': [
                    {
                      'infohash': _pool.first.infohash,
                      'name': _pool.first.name,
                      'seeders': 20,
                      'size_bytes': 1000000000,
                    },
                  ],
                }),
                200,
              );
            }
            wire.add(request);
            switch (request.url.path) {
              case '/rest/1.0/torrents/addMagnet':
                return add.future;
              case '/rest/1.0/torrents/info/prefer-1':
                expect(request.method, 'GET');
                return http.Response(
                  jsonEncode({
                    'files': [
                      {'id': 1, 'path': '/First File.mkv', 'bytes': 1000000000},
                      {'id': 2, 'name': 'Second File.mkv', 'bytes': 1000000000},
                      {'id': 3, 'name': 'Readme.txt', 'bytes': 200},
                    ],
                    'links': [
                      'https://locked.invalid/first',
                      'https://locked.invalid/second',
                    ],
                  }),
                  200,
                );
              case '/rest/1.0/torrents/selectFiles/prefer-1':
                expect(request.method, 'POST');
                return http.Response('', 204);
              case '/rest/1.0/unrestrict/link':
                expect(request.method, 'POST');
                final first =
                    request.bodyFields['link'] ==
                    'https://locked.invalid/first';
                return http.Response(
                  jsonEncode({
                    'download':
                        'https://fixture.invalid/${first ? 'First' : 'Second'}%20File.mkv',
                    'filesize': 1000000000,
                  }),
                  200,
                );
              default:
                fail(
                  'Unexpected wire request ${request.method} ${request.url}',
                );
            }
          }),
        );
      },
    );
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
