import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Current reset origin ba527454bb69a6cebb6fc226ed075ee176b24b69.
// The export fixture separately targets pre-S2 6d26d7a1; it does not claim that
// pre-S2 already had the current separate provider-reset phase.
final filterDefaultCases =
    <
      ({
        String key,
        Future<List<String>> Function() read,
        Future<void> Function(List<String>) write,
      })
    >[
      (
        key: 'default_filter_qualities_v1',
        read: StorageService.getDefaultFilterQualities,
        write: StorageService.setDefaultFilterQualities,
      ),
      (
        key: 'default_filter_rip_sources_v1',
        read: StorageService.getDefaultFilterRipSources,
        write: StorageService.setDefaultFilterRipSources,
      ),
      (
        key: 'default_filter_languages_v1',
        read: StorageService.getDefaultFilterLanguages,
        write: StorageService.setDefaultFilterLanguages,
      ),
      (
        key: 'default_filter_sizes_v1',
        read: StorageService.getDefaultFilterSizes,
        write: StorageService.setDefaultFilterSizes,
      ),
      (
        key: 'default_filter_dynamic_ranges_v1',
        read: StorageService.getDefaultFilterDynamicRanges,
        write: StorageService.setDefaultFilterDynamicRanges,
      ),
    ];

Map<String, Object?> filterDefaultRecipe() => Map<String, Object?>.from(
  (jsonDecode(
            File(
              'test/fixtures/storage_origin_restore/recipe.json',
            ).readAsStringSync(),
          )
          as Map)['residualDomains']['filter-defaults']['values']
      as Map,
);

Future<void> seedFilterDefaults(Map<String, Object?> expected) async {
  for (final entry in filterDefaultCases) {
    await entry.write(
      (jsonDecode(expected[entry.key]! as String) as List).cast<String>(),
    );
  }
}

Future<void> expectFilterDefaultReaders(Map<String, Object?> expected) async {
  for (final entry in filterDefaultCases) {
    expect(
      await entry.read(),
      jsonDecode(expected[entry.key]! as String),
      reason: entry.key,
    );
  }
}

class _ObservedPreferences extends InMemorySharedPreferencesStore {
  _ObservedPreferences(super.data) : super.withData();
  final attempts = <String>[];
  String? failKey;
  String? holdKey;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> remove(String key) async {
    attempts.add(key);
    if (key == failKey) throw StateError('synthetic remove failure');
    final result = await super.remove(key);
    if (key == holdKey) {
      entered.complete();
      await release.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final expected = filterDefaultRecipe();
  final keys = filterDefaultCases.map((e) => e.key).toList();
  const provider = 'default_torrent_provider_v1';
  const sentinels = <String, Object>{
    'quick_play_honors_filters_v1': false,
    'quick_play_movie_rules_v2': '{"fixture":"movie"}',
    'quick_play_series_rules_v2': '{"fixture":"series"}',
    'unrelated_filter_sentinel': 'untouched',
  };
  late SharedPreferencesStorePlatform previous;
  late _ObservedPreferences backend;
  final a = ProfileScope(
    profileId: 'filter-origin-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'filter-origin-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );

  Future<void> install({bool committed = false}) async {
    final values = {...expected, ...sentinels, provider: 'torbox'};
    backend = _ObservedPreferences({
      if (!committed)
        for (final e in values.entries) 'flutter.${e.key}': e.value!,
      if (committed)
        for (final scope in [a, b])
          for (final e in values.entries)
            'flutter.${scope.preferenceKey(e.key)}': e.value!,
    });
    SharedPreferences.resetStatic();
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

  for (final entry in filterDefaultCases) {
    test(
      '${entry.key}: String JSON roundtrip keeps order/duplicates and absent default',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(entry.key);
        expect(await entry.read(), isEmpty);
        await entry.write(
          (jsonDecode(expected[entry.key]! as String) as List).cast<String>(),
        );
        expect(prefs.get(entry.key), isA<String>());
        expect(prefs.get(entry.key), expected[entry.key]);
        expect(await entry.read(), jsonDecode(expected[entry.key]! as String));
        await entry.write([]);
        expect(prefs.get(entry.key), '[]');
        expect(await entry.read(), isEmpty);
        for (final e in sentinels.entries) {
          expect(prefs.get(e.key), e.value);
        }
      },
    );

    test(
      '${entry.key}: malformed JSON and wrong physical/root/element types throw',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(entry.key, '[');
        await expectLater(entry.read(), throwsA(isA<FormatException>()));
        for (final raw in ['{}', '[1]', 'null']) {
          await prefs.setString(entry.key, raw);
          await expectLater(entry.read(), throwsA(isA<TypeError>()));
        }
        await prefs.setStringList(entry.key, ['not a JSON String']);
        await expectLater(entry.read(), throwsA(isA<TypeError>()));
      },
    );
  }

  test(
    'reset removes five filters in order then provider; keeps legacy rules',
    () async {
      await StorageService.clearAllFilterSettings();
      expect(backend.attempts, [...keys, provider].map((k) => 'flutter.$k'));
      expect(await backend.getAll(), {
        for (final e in sentinels.entries) 'flutter.${e.key}': e.value,
      });
    },
  );

  for (var failIndex = 0; failIndex <= keys.length; failIndex++) {
    test(
      'reset failed removal $failIndex stops before subsequent keys',
      () async {
        final ordered = [...keys, provider];
        backend.failKey = 'flutter.${ordered[failIndex]}';
        await expectLater(
          StorageService.clearAllFilterSettings(),
          throwsA(isA<StateError>()),
        );
        expect(
          backend.attempts,
          ordered.take(failIndex + 1).map((k) => 'flutter.$k'),
        );
        final persisted = await backend.getAll();
        for (var i = 0; i < ordered.length; i++) {
          expect(
            persisted.containsKey('flutter.${ordered[i]}'),
            i >= failIndex,
          );
        }
        for (final e in sentinels.entries) {
          expect(persisted['flutter.${e.key}'], e.value);
        }
      },
    );
  }

  for (final holdIndex in [0, 4]) {
    test(
      'profile switch after filter $holdIndex pins captured filters and separate provider phase',
      () async {
        await install(committed: true);
        backend.holdKey = 'flutter.${a.preferenceKey(keys[holdIndex])}';
        final completion = StorageService.clearAllFilterSettings();
        final observed = holdIndex == 0
            ? expectLater(completion, throwsA(isA<StateError>()))
            : expectLater(completion, completes);
        await backend.entered.future;
        ProfileRuntime.publish(b);
        backend.release.complete();
        await observed;
        expect(backend.attempts, [
          for (final key in keys.take(holdIndex + 1))
            'flutter.${a.preferenceKey(key)}',
          if (holdIndex == 4) 'flutter.${b.preferenceKey(provider)}',
        ]);
        final persisted = await backend.getAll();
        for (var i = 0; i < keys.length; i++) {
          expect(
            persisted.containsKey('flutter.${a.preferenceKey(keys[i])}'),
            i > holdIndex,
          );
          expect(
            persisted['flutter.${b.preferenceKey(keys[i])}'],
            expected[keys[i]],
          );
        }
        expect(persisted['flutter.${a.preferenceKey(provider)}'], 'torbox');
        expect(
          persisted.containsKey('flutter.${b.preferenceKey(provider)}'),
          holdIndex == 0,
        );
        for (final scope in [a, b]) {
          for (final e in sentinels.entries) {
            expect(persisted['flutter.${scope.preferenceKey(e.key)}'], e.value);
          }
        }
      },
    );
  }
}
