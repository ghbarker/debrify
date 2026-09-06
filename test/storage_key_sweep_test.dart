import 'package:debrify/services/storage/device_maintenance_prefs.dart';
import 'package:debrify/services/storage/catalog_search_prefs.dart';
import 'package:debrify/services/storage/ambient_trailer_prefs.dart';
import 'package:debrify/services/storage/download_destination_prefs.dart';
import 'package:debrify/services/storage/torrent_search_history_store.dart';
import 'package:debrify/services/remote_control/remote_device_prefs.dart';
import 'package:debrify/services/profiles/profile_onboarding_state.dart';
import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'dart:io';

import 'package:debrify/services/storage/my_watchlist_store.dart';

import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/storage/cloud_secret_prefs.dart';
import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/default_torrent_filter_prefs.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/player_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'package:debrify/services/storage/social_prefs.dart';
import 'package:debrify/services/storage/storage_key_ownership.dart';
import 'package:debrify/services/storage/stremio_tv_prefs.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
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
const jsonPayloadFields = {'finishedEpisodes', 'seasons', 'trackPreferences'};

const _aliases = {
  'PlaybackProgressStore.playbackStateKey': PlaybackProgressStore.playbackStateKey,
  'PlaybackProgressStore.continueWatchingKey': PlaybackProgressStore.continueWatchingKey,
  'PlaybackProgressStore.localSeriesCompletionStateKey': PlaybackProgressStore.localSeriesCompletionStateKey,
  'PlaybackProgressStore.localSeriesCalendarCheckedAtKey': PlaybackProgressStore.localSeriesCalendarCheckedAtKey,
  'PlaybackProgressStore.localSeriesCalendarAttemptedAtKey': PlaybackProgressStore.localSeriesCalendarAttemptedAtKey,
  'PlaybackProgressStore.finishedMoviesKey': PlaybackProgressStore.finishedMoviesKey,
  'PlaybackProgressStore.tvMazeSeriesMappingKey': PlaybackProgressStore.tvMazeSeriesMappingKey,
  'PlaybackProgressStore.playlistPosterOverridesKey': PlaybackProgressStore.playlistPosterOverridesKey,

  'CloudSecretPrefs.torboxApiKey': CloudSecretPrefs.torboxApiKey,
  'CloudSecretPrefs.premiumizeApiKey': CloudSecretPrefs.premiumizeApiKey,
  'CloudSecretPrefs.allDebridApiKey': CloudSecretPrefs.allDebridApiKey,
  'CloudSecretPrefs.pikpakEmail': CloudSecretPrefs.pikpakEmail,
  'CloudSecretPrefs.pikpakPassword': CloudSecretPrefs.pikpakPassword,
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
  ...DeviceMaintenancePrefs.ownedKeys,
  ...CatalogSearchPrefs.ownedKeys,
  ...DownloadDestinationPrefs.ownedKeys,
  ...TorrentSearchHistoryStore.ownedKeys,
  ...RemoteDevicePrefs.ownedKeys,
  ...ProfileOnboardingState.ownedKeys,
  ...declaredOnStorageService(),
  ...declaredOnCloudSecretPrefs(),
  ...MyWatchlistStore.ownedKeys,
  ...HomePrefs.ownedKeys,
  ...StremioTvPrefs.ownedKeys,
  ...SocialPrefs.ownedKeys,
  ...DebrifyTvPrefs.ownedKeys,
  ...ProviderCredentialPrefs.ownedKeys,
  ...PlayerPrefs.ownedKeys,
  ...IptvPrefs.ownedKeys,
  ...AppStylePrefs.ownedKeys,
  ...TrackingPrefs.ownedKeys,
  ...PlaybackProgressStore.ownedKeys,
  ...DefaultTorrentFilterPrefs.ownedKeys,
  ...QuickPlayPolicyPrefs.ownedKeys,
  ...inlinePrefsKeysOnStorageService(),
  ...AmbientTrailerPrefs.ownedKeys,
};

/// Discovered names not yet in [StorageKeyOwnership.byKey]. Must stay empty.
Set<String> unownedDiscoveredPrefsKeys() =>
    allDiscoveredPrefsKeys().difference(StorageKeyOwnership.byKey.keys.toSet());

void main() {
  test('device maintenance keys have exact ownership and missing rows fail', () {
    const expected = {
      'support_remote_config_cache_v1', 'dismissed_donation_campaign_ids_v1',
      'update_auto_check_enabled', 'update_ignored_version',
    };
    expect(DeviceMaintenancePrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.deviceMaintenancePrefs), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(inlinePrefsKeysOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      expect(allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key})), {key});
    }
  });

  test('catalog search key has exact ownership and missing row fails', () {
    const expected = {'catalog_search_disabled_addons_v1'};
    expect(CatalogSearchPrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.catalogSearchPrefs), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(inlinePrefsKeysOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    expect(allDiscoveredPrefsKeys().difference(
      StorageKeyOwnership.byKey.keys.toSet().difference(expected)), expected);
  });

  test('keyboard pair belongs to AppStylePrefs and missing rows fail', () {
    const expected = {'tv_keyboard_enabled', 'tvos_keyboard_default_generation'};
    expect(AppStylePrefs.ownedKeys.intersection(expected), expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.appStylePrefs).intersection(expected), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(inlinePrefsKeysOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      expect(allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key})), {key});
    }
  });

  test('ambient detail keys have exact ownership and missing rows fail', () {
    const expected = {'detail_trailer_audio_enabled', 'detail_trailer_volume'};
    expect(AmbientTrailerPrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.ambientTrailerPrefs), expected);
    expect(HomePrefs.ownedKeys, containsAll({
      'home_hero_trailer_audio_enabled', 'home_hero_trailer_volume',
    }));
    expect(HomePrefs.ownedKeys.intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      expect(allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key})), {key});
    }
  });

  test('download destinations have exact ownership and every missing row fails', () {
    const expected = {
      'download_tree_uri_v1',
      'download_tree_display_name_v1',
      'download_dir_path_v1',
    };
    expect(DownloadDestinationPrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.downloadDestinationPrefs), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      expect(allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key})), {key});
    }
  });


  test('history keys are discovered and either missing registry row fails', () {
    const expected = {'torrent_search_history_v1', 'torrent_search_history_enabled'};
    expect(TorrentSearchHistoryStore.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.torrentSearchHistoryStore), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      expect(allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key})), {key});
    }
  });


  test('remote device keys have exact ownership and missing rows are detected', () {
    const expected = {
      'remote_control_enabled', 'remote_intro_shown',
      'remote_tv_device_name', 'remote_last_device',
    };
    expect(RemoteDevicePrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.remoteDevicePrefs), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      expect(allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key})), {key});
    }
  });

  test('onboarding singleton is discovered and missing ownership fails', () {
    const expected = {'initial_setup_complete_v1'};
    expect(ProfileOnboardingState.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.profileOnboardingState), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    expect(allDiscoveredPrefsKeys().difference(
      StorageKeyOwnership.byKey.keys.toSet().difference(expected)), expected);
  });

  test('watchlist singleton is discovered and missing registry ownership fails', () {
    const expected = {'my_watchlist_v1'};
    expect(MyWatchlistStore.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.myWatchlistStore), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    final missing = allDiscoveredPrefsKeys().difference(
      StorageKeyOwnership.byKey.keys.toSet().difference(expected),
    );
    expect(missing, expected);
  });

  test('default filter keys participate in discovery and exact ownership', () {
    const expected = {
      'default_filter_qualities_v1',
      'default_filter_rip_sources_v1',
      'default_filter_languages_v1',
      'default_filter_sizes_v1',
      'default_filter_dynamic_ranges_v1',
    };
    expect(DefaultTorrentFilterPrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.defaultTorrentFilterPrefs),
        expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final key in expected) {
      final missing = allDiscoveredPrefsKeys().difference(
        StorageKeyOwnership.byKey.keys.toSet().difference({key}),
      );
      expect(missing, {key});
    }
  });

  test('playback store keys participate in discovery and exact ownership', () {
    expect(PlaybackProgressStore.ownedKeys,
        StorageKeyOwnership.keysFor(StorageKeyStore.playbackProgressStore));
    expect(allDiscoveredPrefsKeys(), containsAll(PlaybackProgressStore.ownedKeys));
    // These names left the facade entirely: aliases alone cannot cover them.
    expect(declaredOnStorageService().contains('episode_trakt_progress_v2'), isFalse);
    expect(allDiscoveredPrefsKeys(), contains('episode_trakt_progress_v2'));
    final missingPlayback = allDiscoveredPrefsKeys().difference(
      StorageKeyOwnership.byKey.keys.toSet().difference({'episode_trakt_progress_v2'}),
    );
    expect(missingPlayback, {'episode_trakt_progress_v2'});
  });

  test('Quick Play policy keys participate in exact discovery and ownership', () {
    const expected = {
      'quick_play_honors_filters_v1',
      'quick_play_try_multiple_torrents',
      'quick_play_max_retries',
      'quick_play_movie_rules_v2',
      'quick_play_series_rules_v2',
      'play_button_mode',
      'auto_bind_series_packs_on_play',
    };
    expect(QuickPlayPolicyPrefs.ownedKeys, expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.quickPlayPolicyPrefs), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final missing in expected) {
      final incompleteRegistry = StorageKeyOwnership.byKey.keys.toSet()..remove(missing);
      expect(allDiscoveredPrefsKeys().difference(incompleteRegistry), {missing});
    }
  });

  test('VR keys belong to PlayerPrefs and every missing row is detected', () {
    const expected = {
      'quick_play_vr_mode',
      'quick_play_vr_default_screen_type',
      'quick_play_vr_default_stereo_mode',
      'quick_play_vr_auto_detect_format',
      'quick_play_vr_show_dialog',
    };
    expect(PlayerPrefs.ownedKeys.intersection(expected), expected);
    expect(StorageKeyOwnership.keysFor(StorageKeyStore.playerPrefs).intersection(expected), expected);
    expect(declaredOnStorageService().intersection(expected), isEmpty);
    expect(allDiscoveredPrefsKeys(), containsAll(expected));
    for (final missing in expected) {
      final incompleteRegistry = StorageKeyOwnership.byKey.keys.toSet()..remove(missing);
      expect(allDiscoveredPrefsKeys().difference(incompleteRegistry), {missing});
    }
  });

  test('every declared persisted key is owned by exactly one store', () {
    final fromGodFile = declaredOnStorageService();
    final fromCloud = declaredOnCloudSecretPrefs();
    final fromHome = HomePrefs.ownedKeys;
    final fromStremio = StremioTvPrefs.ownedKeys;
    final fromSocial = SocialPrefs.ownedKeys;
    final fromDebrify = DebrifyTvPrefs.ownedKeys;
    final fromProvider = ProviderCredentialPrefs.ownedKeys;
    final fromPlayer = PlayerPrefs.ownedKeys;
    final fromIptv = IptvPrefs.ownedKeys;
    final fromAppStyle = AppStylePrefs.ownedKeys;
    final fromTracking = TrackingPrefs.ownedKeys;
    final fromInline = {
      ...inlinePrefsKeysOnStorageService(),
    };
    expect(fromCloud, {
      CloudSecretPrefs.realDebridApiKey,
      CloudSecretPrefs.torboxApiKey,
      CloudSecretPrefs.premiumizeApiKey,
      CloudSecretPrefs.allDebridApiKey,
      CloudSecretPrefs.pikpakEmail,
      CloudSecretPrefs.pikpakPassword,
    });

    final declared = allDiscoveredPrefsKeys();
    expect(
      StorageKeyOwnership.byKey.keys.toSet(),
      declared,
      reason:
          'StorageKeyOwnership.byKey must pin every StorageService '
          '`const _…Key` / CloudSecretPrefs alias, store-owned keys, '
          'and undeclared inline / interpolated prefs names',
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

    void expectStore(Set<String> keys, StorageKeyStore store, String label) {
      expect(keys, StorageKeyOwnership.keysFor(store));
      for (final key in keys) {
        expect(claimed[key], store, reason: '$key must be owned by $label');
        expect(
          fromGodFile.contains(key),
          isFalse,
          reason: '$key must not remain declared on StorageService',
        );
      }
    }

    expectStore(DeviceMaintenancePrefs.ownedKeys,
        StorageKeyStore.deviceMaintenancePrefs, 'DeviceMaintenancePrefs');
    expectStore(CatalogSearchPrefs.ownedKeys,
        StorageKeyStore.catalogSearchPrefs, 'CatalogSearchPrefs');
    expectStore(DownloadDestinationPrefs.ownedKeys,
        StorageKeyStore.downloadDestinationPrefs, 'DownloadDestinationPrefs');
    expectStore(AmbientTrailerPrefs.ownedKeys,
        StorageKeyStore.ambientTrailerPrefs, 'AmbientTrailerPrefs');
    expectStore(TorrentSearchHistoryStore.ownedKeys,
        StorageKeyStore.torrentSearchHistoryStore, 'TorrentSearchHistoryStore');
    expectStore(RemoteDevicePrefs.ownedKeys,
        StorageKeyStore.remoteDevicePrefs, 'RemoteDevicePrefs');
    expectStore(ProfileOnboardingState.ownedKeys,
        StorageKeyStore.profileOnboardingState, 'ProfileOnboardingState');
    expectStore(fromStremio, StorageKeyStore.stremioTvPrefs, 'StremioTvPrefs');
    expectStore(fromSocial, StorageKeyStore.socialPrefs, 'SocialPrefs');
    expectStore(fromDebrify, StorageKeyStore.debrifyTvPrefs, 'DebrifyTvPrefs');
    expectStore(
      fromProvider,
      StorageKeyStore.providerCredentialPrefs,
      'ProviderCredentialPrefs',
    );
    expectStore(fromPlayer, StorageKeyStore.playerPrefs, 'PlayerPrefs');
    expectStore(fromIptv, StorageKeyStore.iptvPrefs, 'IptvPrefs');
    expectStore(fromAppStyle, StorageKeyStore.appStylePrefs, 'AppStylePrefs');
    expectStore(fromTracking, StorageKeyStore.trackingPrefs, 'TrackingPrefs');
    expectStore(QuickPlayPolicyPrefs.ownedKeys,
        StorageKeyStore.quickPlayPolicyPrefs, 'QuickPlayPolicyPrefs');
    expectStore(DefaultTorrentFilterPrefs.ownedKeys,
        StorageKeyStore.defaultTorrentFilterPrefs, 'DefaultTorrentFilterPrefs');

    final extracted = {
      ...DeviceMaintenancePrefs.ownedKeys,
      ...CatalogSearchPrefs.ownedKeys,
      ...AmbientTrailerPrefs.ownedKeys,
      ...DownloadDestinationPrefs.ownedKeys,
      ...TorrentSearchHistoryStore.ownedKeys,
      ...RemoteDevicePrefs.ownedKeys,
      ...ProfileOnboardingState.ownedKeys,
      ...fromCloud,
      ...fromHome,
      ...fromStremio,
      ...fromSocial,
      ...fromDebrify,
      ...fromProvider,
      ...fromPlayer,
      ...fromIptv,
      ...fromAppStyle,
      ...fromTracking,
      ...MyWatchlistStore.ownedKeys,
      ...PlaybackProgressStore.ownedKeys,
      ...DefaultTorrentFilterPrefs.ownedKeys,
      ...QuickPlayPolicyPrefs.ownedKeys,
    };
    final residual = declared.difference(extracted);
    for (final key in residual) {
      expect(
        claimed[key],
        StorageKeyStore.storageService,
        reason:
            '$key is still declared or inlined on StorageService this slice',
      );
    }

    expect(fromInline.difference(claimed.keys.toSet()), isEmpty);
    expect(claimed.length, declared.length);
  });

  test('a missing declaration fails the sweep', () {
    expect(
      unownedDiscoveredPrefsKeys(),
      isEmpty,
      reason:
          'A new `const _…Key`, CloudSecretPrefs name, HomePrefs owned '
          'key, inline prefs literal, or interpolated detail-trailer name '
          'must be added to StorageKeyOwnership.byKey',
    );
    expect(
      StorageKeyOwnership.byKey.containsKey('not_a_real_prefs_key'),
      isFalse,
      reason:
          'Mutation: an undeclared name must not be in byKey, and a '
          'discovered name must not be missing (holes above)',
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
