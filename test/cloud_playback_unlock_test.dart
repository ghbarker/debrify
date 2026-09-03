import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
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
      playbackUnlockUrl: 'https://rd/play',
      playlistUrl: 'https://rd/dl',
    );
    torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      playbackUnlockUrl: 'https://tb/play',
      playlistUrl: 'https://tb/dl',
    );
    alldebrid = FakeCloudProvider(
      id: CloudProviderId.alldebrid,
      playbackUnlockUrl: 'https://ad/play',
    );
    premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      playbackUnlockUrl: 'https://pm/play',
    );
    pikpak = FakeCloudProvider(
      id: CloudProviderId.pikpak,
      playbackUnlockUrl: 'https://pp/play',
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([
      debrid,
      torbox,
      alldebrid,
      premiumize,
      pikpak,
    ]);
  });

  test(
    'TorBox wins over restrictedLink; download picker does the opposite',
    () async {
      const entry = PlaylistEntry(
        url: '',
        title: 'a',
        restrictedLink: 'https://rd/restrict',
        torboxTorrentId: 1,
        torboxFileId: 2,
      );
      expect(
        await CloudProviderRegistry.instance.unlockPlaybackEntry(entry),
        'https://tb/play',
      );
      expect(
        await CloudProviderRegistry.instance.resolveEntryUrl(entry),
        'https://rd/dl',
      );
    },
  );

  test(
    'TorBox web-download unlocks for playback and is ignored for download picker',
    () async {
      const entry = PlaylistEntry(
        url: '',
        title: 'a',
        provider: 'torbox',
        torboxWebDownloadId: 4,
        torboxFileId: 3,
      );
      expect(
        await CloudProviderRegistry.instance.unlockPlaybackEntry(entry),
        'https://tb/play',
      );
      expect(
        await CloudProviderRegistry.instance.resolveEntryUrl(entry),
        isNull,
      );
    },
  );

  test('provider torbox with no ids throws on the adapter', () async {
    expect(
      () => const TorboxCloudProvider().unlockPlaybackEntry(
        const PlaylistEntry(url: '', title: 'a', provider: 'torbox'),
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Torbox file metadata missing'),
        ),
      ),
    );
  });

  test('incomplete Premiumize hash falls through to Real-Debrid', () async {
    expect(
      await CloudProviderRegistry.instance.unlockPlaybackEntry(
        const PlaylistEntry(
          url: '',
          title: 'a',
          provider: 'premiumize',
          premiumizeHash: '',
          restrictedLink: 'https://rd/restrict',
        ),
      ),
      'https://rd/play',
    );
  });

  test('fallback videoUrl is used when nothing else matches', () async {
    expect(
      await CloudProviderRegistry.instance.unlockPlaybackEntry(
        const PlaylistEntry(url: '', title: 'a'),
        fallbackUrl: 'https://args/video',
      ),
      'https://args/video',
    );
  });

  test('empty fallback throws', () async {
    expect(
      () => CloudProviderRegistry.instance.unlockPlaybackEntry(
        const PlaylistEntry(url: '', title: 'a'),
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No URL metadata available for this entry'),
        ),
      ),
    );
  });
}
