import 'dart:io';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Origin pin for the Android TV playback payload cluster that lives at the
/// tail of `lib/services/video_player_launcher.dart`
/// (`_PlaybackContentType`, `_AndroidTvPlaybackPayload`,
/// `_AndroidTvPlaybackItem`, `_AndroidTvSeriesSeason`,
/// `_AndroidTvCollectionGroup`, `_AndroidTvSeriesEpisode`,
/// `_AndroidTvPlaybackPayloadResult`, `_LauncherEntry`,
/// `_AndroidTvPlaylistResolver`, `_AndroidTvPlaybackPayloadBuilder`).
///
/// Those classes are file-private, so the pin drives them through the public
/// entry point that reaches them — `VideoPlayerLauncher.push` with
/// `isAndroidTvOverride` forcing the native-TV branch — and asserts the exact
/// map that would cross the `com.debrify.app/android_tv_player` platform
/// channel as `launchTorrentPlayback`'s `payload`, plus the live playlist
/// resolver, both captured at `VideoPlayerLauncher.debugAndroidTvLaunch`.
///
/// That seam exists because `AndroidTvPlayerBridge.launchTorrentPlayback`
/// returns false off Android before touching the channel, so on a host test
/// runner the launcher would silently fall through to the Flutter player and
/// the payload would never be observable. Everything before the bridge call —
/// playlist normalisation, series parsing, progress merges, payload and
/// resolver construction, serialisation — is the real production code.
///
/// Nothing here imports a launcher-internal file: if the cluster moves, this
/// test must keep passing unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> launched;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? resolveStream;

  setUp(() {
    HttpOverrides.global = _OfflineHttpOverrides();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    launched = <Map<String, dynamic>>[];
    resolveStream = null;
    VideoPlayerLauncher.debugAndroidTvLaunch = (payload, resolver) async {
      launched.add(payload);
      resolveStream = resolver;
      return true;
    };
  });

  tearDown(() {
    VideoPlayerLauncher.debugAndroidTvLaunch = null;
    HttpOverrides.global = null;
  });

  PlaylistEntry entry(String title, {int? sizeBytes, String? provider}) =>
      PlaylistEntry(
        url: 'https://stream.invalid/${title.replaceAll(' ', '_')}.mkv',
        title: title,
        sizeBytes: sizeBytes,
        provider: provider,
      );

  /// Runs the real launcher down the Android TV branch and returns the payload
  /// map handed to the platform channel.
  Future<Map<String, dynamic>> launch(
    WidgetTester tester,
    VideoPlayerLaunchArgs args,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.runAsync(
      // isTrailer skips the app-return observer so no 30s timer outlives the
      // test; the payload build is unaffected by it.
      () => VideoPlayerLauncher.push(captured, args, isTrailer: true),
    );
    await tester.pump();
    expect(launched, hasLength(1), reason: 'native TV launch did not happen');
    return launched.single;
  }

  /// The native activity's own lazy-resolution request, replayed against the
  /// live resolver the launcher handed to the bridge.
  Future<Map<String, dynamic>?> requestTorrentStream(
    Map<String, dynamic> request,
  ) async {
    final resolver = resolveStream;
    expect(resolver, isNotNull, reason: 'no playlist resolver was registered');
    return resolver!(request);
  }

  testWidgets('single content serialises one flat item', (tester) async {
    final movie = entry('Pinned Single Release');
    await PlaybackProgressStore.saveVideoPlaybackState(
      videoTitle: VideoPlayerLauncher.resumeIdForEntry(
        movie,
        fallbackTitle: 'Pinned Single',
      ),
      videoUrl: movie.url,
      positionMs: 640000,
      durationMs: 5400000,
    );

    final payload = await launch(
      tester,
      VideoPlayerLaunchArgs(
        videoUrl: movie.url,
        title: 'Pinned Single',
        subtitle: 'pin-subtitle',
        playlist: [movie],
        isAndroidTvOverride: () => true,
        disableExternalPlayer: true,
        suppressTraktAutoSync: true,
      ),
    );

    expect(payload['version'], 1);
    expect(payload['contentType'], 'single');
    expect(payload['title'], 'Pinned Single');
    expect(payload['subtitle'], 'pin-subtitle');
    expect(payload['startIndex'], 0);
    expect(payload['seasons'], isEmpty);
    expect(payload['collectionGroups'], isNull);

    final items = (payload['items'] as List).cast<Map>();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item['index'], 0);
    expect(item['title'], 'Pinned Single Release');
    expect(item['url'], movie.url);
    expect(item['id'], movie.url);
    expect(item['season'], isNull);
    expect(item['episode'], isNull);
    expect(item['resumePositionMs'], 640000);
    expect(item['durationMs'], 5400000);
    expect(item['watched'], isFalse);
    expect(item.containsKey('traktProgressPercent'), isFalse);
    // Local completion is on whenever no tracker scrobbles this launch.
    expect(payload['localCompletionTracking'], isTrue);
    expect(payload['movieCompletionThreshold'], isA<int>());
    expect(payload['episodeCompletionThreshold'], isA<int>());
  });

  testWidgets('collection content serialises groups and per-file resume', (
    tester,
  ) async {
    final main = entry('Pinned Pack Feature', sizeBytes: 8000000000);
    final extra = entry('Pinned Pack Extra', sizeBytes: 40000000);
    await PlaybackProgressStore.saveVideoPlaybackState(
      videoTitle: VideoPlayerLauncher.resumeIdForEntry(
        extra,
        fallbackTitle: 'Pinned Pack',
      ),
      videoUrl: extra.url,
      positionMs: 123000,
      durationMs: 456000,
    );

    final payload = await launch(
      tester,
      VideoPlayerLaunchArgs(
        videoUrl: main.url,
        title: 'Pinned Pack',
        playlist: [main, extra],
        viewMode: PlaylistViewMode.raw,
        contentType: 'movie',
        isAndroidTvOverride: () => true,
        disableExternalPlayer: true,
        suppressTraktAutoSync: true,
      ),
    );

    expect(payload['contentType'], 'collection');
    final groups = (payload['collectionGroups'] as List).cast<Map>();
    expect(groups, isNotEmpty);
    for (final group in groups) {
      expect(group['name'], isA<String>());
      expect((group['fileIndices'] as List), isNotEmpty);
    }
    final allIndices = groups
        .expand((g) => (g['fileIndices'] as List).cast<int>())
        .toList();
    expect(allIndices..sort(), [0, 1]);

    final items = (payload['items'] as List).cast<Map>();
    expect(items, hasLength(2));
    expect(items[0]['resumePositionMs'], 0);
    expect(items[0]['durationMs'], 0);
    expect(items[1]['resumePositionMs'], 123000);
    expect(items[1]['durationMs'], 456000);
    expect(items[1]['updatedAt'], greaterThan(0));
    expect(items[1]['sizeBytes'], 40000000);
  });

  testWidgets(
    'series content serialises seasons, navigation and local progress',
    (tester) async {
      const imdbId = 'tt7654321';
      const showTitle = 'Pinned Show';
      final s01e01 = entry('Pinned.Show.S01E01.1080p.WEB.mkv');
      final s01e02 = entry('Pinned.Show.S01E02.1080p.WEB.mkv');
      final s02e01 = entry('Pinned.Show.S02E01.1080p.WEB.mkv');

      // Local completion for S01E01 and a local resume for S01E02.
      await PlaybackProgressStore.markEpisodeAsFinished(
        seriesTitle: showTitle,
        season: 1,
        episode: 1,
        imdbId: imdbId,
      );
      // `getLastPlayedEpisode` breaks ties on `updatedAt` by iteration order,
      // so separate the two writes on the real clock to keep the resume pick
      // (and therefore `startIndex`) deterministic.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await PlaybackProgressStore.saveSeriesPlaybackState(
        seriesTitle: showTitle,
        season: 1,
        episode: 2,
        positionMs: 300000,
        durationMs: 2400000,
        imdbId: imdbId,
      );
      // Seeded but doomed: a multi-entry series launch with an IMDb id
      // refreshes the Trakt/Simkl snapshots first, and with no credential that
      // refresh authoritatively CLEARS them. Preserved quirk, asserted below.
      await PlaybackProgressStore.saveEpisodeTraktProgress(
        imdbId: imdbId,
        percents: {'2_1': 11},
      );
      await PlaybackProgressStore.saveEpisodeSimklProgress(
        imdbId: imdbId,
        percents: {'2_1': 47},
      );

      final payload = await launch(
        tester,
        VideoPlayerLaunchArgs(
          videoUrl: s01e01.url,
          title: 'Pinned.Show.S01-S02.1080p.WEB',
          contentTitle: showTitle,
          contentType: 'series',
          contentImdbId: imdbId,
          playlist: [s01e01, s01e02, s02e01],
          isAndroidTvOverride: () => true,
          disableExternalPlayer: true,
          suppressTraktAutoSync: true,
        ),
      );

      expect(payload['contentType'], 'series');
      expect(payload['seriesTitle'], showTitle);
      expect(payload['imdbId'], imdbId);

      final seasons = (payload['seasons'] as List).cast<Map>();
      expect(seasons.map((s) => s['seasonNumber']).toList(), [1, 2]);
      final seasonOne = (seasons[0]['episodes'] as List).cast<Map>();
      expect(seasonOne, hasLength(2));
      expect(seasonOne[0]['season'], 1);
      expect(seasonOne[0]['episode'], 1);
      expect(seasonOne[1]['episode'], 2);
      expect(seasonOne[0].containsKey('description'), isTrue);
      expect(seasonOne[0].containsKey('artwork'), isTrue);
      final seasonTwo = (seasons[1]['episodes'] as List).cast<Map>();
      expect(seasonTwo, hasLength(1));
      expect(seasonTwo[0]['season'], 2);
      expect(seasonTwo[0]['episode'], 1);

      final items = (payload['items'] as List).cast<Map>();
      expect(items, hasLength(3));
      expect(items.map((i) => i['season']).toList(), [1, 1, 2]);
      expect(items.map((i) => i['episode']).toList(), [1, 2, 1]);

      // S01E01: locally finished.
      expect(items[0]['watched'], isTrue);
      // S01E02: local resume flows through untouched.
      expect(items[1]['watched'], isFalse);
      expect(items[1]['resumePositionMs'], 300000);
      expect(items[1]['durationMs'], 2400000);
      // S02E01: no local state, and the disconnected-tracker refresh above
      // wiped the seeded snapshots, so no tracker percent is serialised.
      expect(items[2]['resumePositionMs'], 0);
      for (final item in items) {
        expect(item.containsKey('traktProgressPercent'), isFalse);
      }

      final nextMap = Map<String, dynamic>.from(
        payload['nextEpisodeMap'] as Map,
      );
      final prevMap = Map<String, dynamic>.from(
        payload['prevEpisodeMap'] as Map,
      );
      expect(nextMap['0'], 1);
      expect(nextMap['1'], 2);
      expect(nextMap.containsKey('2'), isFalse);
      expect(prevMap['1'], 0);
      expect(prevMap['2'], 1);
      expect(prevMap.containsKey('0'), isFalse);

      // Series launches start on the first unwatched episode.
      expect(payload['startIndex'], 1);
    },
  );

  testWidgets(
    'series items carry the furthest of the three tracker snapshots',
    (tester) async {
      // `contentType: 'movie'` with a forced series view mode is the one shape
      // that reaches series serialisation WITHOUT the launch-time Trakt/Simkl
      // snapshot refresh, so the stored cross-device percents survive into the
      // payload and the three-way merge is observable.
      const imdbId = 'tt5551234';
      final s01e01 = entry('Merged.Show.S01E01.1080p.WEB.mkv');
      final s01e02 = entry('Merged.Show.S01E02.1080p.WEB.mkv');

      await PlaybackProgressStore.saveEpisodeTraktProgress(
        imdbId: imdbId,
        percents: {'1_1': 11, '1_2': 62},
      );
      await PlaybackProgressStore.saveEpisodeSimklProgress(
        imdbId: imdbId,
        percents: {'1_1': 47},
      );
      await PlaybackProgressStore.saveEpisodeMdblistProgress(
        imdbId: imdbId,
        percents: {'1_1': 23},
      );

      final payload = await launch(
        tester,
        VideoPlayerLaunchArgs(
          videoUrl: s01e01.url,
          title: 'Merged.Show.S01.1080p.WEB',
          contentTitle: 'Merged Show',
          contentType: 'movie',
          viewMode: PlaylistViewMode.series,
          contentImdbId: imdbId,
          playlist: [s01e01, s01e02],
          isAndroidTvOverride: () => true,
          disableExternalPlayer: true,
          suppressTraktAutoSync: true,
        ),
      );

      expect(payload['contentType'], 'series');
      final items = (payload['items'] as List).cast<Map>();
      expect(items, hasLength(2));
      // S01E01: Trakt 11 / Simkl 47 / MDBList 23 → the furthest wins.
      expect(items[0]['traktProgressPercent'], 47);
      // S01E02: only Trakt has a value.
      expect(items[1]['traktProgressPercent'], 62);
      // Tracker progress alone never marks an item watched.
      expect(items[0]['watched'], isFalse);
      expect(items[1]['watched'], isFalse);
      expect(items[0]['resumePositionMs'], 0);
    },
  );

  testWidgets('playlist resolver answers the native lazy-stream request', (
    tester,
  ) async {
    final first = entry('Pinned.Show.S03E01.1080p.WEB.mkv', provider: 'torbox');
    final second = entry('Pinned.Show.S03E02.1080p.WEB.mkv', provider: 'torbox');

    final payload = await launch(
      tester,
      VideoPlayerLaunchArgs(
        videoUrl: first.url,
        title: 'Pinned.Show.S03.1080p.WEB',
        contentTitle: 'Pinned Resolver Show',
        contentType: 'series',
        playlist: [first, second],
        isAndroidTvOverride: () => true,
        disableExternalPlayer: true,
        suppressTraktAutoSync: true,
      ),
    );

    final items = (payload['items'] as List).cast<Map>();
    final targetResumeId = items[1]['resumeId'] as String;

    final byResumeId = await tester.runAsync(
      () => requestTorrentStream({'resumeId': targetResumeId}),
    );
    expect(byResumeId, isNotNull);
    expect(byResumeId!['url'], second.url);
    expect(byResumeId['resumeId'], targetResumeId);
    expect(byResumeId['index'], 1);
    expect(byResumeId['provider'], 'torbox');

    final byFirstIndex = await tester.runAsync(
      () => requestTorrentStream({'index': 0}),
    );
    expect(byFirstIndex, isNotNull);
    expect(byFirstIndex!['url'], first.url);
    expect(byFirstIndex['index'], 0);

    final bySecondIndex = await tester.runAsync(
      () => requestTorrentStream({'index': 1}),
    );
    expect(bySecondIndex, isNotNull);
    expect(bySecondIndex!['url'], second.url);
    expect(bySecondIndex['index'], 1);
    expect(bySecondIndex['resumeId'], targetResumeId);

    // Unknown resumeId and out-of-range index both resolve to nothing.
    final missing = await tester.runAsync(
      () => requestTorrentStream({'resumeId': 'no-such-entry', 'index': 99}),
    );
    expect(missing, isNull);
  });
}

/// Every outbound HTTP call in this path (Cinemeta / TVMaze enrichment) is
/// optional best-effort work; refuse it so the pin never touches the network.
class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

class _OfflineHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter || invocation.isGetter) return null;
    throw const SocketException('offline pin test');
  }
}
