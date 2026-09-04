import 'transfer_category.dart';
import 'transfer_category_registry.dart';
import 'transfer_categories.dart';

/// Which categories to include when restoring.
///
/// Internally a [Set] of [TransferCategory] for [BackupSelection.only] /
/// [BackupSelection.all]. The named constructor keeps today's bool fields and
/// default-on quirk (`mdblist`, IPTV, `homeCollections`, `streamBadges`) so
/// unowned callers such as `test/tracking_source_storage_test.dart` stay
/// `const`.
///
/// New call sites should use [BackupSelection.only] with an explicit set —
/// omitting a default-on field from the named constructor used to silently
/// re-apply it (the restore coordinator's double-apply bug).
class BackupSelection {
  final Set<TransferCategory>? _explicit;

  final bool realDebrid;
  final bool torbox;
  final bool premiumize;
  final bool allDebrid;
  final bool pikpak;
  final bool trakt;
  final bool simkl;
  final bool mdblist;
  final bool searchEngines;
  final bool addons;
  final bool webDav;
  final bool indexerManagers;
  final bool iptvPlaylists;
  final bool iptvFavorites;
  final bool iptvLists;
  final bool homeCollections;
  final bool streamBadges;
  final bool trackingPreferences;

  const BackupSelection({
    required this.realDebrid,
    required this.torbox,
    required this.premiumize,
    required this.allDebrid,
    required this.pikpak,
    required this.trakt,
    required this.simkl,
    this.mdblist = true,
    required this.searchEngines,
    required this.addons,
    required this.webDav,
    required this.indexerManagers,
    this.iptvPlaylists = true,
    this.iptvFavorites = true,
    this.iptvLists = true,
    this.homeCollections = true,
    this.streamBadges = true,
    this.trackingPreferences = false,
  }) : _explicit = null;

  BackupSelection._fromSet(Set<TransferCategory> categories)
    : _explicit = Set<TransferCategory>.unmodifiable(categories),
      realDebrid = categories.contains(TransferCategories.realDebrid),
      torbox = categories.contains(TransferCategories.torbox),
      premiumize = categories.contains(TransferCategories.premiumize),
      allDebrid = categories.contains(TransferCategories.allDebrid),
      pikpak = categories.contains(TransferCategories.pikpak),
      trakt = categories.contains(TransferCategories.trakt),
      simkl = categories.contains(TransferCategories.simkl),
      mdblist = categories.contains(TransferCategories.mdblist),
      searchEngines = categories.contains(TransferCategories.searchEngines),
      addons = categories.contains(TransferCategories.addons),
      webDav = categories.contains(TransferCategories.webDav),
      indexerManagers = categories.contains(TransferCategories.indexerManagers),
      iptvPlaylists = categories.contains(TransferCategories.iptvPlaylists),
      iptvFavorites = categories.contains(TransferCategories.iptvFavorites),
      iptvLists = categories.contains(TransferCategories.iptvLists),
      homeCollections = categories.contains(TransferCategories.homeCollections),
      streamBadges = categories.contains(TransferCategories.streamBadges),
      trackingPreferences = categories.contains(
        TransferCategories.trackingPreferences,
      );

  /// Every currently registered category, including fakes added in tests.
  factory BackupSelection.all() =>
      BackupSelection._fromSet({...TransferCategoryRegistry.instance.all});

  /// Explicit set — the form the restore coordinator must use.
  factory BackupSelection.only(Iterable<TransferCategory> categories) =>
      BackupSelection._fromSet({...categories});

  bool contains(Object? category) {
    if (category is! TransferCategory) return false;
    if (_explicit != null) return _explicit.contains(category);
    return identical(category, TransferCategories.realDebrid) && realDebrid ||
        identical(category, TransferCategories.torbox) && torbox ||
        identical(category, TransferCategories.premiumize) && premiumize ||
        identical(category, TransferCategories.allDebrid) && allDebrid ||
        identical(category, TransferCategories.pikpak) && pikpak ||
        identical(category, TransferCategories.trakt) && trakt ||
        identical(category, TransferCategories.simkl) && simkl ||
        identical(category, TransferCategories.mdblist) && mdblist ||
        identical(category, TransferCategories.searchEngines) &&
            searchEngines ||
        identical(category, TransferCategories.addons) && addons ||
        identical(category, TransferCategories.webDav) && webDav ||
        identical(category, TransferCategories.indexerManagers) &&
            indexerManagers ||
        identical(category, TransferCategories.iptvPlaylists) &&
            iptvPlaylists ||
        identical(category, TransferCategories.iptvFavorites) &&
            iptvFavorites ||
        identical(category, TransferCategories.iptvLists) && iptvLists ||
        identical(category, TransferCategories.homeCollections) &&
            homeCollections ||
        identical(category, TransferCategories.streamBadges) && streamBadges ||
        identical(category, TransferCategories.trackingPreferences) &&
            trackingPreferences;
  }

  BackupSelection copyWith({
    bool? realDebrid,
    bool? torbox,
    bool? premiumize,
    bool? allDebrid,
    bool? pikpak,
    bool? trakt,
    bool? simkl,
    bool? mdblist,
    bool? searchEngines,
    bool? addons,
    bool? webDav,
    bool? indexerManagers,
    bool? iptvPlaylists,
    bool? iptvFavorites,
    bool? iptvLists,
    bool? homeCollections,
    bool? streamBadges,
    bool? trackingPreferences,
  }) {
    return BackupSelection(
      realDebrid: realDebrid ?? this.realDebrid,
      torbox: torbox ?? this.torbox,
      premiumize: premiumize ?? this.premiumize,
      allDebrid: allDebrid ?? this.allDebrid,
      pikpak: pikpak ?? this.pikpak,
      trakt: trakt ?? this.trakt,
      simkl: simkl ?? this.simkl,
      mdblist: mdblist ?? this.mdblist,
      searchEngines: searchEngines ?? this.searchEngines,
      addons: addons ?? this.addons,
      webDav: webDav ?? this.webDav,
      indexerManagers: indexerManagers ?? this.indexerManagers,
      iptvPlaylists: iptvPlaylists ?? this.iptvPlaylists,
      iptvFavorites: iptvFavorites ?? this.iptvFavorites,
      iptvLists: iptvLists ?? this.iptvLists,
      homeCollections: homeCollections ?? this.homeCollections,
      streamBadges: streamBadges ?? this.streamBadges,
      trackingPreferences: trackingPreferences ?? this.trackingPreferences,
    );
  }
}
