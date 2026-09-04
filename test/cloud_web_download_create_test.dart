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
    SecretVault.debugReset(deviceIdOverride: 'web-download-create-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD createWebDownload throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().createWebDownload('https://ex'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().createWebDownload('https://ex'),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.createWebDownload('https://ex'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry hits the TorBox adapter with name and password', () async {
    final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    await CloudProviderRegistry.instance.createWebDownload(
      'https://ex/file',
      name: 'clip',
      password: 'pw',
    );
    expect(torbox.createWebDownloadCount, 1);
    expect(torbox.lastWebDownloadLink, 'https://ex/file');
    expect(torbox.lastWebDownloadName, 'clip');
    expect(torbox.lastWebDownloadPassword, 'pw');
    expect(debrid.createWebDownloadCount, 0);
  });
}
