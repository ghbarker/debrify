import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins tracking-policy and tracker-credential encodings on [StorageService]
/// before the S2-5 extract. Key names and values are a frozen compatibility
/// surface. This file must not import the new store — that lands in the
/// move commit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's25-pin-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
    StorageService.trackingSourceRevision.value = 0;
  });

  tearDown(ProfileRuntime.debugReset);

  group('defaults when no keys are stored', () {
    test(
      'scrobble masters seed every tracker on and persist the key',
      () async {
        expect(
          await TrackingPrefs.getTrackingScrobbleTargets(),
          Set<TrackingSource>.of(TrackingSource.values),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(StorageService.trackingScrobbleTargetsKey), [
          'local',
          'trakt',
          'simkl',
          'mdblist',
        ]);
      },
    );

    test('progress source, fallback notice, catalog switches', () async {
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.smart,
      );
      expect(
        await TrackingPrefs.takeTrackingProgressFallbackNotice(),
        isFalse,
      );
      expect(await TrackingPrefs.getTraktSyncCatalogItems(), isFalse);
      expect(await TrackingPrefs.getSimklSyncCatalogItems(), isFalse);
      expect(await TrackingPrefs.getMdblistSyncCatalogItems(), isFalse);
    });

    test('tracker credentials and MDBList bookkeeping', () async {
      expect(await TrackingPrefs.getTraktAccessToken(), isNull);
      expect(await TrackingPrefs.getTraktRefreshToken(), isNull);
      expect(await TrackingPrefs.getTraktUsername(), isNull);
      expect(await TrackingPrefs.getTraktTokenExpiry(), isNull);
      expect(await TrackingPrefs.hasTraktCredential(), isFalse);
      expect(await TrackingPrefs.getSimklAccessToken(), isNull);
      expect(await TrackingPrefs.getSimklUsername(), isNull);
      expect(await TrackingPrefs.hasSimklCredential(), isFalse);
      expect(await TrackingPrefs.getMdblistApiKey(), isNull);
      expect(await TrackingPrefs.getMdblistUsername(), isNull);
      expect(await TrackingPrefs.hasMdblistCredential(), isFalse);
      expect(await TrackingPrefs.getMdblistSavedClones(), isEmpty);
      expect(await TrackingPrefs.getMdblistSyncCheckpoint(), isNull);
    });
  });

  test('StorageService writes the historical tracking key bytes', () async {
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.simkl);
    await TrackingPrefs.setHomeTickSources(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.mdblist,
    });
    await TrackingPrefs.setTraktSyncCatalogItems(true);
    await TrackingPrefs.setSimklSyncCatalogItems(true);
    await TrackingPrefs.setMdblistSyncCatalogItems(true);
    await TrackingPrefs.setTraktUsername('trakt-user');
    await TrackingPrefs.setTraktTokenExpiry(1_700_000_000_000);
    await TrackingPrefs.setSimklUsername('simkl-user');
    await TrackingPrefs.setMdblistUsername('mdb-user');
    await TrackingPrefs.setMdblistSavedClone(42, 99);
    await TrackingPrefs.setMdblistSyncCheckpoint(<String, dynamic>{
      'cursor': 'abc',
      'n': 3,
    });

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tracking_scrobble_targets'), [
      'local',
      'trakt',
    ]);
    expect(prefs.getString('watch_progress_source'), 'simkl');
    expect(prefs.getStringList('home_tick_sources'), ['local', 'mdblist']);
    expect(prefs.getBool('trakt_sync_catalog_items'), isTrue);
    expect(prefs.getBool('simkl_sync_catalog_items'), isTrue);
    expect(prefs.getBool('mdblist_sync_catalog_items'), isTrue);
    expect(prefs.getString('trakt_username'), 'trakt-user');
    expect(prefs.getInt('trakt_token_expiry'), 1_700_000_000_000);
    expect(prefs.getString('simkl_username'), 'simkl-user');
    expect(prefs.getString('mdblist_username'), 'mdb-user');
    expect(prefs.getString('mdblist_saved_clones'), '{"42":99}');
    expect(jsonDecode(prefs.getString('mdblist_sync_checkpoint_v1')!), {
      'cursor': 'abc',
      'n': 3,
    });
  });

  test(
    'raw tracking bytes round-trip through StorageService getters',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tracking_scrobble_targets': <String>['local', 'simkl'],
        'watch_progress_source': 'local',
        'home_tick_sources': <String>['trakt'],
        'trakt_sync_catalog_items': true,
        'simkl_sync_catalog_items': false,
        'mdblist_sync_catalog_items': true,
        'trakt_username': 'raw-trakt',
        'trakt_token_expiry': 99,
        'simkl_username': 'raw-simkl',
        'mdblist_username': 'raw-mdb',
        'mdblist_saved_clones': '{"7":8}',
        'mdblist_sync_checkpoint_v1': '{"ok":true}',
        'tracking_progress_fallback_notice': true,
      });

      expect(
        await TrackingPrefs.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local, TrackingSource.simkl},
      );
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.local,
      );
      expect(await TrackingPrefs.getHomeTickSources(), <TrackingSource>{
        TrackingSource.trakt,
      });
      expect(await TrackingPrefs.getTraktSyncCatalogItems(), isTrue);
      expect(await TrackingPrefs.getSimklSyncCatalogItems(), isFalse);
      expect(await TrackingPrefs.getMdblistSyncCatalogItems(), isTrue);
      expect(await TrackingPrefs.getTraktUsername(), 'raw-trakt');
      expect(await TrackingPrefs.getTraktTokenExpiry(), 99);
      expect(await TrackingPrefs.getSimklUsername(), 'raw-simkl');
      expect(await TrackingPrefs.getMdblistUsername(), 'raw-mdb');
      expect(await TrackingPrefs.getMdblistSavedClones(), {7: 8});
      expect(await TrackingPrefs.getMdblistSyncCheckpoint(), {'ok': true});
      expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('tracking_progress_fallback_notice'), isFalse);
      expect(
        await TrackingPrefs.takeTrackingProgressFallbackNotice(),
        isFalse,
      );
    },
  );

  test('unknown watch-progress source reads as smart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'watch_progress_source': 'plex',
    });
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
  });

  test('legacy catalog OFF seeds masters without that tracker', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'trakt_sync_catalog_items': false,
      'mdblist_sync_catalog_items': false,
    });
    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('absent legacy catalog key is treated as ON when seeding', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'simkl_sync_catalog_items': false,
    });
    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.mdblist,
    });
  });

  test('enableTrackingScrobbleTarget is idempotent when already on', () async {
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });
    final revision = StorageService.trackingSourceRevision.value;
    await TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.trakt);
    expect(StorageService.trackingSourceRevision.value, revision);
  });

  test('enableTrackingScrobbleTarget bumps revision when it adds', () async {
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    final revision = StorageService.trackingSourceRevision.value;
    await TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.simkl);
    expect(StorageService.trackingSourceRevision.value, revision + 1);
    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('setTrackingScrobbleTargets / progress / ticks bump revision', () async {
    var revision = StorageService.trackingSourceRevision.value;
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    expect(StorageService.trackingSourceRevision.value, revision + 1);

    revision = StorageService.trackingSourceRevision.value;
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.trakt);
    expect(StorageService.trackingSourceRevision.value, revision + 1);

    revision = StorageService.trackingSourceRevision.value;
    await TrackingPrefs.setHomeTickSources(<TrackingSource>{
      TrackingSource.local,
    });
    expect(StorageService.trackingSourceRevision.value, revision + 1);

    revision = StorageService.trackingSourceRevision.value;
    await TrackingPrefs.reseedTrackingScrobbleTargetsFromLegacy();
    expect(StorageService.trackingSourceRevision.value, revision + 1);
  });

  test('disconnected dedicated progress falls back and sets notice', () async {
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.trakt);
    expect(
      await TrackingPrefs.fallbackDisconnectedProgressSource(
        TrackingSource.trakt,
      ),
      isTrue,
    );
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tracking_progress_fallback_notice'), isTrue);
    expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isTrue);
  });

  test('fallback no-ops when progress source is not that tracker', () async {
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.simkl);
    expect(
      await TrackingPrefs.fallbackDisconnectedProgressSource(
        TrackingSource.trakt,
      ),
      isFalse,
    );
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.simkl,
    );
    expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isFalse);
  });

  test('smart / local progress never owns a disconnected tracker', () async {
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.smart);
    expect(
      await TrackingPrefs.fallbackDisconnectedProgressSource(
        TrackingSource.mdblist,
      ),
      isFalse,
    );
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
    expect(
      await TrackingPrefs.fallbackDisconnectedProgressSource(
        TrackingSource.local,
      ),
      isFalse,
    );
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.local,
    );
  });

  test('tracking payload encode / apply and hide_watched', () async {
    await TrackingPrefs.applyTrackingPreferencesPayload(<String, dynamic>{
      'scrobble_targets': <String>['trakt', 'nope'],
      'progress_source': 'mdblist',
      'home_tick_sources': <String>['local', 'simkl', 'ghost'],
      'hide_watched': true,
    });

    final payload = await TrackingPrefs.buildTrackingPreferencesPayload();
    expect(
      payload['scrobble_targets'],
      containsAll(<String>['local', 'trakt']),
    );
    expect(payload['progress_source'], 'mdblist');
    expect(
      payload['home_tick_sources'],
      containsAll(<String>['local', 'simkl']),
    );
    expect(payload['hide_watched'], isTrue);
  });

  test(
    'applyTrackingPreferencesPayload ignores unknown progress_source',
    () async {
      await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
      await TrackingPrefs.applyTrackingPreferencesPayload(<String, dynamic>{
        'progress_source': 'plex',
      });
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.local,
      );
    },
  );

  test(
    'Trakt / Simkl / MDBList secrets round-trip through the vault',
    () async {
      await TrackingPrefs.setTraktAccessToken('trakt-access');
      await TrackingPrefs.setTraktRefreshToken('trakt-refresh');
      await TrackingPrefs.setSimklAccessToken('simkl-access');
      await TrackingPrefs.saveMdblistApiKey('mdb-key');

      expect(await TrackingPrefs.getTraktAccessToken(), 'trakt-access');
      expect(await TrackingPrefs.getTraktRefreshToken(), 'trakt-refresh');
      expect(await TrackingPrefs.getSimklAccessToken(), 'simkl-access');
      expect(await TrackingPrefs.getMdblistApiKey(), 'mdb-key');
      expect(await TrackingPrefs.hasTraktCredential(), isTrue);
      expect(await TrackingPrefs.hasSimklCredential(), isTrue);
      expect(await TrackingPrefs.hasMdblistCredential(), isTrue);
    },
  );

  test(
    'clearTraktAuth drops username/expiry and falls back progress',
    () async {
      await TrackingPrefs.setTraktAccessToken('access');
      await TrackingPrefs.setTraktRefreshToken('refresh');
      await TrackingPrefs.setTraktUsername('alice');
      await TrackingPrefs.setTraktTokenExpiry(123);
      await TrackingPrefs.setWatchProgressSource(WatchProgressSource.trakt);

      final shouldRevoke = await TrackingPrefs.clearTraktAuth();
      expect(shouldRevoke, isTrue);
      expect(await TrackingPrefs.getTraktAccessToken(), isNull);
      expect(await TrackingPrefs.getTraktRefreshToken(), isNull);
      expect(await TrackingPrefs.getTraktUsername(), isNull);
      expect(await TrackingPrefs.getTraktTokenExpiry(), isNull);
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.smart,
      );
      expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isTrue);
    },
  );

  test('clearSimklAuth drops username and falls back progress', () async {
    await TrackingPrefs.setSimklAccessToken('simkl-access');
    await TrackingPrefs.setSimklUsername('bob');
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.simkl);

    await TrackingPrefs.clearSimklAuth();
    expect(await TrackingPrefs.getSimklAccessToken(), isNull);
    expect(await TrackingPrefs.getSimklUsername(), isNull);
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
  });

  test(
    'clearMdblistAuth drops username, clones, checkpoint, and progress',
    () async {
      await TrackingPrefs.saveMdblistApiKey('mdb-key');
      await TrackingPrefs.setMdblistUsername('carol');
      await TrackingPrefs.setMdblistSavedClone(1, 2);
      await TrackingPrefs.setMdblistSyncCheckpoint(<String, dynamic>{'n': 1});
      await TrackingPrefs.setWatchProgressSource(WatchProgressSource.mdblist);

      await TrackingPrefs.clearMdblistAuth();
      expect(await TrackingPrefs.getMdblistApiKey(), isNull);
      expect(await TrackingPrefs.getMdblistUsername(), isNull);
      expect(await TrackingPrefs.getMdblistSavedClones(), isEmpty);
      expect(await TrackingPrefs.getMdblistSyncCheckpoint(), isNull);
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.smart,
      );
    },
  );

  test(
    'empty MDBList username removes the key; Trakt empty string persists',
    () async {
      await TrackingPrefs.setMdblistUsername('keep');
      await TrackingPrefs.setMdblistUsername('');
      await TrackingPrefs.setTraktUsername('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('mdblist_username'), isFalse);
      expect(prefs.getString('trakt_username'), '');
    },
  );

  test('MDBList clone / checkpoint encodings and corrupt reads', () async {
    await TrackingPrefs.setMdblistSavedClone(10, 20);
    await TrackingPrefs.setMdblistSavedClone(11, 21);
    expect(await TrackingPrefs.getMdblistSavedClones(), {10: 20, 11: 21});
    await TrackingPrefs.removeMdblistSavedClone(10);
    expect(await TrackingPrefs.getMdblistSavedClones(), {11: 21});
    await TrackingPrefs.retireMdblistSavedCloneMarkers();
    expect(await TrackingPrefs.getMdblistSavedClones(), isEmpty);

    await TrackingPrefs.setMdblistSyncCheckpoint(<String, dynamic>{'k': 'v'});
    expect(await TrackingPrefs.getMdblistSyncCheckpoint(), {'k': 'v'});
    await TrackingPrefs.setMdblistSyncCheckpoint(null);
    expect(await TrackingPrefs.getMdblistSyncCheckpoint(), isNull);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'mdblist_saved_clones': 'not-json',
      'mdblist_sync_checkpoint_v1': '[1]',
    });
    expect(await TrackingPrefs.getMdblistSavedClones(), isEmpty);
    expect(await TrackingPrefs.getMdblistSyncCheckpoint(), isNull);
  });

  test('public tracking key names stay on the façade', () {
    expect(
      StorageService.trackingScrobbleTargetsKey,
      'tracking_scrobble_targets',
    );
    expect(StorageService.watchProgressSourceKey, 'watch_progress_source');
  });
}
