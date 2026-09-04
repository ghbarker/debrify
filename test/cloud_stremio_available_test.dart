import 'package:debrify/services/cloud/cloud_credentials.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'stremio-available-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  test('RD key without integration is Stremio-available, not magnet', () async {
    await StorageService.saveApiKey('rd-key');
    await StorageService.setRealDebridIntegrationEnabled(false);
    expect(
      await CloudCredentials.isStremioAvailable(CloudProviderId.debrid),
      isTrue,
    );
    expect(
      await CloudCredentials.isPlaybackConfigured(CloudProviderId.debrid),
      isTrue,
    );
    expect(
      await CloudCredentials.isMagnetConfigured(CloudProviderId.debrid),
      isFalse,
    );
  });

  test('PM key without integration is playback, not Stremio', () async {
    await StorageService.savePremiumizeApiKey('pm-key');
    await StorageService.setPremiumizeIntegrationEnabled(false);
    expect(
      await CloudCredentials.isPlaybackConfigured(CloudProviderId.premiumize),
      isTrue,
    );
    expect(
      await CloudCredentials.isStremioAvailable(CloudProviderId.premiumize),
      isFalse,
    );
    expect(
      await CloudCredentials.isMagnetConfigured(CloudProviderId.premiumize),
      isFalse,
    );
  });

  test('PikPak is enabled-only, not email', () async {
    await StorageService.setPikPakEnabled(true);
    expect(
      await CloudCredentials.isStremioAvailable(CloudProviderId.pikpak),
      isTrue,
    );
    expect(await CloudCredentials.apiKey(CloudProviderId.pikpak), isNull);
  });

  test('picker order is PikPak before Premiumize; labels are catalogChoice', () async {
    await StorageService.saveApiKey('rd-key');
    await StorageService.saveTorboxApiKey('tb-key');
    await StorageService.setPikPakEnabled(true);
    await StorageService.savePremiumizeApiKey('pm-key');
    await StorageService.setPremiumizeIntegrationEnabled(true);
    await StorageService.saveAllDebridApiKey('ad-key');
    await StorageService.setAllDebridIntegrationEnabled(true);

    expect(CloudProviderId.fromPlaybackId('realdebrid'), isNull);
    expect(CloudProviderId.playbackPrecedence, [
      CloudProviderId.debrid,
      CloudProviderId.torbox,
      CloudProviderId.premiumize,
      CloudProviderId.alldebrid,
      CloudProviderId.pikpak,
    ]);

    final rows = await CloudCredentials.stremioPickerChoices();
    expect(rows.map((e) => e.key).toList(), [
      'realdebrid',
      'torbox',
      'pikpak',
      'premiumize',
      'alldebrid',
    ]);
    expect(rows.map((e) => e.value).toList(), [
      'Real-Debrid',
      'TorBox',
      'PikPak',
      'Premiumize',
      'AllDebrid',
    ]);
    expect(rows.singleWhere((e) => e.key == 'realdebrid').value, isNot('Real Debrid'));
  });
}
