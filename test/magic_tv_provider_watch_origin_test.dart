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
import 'package:debrify/screens/debrify_tv/dialogs/external_player_notice_dialog.dart';
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

// M1-3 live origin: d8e940189e54e6376ad7df69c0ab3efe40a76e5e.
// Real mounted host callbacks, existing public provider boundary, real storage.
// External notice cancellation exercises resolved-stream handoff without a decoder.

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
    await StorageService.setPikPakAccessToken('fixture-access');
    await StorageService.setPikPakRefreshToken('fixture-refresh');
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

  testWidgets(
    'origin TorBox cached stream reaches notice; declining clears busy',
    (tester) async {
      await tester.runAsync(_seed);
      torbox.pending = Completer<MagicTvPrepared?>();
      const prepared = MagicTvPrepared(
        streamUrl: 'https://fixture.invalid/first.mkv',
        title: 'Prepared first',
        hasMore: false,
      );
      await _mount(tester, routes);
      await _focus(tester);
      _view(tester).onWatch(_view(tester).channels.single);
      await _until(
        tester,
        () =>
            torbox.requests.length == 1 &&
            find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      torbox.pending!.complete(prepared);
      await _until(
        tester,
        () => find.byType(ExternalPlayerNoticeDialog).evaluate().isNotEmpty,
      );
      expect(torbox.requests, hasLength(1));
      expect(
        torbox.requests.single.infohash,
        isIn(_pool.map((t) => t.infohash)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CachedLoadingDialog), findsNothing);
      await tester.tap(find.text('Cancel'));
      await _until(tester, () => !_view(tester).busy);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ExternalPlayerNoticeDialog), findsNothing);
      expect(find.byType(DebrifyTVScreen), findsOneWidget);
      expect(torbox.requests, hasLength(1));
      expect(routes.pushes, 3);
      expect(routes.pops, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final provider in [
    CloudProviderId.torbox,
    CloudProviderId.pikpak,
    CloudProviderId.premiumize,
  ]) {
    for (final quick in [false, true]) {
      for (final cancel in [false, true]) {
        testWidgets(
          'origin ${provider.name} ${quick ? "quick" : "cached"} launch and next consume candidates cancel=$cancel',
          (tester) async {
            torbox = _HeldTorbox(provider);
            CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
            await StorageService.saveDebrifyTvProvider(provider.magicTvId);
            await StorageService.setDefaultPlayerMode('internal');
            await tester.runAsync(_seed);
            torbox.pending = Completer<MagicTvPrepared?>();
            const prepared = MagicTvPrepared(
              streamUrl: 'https://fixture.invalid/first.mkv',
              title: 'Prepared first',
              hasMore: false,
            );
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
              await http.runWithClient(
                () async {
                  await tester.tap(find.text('Play now'));
                  await _until(tester, () => torbox.requests.length == 1);
                },
                () => MockClient((request) async {
                  expect(
                    request.url,
                    Uri.parse('https://origin-success.invalid/search?q=keep'),
                  );
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
                }),
              );
            } else {
              _view(tester).onWatch(_view(tester).channels.single);
            }
            await _until(
              tester,
              () =>
                  torbox.requests.length == 1 &&
                  find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
            );
            await tester.pump(const Duration(milliseconds: 300));
            if (cancel) {
              await tester.tap(find.text('Cancel'));
              await _until(tester, () => !_view(tester).busy);
            }
            torbox.pending!.complete(prepared);
            // Origin cached TorBox/Premiumize do not recheck cancellation after prepare.
            if (cancel && (quick || provider == CloudProviderId.pikpak)) {
              await _until(tester, () => !_view(tester).busy);
              await tester.pump(const Duration(seconds: 1));
              expect(routes.playerRequest, isNull);
              expect(torbox.requests, hasLength(1));
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              return;
            }
            await _until(tester, () => routes.playerRequest != null);
            final launched = routes.playerRequest!;
            expect(launched.videoUrl, prepared.streamUrl);
            expect(launched.title, prepared.title);
            expect(launched.channelName, quick ? null : 'Origin News');
            expect(launched.channelNumber, quick ? null : 1);
            expect(launched.requestMagicNext, isNotNull);
            if (cancel) {
              expect(await launched.requestMagicNext!(), isNull);
              expect(torbox.requests, hasLength(1));
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              return;
            }
            expect(await launched.requestMagicNext!(), {
              'url': prepared.streamUrl,
              'title': prepared.title,
              if (provider == CloudProviderId.pikpak) 'provider': 'pikpak',
              if (provider == CloudProviderId.pikpak && quick)
                'pikpakFileId': '',
            });
            expect(await launched.requestMagicNext!(), {
              'url': prepared.streamUrl,
              'title': prepared.title,
              if (provider == CloudProviderId.pikpak) 'provider': 'pikpak',
              if (provider == CloudProviderId.pikpak && quick)
                'pikpakFileId': '',
            });
            expect(await launched.requestMagicNext!(), isNull);
            expect(torbox.requests.map((r) => r.infohash).toSet(), {
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'cccccccccccccccccccccccccccccccccccccccc',
            });
            expect(torbox.requests, hasLength(3));
            await _until(tester, () => !_view(tester).busy);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
  for (final provider in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
    for (final quick in [false, true]) {
      for (final cancel in [false, true]) {
        testWidgets(
          'origin ${provider.name} ${quick ? "quick" : "cached"} next retains captured key cancel=$cancel',
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
                  await StorageService.saveApiKey('new-key');
                  await StorageService.saveAllDebridApiKey('new-key');
                });
                if (cancel) {
                  await tester.tap(find.text('Cancel'));
                  await _until(tester, () => !_view(tester).busy);
                }
                port.pending.complete(
                  const MagicTvLockedBatch(
                    remoteId: 'remote-1',
                    name: 'pack',
                    lockedLinks: ['https://locked.invalid/file'],
                  ),
                );
                if (cancel && quick) {
                  await tester.pump(const Duration(seconds: 1));
                  await _until(tester, () => !_view(tester).busy);
                  expect(routes.playerRequest, isNull);
                  expect(unlocks, isEmpty);
                  expect(port.requests, hasLength(1));
                  await tester.pumpWidget(const SizedBox.shrink());
                  await tester.pumpAndSettle();
                  return;
                }
                await _until(tester, () => routes.playerRequest != null);
                final launched = routes.playerRequest!;
                expect(
                  launched.videoUrl,
                  'https://fixture.invalid/resolved.mkv',
                );
                expect(launched.title, 'resolved.mkv');
                if (cancel) {
                  expect(await launched.requestMagicNext!(), isNull);
                  expect(unlocks, hasLength(1));
                  expect(
                    unlocks.single.headers['Authorization'],
                    'Bearer captured-key',
                  );
                  expect(port.requests, hasLength(1));
                  await tester.pumpWidget(const SizedBox.shrink());
                  await tester.pumpAndSettle();
                  return;
                }
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
