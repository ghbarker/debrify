import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Origin pin for `VideoPlayerLaunchArgs` in
/// `lib/services/video_player_launcher.dart` — the single (const) generative
/// constructor and its `suppressTrackerAutoSync ?? suppressTraktAutoSync`
/// initializer, the deprecated `suppressTraktAutoSync` getter, `copyWith`
/// (which carries every field and overrides only the seven tracker knobs),
/// and `toWidget()`.
///
/// `toWidget()` is the one member of this class that reaches out of the
/// services layer: it builds a `VideoPlayerScreen`. The pin therefore asserts
/// both halves of that boundary — every field the screen does receive, and the
/// launcher-only fields it deliberately does not (the screen has no
/// `fallbackUrl`, `webDav*`, `disableExternalPlayer`, `isAndroidTvOverride`,
/// `iptvLists`, `stremioTv*Minutes` / `stremioTvMixSalt`, `posterUrl`,
/// `contentYear`, `addonId` or `suppressTrackerAutoSync` parameter, so those
/// values stop at the launcher). If `toWidget()` is separated from the data
/// class during extraction, this pin is what proves the mapping did not drift.
///
/// Nothing here imports a launcher-internal file: the class may move, so long
/// as `package:debrify/services/video_player_launcher.dart` keeps exporting it
/// and `args.toWidget()` keeps resolving.
void main() {
  const subtitle = StremioSubtitle(
    id: 'sub-1',
    url: 'https://subs.invalid/a.srt',
    lang: 'eng',
    source: 'pin-addon',
  );

  final channel = IptvChannel(
    channelNumber: 7,
    name: 'Pin Channel',
    url: 'https://iptv.invalid/7',
  );

  final source = Torrent(
    rowid: 1,
    infohash: 'a' * 40,
    name: 'Pin.Source.2020.mkv',
    sizeBytes: 123,
    createdUnix: 0,
    seeders: 1,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
  );

  const entry = PlaylistEntry(url: 'https://cdn.invalid/e.mkv', title: 'E');

  Future<Map<String, String>?> magicNext() async => null;
  Future<Map<String, dynamic>?> nextChannel() async => null;
  Future<Map<String, dynamic>?> browse(Map<String, dynamic> _) async => null;
  Future<String?> resolveStremio(Torrent _) async => null;
  Future<List<PlaylistEntry>?> resolvePlaylist(Torrent _) async => null;
  Future<void> committed(Torrent _) async {}
  Future<void> exhausted() async {}
  Future<Map<String, dynamic>?> guideData(List<String> _) async => null;
  Future<Map<String, dynamic>?> channelSwitch(String _) async => null;
  Future<Map<String, dynamic>?> tvNext(String _) async => null;
  bool tvOverride() => true;

  final fetcher = SeriesSourceFetcher(
    searchPacks: (season, episode) async => const <Torrent>[],
    searchEpisodes: (season, episode) async => const <Torrent>[],
    season: 2,
    episode: 5,
  );

  /// Every field set to a value distinguishable from its default.
  VideoPlayerLaunchArgs populated() => VideoPlayerLaunchArgs(
    videoUrl: 'https://cdn.invalid/primary.mkv',
    audioUrl: 'https://cdn.invalid/audio.m4a',
    fallbackUrl: 'https://cdn.invalid/muxed.mp4',
    title: 'Pin Title',
    subtitle: 'Pin Subtitle',
    playlist: const [entry],
    startIndex: 3,
    rdTorrentId: 'rd-1',
    torboxTorrentId: 'tb-1',
    pikpakCollectionId: 'pp-1',
    webDavServerId: 'dav-1',
    webDavBaseUrl: 'https://dav.invalid/',
    webDavPath: '/media/x.mkv',
    requestMagicNext: magicNext,
    requestNextChannel: nextChannel,
    startFromRandom: true,
    randomStartMaxPercent: 11,
    startAtPercent: 42.5,
    hideSeekbar: true,
    showChannelName: true,
    channelName: 'Chan',
    channelNumber: 9,
    showVideoTitle: false,
    hideOptions: true,
    hideBackButton: true,
    httpHeaders: const {'X-Pin': '1'},
    disableExternalPlayer: true,
    isAndroidTvOverride: tvOverride,
    disableAutoResume: true,
    viewMode: PlaylistViewMode.sorted,
    contentImdbId: 'tt7654321',
    contentType: 'series',
    contentSeason: 2,
    contentEpisode: 5,
    resumePolicy: PlaybackResumePolicy.catalogCanonical,
    iptvChannels: [channel],
    iptvStartIndex: 1,
    iptvCategories: const ['News'],
    iptvSourceId: 'src-1',
    iptvSourceName: 'Src',
    iptvSelectedCategory: 'News',
    iptvContentType: 'live',
    iptvSources: const [
      {'id': 'src-1'},
    ],
    iptvLists: const [
      {'id': 'list-1'},
    ],
    iptvBrowseProvider: browse,
    stremioSources: [source],
    stremioCurrentSourceIndex: 0,
    resolveStremioSource: resolveStremio,
    resolveSourceToPlaylist: resolvePlaylist,
    startupFailoverEnabled: true,
    startupResolverProvider: 'pikpak',
    onStremioSourceCommitted: committed,
    onStartupSourcesExhausted: exhausted,
    seriesSourceFetcher: fetcher,
    stremioTvChannels: const [
      {'id': 'tv-1'},
    ],
    stremioTvCurrentChannelId: 'tv-1',
    stremioTvRotationMinutes: 30,
    stremioTvSeriesRotationMinutes: 45,
    stremioTvMixSalt: 77,
    stremioTvGuideDataProvider: guideData,
    stremioTvChannelSwitchProvider: channelSwitch,
    stremioTvNextProvider: tvNext,
    traktScrobble: true,
    suppressTrackerAutoSync: true,
    traktProgressPercent: 12.5,
    simklScrobble: true,
    simklProgressPercent: 23.5,
    mdblistScrobble: true,
    mdblistProgressPercent: 34.5,
    contentTitle: 'Pin Content',
    posterUrl: 'https://img.invalid/p.jpg',
    contentYear: '2020',
    addonId: 'addon-1',
    initialSubtitles: const [subtitle],
  );

  group('constructor defaults and the tracker-suppression alias', () {
    test('unset optional fields keep their declared defaults', () {
      const args = VideoPlayerLaunchArgs(videoUrl: 'u', title: 't');

      expect(args.videoUrl, 'u');
      expect(args.title, 't');
      expect(args.audioUrl, isNull);
      expect(args.fallbackUrl, isNull);
      expect(args.startFromRandom, isFalse);
      expect(args.randomStartMaxPercent, 40);
      expect(args.hideSeekbar, isFalse);
      expect(args.showChannelName, isFalse);
      expect(args.showVideoTitle, isTrue);
      expect(args.hideOptions, isFalse);
      expect(args.hideBackButton, isFalse);
      expect(args.disableExternalPlayer, isFalse);
      expect(args.disableAutoResume, isFalse);
      expect(args.resumePolicy, PlaybackResumePolicy.sourceSpecific);
      expect(args.startupFailoverEnabled, isFalse);
      expect(args.traktScrobble, isFalse);
      expect(args.simklScrobble, isFalse);
      expect(args.mdblistScrobble, isFalse);
      expect(args.suppressTrackerAutoSync, isFalse);
      expect(args.suppressTraktAutoSync, isFalse);
    });

    test('the legacy alias feeds the field only when the new name is absent', () {
      const legacyOnly = VideoPlayerLaunchArgs(
        videoUrl: 'u',
        title: 't',
        suppressTraktAutoSync: true,
      );
      expect(legacyOnly.suppressTrackerAutoSync, isTrue);
      expect(legacyOnly.suppressTraktAutoSync, isTrue);

      // The new name wins outright in both directions, including an explicit
      // `false` that must not be re-raised by the legacy `true`.
      const newNameWins = VideoPlayerLaunchArgs(
        videoUrl: 'u',
        title: 't',
        suppressTrackerAutoSync: false,
        suppressTraktAutoSync: true,
      );
      expect(newNameWins.suppressTrackerAutoSync, isFalse);
      expect(newNameWins.suppressTraktAutoSync, isFalse);

      const newNameRaises = VideoPlayerLaunchArgs(
        videoUrl: 'u',
        title: 't',
        suppressTrackerAutoSync: true,
      );
      expect(newNameRaises.suppressTrackerAutoSync, isTrue);
      expect(newNameRaises.suppressTraktAutoSync, isTrue);
    });
  });

  group('copyWith', () {
    test('carries every non-tracker field through untouched', () {
      final original = populated();
      final copy = original.copyWith();

      expect(identical(copy, original), isFalse);

      expect(copy.videoUrl, original.videoUrl);
      expect(copy.audioUrl, original.audioUrl);
      expect(copy.fallbackUrl, original.fallbackUrl);
      expect(copy.title, original.title);
      expect(copy.subtitle, original.subtitle);
      expect(copy.playlist, same(original.playlist));
      expect(copy.startIndex, original.startIndex);
      expect(copy.rdTorrentId, original.rdTorrentId);
      expect(copy.torboxTorrentId, original.torboxTorrentId);
      expect(copy.pikpakCollectionId, original.pikpakCollectionId);
      expect(copy.webDavServerId, original.webDavServerId);
      expect(copy.webDavBaseUrl, original.webDavBaseUrl);
      expect(copy.webDavPath, original.webDavPath);
      expect(copy.requestMagicNext, same(original.requestMagicNext));
      expect(copy.requestNextChannel, same(original.requestNextChannel));
      expect(copy.startFromRandom, original.startFromRandom);
      expect(copy.randomStartMaxPercent, original.randomStartMaxPercent);
      expect(copy.startAtPercent, original.startAtPercent);
      expect(copy.hideSeekbar, original.hideSeekbar);
      expect(copy.showChannelName, original.showChannelName);
      expect(copy.channelName, original.channelName);
      expect(copy.channelNumber, original.channelNumber);
      expect(copy.showVideoTitle, original.showVideoTitle);
      expect(copy.hideOptions, original.hideOptions);
      expect(copy.hideBackButton, original.hideBackButton);
      expect(copy.httpHeaders, same(original.httpHeaders));
      expect(copy.disableExternalPlayer, original.disableExternalPlayer);
      expect(copy.isAndroidTvOverride, same(original.isAndroidTvOverride));
      expect(copy.disableAutoResume, original.disableAutoResume);
      expect(copy.viewMode, original.viewMode);
      expect(copy.contentImdbId, original.contentImdbId);
      expect(copy.contentType, original.contentType);
      expect(copy.contentSeason, original.contentSeason);
      expect(copy.contentEpisode, original.contentEpisode);
      expect(copy.resumePolicy, original.resumePolicy);
      expect(copy.iptvChannels, same(original.iptvChannels));
      expect(copy.iptvStartIndex, original.iptvStartIndex);
      expect(copy.iptvCategories, same(original.iptvCategories));
      expect(copy.iptvSourceId, original.iptvSourceId);
      expect(copy.iptvSourceName, original.iptvSourceName);
      expect(copy.iptvSelectedCategory, original.iptvSelectedCategory);
      expect(copy.iptvContentType, original.iptvContentType);
      expect(copy.iptvSources, same(original.iptvSources));
      expect(copy.iptvLists, same(original.iptvLists));
      expect(copy.iptvBrowseProvider, same(original.iptvBrowseProvider));
      expect(copy.stremioSources, same(original.stremioSources));
      expect(
        copy.stremioCurrentSourceIndex,
        original.stremioCurrentSourceIndex,
      );
      expect(copy.resolveStremioSource, same(original.resolveStremioSource));
      expect(
        copy.resolveSourceToPlaylist,
        same(original.resolveSourceToPlaylist),
      );
      expect(copy.startupFailoverEnabled, original.startupFailoverEnabled);
      expect(copy.startupResolverProvider, original.startupResolverProvider);
      expect(
        copy.onStremioSourceCommitted,
        same(original.onStremioSourceCommitted),
      );
      expect(
        copy.onStartupSourcesExhausted,
        same(original.onStartupSourcesExhausted),
      );
      expect(copy.seriesSourceFetcher, same(original.seriesSourceFetcher));
      expect(copy.stremioTvChannels, same(original.stremioTvChannels));
      expect(
        copy.stremioTvCurrentChannelId,
        original.stremioTvCurrentChannelId,
      );
      expect(copy.stremioTvRotationMinutes, original.stremioTvRotationMinutes);
      expect(
        copy.stremioTvSeriesRotationMinutes,
        original.stremioTvSeriesRotationMinutes,
      );
      expect(copy.stremioTvMixSalt, original.stremioTvMixSalt);
      expect(
        copy.stremioTvGuideDataProvider,
        same(original.stremioTvGuideDataProvider),
      );
      expect(
        copy.stremioTvChannelSwitchProvider,
        same(original.stremioTvChannelSwitchProvider),
      );
      expect(copy.stremioTvNextProvider, same(original.stremioTvNextProvider));
      expect(copy.contentTitle, original.contentTitle);
      expect(copy.posterUrl, original.posterUrl);
      expect(copy.contentYear, original.contentYear);
      expect(copy.addonId, original.addonId);
      expect(copy.initialSubtitles, same(original.initialSubtitles));
    });

    test('the seven overridable knobs replace, and only when non-null', () {
      final original = populated();

      final same0 = original.copyWith();
      expect(same0.traktScrobble, isTrue);
      expect(same0.traktProgressPercent, 12.5);
      expect(same0.simklScrobble, isTrue);
      expect(same0.simklProgressPercent, 23.5);
      expect(same0.mdblistScrobble, isTrue);
      expect(same0.mdblistProgressPercent, 34.5);
      expect(same0.suppressTrackerAutoSync, isTrue);

      final flipped = original.copyWith(
        traktScrobble: false,
        traktProgressPercent: 1,
        simklScrobble: false,
        simklProgressPercent: 2,
        mdblistScrobble: false,
        mdblistProgressPercent: 3,
        suppressTrackerAutoSync: false,
      );
      expect(flipped.traktScrobble, isFalse);
      expect(flipped.traktProgressPercent, 1);
      expect(flipped.simklScrobble, isFalse);
      expect(flipped.simklProgressPercent, 2);
      expect(flipped.mdblistScrobble, isFalse);
      expect(flipped.mdblistProgressPercent, 3);
      expect(flipped.suppressTrackerAutoSync, isFalse);
      // The legacy getter tracks the field it aliases, not the ctor argument.
      expect(flipped.suppressTraktAutoSync, isFalse);

      // `?? this.x` means an explicit null cannot clear a set percentage.
      final cleared = original.copyWith(
        traktProgressPercent: null,
        simklProgressPercent: null,
        mdblistProgressPercent: null,
      );
      expect(cleared.traktProgressPercent, 12.5);
      expect(cleared.simklProgressPercent, 23.5);
      expect(cleared.mdblistProgressPercent, 34.5);
    });

    test('a copy of a default-constructed args stays at the defaults', () {
      const original = VideoPlayerLaunchArgs(videoUrl: 'u', title: 't');
      final copy = original.copyWith(mdblistScrobble: true);

      expect(copy.mdblistScrobble, isTrue);
      expect(copy.randomStartMaxPercent, 40);
      expect(copy.showVideoTitle, isTrue);
      expect(copy.resumePolicy, PlaybackResumePolicy.sourceSpecific);
      expect(copy.suppressTrackerAutoSync, isFalse);
      expect(copy.playlist, isNull);
    });
  });

  group('toWidget()', () {
    test('builds a VideoPlayerScreen with no widget builder installed', () {
      expect(
        VideoPlayerLauncher.debugPlayerWidgetBuilder,
        isNull,
        reason: 'the launcher ships with no player-widget substitution',
      );

      final widget = populated().toWidget();
      expect(widget, isA<VideoPlayerScreen>());
    });

    test('carries every parameter the player screen accepts', () {
      final args = populated();
      final widget = args.toWidget();

      expect(widget.videoUrl, args.videoUrl);
      expect(widget.audioUrl, args.audioUrl);
      expect(widget.title, args.title);
      expect(widget.subtitle, args.subtitle);
      expect(widget.playlist, same(args.playlist));
      expect(widget.startIndex, args.startIndex);
      expect(widget.rdTorrentId, args.rdTorrentId);
      expect(widget.torboxTorrentId, args.torboxTorrentId);
      expect(widget.pikpakCollectionId, args.pikpakCollectionId);
      expect(widget.requestMagicNext, same(args.requestMagicNext));
      expect(widget.requestNextChannel, same(args.requestNextChannel));
      expect(widget.startFromRandom, args.startFromRandom);
      expect(widget.randomStartMaxPercent, args.randomStartMaxPercent);
      expect(widget.startAtPercent, args.startAtPercent);
      expect(widget.hideSeekbar, args.hideSeekbar);
      expect(widget.showChannelName, args.showChannelName);
      expect(widget.channelName, args.channelName);
      expect(widget.channelNumber, args.channelNumber);
      expect(widget.showVideoTitle, args.showVideoTitle);
      expect(widget.hideOptions, args.hideOptions);
      expect(widget.hideBackButton, args.hideBackButton);
      expect(widget.httpHeaders, same(args.httpHeaders));
      expect(widget.disableAutoResume, args.disableAutoResume);
      expect(widget.viewMode, args.viewMode);
      expect(widget.contentImdbId, args.contentImdbId);
      expect(widget.contentType, args.contentType);
      expect(widget.contentSeason, args.contentSeason);
      expect(widget.contentEpisode, args.contentEpisode);
      expect(widget.resumePolicy, args.resumePolicy);
      expect(widget.contentTitle, args.contentTitle);
      expect(widget.iptvChannels, same(args.iptvChannels));
      expect(widget.iptvStartIndex, args.iptvStartIndex);
      expect(widget.iptvCategories, same(args.iptvCategories));
      expect(widget.iptvSourceId, args.iptvSourceId);
      expect(widget.iptvSourceName, args.iptvSourceName);
      expect(widget.iptvSelectedCategory, args.iptvSelectedCategory);
      expect(widget.iptvContentType, args.iptvContentType);
      expect(widget.iptvSources, same(args.iptvSources));
      expect(widget.iptvBrowseProvider, same(args.iptvBrowseProvider));
      expect(widget.stremioSources, same(args.stremioSources));
      expect(
        widget.stremioCurrentSourceIndex,
        args.stremioCurrentSourceIndex,
      );
      expect(widget.resolveStremioSource, same(args.resolveStremioSource));
      expect(
        widget.resolveSourceToPlaylist,
        same(args.resolveSourceToPlaylist),
      );
      expect(widget.startupFailoverEnabled, args.startupFailoverEnabled);
      expect(widget.startupResolverProvider, args.startupResolverProvider);
      expect(
        widget.onStremioSourceCommitted,
        same(args.onStremioSourceCommitted),
      );
      expect(
        widget.onStartupSourcesExhausted,
        same(args.onStartupSourcesExhausted),
      );
      expect(widget.seriesSourceFetcher, same(args.seriesSourceFetcher));
      expect(widget.stremioTvChannels, same(args.stremioTvChannels));
      expect(
        widget.stremioTvCurrentChannelId,
        args.stremioTvCurrentChannelId,
      );
      expect(
        widget.stremioTvGuideDataProvider,
        same(args.stremioTvGuideDataProvider),
      );
      expect(
        widget.stremioTvChannelSwitchProvider,
        same(args.stremioTvChannelSwitchProvider),
      );
      expect(
        widget.stremioTvNextProvider,
        same(args.stremioTvNextProvider),
      );
      expect(widget.traktScrobble, args.traktScrobble);
      expect(widget.traktProgressPercent, args.traktProgressPercent);
      expect(widget.simklScrobble, args.simklScrobble);
      expect(widget.simklProgressPercent, args.simklProgressPercent);
      expect(widget.mdblistScrobble, args.mdblistScrobble);
      expect(widget.mdblistProgressPercent, args.mdblistProgressPercent);
      expect(widget.initialSubtitles, same(args.initialSubtitles));

      // Not forwarded, because the screen has no such parameter — these are
      // launcher-scoped and stop at `toWidget()`.
      expect(widget.channelDirectory, isNull);
      expect(widget.requestChannelById, isNull);
    });

    test('does not blank the primary URL when a muxed fallback exists', () {
      // `fallbackUrl` is external-player-only (see externalPlaybackUrlFor);
      // the in-app screen always receives the primary stream plus its audio.
      const args = VideoPlayerLaunchArgs(
        videoUrl: 'https://cdn.invalid/video-only.mp4',
        audioUrl: 'https://cdn.invalid/audio.m4a',
        fallbackUrl: 'https://cdn.invalid/muxed.mp4',
        title: 't',
      );

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(args),
        'https://cdn.invalid/muxed.mp4',
      );
      expect(args.toWidget().videoUrl, 'https://cdn.invalid/video-only.mp4');
      expect(args.toWidget().audioUrl, 'https://cdn.invalid/audio.m4a');
    });

    test('a copyWith round trip reaches the screen with the new flags', () {
      final widget = populated()
          .copyWith(mdblistScrobble: false, traktProgressPercent: 99)
          .toWidget();

      expect(widget.mdblistScrobble, isFalse);
      expect(widget.traktProgressPercent, 99);
      expect(widget.simklScrobble, isTrue);
      expect(widget.resumePolicy, PlaybackResumePolicy.catalogCanonical);
      expect(widget.startupFailoverEnabled, isTrue);
    });
  });
}
