import '../mdblist/mdblist_list_source.dart';
import '../simkl/simkl_list_source.dart';
import '../trakt/trakt_list_source.dart';

/// Frozen Home row-id grammar. Prefixes are a compatibility surface — renaming
/// a persisted id is not allowed (REFACTOR_PLAN §2.4).
class HomeRowIds {
  HomeRowIds._();

  static const String cwPrefix = 'cw:';
  static const String traktCwPrefix = 'trakt:';
  static const String simklCwPrefix = 'simkl:';
  static const String mdblistCwPrefix = 'mdblist:';
  static const String iptvCwPrefix = 'iptv:';
  static const String watchlistPrefix = 'watchlist:';
  static const String favPrefix = 'fav:';

  static const String cwMovies = 'cw:movies';
  static const String cwSeries = 'cw:series';
  static const String traktMovies = 'trakt:movies';
  static const String traktShows = 'trakt:shows';
  static const String simklMovies = 'simkl:movies';
  static const String simklShows = 'simkl:shows';
  static const String mdblistMovies = 'mdblist:movies';
  static const String mdblistShows = 'mdblist:shows';
  static const String iptvMovies = 'iptv:movies';
  static const String iptvSeries = 'iptv:series';
  static const String watchlistMovies = 'watchlist:movies';
  static const String watchlistSeries = 'watchlist:series';
  static const String favPlaylist = 'fav:playlist';
  static const String favDebrify = 'fav:debrify';
  static const String favStremio = 'fav:stremio';
  static const String favIptv = 'fav:iptv';

  /// `addonId:type:catalogId` — search_screen `_sectionRowId` / `_catalogRefRowId`.
  static String catalog(String addonId, String type, String catalogId) =>
      '$addonId:$type:$catalogId';

  /// Section row id: list/collection rows carry their own id; catalogs use
  /// [catalog]. Copied from search_screen `_sectionRowId`.
  static String sectionRowId({
    String? listRowId,
    String? collectionRowId,
    required String addonId,
    required String catalogType,
    required String catalogId,
  }) =>
      listRowId ?? collectionRowId ?? catalog(addonId, catalogType, catalogId);
}

/// ID grammar for the opt-in extra Home rows (see
/// `HomePrefs.getHomeExtraRows`). Kept together so the board, the
/// resolver and the Home Rows manager can never drift on what an id means.
class HomeExtraRowIds {
  HomeExtraRowIds._();

  static const String traktPrefix = 'traktlist:';
  static const String traktCustomPrefix = 'traktlist:custom:';
  static const String traktLikedPrefix = 'traktlist:liked:';
  static const String simklPrefix = 'simkllist:';
  static const String mdblistPrefix = 'mdblistlist:';
  static const String mdblistMinePrefix = 'mdblistlist:mine:';
  static const String mdblistLikedPrefix = 'mdblistlist:liked:';
  static const String mdblistTopPrefix = 'mdblistlist:top:';
  static const String iptvPrefix = 'iptvlist:';

  /// `traktlist:watchlist` … — built-ins key off the API slug, which is
  /// stable across enum reorderings.
  static String traktBuiltin(TraktSeeAllList list) =>
      '$traktPrefix${list.apiValue}';

  static String traktUserList(TraktListChoice choice) => choice.liked
      ? '$traktLikedPrefix${choice.userListId}'
      : '$traktCustomPrefix${choice.userListId}';

  /// `simkllist:planToWatch` … — enum names are part of the storage contract;
  /// renaming a [SimklSeeAllList] value needs a migration.
  static String simkl(SimklSeeAllList list) => '$simklPrefix${list.name}';

  static String mdblistMine(MdblistListChoice list) =>
      '$mdblistMinePrefix${list.id}';
  static String mdblistLiked(MdblistListChoice list) =>
      '$mdblistLikedPrefix${list.id}';
  static String mdblistTop(MdblistListChoice list) =>
      '$mdblistTopPrefix${list.id}';

  static String iptvList(String listId) => '$iptvPrefix$listId';

  static bool isTracker(String id) =>
      id.startsWith(traktPrefix) ||
      id.startsWith(simklPrefix) ||
      id.startsWith(mdblistPrefix);

  static bool isMdblist(String id) => id.startsWith(mdblistPrefix);

  static bool isTraktUserList(String id) =>
      id.startsWith(traktCustomPrefix) || id.startsWith(traktLikedPrefix);

  static bool isIptv(String id) => id.startsWith(iptvPrefix);

  /// The `<listId>` of an `iptvlist:` id (null for anything else).
  static String? iptvListId(String id) =>
      isIptv(id) ? id.substring(iptvPrefix.length) : null;
}
