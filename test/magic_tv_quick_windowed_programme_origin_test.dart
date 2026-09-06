import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/screens/debrify_tv/widgets/random_start_slider.dart';
import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_layout.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
import 'package:debrify/services/debrify_tv_database.dart';
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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_cloud_provider.dart';

// Actual unchanged origin ec5377aa661f5ba5d5c5d84d8ce21e2271fa1cf1.
// Real mounted host/engine/provider transport. Captures actual public Play now
// async callback to observe thrown preparation errors. Presentation inspects the
// outgoing builder and removes its route; no native playback or device claim.
// Held-prepare settings use the actual mounted view callback, not a physical tap
// through the loading modal. No private host access or copied application logic.
String _hash(int value) => value.toRadixString(16).padLeft(40, '0');

class _Provider extends FakeCloudProvider {
  _Provider(CloudProviderId id)
    : super(id: id, cacheFlags: [true], cachedHashes: {_hash(1)});
  final requests = <MagicTvPrepareRequest>[];
  final first = Completer<MagicTvPrepared?>();
  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    requests.add(request);
    return first.future;
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

String _engine(String id) =>
    '''id: $id
display_name: $id
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://$id.invalid/search
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

Map<String, Object> _row(int id, String name, int seeders) => {
  'infohash': _hash(id),
  'name': name,
  'seeders': seeders,
  'size_bytes': 1000000000,
};

// Exact inherited Flutter3.44.8 diagnostic: one for Quick Play, three total
// when settings are opened/changed during held prepare. Unexpected errors fail.
const _editorPaintDiagnostic =
    'ListTile background color or ink splashes may be invisible.\n'
    'The ListTile is wrapped in a DecoratedBox that has a background color. '
    'Because ListTile paints its background and ink splashes on the nearest '
    'Material ancestor, this DecoratedBox will hide those effects.\n'
    'To fix this, wrap the ListTile in its own Material widget, or remove the '
    'background color from the intermediate DecoratedBox.';

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
      deviceIdOverride: 'm17-quick-programme-origin-fixture',
    );
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('m17-quick-programme-origin-');
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
    if (!provider.first.isCompleted) provider.first.complete(null);
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
    for (final outcome in ['throw', 'null', 'one-channel', 'two-channels']) {
      testWidgets('origin ${id.name} quick programme $outcome', (tester) async {
        provider = _Provider(id);
        CloudProviderRegistry.instance = CloudProviderRegistry([provider]);
        await StorageService.saveDebrifyTvProvider(id.magicTvId);
        await StorageService.saveDebrifyTvStartRandom(true);
        await StorageService.saveDebrifyTvRandomStartPercent(65);
        await StorageService.saveDebrifyTvShowChannelName(false);
        await StorageService.saveDebrifyTvShowVideoTitle(false);
        await StorageService.saveDebrifyTvHideSeekbar(true);
        await StorageService.saveDebrifyTvHideOptions(true);
        final presentation =
            outcome.endsWith('channel') || outcome == 'two-channels';
        final channelCount = outcome == 'two-channels' ? 2 : 1;
        await tester.runAsync(() async {
          await LocalEngineStorage.instance.saveEngine(
            engineId: 'programme',
            fileName: 'programme.yaml',
            yamlContent: _engine('programme'),
            displayName: 'Programme',
          );
          await EngineRegistry.instance.reload();
          for (var i = 0; i < channelCount; i++) {
            final now = DateTime.utc(2026, 9, 5);
            await DebrifyTvRepository.instance.upsertChannel(
              DebrifyTvChannelRecord(
                channelId: 'channel-$i',
                name: 'Channel $i',
                keywords: ['keep'],
                avoidNsfw: true,
                channelNumber: i + 1,
                createdAt: now,
                updatedAt: now,
              ),
            );
          }
        });
        final diagnostics = <String>[];
        final original = FlutterError.onError!;
        const unfiltered = bool.fromEnvironment('PROGRAMME_UNFILTERED');
        FlutterError.onError = (details) {
          if (!unfiltered &&
              details.exception is FlutterError &&
              details.exceptionAsString() == _editorPaintDiagnostic) {
            diagnostics.add(details.exceptionAsString());
          } else {
            original(details);
          }
        };
        addTearDown(() {
          FlutterError.onError = original;
          if (!unfiltered) {
            expect(
              diagnostics,
              List.filled(presentation ? 3 : 1, _editorPaintDiagnostic),
            );
          }
        });
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
        await _until(
          tester,
          () => _view(tester).channels.length == channelCount,
        );
        await _drain(tester);
        _view(tester).onQuickPlay();
        await _until(tester, () => find.text('Play now').evaluate().isNotEmpty);
        await tester.enterText(
          find.descendant(
            of: find.byType(DebrifyTvSpotlightDialog),
            matching: find.byType(TextField),
          ),
          'keep',
        );
        final engineRequests = <Uri>[];
        final failure = StateError('origin prepare failure');
        await http.runWithClient(
          () async {
            final play = tester.widget<DebrifyTvDialogButton>(
              find.widgetWithText(DebrifyTvDialogButton, 'Play now'),
            );
            // This is the real widget's async closure, retaining its returned error.
            final action = play.onPressed! as Future<void> Function();
            final completion = action().then<Object?>(
              (_) => null,
              onError: (Object error, StackTrace stack) => error,
            );
            await _until(tester, () => provider.requests.length == 1);
            expect(engineRequests, [
              Uri.parse('https://programme.invalid/search?q=keep'),
            ]);
            expect(provider.requests.single.infohash, _hash(1));
            expect(_view(tester).busy, isTrue);
            expect(find.byType(CachedLoadingDialog), findsOneWidget);
            expect(routes.player, isNull);
            if (presentation) {
              // Quick options were copied at Play now. Change the live GLOBAL
              // state through its existing settings callback while prepare is held.
              _view(tester).onSettings();
              await _until(
                tester,
                () => find.text('Channel playback').evaluate().isNotEmpty,
              );
              await tester.pump(const Duration(milliseconds: 400));
              final slider = tester.widget<RandomStartSlider>(
                find.byType(RandomStartSlider),
              );
              expect(slider.value, 65);
              slider.onChanged(37);
              tester.widget<SwitchRow>(find.byType(SwitchRow)).onChanged(false);
              await tester.pump();
              expect(
                tester.widget<SwitchRow>(find.byType(SwitchRow)).value,
                isFalse,
              );
              expect(provider.requests, hasLength(1));
              await tester.tap(find.text('Done'));
              await tester.pump(const Duration(milliseconds: 400));
              provider.first.complete(
                const MagicTvPrepared(
                  streamUrl: 'https://fixture.invalid/programme.mkv',
                  title: 'Prepared programme',
                  hasMore: false,
                ),
              );
              await _until(tester, () => routes.player != null);
              final player = routes.player!;
              expect(player.videoUrl, 'https://fixture.invalid/programme.mkv');
              expect(player.title, 'Prepared programme');
              expect(
                player.startFromRandom,
                isFalse,
              ); // Quick snapshot remains true.
              expect(
                player.randomStartMaxPercent,
                37,
              ); // Quick snapshot remains 65.
              expect(player.showChannelName, isFalse);
              expect(player.showVideoTitle, isFalse);
              expect(
                player.hideSeekbar,
                isFalse,
              ); // Origin load hardcodes false.
              expect(player.hideOptions, isFalse);
              expect(player.channelName, isNull);
              expect(player.channelNumber, isNull);
              expect(player.channelDirectory, isNull);
              expect(player.requestMagicNext, isNotNull);
              expect(
                player.requestNextChannel,
                channelCount == 2 ? isNotNull : isNull,
              );
            } else if (outcome == 'throw') {
              provider.first.completeError(failure);
            } else {
              provider.first.complete(null);
            }
            await _until(tester, () => !_view(tester).busy);
            expect(
              await completion,
              outcome == 'throw' ? same(failure) : isNull,
            );
            await _drain(tester);
            expect(find.byType(CachedLoadingDialog), findsNothing);
            expect(provider.requests, hasLength(1));
            final label = id == CloudProviderId.torbox
                ? 'Torbox'
                : 'Premiumize';
            if (outcome == 'null') {
              expect(
                find.text(
                  'No playable $label streams found. Try different keywords.',
                ),
                findsOneWidget,
              );
            } else if (outcome == 'throw') {
              expect(find.byType(SnackBar), findsNothing);
              expect(find.textContaining('cache check failed'), findsNothing);
            }
            if (!presentation) {
              expect(routes.player, isNull);
              expect(routes.pushes, 3);
              expect(routes.pops, 2);
            }
          },
          () => MockClient((request) async {
            engineRequests.add(request.url);
            return http.Response(
              jsonEncode({
                'results': [_row(1, 'Programme 1080p', 20)],
              }),
              200,
            );
          }),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
