import 'dart:convert';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/webdav_item.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/profile_collection_resource_facade.dart';
import '../profiles/profile_credential_facade.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_runtime.dart';
import '../secret_vault.dart';
import 'cloud_secret_prefs.dart';

/// Provider-credential *settings*: integration toggles, hidden-from-nav,
/// post-torrent / file-selection precedence, RD endpoint, PikPak session
/// and folder prefs, and WebDAV connections.
///
/// CloudSecretPrefs already owns RD/TB/PM/AD/PikPak secret keys — those
/// strings are not redeclared here. [StorageService] forwards to this
/// store. Key names and encodings are frozen; do not rename a persisted
/// string.
class ProviderCredentialPrefs {
  ProviderCredentialPrefs._();

  static const String _rdEndpointKey = 'real_debrid_endpoint';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  static const String _torboxCacheCheckPref =
      'torbox_check_cache_before_search';
  static const String _realDebridIntegrationEnabledKey =
      'real_debrid_integration_enabled';
  static const String _realDebridHiddenFromNavKey =
      'real_debrid_hidden_from_nav';
  static const String _rdSkipBlockedTorrentsKey = 'rd_skip_blocked_torrents';
  static const String _torboxIntegrationEnabledKey =
      'torbox_integration_enabled';
  static const String _torboxHiddenFromNavKey = 'torbox_hidden_from_nav';
  static const String _premiumizeIntegrationEnabledKey =
      'premiumize_integration_enabled';
  static const String _premiumizePostTorrentActionKey =
      'premiumize_post_torrent_action';
  static const String _premiumizeCacheCheckPref =
      'premiumize_check_cache_before_search';
  static const String _premiumizeHiddenFromNavKey =
      'premiumize_hidden_from_nav';
  static const String _allDebridIntegrationEnabledKey =
      'alldebrid_integration_enabled';
  static const String _allDebridPostTorrentActionKey =
      'alldebrid_post_torrent_action';
  static const String _allDebridHiddenFromNavKey = 'alldebrid_hidden_from_nav';
  static const String _pikpakHiddenFromNavKey = 'pikpak_hidden_from_nav';
  static const String _postTorrentActionKey = 'post_torrent_action';
  static const String _torboxPostTorrentActionKey =
      'torbox_post_torrent_action';
  static const String _pikpakPostTorrentActionKey =
      'pikpak_post_torrent_action';
  static const String _pikpakEnabledKey = 'pikpak_enabled';
  static const String _pikpakAccessTokenKey = 'pikpak_access_token';
  static const String _pikpakRefreshTokenKey = 'pikpak_refresh_token';
  static const String _pikpakDeviceIdKey = 'pikpak_device_id';
  static const String _pikpakCaptchaTokenKey = 'pikpak_captcha_token';
  static const String _pikpakUserIdKey = 'pikpak_user_id';
  static const String _pikpakShowVideosOnlyKey = 'pikpak_show_videos_only';
  static const String _pikpakIgnoreSmallVideosKey =
      'pikpak_ignore_small_videos';
  static const String _pikpakRestrictedFolderIdKey =
      'pikpak_restricted_folder_id';
  static const String _pikpakRestrictedFolderNameKey =
      'pikpak_restricted_folder_name';
  static const String _pikpakTorrentsFolderIdKey = 'pikpak_torrents_folder_id';
  static const String _pikpakTvFolderIdKey = 'pikpak_tv_folder_id';
  static const String _webDavEnabledKey = 'webdav_enabled';
  static const String _webDavHiddenFromNavKey = 'webdav_hidden_from_nav';
  static const String _webDavBaseUrlKey = 'webdav_base_url';
  static const String _webDavUsernameKey = 'webdav_username';
  static const String _webDavPasswordKey = 'webdav_password';
  static const String _webDavShowVideosOnlyKey = 'webdav_show_videos_only';
  static const String _webDavServersKey = 'webdav_servers_v1';
  static const String _webDavSelectedServerIdKey =
      'webdav_selected_server_id_v1';
  static const String _defaultTorrentProviderKey =
      'default_torrent_provider_v1';

  /// Declared persisted names. Secret key *strings* stay on CloudSecretPrefs.
  static const Set<String> ownedKeys = {
    _rdEndpointKey,
    _fileSelectionKey,
    _torboxCacheCheckPref,
    _realDebridIntegrationEnabledKey,
    _realDebridHiddenFromNavKey,
    _rdSkipBlockedTorrentsKey,
    _torboxIntegrationEnabledKey,
    _torboxHiddenFromNavKey,
    _premiumizeIntegrationEnabledKey,
    _premiumizePostTorrentActionKey,
    _premiumizeCacheCheckPref,
    _premiumizeHiddenFromNavKey,
    _allDebridIntegrationEnabledKey,
    _allDebridPostTorrentActionKey,
    _allDebridHiddenFromNavKey,
    _pikpakHiddenFromNavKey,
    _postTorrentActionKey,
    _torboxPostTorrentActionKey,
    _pikpakPostTorrentActionKey,
    _pikpakEnabledKey,
    _pikpakAccessTokenKey,
    _pikpakRefreshTokenKey,
    _pikpakDeviceIdKey,
    _pikpakCaptchaTokenKey,
    _pikpakUserIdKey,
    _pikpakShowVideosOnlyKey,
    _pikpakIgnoreSmallVideosKey,
    _pikpakRestrictedFolderIdKey,
    _pikpakRestrictedFolderNameKey,
    _pikpakTorrentsFolderIdKey,
    _pikpakTvFolderIdKey,
    _webDavEnabledKey,
    _webDavHiddenFromNavKey,
    _webDavBaseUrlKey,
    _webDavUsernameKey,
    _webDavPasswordKey,
    _webDavShowVideosOnlyKey,
    _webDavServersKey,
    _webDavSelectedServerIdKey,
    _defaultTorrentProviderKey,
  };

  // Real-Debrid endpoint preference (for fallback to backup endpoint)
  static Future<String> getRdEndpoint() async {
    final prefs = await ProfilePreferences.instance();
    // Default to primary endpoint
    return prefs.getString(_rdEndpointKey) ??
        'https://api.real-debrid.com/rest/1.0';
  }

  static Future<void> saveRdEndpoint(String endpoint) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_rdEndpointKey, endpoint);
  }

  static Future<void> deleteRdEndpoint() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_rdEndpointKey);
  }

  static Future<bool> getTorboxCacheCheckEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxCacheCheckPref) ?? false;
  }

  static Future<void> setTorboxCacheCheckEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxCacheCheckPref, enabled);
  }

  static Future<bool> getRealDebridIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_realDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setRealDebridIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_realDebridIntegrationEnabledKey, enabled);
  }

  static Future<bool> getRealDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_realDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setRealDebridHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_realDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearRealDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_realDebridHiddenFromNavKey);
  }

  static Future<bool> getRdSkipBlockedTorrents() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_rdSkipBlockedTorrentsKey) ?? true;
  }

  static Future<void> setRdSkipBlockedTorrents(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_rdSkipBlockedTorrentsKey, enabled);
  }

  static Future<bool> getTorboxIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxIntegrationEnabledKey) ?? true;
  }

  static Future<void> setTorboxIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxIntegrationEnabledKey, enabled);
  }

  static Future<bool> getTorboxHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxHiddenFromNavKey) ?? false;
  }

  static Future<void> setTorboxHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxHiddenFromNavKey, hidden);
  }

  static Future<void> clearTorboxHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_torboxHiddenFromNavKey);
  }

  static Future<bool> getPremiumizeIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeIntegrationEnabledKey) ?? true;
  }

  static Future<void> setPremiumizeIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeIntegrationEnabledKey, enabled);
  }

  static Future<bool> getPremiumizeHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeHiddenFromNavKey) ?? false;
  }

  static Future<void> setPremiumizeHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeHiddenFromNavKey, hidden);
  }

  static Future<void> clearPremiumizeHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_premiumizeHiddenFromNavKey);
  }

  static Future<bool> getAllDebridIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_allDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setAllDebridIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_allDebridIntegrationEnabledKey, enabled);
  }

  // AllDebrid post-torrent action methods
  static Future<String> getAllDebridPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_allDebridPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveAllDebridPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_allDebridPostTorrentActionKey, action);
  }

  // AllDebrid hide-from-navigation
  static Future<bool> getAllDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_allDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setAllDebridHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_allDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearAllDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_allDebridHiddenFromNavKey);
  }

  // File Selection methods
  static Future<String> getFileSelection() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_fileSelectionKey) ??
        'smart'; // Default to smart selection
  }

  static Future<void> saveFileSelection(String selection) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_fileSelectionKey, selection);
  }

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_postTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_postTorrentActionKey, action);
  }

  // TorBox post-torrent action methods
  static Future<String> getTorboxPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_torboxPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveTorboxPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_torboxPostTorrentActionKey, action);
  }

  // PikPak post-torrent action methods
  static Future<String> getPikPakPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePikPakPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakPostTorrentActionKey, action);
  }

  // Premiumize post-torrent action methods
  static Future<String> getPremiumizePostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_premiumizePostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePremiumizePostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_premiumizePostTorrentActionKey, action);
  }

  static Future<bool> getPremiumizeCacheCheckEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeCacheCheckPref) ?? false;
  }

  static Future<void> setPremiumizeCacheCheckEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeCacheCheckPref, enabled);
  }

  /// Clear integration enabled states (RD, TorBox)
  static Future<void> clearAllIntegrationStates() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_realDebridIntegrationEnabledKey);
    await prefs.remove(_realDebridHiddenFromNavKey);
    await prefs.remove(_torboxIntegrationEnabledKey);
    await prefs.remove(_torboxHiddenFromNavKey);
    await prefs.remove(_premiumizeIntegrationEnabledKey);
    await prefs.remove(_premiumizeHiddenFromNavKey);
    await prefs.remove(_allDebridIntegrationEnabledKey);
    await prefs.remove(_allDebridHiddenFromNavKey);
    await prefs.remove(_webDavEnabledKey);
    await prefs.remove(_webDavHiddenFromNavKey);
  }

  /// Clear post-torrent action preferences
  static Future<void> clearAllPostTorrentActions() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_postTorrentActionKey);
    await prefs.remove(_torboxPostTorrentActionKey);
    await prefs.remove(_pikpakPostTorrentActionKey);
    await prefs.remove(_premiumizePostTorrentActionKey);
    await prefs.remove(_allDebridPostTorrentActionKey);
  }

  // PikPak API Settings
  static Future<bool> getPikPakEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakEnabledKey) ?? false;
  }

  static Future<void> setPikPakEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakEnabledKey, value);
  }

  static Future<String?> getPikPakAccessToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakAccessTokenKey);
  }

  static Future<void> setPikPakAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakAccessTokenKey, token);
  }

  static Future<String?> getPikPakRefreshToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakRefreshTokenKey);
  }

  static Future<void> setPikPakRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakRefreshTokenKey, token);
  }

  static Future<void> clearPikPakAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(
      CloudSecretPrefs.pikpakEmail,
    )) {
      await prefs.remove(CloudSecretPrefs.pikpakEmail);
      await prefs.remove(CloudSecretPrefs.pikpakPassword);
      await prefs.remove(_pikpakAccessTokenKey);
      await prefs.remove(_pikpakRefreshTokenKey);
      await prefs.remove(_pikpakDeviceIdKey);
      await prefs.remove(_pikpakCaptchaTokenKey);
      await prefs.remove(_pikpakUserIdKey);
    }
    await prefs.setBool(_pikpakEnabledKey, false);

    // Also clear restricted folder settings and cached subfolder IDs
    await clearPikPakRestrictedFolder();
    await clearPikPakSubfolderCaches();
    await clearPikPakHiddenFromNav();
  }

  // PikPak Device ID and Captcha Token
  static Future<void> setPikPakDeviceId(String deviceId) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakDeviceIdKey, deviceId);
  }

  static Future<String?> getPikPakDeviceId() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakDeviceIdKey);
  }

  static Future<void> deletePikPakDeviceId() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakDeviceIdKey);
  }

  static Future<void> setPikPakCaptchaToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakCaptchaTokenKey, token);
  }

  static Future<String?> getPikPakCaptchaToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakCaptchaTokenKey);
  }

  static Future<void> clearPikPakCaptchaToken() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakCaptchaTokenKey);
  }

  static Future<void> setPikPakUserId(String userId) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakUserIdKey, userId);
  }

  static Future<String?> getPikPakUserId() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakUserIdKey);
  }

  // PikPak Show Videos Only
  static Future<bool> getPikPakShowVideosOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakShowVideosOnlyKey) ?? true; // Default to true
  }

  static Future<void> setPikPakShowVideosOnly(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakShowVideosOnlyKey, value);
  }

  // PikPak Ignore Small Videos (under 100MB)
  static Future<bool> getPikPakIgnoreSmallVideos() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakIgnoreSmallVideosKey) ??
        true; // Default to true
  }

  static Future<void> setPikPakIgnoreSmallVideos(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakIgnoreSmallVideosKey, value);
  }

  // PikPak Restricted Folder
  static Future<String?> getPikPakRestrictedFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakRestrictedFolderIdKey);
  }

  static Future<String?> getPikPakRestrictedFolderName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakRestrictedFolderNameKey);
  }

  static Future<void> setPikPakRestrictedFolder(
    String? folderId,
    String? folderName,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (folderId == null) {
      await prefs.remove(_pikpakRestrictedFolderIdKey);
      await prefs.remove(_pikpakRestrictedFolderNameKey);
    } else {
      await prefs.setString(_pikpakRestrictedFolderIdKey, folderId);
      if (folderName != null) {
        await prefs.setString(_pikpakRestrictedFolderNameKey, folderName);
      }
    }
  }

  static Future<void> clearPikPakRestrictedFolder() async {
    await setPikPakRestrictedFolder(null, null);
    // Also clear subfolder caches when restriction changes
    await clearPikPakSubfolderCaches();
  }

  // PikPak Subfolder ID caching (for debrify-torrents and debrify-tv folders)
  static Future<String?> getPikPakTorrentsFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakTorrentsFolderIdKey);
  }

  static Future<void> setPikPakTorrentsFolderId(String folderId) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakTorrentsFolderIdKey, folderId);
  }

  static Future<String?> getPikPakTvFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakTvFolderIdKey);
  }

  static Future<void> setPikPakTvFolderId(String folderId) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakTvFolderIdKey, folderId);
  }

  static Future<void> clearPikPakSubfolderCaches() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakTorrentsFolderIdKey);
    await prefs.remove(_pikpakTvFolderIdKey);
  }

  // PikPak Hidden from Navigation
  static Future<bool> getPikPakHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakHiddenFromNavKey) ?? false;
  }

  static Future<void> setPikPakHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakHiddenFromNavKey, hidden);
  }

  static Future<void> clearPikPakHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakHiddenFromNavKey);
  }

  // WebDAV Settings
  static Future<bool> getWebDavEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavEnabledKey) ?? false;
  }

  static Future<void> setWebDavEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavEnabledKey, value);
  }

  static Future<bool> getWebDavHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavHiddenFromNavKey) ?? false;
  }

  static Future<void> setWebDavHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavHiddenFromNavKey, hidden);
  }

  static Future<void> clearWebDavHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_webDavHiddenFromNavKey);
  }

  static Future<String?> getWebDavBaseUrl() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await getSelectedWebDavServer();
    return selected?.baseUrl ??
        await SecretVault.getString(prefs, _webDavBaseUrlKey);
  }

  static Future<void> setWebDavBaseUrl(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await getWebDavServers(forSettings: false);
        await saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: value,
                    username: item.username,
                    password: item.password,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _webDavBaseUrlKey, value);
  }

  static Future<String?> getWebDavUsername() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await getSelectedWebDavServer();
    return selected?.username ??
        await SecretVault.getString(prefs, _webDavUsernameKey);
  }

  static Future<void> setWebDavUsername(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await getWebDavServers(forSettings: false);
        await saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: item.baseUrl,
                    username: value,
                    password: item.password,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _webDavUsernameKey, value);
  }

  static Future<String?> getWebDavPassword() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await getSelectedWebDavServer();
    return selected?.password ??
        await SecretVault.getString(prefs, _webDavPasswordKey);
  }

  static Future<void> setWebDavPassword(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await getWebDavServers(forSettings: false);
        await saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: item.baseUrl,
                    username: item.username,
                    password: value,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _webDavPasswordKey, value);
  }

  static Future<bool> getWebDavShowVideosOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavShowVideosOnlyKey) ?? true;
  }

  static Future<void> setWebDavShowVideosOnly(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavShowVideosOnlyKey, value);
  }

  static Future<void> clearWebDav() async {
    if (ProfileCollectionResourceFacade.active) {
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
        items: const <ResourceCollectionItem>[],
      );
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_webDavBaseUrlKey);
    await prefs.remove(_webDavUsernameKey);
    await prefs.remove(_webDavPasswordKey);
    await prefs.remove(_webDavHiddenFromNavKey);
    await prefs.remove(_webDavServersKey);
    await prefs.remove(_webDavSelectedServerIdKey);
    await prefs.setBool(_webDavEnabledKey, false);
  }

  static Future<List<WebDavConfig>> getWebDavServers({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows
          .map(WebDavConfig.fromJson)
          .where(
            (config) =>
                config.baseUrl.trim().isNotEmpty || config.credentialsRedacted,
          )
          .toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _webDavServersKey);
    final servers = <WebDavConfig>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final config = WebDavConfig.fromJson(
                item.cast<String, dynamic>(),
              );
              if (config.baseUrl.trim().isNotEmpty) servers.add(config);
            }
          }
        }
      } catch (_) {}
    }

    if (servers.isEmpty) {
      final legacyUrl = await SecretVault.getString(prefs, _webDavBaseUrlKey);
      if (legacyUrl != null && legacyUrl.trim().isNotEmpty) {
        final config = WebDavConfig(
          id: 'legacy-${legacyUrl.hashCode}',
          name: Uri.tryParse(legacyUrl)?.host ?? 'WebDAV',
          baseUrl: legacyUrl,
          username:
              await SecretVault.getString(prefs, _webDavUsernameKey) ?? '',
          password:
              await SecretVault.getString(prefs, _webDavPasswordKey) ?? '',
        );
        servers.add(config);
        await saveWebDavServers(servers);
        await setSelectedWebDavServerId(config.id);
      }
    }

    return servers;
  }

  static Future<List<WebDavConfig>> saveWebDavServers(
    List<WebDavConfig> servers,
  ) async {
    if (ProfileCollectionResourceFacade.active) {
      final expectedScope = ProfileRuntime.scope.value;
      if (expectedScope == null) throw StateError('No visible profile scope');
      // Capture the preference namespace before the registry mutation. If a
      // profile switch races this operation, this handle can only write the
      // initiating namespace (or fail); it can never write the new profile.
      final prefs = await ProfilePreferences.instance();
      final rows = await ProfileCollectionResourceFacade.replaceAndRead(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
        items: <ResourceCollectionItem>[
          for (final server in servers)
            ResourceCollectionItem(
              type: ConnectionResourceType.webDav,
              label: server.name,
              publicConfig: <String, dynamic>{'accountLabel': server.name},
              secretConfig: server.toJson(),
              sourceResourceId: server.connectionResourceId,
            ),
        ],
        forSettings: true,
      );
      final saved = rows.map(WebDavConfig.fromJson).toList(growable: false);
      if (ProfileRuntime.scope.value != expectedScope) {
        throw StateError('Profile changed while saving WebDAV connections');
      }
      await prefs.setBool(_webDavEnabledKey, saved.isNotEmpty);
      if (ProfileRuntime.scope.value != expectedScope) {
        throw StateError('Profile changed while saving WebDAV settings');
      }
      return saved;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(
      prefs,
      _webDavServersKey,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
    await prefs.setBool(_webDavEnabledKey, servers.isNotEmpty);
    return List<WebDavConfig>.unmodifiable(servers);
  }

  static Future<String?> getSelectedWebDavServerId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_webDavSelectedServerIdKey);
  }

  static Future<void> setSelectedWebDavServerId(String? id) async {
    final prefs = await ProfilePreferences.instance();
    if (id == null || id.isEmpty) {
      await prefs.remove(_webDavSelectedServerIdKey);
    } else {
      await prefs.setString(_webDavSelectedServerIdKey, id);
    }
  }

  static Future<WebDavConfig?> getSelectedWebDavServer({
    bool forSettings = true,
  }) async {
    final servers = await getWebDavServers(forSettings: forSettings);
    if (servers.isEmpty) return null;
    final selectedId = await getSelectedWebDavServerId();
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final server in servers) {
        if (server.id == selectedId) return server;
      }
    }
    await setSelectedWebDavServerId(servers.first.id);
    return servers.first;
  }

  static Future<WebDavConfig> upsertWebDavServer(WebDavConfig config) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    final selectionPrefs = await ProfilePreferences.instance();
    final servers = (await getWebDavServers()).toList();
    final priorResourceIds = <String>{
      for (final server in servers)
        if (server.connectionResourceId != null) server.connectionResourceId!,
    };
    final index = servers.indexWhere((server) => server.id == config.id);
    var persisted = config;
    if (index == -1) {
      servers.add(persisted);
    } else {
      final source = servers[index];
      if (source.connectionReadOnly) {
        throw const ResourceAuthorizationException(
          'Shared WebDAV connections cannot be edited',
        );
      }
      persisted = WebDavConfig(
        id: config.id,
        name: config.name,
        baseUrl: config.baseUrl,
        username: config.username,
        password: config.password,
        connectionResourceId: source.connectionResourceId,
        connectionResourceRevision: source.connectionResourceRevision,
      );
      servers[index] = persisted;
    }
    final saved = await saveWebDavServers(servers);
    final WebDavConfig canonical;
    final sourceResourceId = persisted.connectionResourceId;
    if (sourceResourceId != null) {
      canonical = saved.singleWhere(
        (server) => server.connectionResourceId == sourceResourceId,
      );
    } else if (ProfileCollectionResourceFacade.active) {
      canonical = saved.singleWhere(
        (server) =>
            server.connectionResourceId != null &&
            !priorResourceIds.contains(server.connectionResourceId),
      );
    } else {
      canonical = saved.singleWhere((server) => server.id == persisted.id);
    }
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while selecting a WebDAV connection');
    }
    await selectionPrefs.setString(_webDavSelectedServerIdKey, canonical.id);
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while selecting a WebDAV connection');
    }
    return canonical;
  }

  static Future<void> deleteWebDavServer(String id) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    final selectionPrefs = await ProfilePreferences.instance();
    final servers = (await getWebDavServers()).toList();
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while deleting a WebDAV connection');
    }
    servers.removeWhere((server) => server.id == id);
    final saved = await saveWebDavServers(servers);
    final selected = selectionPrefs.getString(_webDavSelectedServerIdKey);
    if (selected == id) {
      if (saved.isEmpty) {
        await selectionPrefs.remove(_webDavSelectedServerIdKey);
      } else {
        await selectionPrefs.setString(
          _webDavSelectedServerIdKey,
          saved.first.id,
        );
      }
    }
    if (saved.isEmpty) {
      await selectionPrefs.setBool(_webDavHiddenFromNavKey, false);
    }
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while deleting a WebDAV connection');
    }
  }

  // Default Torrent Provider methods
  // Returns: 'none' (ask every time), 'torbox', 'debrid', or 'pikpak'
  static Future<String> getDefaultTorrentProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_defaultTorrentProviderKey) ?? 'none';
  }

  static Future<void> setDefaultTorrentProvider(String provider) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultTorrentProviderKey, provider);
  }

  static Future<void> clearDefaultTorrentProvider() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultTorrentProviderKey);
  }
}
