import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

void main() {
  tearDown(CloudProviderRegistry.debugReset);

  late FakeCloudProvider debrid;
  late FakeCloudProvider torbox;
  late FakeCloudProvider alldebrid;
  late FakeCloudProvider premiumize;
  late FakeCloudProvider pikpak;

  setUp(() {
    debrid = FakeCloudProvider(
      id: CloudProviderId.debrid,
      playlistUrl: 'https://rd/file',
    );
    torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      playlistUrl: 'https://tb/file',
    );
    alldebrid = FakeCloudProvider(
      id: CloudProviderId.alldebrid,
      playlistUrl: 'https://ad/file',
    );
    premiumize = FakeCloudProvider(id: CloudProviderId.premiumize);
    pikpak = FakeCloudProvider(id: CloudProviderId.pikpak);
    CloudProviderRegistry.instance = CloudProviderRegistry([
      debrid,
      torbox,
      alldebrid,
      premiumize,
      pikpak,
    ]);
  });

  test('nonempty url is returned without unlocking', () async {
    final url = await CloudProviderRegistry.instance.resolveEntryUrl(
      const PlaylistEntry(url: 'https://already', title: 'a'),
    );
    expect(url, 'https://already');
    expect(debrid.playlistCount, 0);
    expect(torbox.playlistCount, 0);
    expect(alldebrid.playlistCount, 0);
  });

  test('restrictedLink wins over TorBox fields and ignores provider string', () async {
    final url = await CloudProviderRegistry.instance.resolveEntryUrl(
      const PlaylistEntry(
        url: '',
        title: 'a',
        provider: 'torbox',
        restrictedLink: 'https://rd/restrict',
        torboxTorrentId: 1,
        torboxFileId: 2,
      ),
    );
    expect(url, 'https://rd/file');
    expect(debrid.playlistCount, 1);
    expect(torbox.playlistCount, 0);
  });

  test('TorBox torrent+file unlocks; web-download ids do not', () async {
    final torrent = await CloudProviderRegistry.instance.resolveEntryUrl(
      const PlaylistEntry(
        url: '',
        title: 'a',
        torboxTorrentId: 9,
        torboxFileId: 3,
      ),
    );
    expect(torrent, 'https://tb/file');
    expect(torbox.playlistCount, 1);

    final web = await CloudProviderRegistry.instance.resolveEntryUrl(
      const PlaylistEntry(
        url: '',
        title: 'a',
        provider: 'torbox',
        torboxWebDownloadId: 4,
        torboxFileId: 3,
      ),
    );
    expect(web, isNull);
    expect(torbox.playlistCount, 1);
  });

  test('AllDebrid locked link unlocks', () async {
    final url = await CloudProviderRegistry.instance.resolveEntryUrl(
      const PlaylistEntry(
        url: '',
        title: 'a',
        allDebridLink: 'https://ad/lock',
      ),
    );
    expect(url, 'https://ad/file');
    expect(alldebrid.playlistCount, 1);
  });

  test('Premiumize and PikPak stay on the player launcher path', () async {
    expect(
      await CloudProviderRegistry.instance.resolveEntryUrl(
        const PlaylistEntry(
          url: '',
          title: 'a',
          provider: 'premiumize',
          premiumizePath: '/movie.mkv',
          premiumizeItemId: 'item',
        ),
      ),
      isNull,
    );
    expect(
      await CloudProviderRegistry.instance.resolveEntryUrl(
        const PlaylistEntry(
          url: '',
          title: 'a',
          provider: 'pikpak',
          pikpakFileId: 'file',
        ),
      ),
      isNull,
    );
    expect(premiumize.playlistCount, 0);
    expect(pikpak.playlistCount, 0);
  });

  test('unlock errors become null', () async {
    debrid.error = Exception('429');
    expect(
      await CloudProviderRegistry.instance.resolveEntryUrl(
        const PlaylistEntry(
          url: '',
          title: 'a',
          restrictedLink: 'https://rd/restrict',
        ),
      ),
      isNull,
    );
  });
}
