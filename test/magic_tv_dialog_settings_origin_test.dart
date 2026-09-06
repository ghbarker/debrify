import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/screens/debrify_tv/widgets/random_start_slider.dart';
import 'dart:io';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_layout.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/magic_tv_provider.dart';
import 'package:debrify/screens/debrify_tv/widgets/spotlight_choice_chip.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_cloud_provider.dart';

// M1-5 real-origin characterization at 397398d5, before extraction.
// Host callbacks and real storage execute; fixtures control external results.
// Scope: desktop editor outcomes and immediate/reset preference writes. No TV
// focus, successful new-channel warming, quick-scope or native claims.
// Reset first-two-write reversal fails the serial first-write assertion.
// Pending-keyword ==/!= mutation survives both comma-entry and existing-keyword
// probes: those returned-value cases do not establish sensitivity of that guard.
// Flutter 3.44.8 requires the exact ListTile diagnostic/count handling below;
// an unfiltered origin run fails. Unexpected diagnostics are forwarded to fail.

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
  DebrifyTvChannel? savedChannel;
  int pushes = 0;
  int pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    route.popped.then((value) {
      if (value is DebrifyTvChannel) savedChannel = value;
    });
  }

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
    // Reproduced on untouched M1-5 origin production with Flutter 3.44.8.
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

// M1-5 actual origin 397398d5. Only real host entry callbacks are used.
// Quick settings scope has no current card caller and is not claimed covered.
// Host TV detection uses AndroidNativeDownloader and is false on desktop;
// PlatformUtil's cached TV override cannot prove TV host focus/launcher paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  final persisted = <String, Object>{};
  final writes = <(String, String, Object)>[];
  String? heldKey;
  Completer<void>? heldWrite;
  late SharedPreferences prefs;
  late Directory root;
  late _Routes routes;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, (call) async {
          if (call.method == 'getAll') {
            return Map<String, Object>.from(persisted);
          }
          if (call.method == 'clear') {
            persisted.clear();
            return true;
          }
          final args = call.arguments as Map;
          final key = args['key'] as String;
          if (call.method == 'remove') {
            persisted.remove(key);
            return true;
          }
          if (call.method.startsWith('set')) {
            final value = args['value'] as Object;
            writes.add((call.method, key.substring('flutter.'.length), value));
            if (key == heldKey) await heldWrite!.future;
            persisted[key] = value;
            return true;
          }
          throw StateError('Unexpected prefs method ${call.method}');
        });
    prefs = await SharedPreferences.getInstance();
  });
  setUp(() async {
    persisted.clear();
    writes.clear();
    heldKey = null;
    heldWrite = null;
    await prefs.reload();
    PlatformUtil.debugSetAndroidTvCached(false);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'm15-origin-fixture');
    StorageService.resetProfileCaches();
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.tvKeyboardEnabledCached = false;
    root = await Directory('.dart_tool').absolute.createTemp('m15-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
    await StorageService.saveTorboxApiKey('fixture-key');
    await DebrifyTvPrefs.saveDebrifyTvProvider('torbox');
    CloudProviderRegistry.instance = CloudProviderRegistry([_HeldTorbox()]);
    routes = _Routes();
  });
  tearDown(() async {
    if (heldWrite != null && !heldWrite!.isCompleted) heldWrite!.complete();
    PlatformUtil.debugSetAndroidTvCached(null);
    CloudProviderRegistry.debugReset();
    await DebrifyTvDatabase.instance.debugResetScopeState();
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    StorageService.resetProfileCaches();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
  });
  tearDownAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, null),
  );

  Future<void> openEditor(WidgetTester tester, {bool edit = false}) async {
    if (edit) {
      await _focus(tester);
      _view(tester).onEdit(_view(tester).channels.single);
    } else {
      _view(tester).onAdd();
    }
    await _until(tester, () => find.text('Save channel').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> close(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.byType(DebrifyTvSpotlightDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> settings(WidgetTester tester) async {
    _view(tester).onSettings();
    await _until(
      tester,
      () => find.text('Channel playback').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('origin new editor cancel leaves storage untouched desktop', (
    tester,
  ) async {
    await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
    await openEditor(tester);
    final fields = _editorFields;
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'Discarded');
    await tester.enterText(fields.last, 'Alpha, alpha');
    await close(tester, 'Cancel');
    expect(
      await tester.runAsync(
        () => DebrifyTvRepository.instance.fetchAllChannels(),
      ),
      isEmpty,
    );
  });

  testWidgets('origin edit cancel preserves keywords and NSFW', (tester) async {
    await tester.runAsync(_seed);
    await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
    await openEditor(tester, edit: true);
    await tester.enterText(_editorFields.first, 'Discarded edit');
    tester.widget<SwitchRow>(find.byType(SwitchRow)).onChanged(false);
    await tester.pump();
    await close(tester, 'Cancel');
    final records = await tester.runAsync(
      () => DebrifyTvRepository.instance.fetchAllChannels(),
    );
    expect(records!.single.name, 'Origin News');
    expect(records.single.keywords, ['Keep', 'Drop']);
    expect(records.single.avoidNsfw, isTrue);
  });
  testWidgets('origin editor validates name and keywords before persistence', (
    tester,
  ) async {
    await _mount(tester, routes, expectedEditorPaintDiagnostics: 3);
    await openEditor(tester);
    await tester.tap(find.text('Save channel'));
    await tester.pump();
    expect(find.text('Give the channel a name'), findsOneWidget);
    await tester.enterText(_editorFields.first, 'Named');
    await tester.tap(find.text('Save channel'));
    await tester.pump();
    expect(find.text('Add at least one keyword'), findsOneWidget);
    await close(tester, 'Cancel');
    expect(
      await tester.runAsync(
        () => DebrifyTvRepository.instance.fetchAllChannels(),
      ),
      isEmpty,
    );
  });
  testWidgets(
    'origin comma keyword entry returns trimmed first-spelling dedup',
    (tester) async {
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await openEditor(tester);
      await tester.enterText(_editorFields.first, '  Origin saved  ');
      await tester.enterText(_editorFields.last, 'Alpha, alpha, Beta');
      await tester.tap(find.text('Save channel'));
      await _until(tester, () => routes.savedChannel != null);
      expect(routes.savedChannel!.name, 'Origin saved');
      expect(routes.savedChannel!.keywords, ['Alpha', 'Beta']);
      expect(routes.savedChannel!.avoidNsfw, isTrue);
      // Empty engine fixture rejects persistence downstream; pin the editor's
      // actual returned value, not a successful channel warm/save claim.
      await _until(tester, () => routes.pops >= 2);
      expect(
        await tester.runAsync(
          () => DebrifyTvRepository.instance.fetchAllChannels(),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'origin existing keyword and pending case variant retain first spelling',
    (tester) async {
      await tester.runAsync(_seed);
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 1);
      await openEditor(tester, edit: true);
      await tester.enterText(_editorFields.last, 'KEEP');
      await tester.tap(find.text('Save channel'));
      await _until(tester, () => routes.savedChannel != null);
      expect(routes.savedChannel!.id, 'fixture');
      expect(routes.savedChannel!.keywords, ['Keep', 'Drop']);
      await _until(
        tester,
        () =>
            !_view(tester).busy &&
            find.byType(DebrifyTvSpotlightDialog).evaluate().isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'origin keyword Enter add dedups existing case, removes chip and rejects keyword 1001',
    (tester) async {
      await tester.runAsync(_seed);
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 6);
      await openEditor(tester, edit: true);
      await tester.enterText(_editorFields.last, 'KEEP');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Keywords (2/1000)'), findsOneWidget);
      expect(
        tester.widget<EditableText>(_editorFields.last).controller.text,
        isEmpty,
      );
      await tester.tap(find.text('Drop').last);
      await tester.pump();
      expect(find.text('Keywords (1/1000)'), findsOneWidget);
      await tester.enterText(_editorFields.last, 'Added');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Keywords (2/1000)'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      // Comma-entry is the other actual UI entry to the same Add helper.
      await tester.enterText(
        _editorFields.last,
        List.generate(998, (i) => 'K$i').join(','),
      );
      await tester.pump();
      expect(find.text('Keywords (1000/1000)'), findsOneWidget);
      expect(
        find.text('You can add up to 1000 keywords per channel.'),
        findsOneWidget,
      );
      await tester.ensureVisible(_editorFields.last);
      await tester.enterText(_editorFields.last, 'Rejected1001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Keywords (1000/1000)'), findsOneWidget);
      expect(find.text('Rejected1001'), findsNothing);
      expect(
        find.text('You can add up to 1000 keywords per channel.'),
        findsOneWidget,
      );
      await close(tester, 'Cancel');
      final stored = await tester.runAsync(
        () => DebrifyTvRepository.instance.fetchAllChannels(),
      );
      expect(stored!.single.keywords, ['Keep', 'Drop']);
    },
  );
  testWidgets(
    'origin setting writes immediately before Done and rebuilds locally',
    (tester) async {
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await settings(tester);
      writes.clear();
      heldKey = 'flutter.debrify_tv_start_random';
      heldWrite = Completer<void>();
      final row = tester.widget<SwitchRow>(find.byType(SwitchRow));
      row.onChanged(false);
      await tester.pump();
      await _until(tester, () => writes.isNotEmpty);
      expect(tester.widget<SwitchRow>(find.byType(SwitchRow)).value, isFalse);
      expect(persisted.containsKey('flutter.debrify_tv_start_random'), isFalse);
      heldWrite!.complete();
      await _until(
        tester,
        () => persisted['flutter.debrify_tv_start_random'] == false,
      );
      expect(tester.widget<SwitchRow>(find.byType(SwitchRow)).value, isFalse);
      expect(find.byType(RandomStartSlider), findsNothing);
      expect(writes, [('setBool', 'debrify_tv_start_random', false)]);
      await close(tester, 'Done');
      expect(persisted['flutter.debrify_tv_start_random'], isFalse);
    },
  );
  testWidgets(
    'origin reset writes filters then defaults serially and keeps percent storage quirk',
    (tester) async {
      await DebrifyTvPrefs.saveDebrifyTvRandomStartPercent(65);
      await DebrifyTvPrefs.saveDebrifyTvStartRandom(false);
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await settings(tester);
      writes.clear();
      heldKey = 'flutter.debrify_tv_filter_qualities';
      heldWrite = Completer<void>();
      final button = tester.widget<DebrifyTvDialogButton>(
        find.widgetWithText(DebrifyTvDialogButton, 'Reset to defaults'),
      );
      button.onPressed!();
      await tester.pump();
      await _until(tester, () => writes.isNotEmpty);
      expect(writes, [('setString', 'debrify_tv_filter_qualities', '[]')]);
      expect(tester.widget<SwitchRow>(find.byType(SwitchRow)).value, isTrue);
      expect(
        tester.widget<RandomStartSlider>(find.byType(RandomStartSlider)).value,
        20,
      );
      heldWrite!.complete();
      await _until(tester, () => writes.length == 7);
      expect(writes, [
        ('setString', 'debrify_tv_filter_qualities', '[]'),
        ('setString', 'debrify_tv_filter_sizes', '[]'),
        ('setBool', 'debrify_tv_start_random', true),
        ('setBool', 'debrify_tv_hide_seekbar', true),
        ('setBool', 'debrify_tv_show_watermark', true),
        ('setBool', 'debrify_tv_show_video_title', true),
        ('setString', 'debrify_tv_provider', 'torbox'),
      ]);
      expect(persisted['flutter.debrify_tv_random_start_percent'], 65);
      await close(tester, 'Done');
    },
  );
  testWidgets(
    'origin selected and unavailable providers do not write preferences',
    (tester) async {
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 1);
      await settings(tester);
      writes.clear();
      await tester.tap(find.byTooltip('Use Torbox for Debrify TV'));
      await tester.pump();
      await tester.tap(
        find.byTooltip('Enable Real Debrid and add an API key in Settings.'),
      );
      await tester.pump();
      expect(writes, isEmpty);
      expect(persisted['flutter.debrify_tv_provider'], 'torbox');
      await close(tester, 'Done');
    },
  );
  // M1-5b origin c35c41c1; actual load and Reset paths, no private host access.
  testWidgets(
    'origin load keeps percent and normalizes seekbar before held write completes',
    (tester) async {
      await DebrifyTvPrefs.saveDebrifyTvRandomStartPercent(65);
      await DebrifyTvPrefs.saveDebrifyTvHideSeekbar(true);
      await prefs.setString('debrify_tv_provider', 'unknown-origin-provider');
      writes.clear();
      heldKey = 'flutter.debrify_tv_hide_seekbar';
      heldWrite = Completer<void>();
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 1);
      await _until(tester, () => writes.length >= 2);
      expect(writes, [
        ('setBool', 'debrify_tv_hide_seekbar', false),
        ('setString', 'debrify_tv_provider', 'torbox'),
      ]);
      expect(persisted['flutter.debrify_tv_hide_seekbar'], isTrue);
      expect(persisted['flutter.debrify_tv_provider'], 'torbox');
      await settings(tester);
      expect(tester.widget<SwitchRow>(find.byType(SwitchRow)).value, isTrue);
      expect(
        tester.widget<RandomStartSlider>(find.byType(RandomStartSlider)).value,
        65,
      );
      heldWrite!.complete();
      await _until(
        tester,
        () => persisted['flutter.debrify_tv_hide_seekbar'] == false,
      );
      await close(tester, 'Done');
      expect(persisted['flutter.debrify_tv_random_start_percent'], 65);
    },
  );

  testWidgets(
    'origin Reset ignores preferred Torbox and chooses available Real Debrid',
    (tester) async {
      await tester.runAsync(() => StorageService.saveApiKey('origin-rd-key'));
      await _mount(tester, routes, expectedEditorPaintDiagnostics: 2);
      await settings(tester);
      final torbox = find.byWidgetPredicate(
        (w) => w is SpotlightChoiceChip && w.label == 'Torbox',
      );
      expect(tester.widget<SpotlightChoiceChip>(torbox).selected, isTrue);
      writes.clear();
      tester
          .widget<DebrifyTvDialogButton>(
            find.widgetWithText(DebrifyTvDialogButton, 'Reset to defaults'),
          )
          .onPressed!();
      await _until(tester, () => writes.length == 7);
      expect(writes.last, ('setString', 'debrify_tv_provider', 'real_debrid'));
      final rd = find.byWidgetPredicate(
        (w) => w is SpotlightChoiceChip && w.label == 'Real Debrid',
      );
      expect(tester.widget<SpotlightChoiceChip>(rd).selected, isTrue);
      await close(tester, 'Done');
      expect(persisted['flutter.debrify_tv_provider'], 'real_debrid');
    },
  );

  test(
    'origin provider helpers preserve all availability masks and Real Debrid fallback',
    () {
      const ids = [
        CloudProviderId.debrid,
        CloudProviderId.torbox,
        CloudProviderId.premiumize,
        CloudProviderId.alldebrid,
        CloudProviderId.pikpak,
      ];
      const names = [
        'real_debrid',
        'torbox',
        'premiumize',
        'alldebrid',
        'pikpak',
      ];
      for (var mask = 0; mask < 32; mask++) {
        final flags = List.generate(5, (i) => (mask & (1 << i)) != 0);
        final available = MagicTvProvider.availability(
          realDebrid: flags[0],
          torbox: flags[1],
          premiumize: flags[2],
          allDebrid: flags[3],
          pikpak: flags[4],
        );
        for (var i = 0; i < ids.length; i++) {
          expect(
            MagicTvDispatch.isSelectable(
              names[i],
              realDebrid: flags[0],
              torbox: flags[1],
              premiumize: flags[2],
              allDebrid: flags[3],
              pikpak: flags[4],
            ),
            flags[i],
          );
          expect(available[ids[i]], flags[i]);
        }
        for (final unknown in ['', 'unknown', 'debrid', 'rd', 'Torbox']) {
          expect(MagicTvDispatch.watchId(unknown), CloudProviderId.debrid);
          expect(
            MagicTvDispatch.isSelectable(
              unknown,
              realDebrid: flags[0],
              torbox: flags[1],
              premiumize: flags[2],
              allDebrid: flags[3],
              pikpak: flags[4],
            ),
            flags[0],
          );
        }
        final first = flags.indexOf(true);
        expect(
          MagicTvProvider.pickDefault(preferred: null, available: available),
          first < 0 ? 'real_debrid' : names[first],
        );
        for (var i = 0; i < ids.length; i++) {
          if (flags[i]) {
            expect(
              MagicTvProvider.pickDefault(
                preferred: names[i],
                available: available,
              ),
              names[i],
            );
          }
        }
      }
    },
  );
}
