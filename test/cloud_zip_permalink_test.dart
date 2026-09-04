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
    SecretVault.debugReset(deviceIdOverride: 'zip-permalink-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD zipPermalink throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().zipPermalink(1),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().zipPermalink(1),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.zipPermalink(1),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry hits the TorBox adapter only', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      zipPermalinkUrl: 'https://tb.example/zip',
    );
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    expect(
      await CloudProviderRegistry.instance.zipPermalink(9),
      'https://tb.example/zip',
    );
    expect(torbox.zipPermalinkCount, 1);
  });

  test('production permalink includes torrent id and zip_link', () async {
    await StorageService.saveTorboxApiKey('tb-secret');
    final url = await const TorboxCloudProvider().zipPermalink(42);
    expect(url, contains('torrent_id=42'));
    expect(url, contains('zip_link=true'));
    expect(url, isNot(contains('web_id')));
  });
}
