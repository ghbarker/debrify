import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/tmdb_credential_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ControlledCipher extends MemoryDeviceSecretCipher {
  Completer<void>? entered;
  Completer<void>? release;
  bool failOpen = false;
  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    if (entered != null) {
      entered!.complete();
      await release!.future;
    }
    return super.seal(plaintext, associatedData: associatedData);
  }

  @override
  Future<List<int>> open(String envelope, {required List<int> associatedData}) {
    if (failOpen) throw StateError('vault temporarily unavailable');
    return super.open(envelope, associatedData: associatedData);
  }
}

void main() {
  late Directory temporary;
  late ProfileRegistry registry;
  late _ControlledCipher cipher;
  late String a;
  late String b;
  var epoch = 1;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    TmdbCredentialService.resetForTesting();
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('tmdb-profile-test-');
    registry = await ProfileRegistry.open(
      path: p.join(temporary.path, 'profiles.db'),
    );
    a = (await registry.createProfile(
      name: 'A',
      role: UserProfileRole.admin,
    )).id;
    b = (await registry.createProfile(
      name: 'B',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: a,
      migratedLegacyInstall: false,
    );
    cipher = _ControlledCipher();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    epoch = 1;
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: a, dataGeneration: 1, sessionEpoch: epoch),
    );
    await TmdbCredentialService.initialize();
  });
  tearDown(() async {
    TmdbCredentialService.resetForTesting();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporary.delete(recursive: true);
  });
  Future<void> switchTo(String id, {int generation = 1}) async {
    await registry.setActiveProfile(id);
    ProfileRuntime.publish(
      ProfileScope(
        profileId: id,
        dataGeneration: generation,
        sessionEpoch: ++epoch,
      ),
    );
    await TmdbCredentialService.initialize();
  }

  test(
    'resource secret is profile isolated and absent from preferences',
    () async {
      await TmdbCredentialService.save('a-secret');
      final aSnapshot = await TmdbCredentialService.capture();
      expect(aSnapshot.token, 'a-secret');
      final id = await registry.getBoundResourceId(
        a,
        TmdbCredentialService.slot,
      );
      expect(id, isNotNull);
      expect(await registry.getGrant(b, id!), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((key) => key.contains('tmdb')), isFalse);
      await switchTo(b);
      expect(
        (await TmdbCredentialService.capture()).token,
        TmdbCredentialService.buildToken.trim(),
      );
      await TmdbCredentialService.save('b-secret');
      await switchTo(a);
      expect((await TmdbCredentialService.capture()).token, 'a-secret');
      await expectLater(aSnapshot.validate(), throwsStateError);
      final beforeRestore = await TmdbCredentialService.capture();
      await switchTo(a, generation: 2);
      await expectLater(beforeRestore.validate(), throwsStateError);
      await TmdbCredentialService.save('');
      expect(
        (await TmdbCredentialService.capture()).token,
        TmdbCredentialService.buildToken.trim(),
      );
      await switchTo(b);
      expect((await TmdbCredentialService.capture()).token, 'b-secret');
    },
  );

  test(
    'profile switch during encryption cannot save into either profile',
    () async {
      cipher.entered = Completer<void>();
      cipher.release = Completer<void>();
      final save = TmdbCredentialService.save('must-not-publish');
      final rejected = expectLater(save, throwsA(anything));
      await cipher.entered!.future;
      await switchTo(b);
      cipher.release!.complete();
      await rejected;
      expect(
        await registry.getBoundResourceId(a, TmdbCredentialService.slot),
        isNull,
      );
      expect(
        await registry.getBoundResourceId(b, TmdbCredentialService.slot),
        isNull,
      );
    },
  );

  test(
    'failed scope refresh recovers on next capture without another switch',
    () async {
      await TmdbCredentialService.save('a-secret');
      await switchTo(b);
      cipher.failOpen = true;
      await switchTo(a);
      await expectLater(TmdbCredentialService.capture(), throwsA(anything));
      cipher.failOpen = false;
      expect((await TmdbCredentialService.capture()).token, 'a-secret');
    },
  );

  test(
    'build fallback cannot bypass discovery permission without a resource',
    () async {
      final actor = await ProfileAuthorizationContext.capture(registry);
      final restricted = await registry.createProfile(
        name: 'Restricted',
        role: UserProfileRole.member,
        policy: const ProfilePolicy(enabled: {}),
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );
      await switchTo(restricted.id);
      expect(
        await registry.getBoundResourceId(
          restricted.id,
          TmdbCredentialService.slot,
        ),
        isNull,
      );
      var requests = 0;
      final repository = TmdbMetadataRepository(
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.get('movie/1'),
        throwsA(isA<ResourceAuthorizationException>()),
      );
      expect(requests, 0);
    },
  );
}
