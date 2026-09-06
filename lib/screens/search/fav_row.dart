import 'package:flutter/material.dart';
import '../../models/iptv_playlist.dart';
import 'fav_row_ref.dart';
import 'favourite_art_cell.dart';
import 'fav_rows_controller.dart';

/// Classic favourites row; cross-row navigation and hero updates stay host-owned.
class FavRow extends StatelessWidget {
  const FavRow({
    super.key,
    required this.controller,
    required this.hostContext,
    required this.ref,
    required this.homeRowId,
    required this.isTelevision,
    required this.hideTitles,
    required this.posterW,
    required this.captionBand,
    required this.onUp,
    required this.onDown,
    required this.clearHero,
    required this.setLiveHero,
    required this.tag,
  });
  final FavRowsController controller;
  // Preserve the original host Theme/MediaQuery lookup boundary.
  final BuildContext hostContext;
  final FavRowRef ref;
  final String homeRowId;
  final bool isTelevision;
  final bool hideTitles;
  final double posterW;
  final double captionBand;
  final VoidCallback Function(String, int) onUp;
  final VoidCallback Function(String, int) onDown;
  final VoidCallback clearHero;
  final void Function(IptvChannel) setLiveHero;
  final Widget Function(String, {IconData? icon}) tag;
  @override
  Widget build(BuildContext context) =>
      _buildFavRow(hostContext, ref, homeRowId);

  Widget _buildFavRow(BuildContext context, FavRowRef ref, String homeRowId) {
    if (ref.isIptvList) {
      return _buildIptvListRow(context, ref, homeRowId);
    }
    switch (ref.kind) {
      case FavKind.watchlistMovies:
      case FavKind.watchlistSeries:
        return _buildWatchlistRow(context, ref, homeRowId);
      case FavKind.iptv:
        return _buildIptvFavRow(context, homeRowId);
      case FavKind.debrify:
        return _buildTvFavRow(context, homeRowId);
      case FavKind.stremio:
        return _buildStremioTvFavRow(context, homeRowId);
      case FavKind.playlist:
        return _buildPlaylistFavRow(context, homeRowId);
    }
  }

  Widget _buildWatchlistRow(
    BuildContext context,
    FavRowRef ref,
    String homeRowId,
  ) {
    final tv = isTelevision;
    final isMovies = ref.kind == FavKind.watchlistMovies;
    final items = isMovies
        ? controller.watchlistMovieItems
        : controller.watchlistSeriesItems;
    final nodes = isMovies
        ? controller.watchlistMovieNodes
        : controller.watchlistSeriesNodes;
    return _buildFavRowShell(
      context,
      title: isMovies ? 'Watchlist Movies' : 'Watchlist Series',
      tags: [tag(isMovies ? 'Movies' : 'Series', icon: Icons.bookmark_rounded)],
      itemCount: items.length,
      cellBuilder: (col, posterW, cellH) {
        final item = items[col];
        return FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: nodes,
          onUp: onUp(homeRowId, col),
          onDown: onDown(homeRowId, col),
          child: ArtPoster(
            imageUrl: item.poster,
            title: item.name,
            showTitle: !hideTitles,
            isTelevision: tv,
            focusNode: nodes[col],
            onOpen: () => controller.openMyWatchlistItem(item),
            onFocused: clearHero,
          ),
        );
      },
    );
  }

  /// Shared scaffold for a favourites row: a header (title + tag pills) above a
  /// horizontal strip of poster-shaped cards, sized exactly like the catalog
  /// rows so the whole board reads as one grid. [cellBuilder] gets the poster
  /// width and full cell height (poster + title band) for each column.
  Widget _buildFavRowShell(
    BuildContext context, {
    required String title,
    required List<Widget> tags,
    required int itemCount,
    required Widget Function(int col, double posterW, double cellH) cellBuilder,
  }) {
    final tv = isTelevision;
    final posterW = this.posterW;
    final posterH = posterW * 3 / 2;
    // Reserve the inline caption band so a long title — e.g. a full release-name
    // playlist item — doesn't overflow the cell into the next section's header.
    final cellH = posterH + captionBand;
    final rowH = cellH + 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tv ? 20 : 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              for (final t in tags) ...[const SizedBox(width: 6), t],
            ],
          ),
        ),
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 400,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: itemCount,
            itemBuilder: (context, col) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: SizedBox(
                    width: posterW,
                    height: cellH,
                    child: cellBuilder(col, posterW, cellH),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The "Debrify TV" row of favourited keyword channels, styled to match the
  /// catalog rows (same poster-shaped cards + title below).
  Widget _buildTvFavRow(BuildContext context, String homeRowId) {
    final tv = isTelevision;
    return _buildFavRowShell(
      context,
      title: 'Debrify TV',
      tags: [
        tag('Channels'),
        // Make it explicit this row is the user's STARRED channels, not every
        // channel — otherwise people expect all channels here.
        tag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: controller.tvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = controller.tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: controller.tvFavNodes,
          onUp: onUp(homeRowId, col),
          onDown: onDown(homeRowId, col),
          // Debrify channels have no artwork — the glyph fallback + channel
          // number badge is the intended look.
          child: ArtPoster(
            imageUrl: null,
            title: channel.name,
            showTitle: !hideTitles,
            badge: '$number',
            isTelevision: tv,
            focusNode: controller.tvFavNodes[col],
            onOpen: () => controller.playChannel(channel),
            onFocused: clearHero,
          ),
        );
      },
    );
  }

  /// The "Stremio TV" row of favourited channels. Each card shows the channel's
  /// current now-playing item poster (rotating on the same schedule as the Home
  /// / Stremio TV screens); tapping opens the channel.
  Widget _buildStremioTvFavRow(BuildContext context, String homeRowId) {
    final tv = isTelevision;
    return _buildFavRowShell(
      context,
      title: 'Stremio TV',
      tags: [
        tag('Channels'),
        tag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: controller.stvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = controller.stvFavChannels[col];
        final item = controller.stvNowPlaying(channel)?.item;
        // Prefer the 2:3 poster for this poster-shaped tile; fall back to the
        // (landscape) background so channels whose now-playing meta lacks a
        // poster still show art instead of a blank glyph.
        final art = controller.firstNonEmpty(item?.poster, item?.background);
        return FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: controller.stvFavNodes,
          onUp: onUp(homeRowId, col),
          onDown: onDown(homeRowId, col),
          child: ArtPoster(
            imageUrl: art,
            title: channel.displayName,
            showTitle: !hideTitles,
            live: true,
            isTelevision: tv,
            focusNode: controller.stvFavNodes[col],
            onOpen: () => controller.playStremioTvChannel(channel),
            onFocused: clearHero,
          ),
        );
      },
    );
  }

  /// The "IPTV" row of favourited live channels. Cards show the channel logo
  /// (glyph fallback); tapping plays the stream directly.
  Widget _buildIptvFavRow(BuildContext context, String homeRowId) {
    final tv = isTelevision;
    return _buildFavRowShell(
      context,
      title: 'IPTV',
      tags: [
        tag('Live'),
        tag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: controller.iptvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = controller.iptvFavChannels[col];
        return FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: controller.iptvFavNodes,
          onUp: onUp(homeRowId, col),
          onDown: onDown(homeRowId, col),
          child: ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !hideTitles,
            // Logos are usually square/wide, not 2:3 — contain so they aren't
            // cropped; the gradient shows around them.
            imageFit: BoxFit.contain,
            isTelevision: tv,
            focusNode: controller.iptvFavNodes[col],
            onOpen: () => controller.playIptvChannel(channel),
            // DPAD focus retunes the Home hero's boxed video region to this
            // channel's live stream — same HeroTrailerBackdrop(live: true)
            // mechanism the IPTV page's own inline preview uses.
            onFocused: () => setLiveHero(channel),
          ),
        );
      },
    );
  }

  /// An opted-in IPTV custom list as a Home row. Same cell stack as the IPTV
  /// favourites row, but content-aware: play routes by the stored content
  /// type (lists can hold VOD/series alongside live), and only a live entry
  /// retunes the hero's live preview on focus.
  Widget _buildIptvListRow(
    BuildContext context,
    FavRowRef ref,
    String homeRowId,
  ) {
    final tv = isTelevision;
    final row = controller.iptvListRows[ref.list];
    return _buildFavRowShell(
      context,
      title: row.title,
      tags: [
        tag('IPTV'),
        tag('List', icon: Icons.playlist_play_rounded),
      ],
      itemCount: row.channels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = row.channels[col];
        final live = channel.isLive;
        return FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: row.nodes,
          onUp: onUp(homeRowId, col),
          onDown: onDown(homeRowId, col),
          child: ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !hideTitles,
            // Logos are usually square/wide, not 2:3 — contain so they aren't
            // cropped; the gradient shows around them.
            imageFit: BoxFit.contain,
            isTelevision: tv,
            focusNode: row.nodes[col],
            onOpen: () => controller.playIptvListChannel(channel),
            onFocused: live ? () => setLiveHero(channel) : clearHero,
          ),
        );
      },
    );
  }

  /// The "Playlist" row of the user's saved items. Cards show the item poster
  /// with a resume-progress bar; tapping opens the full action menu
  /// ([controller.onPlaylistItemTap]) — this row is a complete playlist manager on its own.
  Widget _buildPlaylistFavRow(BuildContext context, String homeRowId) {
    final tv = isTelevision;
    return _buildFavRowShell(
      context,
      title: 'Playlist',
      tags: [tag('Saved')],
      itemCount: controller.playlistItems.length,
      cellBuilder: (col, posterW, cellH) {
        final item = controller.playlistItems[col];
        final posterUrl = item['posterUrl'] as String?;
        final title = (item['title'] as String?) ?? 'Unknown';
        return FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: controller.playlistFavNodes,
          onUp: onUp(homeRowId, col),
          onDown: onDown(homeRowId, col),
          child: ArtPoster(
            imageUrl: posterUrl,
            title: title,
            showTitle: !hideTitles,
            progress: controller.playlistProgressFor(item),
            isTelevision: tv,
            focusNode: controller.playlistFavNodes[col],
            onOpen: () => controller.onPlaylistItemTap(item),
            onFocused: clearHero,
          ),
        );
      },
    );
  }
}
