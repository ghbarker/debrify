import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/torrent_bulk_add_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

/// Fat-port fake that also implements [CloudCachedHashes] so `is` checks hit
/// (P1 FakeCloudProvider does not implement that type).
class _HashesCapFake extends FakeCloudProvider implements CloudCachedHashes {
  _HashesCapFake({required super.id});
}

class _CheckCacheCapFake extends FakeCloudProvider implements CloudCheckCache {
  _CheckCacheCapFake({required super.id});
}

class _PrepareOnlyFake extends FakeCloudProvider
    implements CloudMagicTvPrepare {
  _PrepareOnlyFake({required super.id});

  @override
  bool supports(CloudPortFeature feature) =>
      feature == CloudPortFeature.magicTvPrepare;
}

void _installFakes({
  FakeCloudProvider? debrid,
  FakeCloudProvider? torbox,
  FakeCloudProvider? pikpak,
  FakeCloudProvider? premiumize,
  FakeCloudProvider? alldebrid,
}) {
  CloudProviderRegistry.instance = CloudProviderRegistry([
    debrid ?? FakeCloudProvider(id: CloudProviderId.debrid),
    torbox ?? FakeCloudProvider(id: CloudProviderId.torbox),
    pikpak ?? FakeCloudProvider(id: CloudProviderId.pikpak),
    premiumize ?? FakeCloudProvider(id: CloudProviderId.premiumize),
    alldebrid ?? FakeCloudProvider(id: CloudProviderId.alldebrid),
  ]);
}

PlaylistEntry _entry({
  String title = 'File.Name.mkv',
  String? provider,
  int? torboxTorrentId,
  int? torboxWebDownloadId,
  int? torboxFileId,
  String? pikpakFileId,
  String? rdTorrentId,
  String url = 'https://example.test/file.mkv',
}) {
  return PlaylistEntry(
    url: url,
    title: title,
    provider: provider,
    torboxTorrentId: torboxTorrentId,
    torboxWebDownloadId: torboxWebDownloadId,
    torboxFileId: torboxFileId,
    pikpakFileId: pikpakFileId,
    rdTorrentId: rdTorrentId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CloudProviderRegistry.debugReset);

  setUp(_installFakes);

  group('launcher resume ids', () {
    test('TorBox / PikPak playback ids keep persisted prefixes', () {
      expect(
        LauncherProviderDispatch.resumeIdForEntry(
          _entry(
            provider: 'torbox',
            torboxWebDownloadId: 9,
            torboxFileId: 3,
          ),
        ),
        'torbox_web_9_3',
      );
      expect(
        LauncherProviderDispatch.resumeIdForEntry(
          _entry(provider: 'torbox', torboxTorrentId: 4, torboxFileId: 5),
        ),
        'torbox_4_5',
      );
      expect(
        LauncherProviderDispatch.resumeIdForEntry(
          _entry(provider: 'pikpak', pikpakFileId: 'abc'),
        ),
        'pikpak_abc',
      );
    });

    test('resume matches VideoPlayerLauncher for the string-switch paths', () {
      final cases = <PlaylistEntry>[
        _entry(provider: 'torbox', torboxWebDownloadId: 1, torboxFileId: 2),
        _entry(provider: 'torbox', torboxTorrentId: 8, torboxFileId: 1),
        _entry(provider: 'pikpak', pikpakFileId: 'pp1'),
        _entry(provider: 'torbox'),
        _entry(provider: 'pikpak'),
        _entry(provider: 'realdebrid', rdTorrentId: 'rd1'),
        _entry(torboxTorrentId: 1, torboxFileId: 2),
        _entry(title: 'Movie.Title.mkv'),
      ];
      for (final entry in cases) {
        expect(
          LauncherProviderDispatch.resumeIdForEntry(
            entry,
            fallbackTitle: 'Fallback',
          ),
          VideoPlayerLauncher.resumeIdForEntry(
            entry,
            fallbackTitle: 'Fallback',
          ),
          reason: 'provider=${entry.provider} title=${entry.title}',
        );
      }
    });

    test('playlist realdebrid / metadata-only TorBox still filename-hash', () {
      final rd = _entry(provider: 'realdebrid', rdTorrentId: 'x');
      final hashed = 'File.Name'.hashCode.toString();
      expect(LauncherProviderDispatch.resumeIdForEntry(rd), hashed);
      expect(
        LauncherProviderDispatch.resumeIdForEntry(
          _entry(torboxTorrentId: 1, torboxFileId: 2),
        ),
        hashed,
      );
    });

    test('capability is-checks win over FakeCloudProvider.supports table', () {
      _installFakes(debrid: _HashesCapFake(id: CloudProviderId.debrid));
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.debrid,
        ).contains(CloudPortFeature.cachedHashes),
        isFalse,
      );
      expect(
        LauncherProviderDispatch.resumeIdForEntry(
          _entry(provider: 'debrid', torboxTorrentId: 1, torboxFileId: 2),
        ),
        'torbox_1_2',
      );
    });
  });

  group('launcher analytics labels', () {
    test('arg fields: RD is magicTvId, TorBox/PikPak are playbackId', () {
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(
            videoUrl: 'https://cdn.example/a',
            title: 't',
            rdTorrentId: 'rd1',
            torboxTorrentId: 'tb1',
          ),
        ),
        'real_debrid',
      );
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(
            videoUrl: 'https://cdn.example/a',
            title: 't',
            torboxTorrentId: 'tb1',
          ),
        ),
        'torbox',
      );
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(
            videoUrl: 'https://cdn.example/a',
            title: 't',
            pikpakCollectionId: 'pp1',
          ),
        ),
        'pikpak',
      );
    });

    test('playlist explicit RD spellings: realdebrid, real_debrid, space', () {
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(provider: 'realdebrid'),
        ]),
        'real_debrid',
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(provider: 'real_debrid'),
        ]),
        'real_debrid',
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(provider: 'real debrid'),
        ]),
        'real_debrid',
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(provider: 'real-debrid'),
        ]),
        isNull,
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(provider: 'debrid'),
        ]),
        isNull,
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(provider: 'rd'),
        ]),
        isNull,
      );
    });

    test('playlist metadata fallback and URL host labels', () {
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(torboxFileId: 3),
        ]),
        'torbox',
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(pikpakFileId: 'f'),
        ]),
        'pikpak',
      );
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel([
          _entry(rdTorrentId: 'abc'),
        ]),
        'real_debrid',
      );
      expect(
        LauncherProviderDispatch.analyticsUrlLabel(
          'https://stream.real-debrid.com/d/x',
        ),
        'real_debrid',
      );
      expect(
        LauncherProviderDispatch.analyticsUrlLabel(
          'https://mypikpak.com/file',
        ),
        'pikpak',
      );
      expect(
        LauncherProviderDispatch.analyticsUrlLabel(
          'https://tb-cdn.example/file',
        ),
        'torbox',
      );
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(
            videoUrl: 'https://cdn.example/direct.mp4',
            title: 't',
          ),
        ),
        'direct',
      );
    });
  });

  group('launcher CDN skip hosts', () {
    test('redirect skip matches today (no tb-cdn / mypikpak extras)', () {
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('foo.real-debrid.com'),
        isTrue,
      );
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('s.torbox.app'),
        isTrue,
      );
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('dl.pikpak.com'),
        isTrue,
      );
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('1fichier.com'),
        isTrue,
      );
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('rapidgator.net'),
        isTrue,
      );
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('tb-cdn.example'),
        isFalse,
      );
      expect(
        LauncherProviderDispatch.isKnownDebridCdnHost('mypikpak.com'),
        isTrue,
      );
    });
  });

  group('bulk-add dispatch', () {
    test('dialog pop ids: RD is realdebrid, others playbackId', () {
      expect(
        BulkAddDispatch.dialogResultFor(CloudProviderId.debrid),
        'realdebrid',
      );
      expect(BulkAddDispatch.dialogResultFor(CloudProviderId.torbox), 'torbox');
      expect(BulkAddDispatch.dialogResultFor(CloudProviderId.pikpak), 'pikpak');
      expect(
        BulkAddDispatch.dialogResultFor(CloudProviderId.premiumize),
        'premiumize',
      );
      expect(
        BulkAddDispatch.dialogResultFor(CloudProviderId.alldebrid),
        'alldebrid',
      );
      expect(BulkAddDispatch.idForDialogResult('debrid'), isNull);
      expect(BulkAddDispatch.idForDialogResult('real_debrid'), isNull);
      expect(BulkAddDispatch.idForDialogResult('rd'), isNull);
    });

    test('chooser order is TB, RD, PP, PM, AD and autofocus first enabled', () {
      expect(BulkAddDispatch.chooserOrder, [
        CloudProviderId.torbox,
        CloudProviderId.debrid,
        CloudProviderId.pikpak,
        CloudProviderId.premiumize,
        CloudProviderId.alldebrid,
      ]);
      expect(
        BulkAddDispatch.autoFocus({
          CloudProviderId.torbox: false,
          CloudProviderId.debrid: true,
          CloudProviderId.pikpak: true,
        }),
        CloudProviderId.debrid,
      );
      expect(BulkAddDispatch.autoFocus(const {}), isNull);
    });

    test('FakeCloudProvider: engine follows supports() table', () {
      expect(BulkAddDispatch.engineFor('torbox'), BulkAddEngine.torbox);
      expect(
        BulkAddDispatch.engineFor('realdebrid'),
        BulkAddEngine.realDebrid,
      );
      expect(BulkAddDispatch.engineFor('pikpak'), BulkAddEngine.pikpak);
      expect(
        BulkAddDispatch.engineFor('premiumize'),
        BulkAddEngine.premiumize,
      );
      expect(BulkAddDispatch.engineFor('alldebrid'), BulkAddEngine.allDebrid);
      expect(
        BulkAddDispatch.engineFor('create_channel'),
        BulkAddEngine.createChannel,
      );
      expect(BulkAddDispatch.engineFor('debrid'), BulkAddEngine.none);
      expect(BulkAddDispatch.engineFor('mystery'), BulkAddEngine.none);
    });

    test('capability is-checks win over dialog id and supports() table', () {
      _installFakes(
        debrid: _HashesCapFake(id: CloudProviderId.debrid),
        alldebrid: _CheckCacheCapFake(id: CloudProviderId.alldebrid),
        torbox: _PrepareOnlyFake(id: CloudProviderId.torbox),
      );
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.debrid,
        ).contains(CloudPortFeature.cachedHashes),
        isFalse,
      );
      expect(BulkAddDispatch.engineFor('realdebrid'), BulkAddEngine.torbox);
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.alldebrid,
        ).contains(CloudPortFeature.checkCache),
        isFalse,
      );
      expect(
        BulkAddDispatch.engineFor('alldebrid'),
        BulkAddEngine.premiumize,
      );
      expect(
        CloudPortFeature.forProvider(
          CloudProviderId.torbox,
        ).contains(CloudPortFeature.cachedHashes),
        isTrue,
      );
      expect(BulkAddDispatch.engineFor('torbox'), BulkAddEngine.pikpak);
    });
  });
}
