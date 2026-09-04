import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_exceptions.dart';
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
      playbackUnlockUrl: 'https://rd/play',
    );
    torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      playbackUnlockUrl: 'https://tb/play',
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
    'incomplete Premiumize hash throws; launcher falls through to Real-Debrid',
    () async {
      const entry = PlaylistEntry(
        url: '',
        title: 'a',
        provider: 'premiumize',
        premiumizeHash: '',
        restrictedLink: 'https://rd/restrict',
      );
      await expectLater(
        CloudProviderRegistry.instance.unlockPlayerScreenEntry(entry),
        throwsA(isA<CloudMetadataMissing>()),
      );
      expect(debrid.unlockCount, 0);
      expect(
        await CloudProviderRegistry.instance.unlockPlaybackEntry(entry),
        'https://rd/play',
      );
    },
  );

  test('empty restrictedLink still hits Real-Debrid on the player path', () async {
    const entry = PlaylistEntry(
      url: '',
      title: 'a',
      restrictedLink: '',
    );
    expect(
      await CloudProviderRegistry.instance.unlockPlayerScreenEntry(entry),
      'https://rd/play',
    );
    expect(debrid.unlockCount, 1);
    expect(
      () => CloudProviderRegistry.instance.unlockPlaybackEntry(entry),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No URL metadata available for this entry'),
        ),
      ),
    );
  });

  test('adapter HTTP errors wrap as Torbox link failed', () async {
    torbox.error = Exception('429');
    await expectLater(
      CloudProviderRegistry.instance.unlockPlayerScreenEntry(
        const PlaylistEntry(
          url: '',
          title: 'a',
          torboxTorrentId: 1,
          torboxFileId: 2,
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Torbox link failed'),
        ),
      ),
    );
    expect(
      () => CloudProviderRegistry.instance.unlockPlaybackEntry(
        const PlaylistEntry(
          url: '',
          title: 'a',
          torboxTorrentId: 1,
          torboxFileId: 2,
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('429'), isNot(contains('link failed'))),
        ),
      ),
    );
  });

  test('missing Torbox metadata is not wrapped', () async {
    CloudProviderRegistry.debugReset();
    await expectLater(
      CloudProviderRegistry.instance.unlockPlayerScreenEntry(
        const PlaylistEntry(url: '', title: 'a', provider: 'torbox'),
      ),
        throwsA(isA<CloudMetadataMissing>()),
    );
  });

  test('player path has no fallbackUrl', () async {
    await expectLater(
      CloudProviderRegistry.instance.unlockPlayerScreenEntry(
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
    expect(
      await CloudProviderRegistry.instance.unlockPlaybackEntry(
        const PlaylistEntry(url: '', title: 'a'),
        fallbackUrl: 'https://args/video',
      ),
      'https://args/video',
    );
  });

}
