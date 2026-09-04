import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/stremio_tv_cache_filter.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

Torrent _torrent({
  String hash = 'abc',
  StreamType type = StreamType.torrent,
}) => Torrent(
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
  streamType: type,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'stremio-cache-filter-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('other providers are a no-op', () async {
    final sources = [_torrent()];
    expect(
      await StremioTvCacheFilter.apply(
        provider: 'realdebrid',
        sources: sources,
      ),
      sources,
    );
  });

  test('no TorBox key skips the filter and does not call the adapter', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    final sources = [_torrent()];
    expect(
      await StremioTvCacheFilter.apply(provider: 'torbox', sources: sources),
      sources,
    );
    expect(torbox.cachedHashesCount, 0);
  });

  test('explicit TorBox keeps directs and only cached torrents', () async {
    await StorageService.saveTorboxApiKey('tb-key');
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    final direct = _torrent(hash: 'url', type: StreamType.directUrl);
    final hit = _torrent(hash: 'ABC');
    final miss = _torrent(hash: 'def');
    final filtered = await StremioTvCacheFilter.apply(
      provider: 'torbox',
      sources: [direct, hit, miss],
    );
    expect(filtered, [direct, hit]);
    expect(torbox.lastCachedHashQuery, ['abc', 'def']);
  });

  test('no Premiumize key skips the zip filter', () async {
    final premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      cacheFlags: const [true],
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([premiumize]);
    final sources = [_torrent()];
    expect(
      await StremioTvCacheFilter.apply(
        provider: 'premiumize',
        sources: sources,
      ),
      sources,
    );
    expect(premiumize.checkCacheCount, 0);
  });

  test('explicit Premiumize zips positional bools onto hashes', () async {
    await StorageService.savePremiumizeApiKey('pm-key');
    final premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      cacheFlags: const [false, true],
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([premiumize]);
    final miss = _torrent(hash: 'aaa');
    final hit = _torrent(hash: 'bbb');
    final filtered = await StremioTvCacheFilter.apply(
      provider: 'premiumize',
      sources: [miss, hit],
    );
    expect(filtered, [hit]);
    expect(premiumize.lastCacheQuery, ['aaa', 'bbb']);
  });

  test('cancel before HTTP aborts without calling the adapter', () async {
    await StorageService.saveTorboxApiKey('tb-key');
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    expect(
      await StremioTvCacheFilter.apply(
        provider: 'torbox',
        sources: [_torrent()],
        isCancelled: () => true,
      ),
      isNull,
    );
    expect(torbox.cachedHashesCount, 0);
  });
}
