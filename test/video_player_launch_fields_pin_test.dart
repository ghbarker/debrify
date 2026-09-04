import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pin of [VideoPlayerScreen] launch constructor fields *before*
/// `PlayerLaunchConfig` exists. Reads the same public fields `_VideoPlayerScreenState`
/// would via `widget.*` in init / episode-nav.
///
/// Origin: `lib/screens/video_player_screen.dart` ~219–388.
/// This file must not import `player_launch_config.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('omitted launch args keep origin defaults', () {
    const screen = VideoPlayerScreen(
      videoUrl: 'https://example/a.mkv',
      title: 'A',
    );

    expect(screen.videoUrl, 'https://example/a.mkv');
    expect(screen.title, 'A');
    expect(screen.audioUrl, isNull);
    expect(screen.subtitle, isNull);
    expect(screen.playlist, isNull);
    expect(screen.startIndex, isNull);
    expect(screen.rdTorrentId, isNull);
    expect(screen.torboxTorrentId, isNull);
    expect(screen.pikpakCollectionId, isNull);
    expect(screen.requestMagicNext, isNull);
    expect(screen.requestNextChannel, isNull);
    expect(screen.requestChannelById, isNull);
    expect(screen.channelDirectory, isNull);
    expect(screen.startFromRandom, isFalse);
    expect(screen.randomStartMaxPercent, 40);
    expect(screen.startAtPercent, isNull);
    expect(screen.hideSeekbar, isFalse);
    expect(screen.showChannelName, isFalse);
    expect(screen.channelName, isNull);
    expect(screen.channelNumber, isNull);
    expect(screen.showVideoTitle, isTrue);
    expect(screen.hideOptions, isFalse);
    expect(screen.hideBackButton, isFalse);
    expect(screen.httpHeaders, isNull);
    expect(screen.disableAutoResume, isFalse);
    expect(screen.viewMode, isNull);
    expect(screen.contentImdbId, isNull);
    expect(screen.contentType, isNull);
    expect(screen.contentSeason, isNull);
    expect(screen.contentEpisode, isNull);
    expect(screen.contentTitle, isNull);
    expect(screen.resumePolicy, PlaybackResumePolicy.sourceSpecific);
    expect(screen.iptvChannels, isNull);
    expect(screen.iptvStartIndex, isNull);
    expect(screen.iptvCategories, isNull);
    expect(screen.iptvSourceId, isNull);
    expect(screen.iptvSourceName, isNull);
    expect(screen.iptvSelectedCategory, isNull);
    expect(screen.iptvContentType, isNull);
    expect(screen.iptvSources, isNull);
    expect(screen.iptvBrowseProvider, isNull);
    expect(screen.stremioSources, isNull);
    expect(screen.stremioCurrentSourceIndex, isNull);
    expect(screen.resolveStremioSource, isNull);
    expect(screen.resolveSourceToPlaylist, isNull);
    expect(screen.startupFailoverEnabled, isFalse);
    expect(screen.startupResolverProvider, isNull);
    expect(screen.onStremioSourceCommitted, isNull);
    expect(screen.onStartupSourcesExhausted, isNull);
    expect(screen.seriesSourceFetcher, isNull);
    expect(screen.stremioTvChannels, isNull);
    expect(screen.stremioTvCurrentChannelId, isNull);
    expect(screen.stremioTvGuideDataProvider, isNull);
    expect(screen.stremioTvChannelSwitchProvider, isNull);
    expect(screen.stremioTvNextProvider, isNull);
    expect(screen.traktScrobble, isFalse);
    expect(screen.traktProgressPercent, isNull);
    expect(screen.simklScrobble, isFalse);
    expect(screen.simklProgressPercent, isNull);
    expect(screen.mdblistScrobble, isFalse);
    expect(screen.mdblistProgressPercent, isNull);
    expect(screen.initialSubtitles, isNull);
  });

  test(
    'populated launch args round-trip on the widget (State widget.* reads)',
    () {
      const key = ValueKey<String>('launch-pin');
      final playlist = [
        const PlaylistEntry(url: 'https://example/e1.mkv', title: 'E1'),
        const PlaylistEntry(url: 'https://example/e2.mkv', title: 'E2'),
      ];
      Future<Map<String, String>?> magicNext() async => {'url': 'https://n'};
      Future<Map<String, dynamic>?> nextChannel() async => {'id': 'ch2'};
      Future<Map<String, dynamic>?> channelById(String id) async => {'id': id};
      final directory = [
        <String, dynamic>{'id': 'ch1', 'name': 'One'},
      ];
      final iptv = [IptvChannel(name: 'News', url: 'https://iptv/news.m3u8')];
      Future<Map<String, dynamic>?> browse(Map<String, dynamic> q) async => q;
      final torrent = Torrent(
        rowid: 1,
        infohash: 'abc',
        name: 'Show.S01E02.mkv',
        sizeBytes: 10,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        source: 'test',
      );
      Future<String?> resolveSource(Torrent t) async => t.directUrl;
      Future<List<PlaylistEntry>?> resolvePlaylist(Torrent t) async => playlist;
      Future<void> committed(Torrent t) async {}
      Future<void> exhausted() async {}
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 2,
        searchPacks: (s, e) async => <Torrent>[],
        searchEpisodes: (s, e) async => <Torrent>[torrent],
      );
      Future<Map<String, dynamic>?> guide(List<String> ids) async => {
        'ids': ids,
      };
      Future<Map<String, dynamic>?> tvSwitch(String id) async => {'id': id};
      Future<Map<String, dynamic>?> tvNext(String id) async => {'id': id};
      final captions = [
        const StremioSubtitle(
          id: 'en',
          url: 'https://subs/en.vtt',
          lang: 'eng',
          source: 'YouTube',
        ),
      ];

      final screen = VideoPlayerScreen(
        key: key,
        videoUrl: 'https://example/video.mkv',
        audioUrl: 'https://example/audio.m4a',
        title: 'Launch Title',
        subtitle: 'Launch Subtitle',
        playlist: playlist,
        startIndex: 1,
        rdTorrentId: 'rd-1',
        torboxTorrentId: 'tb-2',
        pikpakCollectionId: 'pk-3',
        requestMagicNext: magicNext,
        requestNextChannel: nextChannel,
        requestChannelById: channelById,
        channelDirectory: directory,
        startFromRandom: true,
        randomStartMaxPercent: 25,
        startAtPercent: 0.15,
        hideSeekbar: true,
        showChannelName: true,
        channelName: 'BBC One',
        channelNumber: 101,
        showVideoTitle: false,
        hideOptions: true,
        hideBackButton: true,
        httpHeaders: const {'Authorization': 'Bearer x'},
        disableAutoResume: true,
        viewMode: PlaylistViewMode.series,
        contentImdbId: 'tt0111161',
        contentType: 'series',
        contentSeason: 1,
        contentEpisode: 2,
        contentTitle: 'The Show',
        resumePolicy: PlaybackResumePolicy.catalogCanonical,
        iptvChannels: iptv,
        iptvStartIndex: 0,
        iptvCategories: const ['News'],
        iptvSourceId: 'src-1',
        iptvSourceName: 'My IPTV',
        iptvSelectedCategory: 'News',
        iptvContentType: 'live',
        iptvSources: const [
          {'id': 'src-1'},
        ],
        iptvBrowseProvider: browse,
        stremioSources: [torrent],
        stremioCurrentSourceIndex: 0,
        resolveStremioSource: resolveSource,
        resolveSourceToPlaylist: resolvePlaylist,
        startupFailoverEnabled: true,
        startupResolverProvider: 'pikpak',
        onStremioSourceCommitted: committed,
        onStartupSourcesExhausted: exhausted,
        seriesSourceFetcher: fetcher,
        stremioTvChannels: const [
          {'id': 'stv-1'},
        ],
        stremioTvCurrentChannelId: 'stv-1',
        stremioTvGuideDataProvider: guide,
        stremioTvChannelSwitchProvider: tvSwitch,
        stremioTvNextProvider: tvNext,
        traktScrobble: true,
        traktProgressPercent: 12.5,
        simklScrobble: true,
        simklProgressPercent: 8.0,
        mdblistScrobble: true,
        mdblistProgressPercent: 3.0,
        initialSubtitles: captions,
      );

      expect(screen.key, key);
      expect(screen.videoUrl, 'https://example/video.mkv');
      expect(screen.audioUrl, 'https://example/audio.m4a');
      expect(screen.title, 'Launch Title');
      expect(screen.subtitle, 'Launch Subtitle');
      expect(identical(screen.playlist, playlist), isTrue);
      expect(screen.startIndex, 1);
      expect(screen.rdTorrentId, 'rd-1');
      expect(screen.torboxTorrentId, 'tb-2');
      expect(screen.pikpakCollectionId, 'pk-3');
      expect(identical(screen.requestMagicNext, magicNext), isTrue);
      expect(identical(screen.requestNextChannel, nextChannel), isTrue);
      expect(identical(screen.requestChannelById, channelById), isTrue);
      expect(identical(screen.channelDirectory, directory), isTrue);
      expect(screen.startFromRandom, isTrue);
      expect(screen.randomStartMaxPercent, 25);
      expect(screen.startAtPercent, 0.15);
      expect(screen.hideSeekbar, isTrue);
      expect(screen.showChannelName, isTrue);
      expect(screen.channelName, 'BBC One');
      expect(screen.channelNumber, 101);
      expect(screen.showVideoTitle, isFalse);
      expect(screen.hideOptions, isTrue);
      expect(screen.hideBackButton, isTrue);
      expect(screen.httpHeaders, {'Authorization': 'Bearer x'});
      expect(screen.disableAutoResume, isTrue);
      expect(screen.viewMode, PlaylistViewMode.series);
      expect(screen.contentImdbId, 'tt0111161');
      expect(screen.contentType, 'series');
      expect(screen.contentSeason, 1);
      expect(screen.contentEpisode, 2);
      expect(screen.contentTitle, 'The Show');
      expect(screen.resumePolicy, PlaybackResumePolicy.catalogCanonical);
      expect(identical(screen.iptvChannels, iptv), isTrue);
      expect(screen.iptvStartIndex, 0);
      expect(screen.iptvCategories, ['News']);
      expect(screen.iptvSourceId, 'src-1');
      expect(screen.iptvSourceName, 'My IPTV');
      expect(screen.iptvSelectedCategory, 'News');
      expect(screen.iptvContentType, 'live');
      expect(screen.iptvSources, [
        {'id': 'src-1'},
      ]);
      expect(identical(screen.iptvBrowseProvider, browse), isTrue);
      expect(screen.stremioSources, hasLength(1));
      expect(identical(screen.stremioSources!.single, torrent), isTrue);
      expect(screen.stremioCurrentSourceIndex, 0);
      expect(identical(screen.resolveStremioSource, resolveSource), isTrue);
      expect(
        identical(screen.resolveSourceToPlaylist, resolvePlaylist),
        isTrue,
      );
      expect(screen.startupFailoverEnabled, isTrue);
      expect(screen.startupResolverProvider, 'pikpak');
      expect(identical(screen.onStremioSourceCommitted, committed), isTrue);
      expect(identical(screen.onStartupSourcesExhausted, exhausted), isTrue);
      expect(identical(screen.seriesSourceFetcher, fetcher), isTrue);
      expect(screen.stremioTvChannels, [
        {'id': 'stv-1'},
      ]);
      expect(screen.stremioTvCurrentChannelId, 'stv-1');
      expect(identical(screen.stremioTvGuideDataProvider, guide), isTrue);
      expect(
        identical(screen.stremioTvChannelSwitchProvider, tvSwitch),
        isTrue,
      );
      expect(identical(screen.stremioTvNextProvider, tvNext), isTrue);
      expect(screen.traktScrobble, isTrue);
      expect(screen.traktProgressPercent, 12.5);
      expect(screen.simklScrobble, isTrue);
      expect(screen.simklProgressPercent, 8.0);
      expect(screen.mdblistScrobble, isTrue);
      expect(screen.mdblistProgressPercent, 3.0);
      expect(identical(screen.initialSubtitles, captions), isTrue);
    },
  );

  test('randomStartMaxPercent 0 is allowed; negative asserts', () {
    final zero = VideoPlayerScreen(
      videoUrl: 'https://example/a.mkv',
      title: 'A',
      randomStartMaxPercent: 0,
    );
    expect(zero.randomStartMaxPercent, 0);

    expect(
      () => VideoPlayerScreen(
        videoUrl: 'https://example/a.mkv',
        title: 'A',
        randomStartMaxPercent: -1,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
