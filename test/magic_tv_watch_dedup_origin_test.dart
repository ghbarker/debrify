import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/magic_tv_screen.dart';
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

// M1-7 origin: 0a56e55fb4e190e1c2514ed0883808b586a3b215.
// Actual mounted host -> user-importable engines -> real parser/search aggregate
// -> public provider preparation boundary. Only external I/O results are faked.
// No private-state access, copied production algorithm, or source behavioral pin.
// Intermediate private queue contents are not independently observable here.
// No native playback, successful stream handoff, cache-window or hasMore claim.
String _hash(int value) => value.toRadixString(16).padLeft(40, '0');

class _Provider extends FakeCloudProvider {
  _Provider(CloudProviderId id)
    : super(id: id, cachedHashes: {_hash(1), _hash(2), _hash(3)});
  final requests = <MagicTvPrepareRequest>[];
  final first = Completer<MagicTvPrepared?>();
  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    requests.add(request);
    if (requests.length == 1) return first.future;
    return null;
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

// Exact inherited Flutter3.44.8 ListTile diagnostic, one per actual Quick Play
// dialog. Unexpected diagnostics always forward to the original test handler.
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
    SecretVault.debugReset(deviceIdOverride: 'm17-origin-fixture');
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('m17-watch-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
    await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
    await StorageService.saveTorboxApiKey('fixture-key');
    await StorageService.setPikPakAccessToken('fixture-access');
    await StorageService.setPikPakRefreshToken('fixture-refresh');
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

  for (final id in [CloudProviderId.torbox, CloudProviderId.pikpak]) {
    for (final phase in ['alpha-first', 'beta-first', 'cancel-held-engine']) {
      testWidgets(
        'origin ${id.name} two-engine $phase preserves duplicate quality and preparation timing',
        (tester) async {
          provider = _Provider(id);
          CloudProviderRegistry.instance = CloudProviderRegistry([provider]);
          await StorageService.saveDebrifyTvProvider(id.magicTvId);
          await tester.runAsync(() async {
            for (final name in ['dedup_one', 'dedup_two']) {
              await LocalEngineStorage.instance.saveEngine(
                engineId: name,
                fileName: '$name.yaml',
                yamlContent: _engine(name),
                displayName: name,
              );
            }
            await EngineRegistry.instance.reload();
          });
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
            expect(diagnostics, [_editorPaintDiagnostic]);
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
          await _drain(tester);
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
            'alpha, beta',
          );
          final requests = <String>[];
          final wires = <String, Completer<http.Response>>{
            for (final engine in ['dedup_one', 'dedup_two'])
              for (final query in ['alpha', 'beta'])
                '$engine/$query': Completer<http.Response>(),
          };
          final rows = <String, List<Map<String, Object>>>{
            'dedup_one/alpha': [_row(1, 'Alpha first 1080p', 10)],
            'dedup_two/alpha': [_row(2, 'Rejected quality 720p', 20)],
            'dedup_one/beta': [_row(1, 'Beta later 1080p', 90)],
            'dedup_two/beta': [_row(3, 'Third match 1080p', 30)],
          };
          void release(String key) => wires[key]!.complete(
            http.Response(
              jsonEncode({'results': rows[key]}),
              200,
              headers: {'content-type': 'application/json'},
            ),
          );
          await http.runWithClient(
            () async {
              await tester.tap(find.text('Play now'));
              await _until(tester, () => requests.length == 4);
              expect(requests.toSet(), wires.keys.toSet());
              expect(_view(tester).busy, isTrue);
              expect(provider.requests, isEmpty);
              final firstQuery = phase == 'beta-first' ? 'beta' : 'alpha';
              final lastQuery = firstQuery == 'alpha' ? 'beta' : 'alpha';
              release('dedup_one/$firstQuery');
              await _drain(tester);
              expect(
                provider.requests,
                isEmpty,
                reason: 'One engine is not a completed keyword search',
              );
              release('dedup_two/$firstQuery');
              await _drain(tester);
              expect(
                provider.requests,
                isEmpty,
                reason: 'Preparation waits for all keyword searches',
              );
              expect(provider.cachedHashesCount, 0);
              if (phase == 'cancel-held-engine') {
                await tester.tap(find.text('Cancel'));
                await _until(tester, () => !_view(tester).busy);
                await _drain(tester);
                expect(find.byType(CachedLoadingDialog), findsNothing);
              }
              release('dedup_one/$lastQuery');
              release('dedup_two/$lastQuery');
              if (phase == 'cancel-held-engine') {
                if (id == CloudProviderId.torbox) {
                  await _until(tester, () => provider.cachedHashesCount == 1);
                  expect(provider.lastCachedHashQuery!.toSet(), {
                    _hash(1),
                    _hash(3),
                  });
                }
                await _drain(tester);
                expect(provider.requests, isEmpty);
                expect(_view(tester).busy, isFalse);
              } else {
                await _until(tester, () => provider.requests.length == 1);
                await _drain(tester);
                expect(
                  provider.requests,
                  hasLength(1),
                  reason: 'Held prepare serializes candidate consumption',
                );
                expect(_view(tester).busy, isTrue);
                provider.first.complete(null);
                await _until(
                  tester,
                  () => provider.requests.length == 2 && !_view(tester).busy,
                );
                expect(provider.requests.map((r) => r.infohash).toSet(), {
                  _hash(1),
                  _hash(3),
                });
                final duplicate = provider.requests.singleWhere(
                  (r) => r.infohash == _hash(1),
                );
                expect(
                  duplicate.torrent.name,
                  firstQuery == 'alpha'
                      ? 'Alpha first 1080p'
                      : 'Beta later 1080p',
                );
                expect(
                  duplicate.torrent.seeders,
                  firstQuery == 'alpha' ? 10 : 90,
                );
                expect(
                  provider.requests,
                  hasLength(2),
                  reason: 'Duplicate prepared once; 720p never prepared',
                );
                if (id == CloudProviderId.torbox) {
                  expect(provider.cachedHashesCount, 1);
                  expect(provider.lastCachedHashQuery!.toSet(), {
                    _hash(1),
                    _hash(3),
                  });
                }
              }
              await _drain(tester);
              expect(find.byType(CachedLoadingDialog), findsNothing);
              expect(find.byType(DebrifyTVScreen), findsOneWidget);
              expect(
                routes.pushes,
                3,
              ); // Host, real Quick Play dialog, loading dialog.
              expect(routes.pops, 2); // No playback route or external launch.
            },
            () => MockClient((request) async {
              expect(request.method, 'GET');
              expect(request.url.path, '/search');
              final key =
                  '${request.url.host.split('.').first}/${request.url.queryParameters['q']}';
              expect(wires, contains(key));
              expect(
                requests,
                isNot(contains(key)),
                reason: 'No duplicate or unexpected I/O',
              );
              requests.add(key);
              return wires[key]!.future;
            }),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
