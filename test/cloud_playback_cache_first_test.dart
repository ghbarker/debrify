import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/playback_cache_first.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

Torrent _t(String hash) => Torrent(
  rowid: 0,
  infohash: hash,
  name: hash,
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'test',
);

void main() {
  tearDown(CloudProviderRegistry.debugReset);

  test('non cache providers leave order alone and do not call adapters', () async {
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'b'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([torbox]);
    final candidates = [_t('a'), _t('b')];
    expect(await PlaybackCacheFirst.reorder('debrid', candidates), candidates);
    expect(torbox.cachedHashesCount, 0);
  });

  test('TorBox hits move to the front; misses stay', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(
        id: CloudProviderId.torbox,
        cachedHashes: const {'b'},
      ),
    ]);
    final a = _t('a');
    final b = _t('b');
    final c = _t('c');
    expect(await PlaybackCacheFirst.reorder('torbox', [a, b, c]), [b, a, c]);
  });

  test('Premiumize zips bools; empty cache returns the original list', () async {
    final premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      cacheFlags: const [false, false],
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([premiumize]);
    final candidates = [_t('a'), _t('b')];
    expect(
      await PlaybackCacheFirst.reorder('premiumize', candidates),
      same(candidates),
    );
    expect(premiumize.lastCacheQuery, ['a', 'b']);
  });

  test('adapter errors return the original order', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(
        id: CloudProviderId.torbox,
        error: Exception('down'),
      ),
    ]);
    final candidates = [_t('a'), _t('b')];
    expect(await PlaybackCacheFirst.reorder('torbox', candidates), candidates);
  });
}
