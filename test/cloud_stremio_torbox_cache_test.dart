import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/stremio_tv_torbox_cache.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

Torrent _t({String hash = 'abc'}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: 'Show.S01E01.mkv',
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'stremio-torbox-cache-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('only TorBox supports cachedHashes', () {
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.cachedHashes),
      isTrue,
    );
    expect(
      const RealDebridCloudProvider().supports(CloudPortFeature.cachedHashes),
      isFalse,
    );
  });

  test('production RD checkCachedHashes throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().checkCachedHashes(const ['abc']),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing TorBox key throws CloudMissingApiKey', () async {
    await expectLater(
      const TorboxCloudProvider().checkCachedHashes(const ['abc']),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no TorBox adapter returns empty', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    expect(
      await CloudProviderRegistry.instance.checkCachedHashes(const ['abc']),
      isEmpty,
    );
  });

  test('registry hits the TorBox adapter only', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    expect(
      await CloudProviderRegistry.instance.checkCachedHashes(const ['abc']),
      {'abc'},
    );
    expect(torbox.cachedHashesCount, 1);
    expect(debrid.cachedHashesCount, 0);
  });

  test('auto load is empty without a key and does not call the adapter', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    expect(await StremioTvTorboxCache.load([_t()]), isEmpty);
    expect(torbox.cachedHashesCount, 0);
  });

  test('auto load returns adapter hashes when a key is saved', () async {
    await StorageService.saveTorboxApiKey('tb-key');
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    expect(await StremioTvTorboxCache.load([_t(hash: 'ABC')]), {'abc'});
    expect(torbox.lastCachedHashQuery, ['abc']);
  });

  test('auto load maps HTTP errors to empty, unlike explicit-provider filter', () async {
    await StorageService.saveTorboxApiKey('tb-key');
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      error: Exception('torbox down'),
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    expect(await StremioTvTorboxCache.load([_t()]), isEmpty);
    expect(torbox.cachedHashesCount, 1);
    await expectLater(
      CloudProviderRegistry.instance.checkCachedHashes(const ['abc']),
      throwsA(isA<Exception>()),
    );
  });
}
