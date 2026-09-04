import '../../models/iptv_playlist.dart';
import '../../models/playlist_view_mode.dart';
import '../../models/stremio_subtitle.dart';
import '../../models/torrent.dart';
import '../../services/local_playback_resume_resolver.dart';
import '../../services/series_source_fetcher.dart';
import '../video_player_screen.dart';

/// Launch-time arguments for [VideoPlayerScreen].
///
/// Field list, comments, defaults and the `randomStartMaxPercent >= 0` assert
/// are copied from the screen constructor (origin ~219–388). The public
/// [VideoPlayerScreen] constructor stays on the widget; State reads this
/// object in init / episode-nav instead of `widget.*`.
class PlayerLaunchConfig {
  final String videoUrl;

  /// Optional separate audio track played alongside [videoUrl] via mpv's
  /// external-audio support (high-res YouTube serves video/audio separately).
  final String? audioUrl;
  final String title;
  final String? subtitle;
  final List<PlaylistEntry>? playlist;
  final int? startIndex;
  final String? rdTorrentId; // For updating playlist poster (RealDebrid)
  final String? torboxTorrentId; // For updating playlist poster (Torbox)
  final String? pikpakCollectionId; // For updating playlist poster (PikPak)
  // Optional: Debrify TV provider to fetch the next playable item (url & title)
  final Future<Map<String, String>?> Function()? requestMagicNext;
  // Optional: Debrify TV channel switcher (firstUrl, firstTitle, channel metadata)
  final Future<Map<String, dynamic>?> Function()? requestNextChannel;
  // Optional: Switch to a specific channel by ID
  final Future<Map<String, dynamic>?> Function(String channelId)?
  requestChannelById;
  // Optional: Channel directory for channel guide
  final List<Map<String, dynamic>>? channelDirectory;
  // Advanced: start each video at a random timestamp
  final bool startFromRandom;
  final int randomStartMaxPercent;
  // Start video at a specific percentage (0.0 to 1.0)
  final double? startAtPercent;
  // Advanced: hide seekbar (double-tap seek still enabled)
  final bool hideSeekbar;
  // Channel name badge overlay
  final bool showChannelName;
  final String? channelName;
  final int? channelNumber;
  // Show video title in player controls
  final bool showVideoTitle;
  // Hide all bottom options (next, audio, etc.) - back button stays
  final bool hideOptions;
  // Hide back button - use device back gesture or escape key
  final bool hideBackButton;
  // HTTP headers for authenticated streaming (e.g., PikPak, private CDNs)
  final Map<String, String>? httpHeaders;
  // Disable auto-resume - start from the specified startIndex instead of last played
  final bool disableAutoResume;
  // Explicit view mode - if null, auto-detect from filenames
  final PlaylistViewMode? viewMode;
  // Content metadata for fetching external subtitles from Stremio addons
  final String? contentImdbId;
  final String? contentType; // 'movie' or 'series'
  final int? contentSeason;
  final int? contentEpisode;
  final String? contentTitle; // Clean display name (IMDB title)
  final PlaybackResumePolicy resumePolicy;
  // IPTV channel list for in-player channel switching
  final List<IptvChannel>? iptvChannels;
  final int? iptvStartIndex;
  final List<String>? iptvCategories;
  final String? iptvSourceId;
  final String? iptvSourceName;
  final String? iptvSelectedCategory;
  final String? iptvContentType;
  final List<Map<String, dynamic>>? iptvSources;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  iptvBrowseProvider;
  // Stremio sources for in-player source switching
  final List<Torrent>? stremioSources;
  final int? stremioCurrentSourceIndex;
  final Future<String?> Function(Torrent)? resolveStremioSource;
  // Torrent search source switching: resolves a Torrent to a full playlist
  final Future<List<PlaylistEntry>?> Function(Torrent)? resolveSourceToPlaylist;
  final bool startupFailoverEnabled;
  final String? startupResolverProvider;
  final Future<void> Function(Torrent)? onStremioSourceCommitted;
  final Future<void> Function()? onStartupSourcesExhausted;
  // "Load more sources" backend for the source sheet (series pack/episode
  // searches, or the movie search for bound movie plays)
  final SeriesSourceFetcher? seriesSourceFetcher;
  // Stremio TV channel guide data
  final List<Map<String, dynamic>>? stremioTvChannels;
  final String? stremioTvCurrentChannelId;
  final Future<Map<String, dynamic>?> Function(List<String>)?
  stremioTvGuideDataProvider;
  final Future<Map<String, dynamic>?> Function(String)?
  stremioTvChannelSwitchProvider;
  final Future<Map<String, dynamic>?> Function(String)? stremioTvNextProvider;
  // Trakt scrobble: send playback progress to Trakt when playing from Trakt screen
  final bool traktScrobble;
  // Trakt progress: resume fallback when no local resume exists (0-100)
  final double? traktProgressPercent;
  // Simkl scrobble/progress — fully parallel to the Trakt pair above (both
  // trackers can run simultaneously; see the Simkl integration plan).
  final bool simklScrobble;
  final double? simklProgressPercent;
  final bool mdblistScrobble;
  final double? mdblistProgressPercent;

  /// Subtitle tracks known at launch (e.g. YouTube closed captions), surfaced
  /// in the subtitle menu as a pre-loaded provider group. Null for sources
  /// whose subtitles are fetched lazily from Stremio addons by IMDb id.
  final List<StremioSubtitle>? initialSubtitles;

  const PlayerLaunchConfig({
    required this.videoUrl,
    this.audioUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    this.rdTorrentId,
    this.torboxTorrentId,
    this.pikpakCollectionId,
    this.requestMagicNext,
    this.requestNextChannel,
    this.requestChannelById,
    this.channelDirectory,
    this.startFromRandom = false,
    this.randomStartMaxPercent = 40,
    this.startAtPercent,
    this.hideSeekbar = false,
    this.showChannelName = false,
    this.channelName,
    this.channelNumber,
    this.showVideoTitle = true,
    this.hideOptions = false,
    this.hideBackButton = false,
    this.httpHeaders,
    this.disableAutoResume = false,
    this.viewMode,
    this.contentImdbId,
    this.contentType,
    this.contentSeason,
    this.contentEpisode,
    this.contentTitle,
    this.resumePolicy = PlaybackResumePolicy.sourceSpecific,
    this.iptvChannels,
    this.iptvStartIndex,
    this.iptvCategories,
    this.iptvSourceId,
    this.iptvSourceName,
    this.iptvSelectedCategory,
    this.iptvContentType,
    this.iptvSources,
    this.iptvBrowseProvider,
    this.stremioSources,
    this.stremioCurrentSourceIndex,
    this.resolveStremioSource,
    this.resolveSourceToPlaylist,
    this.startupFailoverEnabled = false,
    this.startupResolverProvider,
    this.onStremioSourceCommitted,
    this.onStartupSourcesExhausted,
    this.seriesSourceFetcher,
    this.stremioTvChannels,
    this.stremioTvCurrentChannelId,
    this.stremioTvGuideDataProvider,
    this.stremioTvChannelSwitchProvider,
    this.stremioTvNextProvider,
    this.traktScrobble = false,
    this.traktProgressPercent,
    this.simklScrobble = false,
    this.simklProgressPercent,
    this.mdblistScrobble = false,
    this.mdblistProgressPercent,
    this.initialSubtitles,
  }) : assert(randomStartMaxPercent >= 0);

  factory PlayerLaunchConfig.fromWidget(VideoPlayerScreen widget) {
    return PlayerLaunchConfig(
      videoUrl: widget.videoUrl,
      audioUrl: widget.audioUrl,
      title: widget.title,
      subtitle: widget.subtitle,
      playlist: widget.playlist,
      startIndex: widget.startIndex,
      rdTorrentId: widget.rdTorrentId,
      torboxTorrentId: widget.torboxTorrentId,
      pikpakCollectionId: widget.pikpakCollectionId,
      requestMagicNext: widget.requestMagicNext,
      requestNextChannel: widget.requestNextChannel,
      requestChannelById: widget.requestChannelById,
      channelDirectory: widget.channelDirectory,
      startFromRandom: widget.startFromRandom,
      randomStartMaxPercent: widget.randomStartMaxPercent,
      startAtPercent: widget.startAtPercent,
      hideSeekbar: widget.hideSeekbar,
      showChannelName: widget.showChannelName,
      channelName: widget.channelName,
      channelNumber: widget.channelNumber,
      showVideoTitle: widget.showVideoTitle,
      hideOptions: widget.hideOptions,
      hideBackButton: widget.hideBackButton,
      httpHeaders: widget.httpHeaders,
      disableAutoResume: widget.disableAutoResume,
      viewMode: widget.viewMode,
      contentImdbId: widget.contentImdbId,
      contentType: widget.contentType,
      contentSeason: widget.contentSeason,
      contentEpisode: widget.contentEpisode,
      contentTitle: widget.contentTitle,
      resumePolicy: widget.resumePolicy,
      iptvChannels: widget.iptvChannels,
      iptvStartIndex: widget.iptvStartIndex,
      iptvCategories: widget.iptvCategories,
      iptvSourceId: widget.iptvSourceId,
      iptvSourceName: widget.iptvSourceName,
      iptvSelectedCategory: widget.iptvSelectedCategory,
      iptvContentType: widget.iptvContentType,
      iptvSources: widget.iptvSources,
      iptvBrowseProvider: widget.iptvBrowseProvider,
      stremioSources: widget.stremioSources,
      stremioCurrentSourceIndex: widget.stremioCurrentSourceIndex,
      resolveStremioSource: widget.resolveStremioSource,
      resolveSourceToPlaylist: widget.resolveSourceToPlaylist,
      startupFailoverEnabled: widget.startupFailoverEnabled,
      startupResolverProvider: widget.startupResolverProvider,
      onStremioSourceCommitted: widget.onStremioSourceCommitted,
      onStartupSourcesExhausted: widget.onStartupSourcesExhausted,
      seriesSourceFetcher: widget.seriesSourceFetcher,
      stremioTvChannels: widget.stremioTvChannels,
      stremioTvCurrentChannelId: widget.stremioTvCurrentChannelId,
      stremioTvGuideDataProvider: widget.stremioTvGuideDataProvider,
      stremioTvChannelSwitchProvider: widget.stremioTvChannelSwitchProvider,
      stremioTvNextProvider: widget.stremioTvNextProvider,
      traktScrobble: widget.traktScrobble,
      traktProgressPercent: widget.traktProgressPercent,
      simklScrobble: widget.simklScrobble,
      simklProgressPercent: widget.simklProgressPercent,
      mdblistScrobble: widget.mdblistScrobble,
      mdblistProgressPercent: widget.mdblistProgressPercent,
      initialSubtitles: widget.initialSubtitles,
    );
  }
}
