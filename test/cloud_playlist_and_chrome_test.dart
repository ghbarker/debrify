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
import 'package:debrify/services/storage/resume_prefs.dart';
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
      expect(CloudProviderChrome.code('debrid'), 'RD');
      expect(CloudProviderChrome.code(''), '·');
      expect(CloudProviderChrome.code('xyz'), 'X');
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

  group('CloudSecretPrefs / ResumePrefs', () {
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
      expect(RdPrefs.apiKeyKey, 'real_debrid_api_key');
      expect(ResumePrefs.videoResumeKey, 'video_resume_v1');
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
