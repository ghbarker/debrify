import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Real public origin: 5d509e0ff0dfa99c6ec589e46cd2bb75d39f92ef.
// No store copy, private helper invocation or production seam. Backend controls
// only persistence transport; cached SharedPreferences values remain real SDK state.
const movieKey = 'quick_play_movie_rules_v2';
const seriesKey = 'quick_play_series_rules_v2';
const honorsKey = 'quick_play_honors_filters_v1';
const retryKey = 'quick_play_try_multiple_torrents';
const maxKey = 'quick_play_max_retries';
const packsKey = 'auto_bind_series_packs_on_play';
const modeKey = 'play_button_mode';

class _Observed extends InMemorySharedPreferencesStore {
  _Observed(super.data) : super.withData();
  final attempts = <String>[];
  final values = <Object?>[];
  int? failAt;
  int? falseAt;
  int? holdAt;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<bool> _write(
    String key,
    Object? value,
    Future<bool> Function() commit,
  ) async {
    attempts.add(key);
    values.add(value);
    final index = attempts.length - 1;
    if (index == holdAt) {
      entered.complete();
      await release.future;
    }
    if (index == failAt) throw StateError('synthetic write failure');
    if (index == falseAt) return false;
    return commit();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _write(key, value, () => super.setValue(valueType, key, value));
  @override
  Future<bool> remove(String key) => _write(key, null, () => super.remove(key));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Observed backend;
  final a = ProfileScope(
    profileId: 'quick-policy-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'quick-policy-b',
    dataGeneration: 2,
    sessionEpoch: 2,
  );
  const legacy = <String, Object>{
    honorsKey: false,
    retryKey: false,
    maxKey: 3,
    packsKey: false,
    modeKey: 'smart',
  };
  const sentinels = <String, Object>{
    'series_auto_pin_on_play': false,
    'quick_play_search_timeout': 42,
    'quick_play_vr_mode': 'auto',
    'policy_sentinel': 'untouched',
  };
  final selected = QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
    preset: QuickPlayPreset.custom,
    maxAttempts: 8,
    tryNextOnFailure: true,
    preferSeriesPacks: true,
  );
  Future<void> install(
    Map<String, Object> data, {
    bool committed = false,
  }) async {
    SharedPreferences.resetStatic();
    backend = _Observed({
      if (!committed)
        for (final e in data.entries) 'flutter.${e.key}': e.value,
      if (committed)
        for (final scope in [a, b])
          for (final e in data.entries)
            'flutter.${scope.preferenceKey(e.key)}': e.value,
    });
    SharedPreferencesStorePlatform.instance = backend;
    if (committed) ProfileRuntime.initializeCommitted(a);
  }

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await install({...legacy, ...sentinels});
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  for (final raw in ['[', '[]', 'null', '{"maxAttempts":"bad"}']) {
    test(
      'invalid v2 $raw falls back without normalizing stored bytes',
      () async {
        await install({...legacy, movieKey: raw});
        final result = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
        expect(result.preset, QuickPlayPreset.custom);
        expect(result.useFilters, false);
        expect(result.maxAttempts, 3);
        expect(result.tryNextOnFailure, false);
        expect(result.preferSeriesPacks, false);
        expect((await SharedPreferences.getInstance()).get(movieKey), raw);
        expect(backend.attempts, isEmpty);
      },
    );
  }
  test('wrong physical v2 type escapes before parser catch', () async {
    await install({...legacy, movieKey: 7});
    await expectLater(
      QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true),
      throwsA(isA<TypeError>()),
    );
    expect(backend.attempts, isEmpty);
  });
  for (final key in [honorsKey, retryKey, maxKey]) {
    test('wrong legacy physical type $key escapes fallback', () async {
      await install({...legacy, key: 'bad'});
      await expectLater(
        QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true),
        throwsA(isA<TypeError>()),
      );
      expect(backend.attempts, isEmpty);
    });
  }
  test('movie skips malformed packs legacy read; series throws', () async {
    await install({...legacy, packsKey: 'bad'});
    expect(
      (await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true)).preferSeriesPacks,
      false,
    );
    await expectLater(
      QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false),
      throwsA(isA<TypeError>()),
    );
  });
  test(
    'existing malformed sibling is preserved by containsKey without parsing',
    () async {
      await install({...legacy, movieKey: 7});
      await QuickPlayPolicyPrefs.setQuickPlayRules(selected, isMovie: false);
      expect(
        backend.attempts,
        [seriesKey, retryKey, maxKey, packsKey].map((k) => 'flutter.$k'),
      );
      expect((await SharedPreferences.getInstance()).get(movieKey), 7);
    },
  );
  test(
    'missing sibling snapshots legacy BEFORE selected write and mirrors',
    () async {
      backend.holdAt = 0;
      final work = QuickPlayPolicyPrefs.setQuickPlayRules(selected, isMovie: false);
      await backend.entered.future;
      final prefs = await SharedPreferences.getInstance();
      expect(backend.attempts, ['flutter.$seriesKey']);
      expect(prefs.getString(seriesKey), jsonEncode(selected.toJson()));
      expect((await backend.getAll()).containsKey('flutter.$seriesKey'), false);
      // Change real SDK cache while the durable first write is held. The sibling
      // must use the already captured legacy values, not re-read these new ones.
      await prefs.setInt(maxKey, 9);
      backend.release.complete();
      await work;
      final sibling = jsonDecode(prefs.getString(movieKey)!) as Map;
      expect(sibling['maxAttempts'], 3);
      expect(sibling['tryNextOnFailure'], false);
      expect(sibling['useFilters'], false);
      expect(
        backend.attempts,
        [
          seriesKey,
          maxKey,
          movieKey,
          retryKey,
          maxKey,
          packsKey,
        ].map((k) => 'flutter.$k'),
      );
      expect(prefs.getBool(honorsKey), false);
    },
  );
  test('malformed missing-sibling legacy prevents every write', () async {
    await install({...legacy, maxKey: 'bad'});
    await expectLater(
      QuickPlayPolicyPrefs.setQuickPlayRules(selected, isMovie: false),
      throwsA(isA<TypeError>()),
    );
    expect(backend.attempts, isEmpty);
  });
  final ordered = [seriesKey, movieKey, retryKey, maxKey, packsKey];
  for (var failure = 0; failure < 5; failure++) {
    test(
      'write throw $failure leaves only durable prefix, cached failed write remains',
      () async {
        backend.failAt = failure;
        final before = await backend.getAll();
        await expectLater(
          QuickPlayPolicyPrefs.setQuickPlayRules(selected, isMovie: false),
          throwsStateError,
        );
        expect(
          backend.attempts,
          ordered.take(failure + 1).map((k) => 'flutter.$k'),
        );
        final durable = await backend.getAll();
        for (var i = 0; i < ordered.length; i++) {
          final k = 'flutter.${ordered[i]}';
          expect(
            durable[k],
            i < failure ? backend.values[i] : before[k],
            reason: k,
          );
        }
        expect(
          (await SharedPreferences.getInstance()).get(ordered[failure]),
          backend.values[failure],
        );
      },
    );
  }
  test('false write is ignored and later writes continue', () async {
    backend.falseAt = 0;
    await QuickPlayPolicyPrefs.setQuickPlayRules(selected, isMovie: false);
    expect(backend.attempts, ordered.map((k) => 'flutter.$k'));
    expect((await backend.getAll()).containsKey('flutter.$seriesKey'), false);
    expect(
      (await SharedPreferences.getInstance()).getString(seriesKey),
      jsonEncode(selected.toJson()),
    );
  });
  test(
    'captured prefs reject later writes after held write switches session',
    () async {
      await install({...legacy, ...sentinels}, committed: true);
      backend.holdAt = 0;
      final work = QuickPlayPolicyPrefs.setQuickPlayRules(selected, isMovie: false);
      final failure = expectLater(work, throwsStateError);
      await backend.entered.future;
      ProfileRuntime.initializeCommitted(b);
      backend.release.complete();
      await failure;
      expect(backend.attempts, ['flutter.${a.preferenceKey(seriesKey)}']);
      expect((await backend.getAll())['flutter.${b.preferenceKey(maxKey)}'], 3);
    },
  );
  test(
    'restore reacquires for second rules phase after first final write',
    () async {
      await install({...legacy, ...sentinels}, committed: true);
      backend.holdAt =
          3; // movie, missing series, try, max: first phase ends here
      final work = QuickPlayPolicyPrefs.restoreQuickPlayDefaults();
      await backend.entered.future;
      ProfileRuntime.initializeCommitted(b);
      backend.release.complete();
      await work;
      expect(backend.attempts, [
        for (final key in [movieKey, seriesKey, retryKey, maxKey])
          'flutter.${a.preferenceKey(key)}',
        for (final key in [
          seriesKey,
          movieKey,
          retryKey,
          maxKey,
          packsKey,
          honorsKey,
          modeKey,
        ])
          'flutter.${b.preferenceKey(key)}',
      ]);
      final raw = await backend.getAll();
      expect(raw['flutter.${a.preferenceKey(modeKey)}'], 'smart');
      expect(raw.containsKey('flutter.${b.preferenceKey(modeKey)}'), false);
      expect(raw['flutter.${a.preferenceKey(honorsKey)}'], false);
      expect(raw['flutter.${b.preferenceKey(honorsKey)}'], true);
    },
  );
  test(
    'restore reacquires final honors and mode phase after series finishes',
    () async {
      await install({...legacy, ...sentinels}, committed: true);
      backend.holdAt = 7;
      final work = QuickPlayPolicyPrefs.restoreQuickPlayDefaults();
      await backend.entered.future;
      ProfileRuntime.initializeCommitted(b);
      backend.release.complete();
      await work;
      expect(backend.attempts, [
        for (final key in [
          movieKey,
          seriesKey,
          retryKey,
          maxKey,
          seriesKey,
          retryKey,
          maxKey,
          packsKey,
        ])
          'flutter.${a.preferenceKey(key)}',
        for (final key in [honorsKey, modeKey])
          'flutter.${b.preferenceKey(key)}',
      ]);
      final raw = await backend.getAll();
      expect(raw['flutter.${a.preferenceKey(honorsKey)}'], false);
      expect(raw['flutter.${a.preferenceKey(modeKey)}'], 'smart');
      expect(raw.containsKey('flutter.${b.preferenceKey(movieKey)}'), false);
    },
  );
  test(
    'clear retains captured prefs after held remove and stops on stale scope',
    () async {
      await install({
        ...legacy,
        movieKey: '{}',
        seriesKey: '{}',
      }, committed: true);
      backend.holdAt = 0;
      final work = QuickPlayPolicyPrefs.clearQuickPlayCacheFallbackSettings();
      final failure = expectLater(work, throwsStateError);
      await backend.entered.future;
      ProfileRuntime.initializeCommitted(b);
      backend.release.complete();
      await failure;
      expect(backend.attempts, ['flutter.${a.preferenceKey(retryKey)}']);
      expect(
        (await backend.getAll())['flutter.${b.preferenceKey(retryKey)}'],
        false,
      );
    },
  );
  final clearKeys = [retryKey, maxKey, movieKey, seriesKey];
  for (var failure = 0; failure <= 4; failure++) {
    test(
      'clear ordered prefix failure $failure preserves nonmembers',
      () async {
        await install({
          ...legacy,
          ...sentinels,
          movieKey: '{}',
          seriesKey: '{}',
        });
        backend.failAt = failure < 4 ? failure : null;
        if (failure < 4) {
          await expectLater(
            QuickPlayPolicyPrefs.clearQuickPlayCacheFallbackSettings(),
            throwsStateError,
          );
        } else {
          await QuickPlayPolicyPrefs.clearQuickPlayCacheFallbackSettings();
        }
        expect(
          backend.attempts,
          clearKeys
              .take(failure < 4 ? failure + 1 : 4)
              .map((k) => 'flutter.$k'),
        );
        final raw = await backend.getAll();
        for (var i = 0; i < 4; i++) {
          expect(raw.containsKey('flutter.${clearKeys[i]}'), i >= failure);
        }
        for (final e in {
          ...sentinels,
          honorsKey: false,
          packsKey: false,
          modeKey: 'smart',
        }.entries) {
          expect(raw['flutter.${e.key}'], e.value);
        }
      },
    );
  }
  test(
    'legacy scalar clamps differ from rules and mode read does not normalize',
    () async {
      await install({maxKey: 99, modeKey: 'future-mode'});
      expect(await QuickPlayPolicyPrefs.getQuickPlayMaxRetries(), 99);
      expect(
        (await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true)).maxAttempts,
        10,
      );
      await QuickPlayPolicyPrefs.setQuickPlayMaxRetries(1);
      expect(await QuickPlayPolicyPrefs.getQuickPlayMaxRetries(), 2);
      await QuickPlayPolicyPrefs.setQuickPlayMaxRetries(99);
      expect(await QuickPlayPolicyPrefs.getQuickPlayMaxRetries(), 10);
      await QuickPlayPolicyPrefs.setPlayButtonMode('future-mode');
      expect(await QuickPlayPolicyPrefs.getPlayButtonMode(), 'quick');
      expect(
        (await SharedPreferences.getInstance()).getString(modeKey),
        'future-mode',
      );
    },
  );
}
