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
    SecretVault.debugReset(deviceIdOverride: 'file-download-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD fileDownloadLink throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().fileDownloadLink(1, 2),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().fileDownloadLink(1, 2),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.fileDownloadLink(1, 2),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry hits the TorBox adapter only', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      fileDownloadUrl: 'https://tb.example/file',
    );
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    expect(
      await CloudProviderRegistry.instance.fileDownloadLink(9, 3),
      'https://tb.example/file',
    );
    expect(torbox.fileDownloadLinkCount, 1);
    expect(torbox.lastFileDownloadTorrentId, 9);
    expect(torbox.lastFileDownloadFileId, 3);
    expect(debrid.fileDownloadLinkCount, 0);
  });
}
