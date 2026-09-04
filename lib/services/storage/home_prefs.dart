import '../profiles/profile_preferences.dart';

/// Artwork orientation for TITLE cards on the Home layouts: portrait 2:3
/// posters or landscape 16:9 backdrops. Favourites, channel, and playlist
/// rows keep their own geometry — a station logo or folder is not a title.
/// Promenade is landscape by design and ignores the portrait setting.
enum HomeCardOrientation { portrait, landscape }

/// Home page default prefs. [StorageService] forwards to this store.
///
/// Key names and encodings are frozen; do not rename a persisted string.
class HomePrefs {
  HomePrefs._();

  // Home page default keys
  static const String _homeDefaultSourceTypeKey = 'home_default_source_type';
  static const String _homeDefaultAddonUrlKey = 'home_default_addon_url';
  static const String _homeDefaultCatalogIdKey = 'home_default_catalog_id';
  static const String _homeDefaultTraktListTypeKey =
      'home_default_trakt_list_type';
  static const String _homeDefaultTraktContentTypeKey =
      'home_default_trakt_content_type';
  static const String _homeHideProviderCardsKey = 'home_hide_provider_cards';
  static const String _homeContinueWatchingEnabledKey =
      'home_continue_watching_enabled';
  static const String _homeCwHoldToQuickPlayKey = 'home_cw_hold_to_quick_play';
  static const String _homeCwMergedRowsKeyPrefix = 'home_cw_merge_';
  static const String _homeFavoritesOpenFolderKey =
      'home_favorites_open_folder';
  static const String _homeCardOrientationKey = 'home_card_orientation';
  static const String _homeHideCardTitlesAndRatingsKey =
      'home_hide_card_titles_and_ratings';
  static const String _homeHideCatalogAddonNamesKey =
      'home_hide_catalog_addon_names';

  /// Declared persisted names (including the CW-merge prefix).
  static const Set<String> ownedKeys = {
    _homeDefaultSourceTypeKey,
    _homeDefaultAddonUrlKey,
    _homeDefaultCatalogIdKey,
    _homeDefaultTraktListTypeKey,
    _homeDefaultTraktContentTypeKey,
    _homeHideProviderCardsKey,
    _homeContinueWatchingEnabledKey,
    _homeCwHoldToQuickPlayKey,
    _homeCwMergedRowsKeyPrefix,
    _homeFavoritesOpenFolderKey,
    _homeCardOrientationKey,
    _homeHideCardTitlesAndRatingsKey,
    _homeHideCatalogAddonNamesKey,
  };

  // Home Page Default Settings
  static Future<String?> getHomeDefaultSourceType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultSourceTypeKey);
  }

  static Future<void> setHomeDefaultSourceType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultSourceTypeKey);
    } else {
      await prefs.setString(_homeDefaultSourceTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultAddonUrl() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultAddonUrlKey);
  }

  static Future<void> setHomeDefaultAddonUrl(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultAddonUrlKey);
    } else {
      await prefs.setString(_homeDefaultAddonUrlKey, value);
    }
  }

  static Future<String?> getHomeDefaultCatalogId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultCatalogIdKey);
  }

  static Future<void> setHomeDefaultCatalogId(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultCatalogIdKey);
    } else {
      await prefs.setString(_homeDefaultCatalogIdKey, value);
    }
  }

  static Future<String?> getHomeDefaultTraktListType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultTraktListTypeKey);
  }

  static Future<void> setHomeDefaultTraktListType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultTraktListTypeKey);
    } else {
      await prefs.setString(_homeDefaultTraktListTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultTraktContentType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultTraktContentTypeKey);
  }

  static Future<void> setHomeDefaultTraktContentType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultTraktContentTypeKey);
    } else {
      await prefs.setString(_homeDefaultTraktContentTypeKey, value);
    }
  }

  static Future<bool> getHomeHideProviderCards() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideProviderCardsKey) ?? true;
  }

  static Future<void> setHomeHideProviderCards(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideProviderCardsKey, value);
  }

  static Future<bool> getHomeContinueWatchingEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeContinueWatchingEnabledKey) ?? true;
  }

  static Future<void> setHomeContinueWatchingEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeContinueWatchingEnabledKey, value);
  }

  /// Whether holding a Continue Watching card should immediately Quick Play
  /// instead of opening the Play / Remove action menu. Off by default so the
  /// removal action remains discoverable until the user opts into the faster
  /// gesture.
  static Future<bool> getHomeCwHoldToQuickPlay() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeCwHoldToQuickPlayKey) ?? false;
  }

  static Future<void> setHomeCwHoldToQuickPlay(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeCwHoldToQuickPlayKey, value);
  }

  /// Whether [provider]'s home Continue Watching shelf combines Movies and
  /// Shows into ONE recency-ordered row instead of two. [provider] is one of
  /// 'local', 'trakt', 'simkl', 'mdblist'. Off by default (two rows, the
  /// original layout).
  static Future<bool> getHomeCwMergedRows(String provider) async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('$_homeCwMergedRowsKeyPrefix$provider') ?? false;
  }

  static Future<void> setHomeCwMergedRows(String provider, bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('$_homeCwMergedRowsKeyPrefix$provider', value);
  }

  static Future<String> getHomeFavoritesTapAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeFavoritesOpenFolderKey) ?? 'choose';
  }

  static Future<void> setHomeFavoritesTapAction(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_homeFavoritesOpenFolderKey, value);
  }

  /// Landscape is the DEFAULT (since 0.8.4): the absence of the key means
  /// landscape, so only an explicit 'portrait' choice reads as portrait.
  static Future<HomeCardOrientation> getHomeCardOrientation() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeCardOrientationKey) == 'portrait'
        ? HomeCardOrientation.portrait
        : HomeCardOrientation.landscape;
  }

  static Future<void> setHomeCardOrientation(
    HomeCardOrientation orientation,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_homeCardOrientationKey, orientation.name);
  }

  /// Keeps Home artwork clean by suppressing the title and rating painted on
  /// content cards. Row headings, hero identity, progress and context metadata
  /// are separate presentation and remain visible.
  static Future<bool> getHomeHideCardTitlesAndRatings() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideCardTitlesAndRatingsKey) ?? false;
  }

  static Future<void> setHomeHideCardTitlesAndRatings(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideCardTitlesAndRatingsKey, value);
  }

  /// Suppresses the source/add-on pill beside Home catalog row headings.
  /// The catalog title itself remains visible so the row keeps its identity.
  static Future<bool> getHomeHideCatalogAddonNames() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideCatalogAddonNamesKey) ?? false;
  }

  static Future<void> setHomeHideCatalogAddonNames(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideCatalogAddonNamesKey, value);
  }

  static Future<void> clearAllHomePageSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_homeDefaultSourceTypeKey);
    await prefs.remove(_homeDefaultAddonUrlKey);
    await prefs.remove(_homeDefaultCatalogIdKey);
    await prefs.remove(_homeHideProviderCardsKey);
    await prefs.remove(_homeContinueWatchingEnabledKey);
    await prefs.remove(_homeCwHoldToQuickPlayKey);
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}local');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}trakt');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}simkl');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}mdblist');
    await prefs.remove(_homeFavoritesOpenFolderKey);
    await prefs.remove(_homeCardOrientationKey);
    await prefs.remove(_homeHideCardTitlesAndRatingsKey);
    await prefs.remove(_homeHideCatalogAddonNamesKey);
  }
}
