import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(ProfileRuntime.debugReset);

  test('absent legacy scrobble switches seed all tracker masters on', () async {
    final targets = await TrackingPrefs.getTrackingScrobbleTargets();

    expect(targets, Set<TrackingSource>.of(TrackingSource.values));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(StorageService.trackingScrobbleTargetsKey),
      isNotNull,
    );
  });

  test('legacy values are consulted once when seeding masters', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'trakt_sync_catalog_items': false,
      'mdblist_sync_catalog_items': false,
    });

    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });

    await TrackingPrefs.setTraktSyncCatalogItems(true);
    await TrackingPrefs.setSimklSyncCatalogItems(false);
    await TrackingPrefs.setMdblistSyncCatalogItems(true);
    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('connecting a tracker re-enables only that scrobble target', () async {
    for (final source in const <TrackingSource>[
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    ]) {
      await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });

      await TrackingPrefs.enableTrackingScrobbleTarget(source);

      expect(
        await TrackingPrefs.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local, source},
      );
    }
  });

  test('re-enabling an active scrobble target is idempotent', () async {
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
    final revision = StorageService.trackingSourceRevision.value;

    await TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.simkl);

    expect(StorageService.trackingSourceRevision.value, revision);
    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('re-enabling a tracker preserves other scrobble choices', () async {
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });

    await TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.simkl);

    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.simkl,
    });
  });

  test('simultaneous tracker connections merge every target', () async {
    await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });

    await Future.wait(<Future<void>>[
      TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.trakt),
      TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.simkl),
      TrackingPrefs.enableTrackingScrobbleTarget(TrackingSource.mdblist),
    ]);

    expect(
      await TrackingPrefs.getTrackingScrobbleTargets(),
      Set<TrackingSource>.of(TrackingSource.values),
    );
  });

  test(
    'legacy reseed after an old-backup restore re-adopts restored switches',
    () async {
      // App start seeds the masters (all ON) before any restore happens.
      expect(
        await TrackingPrefs.getTrackingScrobbleTargets(),
        Set<TrackingSource>.of(TrackingSource.values),
      );

      // An old backup's tracker sections then restore the legacy switches —
      // Trakt/Simkl hardcode ON, MDBList carries its saved value (OFF here).
      await TrackingPrefs.setTraktSyncCatalogItems(true);
      await TrackingPrefs.setSimklSyncCatalogItems(true);
      await TrackingPrefs.setMdblistSyncCatalogItems(false);

      // Without the reseed the already-seeded masters would ignore that OFF.
      await TrackingPrefs.reseedTrackingScrobbleTargetsFromLegacy();
      expect(
        await TrackingPrefs.getTrackingScrobbleTargets(),
        <TrackingSource>{
          TrackingSource.local,
          TrackingSource.trakt,
          TrackingSource.simkl,
        },
      );
    },
  );

  test('tracking transfer payload round-trips all three preferences', () async {
    await TrackingPrefs.applyTrackingPreferencesPayload(<String, dynamic>{
      'scrobble_targets': <String>['trakt'],
      'progress_source': 'trakt',
      'home_tick_sources': <String>['local', 'simkl'],
    });

    final payload = await TrackingPrefs.buildTrackingPreferencesPayload();
    expect(
      payload['scrobble_targets'],
      containsAll(<String>['local', 'trakt']),
    );
    expect(payload['progress_source'], 'trakt');
    expect(
      payload['home_tick_sources'],
      containsAll(<String>['local', 'simkl']),
    );
  });

  test('a disconnected dedicated progress source falls back visibly', () async {
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.trakt);

    final policy = await TrackingSourcePolicy.load();

    expect(policy.progressSource, WatchProgressSource.smart);
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isTrue);
    expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isFalse);
  });

  test(
    'partial backup restore leaves tracking preferences untouched',
    () async {
      await TrackingPrefs.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });
      await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
      await TrackingPrefs.setHomeTickSources(<TrackingSource>{
        TrackingSource.local,
      });

      await BackupRestoreService.applyBackup(
        <String, dynamic>{
          'trackingPreferences': <String, dynamic>{
            'scrobble_targets': <String>['local', 'trakt'],
            'progress_source': 'smart',
            'home_tick_sources': <String>['trakt'],
          },
        },
        selection: const BackupSelection(
          realDebrid: false,
          torbox: false,
          premiumize: false,
          allDebrid: false,
          pikpak: false,
          trakt: false,
          simkl: false,
          mdblist: false,
          searchEngines: false,
          addons: false,
          webDav: false,
          indexerManagers: false,
          iptvPlaylists: false,
          iptvFavorites: false,
          iptvLists: false,
        ),
      );

      expect(
        await TrackingPrefs.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local},
      );
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.local,
      );
      expect(await TrackingPrefs.getHomeTickSources(), <TrackingSource>{
        TrackingSource.local,
      });
    },
  );

  test('full backup restore applies tracking preferences', () async {
    await BackupRestoreService.applyBackup(<String, dynamic>{
      'trackingPreferences': <String, dynamic>{
        'scrobble_targets': <String>['local', 'simkl'],
        'progress_source': 'local',
        'home_tick_sources': <String>['mdblist'],
      },
    });

    expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.local,
    );
    expect(await TrackingPrefs.getHomeTickSources(), <TrackingSource>{
      TrackingSource.mdblist,
    });
  });
}
