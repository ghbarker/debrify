import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_playback_result.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_provider.dart';

Torrent _t() => Torrent(
  rowid: 0,
  infohash: 'abc',
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
  tearDown(CloudProviderRegistry.debugReset);

  FakeCloudProvider fake(
    CloudProviderId id, {
    bool configured = true,
    Object? error,
    CloudPlaybackResult? result,
  }) => FakeCloudProvider(
    id: id,
    configured: configured,
    error: error,
    result: result,
  );

  test('unknown provider throws', () {
    expect(
      () => CloudProviderRegistry.instance.addMagnet(
        'not-a-provider',
        'magnet:?xt=urn:btih:abc',
        _t(),
      ),
      throwsA(isA<Exception>()),
    );
  });

  for (final id in CloudProviderId.values) {
    test('${id.playbackId}: missing config is observable', () async {
      final p = fake(id, configured: false);
      CloudProviderRegistry.instance = CloudProviderRegistry([p]);
      expect(await CloudProviderRegistry.instance.isConfigured(id.playbackId), isFalse);
    });

    test('${id.playbackId}: empty file list still returns a result object', () async {
      final p = fake(
        id,
        result: CloudPlaybackResult(
          title: 'Show.S01E01.mkv',
          playUrl: null,
          downloadUrls: const [],
        ),
      );
      CloudProviderRegistry.instance = CloudProviderRegistry([p]);
      final r = await CloudProviderRegistry.instance.addMagnet(
        id.playbackId,
        'magnet:?xt=urn:btih:abc',
        _t(),
      );
      expect(r.playUrl, isNull);
      expect(r.hasPlaylist, isFalse);
      expect(p.addCount, 1);
    });
  }

  test('TorBox cache miss surfaces TorboxNotCached', () async {
    final p = fake(CloudProviderId.torbox, error: const TorboxNotCached());
    CloudProviderRegistry.instance = CloudProviderRegistry([p]);
    expect(
      () => CloudProviderRegistry.instance.addMagnet(
        'torbox',
        'magnet:?xt=urn:btih:abc',
        _t(),
      ),
      throwsA(isA<TorboxNotCached>()),
    );
  });

  test('Premiumize cache miss surfaces PremiumizeNotCached', () async {
    final p = fake(
      CloudProviderId.premiumize,
      error: const PremiumizeNotCached(),
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([p]);
    expect(
      () => CloudProviderRegistry.instance.addMagnet(
        'premiumize',
        'magnet:?xt=urn:btih:abc',
        _t(),
      ),
      throwsA(isA<PremiumizeNotCached>()),
    );
  });

  test('malformed HTTP error is not swallowed by the registry', () async {
    final p = fake(CloudProviderId.alldebrid, error: Exception('429'));
    CloudProviderRegistry.instance = CloudProviderRegistry([p]);
    expect(
      () => CloudProviderRegistry.instance.addMagnet(
        'alldebrid',
        'magnet:?xt=urn:btih:abc',
        _t(),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
