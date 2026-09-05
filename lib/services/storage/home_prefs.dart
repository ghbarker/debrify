import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/tracking_source.dart';
import '../profiles/profile_preferences.dart';

/// Artwork orientation for TITLE cards on the Home layouts: portrait 2:3
/// posters or landscape 16:9 backdrops. Favourites, channel, and playlist
/// rows keep their own geometry — a station logo or folder is not a title.
/// Promenade is landscape by design and ignores the portrait setting.
enum HomeCardOrientation { portrait, landscape }

/// See [HomePrefs.getHomeHeroSource].
enum HomeHeroSourceMode { auto, random, custom }

/// The Spotlight hero source pref — see [HomePrefs.getHomeHeroSource].
/// [ids] are kept even in `auto`/`random` mode so a user flipping modes in
/// Settings doesn't lose their custom picks.
typedef HomeHeroSource = ({HomeHeroSourceMode mode, List<String> ids});

/// One opted-in extra Home row — see [HomePrefs.getHomeExtraRows].
typedef HomeExtraRow = ({String id, String title});

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
  static const String homeTickSourcesKey = 'home_tick_sources';
  static const String tvHomeStyleKey = 'tv_home_style';
  static const String _homeDisabledSectionsKey = 'home_disabled_sections_v1';
  static const String _homeExtraRowsKey = 'home_extra_rows_v1';
  static const String _homeRowOrderKey = 'home_row_order_v1';
  static const String _homeHeroSourceKey = 'home_hero_source_v1';
  static const String _homeHeroTrailerEnabledKey = 'home_hero_trailer_enabled';
  static const String _homeHeroTrailerAudioEnabledKey =
      'home_hero_trailer_audio_enabled';
  static const String _homeHeroTrailerVolumeKey = 'home_hero_trailer_volume';

  static const Set<TrackingSource> _allTrackingSources = <TrackingSource>{
    TrackingSource.local,
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  };

  /// Every shipping TV Home layout. 'canvas' is the product default;
  /// 'classic' is the original hero + scrolling rows. The rest are the
  /// alternate stages (see `_buildAtriumBoard` and friends in search_screen).
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one — or the long-removed 'shelf' — lands on 'canvas'
  /// rather than rendering nothing.
  static const Set<String> kTvHomeStyles = {
    'canvas',
    'classic',
    'atrium',
    'mosaic',
    'promenade',
    'deck',
    'tonight',
    'spotlight',
  };

  /// Synchronous mirror of `tvHomeStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String tvHomeStyleCached = 'canvas';

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
    homeTickSourcesKey,
    tvHomeStyleKey,
    _homeDisabledSectionsKey,
    _homeExtraRowsKey,
    _homeRowOrderKey,
    _homeHeroSourceKey,
    _homeHeroTrailerEnabledKey,
    _homeHeroTrailerAudioEnabledKey,
    _homeHeroTrailerVolumeKey,
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

  /// Ambient trailer in the hero surfaces — the Home board's spotlight and
  /// the Discover rail.
  ///
  /// **Defaults ON everywhere** (generation 2). This was once hard-off
  /// anywhere but a television, then a form-factor default that kept phones
  /// and tablets opted out on battery-and-cellular grounds. The hero is the
  /// Spotlight layout's centrepiece on every device now, so it starts on and
  /// the toggle in Settings is where a phone user turns it off. The stored
  /// value, once written, wins everywhere.
  static Future<bool> getHomeHeroTrailerEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHeroTrailerEnabledKey) ?? true;
  }

  static Future<void> setHomeHeroTrailerEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHeroTrailerEnabledKey, enabled);
  }

  static Future<bool> getHomeHeroTrailerAudioEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHeroTrailerAudioEnabledKey) ?? true;
  }

  static Future<void> setHomeHeroTrailerAudioEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHeroTrailerAudioEnabledKey, enabled);
  }

  static Future<int> getHomeHeroTrailerVolume() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_homeHeroTrailerVolumeKey) ?? 70;
    return v.clamp(10, 100);
  }

  static Future<void> setHomeHeroTrailerVolume(int percent) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_homeHeroTrailerVolumeKey, percent.clamp(10, 100));
  }

  /// TV Home layout. Phone/desktop and the Search tab never read it.
  static Future<String> getTvHomeStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(tvHomeStyleKey);
    return tvHomeStyleCached = kTvHomeStyles.contains(raw) ? raw! : 'canvas';
  }

  static Future<void> setTvHomeStyle(String style) async {
    final normalized = kTvHomeStyles.contains(style) ? style : 'canvas';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    tvHomeStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(tvHomeStyleKey, normalized);
  }

  static Future<Set<TrackingSource>> getHomeTickSources() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(homeTickSourcesKey);
    if (stored == null) return Set<TrackingSource>.of(_allTrackingSources);
    return <TrackingSource>{
      for (final value in stored)
        if (TrackingSourceStorageName.parse(value) case final source?) source,
    };
  }

  static Future<void> setHomeTickSources(Set<TrackingSource> value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = value.where(_allTrackingSources.contains).toSet();
    await prefs.setStringList(
      homeTickSourcesKey,
      normalized.map((source) => source.storageName).toList(growable: false),
    );
  }

  /// Get the set of Home-row IDs the user has hidden via the Home Page manager
  /// (empty = every row shown). IDs are fixed-section leaves (e.g. `cw:movies`,
  /// `trakt:shows`, `fav:iptv`) and catalog leaves (`addonId:type:catalogId`).
  static Future<Set<String>> getHomeDisabledSections() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeDisabledSectionsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading home disabled sections: $e');
      return {};
    }
  }

  /// Save the set of hidden Home-row IDs.
  static Future<void> setHomeDisabledSections(Set<String> disabled) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_homeDisabledSectionsKey);
    } else {
      await prefs.setString(
        _homeDisabledSectionsKey,
        jsonEncode(disabled.toList()),
      );
    }
  }

  /// The OPT-IN extra Home rows (default-off, so the disabled-set above can't
  /// express them): Trakt/Simkl list rows and IPTV custom-list rows. IDs are
  /// `traktlist:<apiValue>`, `traktlist:custom:<id>`, `traktlist:liked:<id>`,
  /// `simkllist:<enumName>`, `iptvlist:<listId>`. [HomeExtraRow.title] is the
  /// display name captured at opt-in time so dynamic rows (custom/liked
  /// lists, IPTV lists) render a header instantly and stay representable in
  /// the Home Rows manager through an API outage; built-in rows ignore it.
  /// Order is NOT meaningful — the board renders extras in canonical order.
  static Future<List<HomeExtraRow>> getHomeExtraRows() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeExtraRowsKey);
    if (json == null) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final seen = <String>{};
      final out = <HomeExtraRow>[];
      for (final e in list) {
        if (e is! Map) continue;
        final id = e['id'];
        if (id is! String || id.isEmpty || !seen.add(id)) continue;
        final title = e['title'];
        out.add((id: id, title: title is String ? title : ''));
      }
      return out;
    } catch (e) {
      debugPrint('Error reading home extra rows: $e');
      return const [];
    }
  }

  /// Save the opted-in extra Home rows (empty = key removed).
  static Future<void> setHomeExtraRows(List<HomeExtraRow> rows) async {
    final prefs = await ProfilePreferences.instance();
    if (rows.isEmpty) {
      await prefs.remove(_homeExtraRowsKey);
    } else {
      await prefs.setString(
        _homeExtraRowsKey,
        jsonEncode([
          for (final r in rows) {'id': r.id, 'title': r.title},
        ]),
      );
    }
  }

  /// The user's global Home-row order, expressed with the same stable ids used
  /// by the Home Rows manager. Missing/unavailable ids remain in this list so
  /// reconnecting a tracker or reinstalling an addon restores its old slot.
  /// An empty list means the board's canonical order.
  static Future<List<String>> getHomeRowOrder() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeRowOrderKey);
    if (json == null) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      final seen = <String>{};
      return [
        for (final value in raw)
          if (value is String && value.isNotEmpty && seen.add(value)) value,
      ];
    } catch (e) {
      debugPrint('Error reading home row order: $e');
      return const [];
    }
  }

  /// Save the user's global Home-row order. Empty restores canonical order.
  static Future<void> setHomeRowOrder(List<String> order) async {
    final prefs = await ProfilePreferences.instance();
    final seen = <String>{};
    final normalized = [
      for (final id in order)
        if (id.isNotEmpty && seen.add(id)) id,
    ];
    if (normalized.isEmpty) {
      await prefs.remove(_homeRowOrderKey);
    } else {
      await prefs.setString(_homeRowOrderKey, jsonEncode(normalized));
    }
  }

  /// Where the Spotlight home layout's hero reel comes from.
  ///
  /// Modes: `random` (the DEFAULT — "Surprise me": any installed browsable
  /// catalog, re-rolled each board load), `auto` (the first non-empty board
  /// row) and `custom` (one of [HomeHeroSource.ids], catalog leaves in the
  /// Home Rows grammar `addonId:type:catalogId`; more than one re-rolls among
  /// them each load). Unknown modes and a custom mode with no ids read back
  /// as `random` so a bad write can never wedge the hero. `auto` is an
  /// explicit choice now, so it is STORED — only the default removes the key.
  static Future<HomeHeroSource> getHomeHeroSource() async {
    const fallback = (mode: HomeHeroSourceMode.random, ids: <String>[]);
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeHeroSourceKey);
    if (json == null) return fallback;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final ids = <String>[];
      final seen = <String>{};
      final rawIds = map['ids'];
      if (rawIds is List) {
        for (final e in rawIds) {
          if (e is String && e.isNotEmpty && seen.add(e)) ids.add(e);
        }
      }
      final mode = switch (map['mode']) {
        'auto' => HomeHeroSourceMode.auto,
        'custom' when ids.isNotEmpty => HomeHeroSourceMode.custom,
        _ => HomeHeroSourceMode.random,
      };
      return (mode: mode, ids: ids);
    } catch (e) {
      debugPrint('Error reading home hero source: $e');
      return fallback;
    }
  }

  /// Save the Spotlight hero source (the default `random` + no ids = key
  /// removed; `auto` is stored, or it would read back as the default).
  static Future<void> setHomeHeroSource(HomeHeroSource source) async {
    final prefs = await ProfilePreferences.instance();
    if (source.mode == HomeHeroSourceMode.random && source.ids.isEmpty) {
      await prefs.remove(_homeHeroSourceKey);
    } else {
      await prefs.setString(
        _homeHeroSourceKey,
        jsonEncode({'mode': source.mode.name, 'ids': source.ids}),
      );
    }
  }
  /// Runs between generation 1 theme/detail and sidebar writes.
  static Future<void> migrateDefaultsGeneration1TvHome(
    ProfilePreferences prefs,
  ) async {
    if (!prefs.containsKey(tvHomeStyleKey)) {
      await prefs.setString(tvHomeStyleKey, 'spotlight');
    }
  }

  /// Runs before the coordinator's residual detail-trailer write.
  static Future<void> migrateDefaultsGeneration2Trailers(
    ProfilePreferences prefs,
  ) async {
    // Both ambient trailer surfaces, for installs whose form factor used to
    // default one of them off. An explicit off — the toggles write
    // unconditionally, so a stored `false` is always a real choice — is left
    // alone: this turns trailers on for people who never had an opinion, not
    // for people who said no.
    if (!prefs.containsKey('home_hero_trailer_enabled')) {
      await prefs.setBool('home_hero_trailer_enabled', true);
    }
  }

}
