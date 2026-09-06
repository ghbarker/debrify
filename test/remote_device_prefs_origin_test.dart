import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Real unchanged public origin f31ab5d4ea762f91802c387da77507c99724e34d.
// Device preferences are installation-wide. Profile shadows must not participate.
// Preference transport only: no sockets, identity pairing or portable-device claim.
final _cases =
    <
      ({
        String key,
        Object? fallback,
        Object value,
        Future<Object?> Function() read,
        Future<void> Function(Object) write,
      })
    >[
      (
        key: 'remote_control_enabled',
        fallback: true,
        value: false,
        read: StorageService.getRemoteControlEnabled,
        write: (v) => StorageService.setRemoteControlEnabled(v as bool),
      ),
      (
        key: 'remote_intro_shown',
        fallback: false,
        value: true,
        read: StorageService.getRemoteIntroShown,
        write: (v) => StorageService.setRemoteIntroShown(v as bool),
      ),
      (
        key: 'remote_tv_device_name',
        fallback: null,
        value: '  Synthetic TV  ',
        read: StorageService.getRemoteTvDeviceName,
        write: (v) => StorageService.setRemoteTvDeviceName(v as String),
      ),
      (
        key: 'remote_last_device',
        fallback: null,
        value: <String, dynamic>{
          'id': 'synthetic',
          'port': 17,
          'extra': [true, null],
        },
        read: StorageService.getRemoteLastDevice,
        write: (v) =>
            StorageService.setRemoteLastDevice(v as Map<String, dynamic>),
      ),
    ];

class _Transport extends InMemorySharedPreferencesStore {
  _Transport(super.data) : super.withData();
  final attempts = <String>[];
  String mode = 'ok';
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<bool> record(String label, Future<bool> Function() commit) async {
    attempts.add(label);
    if (hold) {
      entered.complete();
      await release.future;
    }
    if (mode == 'false') return false;
    if (mode == 'throw') throw StateError('synthetic device transport');
    return commit();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      record('set:$type:$key', () => super.setValue(type, key, value));
  @override
  Future<bool> remove(String key) =>
      record('remove:$key', () => super.remove(key));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Transport backend;
  final a = ProfileScope(
    profileId: 'remote-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'remote-b',
    dataGeneration: 2,
    sessionEpoch: 2,
  );
  const sentinels = <String, Object>{
    'remote_static_keypair_v1': 'SYNTHETIC_NOT_A_KEY',
    'remote_paired_devices_v1': 'SYNTHETIC_NOT_A_PAIRING',
    'remote_known_receivers_v1': 'SYNTHETIC_NOT_A_RECEIVER',
    'update_auto_check_enabled': false,
    'update_ignored_version': 'synthetic-version',
  };
  Object physical(Object value) => value is Map ? jsonEncode(value) : value;
  Future<void> install([Map<String, Object> values = const {}]) async {
    SharedPreferences.resetStatic();
    backend = _Transport({
      for (final e in sentinels.entries) 'flutter.${e.key}': e.value,
      for (final scope in [a, b])
        for (final c in _cases)
          'flutter.${scope.preferenceKey(c.key)}': 'profile shadow',
      for (final e in values.entries) 'flutter.${e.key}': e.value,
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  Future<void> expectIsolated() async {
    final raw = await backend.getAll();
    for (final e in sentinels.entries) {
      expect(raw['flutter.${e.key}'], e.value);
    }
    for (final scope in [a, b]) {
      for (final c in _cases) {
        expect(raw['flutter.${scope.preferenceKey(c.key)}'], 'profile shadow');
      }
    }
  }

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(a);
    await install();
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferencesStorePlatform.instance = previous;
    SharedPreferences.resetStatic();
    ProfileRuntime.debugReset();
  });

  test(
    'all defaults ignore profile shadows and work before profile bootstrap',
    () async {
      for (final c in _cases) {
        expect(await c.read(), c.fallback);
      }
      ProfileRuntime.debugReset();
      for (final c in _cases) {
        expect(await c.read(), c.fallback);
      }
      expect(backend.attempts, isEmpty);
      await expectIsolated();
    },
  );

  for (final c in _cases) {
    test(
      '${c.key}: wrong physical integer throws outside JSON catch',
      () async {
        await install({c.key: 17});
        await expectLater(c.read(), throwsA(isA<TypeError>()));
        expect((await backend.getAll())['flutter.${c.key}'], 17);
        expect(backend.attempts, isEmpty);
      },
    );
    for (final mode in ['ok', 'false', 'throw']) {
      test(
        '${c.key}: held $mode write remains device-wide across profiles',
        () async {
          backend.mode = mode;
          backend.hold = true;
          final call = c.write(c.value);
          final completed = mode == 'throw'
              ? expectLater(
                  call,
                  throwsA(
                    isA<StateError>().having(
                      (e) => e.message,
                      'message',
                      'synthetic device transport',
                    ),
                  ),
                )
              : expectLater(call, completes);
          try {
            await backend.entered.future.timeout(const Duration(seconds: 5));
            expect((await backend.getAll())['flutter.${c.key}'], isNull);
            ProfileRuntime.publish(b);
            // The SDK cache is already updated before the transport returns.
            expect(await c.read(), c.value);
            backend.release.complete();
            await completed;
            expect(await c.read(), c.value);
            expect(
              (await backend.getAll())['flutter.${c.key}'],
              mode == 'ok' ? physical(c.value) : null,
            );
            expect(backend.attempts, [
              'set:${c.value is bool ? 'Bool' : 'String'}:flutter.${c.key}',
            ]);
            await expectIsolated();
          } finally {
            if (!backend.release.isCompleted) backend.release.complete();
            await completed;
          }
        },
      );
    }
  }

  for (final raw in [
    '',
    '{broken',
    '[]',
    '[{"id":"x"}]',
    'null',
    'false',
    '17',
    '"text"',
  ]) {
    test('remembered JSON $raw returns null without normalization', () async {
      await install({'remote_last_device': raw});
      expect(await StorageService.getRemoteLastDevice(), isNull);
      expect((await backend.getAll())['flutter.remote_last_device'], raw);
      expect(backend.attempts, isEmpty);
    });
  }
  test('device name preserves empty and whitespace strings', () async {
    for (final name in ['', '  ', ' Synthetic TV ']) {
      await StorageService.setRemoteTvDeviceName(name);
      expect(await StorageService.getRemoteTvDeviceName(), name);
      expect((await backend.getAll())['flutter.remote_tv_device_name'], name);
    }
  });
  test(
    'arbitrary JSON map is encoded exactly and reads are fresh decodes',
    () async {
      final device = <String, dynamic>{
        'extra': [1, null, false],
        'name': '  ',
        'unknown': {'x': 2},
      };
      await StorageService.setRemoteLastDevice(device);
      final raw = jsonEncode(device);
      expect((await backend.getAll())['flutter.remote_last_device'], raw);
      final first = (await StorageService.getRemoteLastDevice())!;
      (first['extra'] as List).clear();
      first['new'] = 'local';
      expect(await StorageService.getRemoteLastDevice(), device);
      expect((await backend.getAll())['flutter.remote_last_device'], raw);
    },
  );
  test(
    'unencodable map throws before transport and preserves remembered JSON',
    () async {
      await install({'remote_last_device': '{"old":true}'});
      await expectLater(
        StorageService.setRemoteLastDevice({'bad': Object()}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(await StorageService.getRemoteLastDevice(), {'old': true});
      expect(backend.attempts, isEmpty);
    },
  );
  for (final mode in ['ok', 'false', 'throw']) {
    test(
      'held clear $mode removes only remembered device, preserving other keys',
      () async {
        await install({for (final c in _cases) c.key: physical(c.value)});
        backend.mode = mode;
        backend.hold = true;
        final call = StorageService.clearRemoteLastDevice();
        final completed = mode == 'throw'
            ? expectLater(call, throwsStateError)
            : expectLater(call, completes);
        try {
          await backend.entered.future.timeout(const Duration(seconds: 5));
          ProfileRuntime.publish(b);
          expect(await StorageService.getRemoteLastDevice(), isNull);
          backend.release.complete();
          await completed;
          expect(
            (await backend.getAll())['flutter.remote_last_device'],
            mode == 'ok' ? null : physical(_cases.last.value),
          );
          for (final c in _cases.take(3)) {
            expect(await c.read(), c.value);
          }
          expect(backend.attempts, ['remove:flutter.remote_last_device']);
          await expectIsolated();
        } finally {
          if (!backend.release.isCompleted) backend.release.complete();
          await completed;
        }
      },
    );
  }
}
