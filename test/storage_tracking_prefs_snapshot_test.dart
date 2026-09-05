import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
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
          await StorageService.getTrackingScrobbleTargets(),
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
        await StorageService.getWatchProgressSource(),
        WatchProgressSource.smart,
      );
      expect(
        await StorageService.takeTrackingProgressFallbackNotice(),
        isFalse,
      );
      expect(await StorageService.getTraktSyncCatalogItems(), isFalse);
      expect(await StorageService.getSimklSyncCatalogItems(), isFalse);
      expect(await StorageService.getMdblistSyncCatalogItems(), isFalse);
    });

    test('tracker credentials and MDBList bookkeeping', () async {
      expect(await StorageService.getTraktAccessToken(), isNull);
      expect(await StorageService.getTraktRefreshToken(), isNull);
      expect(await StorageService.getTraktUsername(), isNull);
      expect(await StorageService.getTraktTokenExpiry(), isNull);
      expect(await StorageService.hasTraktCredential(), isFalse);
      expect(await StorageService.getSimklAccessToken(), isNull);
      expect(await StorageService.getSimklUsername(), isNull);
      expect(await StorageService.hasSimklCredential(), isFalse);
      expect(await StorageService.getMdblistApiKey(), isNull);
      expect(await StorageService.getMdblistUsername(), isNull);
      expect(await StorageService.hasMdblistCredential(), isFalse);
      expect(await StorageService.getMdblistSavedClones(), isEmpty);
      expect(await StorageService.getMdblistSyncCheckpoint(), isNull);
    });
  });

  test('StorageService writes the historical tracking key bytes', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });
    await StorageService.setWatchProgressSource(WatchProgressSource.simkl);
    await StorageService.setHomeTickSources(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.mdblist,
    });
    await StorageService.setTraktSyncCatalogItems(true);
    await StorageService.setSimklSyncCatalogItems(true);
    await StorageService.setMdblistSyncCatalogItems(true);
    await StorageService.setTraktUsername('trakt-user');
    await StorageService.setTraktTokenExpiry(1_700_000_000_000);
    await StorageService.setSimklUsername('simkl-user');
    await StorageService.setMdblistUsername('mdb-user');
    await StorageService.setMdblistSavedClone(42, 99);
    await StorageService.setMdblistSyncCheckpoint(<String, dynamic>{
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
        await StorageService.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local, TrackingSource.simkl},
      );
      expect(
        await StorageService.getWatchProgressSource(),
        WatchProgressSource.local,
      );
      expect(await StorageService.getHomeTickSources(), <TrackingSource>{
        TrackingSource.trakt,
      });
      expect(await StorageService.getTraktSyncCatalogItems(), isTrue);
      expect(await StorageService.getSimklSyncCatalogItems(), isFalse);
      expect(await StorageService.getMdblistSyncCatalogItems(), isTrue);
      expect(await StorageService.getTraktUsername(), 'raw-trakt');
      expect(await StorageService.getTraktTokenExpiry(), 99);
      expect(await StorageService.getSimklUsername(), 'raw-simkl');
      expect(await StorageService.getMdblistUsername(), 'raw-mdb');
      expect(await StorageService.getMdblistSavedClones(), {7: 8});
      expect(await StorageService.getMdblistSyncCheckpoint(), {'ok': true});
      expect(await StorageService.takeTrackingProgressFallbackNotice(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('tracking_progress_fallback_notice'), isFalse);
      expect(
        await StorageService.takeTrackingProgressFallbackNotice(),
        isFalse,
      );
    },
  );

  test('unknown watch-progress source reads as smart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'watch_progress_source': 'plex',
    });
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
  });

  test('legacy catalog OFF seeds masters without that tracker', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'trakt_sync_catalog_items': false,
      'mdblist_sync_catalog_items': false,
    });
    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('absent legacy catalog key is treated as ON when seeding', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'simkl_sync_catalog_items': false,
    });
    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.mdblist,
    });
  });

  test('enableTrackingScrobbleTarget is idempotent when already on', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });
    final revision = StorageService.trackingSourceRevision.value;
    await StorageService.enableTrackingScrobbleTarget(TrackingSource.trakt);
    expect(StorageService.trackingSourceRevision.value, revision);
  });

  test('enableTrackingScrobbleTarget bumps revision when it adds', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    final revision = StorageService.trackingSourceRevision.value;
    await StorageService.enableTrackingScrobbleTarget(TrackingSource.simkl);
    expect(StorageService.trackingSourceRevision.value, revision + 1);
    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('setTrackingScrobbleTargets / progress / ticks bump revision', () async {
    var revision = StorageService.trackingSourceRevision.value;
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    expect(StorageService.trackingSourceRevision.value, revision + 1);

    revision = StorageService.trackingSourceRevision.value;
    await StorageService.setWatchProgressSource(WatchProgressSource.trakt);
    expect(StorageService.trackingSourceRevision.value, revision + 1);

    revision = StorageService.trackingSourceRevision.value;
    await StorageService.setHomeTickSources(<TrackingSource>{
      TrackingSource.local,
    });
    expect(StorageService.trackingSourceRevision.value, revision + 1);

    revision = StorageService.trackingSourceRevision.value;
    await StorageService.reseedTrackingScrobbleTargetsFromLegacy();
    expect(StorageService.trackingSourceRevision.value, revision + 1);
  });

  test('disconnected dedicated progress falls back and sets notice', () async {
    await StorageService.setWatchProgressSource(WatchProgressSource.trakt);
    expect(
      await StorageService.fallbackDisconnectedProgressSource(
        TrackingSource.trakt,
      ),
      isTrue,
    );
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tracking_progress_fallback_notice'), isTrue);
    expect(await StorageService.takeTrackingProgressFallbackNotice(), isTrue);
  });

  test('fallback no-ops when progress source is not that tracker', () async {
    await StorageService.setWatchProgressSource(WatchProgressSource.simkl);
    expect(
      await StorageService.fallbackDisconnectedProgressSource(
        TrackingSource.trakt,
      ),
      isFalse,
    );
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.simkl,
    );
    expect(await StorageService.takeTrackingProgressFallbackNotice(), isFalse);
  });

  test('smart / local progress never owns a disconnected tracker', () async {
    await StorageService.setWatchProgressSource(WatchProgressSource.smart);
    expect(
      await StorageService.fallbackDisconnectedProgressSource(
        TrackingSource.mdblist,
      ),
      isFalse,
    );
    await StorageService.setWatchProgressSource(WatchProgressSource.local);
    expect(
      await StorageService.fallbackDisconnectedProgressSource(
        TrackingSource.local,
      ),
      isFalse,
    );
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.local,
    );
  });

  test('tracking payload encode / apply and hide_watched', () async {
    await StorageService.applyTrackingPreferencesPayload(<String, dynamic>{
      'scrobble_targets': <String>['trakt', 'nope'],
      'progress_source': 'mdblist',
      'home_tick_sources': <String>['local', 'simkl', 'ghost'],
      'hide_watched': true,
    });

    final payload = await StorageService.buildTrackingPreferencesPayload();
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
      await StorageService.setWatchProgressSource(WatchProgressSource.local);
      await StorageService.applyTrackingPreferencesPayload(<String, dynamic>{
        'progress_source': 'plex',
      });
      expect(
        await StorageService.getWatchProgressSource(),
        WatchProgressSource.local,
      );
    },
  );

  test(
    'Trakt / Simkl / MDBList secrets round-trip through the vault',
    () async {
      await StorageService.setTraktAccessToken('trakt-access');
      await StorageService.setTraktRefreshToken('trakt-refresh');
      await StorageService.setSimklAccessToken('simkl-access');
      await StorageService.saveMdblistApiKey('mdb-key');

      expect(await StorageService.getTraktAccessToken(), 'trakt-access');
      expect(await StorageService.getTraktRefreshToken(), 'trakt-refresh');
      expect(await StorageService.getSimklAccessToken(), 'simkl-access');
      expect(await StorageService.getMdblistApiKey(), 'mdb-key');
      expect(await StorageService.hasTraktCredential(), isTrue);
      expect(await StorageService.hasSimklCredential(), isTrue);
      expect(await StorageService.hasMdblistCredential(), isTrue);
    },
  );

  test(
    'clearTraktAuth drops username/expiry and falls back progress',
    () async {
      await StorageService.setTraktAccessToken('access');
      await StorageService.setTraktRefreshToken('refresh');
      await StorageService.setTraktUsername('alice');
      await StorageService.setTraktTokenExpiry(123);
      await StorageService.setWatchProgressSource(WatchProgressSource.trakt);

      final shouldRevoke = await StorageService.clearTraktAuth();
      expect(shouldRevoke, isTrue);
      expect(await StorageService.getTraktAccessToken(), isNull);
      expect(await StorageService.getTraktRefreshToken(), isNull);
      expect(await StorageService.getTraktUsername(), isNull);
      expect(await StorageService.getTraktTokenExpiry(), isNull);
      expect(
        await StorageService.getWatchProgressSource(),
        WatchProgressSource.smart,
      );
      expect(await StorageService.takeTrackingProgressFallbackNotice(), isTrue);
    },
  );

  test('clearSimklAuth drops username and falls back progress', () async {
    await StorageService.setSimklAccessToken('simkl-access');
    await StorageService.setSimklUsername('bob');
    await StorageService.setWatchProgressSource(WatchProgressSource.simkl);

    await StorageService.clearSimklAuth();
    expect(await StorageService.getSimklAccessToken(), isNull);
    expect(await StorageService.getSimklUsername(), isNull);
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
  });

  test(
    'clearMdblistAuth drops username, clones, checkpoint, and progress',
    () async {
      await StorageService.saveMdblistApiKey('mdb-key');
      await StorageService.setMdblistUsername('carol');
      await StorageService.setMdblistSavedClone(1, 2);
      await StorageService.setMdblistSyncCheckpoint(<String, dynamic>{'n': 1});
      await StorageService.setWatchProgressSource(WatchProgressSource.mdblist);

      await StorageService.clearMdblistAuth();
      expect(await StorageService.getMdblistApiKey(), isNull);
      expect(await StorageService.getMdblistUsername(), isNull);
      expect(await StorageService.getMdblistSavedClones(), isEmpty);
      expect(await StorageService.getMdblistSyncCheckpoint(), isNull);
      expect(
        await StorageService.getWatchProgressSource(),
        WatchProgressSource.smart,
      );
    },
  );

  test(
    'empty MDBList username removes the key; Trakt empty string persists',
    () async {
      await StorageService.setMdblistUsername('keep');
      await StorageService.setMdblistUsername('');
      await StorageService.setTraktUsername('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('mdblist_username'), isFalse);
      expect(prefs.getString('trakt_username'), '');
    },
  );

  test('MDBList clone / checkpoint encodings and corrupt reads', () async {
    await StorageService.setMdblistSavedClone(10, 20);
    await StorageService.setMdblistSavedClone(11, 21);
    expect(await StorageService.getMdblistSavedClones(), {10: 20, 11: 21});
    await StorageService.removeMdblistSavedClone(10);
    expect(await StorageService.getMdblistSavedClones(), {11: 21});
    await StorageService.retireMdblistSavedCloneMarkers();
    expect(await StorageService.getMdblistSavedClones(), isEmpty);

    await StorageService.setMdblistSyncCheckpoint(<String, dynamic>{'k': 'v'});
    expect(await StorageService.getMdblistSyncCheckpoint(), {'k': 'v'});
    await StorageService.setMdblistSyncCheckpoint(null);
    expect(await StorageService.getMdblistSyncCheckpoint(), isNull);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'mdblist_saved_clones': 'not-json',
      'mdblist_sync_checkpoint_v1': '[1]',
    });
    expect(await StorageService.getMdblistSavedClones(), isEmpty);
    expect(await StorageService.getMdblistSyncCheckpoint(), isNull);
  });

  test('public tracking key names stay on the façade', () {
    expect(
      StorageService.trackingScrobbleTargetsKey,
      'tracking_scrobble_targets',
    );
    expect(StorageService.watchProgressSourceKey, 'watch_progress_source');
  });
}
