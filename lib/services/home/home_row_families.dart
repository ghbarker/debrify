import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../home_collections_store.dart';
import '../simkl/simkl_list_source.dart';
import '../trakt/trakt_list_source.dart';
import 'home_row_family.dart';
import 'home_row_ids.dart';

/// Production families in **manager-group order**. Canonical/board order is
/// [HomeRowFamily.canonicalIndex], not this list order.
List<HomeRowFamily> productionHomeRowFamilies() => [
  _localCwFamily,
  _traktCwFamily,
  _simklCwFamily,
  _mdblistCwFamily,
  _iptvCwFamily,
  _traktListFamily,
  _simklListFamily,
  _mdblistListFamily,
  _iptvListFamily,
  _collectionFamily,
  _watchlistFamily,
  _favFamily,
  _catalogFamily,
];

HomeRowFamily get _localCwFamily => HomeRowFamily(
  id: 'cw',
  prefix: HomeRowIds.cwPrefix,
  groupName: 'Continue Watching',
  boardSlot: HomeBoardSlot.continueWatching,
  canonicalIndex: 0,
  resolve: (ctx) => [
    ctx.defaultOnLeaf(
      HomeRowIds.cwMovies,
      'Movies',
      groupName: 'Continue Watching',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.cwSeries,
      'Series',
      groupName: 'Continue Watching',
    ),
  ],
);

HomeRowFamily get _traktCwFamily => HomeRowFamily(
  id: 'trakt',
  prefix: HomeRowIds.traktCwPrefix,
  groupName: 'Trakt',
  boardSlot: HomeBoardSlot.continueWatching,
  canonicalIndex: 1,
  resolve: (ctx) => [
    ctx.defaultOnLeaf(
      HomeRowIds.traktMovies,
      'Movies',
      groupName: 'Trakt',
      badge: 'CW',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.traktShows,
      'Shows',
      groupName: 'Trakt',
      badge: 'CW',
    ),
  ],
);

HomeRowFamily get _simklCwFamily => HomeRowFamily(
  id: 'simkl',
  prefix: HomeRowIds.simklCwPrefix,
  groupName: 'Simkl',
  boardSlot: HomeBoardSlot.continueWatching,
  canonicalIndex: 2,
  resolve: (ctx) => [
    ctx.defaultOnLeaf(
      HomeRowIds.simklMovies,
      'Movies',
      groupName: 'Simkl',
      badge: 'CW',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.simklShows,
      'Shows',
      groupName: 'Simkl',
      badge: 'CW',
    ),
  ],
);

HomeRowFamily get _mdblistCwFamily => HomeRowFamily(
  id: 'mdblist',
  prefix: HomeRowIds.mdblistCwPrefix,
  groupName: 'MDBList',
  boardSlot: HomeBoardSlot.continueWatching,
  canonicalIndex: 3,
  resolve: (ctx) {
    if (!ctx.mdblistEnabled) return const [];
    return [
      ctx.defaultOnLeaf(
        HomeRowIds.mdblistMovies,
        'Movies',
        groupName: 'MDBList',
        badge: 'CW',
      ),
      ctx.defaultOnLeaf(
        HomeRowIds.mdblistShows,
        'Shows',
        groupName: 'MDBList',
        badge: 'CW',
      ),
    ];
  },
);

HomeRowFamily get _iptvCwFamily => HomeRowFamily(
  id: 'iptv',
  prefix: HomeRowIds.iptvCwPrefix,
  groupName: 'IPTV Continue Watching',
  boardSlot: HomeBoardSlot.continueWatching,
  canonicalIndex: 4,
  resolve: (ctx) => [
    ctx.defaultOnLeaf(
      HomeRowIds.iptvMovies,
      'Movies',
      groupName: 'IPTV Continue Watching',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.iptvSeries,
      'Series',
      groupName: 'IPTV Continue Watching',
    ),
  ],
);

HomeRowFamily get _watchlistFamily => HomeRowFamily(
  id: 'watchlist',
  prefix: HomeRowIds.watchlistPrefix,
  groupName: 'My Watchlist',
  boardSlot: HomeBoardSlot.favourites,
  canonicalIndex: 5,
  resolve: (ctx) => [
    ctx.defaultOnLeaf(
      HomeRowIds.watchlistMovies,
      'Movies',
      groupName: 'My Watchlist',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.watchlistSeries,
      'Series',
      groupName: 'My Watchlist',
    ),
  ],
);

HomeRowFamily get _favFamily => HomeRowFamily(
  id: 'fav',
  prefix: HomeRowIds.favPrefix,
  groupName: 'Favorites',
  boardSlot: HomeBoardSlot.favourites,
  canonicalIndex: 6,
  resolve: (ctx) => [
    ctx.defaultOnLeaf(
      HomeRowIds.favPlaylist,
      'Playlist',
      groupName: 'Favorites',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.favDebrify,
      'Debrify TV',
      groupName: 'Favorites',
    ),
    ctx.defaultOnLeaf(
      HomeRowIds.favStremio,
      'Stremio TV',
      groupName: 'Favorites',
    ),
    ctx.defaultOnLeaf(HomeRowIds.favIptv, 'IPTV', groupName: 'Favorites'),
  ],
);

HomeRowFamily get _traktListFamily => HomeRowFamily(
  id: 'traktlist',
  prefix: HomeExtraRowIds.traktPrefix,
  groupName: 'Trakt',
  defaultOn: false,
  boardSlot: HomeBoardSlot.section,
  canonicalIndex: 8,
  resolve: (ctx) {
    const group = 'Trakt';
    final customLists = [
      for (final c in ctx.traktUserLists)
        if (!c.liked && c.userListId != null) c,
    ];
    final likedLists = [
      for (final c in ctx.traktUserLists)
        if (c.liked && c.userListId != null) c,
    ];
    return [
      for (final l in TraktSeeAllList.values)
        if (l != TraktSeeAllList.continueWatching)
          ctx.optInLeaf(
            HomeExtraRowIds.traktBuiltin(l),
            l.label,
            groupName: group,
            badge: 'LIST',
          ),
      for (final c in customLists)
        ctx.optInLeaf(
          HomeExtraRowIds.traktUserList(c),
          c.label,
          groupName: group,
          badge: 'CUSTOM',
        ),
      for (final c in likedLists)
        ctx.optInLeaf(
          HomeExtraRowIds.traktUserList(c),
          c.label,
          groupName: group,
          badge: 'LIKED',
        ),
    ];
  },
);

HomeRowFamily get _simklListFamily => HomeRowFamily(
  id: 'simkllist',
  prefix: HomeExtraRowIds.simklPrefix,
  groupName: 'Simkl',
  defaultOn: false,
  boardSlot: HomeBoardSlot.section,
  canonicalIndex: 9,
  resolve: (ctx) => [
    for (final l in SimklSeeAllList.values)
      if (l != SimklSeeAllList.continueWatching)
        ctx.optInLeaf(
          HomeExtraRowIds.simkl(l),
          l.label,
          groupName: 'Simkl',
          badge: 'LIST',
        ),
  ],
);

HomeRowFamily get _mdblistListFamily => HomeRowFamily(
  id: 'mdblistlist',
  prefix: HomeExtraRowIds.mdblistPrefix,
  groupName: 'MDBList',
  defaultOn: false,
  boardSlot: HomeBoardSlot.section,
  canonicalIndex: 10,
  resolve: (ctx) {
    if (!ctx.mdblistEnabled) return const [];
    return [
      for (final l in ctx.mdblistMine)
        ctx.optInLeaf(
          HomeExtraRowIds.mdblistMine(l),
          l.label,
          groupName: 'MDBList',
          badge: 'MINE',
        ),
      for (final l in ctx.mdblistLiked)
        ctx.optInLeaf(
          HomeExtraRowIds.mdblistLiked(l),
          l.label,
          groupName: 'MDBList',
          badge: 'LIKED',
        ),
      for (final l in ctx.mdblistTop)
        ctx.optInLeaf(
          HomeExtraRowIds.mdblistTop(l),
          l.label,
          groupName: 'MDBList',
          badge: 'TOP',
        ),
    ];
  },
);

HomeRowFamily get _iptvListFamily => HomeRowFamily(
  id: 'iptvlist',
  prefix: HomeExtraRowIds.iptvPrefix,
  groupName: 'IPTV Lists',
  defaultOn: false,
  boardSlot: HomeBoardSlot.favourites,
  canonicalIndex: 7,
  resolve: (ctx) => [
    for (final m in ctx.iptvLists)
      if (!m.isFavorites)
        ctx.optInLeaf(
          HomeExtraRowIds.iptvList(m.id),
          m.name,
          groupName: 'IPTV Lists',
          badge: 'LIST',
        ),
  ],
);

HomeRowFamily get _collectionFamily => HomeRowFamily(
  id: 'collection',
  prefix: HomeCollectionRowIds.prefix,
  groupName: 'Collections',
  boardSlot: HomeBoardSlot.section,
  canonicalIndex: 11,
  ownsId: (id) =>
      HomeCollectionRowIds.isCollection(id) ||
      HomeCollectionRowIds.isFolderList(id),
  resolve: (ctx) {
    final leaves = <HomeRowLeaf>[
      for (final c in ctx.collections)
        ctx.defaultOnLeaf(
          c.rowId,
          c.title,
          groupName: 'Collections',
          badge: c.pinToTop ? 'PINNED' : 'FOLDERS',
        ),
    ];
    final addons = [for (final e in ctx.catalogTree) e.addon];
    for (final c in ctx.collections) {
      for (final f in c.folders) {
        if (f.sources.isEmpty) continue;
        final group = '${c.title} › ${f.title}';
        for (final s in f.sources) {
          final id = HomeCollectionRowIds.folderList(c.id, f.id, s);
          leaves.add(
            ctx.defaultOnLeaf(
              id,
              _folderListLabel(s, addons),
              groupName: group,
              badge: s.type,
              arrangeable: false,
            ),
          );
        }
      }
    }
    return leaves;
  },
);

HomeRowFamily get _catalogFamily => HomeRowFamily(
  id: 'catalog',
  prefix: '',
  groupName: '',
  boardSlot: HomeBoardSlot.section,
  canonicalIndex: 12,
  ownsId: (id) => id.split(':').length >= 3,
  resolve: (ctx) {
    final claimed = HomeCollectionsStore.claimedCatalogKeys(ctx.collections, [
      for (final e in ctx.catalogTree) e.addon,
    ]);
    final leaves = <HomeRowLeaf>[];
    for (final entry in ctx.catalogTree) {
      final addon = entry.addon;
      for (final c in entry.catalogs) {
        final id = HomeRowIds.catalog(addon.id, c.type, c.id);
        if (claimed.contains(id)) continue;
        leaves.add(
          ctx.defaultOnLeaf(id, c.name, groupName: addon.name, badge: c.type),
        );
      }
    }
    return leaves;
  },
);

/// "Popular Movies · Action" for a folder list, resolved against the
/// installed addons. Falls back to the raw catalog id when nothing serves
/// it, so the list can still be switched off deliberately.
String _folderListLabel(CollectionCatalogSource s, List<StremioAddon> addons) {
  final addon = HomeCollectionsStore.resolveAddon(s, addons);
  final catalog = addon == null
      ? null
      : HomeCollectionsStore.resolveCatalog(s, addon);
  final base = catalog == null
      ? '${s.catalogId} (${s.type})'
      : CatalogSection.rowTitle(catalog);
  return s.genre == null ? base : '$base · ${s.genre}';
}
