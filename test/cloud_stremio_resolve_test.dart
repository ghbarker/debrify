import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';
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

void main() {
  tearDown(CloudProviderRegistry.debugReset);

  late FakeCloudProvider debrid;
  late FakeCloudProvider torbox;
  late FakeCloudProvider pikpak;
  late FakeCloudProvider premiumize;
  late FakeCloudProvider alldebrid;

  setUp(() {
    debrid = FakeCloudProvider(
      id: CloudProviderId.debrid,
      stremioUrl: 'https://rd/stremio',
    );
    torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      stremioUrl: 'https://tb/stremio',
    );
    pikpak = FakeCloudProvider(
      id: CloudProviderId.pikpak,
      stremioUrl: 'https://pp/stremio',
    );
    premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      stremioUrl: 'https://pm/stremio',
    );
    alldebrid = FakeCloudProvider(
      id: CloudProviderId.alldebrid,
      stremioUrl: 'https://ad/stremio',
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([
      debrid,
      torbox,
      pikpak,
      premiumize,
      alldebrid,
    ]);
  });

  test('realdebrid hits the RD adapter; fromPlaybackId would miss', () async {
    expect(CloudProviderId.fromPlaybackId('realdebrid'), isNull);
    expect(CloudProviderId.tryParse('realdebrid'), CloudProviderId.debrid);
    expect(
      await CloudProviderRegistry.instance.resolveStremioTorrent(
        torrent: _t(),
        contentType: 'movie',
        selected: 'realdebrid',
      ),
      'https://rd/stremio',
    );
    expect(debrid.stremioCount, 1);
    expect(torbox.stremioCount, 0);
  });

  test('auto order is PikPak before Premiumize, not playbackPrecedence', () {
    expect(StremioTvDebridFallback.autoOrder, [
      'realdebrid',
      'torbox',
      'pikpak',
      'premiumize',
      'alldebrid',
    ]);
    expect(
      CloudProviderId.playbackPrecedence.map((id) => id.playbackId).toList(),
      ['debrid', 'torbox', 'premiumize', 'alldebrid', 'pikpak'],
    );
  });

  test('auto skips a null RD result and uses TorBox', () async {
    debrid.stremioUrl = null;
    expect(
      await CloudProviderRegistry.instance.resolveStremioTorrent(
        torrent: _t(),
        contentType: 'series',
        selected: 'auto',
        season: 1,
        episode: 1,
      ),
      'https://tb/stremio',
    );
    expect(debrid.stremioCount, 1);
    expect(torbox.stremioCount, 1);
    expect(pikpak.stremioCount, 0);
  });

  test('explicit provider stays strict', () async {
    torbox.stremioUrl = null;
    expect(
      await CloudProviderRegistry.instance.resolveStremioTorrent(
        torrent: _t(),
        contentType: 'movie',
        selected: 'torbox',
      ),
      isNull,
    );
    expect(debrid.stremioCount, 0);
    expect(torbox.stremioCount, 1);
    expect(pikpak.stremioCount, 0);
  });

  test('canAttempt gates keep Stremio ids, not playback debrid', () async {
    final seen = <String>[];
    expect(
      await CloudProviderRegistry.instance.resolveStremioTorrent(
        torrent: _t(),
        contentType: 'movie',
        selected: 'auto',
        canAttempt: (provider) async {
          seen.add(provider);
          return provider != 'realdebrid';
        },
      ),
      'https://tb/stremio',
    );
    expect(seen.first, 'realdebrid');
    expect(debrid.stremioCount, 0);
    expect(torbox.stremioCount, 1);
  });
}
