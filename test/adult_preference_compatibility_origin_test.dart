import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/social_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Actual public origin 064a03be; no replacement policy/registry or new hooks.
// Holds SDK acquisition only. Exact held registry lookup remains unproved.
const _limit = Duration(seconds: 5);

class _Route {
  const _Route(this.key, this.unsafe, this.read, this.write);
  final String key;
  final bool unsafe;
  final Future<bool> Function() read;
  final Future<void> Function(bool) write;
}

final _routes = [
  _Route(
    'engine_tv_global_avoid_nsfw',
    false,
    () => SettingsManager().getGlobalAvoidNsfw(false),
    SettingsManager().setGlobalAvoidNsfw,
  ),
  _Route(
    'debrify_tv_avoid_nsfw',
    false,
    DebrifyTvPrefs.getDebrifyTvAvoidNsfw,
    DebrifyTvPrefs.saveDebrifyTvAvoidNsfw,
  ),
  _Route(
    'reddit_allow_nsfw',
    true,
    SocialPrefs.getRedditAllowNsfw,
    SocialPrefs.setRedditAllowNsfw,
  ),
  _Route(
    'lemmy_allow_nsfw',
    true,
    SocialPrefs.getLemmyAllowNsfw,
    SocialPrefs.setLemmyAllowNsfw,
  ),
];

class _Prefs extends InMemorySharedPreferencesStore {
  _Prefs(super.data) : super.withData();
  int reads = 0;
  final writes = <(String, Object)>[];
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    reads++;
    if (hold) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    writes.add((key, value));
    return super.setValue(type, key, value);
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Prefs backend;
  ProfileRegistry? registry;
  Directory? directory;
  bool closed = false;
  late String allowed;
  late String denied;
  late String disabled;
  ProfileScope scope(String id, [int epoch = 1]) =>
      ProfileScope(profileId: id, dataGeneration: 1, sessionEpoch: epoch);
  void install(Map<String, Object> data) {
    SharedPreferences.resetStatic();
    backend = _Prefs({
      for (final e in data.entries) 'flutter.${e.key}': e.value,
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  Future<void> canonical() async {
    directory = await Directory.systemTemp.createTemp('adult-public-origin-');
    registry = await ProfileRegistry.open(
      path: '${directory!.path}/profiles.db',
    );
    allowed = (await registry!.createProfile(
      name: 'Owner',
      role: UserProfileRole.admin,
    )).id;
    denied = (await registry!.createProfile(
      name: 'Denied',
      role: UserProfileRole.member,
      policy: const ProfilePolicy(enabled: {}),
    )).id;
    disabled = (await registry!.createProfile(
      name: 'Disabled',
      role: UserProfileRole.member,
      disabled: true,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.member),
    )).id;
    await registry!.commitBootstrap(
      activeProfileId: allowed,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(scope(allowed));
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    closed = false;
    install({});
  });
  tearDown(() async {
    if (!backend.release.isCompleted) backend.release.complete();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    if (!closed) await registry?.close();
    registry = null;
    await directory?.delete(recursive: true);
    directory = null;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });
  test('uninitialized public authority permits without registry', () async {
    ProfileRuntime.debugReset();
    expect(await StorageService.profileAllowsAdultContent(), isTrue);
    expect(backend.reads, 0);
  });
  for (final route in _routes) {
    test('${route.key}: uninitialized preference routes still throw', () async {
      ProfileRuntime.debugReset();
      await expectLater(route.read(), throwsA(isA<StateError>()));
      await expectLater(route.write(route.unsafe), throwsA(isA<StateError>()));
      expect(backend.reads, 0);
      expect(backend.writes, isEmpty);
    });
    for (final mode in [
      'legacy',
      'allow',
      'deny',
      'missing',
      'disabled',
      'maintenance',
      'error',
    ]) {
      test('${route.key}: real public $mode authority and coercion', () async {
        String physical = route.key;
        if (mode != 'legacy') {
          await canonical();
          final id = mode == 'deny'
              ? denied
              : mode == 'missing'
              ? 'missing-profile'
              : mode == 'disabled'
              ? disabled
              : allowed;
          ProfileRuntime.publish(scope(id, 2));
          physical = scope(id).preferenceKey(route.key);
          if (mode == 'maintenance') ProfileRuntime.enterMaintenance();
          if (mode == 'error') {
            await registry!.close();
            closed = true;
          }
        }
        install({physical: route.unsafe, 'adult_sentinel': 'untouched'});
        final permits = [
          'legacy',
          'allow',
          'disabled',
          'maintenance',
        ].contains(mode);
        final expected = permits ? route.unsafe : !route.unsafe;
        expect(await StorageService.profileAllowsAdultContent(), permits);
        expect(await route.read(), expected);
        expect(
          backend.reads,
          permits ? 1 : 0,
          reason:
              'Denied getters must short-circuit before preference acquisition',
        );
        expect(backend.writes, isEmpty);
        expect((await backend.durable())['flutter.$physical'], route.unsafe);
        await route.write(route.unsafe);
        expect(backend.writes, [('flutter.$physical', expected)]);
        expect((await backend.durable())['flutter.$physical'], expected);
        expect(
          (await backend.durable())['flutter.adult_sentinel'],
          'untouched',
        );
      });
    }
    for (final writing in [false, true]) {
      test(
        '${route.key}: held SDK capture writing=$writing exposes authority order',
        () async {
          await canonical();
          final a = scope(allowed);
          final b = scope(denied, 2);
          install({
            a.preferenceKey(route.key): route.unsafe,
            b.preferenceKey(route.key): route.unsafe,
            route.key: 'legacy sentinel',
          });
          backend.hold = true;
          final Future<Object?> pending = writing
              ? route.write(route.unsafe).then<Object?>((_) => null)
              : route.read();
          await backend.entered.future.timeout(_limit);
          ProfileRuntime.publish(b);
          backend.release.complete();
          // Getter already authorized A before held acquisition and reads B's raw value.
          // Setter acquires B after release, then checks denied B and coerces the write.
          expect(await pending, writing ? null : route.unsafe);
          final expected = writing ? !route.unsafe : route.unsafe;
          expect(
            backend.writes,
            writing
                ? [('flutter.${b.preferenceKey(route.key)}', expected)]
                : isEmpty,
          );
          final data = await backend.durable();
          expect(data['flutter.${a.preferenceKey(route.key)}'], route.unsafe);
          expect(data['flutter.${b.preferenceKey(route.key)}'], expected);
          expect(data['flutter.${route.key}'], 'legacy sentinel');
        },
      );
    }
  }
}
