import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Actual public origin bbc6113f. Device preference transport only: no network,
// installation, native permissions, profile-safety or serialization claim.
const _cache = 'support_remote_config_cache_v1';
const _dismissed = 'dismissed_donation_campaign_ids_v1';
const _auto = 'update_auto_check_enabled';
const _ignored = 'update_ignored_version';
const _keys = {_cache, _dismissed, _auto, _ignored};
const _limit = Duration(seconds: 5);

class _Backend extends InMemorySharedPreferencesStore {
  _Backend(super.data) : super.withData();
  final calls = <(String, String, Object?)>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic maintenance persistence failure');
  String? heldKey;
  String outcome = 'ok';
  bool holdRead = false;
  int otherWrites = 0;

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

  Future<bool> finish(String key, Future<bool> Function() persist) async {
    if (key == 'flutter.$heldKey') {
      entered.complete();
      await release.future.timeout(_limit);
      if (outcome == 'false') return false;
      if (outcome == 'throw') throw failure;
    }
    return persist();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (!_keys.any((k) => key == 'flutter.$k')) {
      otherWrites++;
      return super.setValue(type, key, value);
    }
    calls.add(('set', key, value));
    return finish(key, () => super.setValue(type, key, value));
  }

  @override
  Future<bool> remove(String key) {
    if (!_keys.any((k) => key == 'flutter.$k')) {
      otherWrites++;
      return super.remove(key);
    }
    calls.add(('remove', key, null));
    return finish(key, () => super.remove(key));
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Backend backend;
  final a = ProfileScope(
    profileId: 'maintenance-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'maintenance-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final other = ProfileScope(
    profileId: 'maintenance-a',
    dataGeneration: 7,
    sessionEpoch: 3,
  );
  final initial = <String, Object>{
    _cache: '{opaque old',
    _dismissed: <String>['old'],
    _auto: true,
    _ignored: ' old ',
  };

  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    backend = _Backend({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.maintenance_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  void profiles() {
    install({
      ...initial,
      for (final scope in [a, b, other])
        for (final key in _keys) scope.preferenceKey(key): 'profile shadow',
    });
    ProfileRuntime.initializeCommitted(a);
  }

  Future<void> expectShadows() async {
    final data = await backend.durable();
    for (final scope in [a, b, other]) {
      for (final key in _keys) {
        expect(data['flutter.${scope.preferenceKey(key)}'], 'profile shadow');
      }
    }
    expect(data['flutter.maintenance_sentinel'], 'untouched');
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install({});
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  test(
    'absent defaults do not write and dismissal list is independent',
    () async {
      expect(await StorageService.getSupportRemoteConfigCache(), isNull);
      expect(await StorageService.getUpdateAutoCheckEnabled(), isTrue);
      expect(await StorageService.getIgnoredUpdateVersion(), isNull);
      final ids = await StorageService.getDismissedDonationCampaignIds();
      ids.add('local');
      expect(await StorageService.getDismissedDonationCampaignIds(), isEmpty);
      expect(backend.calls, isEmpty);
    },
  );
  final readers = <String, Future<Object?> Function()>{
    _cache: StorageService.getSupportRemoteConfigCache,
    _dismissed: StorageService.getDismissedDonationCampaignIds,
    _auto: StorageService.getUpdateAutoCheckEnabled,
    _ignored: StorageService.getIgnoredUpdateVersion,
  };
  for (final entry in readers.entries) {
    test(
      'wrong physical type throws without normalization: ${entry.key}',
      () async {
        install({entry.key: 17});
        await expectLater(entry.value(), throwsA(isA<TypeError>()));
        expect(backend.calls, isEmpty);
        expect((await backend.durable())['flutter.${entry.key}'], 17);
      },
    );
  }
  test(
    'support cache remains opaque, including malformed and blank JSON',
    () async {
      for (final raw in ['{not JSON', '', '  ']) {
        await StorageService.setSupportRemoteConfigCache(raw);
        expect(await StorageService.getSupportRemoteConfigCache(), raw);
      }
      expect(backend.calls.length, 3);
    },
  );
  for (final raw in ['', '  ', ' version ', 'Version']) {
    test(
      'ignored getter checks blankness without rewriting: ${raw.length}/$raw',
      () async {
        install({_ignored: raw});
        expect(
          await StorageService.getIgnoredUpdateVersion(),
          raw.trim().isEmpty ? null : raw,
        );
        expect(backend.calls, isEmpty);
        expect((await backend.durable())['flutter.$_ignored'], raw);
      },
    );
  }
  for (final value in <String?>[null, '', '  ', ' version ']) {
    test('ignored setter removes blank or stores original: $value', () async {
      install({_ignored: 'before'});
      await StorageService.setIgnoredUpdateVersion(value);
      final remove = value == null || value.trim().isEmpty;
      expect(backend.calls, [
        (remove ? 'remove' : 'set', 'flutter.$_ignored', remove ? null : value),
      ]);
      expect(
        (await backend.durable()).containsKey('flutter.$_ignored'),
        !remove,
      );
    });
  }
  test(
    'dismissal preserves duplicates and exact order; no rewrite on existing ID',
    () async {
      install({
        _dismissed: <String>['A', ' A ', 'A'],
      });
      final copy = await StorageService.getDismissedDonationCampaignIds();
      copy.add('local');
      await StorageService.dismissDonationCampaign('A');
      expect(backend.calls, isEmpty);
      await StorageService.dismissDonationCampaign('a');
      await StorageService.dismissDonationCampaign('');
      expect(await StorageService.getDismissedDonationCampaignIds(), [
        'A',
        ' A ',
        'A',
        'a',
        '',
      ]);
      expect(backend.calls.length, 2);
    },
  );

  final writes =
      <
        ({
          String label,
          String key,
          Object? value,
          Future<void> Function() call,
        })
      >[
        (
          label: 'cache',
          key: _cache,
          value: '{new',
          call: () => StorageService.setSupportRemoteConfigCache('{new'),
        ),
        (
          label: 'dismiss',
          key: _dismissed,
          value: <String>['old', 'new'],
          call: () => StorageService.dismissDonationCampaign('new'),
        ),
        (
          label: 'auto',
          key: _auto,
          value: false,
          call: () => StorageService.setUpdateAutoCheckEnabled(false),
        ),
        (
          label: 'ignored',
          key: _ignored,
          value: ' new ',
          call: () => StorageService.setIgnoredUpdateVersion(' new '),
        ),
        (
          label: 'remove',
          key: _ignored,
          value: null,
          call: () => StorageService.setIgnoredUpdateVersion(null),
        ),
      ];
  for (final entry in writes) {
    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        'key-scoped held ${entry.label} $outcome retains device lifetime',
        () async {
          profiles();
          backend.heldKey = entry.key;
          backend.outcome = outcome;
          final result = entry.call();
          final observed = expectLater(
            result,
            outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
          );
          await backend.entered.future.timeout(_limit);
          expect(
            (await backend.durable())['flutter.${entry.key}'],
            initial[entry.key],
          );
          ProfileRuntime.publish(b);
          backend.release.complete();
          await observed;
          if (entry.label == 'dismiss') {
            expect(backend.calls, hasLength(1));
            expect(backend.calls.single.$1, 'set');
            expect(backend.calls.single.$2, 'flutter.${entry.key}');
            expect(backend.calls.single.$3, entry.value);
          } else {
            expect(backend.calls, [
              (
                entry.value == null ? 'remove' : 'set',
                'flutter.${entry.key}',
                entry.value,
              ),
            ]);
          }
          final cached = await SharedPreferences.getInstance();
          expect(cached.get(entry.key), entry.value);
          final durable = await backend.durable();
          expect(
            durable['flutter.${entry.key}'],
            outcome == 'ok' ? entry.value : initial[entry.key],
          );
          for (final key in _keys.difference({entry.key})) {
            expect(durable['flutter.$key'], initial[key]);
          }
          await expectShadows();
        },
      );
    }
  }
  for (final entry in readers.entries) {
    test(
      'held SDK acquisition ignores profile shadows: ${entry.key}',
      () async {
        profiles();
        backend.holdRead = true;
        final result = entry.value();
        await backend.entered.future.timeout(_limit);
        ProfileRuntime.publish(b);
        backend.release.complete();
        expect(await result, initial[entry.key]);
        expect(backend.calls, isEmpty);
        await expectShadows();
      },
    );
  }
}
