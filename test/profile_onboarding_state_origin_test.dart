import 'dart:async';
import 'dart:io';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Unchanged real origin 25fbc2611792d93c28b5a5f608cd252606f3f0ff.
// Actual public APIs and SQLite registry; only preference transport is controlled.
// Completion of an already-entered remove need not revalidate the runtime.
// These pins preserve that quirk, not a profile-safety/serialization guarantee.
const _key = 'initial_setup_complete_v1';

class _Transport extends InMemorySharedPreferencesStore {
  _Transport() : super.withData({});
  Future<void> Function()? beforeRemove;
  String? mode;
  final attempts = <String>[];
  @override
  Future<bool> remove(String key) async {
    attempts.add('remove:$key');
    await beforeRemove?.call();
    if (mode == 'false') return false;
    if (mode == 'throw') throw StateError('transport refusal');
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    attempts.add('set:$type:$key:$value');
    if (mode == 'false') return false;
    if (mode == 'throw') throw StateError('transport refusal');
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late UserProfile admin;
  late _Transport transport;
  late SharedPreferencesStorePlatform previous;

  ProfileScope scope(UserProfile profile, int epoch) => ProfileScope(
    profileId: profile.id,
    dataGeneration: profile.visibleDataGeneration,
    sessionEpoch: epoch,
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    transport = _Transport();
    SharedPreferencesStorePlatform.instance = transport;
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-onboarding-state-test-',
    );
    final documents = await Directory(
      p.join(temporaryDirectory.path, 'documents'),
    ).create(recursive: true);
    final support = await Directory(
      p.join(temporaryDirectory.path, 'support'),
    ).create(recursive: true);
    final cache = await Directory(
      p.join(temporaryDirectory.path, 'cache'),
    ).create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: true,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: true,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(scope(admin, 1));
    ProfileBootstrap.debugInstallRegistry(registry);
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    AppStorage.debugReset();
    await registry.close();
    SharedPreferencesStorePlatform.instance = previous;
    SharedPreferences.resetStatic();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> seed(Object value) async {
    final prefs = await ProfilePreferences.instance();
    if (value is bool) {
      await prefs.setBool(_key, value);
    } else {
      await prefs.setString(_key, value as String);
    }
    transport.attempts.clear();
  }

  Future<bool> canonical() async =>
      (await registry.getProfile(admin.id))!.setupComplete;
  Future<Object?> durable() async =>
      (await transport.getAll())['flutter.p.${admin.id}.g.1.$_key'];

  test(
    'legacy absent defaults false and true/false remain physical bools',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      expect(await StorageService.isInitialSetupComplete(), isFalse);
      for (final value in [true, false]) {
        await StorageService.setInitialSetupComplete(value);
        expect(await StorageService.isInitialSetupComplete(), value);
        expect((await transport.getAll())['flutter.$_key'], value);
        expect(await canonical(), isTrue);
      }
    },
  );

  for (final mode in ['false', 'throw']) {
    test('legacy write $mode keeps SDK cache but not durable state', () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      transport.mode = mode;
      final write = StorageService.setInitialSetupComplete(true);
      if (mode == 'throw') {
        await expectLater(write, throwsStateError);
      } else {
        await write;
      }
      expect(await StorageService.isInitialSetupComplete(), isTrue);
      expect((await transport.getAll())['flutter.$_key'], isNull);
      expect(await canonical(), isTrue);
    });
  }

  for (final committed in [false, true]) {
    test(
      'wrong physical string throws without normalization committed=$committed',
      () async {
        if (!committed) {
          ProfileRuntime.debugReset();
          ProfileRuntime.initializeLegacy();
        }
        await seed('false');
        await expectLater(
          StorageService.isInitialSetupComplete(),
          throwsA(isA<TypeError>()),
        );
        expect((await ProfilePreferences.instance()).get(_key), 'false');
        expect(transport.attempts, isEmpty);
        expect(await canonical(), isTrue);
      },
    );
  }

  test(
    'absent compatibility reads registry without transport writes',
    () async {
      expect(await StorageService.isInitialSetupComplete(), isTrue);
      expect(transport.attempts, isEmpty);
    },
  );

  for (final reader in [true, false]) {
    for (final value in [true, false]) {
      test(
        '${reader ? 'read' : 'write'} value=$value preserves canonical/remove order',
        () async {
          await seed(value);
          final before = await registry.getProfile(admin.id);
          final observed = <bool>[];
          transport.beforeRemove = () async {
            observed.add(await canonical());
          };
          if (reader) {
            expect(await StorageService.isInitialSetupComplete(), value);
          } else {
            await StorageService.setInitialSetupComplete(value);
          }
          expect(observed, [reader ? value : true]);
          expect(await canonical(), value);
          expect(await durable(), isNull);
          expect(
            (await ProfilePreferences.instance()).containsKey(_key),
            isFalse,
          );
          expect(transport.attempts, [
            'remove:flutter.p.${admin.id}.g.1.$_key',
          ]);
          expect(
            (await registry.getProfile(admin.id))!.authorizationRevision,
            before!.authorizationRevision,
          );
        },
      );
    }
    for (final mode in ['false', 'throw']) {
      test(
        '${reader ? 'read' : 'write'} remove $mode preserves failure prefix',
        () async {
          await seed(false);
          transport.mode = mode;
          final call = reader
              ? StorageService.isInitialSetupComplete()
              : StorageService.setInitialSetupComplete(false);
          await expectLater(
            call,
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                mode == 'false'
                    ? 'Could not retire compatibility onboarding state'
                    : 'transport refusal',
              ),
            ),
          );
          expect(await canonical(), reader ? false : true);
          expect(await durable(), isFalse);
          // SharedPreferences eagerly removes its cache even if transport refuses.
          expect(
            (await ProfilePreferences.instance()).containsKey(_key),
            isFalse,
          );
          expect(transport.attempts, [
            'remove:flutter.p.${admin.id}.g.1.$_key',
          ]);
        },
      );
    }
    test(
      '${reader ? 'read' : 'write'} held remove then generation/session change',
      () async {
        await seed(false);
        final entered = Completer<void>();
        final release = Completer<void>();
        transport.beforeRemove = () async {
          entered.complete();
          await release.future;
        };
        final call = reader
            ? StorageService.isInitialSetupComplete()
            : StorageService.setInitialSetupComplete(false);
        final expectation = reader
            ? expectLater(call, completion(isFalse))
            : expectLater(call, throwsStateError);
        try {
          await entered.future.timeout(const Duration(seconds: 5));
          expect(await canonical(), reader ? false : true);
          ProfileRuntime.publish(
            ProfileScope(
              profileId: admin.id,
              dataGeneration: 2,
              sessionEpoch: 2,
            ),
          );
          release.complete();
          await expectation;
          expect(await durable(), isNull);
          expect(
            (await ProfilePreferences.instance()).containsKey(_key),
            isFalse,
          );
          expect(await canonical(), reader ? false : true);
        } finally {
          if (!release.isCompleted) release.complete();
          await expectation;
        }
      },
    );
  }
  test(
    'invalid captured generation is rejected before compatibility removal',
    () async {
      await seed(false);
      ProfileRuntime.publish(
        ProfileScope(profileId: admin.id, dataGeneration: 2, sessionEpoch: 1),
      );
      await expectLater(
        StorageService.isInitialSetupComplete(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Active profile onboarding state is unavailable',
          ),
        ),
      );
      expect(await durable(), isFalse);
      expect(await canonical(), isTrue);
      expect(transport.attempts, isEmpty);
    },
  );
}
