import 'dart:io';

import 'package:debrify/services/storage/cloud_secret_prefs.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/player_prefs.dart';
import 'package:debrify/services/storage/storage_key_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

/// Value-only consts on StorageService that are not persisted key names.
const _notKeys = {
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

Set<String> _declaredOnStorageService() {
  final source = File('lib/services/storage_service.dart').readAsStringSync();
  final out = <String>{};
  for (final match in _storageConstRe.allMatches(source)) {
    final name = match.group(1)!;
    if (_notKeys.contains(name)) continue;
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

Set<String> _declaredOnCloudSecretPrefs() {
  final source = File(
    'lib/services/storage/cloud_secret_prefs.dart',
  ).readAsStringSync();
  return {
    for (final match in _secretConstRe.allMatches(source)) match.group(2)!,
  };
}

void main() {
  test('every declared persisted key is owned by exactly one store', () {
    final fromGodFile = _declaredOnStorageService();
    final fromCloud = _declaredOnCloudSecretPrefs();
    final fromHome = HomePrefs.ownedKeys;
    final fromPlayer = PlayerPrefs.ownedKeys;
    expect(fromCloud, {
      CloudSecretPrefs.realDebridApiKey,
      CloudSecretPrefs.torboxApiKey,
      CloudSecretPrefs.premiumizeApiKey,
      CloudSecretPrefs.allDebridApiKey,
      CloudSecretPrefs.pikpakEmail,
      CloudSecretPrefs.pikpakPassword,
    });

    final declared = {...fromGodFile, ...fromCloud, ...fromHome, ...fromPlayer};
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

    expect(
      fromPlayer,
      StorageKeyOwnership.keysFor(StorageKeyStore.playerPrefs),
    );
    for (final key in fromPlayer) {
      expect(
        claimed[key],
        StorageKeyStore.playerPrefs,
        reason: '$key must be owned by PlayerPrefs',
      );
      expect(
        fromGodFile.contains(key),
        isFalse,
        reason: '$key must not remain declared on StorageService',
      );
    }

    final residual = declared
        .difference(fromCloud)
        .difference(fromHome)
        .difference(fromPlayer);
    for (final key in residual) {
      expect(
        claimed[key],
        StorageKeyStore.storageService,
        reason: '$key is still declared on StorageService this slice',
      );
    }

    expect(claimed.length, declared.length);
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
