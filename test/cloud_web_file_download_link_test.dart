import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'web-file-download-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD webFileDownloadLink throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().webFileDownloadLink(1, 2),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().webFileDownloadLink(1, 2),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.webFileDownloadLink(1, 2),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry hits the TorBox adapter only', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      webFileDownloadUrl: 'https://tb.example/webfile',
    );
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    expect(
      await CloudProviderRegistry.instance.webFileDownloadLink(7, 3),
      'https://tb.example/webfile',
    );
    expect(torbox.webFileDownloadLinkCount, 1);
    expect(torbox.lastWebZipId, 7);
    expect(torbox.lastWebFileId, 3);
    expect(debrid.webFileDownloadLinkCount, 0);
  });
}
