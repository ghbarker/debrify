import 'dart:convert';

import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Real API origin: d8e940189e54e6376ad7df69c0ab3efe40a76e5e.
// This file must run green and be committed before any S2-6 production move.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playlist dedupe preserves provider dialects and ordered file IDs', () {
    final cases = <(Map<String, dynamic>, String)>[
      ({'torrent_hash': 'ABC'}, 'realdebrid|hash:abc'),
      ({'provider': 'RD', 'rdTorrentId': 'ABC'}, 'rd|rd:abc'),
      (
        {
          'provider': 'webdav',
          'webdavServerId': 'SERVER',
          'webdavPath': '/Case/A',
        },
        'webdav|server:server|path:/Case/A',
      ),
      (
        {'provider': 'TorBox', 'torboxTorrentId': 7, 'torboxFileId': 2},
        'torbox|torbox:7:file:2',
      ),
      (
        {
          'provider': 'torbox',
          'torboxTorrentId': 7,
          'torboxFileIds': [2, 1],
        },
        'torbox|torbox:7:files:2,1',
      ),
      ({'provider': 'pikpak', 'pikpakFileId': 'XYZ'}, 'pikpak|pikpak:file:xyz'),
      (
        {
          'provider': 'pikpak',
          'pikpakFileIds': ['B', 'A'],
        },
        'pikpak|pikpak:files:b,a',
      ),
      (
        {'provider': 'premiumize', 'premiumizeItemId': 'ABC'},
        'premiumize|premiumize:item:abc',
      ),
      (
        {
          'provider': 'premiumize',
          'premiumizeItemIds': ['B', 'A'],
        },
        'premiumize|premiumize:items:b,a',
      ),
      (
        {
          'provider': 'Unknown',
          'url': ' HTTPS://EXAMPLE.INVALID/A ',
          'title': ' Title ',
        },
        'unknown|https://example.invalid/a|title',
      ),
    ];
    for (final (input, expected) in cases) {
      expect(
        StorageService.computePlaylistDedupeKey(input),
        expected,
        reason: '$input',
      );
    }
  });

  test(
    'playlist raw JSON preserves values and reads external changes freshly',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final rows = <Map<String, dynamic>>[
        {
          'title': 'Synthetic',
          'position': 7,
          'ratio': 1.0,
          'enabled': false,
          'ids': ['2', '1'],
        },
      ];
      await StorageService.savePlaylistItemsRaw(rows);
      expect(prefs.getString('user_playlist_v1'), jsonEncode(rows));
      expect(await StorageService.getPlaylistItemsRaw(), rows);
      await prefs.setString('user_playlist_v1', '[false,{"title":"External"}]');
      expect(await StorageService.getPlaylistItemsRaw(), [
        {'title': 'External'},
      ]);
      for (final raw in ['{', '{}', 'null']) {
        await prefs.setString('user_playlist_v1', raw);
        expect(await StorageService.getPlaylistItemsRaw(), isEmpty);
      }
      await StorageService.clearPlaylist();
      expect(prefs.containsKey('user_playlist_v1'), isFalse);
    },
  );

  test(
    'playlist insertion dedupes and removal uses the same persisted identity',
    () async {
      final item = <String, dynamic>{
        'provider': 'torbox',
        'torboxTorrentId': 7,
        'title': 'Synthetic',
      };
      expect(await StorageService.addPlaylistItemRaw(item), isTrue);
      expect(
        await StorageService.addPlaylistItemRaw({...item, 'title': 'Renamed'}),
        isFalse,
      );
      expect(item.containsKey('addedAt'), isFalse);
      final saved = (await StorageService.getPlaylistItemsRaw()).single;
      expect(saved['addedAt'], isA<int>());
      expect(StorageService.getPlaylistItemLastPlayed(saved), isNull);
      await StorageService.updatePlaylistItemLastPlayed(item);
      expect(
        StorageService.getPlaylistItemLastPlayed(
          (await StorageService.getPlaylistItemsRaw()).single,
        ),
        isA<int>(),
      );
      await StorageService.removePlaylistItemByKey('torbox|torbox:7');
      expect(await StorageService.getPlaylistItemsRaw(), isEmpty);
    },
  );

  test(
    'playlist metadata preserves false favorite-key quirk and repairs invalid JSON',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final item = <String, dynamic>{'torrent_hash': 'ABC'};
      await prefs.setString(
        'playlist_favorites_v1',
        '{"realdebrid|hash:abc":false}',
      );
      expect(await StorageService.isPlaylistItemFavorited(item), isFalse);
      expect(await StorageService.getPlaylistFavoriteKeys(), {
        'realdebrid|hash:abc',
      });
      await StorageService.setPlaylistItemFavorited(item, true);
      expect(
        prefs.getString('playlist_favorites_v1'),
        '{"realdebrid|hash:abc":true}',
      );
      await StorageService.setPlaylistItemFavorited(item, false);
      expect(prefs.getString('playlist_favorites_v1'), '{}');
      await prefs.setString('playlist_view_modes_v1', '{');
      expect(await StorageService.getPlaylistItemViewMode(item), isNull);
      await StorageService.savePlaylistItemViewMode(
        item,
        'custom-unvalidated-mode',
      );
      expect(
        prefs.getString('playlist_view_modes_v1'),
        '{"realdebrid|hash:abc":"custom-unvalidated-mode"}',
      );
      expect(
        await StorageService.getPlaylistItemViewMode(item),
        'custom-unvalidated-mode',
      );
      for (final key in [
        'playlist_poster_overrides_v1',
        'tvmaze_series_mappings',
      ]) {
        await prefs.setString(key, '{}');
      }
      await prefs.setString('unrelated', 'keep');
      await StorageService.clearAllPlaylistMetadata();
      expect(prefs.getKeys(), {'unrelated'});
    },
  );

  test(
    'series and video track preferences preserve nested keys and fresh reads',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await StorageService.saveSeriesTrackPreferences(
        seriesTitle: 'A.B',
        audioTrackId: 'auto',
        subtitleTrackId: 'no',
      );
      await StorageService.saveVideoTrackPreferences(
        videoTitle: 'A.B',
        audioTrackId: '2',
        subtitleTrackId: '3',
      );
      final map =
          jsonDecode(prefs.getString('playback_state_v1')!)
              as Map<String, dynamic>;
      expect(map.keys.toSet(), {'series_a_b', 'video_a_b'});
      final series = await StorageService.getSeriesTrackPreferences(
        seriesTitle: 'A.B',
      );
      expect(series!['audioTrackId'], 'auto');
      expect(series['subtitleTrackId'], 'no');
      expect(series['updatedAt'], isA<int>());
      final video = await StorageService.getVideoTrackPreferences(
        videoTitle: 'A.B',
      );
      expect(video!['audioTrackId'], '2');
      expect(video['subtitleTrackId'], '3');
      await prefs.setString('playback_state_v1', '{}');
      expect(
        await StorageService.getSeriesTrackPreferences(seriesTitle: 'A.B'),
        isNull,
      );
      expect(
        await StorageService.getVideoTrackPreferences(videoTitle: 'A.B'),
        isNull,
      );
    },
  );

  test(
    'local revision object survives profile-cache reset and differs from remote revision',
    () {
      final local = StorageService.localCompletionRevision;
      expect(identical(local, StorageService.movieFinishedRevision), isFalse);
      StorageService.resetProfileCaches();
      expect(identical(local, StorageService.localCompletionRevision), isTrue);
    },
  );
}
