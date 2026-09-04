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
    SecretVault.debugReset(deviceIdOverride: 'magnet-torrent-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('production RD createMagnetTorrent throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().createMagnetTorrent(
        'magnet:x',
        addOnlyIfCached: true,
      ),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().createMagnetTorrent(
        'magnet:x',
        addOnlyIfCached: true,
      ),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.createMagnetTorrent(
        'magnet:x',
        addOnlyIfCached: true,
      ),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry hits the TorBox adapter with cached-only then not', () async {
    final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
    final premiumize = FakeCloudProvider(id: CloudProviderId.premiumize);
    CloudProviderRegistry.instance = CloudProviderRegistry([
      torbox,
      premiumize,
    ]);
    await CloudProviderRegistry.instance.createMagnetTorrent(
      'magnet:tb',
      addOnlyIfCached: true,
    );
    await CloudProviderRegistry.instance.createMagnetTorrent(
      'magnet:tb2',
      addOnlyIfCached: false,
    );
    expect(torbox.createMagnetTorrentCount, 2);
    expect(torbox.lastTransferMagnet, 'magnet:tb2');
    expect(torbox.lastAddOnlyIfCached, isFalse);
    expect(premiumize.createMagnetTorrentCount, 0);
  });
}
