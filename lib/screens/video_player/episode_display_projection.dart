import 'episode_display_inputs.dart';

/// The player's episode display projection: the dock title (with its
/// "fetched, human name" flag), the subtitle line and the OTT metadata map,
/// computed from one [EpisodeDisplayInputs] snapshot. Bodies moved verbatim
/// from `_VideoPlayerScreenState` (`_getCurrentEpisodeTitleInfo`,
/// `_getCurrentEpisodeSubtitle`, `_getEnhancedMetadata`); the host builds the
/// snapshot at each call, which is where the origin evaluated its lazy,
/// cache-writing `_seriesPlaylist` getter first.
abstract final class EpisodeDisplayProjection {
  /// The dock title plus whether it's a fetched, human name (TVMaze episode
  /// title, catalog content title, channel name) as opposed to a release
  /// filename. TvControls skips its release-noise cleaner for fetched names —
  /// the token list would truncate a real title containing e.g. "Proper".
  static ({String title, bool fetched}) titleInfo(EpisodeDisplayInputs inputs) {
    final seriesPlaylist = inputs.seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        inputs.activePlaylist != null) {
      // Find the current episode info
      if (inputs.currentIndex >= 0 &&
          inputs.currentIndex < inputs.activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == inputs.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return episode title if available, otherwise use the playlist entry title
          if (currentEpisode.episodeInfo?.title != null &&
              currentEpisode.episodeInfo!.title!.isNotEmpty) {
            final episodeTitle = currentEpisode.episodeInfo!.title!;
            // "Show — Episode" when TVMaze supplied the official show name;
            // the subtitle then drops the name to avoid saying it twice.
            final show = seriesPlaylist.tvmazeShowName;
            return (
              title: show == null || show.isEmpty
                  ? episodeTitle
                  : '$show — $episodeTitle',
              fetched: true,
            );
          } else if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog singleton without TVMaze data yet: the clean catalog
            // title beats a bare "Episode N".
            final contentTitle = inputs.effectiveContentTitle;
            if (inputs.activePlaylist!.length == 1 &&
                contentTitle != null &&
                contentTitle.isNotEmpty &&
                inputs.effectiveStremioTvChannels == null) {
              return (title: contentTitle, fetched: true);
            }
            final episodeTitle = 'Episode ${currentEpisode.seriesInfo.episode}';
            final show = seriesPlaylist.tvmazeShowName;
            return (
              title: show == null || show.isEmpty
                  ? episodeTitle
                  : '$show — $episodeTitle',
              fetched: true,
            );
          }
        } catch (e) {
          // Silently fail
        }
      }
    }

    // Stremio TV: use dynamic title when a channel switch has occurred
    if (inputs.hasStremioTvGuide && inputs.dynamicTitle.isNotEmpty) {
      return (title: inputs.dynamicTitle, fetched: true);
    }

    // Catalog single stream (Quick Play / Sources tap): prefer the clean
    // content title over the release filename. Packs are handled by the
    // series branch above; Debrify TV, IPTV and Stremio TV keep their
    // dynamic titles.
    final contentTitle = inputs.effectiveContentTitle;
    if (contentTitle != null &&
        contentTitle.isNotEmpty &&
        !inputs.hasMagicNext &&
        inputs.effectiveIptvChannels == null &&
        inputs.effectiveStremioTvChannels == null &&
        (inputs.activePlaylist == null || inputs.activePlaylist!.length <= 1)) {
      return (title: contentTitle, fetched: true);
    }

    // Fallback to the current playlist entry title
    if (inputs.activePlaylist != null &&
        inputs.currentIndex >= 0 &&
        inputs.currentIndex < inputs.activePlaylist!.length) {
      return (
        title: inputs.activePlaylist![inputs.currentIndex].title,
        fetched: false,
      );
    }

    // If Debrify TV (no playlist) is active, use dynamic title when available
    // (a Debrify TV title can be a torrent name — keep the cleaner on it).
    if ((inputs.activePlaylist == null || inputs.activePlaylist!.isEmpty) &&
        inputs.hasMagicNext) {
      return inputs.dynamicTitle.isNotEmpty
          ? (title: inputs.dynamicTitle, fetched: false)
          : (title: inputs.title, fetched: false);
    }

    // IPTV: use current channel name
    final iptvChannels = inputs.effectiveIptvChannels;
    if (iptvChannels != null &&
        inputs.currentIptvIndex >= 0 &&
        inputs.currentIptvIndex < iptvChannels.length) {
      return (
        title: iptvChannels[inputs.currentIptvIndex].numberedName,
        fetched: true,
      );
    }

    // Final fallback
    return (title: inputs.title, fetched: false);
  }

  /// Get the current episode subtitle for display
  static String? subtitle(EpisodeDisplayInputs inputs) {
    final seriesPlaylist = inputs.seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        inputs.activePlaylist != null) {
      // Find the current episode info
      if (inputs.currentIndex >= 0 &&
          inputs.currentIndex < inputs.activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == inputs.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return series name and season/episode info as subtitle
          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog singleton: the filename-parsed series name can be a
            // mangled release string; the clean catalog title is authoritative.
            // While TVMaze hasn't supplied an episode title yet, the title line
            // is already showing the catalog name — don't repeat it here.
            final contentTitle = inputs.effectiveContentTitle;
            final isCatalogSingleton =
                inputs.activePlaylist!.length == 1 &&
                contentTitle != null &&
                contentTitle.isNotEmpty &&
                inputs.effectiveStremioTvChannels == null;
            final seasonEpisode =
                'Season ${currentEpisode.seriesInfo.season}, Episode ${currentEpisode.seriesInfo.episode}';
            // When TVMaze supplied the show name, the TITLE line already
            // reads "Show — Episode", so repeating the name here would say
            // it twice. Without it, fall back to the filename-parsed series
            // name — release strings only as a last resort, same rule as the
            // native player's OTT identity row.
            final showName = seriesPlaylist.tvmazeShowName;
            if (showName != null && showName.isNotEmpty) {
              return seasonEpisode;
            }
            if (isCatalogSingleton) {
              final hasEpisodeTitle =
                  currentEpisode.episodeInfo?.title?.isNotEmpty == true;
              return hasEpisodeTitle
                  ? '$contentTitle • $seasonEpisode'
                  : seasonEpisode;
            }
            return '${seriesPlaylist.seriesTitle} • $seasonEpisode';
          }
        } catch (e) {}
      }
    }

    // IPTV: use current channel group as subtitle
    final iptvChannels = inputs.effectiveIptvChannels;
    if (iptvChannels != null &&
        inputs.currentIptvIndex >= 0 &&
        inputs.currentIptvIndex < iptvChannels.length) {
      return iptvChannels[inputs.currentIptvIndex].group ?? 'IPTV';
    }

    // Catalog single stream: when the title shows the clean content name,
    // surface the episode identity (and the release detail line) here.
    final contentTitle = inputs.effectiveContentTitle;
    if (contentTitle != null &&
        contentTitle.isNotEmpty &&
        !inputs.hasMagicNext &&
        inputs.effectiveStremioTvChannels == null &&
        (inputs.activePlaylist == null || inputs.activePlaylist!.length <= 1)) {
      final season = inputs.effectiveContentSeason;
      final episode = inputs.effectiveContentEpisode;
      final parts = <String>[
        if (season != null && episode != null)
          'Season $season, Episode $episode',
        if (inputs.subtitle != null && inputs.subtitle!.trim().isNotEmpty)
          inputs.subtitle!,
      ];
      if (parts.isNotEmpty) return parts.join(' • ');
    }

    // Fallback to the current subtitle or widget subtitle
    return inputs.subtitle;
  }

  /// Get enhanced metadata for OTT-style display
  static Map<String, dynamic> enhancedMetadata(EpisodeDisplayInputs inputs) {
    final seriesPlaylist = inputs.seriesPlaylist;

    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        inputs.activePlaylist != null) {
      // Find the current episode info
      if (inputs.currentIndex >= 0 &&
          inputs.currentIndex < inputs.activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == inputs.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.episodeInfo != null) {
            final episodeInfo = currentEpisode.episodeInfo!;

            final metadata = {
              'rating': episodeInfo.rating,
              'runtime': episodeInfo.runtime,
              'year': episodeInfo.year,
              'airDate': episodeInfo.airDate,
              'language': episodeInfo.language,
              'genres': episodeInfo.genres,
              'network': episodeInfo.network,
              'country': episodeInfo.country,
              'plot': episodeInfo.plot,
            };

            return metadata;
          }
        } catch (e) {}
      }
    }

    return {};
  }
}
