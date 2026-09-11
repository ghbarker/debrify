import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/settings/browsing_cache_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _storageKey = 'flutter.${BrowsingCachePreferences.key}';

class _Backend extends InMemorySharedPreferencesStore {
  _Backend() : super.withData({});
  final entered = Completer<void>.sync();
  final release = Completer<void>.sync();
  final attempts = <Object>[];
  bool holdFirst = false;
  String firstOutcome = 'ok';

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final first = attempts.isEmpty;
    attempts.add(value);
    if (first) {
      entered.complete();
      if (holdFirst) await release.future;
      if (firstOutcome == 'false') return false;
      if (firstOutcome == 'throw') throw StateError('injected write failure');
    }
    return super.setValue(type, key, value);
  }
}

Future<void> _mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: BrowsingCachePage()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Backend backend;
  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    backend = _Backend();
    SharedPreferencesStorePlatform.instance = backend;
    BrowsingCachePreferences.resetForTesting();
    PlatformUtil.debugSetAndroidTvCached(true);
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    BrowsingCachePreferences.resetForTesting();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    PlatformUtil.debugSetAndroidTvCached(null);
  });

  for (final outcome in ['false', 'throw']) {
    test(
      '$outcome write does not publish or survive a cold reload; retry works',
      () async {
        backend.firstOutcome = outcome;
        await BrowsingCachePreferences.initialize();
        var notifications = 0;
        void onChanged() => notifications++;
        BrowsingCachePreferences.notifier.addListener(onChanged);
        addTearDown(
          () => BrowsingCachePreferences.notifier.removeListener(onChanged),
        );
        const selected = BrowsingCacheOptions(
          rememberTitles: true,
          artworkSizeMb: 128,
        );
        await expectLater(
          BrowsingCachePreferences.update(selected),
          throwsStateError,
        );
        expect(notifications, 0);
        expect(
          BrowsingCachePreferences.current.toJson(),
          const BrowsingCacheOptions().toJson(),
        );
        expect((await backend.getAll())[_storageKey], isNull);
        // Reset the plugin cache too: this models a process restart, not just a
        // controller reload from SharedPreferences' optimistic in-memory cache.
        SharedPreferences.resetStatic();
        BrowsingCachePreferences.resetForTesting();
        await BrowsingCachePreferences.initialize();
        expect(BrowsingCachePreferences.current.rememberTitles, isFalse);
        await BrowsingCachePreferences.update(selected);
        expect(
          jsonDecode((await backend.getAll())[_storageKey] as String),
          selected.toJson(),
        );
        expect(BrowsingCachePreferences.current.toJson(), selected.toJson());
      },
    );

    testWidgets('$outcome save shows an accessible error and allows retry', (
      tester,
    ) async {
      backend.firstOutcome = outcome;
      await _mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(BrowsingCachePreferences.current.rememberTitles, isFalse);
      final error = find.text('Could not save. Please try again.');
      expect(error, findsOneWidget);
      expect(
        tester
            .widgetList<Semantics>(
              find.ancestor(of: error, matching: find.byType(Semantics)),
            )
            .any((s) => s.properties.liveRegion == true),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(BrowsingCachePreferences.current.rememberTitles, isTrue);
      expect(error, findsNothing);
    });

    testWidgets('queued changes continue after a delayed $outcome write', (
      tester,
    ) async {
      backend.holdFirst = true;
      backend.firstOutcome = outcome;
      await _mount(tester);
      await tester.tap(find.byType(SettingsTile).at(0));
      await tester.pump();
      await tester.tap(find.byType(SettingsTile).at(4));
      backend.release.complete();
      await tester.pumpAndSettle();
      expect(BrowsingCachePreferences.current.rememberTitles, isFalse);
      expect(BrowsingCachePreferences.current.prefetchMovieStreams, isFalse);
      expect(backend.attempts.length, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rapid changes to separate rows survive a delayed save', (
    tester,
  ) async {
    backend.holdFirst = true;
    await _mount(tester);
    await tester.tap(find.byType(SettingsTile).at(0));
    await tester.pump();
    expect(backend.entered.isCompleted, isTrue);
    await tester.tap(find.byType(SettingsTile).at(2));
    await tester.tap(find.byType(SettingsTile).at(4));
    await tester.pump();
    expect(backend.attempts.length, 1);
    backend.release.complete();
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.rememberTitles, isTrue);
    expect(BrowsingCachePreferences.current.expandedArtwork, isTrue);
    expect(BrowsingCachePreferences.current.prefetchMovieStreams, isFalse);
    expect(
      jsonDecode((await backend.getAll())[_storageKey] as String),
      BrowsingCachePreferences.current.toJson(),
    );
  });

  test(
    'delayed preference writes serialize and publish only acknowledged values',
    () async {
      backend.holdFirst = true;
      await BrowsingCachePreferences.initialize();
      final first = BrowsingCachePreferences.update(
        const BrowsingCacheOptions(artworkSizeMb: 128),
      );
      await backend.entered.future.timeout(const Duration(seconds: 5));
      final last = BrowsingCachePreferences.update(
        const BrowsingCacheOptions(artworkSizeMb: 2048),
      );
      try {
        await Future<void>.delayed(Duration.zero);
        expect(backend.attempts.length, 1);
        expect(BrowsingCachePreferences.current.artworkSizeMb, 512);
      } finally {
        backend.release.complete();
        await Future.wait([first, last]);
      }
      SharedPreferences.resetStatic();
      BrowsingCachePreferences.resetForTesting();
      await BrowsingCachePreferences.initialize();
      expect(BrowsingCachePreferences.current.artworkSizeMb, 2048);
    },
  );

  testWidgets('two rapid activations apply two toggles after delayed storage', (
    tester,
  ) async {
    backend.holdFirst = true;
    await _mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    backend.release.complete();
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.rememberTitles, isFalse);
    expect(backend.attempts.length, 2);
  });

  testWidgets('queued user changes finish safely after the page is disposed', (
    tester,
  ) async {
    backend.holdFirst = true;
    await _mount(tester);
    await tester.tap(find.byType(SettingsTile).at(0));
    await tester.pump();
    await tester.tap(find.byType(SettingsTile).at(4));
    await tester.pumpWidget(const SizedBox.shrink());
    backend.release.complete();
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.rememberTitles, isTrue);
    expect(BrowsingCachePreferences.current.prefetchMovieStreams, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DPAD skips disabled storage rows in both directions', (
    tester,
  ) async {
    await _mount(tester);
    final rows = tester
        .widgetList<SettingsTile>(find.byType(SettingsTile))
        .toList();
    expect(rows[0].focusNode!.hasFocus, isTrue);
    for (final index in [2, 4]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(rows[index].focusNode!.hasFocus, isTrue);
    }
    for (final index in [2, 0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(rows[index].focusNode!.hasFocus, isTrue);
    }
  });

  testWidgets('reopening the page preserves changes still being saved', (
    tester,
  ) async {
    backend.holdFirst = true;
    await _mount(tester);
    await tester.tap(find.byType(SettingsTile).at(0));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: BrowsingCachePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SettingsTile).at(4));
    await tester.pump();
    backend.release.complete();
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.rememberTitles, isTrue);
    expect(BrowsingCachePreferences.current.prefetchMovieStreams, isFalse);
  });

  for (final raw in <Object>[
    true,
    7,
    ['not-json'],
    'null',
    '{"rememberTitles":"true","expandedArtwork":1,"prefetchMovieStreams":"false","titleSizeMb":null,"artworkSizeMb":{}}',
  ]) {
    test(
      'invalid stored value $raw falls back without rewriting storage',
      () async {
        backend = _Backend();
        SharedPreferencesStorePlatform.instance =
            InMemorySharedPreferencesStore.withData({_storageKey: raw});
        await BrowsingCachePreferences.initialize();
        expect(
          BrowsingCachePreferences.current.toJson(),
          const BrowsingCacheOptions().toJson(),
        );
        expect(
          (await SharedPreferencesStorePlatform.instance.getAll())[_storageKey],
          raw,
        );
      },
    );
  }

  test('device options are excluded from transfers and sync scheduling', () {
    final portable = ProfilePreferencePortability.prepareValue(
      BrowsingCachePreferences.key,
      jsonEncode(const BrowsingCacheOptions().toJson()),
    );
    expect(portable.include, isFalse);
    expect(portable.value, isNull);
    expect(
      WebDavSyncScheduler.admitsLocalChangeKey(BrowsingCachePreferences.key),
      isFalse,
    );
    expect(
      WebDavSyncScheduler.admitsLocalChangeKey('subtitle_font_size'),
      isTrue,
    );
  });
}
