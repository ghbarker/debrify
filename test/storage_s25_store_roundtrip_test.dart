import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Write through [StorageService], read through [TrackingPrefs], byte-equal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's25-roundtrip-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
    StorageService.trackingSourceRevision.value = 0;
    HideWatchedPrefs.debugReset();
  });

  tearDown(() {
    HideWatchedPrefs.debugReset();
    ProfileRuntime.debugReset();
  });

  test(
    'StorageService tracking writes are readable through TrackingPrefs',
    () async {
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
      await TrackingPrefs.setTraktAccessToken('trakt-access');
      await TrackingPrefs.setTraktRefreshToken('trakt-refresh');
      await TrackingPrefs.setTraktUsername('trakt-user');
      await TrackingPrefs.setTraktTokenExpiry(42);
      await TrackingPrefs.setSimklAccessToken('simkl-access');
      await TrackingPrefs.setSimklUsername('simkl-user');
      await TrackingPrefs.saveMdblistApiKey('mdb-key');
      await TrackingPrefs.setMdblistUsername('mdb-user');
      await TrackingPrefs.setMdblistSavedClone(3, 4);
      await TrackingPrefs.setMdblistSyncCheckpoint(<String, dynamic>{
        'cursor': 'z',
      });

      expect(await TrackingPrefs.getTrackingScrobbleTargets(), <TrackingSource>{
        TrackingSource.local,
        TrackingSource.trakt,
      });
      expect(
        await TrackingPrefs.getWatchProgressSource(),
        WatchProgressSource.simkl,
      );
      expect(await TrackingPrefs.getHomeTickSources(), <TrackingSource>{
        TrackingSource.local,
        TrackingSource.mdblist,
      });
      expect(await TrackingPrefs.getTraktSyncCatalogItems(), isTrue);
      expect(await TrackingPrefs.getSimklSyncCatalogItems(), isTrue);
      expect(await TrackingPrefs.getMdblistSyncCatalogItems(), isTrue);
      expect(await TrackingPrefs.getTraktAccessToken(), 'trakt-access');
      expect(await TrackingPrefs.getTraktRefreshToken(), 'trakt-refresh');
      expect(await TrackingPrefs.getTraktUsername(), 'trakt-user');
      expect(await TrackingPrefs.getTraktTokenExpiry(), 42);
      expect(await TrackingPrefs.getSimklAccessToken(), 'simkl-access');
      expect(await TrackingPrefs.getSimklUsername(), 'simkl-user');
      expect(await TrackingPrefs.getMdblistApiKey(), 'mdb-key');
      expect(await TrackingPrefs.getMdblistUsername(), 'mdb-user');
      expect(await TrackingPrefs.getMdblistSavedClones(), {3: 4});
      expect(await TrackingPrefs.getMdblistSyncCheckpoint(), {'cursor': 'z'});
      expect(TrackingPrefs.trackingSourceRevision.value, greaterThan(0));
      expect(
        StorageService.trackingSourceRevision,
        same(TrackingPrefs.trackingSourceRevision),
      );
    },
  );

  test('unknown progress source coerces the same on both APIs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'watch_progress_source': 'plex',
    });
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    expect(
      await TrackingPrefs.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
  });

  test('façade revision notifier is the store instance', () async {
    final before = TrackingPrefs.trackingSourceRevision.value;
    await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
    expect(TrackingPrefs.trackingSourceRevision.value, before + 1);
    expect(
      StorageService.trackingSourceRevision.value,
      TrackingPrefs.trackingSourceRevision.value,
    );
  });
}
