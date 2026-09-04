import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'web-zip-permalink-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD webZipPermalink throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().webZipPermalink(1),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().webZipPermalink(1),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.webZipPermalink(1),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry hits the TorBox adapter only', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      webZipPermalinkUrl: 'https://tb.example/webzip',
    );
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    expect(
      await CloudProviderRegistry.instance.webZipPermalink(7),
      'https://tb.example/webzip',
    );
    expect(torbox.webZipPermalinkCount, 1);
    expect(torbox.lastWebZipId, 7);
    expect(debrid.webZipPermalinkCount, 0);
  });

  test('production permalink includes web_id and not torrent_id', () async {
    await StorageService.saveTorboxApiKey('tb-secret');
    final url = await const TorboxCloudProvider().webZipPermalink(42);
    expect(url, contains('web_id=42'));
    expect(url, contains('zip_link=true'));
    expect(url, isNot(contains('torrent_id')));
  });
}
