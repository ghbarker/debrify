import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
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

// Actual unchanged origin 0f9a84d60ff6bfc36c99adfd3ce3728c65745275.
// Mounted public Home-style view callback returns the original host Future;
// only the provider transport is held. No copied flow or private host state.
// RD catches preparation errors; AD propagates them while mounted. The cached
// finally-return suppresses pending errors after disposal. No quirk is fixed.
const _editorPaintDiagnostic =
    'ListTile background color or ink splashes may be invisible.\n'
    'The ListTile is wrapped in a DecoratedBox that has a background color. '
    'Because ListTile paints its background and ink splashes on the nearest '
    'Material ancestor, this DecoratedBox will hide those effects.\n'
    'To fix this, wrap the ListTile in its own Material widget, or remove the '
    'background color from the intermediate DecoratedBox.';

const _hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Provider extends FakeCloudProvider {
  _Provider(CloudProviderId id)
    : super(id: id, cacheFlags: [true], cachedHashes: {_hash});
  final requests = <MagicTvPrepareRequest>[];
  final pending = Completer<MagicTvLockedBatch?>();
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
  VideoPlayerScreen? player;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    if (route is FrozenLegacyPageRoute) {
      final context = navigator!.context;
      final boundary = route.builder(context) as LegacyThemeBoundary;
      player =
          (boundary.child as Builder).builder(context) as VideoPlayerScreen;
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
      deviceIdOverride: 'm17-cached-locked-origin-fixture',
    );
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('m17-cached-locked-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
    await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
    await StorageService.saveApiKey('fixture-key');
    await StorageService.saveAllDebridApiKey('fixture-key');
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

  for (final id in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
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
        expect(
          await completion,
          dispose || id == CloudProviderId.debrid ? isNull : same(failure),
        );
        await _drain(tester);
        expect(provider.requests, hasLength(1));
        expect(find.byType(CachedLoadingDialog), findsNothing);
        if (!dispose && id == CloudProviderId.debrid) {
          expect(find.byType(SnackBar), findsOneWidget);
          expect(
            find.text(
              'No cached torrents played successfully. Try refreshing the channel.',
            ),
            findsOneWidget,
          );
        } else {
          expect(find.byType(SnackBar), findsNothing);
        }
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
  for (final id in [CloudProviderId.debrid, CloudProviderId.alldebrid]) {
    for (final options in [false, true]) {
      testWidgets(
        'origin ${id.name} cached ${options ? "global options and eligibility after public provider selection" : "rejected head retains playable sibling without reprepare"}',
        (tester) async {
          provider = _Provider(id);
          CloudProviderRegistry.instance = CloudProviderRegistry([provider]);
          await StorageService.saveDebrifyTvProvider(id.magicTvId);
          if (options) {
            await StorageService.saveDebrifyTvStartRandom(false);
            await StorageService.saveDebrifyTvRandomStartPercent(37);
            await StorageService.saveDebrifyTvShowChannelName(false);
            await StorageService.saveDebrifyTvShowVideoTitle(false);
            await StorageService.saveDebrifyTvHideSeekbar(true);
            await StorageService.saveDebrifyTvHideOptions(true);
          }
          await tester.runAsync(() async {
            await _seed();
            if (options) {
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
            }
          });
          // Pinned SDK3.44.8 unfiltered origin emits exactly2 RD /1 AD settings
          // ListTile diagnostics (RD selection rebuilds, AD already selected).
          // No surrounding viewport/theme can insert Material inside that tile.
          final diagnostics = <String>[];
          final originalError = FlutterError.onError!;
          FlutterError.onError = (details) {
            if (details.exception is FlutterError &&
                details.exceptionAsString() == _editorPaintDiagnostic) {
              diagnostics.add(details.exceptionAsString());
            } else {
              originalError(details);
            }
          };
          addTearDown(() {
            FlutterError.onError = originalError;
            expect(
              diagnostics,
              List.filled(
                options ? (id == CloudProviderId.debrid ? 2 : 1) : 0,
                _editorPaintDiagnostic,
              ),
            );
          });
          final wire = <http.Request>[];
          await http.runWithClient(
            () async {
              tester.view.physicalSize = const Size(1280, 1200);
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
              await _until(
                tester,
                () => _view(tester).channels.length == (options ? 2 : 1),
              );
              await _drain(tester);
              final view = _view(tester);
              final watch =
                  view.onWatch as Future<void> Function(DebrifyTvChannel);
              var completed = false;
              final completion =
                  watch(view.channels.singleWhere((c) => c.id == 'fixture'))
                      .then<Object?>(
                        (_) => null,
                        onError: (Object error, StackTrace stack) => error,
                      )
                      .whenComplete(() => completed = true);
              await _until(tester, () => provider.requests.length == 1);
              expect(find.byType(CachedLoadingDialog), findsOneWidget);
              expect(wire, isEmpty);
              expect(completed, isFalse);
              if (options) {
                // The original cached walkers accept late completion after cancellation.
                // Change the provider through the real public settings UI while held;
                // this makes the two live-builder eligibility dialects observable.
                await tester.pump(const Duration(milliseconds: 300));
                await tester.tap(find.text('Cancel'));
                await _until(tester, () => !_view(tester).busy);
                _view(tester).onSettings();
                await tester.pumpAndSettle();
                await tester.ensureVisible(find.text('AllDebrid').last);
                await tester.tap(find.text('AllDebrid').last);
                await tester.pumpAndSettle();
                expect(
                  await StorageService.getDebrifyTvProvider(),
                  'alldebrid',
                );
                await tester.tap(find.text('Done'));
                await tester.pumpAndSettle();
                expect(completed, isFalse);
              }
              provider.pending.complete(
                MagicTvLockedBatch(
                  remoteId: 'remote-pack',
                  name: 'pack',
                  lockedLinks: options
                      ? ['https://locked.invalid/only']
                      : [
                          'https://locked.invalid/first',
                          'https://locked.invalid/second',
                        ],
                ),
              );
              await _until(tester, () => routes.player != null);
              final player = routes.player!;
              expect(player.videoUrl, 'https://fixture.invalid/playable.mkv');
              expect(player.title, 'playable.mkv');
              expect(provider.requests, hasLength(1));
              expect(provider.requests.single.infohash, _hash);
              expect(wire, hasLength(options ? 1 : 2));
              expect(wire.map((r) => r.method), everyElement('POST'));
              expect(
                wire.map((r) => r.url.path),
                everyElement(
                  id == CloudProviderId.debrid
                      ? '/rest/1.0/unrestrict/link'
                      : '/v4/link/unlock',
                ),
              );
              expect(
                wire.map((r) => r.headers['Authorization']),
                everyElement('Bearer fixture-key'),
              );
              if (!options) {
                expect(wire.map((r) => r.bodyFields['link']).toSet(), {
                  'https://locked.invalid/first',
                  'https://locked.invalid/second',
                });
                if (id == CloudProviderId.alldebrid) {
                  expect(wire.map((r) => r.bodyFields['link']).toList(), [
                    'https://locked.invalid/first',
                    'https://locked.invalid/second',
                  ]);
                } // RD shuffles, so reject the first actual request regardless of link.
              } else {
                expect(player.startFromRandom, isFalse);
                expect(player.randomStartMaxPercent, 37);
                expect(player.showChannelName, isFalse);
                expect(player.showVideoTitle, isFalse);
                expect(
                  player.hideSeekbar,
                  isFalse,
                ); // Origin ignores storedtrue.
                expect(player.hideOptions, isFalse); // Origin hardcodedfalse.
                expect(player.channelName, 'Cached origin');
                expect(player.channelNumber, 1);
                expect(player.channelDirectory, [
                  {
                    'id': 'fixture',
                    'name': 'Cached origin',
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
                expect(
                  player.requestNextChannel,
                  id == CloudProviderId.debrid ? isNull : isNotNull,
                );
                expect(player.requestChannelById, isNotNull);
              }
              await _until(tester, () => completed);
              expect(await completion, isNull);
              expect(_view(tester).busy, isFalse);
              expect(find.byType(CachedLoadingDialog), findsNothing);
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
            },
            () => MockClient((request) async {
              wire.add(request);
              if (!options &&
                  wire.length == 1 &&
                  id == CloudProviderId.alldebrid) {
                return http.Response(
                  jsonEncode({
                    'status': 'error',
                    'error': {
                      'code': 'LINK_DOWN',
                      'message': 'fixture head unavailable',
                    },
                  }),
                  400,
                );
              }
              return http.Response(
                jsonEncode(
                  id == CloudProviderId.debrid
                      ? {
                          'download': !options && wire.length == 1
                              ? 'https://fixture.invalid/sample.mkv'
                              : 'https://fixture.invalid/playable.mkv',
                          'filesize': !options && wire.length == 1
                              ? 1
                              : 1000000000,
                        }
                      : {
                          'status': 'success',
                          'data': {
                            'link': 'https://fixture.invalid/playable.mkv',
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
