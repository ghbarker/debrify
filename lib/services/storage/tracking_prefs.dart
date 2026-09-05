import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/tracking_source.dart';
import '../hide_watched_prefs.dart';
import '../profiles/profile_credential_facade.dart';
import '../profiles/profile_preferences.dart';
import '../secret_vault.dart';
import '../tracking_scrobble_preferences.dart';
import 'home_prefs.dart';

/// Tracking source policy, catalog-sync switches, and Trakt / Simkl / MDBList
/// credentials. [StorageService] forwards to this store.
///
/// Key names and encodings are frozen; do not rename a persisted string.
/// [homeTickSourcesKey] stays on [HomePrefs]; this store only bumps
/// [trackingSourceRevision] after that write.
class TrackingPrefs {
  TrackingPrefs._();

  static const String trackingScrobbleTargetsKey =
      TrackingScrobblePreferences.key;
  static const String watchProgressSourceKey = 'watch_progress_source';
  static const String trackingProgressFallbackNoticeKey =
      'tracking_progress_fallback_notice';
  static const String traktSyncCatalogItemsKey = 'trakt_sync_catalog_items';
  static const String simklSyncCatalogItemsKey = 'simkl_sync_catalog_items';
  static const String mdblistSyncCatalogItemsKey = 'mdblist_sync_catalog_items';

  // Trakt settings
  static const String traktAccessTokenKey = 'trakt_access_token';
  static const String traktRefreshTokenKey = 'trakt_refresh_token';
  static const String traktUsernameKey = 'trakt_username';
  static const String traktTokenExpiryKey = 'trakt_token_expiry';

  // Simkl settings. No refresh-token/expiry keys — PIN-issued Simkl tokens
  // don't expire (see SimklService).
  static const String simklAccessTokenKey = 'simkl_access_token';
  static const String simklUsernameKey = 'simkl_username';

  // MDBList settings. Auth is a single API key (from mdblist.com/preferences),
  // so there's no token/expiry — just the key and a cached display username.
  static const String mdblistApiKeyKey = 'mdblist_api_key';
  static const String mdblistUsernameKey = 'mdblist_username';

  // Maps a source MDBList list id -> the id of the static list we CLONED it
  // into on the user's account (the "Save" action). Lets the Save button know a
  // list is already saved and which clone to delete on un-save. JSON object of
  // {"<sourceId>": clonedId}.
  static const String mdblistSavedClonesKey = 'mdblist_saved_clones';
  static const String mdblistSyncCheckpointKey = 'mdblist_sync_checkpoint_v1';

  static const Set<String> ownedKeys = {
    trackingScrobbleTargetsKey,
    watchProgressSourceKey,
    trackingProgressFallbackNoticeKey,
    traktSyncCatalogItemsKey,
    simklSyncCatalogItemsKey,
    mdblistSyncCatalogItemsKey,
    traktAccessTokenKey,
    traktRefreshTokenKey,
    traktUsernameKey,
    traktTokenExpiryKey,
    simklAccessTokenKey,
    simklUsernameKey,
    mdblistApiKeyKey,
    mdblistUsernameKey,
    mdblistSavedClonesKey,
    mdblistSyncCheckpointKey,
  };

  /// Invalidates policy consumers that keep an in-memory snapshot.
  static final ValueNotifier<int> trackingSourceRevision = ValueNotifier(0);

  static Future<bool> _credentialConfigured(
    String key,
    Future<String?> Function() legacyRead,
  ) async {
    final presence = await ProfileCredentialFacade.isConfigured(key);
    if (presence.handled) return presence.configured;
    final value = await legacyRead();
    return value != null && value.isNotEmpty;
  }

  /// Reads the new master scrobble switches. On first read, adopt the retired
  /// per-tracker catalog switches once. An absent legacy value means ON: that
  /// matches interactive connection and old Trakt/Simkl restore behavior.
  static Future<Set<TrackingSource>> getTrackingScrobbleTargets() =>
      TrackingScrobblePreferences.readCurrent();

  static Future<void> setTrackingScrobbleTargets(
    Set<TrackingSource> value,
  ) async {
    await TrackingScrobblePreferences.writeCurrent(value);
    trackingSourceRevision.value++;
  }

  /// Turns on scrobbling for a newly connected tracker without disturbing the
  /// user's choices for any other tracker. Connection flows call this after
  /// authentication succeeds so reconnecting restores the provider's default
  /// ON state even when it had previously been unticked.
  static Future<void> enableTrackingScrobbleTarget(
    TrackingSource source,
  ) async {
    final changed = await TrackingScrobblePreferences.enableCurrent(source);
    if (changed) trackingSourceRevision.value++;
  }

  static Future<WatchProgressSource> getWatchProgressSource() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getString(watchProgressSourceKey);
    return WatchProgressSource.values.firstWhere(
      (source) => source.name == stored,
      orElse: () => WatchProgressSource.smart,
    );
  }

  static Future<void> setWatchProgressSource(WatchProgressSource value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(watchProgressSourceKey, value.name);
    trackingSourceRevision.value++;
  }

  static Future<bool> fallbackDisconnectedProgressSource(
    TrackingSource disconnected,
  ) async {
    final current = await getWatchProgressSource();
    final owns = switch (current) {
      WatchProgressSource.trakt => disconnected == TrackingSource.trakt,
      WatchProgressSource.simkl => disconnected == TrackingSource.simkl,
      WatchProgressSource.mdblist => disconnected == TrackingSource.mdblist,
      _ => false,
    };
    if (!owns) return false;
    await setWatchProgressSource(WatchProgressSource.smart);
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(trackingProgressFallbackNoticeKey, true);
    return true;
  }

  static Future<bool> takeTrackingProgressFallbackNotice() async {
    final prefs = await ProfilePreferences.instance();
    final pending = prefs.getBool(trackingProgressFallbackNoticeKey) ?? false;
    if (pending) await prefs.remove(trackingProgressFallbackNoticeKey);
    return pending;
  }

  static Future<Set<TrackingSource>> getHomeTickSources() =>
      HomePrefs.getHomeTickSources();

  static Future<void> setHomeTickSources(Set<TrackingSource> value) async {
    await HomePrefs.setHomeTickSources(value);
    trackingSourceRevision.value++;
  }

  static Future<Map<String, dynamic>> buildTrackingPreferencesPayload() async {
    final scrobble = await getTrackingScrobbleTargets();
    final progress = await getWatchProgressSource();
    final ticks = await getHomeTickSources();
    return <String, dynamic>{
      'scrobble_targets': scrobble
          .map((source) => source.storageName)
          .toList(growable: false),
      'progress_source': progress.name,
      'home_tick_sources': ticks
          .map((source) => source.storageName)
          .toList(growable: false),
      'hide_watched': await HideWatchedPrefs.read(),
    };
  }

  /// Re-adopts the legacy per-tracker switches after restoring an OLD backup
  /// with no tracking payload. The masters were already seeded on first policy
  /// read at app start, so without this the restored legacy values — notably an
  /// MDBList sync-catalog OFF — would be silently ignored.
  static Future<void> reseedTrackingScrobbleTargetsFromLegacy() async {
    await TrackingScrobblePreferences.reseedCurrentFromLegacy();
    trackingSourceRevision.value++;
  }

  /// Applies only explicitly present new-format preferences. Old backups omit
  /// this object; [reseedTrackingScrobbleTargetsFromLegacy] runs on that
  /// restore path instead so the restored legacy switches are re-adopted by
  /// [getTrackingScrobbleTargets], preserving the absent-key migration rule.
  static Future<void> applyTrackingPreferencesPayload(
    Map<dynamic, dynamic> payload,
  ) async {
    final scrobble = payload['scrobble_targets'];
    if (scrobble is List) {
      await setTrackingScrobbleTargets(<TrackingSource>{
        for (final value in scrobble.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final progress = payload['progress_source'];
    if (progress is String) {
      final parsed = WatchProgressSource.values
          .where((source) => source.name == progress)
          .firstOrNull;
      if (parsed != null) await setWatchProgressSource(parsed);
    }
    final ticks = payload['home_tick_sources'];
    if (ticks is List) {
      await setHomeTickSources(<TrackingSource>{
        for (final value in ticks.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final hideWatched = payload['hide_watched'];
    if (hideWatched is bool) await HideWatchedPrefs.setEnabled(hideWatched);
  }

  static Future<bool> getTraktSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(traktSyncCatalogItemsKey) ?? false;
  }

  static Future<void> setTraktSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(traktSyncCatalogItemsKey, value);
  }

  static Future<String?> getTraktAccessToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        traktAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, traktAccessTokenKey);
  }

  static Future<bool> hasTraktCredential() =>
      _credentialConfigured(traktAccessTokenKey, () => getTraktAccessToken());

  static Future<void> setTraktAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, traktAccessTokenKey, token);
  }

  static Future<String?> getTraktRefreshToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        traktRefreshTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, traktRefreshTokenKey);
  }

  static Future<void> setTraktRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, traktRefreshTokenKey, token);
  }

  static Future<String?> getTraktUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(traktUsernameKey);
  }

  static Future<void> setTraktUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(traktUsernameKey, username);
  }

  static Future<int?> getTraktTokenExpiry() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(traktTokenExpiryKey);
  }

  static Future<void> setTraktTokenExpiry(int expiryMs) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(traktTokenExpiryKey, expiryMs);
  }

  /// Clears the local Trakt connection first and reports whether this profile
  /// was its unshared owner. Only that disposition may revoke the upstream
  /// token; a borrower must never invalidate the account for other profiles.
  static Future<bool> clearTraktAuth() async {
    final prefs = await ProfilePreferences.instance();
    final disposition = await ProfileCredentialFacade.disconnectWithDisposition(
      traktAccessTokenKey,
    );
    if (!disposition.handled) {
      await prefs.remove(traktAccessTokenKey);
      await prefs.remove(traktRefreshTokenKey);
    }
    await prefs.remove(traktUsernameKey);
    await prefs.remove(traktTokenExpiryKey);
    await fallbackDisconnectedProgressSource(TrackingSource.trakt);
    return !disposition.handled || disposition.shouldRevokeRemote;
  }

  static Future<void> setSimklSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(simklSyncCatalogItemsKey, value);
  }

  static Future<bool> getSimklSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(simklSyncCatalogItemsKey) ?? false;
  }

  static Future<void> setMdblistSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(mdblistSyncCatalogItemsKey, value);
  }

  static Future<bool> getMdblistSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(mdblistSyncCatalogItemsKey) ?? false;
  }

  static Future<String?> getSimklAccessToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        simklAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, simklAccessTokenKey);
  }

  static Future<bool> hasSimklCredential() =>
      _credentialConfigured(simklAccessTokenKey, () => getSimklAccessToken());

  static Future<void> setSimklAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, simklAccessTokenKey, token);
  }

  static Future<String?> getSimklUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(simklUsernameKey);
  }

  static Future<void> setSimklUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(simklUsernameKey, username);
  }

  static Future<void> clearSimklAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(simklAccessTokenKey)) {
      await prefs.remove(simklAccessTokenKey);
    }
    await prefs.remove(simklUsernameKey);
    await fallbackDisconnectedProgressSource(TrackingSource.simkl);
  }

  static Future<String?> getMdblistApiKey({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        mdblistApiKeyKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, mdblistApiKeyKey);
  }

  static Future<bool> hasMdblistCredential() =>
      _credentialConfigured(mdblistApiKeyKey, () => getMdblistApiKey());

  static Future<void> saveMdblistApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, mdblistApiKeyKey, apiKey);
  }

  static Future<String?> getMdblistUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(mdblistUsernameKey);
  }

  static Future<void> setMdblistUsername(String? username) async {
    final prefs = await ProfilePreferences.instance();
    if (username == null || username.isEmpty) {
      await prefs.remove(mdblistUsernameKey);
    } else {
      await prefs.setString(mdblistUsernameKey, username);
    }
  }

  /// Clears all stored MDBList auth (key + cached username).
  static Future<void> clearMdblistAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(mdblistApiKeyKey)) {
      await prefs.remove(mdblistApiKeyKey);
    }
    await prefs.remove(mdblistUsernameKey);
    await prefs.remove(mdblistSavedClonesKey);
    await prefs.remove(mdblistSyncCheckpointKey);
    await fallbackDisconnectedProgressSource(TrackingSource.mdblist);
  }

  static Future<Map<int, int>> getMdblistSavedClones() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(mdblistSavedClonesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, int>{};
      decoded.forEach((k, v) {
        final sid = int.tryParse(k.toString());
        final cid = v is int ? v : (v is num ? v.toInt() : null);
        if (sid != null && cid != null) out[sid] = cid;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> setMdblistSavedClone(int sourceId, int clonedId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map[sourceId] = clonedId;
    await prefs.setString(
      mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  static Future<void> removeMdblistSavedClone(int sourceId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map.remove(sourceId);
    await prefs.setString(
      mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  /// Retire the old clone-as-like UI bookkeeping. Remote lists are deliberately
  /// untouched: an old clone is now simply a normal user-owned list.
  static Future<void> retireMdblistSavedCloneMarkers() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(mdblistSavedClonesKey);
  }

  static Future<Map<String, dynamic>?> getMdblistSyncCheckpoint() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(mdblistSyncCheckpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setMdblistSyncCheckpoint(
    Map<String, dynamic>? value,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(mdblistSyncCheckpointKey);
    } else {
      await prefs.setString(mdblistSyncCheckpointKey, jsonEncode(value));
    }
  }
}
