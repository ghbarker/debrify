import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../fav_row_ref.dart';
import '../fav_rows_controller.dart';
import '../favourite_art_cell.dart';
import '../stage_visuals.dart';

/// Builds stage favourites from the existing live controller and host actions.
class StageFavouriteCells {
  const StageFavouriteCells({
    required this.readFavourites,
    required this.readHideTitles,
    required this.switchRail,
    required this.focused,
  });

  final FavRowsController Function() readFavourites;
  final bool Function() readHideTitles;
  final void Function(int) switchRail;
  final void Function(String, int, CanvasFavFocus, {IptvChannel? liveChannel})
      focused;

  /// One favourites cell on the Canvas shelf — the SAME [FavArtCell] +
  /// [ArtPoster] stack the classic rows use (identical art, badges, hold
  /// behaviour and open actions), with UP/DOWN rewired to rail switching and
  /// focus driving the Canvas stage override (and the full-bleed live
  /// preview, for IPTV).
  Widget build(
    FavRowRef ref,
    String railKey,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
  }) {
    final nodes = readFavourites().favNodesFor(ref);
    // Rail switching is the default vertical grammar; Mosaic (grid) and
    // Tonight (zones) pass their own.
    final up = onUp ?? () => switchRail(-1);
    final down = onDown ?? () => switchRail(1);
    // An IPTV custom-list row: same cell stack as the favourites row below,
    // but channels come from the list, play routes by CONTENT TYPE (a list
    // can hold VOD), and only a live entry retunes the stage's live preview.
    if (ref.isIptvList) {
      final row = readFavourites().iptvListRows[ref.list];
      final channel = row.channels[col];
      final live = channel.isLive;
      return FavArtCell(
        isTelevision: true,
        column: col,
        rowNodes: nodes,
        onUp: up,
        onDown: down,
        onLeft: onLeft,
        onRight: onRight,
        onUpHold: onUpHold,
        onDownHold: onDownHold,
        child: ArtPoster(
          imageUrl: channel.logoUrl,
          title: channel.name,
          showTitle: !readHideTitles(),
          imageFit: BoxFit.contain,
          isTelevision: true,
          ringColor: Colors.white,
          focusNode: nodes[col],
          onOpen: () => readFavourites().playIptvListChannel(channel),
          onFocused: () => focused(
            railKey,
            col,
            CanvasFavFocus(
              art: channel.logoUrl,
              fit: BoxFit.contain,
              title: channel.name,
              subtitle: 'IPTV · ${row.title.toUpperCase()}',
            ),
            liveChannel: live ? channel : null,
          ),
        ),
      );
    }
    switch (ref.kind) {
      case FavKind.watchlistMovies:
      case FavKind.watchlistSeries:
        final items = ref.kind == FavKind.watchlistMovies
            ? readFavourites().watchlistMovieItems
            : readFavourites().watchlistSeriesItems;
        final item = items[col];
        return FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: ArtPoster(
            imageUrl: item.poster,
            title: item.name,
            showTitle: !readHideTitles(),
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => readFavourites().openMyWatchlistItem(item),
            onFocused: () => focused(
              railKey,
              col,
              CanvasFavFocus(
                art: readFavourites().firstNonEmpty(item.background, item.poster),
                title: item.name,
                subtitle: 'MY WATCHLIST · ${item.type.toUpperCase()}',
              ),
            ),
          ),
        );
      case FavKind.iptv:
        final channel = readFavourites().iptvFavChannels[col];
        return FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !readHideTitles(),
            imageFit: BoxFit.contain,
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => readFavourites().playIptvChannel(channel),
            // Focus lights the whole stage with this channel's live feed —
            // the classic boxed preview, promoted to full-bleed.
            onFocused: () => focused(
              railKey,
              col,
              CanvasFavFocus(
                art: channel.logoUrl,
                fit: BoxFit.contain,
                title: channel.name,
                subtitle: 'IPTV · FAVORITES',
              ),
              liveChannel: channel,
            ),
          ),
        );
      case FavKind.debrify:
        final channel = readFavourites().tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: ArtPoster(
            imageUrl: null,
            title: channel.name,
            showTitle: !readHideTitles(),
            badge: '$number',
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => readFavourites().playChannel(channel),
            onFocused: () => focused(
              railKey,
              col,
              CanvasFavFocus(
                art: null,
                title: channel.name,
                subtitle: 'DEBRIFY TV · CHANNEL $number',
              ),
            ),
          ),
        );
      case FavKind.stremio:
        final channel = readFavourites().stvFavChannels[col];
        final item = readFavourites().stvNowPlaying(channel)?.item;
        return FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: ArtPoster(
            imageUrl: readFavourites().firstNonEmpty(item?.poster, item?.background),
            title: channel.displayName,
            showTitle: !readHideTitles(),
            live: true,
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => readFavourites().playStremioTvChannel(channel),
            onFocused: () => focused(
              railKey,
              col,
              CanvasFavFocus(
                // The stage prefers the WIDE art; the card keeps the poster.
                art: readFavourites().firstNonEmpty(item?.background, item?.poster),
                title: channel.displayName,
                subtitle: item != null
                    ? 'STREMIO TV · NOW: ${item.name}'
                    : 'STREMIO TV · CHANNEL',
              ),
            ),
          ),
        );
      case FavKind.playlist:
        final item = readFavourites().playlistItems[col];
        final posterUrl = item['posterUrl'] as String?;
        final title = (item['title'] as String?) ?? 'Unknown';
        return FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: ArtPoster(
            imageUrl: posterUrl,
            title: title,
            showTitle: !readHideTitles(),
            progress: readFavourites().playlistProgressFor(item),
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => readFavourites().onPlaylistItemTap(item),
            onFocused: () => focused(
              railKey,
              col,
              CanvasFavFocus(
                art: posterUrl,
                title: title,
                subtitle: 'PLAYLIST · SAVED',
              ),
            ),
          ),
        );
    }
  }
}
