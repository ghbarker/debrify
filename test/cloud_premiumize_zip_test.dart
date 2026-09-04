import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/premiumize_cloud_provider.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'pm-zip-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD createTransferZip throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().createTransferZip('magnet:?xt=urn:btih:abc'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing Premiumize key throws CloudMissingApiKey', () async {
    await expectLater(
      const PremiumizeCloudProvider().createTransferZip('magnet:?xt=urn:btih:abc'),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry hits the Premiumize adapter only', () async {
    final premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      transferZipUrl: 'https://pm.example/zip',
    );
    final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox, premiumize]);
    expect(
      await CloudProviderRegistry.instance.createTransferZip('magnet:x'),
      'https://pm.example/zip',
    );
    expect(premiumize.createTransferZipCount, 1);
    expect(torbox.createTransferZipCount, 0);
  });
}
