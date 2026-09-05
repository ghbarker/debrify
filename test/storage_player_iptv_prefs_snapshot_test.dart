import 'package:debrify/services/storage/iptv_prefs.dart';
import 'dart:convert';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins player + IPTV prefs encodings on [StorageService] before the S2-3
/// extract. Key names and values are a frozen compatibility surface.
/// This file must not import the new stores — those land in the move commit.
///
/// Style keys (`player_dock_*`, `iptv_style`, `tv_player_controls_style`,
/// `debrify_tv_player_style`, …) stay on StorageService until S2-4.
/// Completion thresholds / `_getPlaybackStateMap` stay until S2-6.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's23-pin-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
  });

  tearDown(ProfileRuntime.debugReset);

  group('player prefs defaults', () {
    test('mode, external players, aspect, night, audio', () async {
      expect(await StorageService.getDefaultPlayerMode(), 'debrify');
      expect(
        await StorageService.getPreferredExternalPlayer(),
        'system_default',
      );
      expect(await StorageService.getCustomExternalPlayerPath(), isNull);
      expect(await StorageService.getCustomExternalPlayerName(), isNull);
      expect(await StorageService.getCustomExternalPlayerCommand(), isNull);
      // Quirk: iOS defaults to VLC, not system_default.
      expect(await StorageService.getPreferredIOSExternalPlayer(), 'vlc');
      expect(await StorageService.getIOSCustomSchemeTemplate(), isNull);
      expect(
        await StorageService.getPreferredLinuxExternalPlayer(),
        'system_default',
      );
      expect(await StorageService.getLinuxCustomCommand(), isNull);
      expect(
        await StorageService.getPreferredWindowsExternalPlayer(),
        'system_default',
      );
      expect(await StorageService.getWindowsCustomCommand(), isNull);

      expect(await StorageService.getPlayerDefaultAspectIndex(), 2);
      expect(await StorageService.getPlayerDefaultAspectIndexTv(), 0);
      expect(await StorageService.getPlayerNightModeIndex(), 0);
      expect(await StorageService.getPlayerSystemAudioEffects(), isFalse);
      expect(await StorageService.getAudioPassthroughEnabled(), isFalse);
      expect(await StorageService.getAppleMultichannelAudio(), isFalse);
      expect(await StorageService.getTvosForceStereoAudio(), isFalse);
      expect(await StorageService.getTvosLegacyAudioOutput(), isFalse);
      expect(await StorageService.getTvosForceSoftwareDecode(), isFalse);
    });

    test('skip segments, portrait, UI feedback, subtitles', () async {
      expect(await StorageService.getSkipSegmentsEnabled(), isTrue);
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderAuto,
      );
      expect(await StorageService.getPlayerStartPortrait(), isFalse);
      expect(StorageService.playerStartPortraitCached, isFalse);
      expect(await StorageService.getUiSounds(), isTrue);
      expect(await StorageService.getUiHaptics(), isTrue);
      expect(StorageService.uiSoundsCached, isTrue);
      expect(StorageService.uiHapticsCached, isTrue);
      expect(await StorageService.getSubtitleAutoSyncEnabled(), isFalse);
      expect(await StorageService.getDefaultSubtitleLanguage(), isNull);
      expect(await StorageService.getDefaultAudioLanguage(), isNull);
    });

    test('network tuning defaults to standard', () async {
      expect(await StorageService.getNetworkConnectPatience(), 'standard');
      expect(await StorageService.getNetworkBufferSize(), 'standard');
    });
  });

  group('iptv prefs defaults', () {
    test('decoder, playlists, last-live, startup, series audio', () async {
      expect(await StorageService.getIptvDecoderMode(), 'auto');
      expect(StorageService.iptvDecoderModes, ['auto', 'hardware', 'software']);
      expect(await IptvPrefs.getIptvPlaylists(), isEmpty);
      expect(await IptvPrefs.getIptvDefaultPlaylist(), isNull);
      expect(await IptvPrefs.getIptvDefaultsInitialized(), isFalse);
      expect(await IptvPrefs.getIptvLastLiveChannel(), isNull);
      expect(await IptvPrefs.getStartupIptvEnabled(), isFalse);
      expect(
        await IptvPrefs.getStartupIptvMode(),
        StorageService.startupIptvModeLast,
      );
      expect(await IptvPrefs.getStartupIptvChannel(), isNull);
      expect(StorageService.startupIptvChannelCached, isNull);
      expect(await IptvPrefs.getIptvSeriesAudioLanguage('any'), isNull);
      expect(await IptvPrefs.getIptvTrackContinueWatching(), isTrue);
      expect(StorageService.iptvWatchFinishedFraction, 0.95);
    });
  });

  test('StorageService writes the historical player key bytes', () async {
    await StorageService.setDefaultPlayerMode('external');
    await StorageService.setPreferredExternalPlayer('vlc');
    await StorageService.setCustomExternalPlayerPath('/opt/vlc');
    await StorageService.setCustomExternalPlayerName('VLC');
    await StorageService.setCustomExternalPlayerCommand('vlc {url}');
    await StorageService.setPreferredIOSExternalPlayer('infuse');
    await StorageService.setIOSCustomSchemeTemplate('infuse://x?url={url}');
    await StorageService.setPreferredLinuxExternalPlayer('mpv');
    await StorageService.setLinuxCustomCommand('mpv {url}');
    await StorageService.setPreferredWindowsExternalPlayer('mpc');
    await StorageService.setWindowsCustomCommand('mpc {url}');
    await StorageService.setPlayerDefaultAspectIndex(4);
    await StorageService.setPlayerDefaultAspectIndexTv(2);
    await StorageService.setPlayerNightModeIndex(3);
    await StorageService.setPlayerSystemAudioEffects(true);
    await StorageService.setAudioPassthroughEnabled(true);
    await StorageService.setAppleMultichannelAudio(true);
    await StorageService.setTvosForceStereoAudio(true);
    await StorageService.setTvosLegacyAudioOutput(true);
    await StorageService.setTvosForceSoftwareDecode(true);
    await StorageService.setSkipSegmentsEnabled(false);
    await StorageService.setSkipSegmentProvider(
      StorageService.skipSegmentProviderSkipDb,
    );
    await StorageService.setPlayerStartPortrait(true);
    await StorageService.setUiSounds(false);
    await StorageService.setUiHaptics(false);
    await StorageService.setSubtitleAutoSyncEnabled(true);
    await StorageService.setDefaultSubtitleLanguage('es');
    await StorageService.setDefaultAudioLanguage('fr');
    await StorageService.setNetworkConnectPatience('patient');
    await StorageService.setNetworkBufferSize('huge');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_player_mode'), 'external');
    expect(prefs.getString('external_player_preferred'), 'vlc');
    expect(prefs.getString('external_player_custom_path'), '/opt/vlc');
    expect(prefs.getString('external_player_custom_name'), 'VLC');
    expect(prefs.getString('external_player_custom_command'), 'vlc {url}');
    expect(prefs.getString('ios_external_player_preferred'), 'infuse');
    expect(prefs.getString('ios_custom_scheme_template'), 'infuse://x?url={url}');
    expect(prefs.getString('linux_external_player_preferred'), 'mpv');
    expect(prefs.getString('linux_custom_command'), 'mpv {url}');
    expect(prefs.getString('windows_external_player_preferred'), 'mpc');
    expect(prefs.getString('windows_custom_command'), 'mpc {url}');
    expect(prefs.getInt('player_default_aspect_index'), 4);
    expect(prefs.getInt('player_default_aspect_index_tv'), 2);
    expect(prefs.getInt('player_night_mode_index'), 3);
    expect(prefs.getBool('player_system_audio_effects'), isTrue);
    expect(prefs.getBool('player_audio_passthrough'), isTrue);
    expect(prefs.getBool('player_apple_multichannel_audio'), isTrue);
    expect(prefs.getBool('tvos_force_stereo_audio_v1'), isTrue);
    expect(prefs.getBool('tvos_legacy_audio_output_v1'), isTrue);
    expect(prefs.getBool('tvos_force_software_decode'), isTrue);
    expect(prefs.getBool('skip_segments_enabled'), isFalse);
    expect(prefs.getString('skip_segment_provider'), 'skipdb');
    expect(prefs.getBool('player_start_portrait'), isTrue);
    expect(prefs.getBool('ui_sounds'), isFalse);
    expect(prefs.getBool('ui_haptics'), isFalse);
    expect(prefs.getBool('subtitle_auto_sync_enabled'), isTrue);
    expect(prefs.getString('player_default_subtitle_language'), 'es');
    expect(prefs.getString('player_default_audio_language'), 'fr');
    expect(prefs.getString('network_connect_patience'), 'patient');
    expect(prefs.getString('network_buffer_size'), 'huge');
  });

  test('StorageService writes the historical IPTV key bytes', () async {
    await IptvPrefs.setIptvDecoderMode('software');
    await IptvPrefs.setIptvDefaultPlaylist('pl-1');
    await IptvPrefs.setIptvDefaultsInitialized(true);
    await IptvPrefs.setIptvTrackContinueWatching(false);
    await StorageService.setIptvSeriesAudioLanguage('show::1', 'deu');
    await IptvPrefs.setStartupIptvEnabled(true);
    await IptvPrefs.setStartupIptvMode(StorageService.startupIptvModePinned);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('iptv_decoder_mode'), 'software');
    expect(prefs.getString('iptv_default_playlist'), 'pl-1');
    expect(prefs.getBool('iptv_defaults_initialized'), isTrue);
    expect(prefs.getBool('iptv_track_continue_watching'), isFalse);
    expect(
      prefs.getString('iptv_series_audio_lang'),
      jsonEncode({'show::1': 'deu'}),
    );
    expect(prefs.getBool('startup_auto_launch_enabled'), isTrue);
    expect(prefs.getString('startup_mode'), 'iptv');
    expect(prefs.getString('startup_iptv_mode'), 'pinned');
  });

  test('raw player bytes round-trip through StorageService getters', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'default_player_mode': 'deovr',
      'external_player_preferred': 'mx',
      'external_player_custom_path': '/bin/mx',
      'ios_external_player_preferred': 'nplayer',
      'player_default_aspect_index': 1,
      'player_default_aspect_index_tv': 3,
      'player_night_mode_index': 7,
      'player_system_audio_effects': true,
      'player_audio_passthrough': true,
      'skip_segments_enabled': false,
      'skip_segment_provider': 'introdb',
      'player_start_portrait': true,
      'ui_sounds': false,
      'ui_haptics': false,
      'subtitle_auto_sync_enabled': true,
      'player_default_subtitle_language': 'off',
      'player_default_audio_language': 'ja',
      'network_connect_patience': 'extended',
      'network_buffer_size': 'large',
    });

    expect(await StorageService.getDefaultPlayerMode(), 'deovr');
    expect(await StorageService.getPreferredExternalPlayer(), 'mx');
    expect(await StorageService.getCustomExternalPlayerPath(), '/bin/mx');
    expect(await StorageService.getPreferredIOSExternalPlayer(), 'nplayer');
    expect(await StorageService.getPlayerDefaultAspectIndex(), 1);
    expect(await StorageService.getPlayerDefaultAspectIndexTv(), 3);
    expect(await StorageService.getPlayerNightModeIndex(), 7);
    expect(await StorageService.getPlayerSystemAudioEffects(), isTrue);
    expect(await StorageService.getAudioPassthroughEnabled(), isTrue);
    expect(await StorageService.getSkipSegmentsEnabled(), isFalse);
    expect(
      await StorageService.getSkipSegmentProvider(),
      StorageService.skipSegmentProviderIntroDb,
    );
    expect(await StorageService.getPlayerStartPortrait(), isTrue);
    expect(StorageService.playerStartPortraitCached, isTrue);
    expect(await StorageService.getUiSounds(), isFalse);
    expect(await StorageService.getUiHaptics(), isFalse);
    expect(await StorageService.getSubtitleAutoSyncEnabled(), isTrue);
    expect(await StorageService.getDefaultSubtitleLanguage(), 'off');
    expect(await StorageService.getDefaultAudioLanguage(), 'ja');
    expect(await StorageService.getNetworkConnectPatience(), 'extended');
    expect(await StorageService.getNetworkBufferSize(), 'large');
  });

  test(
    'empty custom player path/name/command remove the key; subtitle empty stores',
    () async {
      await StorageService.setCustomExternalPlayerPath('/x');
      await StorageService.setCustomExternalPlayerName('X');
      await StorageService.setCustomExternalPlayerCommand('x {url}');
      await StorageService.setIOSCustomSchemeTemplate('x://{url}');
      await StorageService.setLinuxCustomCommand('x {url}');
      await StorageService.setWindowsCustomCommand('x {url}');
      await StorageService.setDefaultSubtitleLanguage('en');
      await StorageService.setDefaultAudioLanguage('en');

      await StorageService.setCustomExternalPlayerPath('');
      await StorageService.setCustomExternalPlayerName('');
      await StorageService.setCustomExternalPlayerCommand('');
      await StorageService.setIOSCustomSchemeTemplate('');
      await StorageService.setLinuxCustomCommand('');
      await StorageService.setWindowsCustomCommand('');
      // Quirk: subtitle/audio treat only null as clear; empty string persists.
      await StorageService.setDefaultSubtitleLanguage('');
      await StorageService.setDefaultAudioLanguage('');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('external_player_custom_path'), isFalse);
      expect(prefs.containsKey('external_player_custom_name'), isFalse);
      expect(prefs.containsKey('external_player_custom_command'), isFalse);
      expect(prefs.containsKey('ios_custom_scheme_template'), isFalse);
      expect(prefs.containsKey('linux_custom_command'), isFalse);
      expect(prefs.containsKey('windows_custom_command'), isFalse);
      expect(prefs.getString('player_default_subtitle_language'), '');
      expect(prefs.getString('player_default_audio_language'), '');

      await StorageService.setDefaultSubtitleLanguage(null);
      await StorageService.setDefaultAudioLanguage(null);
      expect(prefs.containsKey('player_default_subtitle_language'), isFalse);
      expect(prefs.containsKey('player_default_audio_language'), isFalse);
    },
  );

  test(
    'clearExternalPlayerSettings drops Android keys only, not iOS/Linux/Windows',
    () async {
      await StorageService.setDefaultPlayerMode('external');
      await StorageService.setPreferredExternalPlayer('vlc');
      await StorageService.setCustomExternalPlayerPath('/opt/vlc');
      await StorageService.setPreferredIOSExternalPlayer('infuse');
      await StorageService.setPreferredLinuxExternalPlayer('mpv');
      await StorageService.setPreferredWindowsExternalPlayer('mpc');

      await StorageService.clearExternalPlayerSettings();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('default_player_mode'), isFalse);
      expect(prefs.containsKey('external_player_preferred'), isFalse);
      expect(prefs.containsKey('external_player_custom_path'), isFalse);
      // Quirk: platform-specific preferred players survive the clear helper.
      expect(prefs.getString('ios_external_player_preferred'), 'infuse');
      expect(prefs.getString('linux_external_player_preferred'), 'mpv');
      expect(prefs.getString('windows_external_player_preferred'), 'mpc');
      expect(await StorageService.getDefaultPlayerMode(), 'debrify');
    },
  );

  test('unknown skip-segment provider reads and writes as auto', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'skip_segment_provider': 'removed_vendor',
    });
    expect(
      await StorageService.getSkipSegmentProvider(),
      StorageService.skipSegmentProviderAuto,
    );

    await StorageService.setSkipSegmentProvider('also-unknown');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('skip_segment_provider'), 'auto');
  });

  test('uiSoundsCached is published before the prefs write', () async {
    expect(StorageService.uiSoundsCached, isTrue);
    final pending = StorageService.setUiSounds(false);
    expect(StorageService.uiSoundsCached, isFalse);
    await pending;
    expect(await StorageService.getUiSounds(), isFalse);
  });

  test('Android renderer first read migrates null/direct_surface once', () async {
    expect(
      await StorageService.getAndroidVideoRendererMode(),
      AndroidVideoRendererMode.directMediaCodec,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('android_video_renderer_mode'), 'direct_mediacodec');
    expect(prefs.getBool('android_video_renderer_gpu_migration_v1'), isTrue);
  });

  test('unknown IPTV decoder and startup mode coerce on write', () async {
    await IptvPrefs.setIptvDecoderMode('vulkan');
    await IptvPrefs.setStartupIptvMode('random');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('iptv_decoder_mode'), 'auto');
    expect(prefs.getString('startup_iptv_mode'), 'last');
    expect(await StorageService.getIptvDecoderMode(), 'auto');
    expect(
      await IptvPrefs.getStartupIptvMode(),
      StorageService.startupIptvModeLast,
    );
  });

  test('network tuning does not coerce unknown values', () async {
    await StorageService.setNetworkConnectPatience('turbo');
    await StorageService.setNetworkBufferSize('tiny');
    expect(await StorageService.getNetworkConnectPatience(), 'turbo');
    expect(await StorageService.getNetworkBufferSize(), 'tiny');
  });

  test('IPTV series audio empty key/lang is a no-op', () async {
    await StorageService.setIptvSeriesAudioLanguage('', 'eng');
    await StorageService.setIptvSeriesAudioLanguage('show', '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('iptv_series_audio_lang'), isFalse);
  });

  test('IPTV series audio malformed JSON reads null', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'iptv_series_audio_lang': 'not-json',
    });
    expect(await IptvPrefs.getIptvSeriesAudioLanguage('show'), isNull);
  });

  test('virtual IPTV playlists are dropped; secrets are sealed', () async {
    final addedAt = DateTime.utc(2024, 6, 1, 12);
    await IptvPrefs.setIptvPlaylists([
      IptvPlaylist(
        id: 'fav',
        name: 'Favorites',
        url: 'favorites://',
        addedAt: addedAt,
      ),
      IptvPlaylist(
        id: 'real',
        name: 'Sports',
        url: 'https://user:pass@example.com/list.m3u',
        addedAt: addedAt,
      ),
    ]);

    final stored = await IptvPrefs.getIptvPlaylists();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'real');
    expect(stored.single.url, 'https://user:pass@example.com/list.m3u');

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('iptv_playlists')!;
    expect(rawList, hasLength(1));
    final raw = jsonDecode(rawList.single) as Map<String, dynamic>;
    expect(raw['url'], startsWith(SecretVault.prefix));
    expect(raw['id'], 'real');
  });

  test('empty default playlist id removes the key', () async {
    await IptvPrefs.setIptvDefaultPlaylist('pl');
    await IptvPrefs.setIptvDefaultPlaylist('');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('iptv_default_playlist'), isFalse);
  });

  test('last-live empty url is a no-op; blob is SecretVault-sealed', () async {
    await StorageService.setIptvLastLiveChannel(
      '',
      name: 'ignored',
    );
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('iptv_last_live_channel'), isFalse);

    await StorageService.setIptvLastLiveChannel(
      'http://live.example/1',
      name: 'One',
      playlistId: 'pl',
      channelNumber: 7,
    );
    prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('iptv_last_live_channel'),
      startsWith(SecretVault.prefix),
    );
    final blob = await IptvPrefs.getIptvLastLiveChannel();
    expect(blob!['url'], 'http://live.example/1');
    expect(blob['name'], 'One');
    expect(blob['playlistId'], 'pl');
    expect(blob['channelNumber'], 7);
    expect(blob['playedAt'], isA<int>());

    await IptvPrefs.clearIptvLastLiveChannel();
    expect(await IptvPrefs.getIptvLastLiveChannel(), isNull);
  });

  test('malformed last-live and startup channel blobs read as null', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'iptv_last_live_channel': 'not-json',
      'startup_iptv_channel': 'not-json',
    });
    expect(await IptvPrefs.getIptvLastLiveChannel(), isNull);
    expect(await IptvPrefs.getStartupIptvChannel(), isNull);
  });

  test(
    'setStartupIptvEnabled(false) clears startup_mode despite the comment',
    () async {
      await IptvPrefs.setStartupIptvEnabled(true);
      await IptvPrefs.setStartupIptvEnabled(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('startup_auto_launch_enabled'), isFalse);
      // Comment says "leave the mode behind"; the body removes it.
      expect(prefs.containsKey('startup_mode'), isFalse);
      expect(await IptvPrefs.getStartupIptvEnabled(), isFalse);
    },
  );

  test('warmStartupIptv last-with-no-channel sets firstAvailable', () async {
    await IptvPrefs.setStartupIptvEnabled(true);
    await IptvPrefs.setStartupIptvMode(StorageService.startupIptvModeLast);
    await IptvPrefs.warmStartupIptv();
    expect(StorageService.startupIptvChannelCached, {
      StorageService.startupIptvFirstAvailable: true,
    });
  });

  test('warmStartupIptv pinned-with-no-channel leaves cache null', () async {
    await IptvPrefs.setStartupIptvEnabled(true);
    await IptvPrefs.setStartupIptvMode(
      StorageService.startupIptvModePinned,
    );
    await IptvPrefs.warmStartupIptv();
    expect(StorageService.startupIptvChannelCached, isNull);
  });

  test('warmStartupIptv is a no-op when startup is disabled', () async {
    await StorageService.setIptvLastLiveChannel(
      'http://live.example/1',
      name: 'One',
    );
    await IptvPrefs.warmStartupIptv();
    expect(StorageService.startupIptvChannelCached, isNull);
  });

  test(
    'clearAllStartupSettings removes IPTV last-live and startup IPTV keys',
    () async {
      await StorageService.setIptvLastLiveChannel(
        'http://live.example/1',
        name: 'One',
      );
      await IptvPrefs.setStartupIptvEnabled(true);
      await IptvPrefs.setStartupIptvMode(
        StorageService.startupIptvModePinned,
      );
      await IptvPrefs.setStartupIptvChannel(
        'http://live.example/2',
        name: 'Two',
      );

      await StorageService.clearAllStartupSettings();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('iptv_last_live_channel'), isFalse);
      expect(prefs.containsKey('startup_iptv_mode'), isFalse);
      expect(prefs.containsKey('startup_iptv_channel'), isFalse);
      expect(prefs.containsKey('startup_auto_launch_enabled'), isFalse);
    },
  );

  test(
    'IPTV track-continue-watching off makes recordIptvWatch a no-op',
    () async {
      await IptvPrefs.setIptvTrackContinueWatching(false);
      await StorageService.recordIptvWatch(
        'http://vod.example/1',
        channelName: 'Movie',
      );
      // Tracking-off gates getIptvContinueWatching before the media store.
      expect(await IptvPrefs.getIptvContinueWatching(), isEmpty);
    },
  );
}
