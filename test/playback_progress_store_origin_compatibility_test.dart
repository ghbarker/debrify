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

  test(
    'continue watching insert is case-sensitive but removal is normalized',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await StorageService.saveContinueWatchingItem(
        imdbId: 'TT1',
        title: 'Upper',
        contentType: 'movie',
      );
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt1',
        title: 'Lower',
        contentType: 'movie',
      );
      expect((await StorageService.getContinueWatchingItems()).length, 2);
      final raw = jsonDecode(prefs.getString('continue_watching_v1')!) as List;
      expect(raw.first, containsPair('posterUrl', null));
      expect(raw.first['updatedAt'], isA<int>());
      await StorageService.removeContinueWatchingItem(' TT1 ');
      expect(await StorageService.getContinueWatchingItems(), isEmpty);
      await prefs.setString(
        'continue_watching_v1',
        jsonEncode([
          for (var i = 0; i < 51; i++) {'imdbId': 'tt$i', 'updatedAt': i},
        ]),
      );
      await StorageService.saveContinueWatchingItem(
        imdbId: 'new',
        title: 'New',
        contentType: 'series',
      );
      final items = await StorageService.getContinueWatchingItems();
      expect(items.length, 50);
      expect(items.first['imdbId'], 'new');
      expect(items.any((row) => row['imdbId'] == 'tt50'), isFalse);
      await StorageService.clearContinueWatching();
      expect(prefs.containsKey('continue_watching_v1'), isFalse);
    },
  );

  test(
    'explicit series completion stores sorted strings and only notifies changes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final revision = StorageService.localCompletionRevision;
      final start = revision.value;
      await StorageService.setSeriesExplicitlyWatched(' TT2 ', watched: true);
      await StorageService.setSeriesExplicitlyWatched('tt1', watched: true);
      await StorageService.setSeriesExplicitlyWatched('TT2', watched: true);
      await StorageService.setSeriesExplicitlyWatched(' ', watched: true);
      expect(prefs.getStringList('explicitly_watched_series_v1'), [
        'tt1',
        'tt2',
      ]);
      expect(await StorageService.getExplicitlyWatchedSeriesIds(), {
        'tt1',
        'tt2',
      });
      expect(revision.value - start, 2);
      await StorageService.setSeriesExplicitlyWatched('tt1', watched: false);
      await StorageService.setSeriesExplicitlyWatched('tt2', watched: false);
      expect(prefs.containsKey('explicitly_watched_series_v1'), isFalse);
      expect(revision.value - start, 4);
    },
  );

  test(
    'poster and IMDb use different provider precedence and preserve existing IMDb',
    () async {
      await StorageService.savePlaylistItemsRaw([
        {
          'provider': 'torbox',
          'torboxTorrentId': 7,
          'title': 'Torbox',
          'imdbId': 'tt-old',
        },
        {
          'provider': 'premiumize',
          'torrent_hash': 'ABC',
          'title': 'Premiumize',
        },
        {
          'provider': 'pikpak',
          'pikpakFileIds': ['first', 'second'],
        },
        {
          'provider': 'webdav',
          'webdavServerId': 'SERVER',
          'webdavPath': '/Case',
        },
      ]);
      expect(
        await StorageService.updatePlaylistItemPoster(
          'synthetic-poster',
          torboxTorrentId: '7',
          premiumizeHash: 'abc',
        ),
        isTrue,
      );
      expect(
        await StorageService.updatePlaylistItemImdbId(
          'tt-new',
          torboxTorrentId: '7',
          premiumizeHash: 'abc',
        ),
        isTrue,
      );
      var rows = await StorageService.getPlaylistItemsRaw();
      expect(rows[0]['posterUrl'], 'synthetic-poster');
      expect(rows[0]['imdbId'], 'tt-old');
      expect(rows[1]['imdbId'], 'tt-new');
      expect(
        await StorageService.updatePlaylistItemImdbId(
          'tt-replacement',
          torboxTorrentId: '7',
        ),
        isTrue,
      );
      expect(
        (await StorageService.getPlaylistItemsRaw())[0]['imdbId'],
        'tt-old',
      );
      expect(
        await StorageService.updatePlaylistItemImdbId(
          'tt-replacement',
          torboxTorrentId: '7',
          force: true,
        ),
        isTrue,
      );
      expect(
        await StorageService.updatePlaylistItemPoster(
          'miss',
          pikpakCollectionId: 'second',
        ),
        isFalse,
      );
      expect(
        await StorageService.updatePlaylistItemPoster(
          'hit',
          pikpakCollectionId: 'first',
        ),
        isTrue,
      );
      expect(
        await StorageService.updatePlaylistItemPoster(
          'web',
          webDavServerId: 'server',
          webDavPath: '/Case',
        ),
        isTrue,
      );
      expect(
        await StorageService.updatePlaylistItemPoster(
          'miss',
          webDavServerId: 'server',
          webDavPath: '/case',
        ),
        isFalse,
      );
      rows = await StorageService.getPlaylistItemsRaw();
      expect(rows[0]['imdbId'], 'tt-replacement');
      expect(rows[2]['posterUrl'], 'hit');
      expect(rows[3]['posterUrl'], 'web');
    },
  );
}
