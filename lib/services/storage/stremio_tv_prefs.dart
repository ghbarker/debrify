import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/json_isolate.dart';
import '../profiles/profile_preferences.dart';

/// Stremio TV rotation, catalog, filter, and favorite prefs.
///
/// [StorageService] forwards to this store. Key names and encodings are
/// frozen; do not rename a persisted string.
class StremioTvPrefs {
  StremioTvPrefs._();

  // Stremio TV settings
  static const String _stremioTvRotationMinutesKey =
      'stremio_tv_rotation_minutes';
  static const String _stremioTvSeriesRotationMinutesKey =
      'stremio_tv_series_rotation_minutes';
  static const String _stremioTvAutoRefreshKey = 'stremio_tv_auto_refresh';
  static const String _stremioTvFavoriteChannelsKey =
      'stremio_tv_favorite_channels_v1';
  static const String _stremioTvPreferredQualityKey =
      'stremio_tv_preferred_quality';
  static const String _stremioTvDebridProviderKey =
      'stremio_tv_debrid_provider';
  static const String _stremioTvMaxStartPercentKey =
      'stremio_tv_max_start_percent';
  static const String _stremioTvRandomEpisodesKey =
      'stremio_tv_random_episodes';
  static const String _stremioTvLocalCatalogsKey =
      'stremio_tv_local_catalogs_v1';
  static const String _stremioTvCatalogRepoUrlsKey =
      'stremio_tv_catalog_repo_urls_v1';
  static const String _stremioTvHideNowPlayingKey =
      'stremio_tv_hide_now_playing';
  static const String _stremioTvTorrentsFirstKey = 'stremio_tv_torrents_first';

  /// Declared persisted names.
  static const Set<String> ownedKeys = {
    _stremioTvRotationMinutesKey,
    _stremioTvSeriesRotationMinutesKey,
    _stremioTvAutoRefreshKey,
    _stremioTvFavoriteChannelsKey,
    _stremioTvPreferredQualityKey,
    _stremioTvDebridProviderKey,
    _stremioTvMaxStartPercentKey,
    _stremioTvRandomEpisodesKey,
    _stremioTvLocalCatalogsKey,
    _stremioTvCatalogRepoUrlsKey,
    _stremioTvHideNowPlayingKey,
    _stremioTvTorrentsFirstKey,
    _stremioTvDisabledChannelFiltersKey,
  };

  // ==========================================================================
  // Stremio TV Settings
  // ==========================================================================

  /// Get the Stremio TV rotation interval in minutes (default: 90)
  static Future<int> getStremioTvRotationMinutes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvRotationMinutesKey) ?? 90;
  }

  /// Save the Stremio TV rotation interval in minutes
  static Future<void> setStremioTvRotationMinutes(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvRotationMinutesKey, value);
  }

  /// Get the Stremio TV series rotation interval in minutes (default: 45)
  static Future<int> getStremioTvSeriesRotationMinutes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvSeriesRotationMinutesKey) ?? 45;
  }

  /// Save the Stremio TV series rotation interval in minutes
  static Future<void> setStremioTvSeriesRotationMinutes(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvSeriesRotationMinutesKey, value);
  }

  /// Get whether Stremio TV picks a random episode each time (default: false)
  static Future<bool> getStremioTvRandomEpisodes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvRandomEpisodesKey) ?? false;
  }

  /// Save whether Stremio TV picks a random episode each time
  static Future<void> setStremioTvRandomEpisodes(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvRandomEpisodesKey, value);
  }

  /// Get whether Stremio TV auto-refreshes catalogs (default: true)
  static Future<bool> getStremioTvAutoRefresh() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvAutoRefreshKey) ?? true;
  }

  /// Save whether Stremio TV auto-refreshes catalogs
  static Future<void> setStremioTvAutoRefresh(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvAutoRefreshKey, value);
  }

  /// Get whether Stremio TV hides now-playing details (default: false)
  static Future<bool> getStremioTvHideNowPlaying() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvHideNowPlayingKey) ?? false;
  }

  /// Save whether Stremio TV hides now-playing details
  static Future<void> setStremioTvHideNowPlaying(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvHideNowPlayingKey, value);
  }

  static Future<bool> getStremioTvTorrentsFirst() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvTorrentsFirstKey) ?? true;
  }

  static Future<void> setStremioTvTorrentsFirst(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvTorrentsFirstKey, value);
  }

  /// Get preferred quality for Stremio TV streams (default: 'auto')
  /// Values: 'auto', '720p', '1080p', '2160p'
  static Future<String> getStremioTvPreferredQuality() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_stremioTvPreferredQualityKey) ?? 'auto';
  }

  /// Save preferred quality for Stremio TV streams
  static Future<void> setStremioTvPreferredQuality(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_stremioTvPreferredQualityKey, value);
  }

  /// Get preferred debrid provider for Stremio TV (auto = first available)
  static Future<String> getStremioTvDebridProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_stremioTvDebridProviderKey) ?? 'auto';
  }

  /// Save preferred debrid provider for Stremio TV
  static Future<void> setStremioTvDebridProvider(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_stremioTvDebridProviderKey, value);
  }

  /// Get max start position percent for Stremio TV (0 = always from beginning, -1 = no limit)
  static Future<int> getStremioTvMaxStartPercent() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvMaxStartPercentKey) ?? -1;
  }

  /// Save max start position percent for Stremio TV
  static Future<void> setStremioTvMaxStartPercent(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvMaxStartPercentKey, value);
  }

  // ==========================================================================
  // Stremio TV Channel Favorites
  // ==========================================================================

  /// Check if a Stremio TV channel is favorited
  static Future<bool> isStremioTvChannelFavorited(String channelId) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelId);
    } catch (e) {
      debugPrint('Error reading Stremio TV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a Stremio TV channel
  static Future<void> setStremioTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (isFavorited) {
      favorites[channelId] = true;
    } else {
      favorites.remove(channelId);
    }

    await prefs.setString(_stremioTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Stremio TV channel IDs
  static Future<Set<String>> getStremioTvFavoriteChannelIds() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading Stremio TV channel favorites: $e');
      return {};
    }
  }

  // ==========================================================================
  // Stremio TV Local Catalogs
  // ==========================================================================

  /// Get all locally imported catalogs for Stremio TV.
  static Future<List<Map<String, dynamic>>> getStremioTvLocalCatalogs() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvLocalCatalogsKey);
    if (json == null) return [];

    try {
      final list = await decodeJsonAsync(json) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error reading Stremio TV local catalogs: $e');
      return [];
    }
  }

  /// Save all locally imported catalogs for Stremio TV.
  static Future<void> setStremioTvLocalCatalogs(
    List<Map<String, dynamic>> catalogs,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (catalogs.isEmpty) {
      await prefs.remove(_stremioTvLocalCatalogsKey);
    } else {
      await prefs.setString(_stremioTvLocalCatalogsKey, jsonEncode(catalogs));
    }
  }

  /// Add a single local catalog. Returns false if a catalog with the same ID
  /// already exists.
  static Future<bool> addStremioTvLocalCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final existing = await getStremioTvLocalCatalogs();
    final id = catalog['id'] as String?;
    if (id == null) return false;
    if (existing.any((c) => c['id'] == id)) return false;
    existing.add(catalog);
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  /// Remove a local catalog by its ID.
  static Future<void> removeStremioTvLocalCatalog(String catalogId) async {
    final existing = await getStremioTvLocalCatalogs();
    existing.removeWhere((c) => c['id'] == catalogId);
    await setStremioTvLocalCatalogs(existing);
  }

  /// Update an existing local catalog by its ID (replaces the entry in-place).
  static Future<bool> updateStremioTvLocalCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final existing = await getStremioTvLocalCatalogs();
    final id = catalog['id'] as String?;
    if (id == null) return false;
    final idx = existing.indexWhere((c) => c['id'] == id);
    if (idx < 0) return false;
    existing[idx] = catalog;
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  // --------------------------------------------------------------------------
  // Stremio TV Catalog Repo URLs
  // --------------------------------------------------------------------------

  /// Get saved catalog repository URLs.
  static Future<List<String>> getStremioTvCatalogRepoUrls() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_stremioTvCatalogRepoUrlsKey) ?? [];
  }

  /// Set catalog repository URLs.
  static Future<void> setStremioTvCatalogRepoUrls(List<String> urls) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_stremioTvCatalogRepoUrlsKey, urls);
  }

  /// Add a catalog repository URL. Returns false if already present.
  static Future<bool> addStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    if (urls.contains(url)) return false;
    urls.add(url);
    await setStremioTvCatalogRepoUrls(urls);
    return true;
  }

  /// Remove a catalog repository URL.
  static Future<void> removeStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    urls.remove(url);
    await setStremioTvCatalogRepoUrls(urls);
  }

  // ==========================================================================
  // Stremio TV Channel Filters
  // ==========================================================================

  static const String _stremioTvDisabledChannelFiltersKey =
      'stremio_tv_disabled_channel_filters_v1';

  /// Get set of disabled channel filter IDs (addon, catalog, or genre level).
  static Future<Set<String>> getStremioTvDisabledFilters() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvDisabledChannelFiltersKey);
    if (json == null) return {};

    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading Stremio TV disabled filters: $e');
      return {};
    }
  }

  /// Save set of disabled channel filter IDs.
  static Future<void> setStremioTvDisabledFilters(Set<String> disabled) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_stremioTvDisabledChannelFiltersKey);
    } else {
      await prefs.setString(
        _stremioTvDisabledChannelFiltersKey,
        jsonEncode(disabled.toList()),
      );
    }
  }
}
