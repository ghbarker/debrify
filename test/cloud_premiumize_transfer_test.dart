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
    SecretVault.debugReset(deviceIdOverride: 'pm-transfer-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD createCloudTransfer throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().createCloudTransfer('magnet:?xt=urn:btih:abc'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing Premiumize key throws CloudMissingApiKey', () async {
    await expectLater(
      const PremiumizeCloudProvider().createCloudTransfer('magnet:?xt=urn:btih:abc'),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry hits the Premiumize adapter only', () async {
    final premiumize = FakeCloudProvider(id: CloudProviderId.premiumize);
    final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox, premiumize]);
    await CloudProviderRegistry.instance.createCloudTransfer('magnet:x');
    expect(premiumize.createCloudTransferCount, 1);
    expect(premiumize.lastTransferMagnet, 'magnet:x');
    expect(torbox.createCloudTransferCount, 0);
  });
}
