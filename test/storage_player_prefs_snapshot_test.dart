import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins in-app / external-player encodings on [StorageService] before the G3
/// PlayerPrefs move. Key names and values are a frozen compatibility surface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageService.playerStartPortraitCached = false;
  });

  test('PlayerPrefs defaults when no keys are stored', () async {
    expect(await StorageService.getDefaultPlayerMode(), 'debrify');
    expect(await StorageService.getPreferredExternalPlayer(), 'system_default');
    expect(await StorageService.getCustomExternalPlayerPath(), isNull);
    expect(await StorageService.getCustomExternalPlayerName(), isNull);
    expect(await StorageService.getCustomExternalPlayerCommand(), isNull);
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
    expect(await StorageService.getPlayerStartPortrait(), isFalse);
    expect(StorageService.playerStartPortraitCached, isFalse);
    expect(await StorageService.getTvosForceSoftwareDecode(), isFalse);
    expect(await StorageService.getAudioPassthroughEnabled(), isFalse);
    expect(await StorageService.getAppleMultichannelAudio(), isFalse);
    expect(await StorageService.getTvosForceStereoAudio(), isFalse);
    expect(await StorageService.getTvosLegacyAudioOutput(), isFalse);
    expect(await StorageService.getSubtitleAutoSyncEnabled(), isFalse);
    expect(await StorageService.getDefaultSubtitleLanguage(), isNull);
    expect(await StorageService.getDefaultAudioLanguage(), isNull);
    expect(await StorageService.getSkipSegmentsEnabled(), isTrue);
    expect(
      await StorageService.getSkipSegmentProvider(),
      StorageService.skipSegmentProviderAuto,
    );
    expect(await StorageService.getPlayerDockStyle(), 'classic');
    expect(await StorageService.getPlayerDockPalette(), 'ultraviolet');
    expect(await StorageService.getPlayerDockSize(), 'auto');
    expect(await StorageService.getTvPlayerControlsStyle(), 'marquee');
    expect(await StorageService.getDebrifyTvPlayerStyle(), 'cinema');
    expect(await StorageService.getPlayLoaderStyle(), 'marquee');
  });

  test('StorageService writes the historical PlayerPrefs key bytes', () async {
    await StorageService.setDefaultPlayerMode('external');
    await StorageService.setPreferredExternalPlayer('vlc');
    await StorageService.setCustomExternalPlayerPath('/usr/bin/mpv');
    await StorageService.setCustomExternalPlayerName('mpv');
    await StorageService.setCustomExternalPlayerCommand('mpv {url}');
    await StorageService.setPreferredIOSExternalPlayer('infuse');
    await StorageService.setIOSCustomSchemeTemplate(
      'infuse://x-callback-url/play?url={url}',
    );
    await StorageService.setPreferredLinuxExternalPlayer('mpv');
    await StorageService.setLinuxCustomCommand('mpv --fullscreen {url}');
    await StorageService.setPreferredWindowsExternalPlayer('vlc');
    await StorageService.setWindowsCustomCommand('vlc --fullscreen {url}');
    await StorageService.setPlayerDefaultAspectIndex(4);
    await StorageService.setPlayerDefaultAspectIndexTv(2);
    await StorageService.setPlayerNightModeIndex(3);
    await StorageService.setPlayerSystemAudioEffects(true);
    await StorageService.setPlayerStartPortrait(true);
    await StorageService.setTvosForceSoftwareDecode(true);
    await StorageService.setAudioPassthroughEnabled(true);
    await StorageService.setAppleMultichannelAudio(true);
    await StorageService.setTvosForceStereoAudio(true);
    await StorageService.setTvosLegacyAudioOutput(true);
    await StorageService.setSubtitleAutoSyncEnabled(true);
    await StorageService.setDefaultSubtitleLanguage('en');
    await StorageService.setDefaultAudioLanguage('ja');
    await StorageService.setSkipSegmentsEnabled(false);
    await StorageService.setSkipSegmentProvider(
      StorageService.skipSegmentProviderSkipDb,
    );
    await StorageService.setPlayerDockStyle('cinema');
    await StorageService.setPlayerDockPalette('ice');
    await StorageService.setPlayerDockSize('large');
    await StorageService.setTvPlayerControlsStyle('frost');
    await StorageService.setDebrifyTvPlayerStyle('prestige');
    await StorageService.setPlayLoaderStyle('classic');
    await StorageService.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.automatic,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_player_mode'), 'external');
    expect(prefs.getString('external_player_preferred'), 'vlc');
    expect(prefs.getString('external_player_custom_path'), '/usr/bin/mpv');
    expect(prefs.getString('external_player_custom_name'), 'mpv');
    expect(prefs.getString('external_player_custom_command'), 'mpv {url}');
    expect(prefs.getString('ios_external_player_preferred'), 'infuse');
    expect(
      prefs.getString('ios_custom_scheme_template'),
      'infuse://x-callback-url/play?url={url}',
    );
    expect(prefs.getString('linux_external_player_preferred'), 'mpv');
    expect(prefs.getString('linux_custom_command'), 'mpv --fullscreen {url}');
    expect(prefs.getString('windows_external_player_preferred'), 'vlc');
    expect(prefs.getString('windows_custom_command'), 'vlc --fullscreen {url}');
    expect(prefs.getInt('player_default_aspect_index'), 4);
    expect(prefs.getInt('player_default_aspect_index_tv'), 2);
    expect(prefs.getInt('player_night_mode_index'), 3);
    expect(prefs.getBool('player_system_audio_effects'), isTrue);
    expect(prefs.getBool('player_start_portrait'), isTrue);
    expect(StorageService.playerStartPortraitCached, isTrue);
    expect(prefs.getBool('tvos_force_software_decode'), isTrue);
    expect(prefs.getBool('player_audio_passthrough'), isTrue);
    expect(prefs.getBool('player_apple_multichannel_audio'), isTrue);
    expect(prefs.getBool('tvos_force_stereo_audio_v1'), isTrue);
    expect(prefs.getBool('tvos_legacy_audio_output_v1'), isTrue);
    expect(prefs.getBool('subtitle_auto_sync_enabled'), isTrue);
    expect(prefs.getString('player_default_subtitle_language'), 'en');
    expect(prefs.getString('player_default_audio_language'), 'ja');
    expect(prefs.getBool('skip_segments_enabled'), isFalse);
    expect(prefs.getString('skip_segment_provider'), 'skipdb');
    expect(prefs.getString('player_dock_style'), 'cinema');
    expect(prefs.getString('player_dock_palette'), 'ice');
    expect(prefs.getString('player_dock_size'), 'large');
    expect(prefs.getString('tv_player_controls_style'), 'frost');
    expect(prefs.getString('debrify_tv_player_style'), 'prestige');
    expect(prefs.getString('play_loader_style'), 'classic');
    expect(prefs.getString('android_video_renderer_mode'), 'automatic');
    expect(prefs.getBool('android_video_renderer_gpu_migration_v1'), isTrue);
  });

  test(
    'raw PlayerPrefs bytes round-trip through StorageService getters',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'default_player_mode': 'deovr',
        'external_player_preferred': 'mxplayer',
        'external_player_custom_path': 'C:\\Players\\vlc.exe',
        'external_player_custom_name': 'VLC',
        'external_player_custom_command': 'vlc {url} --meta-title={title}',
        'ios_external_player_preferred': 'outplayer',
        'ios_custom_scheme_template': 'outplayer://{url}',
        'linux_external_player_preferred': 'custom',
        'linux_custom_command': 'mpv {url}',
        'windows_external_player_preferred': 'custom',
        'windows_custom_command': 'mpc-hc {url}',
        'player_default_aspect_index': 10,
        'player_default_aspect_index_tv': 3,
        'player_night_mode_index': 7,
        'player_system_audio_effects': true,
        'player_start_portrait': true,
        'tvos_force_software_decode': true,
        'player_audio_passthrough': true,
        'player_apple_multichannel_audio': true,
        'tvos_force_stereo_audio_v1': true,
        'tvos_legacy_audio_output_v1': true,
        'subtitle_auto_sync_enabled': true,
        'player_default_subtitle_language': 'off',
        'player_default_audio_language': 'fr',
        'skip_segments_enabled': false,
        'skip_segment_provider': 'introdb',
        'player_dock_style': 'tiers',
        'player_dock_palette': 'aurum',
        'player_dock_size': 'small',
        'tv_player_controls_style': 'ticket',
        'debrify_tv_player_style': 'guide',
        'play_loader_style': 'classic',
        'android_video_renderer_mode': 'direct_surface',
        'android_video_renderer_gpu_migration_v1': true,
      });

      expect(await StorageService.getDefaultPlayerMode(), 'deovr');
      expect(await StorageService.getPreferredExternalPlayer(), 'mxplayer');
      expect(
        await StorageService.getCustomExternalPlayerPath(),
        'C:\\Players\\vlc.exe',
      );
      expect(await StorageService.getCustomExternalPlayerName(), 'VLC');
      expect(
        await StorageService.getCustomExternalPlayerCommand(),
        'vlc {url} --meta-title={title}',
      );
      expect(await StorageService.getPreferredIOSExternalPlayer(), 'outplayer');
      expect(
        await StorageService.getIOSCustomSchemeTemplate(),
        'outplayer://{url}',
      );
      expect(await StorageService.getPreferredLinuxExternalPlayer(), 'custom');
      expect(await StorageService.getLinuxCustomCommand(), 'mpv {url}');
      expect(
        await StorageService.getPreferredWindowsExternalPlayer(),
        'custom',
      );
      expect(await StorageService.getWindowsCustomCommand(), 'mpc-hc {url}');
      expect(await StorageService.getPlayerDefaultAspectIndex(), 10);
      expect(await StorageService.getPlayerDefaultAspectIndexTv(), 3);
      expect(await StorageService.getPlayerNightModeIndex(), 7);
      expect(await StorageService.getPlayerSystemAudioEffects(), isTrue);
      expect(await StorageService.getPlayerStartPortrait(), isTrue);
      expect(StorageService.playerStartPortraitCached, isTrue);
      expect(await StorageService.getTvosForceSoftwareDecode(), isTrue);
      expect(await StorageService.getAudioPassthroughEnabled(), isTrue);
      expect(await StorageService.getAppleMultichannelAudio(), isTrue);
      expect(await StorageService.getTvosForceStereoAudio(), isTrue);
      expect(await StorageService.getTvosLegacyAudioOutput(), isTrue);
      expect(await StorageService.getSubtitleAutoSyncEnabled(), isTrue);
      expect(await StorageService.getDefaultSubtitleLanguage(), 'off');
      expect(await StorageService.getDefaultAudioLanguage(), 'fr');
      expect(await StorageService.getSkipSegmentsEnabled(), isFalse);
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderIntroDb,
      );
      expect(await StorageService.getPlayerDockStyle(), 'tiers');
      expect(await StorageService.getPlayerDockPalette(), 'aurum');
      expect(await StorageService.getPlayerDockSize(), 'small');
      expect(await StorageService.getTvPlayerControlsStyle(), 'ticket');
      expect(await StorageService.getDebrifyTvPlayerStyle(), 'guide');
      expect(await StorageService.getPlayLoaderStyle(), 'classic');
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directSurface,
      );
    },
  );

  test(
    'empty custom-player strings remove the key; language null removes',
    () async {
      await StorageService.setCustomExternalPlayerPath('/bin/vlc');
      await StorageService.setCustomExternalPlayerName('VLC');
      await StorageService.setCustomExternalPlayerCommand('vlc {url}');
      await StorageService.setIOSCustomSchemeTemplate('vlc://{url}');
      await StorageService.setLinuxCustomCommand('vlc {url}');
      await StorageService.setWindowsCustomCommand('vlc {url}');
      await StorageService.setDefaultSubtitleLanguage('en');
      await StorageService.setDefaultAudioLanguage('de');

      await StorageService.setCustomExternalPlayerPath('');
      await StorageService.setCustomExternalPlayerName('');
      await StorageService.setCustomExternalPlayerCommand('');
      await StorageService.setIOSCustomSchemeTemplate('');
      await StorageService.setLinuxCustomCommand('');
      await StorageService.setWindowsCustomCommand('');
      await StorageService.setDefaultSubtitleLanguage(null);
      await StorageService.setDefaultAudioLanguage(null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('external_player_custom_path'), isFalse);
      expect(prefs.containsKey('external_player_custom_name'), isFalse);
      expect(prefs.containsKey('external_player_custom_command'), isFalse);
      expect(prefs.containsKey('ios_custom_scheme_template'), isFalse);
      expect(prefs.containsKey('linux_custom_command'), isFalse);
      expect(prefs.containsKey('windows_custom_command'), isFalse);
      expect(prefs.containsKey('player_default_subtitle_language'), isFalse);
      expect(prefs.containsKey('player_default_audio_language'), isFalse);

      await StorageService.setCustomExternalPlayerPath(null);
      await StorageService.setCustomExternalPlayerName(null);
      await StorageService.setCustomExternalPlayerCommand(null);
      await StorageService.setIOSCustomSchemeTemplate(null);
      await StorageService.setLinuxCustomCommand(null);
      await StorageService.setWindowsCustomCommand(null);
      expect(prefs.containsKey('external_player_custom_path'), isFalse);
      expect(prefs.containsKey('external_player_custom_name'), isFalse);
      expect(prefs.containsKey('external_player_custom_command'), isFalse);
      expect(prefs.containsKey('ios_custom_scheme_template'), isFalse);
      expect(prefs.containsKey('linux_custom_command'), isFalse);
      expect(prefs.containsKey('windows_custom_command'), isFalse);

      // Quirk: empty language string is stored, unlike custom-player paths.
      await StorageService.setDefaultSubtitleLanguage('');
      await StorageService.setDefaultAudioLanguage('');
      expect(prefs.getString('player_default_subtitle_language'), '');
      expect(prefs.getString('player_default_audio_language'), '');
    },
  );

  test('player dock two_tier is accepted and unknown styles coerce', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'player_dock_style': 'two_tier',
    });
    // Quirk: 'two_tier' stays in the accepted set (same meaning as 'auto'
    // for the dock widget). Storage does not rewrite it to 'auto'.
    expect(await StorageService.getPlayerDockStyle(), 'two_tier');

    await StorageService.setPlayerDockStyle('two_tier');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('player_dock_style'), 'two_tier');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'player_dock_style': 'not-a-dock',
      'player_dock_palette': 'neon',
      'player_dock_size': 'huge',
    });
    expect(await StorageService.getPlayerDockStyle(), 'classic');
    expect(await StorageService.getPlayerDockPalette(), 'ultraviolet');
    expect(await StorageService.getPlayerDockSize(), 'auto');

    await StorageService.setPlayerDockStyle('garbage');
    await StorageService.setPlayerDockPalette('garbage');
    await StorageService.setPlayerDockSize('garbage');
    final after = await SharedPreferences.getInstance();
    expect(after.getString('player_dock_style'), 'classic');
    expect(after.getString('player_dock_palette'), 'ultraviolet');
    expect(after.getString('player_dock_size'), 'auto');

    for (final style in <String>[
      'classic',
      'auto',
      'compact',
      'tiers',
      'cinema',
      'two_tier',
    ]) {
      await StorageService.setPlayerDockStyle(style);
      expect(await StorageService.getPlayerDockStyle(), style);
      expect(after.getString('player_dock_style'), style);
    }
    for (final palette in <String>['ultraviolet', 'crimson', 'aurum', 'ice']) {
      await StorageService.setPlayerDockPalette(palette);
      expect(await StorageService.getPlayerDockPalette(), palette);
    }
    for (final size in <String>['auto', 'small', 'medium', 'large']) {
      await StorageService.setPlayerDockSize(size);
      expect(await StorageService.getPlayerDockSize(), size);
    }
  });

  test(
    'play loader / TV / Debrify TV player styles coerce unknown both ways',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'play_loader_style': 'spinner',
        'tv_player_controls_style': 'legacy',
        'debrify_tv_player_style': 'espn',
      });
      expect(await StorageService.getPlayLoaderStyle(), 'marquee');
      expect(await StorageService.getTvPlayerControlsStyle(), 'marquee');
      expect(await StorageService.getDebrifyTvPlayerStyle(), 'cinema');

      await StorageService.setPlayLoaderStyle('not-a-loader');
      await StorageService.setTvPlayerControlsStyle('not-a-skin');
      await StorageService.setDebrifyTvPlayerStyle('not-a-bar');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('play_loader_style'), 'marquee');
      expect(prefs.getString('tv_player_controls_style'), 'marquee');
      expect(prefs.getString('debrify_tv_player_style'), 'cinema');

      for (final style in <String>['marquee', 'classic']) {
        await StorageService.setPlayLoaderStyle(style);
        expect(await StorageService.getPlayLoaderStyle(), style);
        expect(prefs.getString('play_loader_style'), style);
      }
      for (final style in <String>[
        'classic',
        'ott',
        'frost',
        'marquee',
        'broadcast',
        'pulse',
        'ticket',
      ]) {
        await StorageService.setTvPlayerControlsStyle(style);
        expect(await StorageService.getTvPlayerControlsStyle(), style);
        expect(prefs.getString('tv_player_controls_style'), style);
      }
      for (final style in <String>[
        'classic',
        'network',
        'cinema',
        'guide',
        'spotlight',
        'prestige',
      ]) {
        await StorageService.setDebrifyTvPlayerStyle(style);
        expect(await StorageService.getDebrifyTvPlayerStyle(), style);
        expect(prefs.getString('debrify_tv_player_style'), style);
      }
    },
  );

  test('skip-segment provider unknown falls back to auto both ways', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'skip_segment_provider': 'gone',
    });
    expect(
      await StorageService.getSkipSegmentProvider(),
      StorageService.skipSegmentProviderAuto,
    );

    await StorageService.setSkipSegmentProvider('also-gone');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('skip_segment_provider'), 'auto');

    for (final provider in <String>[
      StorageService.skipSegmentProviderAuto,
      StorageService.skipSegmentProviderSkipDb,
      StorageService.skipSegmentProviderIntroDb,
      StorageService.skipSegmentProviderTheIntroDb,
    ]) {
      await StorageService.setSkipSegmentProvider(provider);
      expect(await StorageService.getSkipSegmentProvider(), provider);
      expect(prefs.getString('skip_segment_provider'), provider);
    }
  });

  test('default player mode writes any string; no coercion table', () async {
    await StorageService.setDefaultPlayerMode('not-a-mode');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_player_mode'), 'not-a-mode');
    expect(await StorageService.getDefaultPlayerMode(), 'not-a-mode');
  });

  test(
    'Android renderer migrates null/direct_surface once; later reads keep surface',
    () async {
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directMediaCodec,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('android_video_renderer_mode'),
        'direct_mediacodec',
      );
      expect(prefs.getBool('android_video_renderer_gpu_migration_v1'), isTrue);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'android_video_renderer_mode': 'direct_surface',
      });
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directMediaCodec,
      );
      final migrated = await SharedPreferences.getInstance();
      expect(
        migrated.getString('android_video_renderer_mode'),
        'direct_mediacodec',
      );
      expect(
        migrated.getBool('android_video_renderer_gpu_migration_v1'),
        isTrue,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'android_video_renderer_mode': 'automatic',
      });
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.automatic,
      );
      final kept = await SharedPreferences.getInstance();
      expect(kept.getString('android_video_renderer_mode'), 'automatic');
      expect(kept.getBool('android_video_renderer_gpu_migration_v1'), isTrue);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'android_video_renderer_mode': 'direct_surface',
        'android_video_renderer_gpu_migration_v1': true,
      });
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directSurface,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'android_video_renderer_mode': 'not-a-renderer',
        'android_video_renderer_gpu_migration_v1': true,
      });
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.automatic,
      );
    },
  );

  test(
    'clearExternalPlayerSettings drops generic keys and leaves platform ones',
    () async {
      await StorageService.setDefaultPlayerMode('external');
      await StorageService.setPreferredExternalPlayer('vlc');
      await StorageService.setCustomExternalPlayerPath('/usr/bin/vlc');
      await StorageService.setCustomExternalPlayerName('VLC');
      await StorageService.setCustomExternalPlayerCommand('vlc {url}');
      await StorageService.setPreferredIOSExternalPlayer('infuse');
      await StorageService.setIOSCustomSchemeTemplate('infuse://{url}');
      await StorageService.setPreferredLinuxExternalPlayer('mpv');
      await StorageService.setLinuxCustomCommand('mpv {url}');
      await StorageService.setPreferredWindowsExternalPlayer('vlc');
      await StorageService.setWindowsCustomCommand('vlc {url}');

      await StorageService.clearExternalPlayerSettings();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('default_player_mode'), isFalse);
      expect(prefs.containsKey('external_player_preferred'), isFalse);
      expect(prefs.containsKey('external_player_custom_path'), isFalse);
      expect(prefs.containsKey('external_player_custom_name'), isFalse);
      expect(prefs.containsKey('external_player_custom_command'), isFalse);
      // Quirk: iOS / Linux / Windows keys are outside the clearer.
      expect(prefs.getString('ios_external_player_preferred'), 'infuse');
      expect(prefs.getString('ios_custom_scheme_template'), 'infuse://{url}');
      expect(prefs.getString('linux_external_player_preferred'), 'mpv');
      expect(prefs.getString('linux_custom_command'), 'mpv {url}');
      expect(prefs.getString('windows_external_player_preferred'), 'vlc');
      expect(prefs.getString('windows_custom_command'), 'vlc {url}');
    },
  );
}
