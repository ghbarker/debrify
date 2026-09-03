import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_playback_result.dart';
import 'package:debrify/services/cloud/cloud_playlist_payload.dart';
import 'package:debrify/services/cloud/cloud_provider_chrome.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/cloud_secret_prefs.dart';
import 'package:debrify/widgets/cloud_browse_select_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudProviderChrome', () {
    test('playback labels and codes match historical TPS switch', () {
      expect(CloudProviderChrome.label('debrid'), 'Real-Debrid');
      expect(CloudProviderChrome.label('preparing'), 'Preparing');
      expect(CloudProviderChrome.label(SeriesSource.localService), 'On-device');
      expect(
        CloudProviderChrome.label(SeriesSource.addonDirectService),
        'Direct addon',
      );
      expect(CloudProviderChrome.label('mystery'), 'mystery');
      expect(CloudProviderChrome.label('rd'), 'rd');
      expect(CloudProviderChrome.label('realdebrid'), 'realdebrid');
      expect(CloudProviderChrome.code('debrid'), 'RD');
      expect(CloudProviderChrome.code(''), '·');
      expect(CloudProviderChrome.code('xyz'), 'X');
    });

    test('TorBox display name is not the overlay title', () {
      expect(CloudProviderId.torbox.displayName, 'TorBox');
      expect(CloudProviderId.torbox.overlayTitle, 'Torbox');
      expect(CloudProviderId.debrid.displayName, 'Real-Debrid');
      expect(CloudProviderId.debrid.overlayTitle, 'Real-Debrid');
      expect(CloudProviderId.debrid.playlistStoredProvider, 'realdebrid');
      expect(CloudProviderId.fromPlaybackId('rd'), isNull);
      expect(CloudProviderId.tryParse('rd'), CloudProviderId.debrid);
    });

    test('unknown providers share the indigo fallback gradient', () {
      expect(
        CloudProviderChrome.gradient('nope').first,
        const Color(0xFF6366F1),
      );
      expect(
        CloudProviderChrome.icon('nope'),
        Icons.cloud_download_rounded,
      );
    });

    test('catalog chips treat realdebrid as RD and auto as AUTO', () {
      expect(CloudProviderChrome.catalogChip('realdebrid'), 'RD');
      expect(CloudProviderChrome.catalogChip('debrid'), 'RD');
      expect(CloudProviderChrome.catalogChip('rd'), 'RD');
      expect(CloudProviderChrome.catalogChip('torbox'), 'TB');
      expect(CloudProviderChrome.catalogChip('auto'), 'AUTO');
      expect(CloudProviderChrome.catalogChip('webdav'), 'AUTO');
      expect(CloudProviderChrome.catalogTitle('realdebrid'), 'Real-Debrid');
      expect(CloudProviderChrome.catalogTitle('auto'), isNull);
    });

    test('bind-source chips use stored ids and Local, not playback chrome', () {
      expect(CloudProviderChrome.sourceChip('rd').label, 'Real-Debrid');
      expect(CloudProviderChrome.sourceChip('debrid').label, 'debrid');
      expect(CloudProviderChrome.sourceChip('torbox').label, 'TorBox');
      expect(
        CloudProviderChrome.sourceChip(SeriesSource.localService).label,
        'Local',
      );
      expect(
        CloudProviderChrome.label(SeriesSource.localService),
        'On-device',
      );
      expect(
        CloudProviderChrome.sourceChip('torbox').color,
        const Color(0xFF3B82F6),
      );
      expect(
        CloudProviderChrome.gradient('torbox').first,
        const Color(0xFF8B5CF6),
      );
      expect(
        CloudProviderChrome.sourceChip('nope').color,
        Colors.white54,
      );
      expect(CloudProviderId.debrid.catalogChoice.key, 'realdebrid');
      expect(CloudProviderId.debrid.catalogChoice.value, 'Real-Debrid');
    });

    test('playlist badges keep empty-as-RD and webdav-as-DV', () {
      expect(CloudProviderChrome.playlistBadge(null), 'RD');
      expect(CloudProviderChrome.playlistBadge(''), 'RD');
      expect(CloudProviderChrome.playlistBadge('realdebrid'), 'RD');
      expect(CloudProviderChrome.playlistBadge('webdav'), 'DV');
      expect(CloudProviderChrome.playlistBadge('pik-pak'), 'PP');
      expect(CloudProviderChrome.playlistBadge('xyz'), 'XY');
      expect(CloudProviderChrome.catalogChip(''), 'AUTO');
      expect(
        CloudProviderId.tryParse('torbox')?.chipCode ?? 'Cached',
        'TB',
      );
      expect(
        CloudProviderId.tryParse('nope')?.chipCode ?? 'Cached',
        'Cached',
      );
    });
  });

  group('CloudPlaylistPayload', () {
    test('Real-Debrid singles store realdebrid + empty url', () {
      final item = CloudPlaylistPayload.build(
        provider: 'debrid',
        result: const CloudPlaybackResult(
          title: 't',
          rdTorrentId: 'RD1',
          restrictedLink: 'https://rd/restrict',
        ),
        torrentHash: 'abc',
        title: 'Show',
        sizeBytes: 10,
        imdbId: 'tt1',
        contentType: 'movie',
        posterUrl: 'https://p',
      );
      expect(item['provider'], 'realdebrid');
      expect(item['kind'], 'single');
      expect(item['url'], '');
      expect(item['rdTorrentId'], 'RD1');
      expect(item['restrictedLink'], 'https://rd/restrict');
      expect(item['imdbId'], 'tt1');
    });

    test('PikPak singles prefer the video file id over the folder id', () {
      final item = CloudPlaylistPayload.build(
        provider: 'pikpak',
        result: const CloudPlaybackResult(
          title: 't',
          pikpakFileId: 'folder',
          pikpakVideoFileId: 'video',
        ),
        torrentHash: 'h',
        title: 'n',
      );
      expect(item['pikpakFileId'], 'video');
      expect(item.containsKey('pikpakFileIds'), isFalse);
    });

    test('TorBox packs collect per-file ids', () {
      final item = CloudPlaylistPayload.build(
        provider: 'torbox',
        result: CloudPlaybackResult(
          title: 't',
          torboxTorrentId: 9,
          playlist: const [
            PlaylistEntry(url: '', title: 'a', torboxFileId: 1),
            PlaylistEntry(url: '', title: 'b', torboxFileId: 2),
          ],
        ),
        torrentHash: 'h',
        title: 'n',
      );
      expect(item['kind'], 'collection');
      expect(item['count'], 2);
      expect(item['torboxTorrentId'], 9);
      expect(item['torboxFileIds'], [1, 2]);
    });
  });

  group('CloudSecretPrefs', () {
    test('keys match CloudProviderId.credentialKey', () {
      expect(
        CloudSecretPrefs.realDebridApiKey,
        CloudProviderId.debrid.credentialKey,
      );
      expect(CloudSecretPrefs.torboxApiKey, CloudProviderId.torbox.credentialKey);
      expect(
        CloudSecretPrefs.premiumizeApiKey,
        CloudProviderId.premiumize.credentialKey,
      );
      expect(
        CloudSecretPrefs.allDebridApiKey,
        CloudProviderId.alldebrid.credentialKey,
      );
      expect(CloudSecretPrefs.pikpakEmail, CloudProviderId.pikpak.credentialKey);
    });
  });

  group('CloudBrowseSelectSource', () {
    Future<void> noop(SeriesSource _) async {}

    test('only premiumize, alldebrid, and pikpak open a browser', () {
      expect(
        CloudBrowseSelectSource.page(
          provider: 'premiumize',
          query: 'q',
          onSourceSelected: noop,
        ),
        isA<PremiumizeFilesScreen>(),
      );
      expect(
        CloudBrowseSelectSource.page(
          provider: 'alldebrid',
          query: 'q',
          onSourceSelected: noop,
        ),
        isA<AllDebridFilesScreen>(),
      );
      expect(
        CloudBrowseSelectSource.page(
          provider: 'pikpak',
          query: 'q',
          onSourceSelected: noop,
        ),
        isA<PikPakFilesScreen>(),
      );
      expect(
        CloudBrowseSelectSource.page(
          provider: 'debrid',
          query: 'q',
          onSourceSelected: noop,
        ),
        isNull,
      );
      expect(
        CloudBrowseSelectSource.page(
          provider: 'rd',
          query: 'q',
          onSourceSelected: noop,
        ),
        isNull,
      );
      expect(
        CloudBrowseSelectSource.page(
          provider: 'torbox',
          query: 'q',
          onSourceSelected: noop,
        ),
        isNull,
      );
    });
  });
}
