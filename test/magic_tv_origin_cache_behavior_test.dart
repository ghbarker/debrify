import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/channel_creation_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
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

// RETROSPECTIVE live-origin evidence, not retroactive pin-before-move compliance.
// Run these same bytes with Flutter 3.44.8 on:
// M1-0 parent efb9fc529264ce490a870b574b542721c907dbb4;
// M1-1 parent b1060b1e01c25dbcb0336f6bf9e70b661da9b7a1;
// current base 0d4ca1a2b3026e67eb21247719590c60df5e106d.
// Every callback comes from a mounted, real DebrifyTVScreen State. The fixture
// provider controls external results only. No extracted-class imports, source
// guards, dynamic private access, or copied production logic are used.
// Unproven: private session field defaults/identity, queue clearing independently
// of the cancellation flag, and progress sanitization;
// multi-engine/page-limit and concurrent batch boundaries; large playback sampling;
// multi-window TorBox limits; RD size relaxation; native/player/prefetch success.

class _HeldTorbox extends FakeCloudProvider {
  _HeldTorbox()
    : super(id: CloudProviderId.torbox, cachedHashes: {'keep', 'both', 'drop'});

  Completer<MagicTvPrepared?>? pending;
  final requests = <MagicTvPrepareRequest>[];

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    requests.add(request);
    return pending?.future;
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

Finder get _editorFields => find.descendant(
  of: find.byType(DebrifyTvSpotlightDialog),
  matching: find.byType(EditableText),
);

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
  _torrent('keep', ['keep'], 'Kept.1080p.mkv'),
  _torrent('both', ['keep', 'drop'], 'Shared.720p.mkv'),
  _torrent('drop', ['drop'], 'Removed.1080p.mkv'),
];

// A user-importable engine; only its wire response is supplied by the fixture.
// Production still constructs requests, parses results and warms/merges cache.
const _successEngineYaml = '''
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

String _hash(int id) => id.toRadixString(16).padLeft(40, '0');

Map<String, Object> _engineRow(int id, {int seeders = 10}) => {
  'infohash': _hash(id),
  'name': 'Origin $id seeders $seeders 1080p',
  'seeders': seeders,
  'size_bytes': 1000000000,
};

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

const _editorPaintDiagnostic =
    'ListTile background color or ink splashes may be invisible.\n'
    'The ListTile is wrapped in a DecoratedBox that has a background color. '
    'Because ListTile paints its background and ink splashes on the nearest '
    'Material ancestor, this DecoratedBox will hide those effects.\n'
    'To fix this, wrap the ListTile in its own Material widget, or remove the '
    'background color from the intermediate DecoratedBox.';

Future<void> _mount(
  WidgetTester tester,
  _Routes routes, {
  int expectedEditorPaintDiagnostics = 0,
}) async {
  final paintDiagnostics = <String>[];
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    // Reproduced on both untouched production parents with Flutter 3.44.8.
    // The editor's tappable ListTile sits inside its own colored DecoratedBox;
    // a surrounding theme/Scaffold/viewport cannot insert Material between them.
    // Assert the full diagnostic AND its per-scenario count, never blanket-ignore.
    if (details.exception is FlutterError &&
        details.exceptionAsString() == _editorPaintDiagnostic) {
      paintDiagnostics.add(details.exceptionAsString());
      return;
    }
    reportError(details);
  };
  addTearDown(() {
    FlutterError.onError = reportError;
    expect(
      paintDiagnostics,
      List.filled(expectedEditorPaintDiagnostics, _editorPaintDiagnostic),
      reason: 'Only the exact reproduced editor paint diagnostics are expected',
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

Future<void> _edit(WidgetTester tester) async {
  _view(tester).onEdit(_view(tester).channels.single);
  await _until(tester, () => find.text('Edit channel').evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _save(WidgetTester tester, String message) async {
  await tester.tap(find.text('Save channel'));
  await _until(tester, () => find.text(message).evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ChannelCreationDialog), findsNothing);
  expect(find.byType(DebrifyTVScreen), findsOneWidget);
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
    await StorageService.saveTorboxApiKey('fixture-key');
    await StorageService.saveDebrifyTvProvider('torbox');
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
    'retrospective origin: focused stats reflect persisted pool and dead keywords',
    (tester) async {
      await tester.runAsync(_seed);
      await _mount(tester, routes);
      await _focus(tester);
      expect(_view(tester).busy, isFalse);
      expect(_view(tester).channels.single.keywords, ['Keep', 'Drop']);
      final stats = _view(tester).stats!;
      expect(stats.pooled, 3);
      expect(stats.atYourQuality, 3);
      expect(stats.qualityMix, [0, 2, 1]);
      expect(stats.deadKeywords, ['drop']);
      expect(stats.keywordYield, {'keep': 2, 'drop': 0});
      expect(stats.sample.map((t) => t.infohash).toSet(), {
        'keep',
        'both',
        'drop',
      });
      expect(torbox.requests, isEmpty);
    },
  );

  testWidgets(
    'retrospective origin: unchanged-keyword edit reuses memory before newer disk cache',
    (tester) async {
      final baseline = await tester.runAsync(_seed);
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 1);
      await _focus(tester); // Actual State has now loaded its memory cache.
      await tester.runAsync(
        () => DebrifyTvCacheService.saveEntry(
          baseline!.copyWith(torrents: [_pool.last]),
        ),
      );
      await _edit(tester);
      await tester.enterText(_editorFields.first, 'Renamed News');
      await _save(tester, 'Channel "Renamed News" updated');
      final stored = await tester.runAsync(
        () => DebrifyTvCacheService.getEntry('fixture'),
      );
      expect(stored!.torrents.map((t) => t.infohash).toSet(), {
        'keep',
        'both',
        'drop',
      });
      expect(stored.fetchedAt, 123);
      expect(stored.errorMessage, 'Baseline diagnostic');
      expect(torbox.requests, isEmpty);
    },
  );

  testWidgets(
    'retrospective origin: remove keyword drops mixed-tag torrents and closes progress',
    (tester) async {
      await tester.runAsync(_seed);
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await _focus(tester);
      await _edit(tester);
      await tester.tap(find.text('Drop'));
      await _save(tester, 'Channel "Origin News" updated');
      final stored = await tester.runAsync(
        () => DebrifyTvCacheService.getEntry('fixture'),
      );
      expect(stored!.normalizedKeywords, ['keep']);
      expect(stored.torrents.map((t) => t.infohash), ['keep']);
      expect(stored.keywordStats.keys, ['keep']);
      expect(stored.errorMessage, isNull);
      expect(stored.status, DebrifyTvCacheStatus.ready);
      expect(
        routes.pushes,
        3,
      ); // Screen, editor, actual warming progress route.
      expect(routes.pops, 2);
      expect(_view(tester).busy, isFalse);
    },
  );

  testWidgets(
    'retrospective origin: prune-to-empty edit restores complete baseline',
    (tester) async {
      await tester.runAsync(() => _seed(keepOnlyTorrent: false));
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await _focus(tester);
      await _edit(tester);
      await tester.tap(find.text('Drop'));
      await _save(tester, 'Baseline diagnostic');
      final stored = await tester.runAsync(
        () => DebrifyTvCacheService.getEntry('fixture'),
      );
      expect(stored!.normalizedKeywords, ['keep', 'drop']);
      expect(stored.torrents.map((t) => t.infohash).toSet(), {'both', 'drop'});
      expect(stored.status, DebrifyTvCacheStatus.ready);
      expect(stored.errorMessage, 'Baseline diagnostic');
      final records = await tester.runAsync(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      expect(records!.single.keywords, ['Keep', 'Drop']);
      expect(routes.pushes, 3);
      expect(routes.pops, 2);
    },
  );

  testWidgets(
    'retrospective origin: added-keyword failed warm preserves seeded successes',
    (tester) async {
      await tester.runAsync(_seed);
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await _focus(tester);
      await _edit(tester);
      await tester.enterText(_editorFields.last, ' New, NEW, ');
      await _save(tester, 'Channel "Origin News" updated');
      final stored = await tester.runAsync(
        () => DebrifyTvCacheService.getEntry('fixture'),
      );
      expect(stored!.normalizedKeywords, ['keep', 'drop', 'new']);
      expect(stored.torrents.map((t) => t.infohash).toSet(), {
        'keep',
        'both',
        'drop',
      });
      expect(stored.keywordStats['new']!.totalFetched, 0);
      expect(stored.keywordStats['keep']!.totalFetched, 2);
      expect(stored.status, DebrifyTvCacheStatus.ready);
      expect(routes.pushes, 3);
      expect(routes.pops, 2);
    },
  );

  testWidgets(
    'retrospective origin: full warm with no engines fails without creating a channel',
    (tester) async {
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      _view(tester).onAdd();
      await _until(
        tester,
        () => find.text('Create a channel').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(_editorFields.first, 'Uncached');
      await tester.enterText(_editorFields.last, ' Fresh, fresh, ');
      await tester.tap(find.text('Save channel'));
      await _until(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_view(tester).channels, isEmpty);
      expect(
        await tester.runAsync(DebrifyTvRepository.instance.fetchAllChannels),
        isEmpty,
      );
      expect(
        await tester.runAsync(DebrifyTvCacheService.loadAllEntries),
        isEmpty,
      );
      expect(find.byType(ChannelCreationDialog), findsNothing);
      expect(find.byType(DebrifyTVScreen), findsOneWidget);
      expect(routes.pushes, 3);
      expect(routes.pops, 2);
    },
  );

  testWidgets(
    'retrospective origin: successful engine warm merges hashes and accepts five but rejects four',
    (tester) async {
      await tester.runAsync(() async {
        await LocalEngineStorage.instance.saveEngine(
          engineId: 'origin_success',
          fileName: 'origin_success.yaml',
          yamlContent: _successEngineYaml,
          displayName: 'Origin Success',
        );
        await EngineRegistry.instance.reload();
      });
      final responses = {
        'alpha': [for (var id = 1; id <= 5; id++) _engineRow(id)],
        'beta': [
          _engineRow(1, seeders: 80),
          for (var id = 6; id <= 9; id++) _engineRow(id),
        ],
        'thin': [for (var id = 10; id <= 13; id++) _engineRow(id)],
      };
      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
          _view(tester).onAdd();
          await _until(
            tester,
            () => find.text('Create a channel').evaluate().isNotEmpty,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.enterText(_editorFields.first, 'Successful Origin');
          await tester.enterText(_editorFields.last, ' Alpha, Beta, Thin, ');
          await _save(tester, 'Channel "Successful Origin" saved');
        },
        () => MockClient((request) async {
          requests.add(request.url);
          expect(request.method, 'GET');
          expect(request.url.host, 'origin-success.invalid');
          final rows = responses[request.url.queryParameters['q']];
          expect(rows, isNotNull, reason: 'Unexpected engine query');
          return http.Response(
            jsonEncode({'results': rows}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(
        requests,
        unorderedEquals([
          Uri.parse('https://origin-success.invalid/search?q=alpha'),
          Uri.parse('https://origin-success.invalid/search?q=beta'),
          Uri.parse('https://origin-success.invalid/search?q=thin'),
        ]),
      );
      final records = await tester.runAsync(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      expect(records, hasLength(1));
      expect(records!.single.keywords, ['Alpha', 'Beta', 'Thin']);
      final stored = await tester.runAsync(
        () => DebrifyTvCacheService.getEntry(records.single.channelId),
      );
      expect(stored!.status, DebrifyTvCacheStatus.ready);
      expect(stored.errorMessage, isNull);
      expect(stored.normalizedKeywords, ['alpha', 'beta', 'thin']);
      expect(stored.torrents.map((t) => t.infohash).toSet(), {
        for (var id = 1; id <= 9; id++) _hash(id),
      });
      expect(stored.torrents, hasLength(9));
      final merged = stored.torrents.singleWhere((t) => t.infohash == _hash(1));
      expect(merged.keywords.toSet(), {'alpha', 'beta'});
      expect(merged.sources, ['origin_success']);
      expect(merged.seeders, 80);
      expect(merged.name, 'Origin 1 seeders 80 1080p');
      expect(stored.keywordStats['alpha']!.totalFetched, 5);
      expect(stored.keywordStats['beta']!.totalFetched, 5);
      expect(stored.keywordStats['thin']!.totalFetched, 0);
      expect(stored.keywordStats.values.map((s) => s.pagesPulled), [1, 1, 1]);
      expect(routes.pushes, 3);
      expect(routes.pops, 2);
      expect(_view(tester).busy, isFalse);
      expect(torbox.requests, isEmpty);
    },
  );

  testWidgets(
    'retrospective origin: cancel clears busy and loading route and stops cached queue consumption',
    (tester) async {
      await tester.runAsync(_seed);
      torbox.pending = Completer<MagicTvPrepared?>();
      await _mount(tester, routes);
      await _focus(tester);
      _view(tester).onWatch(_view(tester).channels.single);
      await _until(
        tester,
        () =>
            torbox.requests.length == 1 &&
            find.byType(CachedLoadingDialog).evaluate().isNotEmpty,
      );
      expect(_view(tester).busy, isTrue);
      expect(torbox.lastCachedHashQuery!.toSet(), {'keep', 'both', 'drop'});
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_view(tester).busy, isFalse);
      expect(find.byType(CachedLoadingDialog), findsNothing);
      torbox.pending!.complete(
        null,
      ); // Complete provider miss AFTER cancellation.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(torbox.requests, hasLength(1)); // No post-cancel tail consumption.
      expect(_view(tester).busy, isFalse);
      expect(find.byType(DebrifyTVScreen), findsOneWidget);
      expect(routes.pushes, 2);
      expect(routes.pops, 1);
    },
  );

  testWidgets(
    'retrospective origin: empty quality match falls back at cache read',
    (tester) async {
      await tester.runAsync(_seed);
      await StorageService.setDebrifyTvFilterQualities(['ultraHd']);
      await _mount(tester, routes);
      await _focus(tester);
      expect(_view(tester).stats!.atYourQuality, 0);
      _view(tester).onWatch(_view(tester).channels.single);
      await _until(
        tester,
        () => torbox.requests.length == 3 && !_view(tester).busy,
      );
      expect(torbox.lastCachedHashQuery!.toSet(), {'keep', 'both', 'drop'});
      expect(torbox.requests.map((r) => r.infohash).toSet(), {
        'keep',
        'both',
        'drop',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CachedLoadingDialog), findsNothing);
      final stored = await tester.runAsync(
        () => DebrifyTvCacheService.getEntry('fixture'),
      );
      expect(
        stored!.torrents,
        hasLength(3),
      ); // Quality filtering never rewrites warm data.
    },
  );
}
