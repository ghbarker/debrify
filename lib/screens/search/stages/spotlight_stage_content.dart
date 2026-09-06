import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../services/home_collection_rows.dart';
import '../../../utils/continue_watching_presentation.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../continue_watching_controller.dart';
import '../fav_row_ref.dart';
import '../fav_rows_controller.dart';
import '../search_board_runtime.dart';

/// Existing presentation/route operations still shared with other Home stages.
/// No State or context is stored; catalogue callbacks retain live board reads.
typedef SpotlightContentBindings = ({
  bool Function() landscapeCards,
  String Function(CanvasRail) railKeyOf,
  String? Function(StremioMeta) wideArtUrl,
  String? Function(CatalogSection) catalogSourceTag,
  String? Function(StremioTvChannel, {bool landscape}) stvFavArt,
  Widget Function(IptvChannel) iptvPreview,
  void Function(CatalogSection) openCatalogSeeAll,
  void Function(HomeCollectionSection, StremioMeta) openCollectionFolder,
  void Function(StremioMeta, StremioAddon) openItem,
  Future<void> Function(CwRow, StremioMeta, int, int) openCwCardMenu,
});

/// Builds Spotlight's real catalog/CW/favourite shelves, borrowing their owners.
/// It allocates no nodes, subscriptions, caches or controller lifetimes.
class SpotlightStageContent {
  const SpotlightStageContent({
    required this.board,
    required this.favourites,
    required this.bindings,
  });

  final SearchBoardRuntime board;
  final FavRowsController favourites;
  final SpotlightContentBindings bindings;

  List<SpotlightShelf> get shelves => [
    for (final rail in board.canvasRails) shelfForRail(rail),
  ];

  SpotlightShelf shelfForRail(CanvasRail rail) {
    // Rail identity — the same key Canvas/Atrium key their rails by — so the
    // board reuses shelf subtrees when tracker rows front-insert.
    final railKey = bindings.railKeyOf(rail);
    final row = rail.cw;
    if (row != null) {
      return SpotlightShelf(
        id: railKey,
        title: row.title,
        // The tag used to be folded into the title text; now it IS the tag —
        // the same pill grammar the catalog rows wear.
        tag: row.tag,
        nodes: row.nodes,
        // Already nullable on the row itself — a tracker row with no grid
        // behind it hands over null and simply draws no chevron.
        onSeeAll: row.onSeeAll,
        // Caption-free like catalog rows in PORTRAIT off TV. LANDSCAPE flips
        // the premise: a textless still needs the title, and CW's second line
        // adds its useful episode / remaining-time context.
        captions: bindings.landscapeCards(),
        items: [
          for (var col = 0; col < row.items.length; col++)
            _continueWatchingCard(row, row.items[col], rail.cwIndex, col),
        ],
      );
    }
    final fav = rail.favKind;
    if (fav != null) return _favShelf(fav, id: railKey);
    final i = rail.sectionIndex!;
    final section = board.sections[i];
    if (section is HomeCollectionSection) {
      return SpotlightShelf(
        id: railKey,
        title: section.title,
        tag: bindings.catalogSourceTag(section),
        nodes: i < board.rowNodes.length ? board.rowNodes[i] : const [],
        onSeeAll: () => bindings.openCatalogSeeAll(section),
        // A brand-logo tile needs no caption; captions stay on only while
        // some folder still wants its title drawn.
        captions: section.collection.folders.any((f) => !f.hideTitle),
        items: [
          for (final m in section.items)
            SpotlightCard(
              image: m.poster,
              fallbackImage: m.background,
              previewBuilder: section.focusArtOf(m) == null
                  ? null
                  : (_) => CachedNetworkImage(
                      imageUrl: section.focusArtOf(m)!,
                      fit: BoxFit.cover,
                    ),
              title: m.name,
              shape: section.landscapeTiles
                  ? SpotlightCardShape.wide
                  : SpotlightCardShape.poster,
              onOpen: () => bindings.openCollectionFolder(section, m),
            ),
        ],
      );
    }
    return SpotlightShelf(
      id: railKey,
      title: board.sections[i].title,
      tag: bindings.catalogSourceTag(board.sections[i]),
      nodes: i < board.rowNodes.length ? board.rowNodes[i] : const [],
      // The same destination the classic rails' "See All" link opens —
      // including the tracker-list rows, which bindings.openCatalogSeeAll routes to
      // their own browser rather than the catalog pager.
      onSeeAll: () => bindings.openCatalogSeeAll(board.sections[i]),
      // Catalog cards go caption-free off TV in PORTRAIT — the art is the
      // label; a caption repeating the poster's own title was the
      // reference's one piece of noise we added ourselves. That rationale
      // inverts for LANDSCAPE, where the backdrop is a textless still and
      // the caption is the only identity the card has.
      captions: bindings.landscapeCards(),
      items: [
        for (final m in board.sections[i].items)
          SpotlightCard(
            image: bindings.landscapeCards()
                ? bindings.wideArtUrl(m)
                : m.poster,
            fallbackImage: bindings.landscapeCards() ? m.poster : null,
            title: m.name,
            rating: m.imdbRating,
            shape: bindings.landscapeCards()
                ? SpotlightCardShape.wide
                : SpotlightCardShape.poster,
            watchedImdbId: m.type == 'movie' || m.type == 'series'
                ? (m.effectiveImdbId ?? m.id)
                : null,
            watchedContentType: m.type,
            onOpen: () => bindings.openItem(m, board.sections[i].addon),
          ),
      ],
    );
  }

  SpotlightCard _continueWatchingCard(
    CwRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) {
    final wideArt = bindings.wideArtUrl(item);
    final episodeArt = item.type == 'series'
        ? row.episodeArtworkOf(item)
        : null;
    return SpotlightCard(
      image: bindings.landscapeCards() ? (episodeArt ?? wideArt) : item.poster,
      // An episode still is best-effort. If it fails at image-decode time (not
      // only during lookup), fall back to the same show art CW used before.
      fallbackImage: bindings.landscapeCards()
          ? (episodeArt != null ? wideArt : item.poster)
          : null,
      title: item.name,
      subtitle: continueWatchingCardSubtitle(
        episodeLabel: row.episodeOf(item),
        minutesLeft: row.remainingMinutesOf(item),
      ),
      rating: item.imdbRating,
      shape: bindings.landscapeCards()
          ? SpotlightCardShape.wide
          : SpotlightCardShape.poster,
      // `CwRow` publishes a 0..1 fraction; the card draws 0..100.
      progress: (row.progressOf(item) ?? 0) * 100,
      onOpen: () => row.onOpen(item),
      // Spotlight used to bypass the shared CW hold handler and Quick Play
      // unconditionally. Route through the same preference-aware menu path as
      // every other Home layout so disabled means Play/Remove and enabled
      // means immediate playback on both touch and DPAD.
      onOptions: () => bindings.openCwCardMenu(row, item, cwIndex, col),
    );
  }

  /// A favourites rail as Spotlight cards.
  ///
  /// The four kinds are NOT the same shape. A playlist is a container rather
  /// than a title, so it keeps the poster it was given (or its override) and
  /// says how many items it holds. The three channel kinds carry LOGOS — wide,
  /// frequently transparent marks — which a 2:3 crop cuts in half, so they get
  /// a square tile that contains the art on a plate instead of filling with it.
  SpotlightShelf _favShelf(FavRowRef ref, {String? id}) {
    final nodes = favourites.favNodesFor(ref);
    if (ref.isIptvList) {
      final row = favourites.iptvListRows[ref.list];
      return SpotlightShelf(
        id: id,
        title: row.title,
        nodes: nodes,
        items: [
          for (final ch in row.channels)
            SpotlightCard(
              image: ch.logoUrl,
              title: ch.name,
              subtitle: 'LIVE',
              shape: bindings.landscapeCards()
                  ? SpotlightCardShape.wideChannel
                  : SpotlightCardShape.channel,
              onOpen: () => favourites.playIptvListChannel(ch),
              previewBuilder: ch.isLive
                  ? (_) => bindings.iptvPreview(ch)
                  : null,
            ),
        ],
      );
    }
    switch (ref.kind) {
      case FavKind.watchlistMovies:
      case FavKind.watchlistSeries:
        final isMovies = ref.kind == FavKind.watchlistMovies;
        final items = isMovies
            ? favourites.watchlistMovieItems
            : favourites.watchlistSeriesItems;
        return SpotlightShelf(
          id: id,
          title: isMovies ? 'Watchlist Movies' : 'Watchlist Series',
          nodes: nodes,
          // Same rule as the catalog rows off TV: pure poster cards in
          // portrait, captions back for landscape backdrops. The subtitle
          // stays on the card because TV still renders overlay captions
          // (this flag is non-TV only) — dropping it here would have
          // changed TV cards too.
          captions: bindings.landscapeCards(),
          items: [
            for (final item in items)
              SpotlightCard(
                image: bindings.landscapeCards()
                    ? bindings.wideArtUrl(item)
                    : item.poster,
                fallbackImage: bindings.landscapeCards() ? item.poster : null,
                title: item.name,
                rating: item.imdbRating,
                subtitle: isMovies ? 'MOVIE' : 'SERIES',
                shape: bindings.landscapeCards()
                    ? SpotlightCardShape.wide
                    : SpotlightCardShape.poster,
                watchedImdbId: item.effectiveImdbId ?? item.id,
                watchedContentType: item.type,
                onOpen: () => favourites.openMyWatchlistItem(item),
              ),
          ],
        );
      case FavKind.playlist:
        return SpotlightShelf(
          id: id,
          title: 'Playlists',
          nodes: nodes,
          items: [
            for (final item in favourites.playlistItems)
              SpotlightCard(
                image: item['posterUrl'] as String?,
                title: (item['title'] as String?) ?? 'Unknown',
                progress: favourites.playlistProgressFor(item),
                onOpen: () => favourites.onPlaylistItemTap(item),
              ),
          ],
        );
      case FavKind.iptv:
        return SpotlightShelf(
          id: id,
          title: 'IPTV Favourites',
          nodes: nodes,
          items: [
            for (final ch in favourites.iptvFavChannels)
              SpotlightCard(
                image: ch.logoUrl,
                title: ch.name,
                subtitle: 'LIVE',
                shape: bindings.landscapeCards()
                    ? SpotlightCardShape.wideChannel
                    : SpotlightCardShape.channel,
                onOpen: () => favourites.playIptvChannel(ch),
                previewBuilder: ch.isLive
                    ? (_) => bindings.iptvPreview(ch)
                    : null,
              ),
          ],
        );
      case FavKind.debrify:
        return SpotlightShelf(
          id: id,
          title: 'Debrify TV',
          nodes: nodes,
          items: [
            for (final ch in favourites.tvFavChannels)
              SpotlightCard(
                title: ch.name,
                subtitle: 'CHANNEL ${ch.channelNumber}',
                shape: bindings.landscapeCards()
                    ? SpotlightCardShape.wideChannel
                    : SpotlightCardShape.channel,
                onOpen: () => favourites.playChannel(ch),
              ),
          ],
        );
      case FavKind.stremio:
        return SpotlightShelf(
          id: id,
          title: 'Stremio TV',
          nodes: nodes,
          items: [
            for (final ch in favourites.stvFavChannels)
              SpotlightCard(
                image: bindings.stvFavArt(
                  ch,
                  landscape: bindings.landscapeCards(),
                ),
                fallbackImage: bindings.landscapeCards()
                    ? favourites.stvNowPlaying(ch)?.item.poster
                    : null,
                title: ch.displayName,
                subtitle: 'STREMIO TV',
                // The now-playing TITLE's rating — the card wears title art,
                // so the rating follows the title, not the channel.
                rating: favourites.stvNowPlaying(ch)?.item.imdbRating,
                // Title art, not a channel logo: follow the user's Spotlight
                // title-card orientation instead of containing it as a square
                // station mark.
                shape: bindings.landscapeCards()
                    ? SpotlightCardShape.wide
                    : SpotlightCardShape.poster,
                onOpen: () => favourites.playStremioTvChannel(ch),
              ),
          ],
        );
    }
  }
}
