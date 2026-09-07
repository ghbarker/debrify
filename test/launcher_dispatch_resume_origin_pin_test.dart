import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

/// Origin pin for the launcher's provider dispatch and its two resume
/// statics, all in `lib/services/video_player_launcher.dart`:
/// `LauncherProviderDispatch` and the `VideoPlayerLauncher.resumeIdForEntry`
/// / `VideoPlayerLauncher.readMovieResumeState` pair that forwards into it and
/// into `LocalPlaybackResumeResolver`.
///
/// `test/cloud_launcher_bulk_add_strings_test.dart` already executes the
/// resume-id string grammar, the analytics provider labels and
/// `isKnownDebridCdnHost`. This pin covers what that file does not:
///
///  * `portForPlayback` called directly — the `fromPlaybackId` lookup that
///    matches the enum `name` exactly (`debrid` resolves, `realdebrid` / `rd`
///    / `real-debrid` do not, even though `CloudProviderId.tryParse` accepts
///    them), the `toLowerCase()` normalisation, and the read through the
///    live `CloudProviderRegistry.instance`;
///  * the `analyticsLabel` precedence band `stremio_tv` > `iptv` > `stremio`
///    that sits between the arg-field ids and the playlist / URL fallbacks,
///    plus the empty-list falls-through cases;
///  * `readMovieResumeState`'s `fallbackTitle` and `policy` forwarding, and
///    the fact that its lookup key is exactly `resumeIdForEntry`'s output.
///
/// The three `launcher.contains('LauncherProviderDispatch.…')` assertions in
/// `cloud_launcher_bulk_add_strings_test.dart` (lines 432/433/435) read the
/// launcher's source text; they are not execution and pin nothing about
/// behaviour.
///
/// Nothing here imports a launcher-internal file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _installFakes();
  });

  tearDown(CloudProviderRegistry.debugReset);

  group('LauncherProviderDispatch.portForPlayback', () {
    test('resolves through the live registry instance', () {
      final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
      _installFakes(torbox: torbox);

      expect(
        LauncherProviderDispatch.portForPlayback('torbox'),
        same(torbox),
      );
    });

    test('matches the playback id exactly — not tryParse spellings', () {
      // `debrid` is Real-Debrid's playbackId (the enum name).
      expect(
        LauncherProviderDispatch.portForPlayback('debrid')?.id,
        CloudProviderId.debrid,
      );
      // These all parse to Real-Debrid via CloudProviderId.tryParse, but
      // fromPlaybackId compares against the enum name, so dispatch misses.
      expect(CloudProviderId.tryParse('realdebrid'), CloudProviderId.debrid);
      expect(CloudProviderId.tryParse('rd'), CloudProviderId.debrid);
      expect(CloudProviderId.tryParse('real_debrid'), CloudProviderId.debrid);
      expect(LauncherProviderDispatch.portForPlayback('realdebrid'), isNull);
      expect(LauncherProviderDispatch.portForPlayback('rd'), isNull);
      expect(LauncherProviderDispatch.portForPlayback('real-debrid'), isNull);
      expect(LauncherProviderDispatch.portForPlayback('real_debrid'), isNull);
    });

    test('lower-cases the input but does not trim it', () {
      expect(
        LauncherProviderDispatch.portForPlayback('TorBox')?.id,
        CloudProviderId.torbox,
      );
      expect(
        LauncherProviderDispatch.portForPlayback('PIKPAK')?.id,
        CloudProviderId.pikpak,
      );
      expect(LauncherProviderDispatch.portForPlayback(' torbox '), isNull);
    });

    test('null, empty and unknown provider strings resolve to nothing', () {
      expect(LauncherProviderDispatch.portForPlayback(null), isNull);
      expect(LauncherProviderDispatch.portForPlayback(''), isNull);
      expect(LauncherProviderDispatch.portForPlayback('nosuchprovider'), isNull);
    });

    test('an unregistered id resolves to nothing, not an exception', () {
      CloudProviderRegistry.instance = CloudProviderRegistry([
        FakeCloudProvider(id: CloudProviderId.torbox),
      ]);

      expect(
        LauncherProviderDispatch.portForPlayback('torbox')?.id,
        CloudProviderId.torbox,
      );
      expect(LauncherProviderDispatch.portForPlayback('pikpak'), isNull);
      expect(LauncherProviderDispatch.portForPlayback('debrid'), isNull);
    });

    test('a missing port makes resumeIdForEntry fall back to the hash', () {
      CloudProviderRegistry.instance = CloudProviderRegistry([
        FakeCloudProvider(id: CloudProviderId.debrid),
      ]);

      final entry = _entry(
        provider: 'torbox',
        torboxTorrentId: 5,
        torboxFileId: 6,
      );
      expect(LauncherProviderDispatch.portForPlayback('torbox'), isNull);
      expect(
        LauncherProviderDispatch.resumeIdForEntry(entry),
        'File.Name'.hashCode.toString(),
      );
      expect(
        VideoPlayerLauncher.resumeIdForEntry(entry),
        'File.Name'.hashCode.toString(),
      );
    });
  });

  group('LauncherProviderDispatch.analyticsLabel — the middle band', () {
    const url = 'https://cdn.example/a';

    test('stremio_tv outranks iptv, stremio, playlist and URL', () {
      expect(
        LauncherProviderDispatch.analyticsLabel(
          VideoPlayerLaunchArgs(
            videoUrl: 'https://mypikpak.com/file',
            title: 't',
            stremioTvChannels: const [
              {'id': 'c1'},
            ],
            iptvChannels: const [],
            stremioSources: [_source()],
            playlist: [_entry(provider: 'torbox', torboxFileId: 1)],
          ),
        ),
        'stremio_tv',
      );
    });

    test('iptv outranks stremio, playlist and URL', () {
      expect(
        LauncherProviderDispatch.analyticsLabel(
          VideoPlayerLaunchArgs(
            videoUrl: 'https://mypikpak.com/file',
            title: 't',
            iptvChannels: const [],
            stremioSources: [_source()],
          ),
        ),
        'iptv',
      );
    });

    test('an empty stremioSources list is not a stremio launch', () {
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(
            videoUrl: url,
            title: 't',
            stremioSources: [],
          ),
        ),
        'direct',
      );
      expect(
        LauncherProviderDispatch.analyticsLabel(
          VideoPlayerLaunchArgs(
            videoUrl: url,
            title: 't',
            stremioSources: [_source()],
          ),
        ),
        'stremio',
      );
    });

    test('stremio outranks the playlist and URL fallbacks', () {
      expect(
        LauncherProviderDispatch.analyticsLabel(
          VideoPlayerLaunchArgs(
            videoUrl: 'https://s.torbox.app/file',
            title: 't',
            stremioSources: [_source()],
            playlist: [_entry(provider: 'pikpak', pikpakFileId: 'p1')],
          ),
        ),
        'stremio',
      );
    });

    test('the playlist label outranks the URL label', () {
      expect(
        LauncherProviderDispatch.analyticsLabel(
          VideoPlayerLaunchArgs(
            videoUrl: 'https://s.torbox.app/file',
            title: 't',
            playlist: [_entry(provider: 'pikpak', pikpakFileId: 'p1')],
          ),
        ),
        'pikpak',
      );
      // An empty playlist yields no label, so the URL is consulted.
      expect(
        LauncherProviderDispatch.analyticsPlaylistLabel(const []),
        isNull,
      );
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(
            videoUrl: 'https://s.torbox.app/file',
            title: 't',
            playlist: [],
          ),
        ),
        'torbox',
      );
    });

    test('an unparseable or hostless URL falls through to direct', () {
      expect(LauncherProviderDispatch.analyticsUrlLabel('/local/file.mkv'), isNull);
      expect(
        LauncherProviderDispatch.analyticsLabel(
          const VideoPlayerLaunchArgs(videoUrl: '/local/file.mkv', title: 't'),
        ),
        'direct',
      );
    });
  });

  group('VideoPlayerLauncher.resumeIdForEntry', () {
    test('forwards fallbackTitle and strips only the last extension', () {
      const blank = PlaylistEntry(url: 'https://x/y', title: '');

      expect(
        VideoPlayerLauncher.resumeIdForEntry(blank, fallbackTitle: 'A.B.mkv'),
        'A.B'.hashCode.toString(),
      );
      expect(
        VideoPlayerLauncher.resumeIdForEntry(blank),
        ''.hashCode.toString(),
      );
      expect(
        VideoPlayerLauncher.resumeIdForEntry(
          const PlaylistEntry(url: 'https://x/y', title: 'Has.Title.mkv'),
          fallbackTitle: 'Ignored',
        ),
        'Has.Title'.hashCode.toString(),
      );
    });

    test('is the same function as the dispatch static it forwards to', () {
      _installFakes(torbox: _HashesCapFake(id: CloudProviderId.torbox));
      final cases = <PlaylistEntry>[
        _entry(provider: 'torbox', torboxWebDownloadId: 3, torboxFileId: 4),
        _entry(provider: 'pikpak', pikpakFileId: 'pp'),
        const PlaylistEntry(url: 'https://x/y', title: ''),
      ];
      for (final entry in cases) {
        expect(
          VideoPlayerLauncher.resumeIdForEntry(entry, fallbackTitle: 'Fb.mkv'),
          LauncherProviderDispatch.resumeIdForEntry(
            entry,
            fallbackTitle: 'Fb.mkv',
          ),
        );
      }
    });
  });

  group('VideoPlayerLauncher.readMovieResumeState', () {
    test('keys the lookup by resumeIdForEntry, fallbackTitle included', () async {
      const blank = PlaylistEntry(url: 'https://x/blank.mkv', title: '');
      final key = VideoPlayerLauncher.resumeIdForEntry(
        blank,
        fallbackTitle: 'Fallback Movie.mkv',
      );

      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: key,
        videoUrl: blank.url,
        positionMs: 1234000,
        durationMs: 7200000,
      );

      final withFallback = await VideoPlayerLauncher.readMovieResumeState(
        entry: blank,
        imdbId: null,
        fallbackTitle: 'Fallback Movie.mkv',
      );
      expect(withFallback?['positionMs'], 1234000);

      // Without the fallback the key is the empty-name hash, which has no
      // record — the fallback is load-bearing, not decoration.
      final withoutFallback = await VideoPlayerLauncher.readMovieResumeState(
        entry: blank,
        imdbId: null,
      );
      expect(withoutFallback, isNull);
    });

    test('matches LocalPlaybackResumeResolver.movie for the same key', () async {
      final entry = _entry(title: 'Some.Movie.2019.mkv');
      final key = VideoPlayerLauncher.resumeIdForEntry(entry);

      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: key,
        videoUrl: entry.url,
        positionMs: 555000,
        durationMs: 7200000,
        imdbId: 'tt0000001',
      );

      final direct = await LocalPlaybackResumeResolver.movie(
        resumeId: key,
        imdbId: 'tt0000001',
        policy: PlaybackResumePolicy.sourceSpecific,
      );
      final viaLauncher = await VideoPlayerLauncher.readMovieResumeState(
        entry: entry,
        imdbId: 'tt0000001',
      );

      expect(viaLauncher?['positionMs'], direct?['positionMs']);
      expect(viaLauncher?['positionMs'], 555000);
    });

    test('forwards the policy, defaulting to source-specific', () async {
      // The exact record deliberately predates IMDb ids being written into
      // playback state, so the canonical scan can only ever find the other
      // release — no updatedAt tie-break decides this test.
      final watched = _entry(title: 'Old.Cut.2019.mkv');
      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: VideoPlayerLauncher.resumeIdForEntry(watched),
        videoUrl: watched.url,
        positionMs: 111000,
        durationMs: 7200000,
      );

      final other = _entry(title: 'New.Cut.2019.mkv');
      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: VideoPlayerLauncher.resumeIdForEntry(other),
        videoUrl: other.url,
        positionMs: 999000,
        durationMs: 7200000,
        imdbId: 'tt2222222',
      );

      // Source-specific (the default) prefers this entry's own record.
      final sourceSpecific = await VideoPlayerLauncher.readMovieResumeState(
        entry: watched,
        imdbId: 'tt2222222',
      );
      expect(sourceSpecific?['positionMs'], 111000);

      final explicitDefault = await VideoPlayerLauncher.readMovieResumeState(
        entry: watched,
        imdbId: 'tt2222222',
        policy: PlaybackResumePolicy.sourceSpecific,
      );
      expect(explicitDefault?['positionMs'], 111000);

      // Catalog-canonical reverses that precedence: the newest record for the
      // IMDb id wins even though this entry has one of its own.
      final canonical = await VideoPlayerLauncher.readMovieResumeState(
        entry: watched,
        imdbId: 'tt2222222',
        policy: PlaybackResumePolicy.catalogCanonical,
      );
      expect(canonical?['positionMs'], 999000);
    });

    test('a debrid file-id key survives a title change', () async {
      final first = _entry(
        title: 'Release.One.mkv',
        provider: 'torbox',
        torboxTorrentId: 7,
        torboxFileId: 9,
      );
      expect(VideoPlayerLauncher.resumeIdForEntry(first), 'torbox_7_9');

      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: 'torbox_7_9',
        videoUrl: first.url,
        positionMs: 321000,
        durationMs: 7200000,
      );

      final renamed = _entry(
        title: 'Totally.Different.Name.mkv',
        provider: 'torbox',
        torboxTorrentId: 7,
        torboxFileId: 9,
      );
      final state = await VideoPlayerLauncher.readMovieResumeState(
        entry: renamed,
        imdbId: null,
      );
      expect(state?['positionMs'], 321000);
    });
  });
}

/// Fat-port fake that also implements [CloudCachedHashes] so the dispatch's
/// `is` checks hit (the P1 [FakeCloudProvider] does not implement that type).
class _HashesCapFake extends FakeCloudProvider implements CloudCachedHashes {
  _HashesCapFake({required super.id});
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

Torrent _source() => Torrent(
  rowid: 1,
  infohash: 'b' * 40,
  name: 'Pin.Source.mkv',
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 1,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);
