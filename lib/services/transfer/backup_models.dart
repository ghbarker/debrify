/// Snapshot of what's in a backup file — used to populate the restore dialog.
class BackupSummary {
  final int? version;
  final String? createdAt;
  final bool hasRealDebrid;
  final bool hasTorbox;
  final bool hasPremiumize;
  final bool hasAllDebrid;
  final bool hasPikpak;
  final bool hasTrakt;
  final bool hasSimkl;
  final bool hasMdblist;
  final int searchEngineCount;
  final int addonCount;
  final int webDavServerCount;
  final int indexerManagerCount;
  final int iptvPlaylistCount;
  final int iptvFavoriteCount;
  final int iptvListCount;
  final int iptvListChannelCount;
  final int homeCollectionCount;
  final int streamBadgeSourceCount;

  BackupSummary({
    required this.version,
    required this.createdAt,
    required this.hasRealDebrid,
    required this.hasTorbox,
    required this.hasPremiumize,
    required this.hasAllDebrid,
    required this.hasPikpak,
    required this.hasTrakt,
    required this.hasSimkl,
    required this.hasMdblist,
    required this.searchEngineCount,
    required this.addonCount,
    required this.webDavServerCount,
    required this.indexerManagerCount,
    this.iptvPlaylistCount = 0,
    this.iptvFavoriteCount = 0,
    this.iptvListCount = 0,
    this.iptvListChannelCount = 0,
    this.homeCollectionCount = 0,
    this.streamBadgeSourceCount = 0,
  });

  bool get isEmpty =>
      !hasRealDebrid &&
      !hasTorbox &&
      !hasPremiumize &&
      !hasAllDebrid &&
      !hasPikpak &&
      !hasTrakt &&
      !hasSimkl &&
      !hasMdblist &&
      searchEngineCount == 0 &&
      addonCount == 0 &&
      webDavServerCount == 0 &&
      indexerManagerCount == 0 &&
      iptvPlaylistCount == 0 &&
      iptvFavoriteCount == 0 &&
      iptvListCount == 0 &&
      homeCollectionCount == 0 &&
      streamBadgeSourceCount == 0;
}

/// Result of a restore operation — surfaced to the user via snackbars / dialog.
class RestoreReport {
  bool realDebrid = false;
  bool torbox = false;
  bool premiumize = false;
  bool allDebrid = false;
  bool pikpak = false;
  // True if PikPak credentials were saved but logging in failed (offline,
  // wrong password, etc.). Saved credentials remain usable from settings.
  bool pikpakLoginFailed = false;
  bool trakt = false;
  bool simkl = false;
  bool mdblist = false;
  int searchEnginesImported = 0;
  int searchEnginesAlreadyPresent = 0;
  int searchEnginesFailed = 0;
  int addonsImported = 0;
  int addonsAlreadyPresent = 0;
  int addonsFailed = 0;
  int webDavServersImported = 0;
  int webDavServersAlreadyPresent = 0;
  int webDavServersFailed = 0;
  int indexerManagersImported = 0;
  int indexerManagersAlreadyPresent = 0;
  int indexerManagersFailed = 0;
  int iptvPlaylistsImported = 0;
  int iptvPlaylistsAlreadyPresent = 0;
  int iptvPlaylistsFailed = 0;
  int iptvFavoritesImported = 0;
  int iptvFavoritesAlreadyPresent = 0;
  int iptvFavoritesFailed = 0;
  int iptvListsCreated = 0;
  // Lists that already existed by name and were topped up rather than added.
  int iptvListsMerged = 0;
  int iptvListChannelsImported = 0;
  int iptvListChannelsAlreadyPresent = 0;
  int iptvListsFailed = 0;
  int homeCollectionsImported = 0;
  int homeCollectionsAlreadyPresent = 0;
  int homeCollectionsFailed = 0;
  int streamBadgeSourcesImported = 0;
  int streamBadgeSourcesAlreadyPresent = 0;
  int streamBadgeSourcesFailed = 0;
  final List<String> errors = [];

  int get totalSuccess =>
      (realDebrid ? 1 : 0) +
      (torbox ? 1 : 0) +
      (premiumize ? 1 : 0) +
      (allDebrid ? 1 : 0) +
      (pikpak ? 1 : 0) +
      (trakt ? 1 : 0) +
      (simkl ? 1 : 0) +
      (mdblist ? 1 : 0) +
      searchEnginesImported +
      addonsImported +
      webDavServersImported +
      indexerManagersImported +
      iptvPlaylistsImported +
      iptvFavoritesImported +
      iptvListsCreated +
      iptvListChannelsImported +
      homeCollectionsImported +
      streamBadgeSourcesImported;

  int get totalFailed =>
      searchEnginesFailed +
      addonsFailed +
      webDavServersFailed +
      indexerManagersFailed +
      iptvPlaylistsFailed +
      iptvFavoritesFailed +
      iptvListsFailed +
      homeCollectionsFailed +
      streamBadgeSourcesFailed +
      errors.length +
      (pikpakLoginFailed ? 1 : 0);

  bool get hasAnyFailure => totalFailed > 0;
}
