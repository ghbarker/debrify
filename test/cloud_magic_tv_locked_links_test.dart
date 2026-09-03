import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/magic_tv_playable.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
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

MagicTvPrepareRequest _req({
  Set<String>? seen,
  bool Function(int bytes)? sizeMatchesBytes,
  bool hasSizeFilter = false,
}) => MagicTvPrepareRequest(
  torrent: _t(),
  log: (_) {},
  seenKeys: seen ?? <String>{},
  sizeMatchesBytes: sizeMatchesBytes ?? ((_) => true),
  hasSizeFilter: hasSizeFilter,
  minVideoSizeBytes: 50 * 1024 * 1024,
);

AllDebridFile _file({
  required String path,
  required int size,
  required String link,
}) => AllDebridFile(path: path, size: size, link: link);

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
      lockedLinksResult: const MagicTvLockedBatch(
        remoteId: 'rd1',
        name: 'Show',
        lockedLinks: ['https://rd/locked'],
      ),
    );
    torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      magicTvResult: const MagicTvPrepared(
        streamUrl: 'https://tb/tv',
        title: 'ep',
        hasMore: true,
      ),
    );
    pikpak = FakeCloudProvider(id: CloudProviderId.pikpak);
    premiumize = FakeCloudProvider(id: CloudProviderId.premiumize);
    alldebrid = FakeCloudProvider(
      id: CloudProviderId.alldebrid,
      lockedLinksResult: const MagicTvLockedBatch(
        remoteId: 'ad1',
        name: 'Show',
        lockedLinks: ['https://ad/locked'],
      ),
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([
      debrid,
      torbox,
      pikpak,
      premiumize,
      alldebrid,
    ]);
  });

  test('real_debrid locked links hit RD; fromPlaybackId would miss', () async {
    expect(CloudProviderId.fromPlaybackId('real_debrid'), isNull);
    expect(CloudProviderId.tryParse('real_debrid'), CloudProviderId.debrid);
    final batch = await CloudProviderRegistry.instance.prepareMagicTvLockedLinks(
      provider: 'real_debrid',
      request: _req(),
    );
    expect(batch?.remoteId, 'rd1');
    expect(debrid.lockedLinksCount, 1);
    expect(debrid.magicTvCount, 0);
    expect(alldebrid.lockedLinksCount, 0);
    expect(
      await CloudProviderRegistry.instance.prepareMagicTv(
        provider: 'real_debrid',
        request: _req(),
      ),
      isNull,
    );
    expect(debrid.magicTvCount, 1);
  });

  test('AllDebrid locked links do not use prepareMagicTv', () async {
    final batch = await CloudProviderRegistry.instance.prepareMagicTvLockedLinks(
      provider: 'alldebrid',
      request: _req(),
    );
    expect(batch?.lockedLinks, ['https://ad/locked']);
    expect(alldebrid.lockedLinksCount, 1);
    expect(alldebrid.magicTvCount, 0);
    expect(torbox.lockedLinksCount, 0);
  });

  test('TorBox stays on prepareMagicTv, not locked links', () async {
    expect(
      await CloudProviderRegistry.instance.prepareMagicTvLockedLinks(
        provider: 'torbox',
        request: _req(),
      ),
      isNull,
    );
    expect(torbox.lockedLinksCount, 1);
    expect(
      await CloudProviderRegistry.instance.prepareMagicTv(
        provider: 'torbox',
        request: _req(),
      ),
      isA<MagicTvPrepared>(),
    );
    expect(torbox.magicTvCount, 1);
  });

  test('locked-link magnet has no dn=', () {
    expect(_req().magnet.contains('dn='), isFalse);
  });

  test('AllDebrid collect applies the 50MB floor and size-filter fallback', () {
    const minOk = 60 * 1024 * 1024;
    const tooSmall = 10 * 1024 * 1024;
    final files = [
      _file(path: 'sample.mkv', size: tooSmall, link: 'https://ad/sample'),
      _file(path: 'ep.mkv', size: minOk, link: 'https://ad/ep'),
      _file(path: 'readme.txt', size: minOk, link: 'https://ad/txt'),
      _file(path: 'zero.mkv', size: 0, link: 'https://ad/zero'),
    ];

    expect(
      MagicTvPlayable.collectAllDebridLockedLinks(
        files,
        _req(sizeMatchesBytes: (b) => b == minOk),
      ),
      ['https://ad/ep'],
    );

    expect(
      MagicTvPlayable.collectAllDebridLockedLinks(
        files,
        _req(
          sizeMatchesBytes: (_) => false,
          hasSizeFilter: true,
        ),
      ),
      ['https://ad/ep', 'https://ad/zero'],
    );

    expect(
      MagicTvPlayable.collectAllDebridLockedLinks(
        files,
        _req(seen: {'https://ad/ep'}),
      ),
      ['https://ad/zero'],
    );
  });
}
