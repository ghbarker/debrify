import 'dart:io';

import 'package:debrify/services/storage/cloud_secret_prefs.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/storage_key_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

/// Value-only consts on StorageService that are not persisted key names.
const notPersistedValueConsts = {
  'skipSegmentProviderAuto',
  'skipSegmentProviderSkipDb',
  'skipSegmentProviderIntroDb',
  'skipSegmentProviderTheIntroDb',
  'kDetailPageStyleDefault',
  'discoverDefaultRememberLast',
  'startupIptvModeLast',
  'startupIptvModePinned',
  'startupIptvFirstAvailable',
  'iptvFavoritesListId',
};

/// JSON object field names inside persisted blobs — not SharedPreferences keys.
const jsonPayloadFields = {
  'finishedEpisodes',
  'seasons',
  'trackPreferences',
};

/// Interpolated names from `_ambientTrailerKeyFor` (detail surface). The
/// Home-hero pair is already a HomePrefs const; these two have no `_…Key`.
const interpolatedPrefsKeys = {
  'detail_trailer_audio_enabled',
  'detail_trailer_volume',
};

const _aliases = {
  'CloudSecretPrefs.torboxApiKey': CloudSecretPrefs.torboxApiKey,
  'CloudSecretPrefs.premiumizeApiKey': CloudSecretPrefs.premiumizeApiKey,
  'CloudSecretPrefs.allDebridApiKey': CloudSecretPrefs.allDebridApiKey,
  'CloudSecretPrefs.pikpakEmail': CloudSecretPrefs.pikpakEmail,
  'CloudSecretPrefs.pikpakPassword': CloudSecretPrefs.pikpakPassword,
  'TrackingScrobblePreferences.key': 'tracking_scrobble_targets',
  'TvOsRecoveryLimits.myWatchlistPreferenceKey': 'my_watchlist_v1',
};

final _storageConstRe = RegExp(
  r'static const String (\w+)\s*=\s*(.*?);',
  dotAll: true,
);

final _secretConstRe = RegExp(r"static const (\w+) = '([^']+)';");

/// `prefs.getBool('foo')` / `setInt('foo')` / `remove('foo')` / `key == 'foo'`.
final _inlinePrefsKeyRe = RegExp(
  r"(?:getBool|setBool|getInt|setInt|getString|setString|getDouble|setDouble|"
  r"getStringList|setStringList|remove|containsKey)\(\s*'([^']+)'"
  r"|key\s*==\s*'([^']+)'",
);

Set<String> declaredOnStorageService() {
  final source = File('lib/services/storage_service.dart').readAsStringSync();
  final out = <String>{};
  for (final match in _storageConstRe.allMatches(source)) {
    final name = match.group(1)!;
    if (notPersistedValueConsts.contains(name)) continue;
    final raw = match.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.startsWith("'") && raw.endsWith("'")) {
      out.add(raw.substring(1, raw.length - 1));
      continue;
    }
    final resolved = _aliases[raw];
    if (resolved == null) {
      fail('unresolved StorageService key alias $name = $raw');
    }
    out.add(resolved);
  }
  return out;
}

Set<String> declaredOnCloudSecretPrefs() {
  final source = File(
    'lib/services/storage/cloud_secret_prefs.dart',
  ).readAsStringSync();
  return {
    for (final match in _secretConstRe.allMatches(source)) match.group(2)!,
  };
}

/// Prefs names StorageService uses as string literals (no `_…Key` const).
Set<String> inlinePrefsKeysOnStorageService() {
  final source = File('lib/services/storage_service.dart').readAsStringSync();
  final out = <String>{};
  for (final match in _inlinePrefsKeyRe.allMatches(source)) {
    final key = match.group(1) ?? match.group(2)!;
    if (jsonPayloadFields.contains(key)) continue;
    out.add(key);
  }
  return out;
}

/// Every name the completed registry must own: declared consts, store-owned
/// keys, undeclared inline literals, and documented interpolated names.
Set<String> allDiscoveredPrefsKeys() => {
  ...declaredOnStorageService(),
  ...declaredOnCloudSecretPrefs(),
  ...HomePrefs.ownedKeys,
  ...inlinePrefsKeysOnStorageService(),
  ...interpolatedPrefsKeys,
};

/// Inline / interpolated names the const-only sweep cannot see. Pin of the
/// origin map: these are the holes S2-0 fills. Empty after the fill commit.
Set<String> unownedDiscoveredPrefsKeys() =>
    allDiscoveredPrefsKeys().difference(StorageKeyOwnership.byKey.keys.toSet());

void main() {
  test('every declared persisted key is owned by exactly one store', () {
    final fromGodFile = declaredOnStorageService();
    final fromCloud = declaredOnCloudSecretPrefs();
    final fromHome = HomePrefs.ownedKeys;
    expect(fromCloud, {
      CloudSecretPrefs.realDebridApiKey,
      CloudSecretPrefs.torboxApiKey,
      CloudSecretPrefs.premiumizeApiKey,
      CloudSecretPrefs.allDebridApiKey,
      CloudSecretPrefs.pikpakEmail,
      CloudSecretPrefs.pikpakPassword,
    });

    final declared = {...fromGodFile, ...fromCloud, ...fromHome};
    expect(
      StorageKeyOwnership.byKey.keys.toSet(),
      declared,
      reason:
          'StorageKeyOwnership.byKey must pin every StorageService '
          '`const _…Key` / CloudSecretPrefs alias plus store-owned keys',
    );

    final claimed = <String, StorageKeyStore>{};
    for (final entry in StorageKeyOwnership.byKey.entries) {
      expect(
        claimed.containsKey(entry.key),
        isFalse,
        reason: '${entry.key} listed twice in StorageKeyOwnership.byKey',
      );
      claimed[entry.key] = entry.value;
    }

    for (final key in fromCloud) {
      expect(
        claimed[key],
        StorageKeyStore.cloudSecretPrefs,
        reason: '$key must be owned by CloudSecretPrefs',
      );
    }

    expect(fromHome, StorageKeyOwnership.keysFor(StorageKeyStore.homePrefs));
    for (final key in fromHome) {
      expect(
        claimed[key],
        StorageKeyStore.homePrefs,
        reason: '$key must be owned by HomePrefs',
      );
      expect(
        fromGodFile.contains(key),
        isFalse,
        reason: '$key must not remain declared on StorageService',
      );
    }

    final residual = declared.difference(fromCloud).difference(fromHome);
    for (final key in residual) {
      expect(
        claimed[key],
        StorageKeyStore.storageService,
        reason: '$key is still declared on StorageService this slice',
      );
    }

    expect(claimed.length, declared.length);
  });

  test('inline prefs literals the const sweep cannot see are pinned', () {
    expect(
      unownedDiscoveredPrefsKeys(),
      {
        'series_browser_dense_view',
        'merged_series_page_enabled',
        'tv_keyboard_enabled',
        'tv_ui_scale_percent',
        'stremio_addon_hub_enabled',
        'detail_trailer_autoplay_enabled',
        'tv_trailer_underlay_enabled',
        'tracking_progress_fallback_notice',
        'trakt_sync_catalog_items',
        'simkl_sync_catalog_items',
        'mdblist_sync_catalog_items',
        'debrify_tv_keyword_threshold',
        'debrify_tv_min_torrents_per_keyword',
        'detail_trailer_audio_enabled',
        'detail_trailer_volume',
      },
      reason:
          'A new undeclared prefs literal (or interpolated name) must be '
          'added to StorageKeyOwnership.byKey — do not grow this hole set',
    );
  });

  test('CloudSecretPrefs aliases on StorageService keep historical names', () {
    final source = File('lib/services/storage_service.dart').readAsStringSync();
    expect(source, contains('CloudSecretPrefs.torboxApiKey'));
    expect(source, contains('CloudSecretPrefs.premiumizeApiKey'));
    expect(source, contains('CloudSecretPrefs.allDebridApiKey'));
    expect(source, contains('CloudSecretPrefs.pikpakEmail'));
    expect(source, contains('CloudSecretPrefs.pikpakPassword'));
    expect(source, contains('CloudSecretPrefs.realDebridApiKey'));
  });
}
