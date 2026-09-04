import 'package:debrify/screens/cloud_screen.dart';
import 'package:debrify/screens/settings/provider_settings_page.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/playlist_player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

/// Fat-port fake that also implements file-download so `is` checks hit
/// (P1 FakeCloudProvider does not implement [CloudFileDownloadLink]).
class _FileLinkCapFake extends FakeCloudProvider
    implements CloudFileDownloadLink {
  _FileLinkCapFake({required super.id});
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CloudProviderRegistry.debugReset);

  setUp(_installFakes);

  group('PlaylistProviderDispatch', () {
    test(
      'playlist JSON ids are playlistStoredProvider, not playback or magicTv',
      () {
        expect(CloudProviderId.debrid.playlistStoredProvider, 'realdebrid');
        expect(CloudProviderId.debrid.playbackId, 'debrid');
        expect(CloudProviderId.debrid.magicTvId, 'real_debrid');
        expect(
          PlaylistProviderDispatch.storedProvider(CloudProviderId.debrid),
          'realdebrid',
        );
        expect(
          PlaylistProviderDispatch.storedProvider(CloudProviderId.torbox),
          'torbox',
        );
        expect(
          PlaylistProviderDispatch.idExact('realdebrid'),
          CloudProviderId.debrid,
        );
        expect(PlaylistProviderDispatch.idExact('debrid'), isNull);
        expect(PlaylistProviderDispatch.idExact('rd'), isNull);
        expect(PlaylistProviderDispatch.idExact('real_debrid'), isNull);
        expect(PlaylistProviderDispatch.idExact('all-debrid'), isNull);
        expect(
          PlaylistProviderDispatch.idExact('alldebrid'),
          CloudProviderId.alldebrid,
        );
        expect(
          PlaylistProviderDispatch.idExact('TORBOX'),
          CloudProviderId.torbox,
        );
        expect(
          PlaylistProviderDispatch.isWebDav('webdav'),
          isTrue,
        );
        expect(
          PlaylistProviderDispatch.isWebDav('WebDAV'),
          isTrue,
        );
      },
    );

    test(
      'kindOrRd: missing/unknown/playback spelling fall through to Real-Debrid',
      () {
        expect(
          PlaylistProviderDispatch.kindOrRd(null),
          PlaylistPlayKind.realdebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd(''),
          PlaylistPlayKind.realdebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('mystery'),
          PlaylistPlayKind.realdebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('debrid'),
          PlaylistPlayKind.realdebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('realdebrid'),
          PlaylistPlayKind.realdebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('torbox'),
          PlaylistPlayKind.torbox,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('pikpak'),
          PlaylistPlayKind.pikpak,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('premiumize'),
          PlaylistPlayKind.premiumize,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('alldebrid'),
          PlaylistPlayKind.alldebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrRd('webdav'),
          PlaylistPlayKind.webdav,
        );
      },
    );

    test(
      'kindOrNull: content-view play is a no-op for unknown/empty/debrid',
      () {
        expect(
          PlaylistProviderDispatch.kindOrNull(null),
          PlaylistPlayKind.realdebrid,
        );
        expect(PlaylistProviderDispatch.kindOrNull(''), isNull);
        expect(PlaylistProviderDispatch.kindOrNull('mystery'), isNull);
        expect(PlaylistProviderDispatch.kindOrNull('debrid'), isNull);
        expect(PlaylistProviderDispatch.kindOrNull('rd'), isNull);
        expect(
          PlaylistProviderDispatch.kindOrNull('realdebrid'),
          PlaylistPlayKind.realdebrid,
        );
        expect(
          PlaylistProviderDispatch.kindOrNull('torbox'),
          PlaylistPlayKind.torbox,
        );
        expect(
          PlaylistProviderDispatch.kindOrNull('webdav'),
          PlaylistPlayKind.webdav,
        );
      },
    );

    test('posterKind has no WebDAV branch', () {
      expect(
        PlaylistProviderDispatch.posterKind(null),
        PlaylistPlayKind.realdebrid,
      );
      expect(
        PlaylistProviderDispatch.posterKind('realdebrid'),
        PlaylistPlayKind.realdebrid,
      );
      expect(
        PlaylistProviderDispatch.posterKind('torbox'),
        PlaylistPlayKind.torbox,
      );
      expect(PlaylistProviderDispatch.posterKind('webdav'), isNull);
      expect(PlaylistProviderDispatch.posterKind(''), isNull);
      expect(PlaylistProviderDispatch.posterKind('mystery'), isNull);
    });

    test(
      'FakeCloudProvider: skipTorrentNameFolder is TorBox fileDownloadLink',
      () {
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('torbox'),
          isTrue,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('realdebrid'),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('pikpak'),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('premiumize'),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('alldebrid'),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('webdav'),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder(null),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('mystery'),
          isFalse,
        );
      },
    );

    test(
      'capability is-checks win over FakeCloudProvider.supports table',
      () {
        _installFakes(
          debrid: _FileLinkCapFake(id: CloudProviderId.debrid),
          torbox: FakeCloudProvider(id: CloudProviderId.torbox),
        );
        expect(
          CloudPortFeature.forProvider(
            CloudProviderId.debrid,
          ).contains(CloudPortFeature.fileDownloadLink),
          isFalse,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('realdebrid'),
          isTrue,
        );
        expect(
          PlaylistProviderDispatch.skipTorrentNameFolder('torbox'),
          isTrue,
        );
      },
    );

    test('missing registry adapter does not skip torrent-name folder', () {
      CloudProviderRegistry.instance = CloudProviderRegistry([
        FakeCloudProvider(id: CloudProviderId.debrid),
      ]);
      expect(
        PlaylistProviderDispatch.skipTorrentNameFolder('torbox'),
        isFalse,
      );
    });
  });

  group('CloudHubDispatch', () {
    test('hub keys are playlistStoredProvider, not playbackId', () {
      expect(
        CloudHubDispatch.hubKey(CloudProviderId.debrid),
        'realdebrid',
      );
      expect(CloudProviderId.debrid.playbackId, 'debrid');
      expect(CloudHubDispatch.webDavKey, 'webdav');
      expect(
        CloudHubDispatch.cloudOrder,
        [
          CloudProviderId.debrid,
          CloudProviderId.torbox,
          CloudProviderId.pikpak,
          CloudProviderId.premiumize,
          CloudProviderId.alldebrid,
        ],
      );
      expect(
        CloudHubDispatch.cloudOrder,
        isNot(CloudProviderId.playbackPrecedence),
      );
    });

    test('hub names keep Real Debrid space and Torbox overlay title', () {
      expect(
        CloudHubDispatch.hubName(CloudProviderId.debrid),
        'Real Debrid',
      );
      expect(CloudProviderId.debrid.displayName, 'Real-Debrid');
      expect(
        CloudHubDispatch.hubName(CloudProviderId.torbox),
        'Torbox',
      );
      expect(CloudProviderId.torbox.displayName, 'TorBox');
      expect(
        CloudHubDispatch.hubName(CloudProviderId.pikpak),
        'PikPak',
      );
      expect(
        CloudHubDispatch.hubSubtitle(CloudProviderId.pikpak),
        'Cloud storage',
      );
      expect(
        CloudHubDispatch.hubSubtitle(CloudProviderId.debrid),
        'Debrid service',
      );
    });

    test('hub colours are not playback chrome gradients', () {
      expect(
        CloudHubDispatch.hubColor(CloudProviderId.debrid),
        const Color(0xFF60A5FA),
      );
      expect(
        CloudHubDispatch.hubColor(CloudProviderId.torbox),
        const Color(0xFFFBBF24),
      );
      expect(
        CloudHubDispatch.hubIcon(CloudProviderId.debrid),
        Icons.cloud_download_rounded,
      );
    });

    test('FakeCloudProvider: inRegistry follows the installed registry', () {
      expect(CloudHubDispatch.inRegistry(CloudProviderId.debrid), isTrue);
      expect(CloudHubDispatch.inRegistry(CloudProviderId.torbox), isTrue);
      CloudProviderRegistry.instance = CloudProviderRegistry([
        FakeCloudProvider(id: CloudProviderId.torbox),
      ]);
      expect(CloudHubDispatch.inRegistry(CloudProviderId.debrid), isFalse);
      expect(CloudHubDispatch.inRegistry(CloudProviderId.torbox), isTrue);
    });
  });

  group('DefaultProviderDispatch', () {
    test('pref values are playbackId, not playlistStoredProvider', () {
      expect(
        DefaultProviderDispatch.prefValue(CloudProviderId.debrid),
        'debrid',
      );
      expect(
        DefaultProviderDispatch.prefValue(CloudProviderId.torbox),
        'torbox',
      );
      expect(DefaultProviderDispatch.askEveryTime, 'none');
      expect(
        DefaultProviderDispatch.parsePref('debrid'),
        CloudProviderId.debrid,
      );
      expect(DefaultProviderDispatch.parsePref('realdebrid'), isNull);
      expect(DefaultProviderDispatch.parsePref('rd'), isNull);
      expect(DefaultProviderDispatch.parsePref('none'), isNull);
      expect(
        DefaultProviderDispatch.parsePref('torbox'),
        CloudProviderId.torbox,
      );
    });

    test('option order is TB then RD, not playbackPrecedence', () {
      expect(DefaultProviderDispatch.optionOrder.first, CloudProviderId.torbox);
      expect(
        DefaultProviderDispatch.optionOrder[1],
        CloudProviderId.debrid,
      );
      expect(
        DefaultProviderDispatch.optionOrder,
        [
          CloudProviderId.torbox,
          CloudProviderId.debrid,
          CloudProviderId.premiumize,
          CloudProviderId.alldebrid,
          CloudProviderId.pikpak,
        ],
      );
      expect(
        CloudProviderId.playbackPrecedence.first,
        CloudProviderId.debrid,
      );
    });

    test(
      'resetIfUnavailable: missing provider → none; unknown spelling kept',
      () {
        expect(
          DefaultProviderDispatch.resetIfUnavailable('none', {
            CloudProviderId.torbox,
          }),
          'none',
        );
        expect(
          DefaultProviderDispatch.resetIfUnavailable('torbox', {
            CloudProviderId.debrid,
          }),
          'none',
        );
        expect(
          DefaultProviderDispatch.resetIfUnavailable('torbox', {
            CloudProviderId.torbox,
          }),
          'torbox',
        );
        expect(
          DefaultProviderDispatch.resetIfUnavailable('debrid', {
            CloudProviderId.torbox,
          }),
          'none',
        );
        expect(
          DefaultProviderDispatch.resetIfUnavailable('realdebrid', {
            CloudProviderId.debrid,
          }),
          'realdebrid',
        );
        expect(
          DefaultProviderDispatch.resetIfUnavailable('mystery', {
            CloudProviderId.debrid,
          }),
          'mystery',
        );
      },
    );

    test('option titles keep Torbox and hyphenated Real-Debrid', () {
      expect(
        DefaultProviderDispatch.optionTitle(CloudProviderId.torbox),
        'Torbox',
      );
      expect(
        DefaultProviderDispatch.optionTitle(CloudProviderId.debrid),
        'Real-Debrid',
      );
      expect(
        DefaultProviderDispatch.optionIcon(CloudProviderId.debrid),
        Icons.cloud_rounded,
      );
    });

    test(
      'FakeCloudProvider isConfigured is not the settings availability dialect',
      () {
        _installFakes(
          pikpak: FakeCloudProvider(
            id: CloudProviderId.pikpak,
            configured: true,
          ),
          torbox: FakeCloudProvider(
            id: CloudProviderId.torbox,
            configured: false,
          ),
        );
        expect(
          CloudProviderRegistry.instance[CloudProviderId.pikpak],
          isNotNull,
        );
        expect(
          DefaultProviderDispatch.prefValue(CloudProviderId.pikpak),
          isNot(CloudProviderId.pikpak.playlistStoredProvider),
        );
        expect(
          DefaultProviderDispatch.parsePref(
            CloudProviderId.pikpak.playbackId,
          ),
          CloudProviderId.pikpak,
        );
      },
    );
  });
}
