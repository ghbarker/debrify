import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Actual public origin cb261b5b; identical 19+5 bodies at 6d26d7a.
// Finite preference transport, not actual tvOS keyboard or native launch proof.
const _enabled = 'tv_keyboard_enabled';
const _generation = 'tvos_keyboard_default_generation';
const _limit = Duration(seconds: 5);

class _KeyboardBackend extends InMemorySharedPreferencesStore {
  _KeyboardBackend(super.data) : super.withData();
  final writes = <(String, Object)>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic keyboard persistence failure');
  int holdWrite = 0;
  bool holdRead = false;
  String outcome = 'ok';

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (holdRead) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    if (writes.length == holdWrite) {
      entered.complete();
      await release.future.timeout(_limit);
      if (outcome == 'throw') throw failure;
      if (outcome == 'false') return false;
    }
    return super.setValue(type, key, value);
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _KeyboardBackend backend;
  late bool previousCache;
  final a = ProfileScope(
    profileId: 'keyboard-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'keyboard-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final otherGeneration = ProfileScope(
    profileId: 'keyboard-a',
    dataGeneration: 2,
    sessionEpoch: 3,
  );

  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    backend = _KeyboardBackend({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.keyboard_sentinel': 'unchanged',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  void profiles() {
    install({
      _enabled: true,
      for (final scope in [a, b, otherGeneration])
        scope.preferenceKey(_enabled): scope != b,
      for (final scope in [b, otherGeneration])
        scope.preferenceKey(_generation): 1,
    });
    ProfileRuntime.initializeCommitted(a);
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    previousCache = StorageService.tvKeyboardEnabledCached;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install({_enabled: true});
    StorageService.tvKeyboardEnabledCached = true;
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    StorageService.tvKeyboardEnabledCached = previousCache;
    ProfileRuntime.debugReset();
  });

  test(
    'legacy explicit true is overwritten once; later user choice survives',
    () async {
      expect(await StorageService.getTvKeyboardEnabled(tvOs: true), isFalse);
      expect(backend.writes, [
        ('flutter.$_enabled', false),
        ('flutter.$_generation', 1),
      ]);
      expect(await StorageService.getTvKeyboardEnabled(tvOs: true), isFalse);
      expect(backend.writes.length, 2);
      await StorageService.setTvKeyboardEnabled(true);
      expect(await StorageService.getTvKeyboardEnabled(tvOs: true), isTrue);
      expect(backend.writes.length, 3);
    },
  );

  for (final tvOs in [false, true]) {
    test('absent value defaults with explicit tvOs=$tvOs', () async {
      install({});
      expect(await StorageService.getTvKeyboardEnabled(tvOs: tvOs), !tvOs);
      expect(StorageService.tvKeyboardEnabledCached, !tvOs);
      expect(backend.writes.length, tvOs ? 2 : 0);
    });
  }

  for (final generation in [-1, 0, 1, 2]) {
    test(
      'generation $generation preserves threshold and repeated read order',
      () async {
        install({_enabled: true, _generation: generation});
        expect(
          await StorageService.getTvKeyboardEnabled(tvOs: true),
          generation >= 1,
        );
        expect(
          await StorageService.getTvKeyboardEnabled(tvOs: true),
          generation >= 1,
        );
        expect(backend.writes.length, generation < 1 ? 2 : 0);
      },
    );
  }

  for (final raw in <Object>[
    '1',
    true,
    1.0,
    <String>['1'],
  ]) {
    test('generation raw ${raw.runtimeType} throws even off tvOS', () async {
      install({_enabled: true, _generation: raw});
      await expectLater(
        StorageService.getTvKeyboardEnabled(tvOs: false),
        throwsA(isA<TypeError>()),
      );
      expect(backend.writes, isEmpty);
      expect(StorageService.tvKeyboardEnabledCached, isTrue);
    });
  }

  test(
    'wrong bool throws after committed generation, but legacy migration overwrites it',
    () async {
      install({_enabled: 'true', _generation: 1});
      await expectLater(
        StorageService.getTvKeyboardEnabled(tvOs: true),
        throwsA(isA<TypeError>()),
      );
      expect(backend.writes, isEmpty);
      install({_enabled: 'true'});
      expect(await StorageService.getTvKeyboardEnabled(tvOs: true), isFalse);
      expect(backend.writes, [
        ('flutter.$_enabled', false),
        ('flutter.$_generation', 1),
      ]);
    },
  );

  for (final held in [1, 2]) {
    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        'migration held write $held/$outcome preserves SDK/cache/durable ordering',
        () async {
          final prefs = await SharedPreferences.getInstance();
          backend.holdWrite = held;
          backend.outcome = outcome;
          final result = StorageService.getTvKeyboardEnabled(tvOs: true);
          final observed = expectLater(
            result,
            outcome == 'throw'
                ? throwsA(same(backend.failure))
                : completion(isFalse),
          );
          await backend.entered.future.timeout(_limit);
          expect(StorageService.tvKeyboardEnabledCached, isTrue);
          expect(prefs.getBool(_enabled), isFalse);
          expect(prefs.getInt(_generation), held == 2 ? 1 : null);
          expect(backend.writes, [
            ('flutter.$_enabled', false),
            if (held == 2) ('flutter.$_generation', 1),
          ]);
          final before = await backend.durable();
          expect(before['flutter.$_enabled'], held == 1);
          expect(before.containsKey('flutter.$_generation'), isFalse);
          backend.release.complete();
          await observed;
          expect(StorageService.tvKeyboardEnabledCached, outcome == 'throw');
          final after = await backend.durable();
          expect(after['flutter.$_enabled'], held == 1 && outcome != 'ok');
          expect(after['flutter.$_generation'], outcome == 'ok' ? 1 : null);
          expect(backend.writes.length, held == 1 && outcome != 'ok' ? 1 : 2);
          expect(after['flutter.keyboard_sentinel'], 'unchanged');
        },
      );
    }
  }

  for (final outcome in ['ok', 'false', 'throw']) {
    test('setter held $outcome updates mirror only after completion', () async {
      install({_enabled: false, _generation: 1});
      StorageService.tvKeyboardEnabledCached = false;
      final prefs = await SharedPreferences.getInstance();
      backend.holdWrite = 1;
      backend.outcome = outcome;
      final observed = expectLater(
        StorageService.setTvKeyboardEnabled(true),
        outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
      );
      await backend.entered.future.timeout(_limit);
      expect(prefs.getBool(_enabled), isTrue);
      expect(StorageService.tvKeyboardEnabledCached, isFalse);
      expect((await backend.durable())['flutter.$_enabled'], isFalse);
      backend.release.complete();
      await observed;
      expect(StorageService.tvKeyboardEnabledCached, outcome != 'throw');
      expect((await backend.durable())['flutter.$_enabled'], outcome == 'ok');
      expect(backend.writes, [('flutter.$_enabled', true)]);
    });
  }

  test(
    'held migration writes old bool then stale marker throws after profile switch',
    () async {
      profiles();
      await SharedPreferences.getInstance();
      backend.holdWrite = 1;
      final result = StorageService.getTvKeyboardEnabled(tvOs: true);
      final observed = expectLater(
        result,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'stale preference guard',
            'A stale ProfilePreferences instance crossed a profile session',
          ),
        ),
      );
      await backend.entered.future.timeout(_limit);
      ProfileRuntime.publish(b);
      backend.release.complete();
      await observed;
      expect(StorageService.tvKeyboardEnabledCached, isTrue);
      expect(backend.writes, [('flutter.${a.preferenceKey(_enabled)}', false)]);
      final data = await backend.durable();
      expect(data['flutter.${a.preferenceKey(_enabled)}'], isFalse);
      expect(
        data.containsKey('flutter.${a.preferenceKey(_generation)}'),
        isFalse,
      );
      expect(data['flutter.${b.preferenceKey(_enabled)}'], isFalse);
      expect(
        data['flutter.${otherGeneration.preferenceKey(_enabled)}'],
        isTrue,
      );
      expect(data['flutter.$_enabled'], isTrue);
    },
  );

  for (final writing in [false, true]) {
    test(
      'profile capture follows held SDK acquisition writing=$writing',
      () async {
        profiles();
        backend.holdRead = true;
        final Future<Object?> result = writing
            ? StorageService.setTvKeyboardEnabled(
                true,
              ).then<Object?>((_) => null)
            : StorageService.getTvKeyboardEnabled(tvOs: false);
        await backend.entered.future.timeout(_limit);
        ProfileRuntime.publish(b);
        backend.release.complete();
        expect(await result, writing ? null : false);
        expect(
          backend.writes,
          writing ? [('flutter.${b.preferenceKey(_enabled)}', true)] : isEmpty,
        );
        final data = await backend.durable();
        expect(data['flutter.${a.preferenceKey(_enabled)}'], isTrue);
        expect(
          data['flutter.${otherGeneration.preferenceKey(_enabled)}'],
          isTrue,
        );
        expect(data['flutter.${b.preferenceKey(_enabled)}'], writing);
      },
    );
  }

  test(
    'profile reset restores synchronous default without preference writes',
    () async {
      StorageService.tvKeyboardEnabledCached = PlatformUtil.isTvOS;
      StorageService.resetProfileCaches();
      expect(StorageService.tvKeyboardEnabledCached, !PlatformUtil.isTvOS);
      expect(backend.writes, isEmpty);
      expect((await backend.durable())['flutter.$_enabled'], isTrue);
    },
  );
}
