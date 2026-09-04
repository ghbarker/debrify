import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/player_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Write through [StorageService], read through [PlayerPrefs] / [IptvPrefs],
/// byte-equal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's23-roundtrip-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
  });

  tearDown(ProfileRuntime.debugReset);

  test(
    'StorageService player writes are readable through PlayerPrefs',
    () async {
      await StorageService.setDefaultPlayerMode('external');
      await StorageService.setPreferredExternalPlayer('vlc');
      await StorageService.setCustomExternalPlayerPath('/opt/vlc');
      await StorageService.setPreferredIOSExternalPlayer('infuse');
      await StorageService.setPlayerDefaultAspectIndex(4);
      await StorageService.setPlayerNightModeIndex(2);
      await StorageService.setSkipSegmentsEnabled(false);
      await StorageService.setSkipSegmentProvider(
        StorageService.skipSegmentProviderSkipDb,
      );
      await StorageService.setPlayerStartPortrait(true);
      await StorageService.setUiSounds(false);
      await StorageService.setSubtitleAutoSyncEnabled(true);
      await StorageService.setDefaultSubtitleLanguage('es');
      await StorageService.setNetworkConnectPatience('patient');
      await StorageService.setAndroidVideoRendererMode(
        AndroidVideoRendererMode.directSurface,
      );

      expect(await PlayerPrefs.getDefaultPlayerMode(), 'external');
      expect(await PlayerPrefs.getPreferredExternalPlayer(), 'vlc');
      expect(await PlayerPrefs.getCustomExternalPlayerPath(), '/opt/vlc');
      expect(await PlayerPrefs.getPreferredIOSExternalPlayer(), 'infuse');
      expect(await PlayerPrefs.getPlayerDefaultAspectIndex(), 4);
      expect(await PlayerPrefs.getPlayerNightModeIndex(), 2);
      expect(await PlayerPrefs.getSkipSegmentsEnabled(), isFalse);
      expect(
        await PlayerPrefs.getSkipSegmentProvider(),
        PlayerPrefs.skipSegmentProviderSkipDb,
      );
      expect(await PlayerPrefs.getPlayerStartPortrait(), isTrue);
      expect(PlayerPrefs.playerStartPortraitCached, isTrue);
      expect(await PlayerPrefs.getUiSounds(), isFalse);
      expect(await PlayerPrefs.getSubtitleAutoSyncEnabled(), isTrue);
      expect(await PlayerPrefs.getDefaultSubtitleLanguage(), 'es');
      expect(await PlayerPrefs.getNetworkConnectPatience(), 'patient');
      expect(
        await PlayerPrefs.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directSurface,
      );
    },
  );

  test('StorageService IPTV writes are readable through IptvPrefs', () async {
    await StorageService.setIptvDecoderMode('software');
    await StorageService.setIptvDefaultPlaylist('pl-1');
    await StorageService.setIptvDefaultsInitialized(true);
    await StorageService.setIptvTrackContinueWatching(false);
    await StorageService.setIptvSeriesAudioLanguage('show::1', 'deu');
    await StorageService.setStartupIptvEnabled(true);
    await StorageService.setStartupIptvMode(
      StorageService.startupIptvModePinned,
    );
    await StorageService.setIptvPlaylists([
      IptvPlaylist(
        id: 'real',
        name: 'Sports',
        url: 'https://example.com/list.m3u',
        addedAt: DateTime.utc(2024, 6, 1),
      ),
    ]);
    await StorageService.setIptvLastLiveChannel(
      'http://live.example/1',
      name: 'One',
      playlistId: 'pl-1',
    );

    expect(await IptvPrefs.getIptvDecoderMode(), 'software');
    expect(await IptvPrefs.getIptvDefaultPlaylist(), 'pl-1');
    expect(await IptvPrefs.getIptvDefaultsInitialized(), isTrue);
    expect(await IptvPrefs.getIptvTrackContinueWatching(), isFalse);
    expect(await IptvPrefs.getIptvSeriesAudioLanguage('show::1'), 'deu');
    expect(await IptvPrefs.getStartupIptvEnabled(), isTrue);
    expect(
      await IptvPrefs.getStartupIptvMode(),
      IptvPrefs.startupIptvModePinned,
    );
    final playlists = await IptvPrefs.getIptvPlaylists();
    expect(playlists, hasLength(1));
    expect(playlists.single.id, 'real');
    final live = await IptvPrefs.getIptvLastLiveChannel();
    expect(live!['url'], 'http://live.example/1');
    expect(live['name'], 'One');
  });
}
