import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
import 'package:debrify/services/cloud/stremio_torrent_resolve_args.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

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

MagicTvPrepareRequest _req() => MagicTvPrepareRequest(
  torrent: _t(),
  log: (_) {},
  seenKeys: <String>{},
  sizeMatchesBytes: (_) => true,
  hasSizeFilter: false,
  minVideoSizeBytes: 50 * 1024 * 1024,
);

void main() {
  tearDown(CloudProviderRegistry.debugReset);

  late FakeCloudProvider debrid;
  late FakeCloudProvider torbox;
  late FakeCloudProvider pikpak;
  late FakeCloudProvider premiumize;
  late FakeCloudProvider alldebrid;

  setUp(() {
    debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      magicTvResult: const MagicTvPrepared(
        streamUrl: 'https://tb/tv',
        title: 'ep',
        hasMore: true,
      ),
    );
    pikpak = FakeCloudProvider(
      id: CloudProviderId.pikpak,
      magicTvResult: const MagicTvPrepared(
        streamUrl: 'https://pp/tv',
        title: 'ep',
        hasMore: false,
      ),
    );
    premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      magicTvResult: const MagicTvPrepared(
        streamUrl: 'https://pm/tv',
        title: 'ep',
        hasMore: false,
      ),
    );
    alldebrid = FakeCloudProvider(id: CloudProviderId.alldebrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([
      debrid,
      torbox,
      pikpak,
      premiumize,
      alldebrid,
    ]);
  });

  test('real_debrid hits the RD adapter; fromPlaybackId would miss', () async {
    expect(CloudProviderId.fromPlaybackId('real_debrid'), isNull);
    expect(CloudProviderId.tryParse('real_debrid'), CloudProviderId.debrid);
    expect(
      await CloudProviderRegistry.instance.prepareMagicTv(
        provider: 'real_debrid',
        request: _req(),
      ),
      isNull,
    );
    expect(debrid.magicTvCount, 1);
    expect(torbox.magicTvCount, 0);
  });

  test('Debrify TV magnet has no dn=; Stremio magnet does', () {
    final tv = _req();
    expect(tv.magnet, 'magnet:?xt=urn:btih:abc');
    expect(tv.magnet.contains('dn='), isFalse);
    final stremio = StremioTorrentResolveArgs(
      torrent: _t(),
      contentType: 'series',
    );
    expect(stremio.magnet.contains('dn='), isTrue);
  });

  test('TorBox prepare does not fall through to PikPak', () async {
    expect(
      await CloudProviderRegistry.instance.prepareMagicTv(
        provider: 'torbox',
        request: _req(),
      ),
      isA<MagicTvPrepared>().having((r) => r.streamUrl, 'url', 'https://tb/tv'),
    );
    expect(torbox.magicTvCount, 1);
    expect(pikpak.magicTvCount, 0);
    expect(premiumize.magicTvCount, 0);
  });

  test('AllDebrid stays off the prepare path', () async {
    expect(
      await CloudProviderRegistry.instance.prepareMagicTv(
        provider: 'alldebrid',
        request: _req(),
      ),
      isNull,
    );
    expect(alldebrid.magicTvCount, 1);
    expect(torbox.magicTvCount, 0);
  });
}
