import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Actual public origin ec5377aa661f5ba5d5c5d84d8ce21e2271fa1cf1.
// Eleven simple prefs bodies/48 lines; no native/DeoVR launch proof.
final _cases =
    <
      ({
        String key,
        Object fallback,
        Object value,
        Future<Object> Function() read,
        Future<void> Function(Object) write,
      })
    >[
      (
        key: 'quick_play_vr_mode',
        fallback: 'disabled',
        value: 'auto',
        read: StorageService.getQuickPlayVrMode,
        write: (v) => StorageService.setQuickPlayVrMode(v as String),
      ),
      (
        key: 'quick_play_vr_default_screen_type',
        fallback: 'dome',
        value: 'fisheye',
        read: StorageService.getQuickPlayVrDefaultScreenType,
        write: (v) =>
            StorageService.setQuickPlayVrDefaultScreenType(v as String),
      ),
      (
        key: 'quick_play_vr_default_stereo_mode',
        fallback: 'sbs',
        value: 'tb',
        read: StorageService.getQuickPlayVrDefaultStereoMode,
        write: (v) =>
            StorageService.setQuickPlayVrDefaultStereoMode(v as String),
      ),
      (
        key: 'quick_play_vr_auto_detect_format',
        fallback: true,
        value: false,
        read: StorageService.getQuickPlayVrAutoDetectFormat,
        write: (v) => StorageService.setQuickPlayVrAutoDetectFormat(v as bool),
      ),
      (
        key: 'quick_play_vr_show_dialog',
        fallback: true,
        value: false,
        read: StorageService.getQuickPlayVrShowDialog,
        write: (v) => StorageService.setQuickPlayVrShowDialog(v as bool),
      ),
    ];

class _Observed extends InMemorySharedPreferencesStore {
  _Observed(super.data) : super.withData();
  final attempts = <String>[];
  int? failAt;
  int? falseAt;
  int? holdAt;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<bool> record(String key, Future<bool> Function() commit) async {
    attempts.add(key);
    final index = attempts.length - 1;
    if (index == holdAt) {
      entered.complete();
      await release.future;
    }
    if (index == failAt) throw StateError('synthetic transport failure');
    if (index == falseAt) return false;
    return commit();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      record(key, () => super.setValue(type, key, value));
  @override
  Future<bool> remove(String key) => record(key, () => super.remove(key));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Observed backend;
  final a = ProfileScope(
    profileId: 'vr-origin-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'vr-origin-b',
    dataGeneration: 2,
    sessionEpoch: 2,
  );
  const sentinels = <String, Object>{
    'default_player_mode': 'external',
    'external_player_preferred': 'synthetic-player',
    'quick_play_movie_rules_v2': '{"synthetic":"untouched"}',
    'series_auto_pin_on_play': false,
    'quick_play_search_timeout': 41,
    'vr_origin_sentinel': 'untouched',
  };
  Future<void> install({bool committed = false, bool populated = false}) async {
    SharedPreferences.resetStatic();
    final values = {
      ...sentinels,
      if (populated)
        for (final c in _cases) c.key: c.value,
    };
    backend = _Observed({
      if (!committed)
        for (final e in values.entries) 'flutter.${e.key}': e.value,
      if (committed)
        for (final scope in [a, b])
          for (final e in values.entries)
            'flutter.${scope.preferenceKey(e.key)}': e.value,
    });
    SharedPreferencesStorePlatform.instance = backend;
    if (committed) ProfileRuntime.initializeCommitted(a);
  }

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await install();
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });
  for (final c in _cases) {
    test(
      '${c.key}: defaults, physical roundtrip and no read persistence',
      () async {
        expect(await c.read(), c.fallback);
        expect(backend.attempts, isEmpty);
        await c.write(c.value);
        expect(await c.read(), c.value);
        expect((await SharedPreferences.getInstance()).get(c.key), c.value);
        expect((await backend.getAll())['flutter.${c.key}'], c.value);
        expect(backend.attempts, ['flutter.${c.key}']);
      },
    );
    test(
      '${c.key}: wrong physical type throws rather than defaulting',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(c.key, 17);
        await expectLater(c.read(), throwsA(isA<TypeError>()));
        expect(prefs.get(c.key), 17);
      },
    );
    if (c.value is String) {
      test(
        '${c.key}: empty and unknown strings are not validated or normalized',
        () async {
          for (final value in ['', ' FUTURE-VR-value ']) {
            await c.write(value);
            expect(await c.read(), value);
            expect(
              (await SharedPreferences.getInstance()).getString(c.key),
              value,
            );
          }
        },
      );
    }
    for (final throws in [false, true]) {
      test(
        '${c.key}: ${throws ? 'thrown' : 'false'} transport keeps real SDK cached write',
        () async {
          if (throws) {
            backend.failAt = 0;
          } else {
            backend.falseAt = 0;
          }
          if (throws) {
            await expectLater(c.write(c.value), throwsStateError);
          } else {
            await c.write(c.value);
          }
          expect(await c.read(), c.value);
          expect(
            (await backend.getAll()).containsKey('flutter.${c.key}'),
            false,
          );
          expect(backend.attempts, ['flutter.${c.key}']);
        },
      );
    }
    test(
      '${c.key}: held write remains on captured profile after session switch',
      () async {
        await install(committed: true);
        backend.holdAt = 0;
        final work = c.write(c.value);
        await backend.entered.future;
        expect(
          (await backend.getAll()).containsKey(
            'flutter.${a.preferenceKey(c.key)}',
          ),
          false,
        );
        ProfileRuntime.initializeCommitted(b);
        backend.release.complete();
        await work;
        final raw = await backend.getAll();
        expect(raw['flutter.${a.preferenceKey(c.key)}'], c.value);
        expect(raw.containsKey('flutter.${b.preferenceKey(c.key)}'), false);
        expect(await c.read(), c.fallback);
      },
    );
  }
  final keys = _cases.map((c) => c.key).toList();
  for (var failure = 0; failure <= 5; failure++) {
    test('clear prefix $failure keeps all non-VR preferences', () async {
      await install(populated: true);
      backend.failAt = failure < 5 ? failure : null;
      if (failure < 5) {
        await expectLater(
          StorageService.clearQuickPlayVrSettings(),
          throwsStateError,
        );
      } else {
        await StorageService.clearQuickPlayVrSettings();
      }
      expect(
        backend.attempts,
        keys.take(failure < 5 ? failure + 1 : 5).map((k) => 'flutter.$k'),
      );
      final raw = await backend.getAll();
      for (var i = 0; i < keys.length; i++) {
        expect(raw.containsKey('flutter.${keys[i]}'), i >= failure);
      }
      for (final e in sentinels.entries) {
        expect(raw['flutter.${e.key}'], e.value);
      }
      if (failure == 5) {
        for (final c in _cases) {
          expect(await c.read(), c.fallback);
        }
      }
    });
  }
  test('clear false removal is ignored and later keys removed', () async {
    await install(populated: true);
    backend.falseAt = 0;
    await StorageService.clearQuickPlayVrSettings();
    expect(backend.attempts, keys.map((k) => 'flutter.$k'));
    final raw = await backend.getAll();
    expect(raw['flutter.${keys.first}'], _cases.first.value);
    for (final key in keys.skip(1)) {
      expect(raw.containsKey('flutter.$key'), false);
    }
    expect(await _cases.first.read(), _cases.first.fallback);
  });
  test(
    'clear captures preferences once and stops after held removal changes session',
    () async {
      await install(committed: true, populated: true);
      backend.holdAt = 0;
      final work = StorageService.clearQuickPlayVrSettings();
      final failure = expectLater(work, throwsStateError);
      await backend.entered.future;
      ProfileRuntime.initializeCommitted(b);
      backend.release.complete();
      await failure;
      expect(backend.attempts, ['flutter.${a.preferenceKey(keys.first)}']);
      final raw = await backend.getAll();
      for (final c in _cases) {
        expect(raw['flutter.${b.preferenceKey(c.key)}'], c.value);
      }
      expect(raw.containsKey('flutter.${a.preferenceKey(keys.first)}'), false);
      for (final c in _cases.skip(1)) {
        expect(raw['flutter.${a.preferenceKey(c.key)}'], c.value);
      }
    },
  );
}
