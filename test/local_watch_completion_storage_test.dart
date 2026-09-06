import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
  });

  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
  });

  test('movie and episode completion thresholds are independent', () async {
    expect(
      await PlaybackProgressStore.getMovieCompletionThreshold(),
      StorageService.defaultLocalCompletionThreshold,
    );
    expect(
      await PlaybackProgressStore.getEpisodeCompletionThreshold(),
      StorageService.defaultLocalCompletionThreshold,
    );

    await PlaybackProgressStore.setMovieCompletionThreshold(90);
    await PlaybackProgressStore.setEpisodeCompletionThreshold(75);

    expect(await PlaybackProgressStore.getMovieCompletionThreshold(), 90);
    expect(await PlaybackProgressStore.getEpisodeCompletionThreshold(), 75);
  });

  test('finishing a local movie clears resume and continue watching', () async {
    await PlaybackProgressStore.saveContinueWatchingItem(
      imdbId: 'TT001',
      title: 'Example Movie',
      contentType: 'movie',
    );
    await PlaybackProgressStore.saveVideoPlaybackState(
      videoTitle: 'Example Movie',
      videoUrl: 'https://example.com/movie.m3u8',
      positionMs: 64000,
      durationMs: 120000,
      imdbId: 'TT001',
    );

    await PlaybackProgressStore.markMovieAsFinished('TT001');

    // Simulate a final autosave racing with the completion cleanup. The local
    // completed marker remains authoritative until a deliberate rewatch.
    await PlaybackProgressStore.saveVideoPlaybackState(
      videoTitle: 'Example Movie',
      videoUrl: 'https://example.com/movie.m3u8',
      positionMs: 96000,
      durationMs: 120000,
      imdbId: 'TT001',
    );

    expect(await PlaybackProgressStore.isMovieFinished('tt001'), isTrue);
    expect(
      await StorageService.getVideoPlaybackState(videoTitle: 'Example Movie'),
      isNull,
    );
    expect(await PlaybackProgressStore.getVideoPlaybackStateByImdbId('tt001'), isNull);
    expect(await PlaybackProgressStore.getContinueWatchingItems(), isEmpty);

    await PlaybackProgressStore.unmarkMovieAsFinished('tt001');
    expect(await PlaybackProgressStore.isMovieFinished('tt001'), isFalse);
  });

  test('clearing playlist progress invalidates local completion', () async {
    await PlaybackProgressStore.saveSeriesPlaybackState(
      seriesTitle: 'Example Series',
      season: 1,
      episode: 1,
      positionMs: 1000,
      durationMs: 1000,
      imdbId: 'tt-series',
    );
    await PlaybackProgressStore.markEpisodeAsFinished(
      seriesTitle: 'Example Series',
      season: 1,
      episode: 1,
      imdbId: 'tt-series',
    );
    final revisionBefore = StorageService.localCompletionRevision.value;

    await PlaybackProgressStore.clearPlaylistProgress(title: 'Example Series');

    expect(
      await PlaybackProgressStore.isEpisodeFinished(
        seriesTitle: 'Example Series',
        season: 1,
        episode: 1,
      ),
      isFalse,
    );
    expect(StorageService.localCompletionRevision.value, revisionBefore + 1);
  });

  test('clearing playback by IMDb invalidates local completion', () async {
    await PlaybackProgressStore.markEpisodeAsFinished(
      seriesTitle: 'IMDb Clear Show',
      season: 1,
      episode: 1,
      imdbId: 'tt-imdb-clear',
    );
    final revisionBefore = StorageService.localCompletionRevision.value;

    await PlaybackProgressStore.clearPlaybackStateByImdbId('TT-IMDB-CLEAR');

    expect(
      await PlaybackProgressStore.isEpisodeFinished(
        seriesTitle: 'IMDb Clear Show',
        season: 1,
        episode: 1,
      ),
      isFalse,
    );
    expect(StorageService.localCompletionRevision.value, revisionBefore + 1);
  });

  test('finished episode index unions duplicate IMDb records', () async {
    await PlaybackProgressStore.markEpisodeAsFinished(
      seriesTitle: 'Original Title',
      season: 1,
      episode: 1,
      imdbId: 'tt-duplicate',
    );
    await PlaybackProgressStore.markEpisodeAsFinished(
      seriesTitle: 'Localized Title',
      season: 1,
      episode: 2,
      imdbId: 'tt-duplicate',
    );

    final index = await PlaybackProgressStore.getFinishedSeriesEpisodeIndex();
    expect(index['tt-duplicate']?['1'], {1, 2});
    expect(
      await PlaybackProgressStore.getFinishedEpisodesByImdbId(imdbId: 'tt-duplicate'),
      {
        '1': {1, 2},
      },
    );
  });

  test('playback removes the matching local watchlist title', () async {
    final item = StremioMeta(
      id: 'tt-watchlist-play',
      imdbId: 'tt-watchlist-play',
      type: 'movie',
      name: 'Watchlist Movie',
    );
    await MyWatchlistStore.setMyWatchlistItem(item, true);

    expect(
      await StorageService.removeMyWatchlistItemForPlayback(
        imdbId: 'TT-WATCHLIST-PLAY',
        contentType: 'movie',
        title: 'Different presentation title',
      ),
      isTrue,
    );
    expect(await MyWatchlistStore.getMyWatchlistItems(), isEmpty);
  });

  test(
    'existing playback is migrated once using separate thresholds',
    () async {
      await PlaybackProgressStore.setMovieCompletionThreshold(90);
      await PlaybackProgressStore.setEpisodeCompletionThreshold(75);

      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'tt-movie-done',
        title: 'Done Movie',
        contentType: 'movie',
      );
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'tt-movie-partial',
        title: 'Partial Movie',
        contentType: 'movie',
      );
      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: 'Done Movie',
        videoUrl: 'https://example.com/done.m3u8',
        positionMs: 900,
        durationMs: 1000,
        imdbId: 'tt-movie-done',
      );
      await StorageService.upsertVideoResume('Done Movie', {
        'positionMs': 900,
        'durationMs': 1000,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': 1,
      });
      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: 'Partial Movie',
        videoUrl: 'https://example.com/partial.m3u8',
        positionMs: 850,
        durationMs: 1000,
        imdbId: 'tt-movie-partial',
      );
      await PlaybackProgressStore.saveSeriesPlaybackState(
        seriesTitle: 'Example Series',
        season: 1,
        episode: 1,
        positionMs: 750,
        durationMs: 1000,
        imdbId: 'tt-series',
      );
      await PlaybackProgressStore.saveSeriesPlaybackState(
        seriesTitle: 'Example Series',
        season: 1,
        episode: 2,
        positionMs: 740,
        durationMs: 1000,
        imdbId: 'tt-series',
      );

      await PlaybackProgressStore.migrateExistingPlaybackCompletionThresholds();

      expect(await PlaybackProgressStore.isMovieFinished('tt-movie-done'), isTrue);
      expect(await PlaybackProgressStore.isMovieFinished('tt-movie-partial'), isFalse);
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'Done Movie'),
        isNull,
      );
      expect(await StorageService.getVideoResume('Done Movie'), isNull);
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'Partial Movie'),
        isNotNull,
      );
      expect(
        await PlaybackProgressStore.isEpisodeFinished(
          seriesTitle: 'Example Series',
          season: 1,
          episode: 1,
        ),
        isTrue,
      );
      expect(
        await PlaybackProgressStore.isEpisodeFinished(
          seriesTitle: 'Example Series',
          season: 1,
          episode: 2,
        ),
        isFalse,
      );
      expect(
        (await PlaybackProgressStore.getContinueWatchingItems())
            .map((item) => item['imdbId'])
            .toList(),
        ['tt-movie-partial'],
      );

      // The generation marker makes this a one-time adoption: changing the
      // threshold later must not retroactively migrate more old entries.
      await PlaybackProgressStore.setMovieCompletionThreshold(80);
      await PlaybackProgressStore.migrateExistingPlaybackCompletionThresholds();
      expect(await PlaybackProgressStore.isMovieFinished('tt-movie-partial'), isFalse);
    },
  );
}
