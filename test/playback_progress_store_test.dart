import 'dart:convert';

import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/storage_key_ownership.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'facade and store share one notifier and observe writes in both directions',
    () async {
      final notifier = StorageService.localCompletionRevision;
      expect(
        identical(notifier, PlaybackProgressStore.localCompletionRevision),
        isTrue,
      );
      final before = notifier.value;
      await PlaybackProgressStore.setSeriesExplicitlyWatched('TT2', watched: true);
      expect(await PlaybackProgressStore.getExplicitlyWatchedSeriesIds(), {
        'tt2',
      });
      await PlaybackProgressStore.setSeriesExplicitlyWatched(
        'TT1',
        watched: true,
      );
      expect(await PlaybackProgressStore.getExplicitlyWatchedSeriesIds(), {
        'tt1',
        'tt2',
      });
      expect(notifier.value, before + 2);
      StorageService.resetProfileCaches();
      expect(
        identical(notifier, PlaybackProgressStore.localCompletionRevision),
        isTrue,
      );
      expect(notifier.value, before + 2);
    },
  );

  test(
    'outside-caller playback bridge remains a fresh decoded typed snapshot',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'playback_state_v1',
        '{"synthetic":{"position":7,"speed":1.0,"finished":false}}',
      );
      final first = await PlaybackProgressStore.readPlaybackStateMap();
      expect(first['synthetic']['position'], isA<int>());
      expect(first['synthetic']['speed'], isA<double>());
      first['synthetic']['position'] = 99;
      expect(
        (await PlaybackProgressStore.readPlaybackStateMap())['synthetic']['position'],
        7,
      );
      await PlaybackProgressStore.writePlaybackStateMap(first);
      expect(prefs.getString('playback_state_v1'), jsonEncode(first));
      await prefs.setString('playback_state_v1', '{}');
      expect(await PlaybackProgressStore.readPlaybackStateMap(), isEmpty);
    },
  );

  test(
    'store owns exact persisted names including legacy cleanup dependencies',
    () {
      expect(
        StorageKeyOwnership.keysFor(StorageKeyStore.playbackProgressStore),
        {
          'continue_watching_v1',
          'episode_mdblist_progress_v1',
          'episode_simkl_progress_v1',
          'episode_trakt_progress_v2',
          'explicitly_watched_series_v1',
          'finished_movies_v1',
          'playback_state_v1',
          'playlist_favorites_v1',
          'user_playlist_v1',
          'playlist_poster_overrides_v1',
          'playlist_view_modes_v1',
          'tvmaze_series_mappings',
          'video_resume_v1',
          'local_series_completion_v1',
          'local_series_completion_calendar_checked_at_v1',
          'local_series_completion_calendar_attempted_at_v1',
          'movie_completion_threshold',
          'episode_completion_threshold',
          'playback_completion_migration_generation',
          'resume_ghost_purge_generation',
        },
      );
    },
  );
}
