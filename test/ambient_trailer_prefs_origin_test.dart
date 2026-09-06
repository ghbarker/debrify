import 'package:debrify/services/storage/ambient_trailer_prefs.dart' show AmbientTrailerPrefs;
import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart' show AmbientTrailerSurface;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Real public origin 045701afd04265291fe7bd522f0ae6e22d3f3029.
// Preference transport only, not platform choice, trailer playback or underlay.
const _initial = <String, Object>{
  'home_hero_trailer_audio_enabled': false,
  'home_hero_trailer_volume': 31,
  'detail_trailer_audio_enabled': false,
  'detail_trailer_volume': 42,
};

class _AmbientBackend extends InMemorySharedPreferencesStore {
  _AmbientBackend(super.data) : super.withData();
  final attempts = <String>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic ambient preferences failure');
  bool holdRead = false;
  bool holdWrite = false;
  String outcome = 'ok';

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (holdRead) {
      entered.complete();
      await release.future;
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    attempts.add(key);
    if (holdWrite) {
      entered.complete();
      await release.future;
    }
    if (outcome == 'throw') throw failure;
    if (outcome == 'false') return false;
    return super.setValue(type, key, value);
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _AmbientBackend backend;
  final a = ProfileScope(
    profileId: 'ambient-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'ambient-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final anotherGeneration = ProfileScope(
    profileId: 'ambient-a',
    dataGeneration: 2,
    sessionEpoch: 3,
  );

  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    backend = _AmbientBackend({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.ambient_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  void installProfiles({Map<String, Object>? destination}) {
    install({
      ..._initial,
      for (final scope in [a, b, anotherGeneration])
        for (final e
            in (scope == b && destination != null ? destination : _initial)
                .entries)
          scope.preferenceKey(e.key): e.value,
    });
    ProfileRuntime.initializeCommitted(a);
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install(_initial);
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  for (final surface in AmbientTrailerSurface.values) {
    final prefix = surface == AmbientTrailerSurface.homeHero
        ? 'home_hero'
        : 'detail';
    final audio = '${prefix}_trailer_audio_enabled';
    final volume = '${prefix}_trailer_volume';

    test(
      '$surface: absent defaults true/70 do not write either surface',
      () async {
        install({});
        final before = await backend.durable();
        expect(
          await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(surface),
          isTrue,
        );
        expect(await AmbientTrailerPrefs.getAmbientTrailerVolume(surface), 70);
        expect(await backend.durable(), before);
        expect(backend.attempts, isEmpty);
      },
    );

    test(
      '$surface: stored out-of-range integers clamp on read without normalization writes',
      () async {
        for (final pair in [
          (0, 10),
          (9, 10),
          (10, 10),
          (70, 70),
          (100, 100),
          (101, 100),
          (-99, 10),
        ]) {
          install({..._initial, volume: pair.$1});
          final before = await backend.durable();
          expect(
            await AmbientTrailerPrefs.getAmbientTrailerVolume(surface),
            pair.$2,
          );
          expect((await SharedPreferences.getInstance()).get(volume), pair.$1);
          expect(await backend.durable(), before);
          expect(backend.attempts, isEmpty);
        }
      },
    );

    test(
      '$surface: wrong physical types propagate without repair or other-surface fallback',
      () async {
        for (final value in <Object>[
          'false',
          0,
          <String>['false'],
        ]) {
          install({..._initial, audio: value});
          final before = await backend.durable();
          await expectLater(
            AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(surface),
            throwsA(isA<TypeError>()),
          );
          expect(await backend.durable(), before);
        }
        for (final value in <Object>[
          '70',
          true,
          70.5,
          <String>['70'],
        ]) {
          install({..._initial, volume: value});
          final before = await backend.durable();
          await expectLater(
            AmbientTrailerPrefs.getAmbientTrailerVolume(surface),
            throwsA(isA<TypeError>()),
          );
          expect(await backend.durable(), before);
        }
        expect(backend.attempts, isEmpty);
      },
    );

    test(
      '$surface: writes clamp only their volume key and keep physical bool/int types',
      () async {
        for (final pair in [
          (-20, 10),
          (10, 10),
          (37, 37),
          (100, 100),
          (1000, 100),
        ]) {
          await AmbientTrailerPrefs.setAmbientTrailerVolume(surface, pair.$1);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.get(volume), pair.$2);
          expect(prefs.get(volume), isA<int>());
          expect(
            await AmbientTrailerPrefs.getAmbientTrailerVolume(surface),
            pair.$2,
          );
        }
        for (final value in [true, false]) {
          await AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(surface, value);
          expect((await SharedPreferences.getInstance()).get(audio), value);
          expect(
            await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(surface),
            value,
          );
        }
        final persisted = await backend.durable();
        for (final e in _initial.entries.where(
          (e) => e.key != audio && e.key != volume,
        )) {
          expect(persisted['flutter.${e.key}'], e.value);
        }
        expect(persisted['flutter.ambient_sentinel'], 'untouched');
      },
    );

    for (final isAudio in [true, false]) {
      final key = isAudio ? audio : volume;
      final Object updated = isAudio ? true : 100;
      Future<void> write() => isAudio
          ? AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(surface, true)
          : AmbientTrailerPrefs.setAmbientTrailerVolume(surface, 1000);
      Future<Object> read() async => isAudio
          ? await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(surface)
          : await AmbientTrailerPrefs.getAmbientTrailerVolume(surface);

      for (final outcome in ['ok', 'false', 'throw']) {
        test(
          '$surface/$key: held $outcome separates SDK cache from persisted state',
          () async {
            final prefs = await SharedPreferences.getInstance();
            backend.holdWrite = true;
            backend.outcome = outcome;
            final future = write();
            final observed = expectLater(
              future,
              outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
            );
            await backend.entered.future;
            expect(backend.attempts, ['flutter.$key']);
            expect(prefs.get(key), updated);
            expect((await backend.durable())['flutter.$key'], _initial[key]);
            backend.release.complete();
            await observed;
            expect(await read(), updated);
            final persisted = await backend.durable();
            expect(
              persisted['flutter.$key'],
              outcome == 'ok' ? updated : _initial[key],
            );
            for (final e in _initial.entries.where((e) => e.key != key)) {
              expect(persisted['flutter.${e.key}'], e.value);
            }
          },
        );
      }

      test(
        '$surface/$key: held write completes in captured old profile after switch',
        () async {
          installProfiles();
          await SharedPreferences.getInstance();
          backend.holdWrite = true;
          final future = write();
          final observed = expectLater(future, completes);
          await backend.entered.future;
          ProfileRuntime.publish(b);
          backend.release.complete();
          await observed;
          expect(backend.attempts, ['flutter.${a.preferenceKey(key)}']);
          final persisted = await backend.durable();
          expect(persisted['flutter.${a.preferenceKey(key)}'], updated);
          for (final e in _initial.entries) {
            if (e.key != key) {
              expect(persisted['flutter.${a.preferenceKey(e.key)}'], e.value);
            }
            expect(persisted['flutter.${b.preferenceKey(e.key)}'], e.value);
            expect(
              persisted['flutter.${anotherGeneration.preferenceKey(e.key)}'],
              e.value,
            );
            expect(persisted['flutter.${e.key}'], e.value);
          }
          expect(await read(), _initial[key]);
        },
      );

      for (final writing in [false, true]) {
        test(
          '$surface/$key: profile capture follows held SDK acquisition (${writing ? 'write' : 'read'})',
          () async {
            final Object destinationValue = isAudio ? true : 84;
            installProfiles(destination: {..._initial, key: destinationValue});
            backend.holdRead = true;
            final Future<Object?> future = writing
                ? write().then<Object?>((_) => null)
                : read();
            await backend.entered.future;
            ProfileRuntime.publish(b);
            backend.release.complete();
            expect(await future, writing ? null : destinationValue);
            expect(
              backend.attempts,
              writing ? ['flutter.${b.preferenceKey(key)}'] : isEmpty,
            );
            final persisted = await backend.durable();
            expect(persisted['flutter.${a.preferenceKey(key)}'], _initial[key]);
            expect(
              persisted['flutter.${b.preferenceKey(key)}'],
              writing ? updated : destinationValue,
            );
            expect(
              persisted['flutter.${anotherGeneration.preferenceKey(key)}'],
              _initial[key],
            );
            expect(persisted['flutter.ambient_sentinel'], 'untouched');
          },
        );
      }
    }
  }
}
