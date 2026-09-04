import 'package:debrify/services/cloud/cloud_credentials.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/storage_key_ownership.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_key_sweep_test.dart' as sweep;

/// Cloud credential helpers must not invent unscoped keys in committed profile
/// mode. API-key writes in committed mode go through ProfileCredentialFacade
/// (resources), so this suite uses a non-secret StorageService write for the
/// orphan sweep and legacy mode for backup/magnet vs playback semantics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'cloud-sweep-device');
    ProfileRuntime.debugReset();
  });

  tearDown(ProfileRuntime.debugReset);

  test('a real settings write in committed mode is profile-scoped', () async {
    final scope = ProfileScope(
      profileId: 'cloud-sweep',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    await StorageService.setTvHomeStyle('atrium');

    final raw = await SharedPreferences.getInstance();
    await raw.reload();
    final orphan = <String>[];
    for (final key in raw.getKeys()) {
      if (!key.startsWith('p.') &&
          !DevicePreferences.allowedKeys.contains(key)) {
        orphan.add(key);
      }
    }
    expect(orphan, isEmpty);
    expect(
      raw.getKeys().any((k) => k.startsWith(scope.preferencePrefix)),
      isTrue,
    );
  });

  test('legacy backupSecrets round-trips API keys', () async {
    ProfileRuntime.initializeLegacy();
    await StorageService.saveApiKey('rd-key');
    await StorageService.saveTorboxApiKey('tb-key');
    await StorageService.savePremiumizeApiKey('pm-key');
    await StorageService.saveAllDebridApiKey('ad-key');
    await StorageService.setPikPakEmail('user@example.com');

    final secrets = await CloudCredentials.backupSecrets();
    expect(secrets['realDebridApiKey'], 'rd-key');
    expect(secrets['torboxApiKey'], 'tb-key');
    expect(secrets['premiumizeApiKey'], 'pm-key');
    expect(secrets['allDebridApiKey'], 'ad-key');
    expect((secrets['pikpak'] as Map)['email'], 'user@example.com');
  });

  test('playback configured vs magnet configured disagree on disabled RD', () async {
    ProfileRuntime.initializeLegacy();
    await StorageService.saveApiKey('rd-key');
    await StorageService.setRealDebridIntegrationEnabled(false);
    expect(
      await CloudCredentials.isPlaybackConfigured(CloudProviderId.debrid),
      isTrue,
    );
    expect(
      await CloudCredentials.isMagnetConfigured(CloudProviderId.debrid),
      isFalse,
    );
  });

  test('every CloudProviderId credential key is the historical prefs name', () {
    expect(
      {
        for (final id in CloudProviderId.values) id.playbackId: id.credentialKey,
      },
      {
        'debrid': 'real_debrid_api_key',
        'torbox': 'torbox_api_key',
        'premiumize': 'premiumize_api_key',
        'alldebrid': 'alldebrid_api_key',
        'pikpak': 'pikpak_email',
      },
    );
  });

  test('a discovered prefs name missing from byKey fails the sweep', () {
    expect(
      sweep.unownedDiscoveredPrefsKeys(),
      isEmpty,
      reason:
          'Mutation: drop any byKey entry for an inline literal (e.g. '
          'series_browser_dense_view) and this must fail.',
    );
    expect(
      StorageKeyOwnership.byKey.containsKey('series_browser_dense_view'),
      isTrue,
    );
    expect(
      StorageKeyOwnership.byKey['series_browser_dense_view'],
      StorageKeyStore.storageService,
    );
    expect(
      StorageKeyOwnership.byKey['home_tick_sources'],
      StorageKeyStore.homePrefs,
    );
  });
}
