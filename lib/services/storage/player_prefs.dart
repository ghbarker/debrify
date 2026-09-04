import '../../models/android_video_renderer_mode.dart';
import '../profiles/profile_preferences.dart';

/// In-app player chrome / A/V and external-player prefs.
/// [StorageService] forwards to this store.
///
/// Key names and encodings are frozen; do not rename a persisted string.
class PlayerPrefs {
  PlayerPrefs._();

  // External Player settings
  // Default player mode: 'debrify' (app player), 'external' (external player), 'deovr' (DeoVR on Android)
  static const String _defaultPlayerModeKey = 'default_player_mode';
  static const String _externalPlayerPreferredKey = 'external_player_preferred';
  static const String _externalPlayerCustomPathKey =
      'external_player_custom_path';
  static const String _externalPlayerCustomNameKey =
      'external_player_custom_name';
  static const String _externalPlayerCustomCommandKey =
      'external_player_custom_command';
  // iOS External Player settings
  static const String _iosExternalPlayerPreferredKey =
      'ios_external_player_preferred';
  static const String _iosCustomSchemeTemplateKey =
      'ios_custom_scheme_template';
  // Linux External Player settings
  static const String _linuxExternalPlayerPreferredKey =
      'linux_external_player_preferred';
  static const String _linuxCustomCommandKey = 'linux_custom_command';
  // Windows External Player settings
  static const String _windowsExternalPlayerPreferredKey =
      'windows_external_player_preferred';
  static const String _windowsCustomCommandKey = 'windows_custom_command';

  // Debrify Player default settings
  static const String _playerDefaultAspectIndexKey =
      'player_default_aspect_index';
  static const String _playerDefaultAspectIndexTvKey =
      'player_default_aspect_index_tv';
  static const String _playerNightModeIndexKey = 'player_night_mode_index';
  static const String _playerSystemAudioEffectsKey =
      'player_system_audio_effects';
  static const String _playerStartPortraitKey = 'player_start_portrait';
  static const String _androidVideoRendererModeKey =
      'android_video_renderer_mode';
  static const String _androidVideoRendererGpuMigrationKey =
      'android_video_renderer_gpu_migration_v1';
  static const String _tvosForceSoftwareDecodeKey =
      'tvos_force_software_decode';
  static const String _audioPassthroughKey = 'player_audio_passthrough';
  static const String _appleMultichannelAudioKey =
      'player_apple_multichannel_audio';
  static const String _tvosForceStereoAudioKey = 'tvos_force_stereo_audio_v1';
  static const String _tvosLegacyAudioOutputKey = 'tvos_legacy_audio_output_v1';
  static const String _subtitleAutoSyncKey = 'subtitle_auto_sync_enabled';
  static const String _playerDefaultSubtitleLanguageKey =
      'player_default_subtitle_language';
  static const String _playerDefaultAudioLanguageKey =
      'player_default_audio_language';
  static const String _skipSegmentsEnabledKey = 'skip_segments_enabled';
  static const String _skipSegmentProviderKey = 'skip_segment_provider';

  /// Stable provider identifier persisted by the Playback settings page.
  /// Kept here rather than using a display label so future provider names can
  /// change without migrating preferences.
  static const String skipSegmentProviderAuto = 'auto';
  static const String skipSegmentProviderSkipDb = 'skipdb';
  static const String skipSegmentProviderIntroDb = 'introdb';
  static const String skipSegmentProviderTheIntroDb = 'theintrodb';
  static const Set<String> _supportedSkipSegmentProviders = <String>{
    skipSegmentProviderAuto,
    skipSegmentProviderSkipDb,
    skipSegmentProviderIntroDb,
    skipSegmentProviderTheIntroDb,
  };

  // ── Player dock (touch/desktop transport controls) ──────────────────────
  //
  // Three independent prefs so any style works in any palette at any size;
  // bundling them into one "look" would only remove combinations. Palette and
  // size are inert under `classic`, whose values are still preserved so
  // switching to a styled dock restores the user's choices.
  //
  // Read once at player launch. Televisions never consult these — they build
  // `TvControls`, not `Controls`.
  static const String _playerDockStyleKey = 'player_dock_style';
  static const Set<String> _playerDockStyles = {
    'classic',
    'auto',
    'compact',
    'tiers',
    'cinema',
    // The value shipped before the arrangements became selectable. Still
    // accepted on read so existing installs keep the dock they chose; it
    // means the same thing 'auto' does.
    'two_tier',
  };

  static const String _playerDockPaletteKey = 'player_dock_palette';
  static const Set<String> _playerDockPalettes = {
    'ultraviolet',
    'crimson',
    'aurum',
    'ice',
  };

  static const String _playerDockSizeKey = 'player_dock_size';
  static const Set<String> _playerDockSizes = {
    'auto',
    'small',
    'medium',
    'large',
  };

  static const String _playLoaderStyleKey = 'play_loader_style';
  static const Set<String> _playLoaderStyles = {'marquee', 'classic'};

  static const String _tvPlayerControlsStyleKey = 'tv_player_controls_style';
  static const Set<String> _tvPlayerControlsStyles = {
    'classic',
    'ott',
    'frost',
    'marquee',
    'broadcast',
    'pulse',
    'ticket',
  };

  static const String _debrifyTvPlayerStyleKey = 'debrify_tv_player_style';
  static const Set<String> _debrifyTvPlayerStyles = {
    'classic',
    'network',
    'cinema',
    'guide',
    'spotlight',
    'prestige',
  };

  /// Declared persisted names owned by this store.
  static const Set<String> ownedKeys = {
    _defaultPlayerModeKey,
    _externalPlayerPreferredKey,
    _externalPlayerCustomPathKey,
    _externalPlayerCustomNameKey,
    _externalPlayerCustomCommandKey,
    _iosExternalPlayerPreferredKey,
    _iosCustomSchemeTemplateKey,
    _linuxExternalPlayerPreferredKey,
    _linuxCustomCommandKey,
    _windowsExternalPlayerPreferredKey,
    _windowsCustomCommandKey,
    _playerDefaultAspectIndexKey,
    _playerDefaultAspectIndexTvKey,
    _playerNightModeIndexKey,
    _playerSystemAudioEffectsKey,
    _playerStartPortraitKey,
    _androidVideoRendererModeKey,
    _androidVideoRendererGpuMigrationKey,
    _tvosForceSoftwareDecodeKey,
    _audioPassthroughKey,
    _appleMultichannelAudioKey,
    _tvosForceStereoAudioKey,
    _tvosLegacyAudioOutputKey,
    _subtitleAutoSyncKey,
    _playerDefaultSubtitleLanguageKey,
    _playerDefaultAudioLanguageKey,
    _skipSegmentsEnabledKey,
    _skipSegmentProviderKey,
    _playerDockStyleKey,
    _playerDockPaletteKey,
    _playerDockSizeKey,
    _playLoaderStyleKey,
    _tvPlayerControlsStyleKey,
    _debrifyTvPlayerStyleKey,
  };

  static Future<String> getPlayerDockStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockStyleKey);
    return _playerDockStyles.contains(raw) ? raw! : 'classic';
  }

  static Future<void> setPlayerDockStyle(String style) async {
    final normalized = _playerDockStyles.contains(style) ? style : 'classic';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockStyleKey, normalized);
  }

  static Future<String> getPlayerDockPalette() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockPaletteKey);
    return _playerDockPalettes.contains(raw) ? raw! : 'ultraviolet';
  }

  static Future<void> setPlayerDockPalette(String palette) async {
    final normalized = _playerDockPalettes.contains(palette)
        ? palette
        : 'ultraviolet';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockPaletteKey, normalized);
  }

  static Future<String> getPlayerDockSize() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockSizeKey);
    return _playerDockSizes.contains(raw) ? raw! : 'auto';
  }

  static Future<void> setPlayerDockSize(String size) async {
    final normalized = _playerDockSizes.contains(size) ? size : 'auto';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockSizeKey, normalized);
  }

  /// The look of the play → resolve loader: 'marquee' (the default — backdrop,
  /// logo art and a segmented stage rail) or 'classic' (the poster-and-
  /// checklist card this overlay shipped with). Unknown or unset coerces to
  /// 'marquee' on BOTH read and write, so a value written by a newer build can
  /// never pin a look this one cannot render.
  ///
  /// The play path reads it synchronously through
  /// [PlayLoaderStyleController.cached]; this getter is the warm source.
  static Future<String> getPlayLoaderStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playLoaderStyleKey);
    return _playLoaderStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setPlayLoaderStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _playLoaderStyleKey,
      _playLoaderStyles.contains(style) ? style : 'marquee',
    );
  }

  /// Control skin for the NATIVE Android TV player: 'marquee' (editorial
  /// serif — the default), 'ott' (the Apple TV dock ported to Kotlin),
  /// 'classic' (the legacy Cinema Mode controls), or one of the other
  /// premium dock skins ('frost', 'broadcast', 'pulse', 'ticket'). Android TV only; tvOS runs the
  /// Flutter player and has nothing to choose. Read once per player launch — the native side via
  /// `ProfilePreferenceProjection.getString("tv_player_controls_style")`
  /// (falling back to `flutter.tv_player_controls_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'marquee' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getTvPlayerControlsStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_tvPlayerControlsStyleKey);
    return _tvPlayerControlsStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setTvPlayerControlsStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _tvPlayerControlsStyleKey,
      _tvPlayerControlsStyles.contains(style) ? style : 'marquee',
    );
  }

  /// Playback-screen style for the NATIVE Debrify TV player
  /// (TorboxTvPlayerActivity): 'cinema' (poster + gilded spec line — the
  /// default), 'network' (broadcast lower-third), 'guide' (opaque
  /// broadcast band), 'spotlight' (frosted glass panel), 'prestige'
  /// (quiet serif identity), or 'classic' (the legacy ESPN-style bar +
  /// top marquee). Android TV only. Read once per player launch — the
  /// native side via
  /// `ProfilePreferenceProjection.getString("debrify_tv_player_style")`
  /// (falling back to `flutter.debrify_tv_player_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'cinema' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getDebrifyTvPlayerStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvPlayerStyleKey);
    return _debrifyTvPlayerStyles.contains(raw) ? raw! : 'cinema';
  }

  static Future<void> setDebrifyTvPlayerStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _debrifyTvPlayerStyleKey,
      _debrifyTvPlayerStyles.contains(style) ? style : 'cinema',
    );
  }

  // External Player Settings methods

  /// Get default player mode
  /// Returns 'debrify' (built-in player) by default
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<String> getDefaultPlayerMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_defaultPlayerModeKey) ?? 'debrify';
  }

  /// Set default player mode
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<void> setDefaultPlayerMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultPlayerModeKey, mode);
  }

  /// Get preferred external player key
  /// Returns 'system_default' if not set
  static Future<String> getPreferredExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred external player key
  static Future<void> setPreferredExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_externalPlayerPreferredKey, playerKey);
  }

  /// Get custom external player path (for custom player option)
  static Future<String?> getCustomExternalPlayerPath() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomPathKey);
  }

  /// Set custom external player path
  static Future<void> setCustomExternalPlayerPath(String? path) async {
    final prefs = await ProfilePreferences.instance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_externalPlayerCustomPathKey);
    } else {
      await prefs.setString(_externalPlayerCustomPathKey, path);
    }
  }

  /// Get custom external player display name
  static Future<String?> getCustomExternalPlayerName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomNameKey);
  }

  /// Set custom external player display name
  static Future<void> setCustomExternalPlayerName(String? name) async {
    final prefs = await ProfilePreferences.instance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_externalPlayerCustomNameKey);
    } else {
      await prefs.setString(_externalPlayerCustomNameKey, name);
    }
  }

  /// Get custom external player command template
  /// Should contain {url} placeholder, optionally {title}
  static Future<String?> getCustomExternalPlayerCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomCommandKey);
  }

  /// Set custom external player command template
  static Future<void> setCustomExternalPlayerCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_externalPlayerCustomCommandKey);
    } else {
      await prefs.setString(_externalPlayerCustomCommandKey, command);
    }
  }

  // ============================================================
  // iOS External Player Settings
  // ============================================================

  /// Get preferred iOS external player key
  static Future<String> getPreferredIOSExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iosExternalPlayerPreferredKey) ?? 'vlc';
  }

  /// Set preferred iOS external player key
  static Future<void> setPreferredIOSExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iosExternalPlayerPreferredKey, playerKey);
  }

  /// Get iOS custom URL scheme template
  /// Should contain {url} placeholder, e.g., "myplayer://play?url={url}"
  static Future<String?> getIOSCustomSchemeTemplate() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iosCustomSchemeTemplateKey);
  }

  /// Set iOS custom URL scheme template
  static Future<void> setIOSCustomSchemeTemplate(String? template) async {
    final prefs = await ProfilePreferences.instance();
    if (template == null || template.isEmpty) {
      await prefs.remove(_iosCustomSchemeTemplateKey);
    } else {
      await prefs.setString(_iosCustomSchemeTemplateKey, template);
    }
  }

  // ============================================================
  // Linux External Player Settings
  // ============================================================

  /// Get preferred Linux external player key
  static Future<String> getPreferredLinuxExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_linuxExternalPlayerPreferredKey) ??
        'system_default';
  }

  /// Set preferred Linux external player key
  static Future<void> setPreferredLinuxExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_linuxExternalPlayerPreferredKey, playerKey);
  }

  /// Get Linux custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getLinuxCustomCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_linuxCustomCommandKey);
  }

  /// Set Linux custom command template
  static Future<void> setLinuxCustomCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_linuxCustomCommandKey);
    } else {
      await prefs.setString(_linuxCustomCommandKey, command);
    }
  }

  // ============================================================
  // Windows External Player Settings
  // ============================================================

  /// Get preferred Windows external player key
  static Future<String> getPreferredWindowsExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_windowsExternalPlayerPreferredKey) ??
        'system_default';
  }

  /// Set preferred Windows external player key
  static Future<void> setPreferredWindowsExternalPlayer(
    String playerKey,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_windowsExternalPlayerPreferredKey, playerKey);
  }

  /// Get Windows custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getWindowsCustomCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_windowsCustomCommandKey);
  }

  /// Set Windows custom command template
  static Future<void> setWindowsCustomCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_windowsCustomCommandKey);
    } else {
      await prefs.setString(_windowsCustomCommandKey, command);
    }
  }

  /// Clear all external player settings
  static Future<void> clearExternalPlayerSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultPlayerModeKey);
    await prefs.remove(_externalPlayerPreferredKey);
    await prefs.remove(_externalPlayerCustomPathKey);
    await prefs.remove(_externalPlayerCustomNameKey);
    await prefs.remove(_externalPlayerCustomCommandKey);
  }

  // Debrify Player Default Settings

  /// Get default aspect ratio index for Flutter/mobile player
  /// 0=Contain, 1=Cover, 2=FitWidth, 3=FitHeight, 4=16:9, 5=4:3, 6=21:9, 7=1:1, 8=3:2, 9=5:4, 10=CinemaZoom
  /// Default: 2 (Fit Width)
  static Future<int> getPlayerDefaultAspectIndex() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerDefaultAspectIndexKey) ?? 2;
  }

  /// Set default aspect ratio index for Flutter/mobile player
  static Future<void> setPlayerDefaultAspectIndex(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerDefaultAspectIndexKey, index);
  }

  /// Get default aspect ratio index for Android TV player
  /// 0=Fit, 1=Fill, 2=Zoom, 3=CinemaZoom
  /// Default: 0 (Fit)
  static Future<int> getPlayerDefaultAspectIndexTv() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerDefaultAspectIndexTvKey) ?? 0;
  }

  /// Set default aspect ratio index for Android TV player
  static Future<void> setPlayerDefaultAspectIndexTv(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerDefaultAspectIndexTvKey, index);
  }

  /// Get night mode index (Android TV only)
  /// 0=Off, 1=Low, 2=Medium, 3=High, 4=Higher, 5=Extreme, 6=Max, 7=Sleeping Baby
  /// Default: 0 (Off)
  static Future<int> getPlayerNightModeIndex() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerNightModeIndexKey) ?? 0;
  }

  /// Set night mode index (Android TV only)
  static Future<void> setPlayerNightModeIndex(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerNightModeIndexKey, index);
  }

  /// Whether to route playback through Android's effects-capable audio output
  /// and announce the session to system equalizer apps (Wavelet, OEM effects).
  /// Android only. Default: false — off changes nothing about how audio is
  /// output today, since enabling it switches the phone player's audio backend.
  static Future<bool> getPlayerSystemAudioEffects() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_playerSystemAudioEffectsKey) ?? false;
  }

  /// Set whether system audio effect apps may process our playback.
  static Future<void> setPlayerSystemAudioEffects(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_playerSystemAudioEffectsKey, enabled);
  }

  /// Android Dart player only: bitstream AC3/EAC3/DTS-core to the audio
  /// device instead of decoding to PCM (AUDIO_FIDELITY_PLAN.md). Default
  /// false — passthrough is fail-loud on routes that misreport support,
  /// so only the user can turn it on.
  static Future<bool> getAudioPassthroughEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_audioPassthroughKey) ?? false;
  }

  static Future<void> setAudioPassthroughEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_audioPassthroughKey, enabled);
  }

  /// Apple (tvOS/iOS) Dart player: request the track's real channel layout
  /// (`audio-channels=auto`) so an HDMI/eARC AVR route gets full
  /// multichannel LPCM. Default false until route-safety is field-proven
  /// (AUDIO_FIDELITY_PLAN.md rev 2).
  static Future<bool> getAppleMultichannelAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_appleMultichannelAudioKey) ?? false;
  }

  static Future<void> setAppleMultichannelAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_appleMultichannelAudioKey, enabled);
  }

  /// Apple TV diagnostics. The player picks `ao=avfoundation,audiounit` and
  /// caps `audio-channels` to stereo on a route that reports two channels;
  /// these two override that automatic choice from either direction, so a
  /// reporter can narrow an audio problem without a custom build.
  ///
  /// Force stereo: cap regardless of what the route claims. Use when a
  /// multichannel route folds badly.
  static Future<bool> getTvosForceStereoAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosForceStereoAudioKey) ?? false;
  }

  static Future<void> setTvosForceStereoAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosForceStereoAudioKey, enabled);
  }

  /// Legacy output: go back to `ao=audiounit`, the pre-2026-08 behaviour.
  /// It is silent on Dolby Atmos routes — which is why avfoundation is now
  /// the default — but it is the escape hatch if the new output misbehaves.
  static Future<bool> getTvosLegacyAudioOutput() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosLegacyAudioOutputKey) ?? false;
  }

  static Future<void> setTvosLegacyAudioOutput(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosLegacyAudioOutputKey, enabled);
  }

  /// Apple TV only: force the media-kit player to software video decoding.
  /// The escape hatch behind the automatic 10-bit remedy ladder (see
  /// PLAYER_TVOS_10BIT_PLAN.md) — for files whose formats read clean but
  /// render wrong. Default false: hardware decoding, today's behavior.
  static Future<bool> getTvosForceSoftwareDecode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosForceSoftwareDecodeKey) ?? false;
  }

  static Future<void> setTvosForceSoftwareDecode(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosForceSoftwareDecodeKey, enabled);
  }

  /// Renderer used by the Flutter media-kit player on Android phones/tablets.
  /// Android TV ignores this and keeps its native Media3 SurfaceView backend.
  static Future<AndroidVideoRendererMode> getAndroidVideoRendererMode() async {
    final prefs = await ProfilePreferences.instance();
    final migrated =
        prefs.getBool(_androidVideoRendererGpuMigrationKey) ?? false;
    final stored = prefs.getString(_androidVideoRendererModeKey);
    if (!migrated) {
      // Direct Surface used to be the default, but mediacodec_embed cannot
      // composite bitmap subtitles. Migrate existing installs once; users may
      // still explicitly choose the performance renderer afterwards.
      if (stored == null ||
          stored == AndroidVideoRendererMode.directSurface.storageKey) {
        await prefs.setString(
          _androidVideoRendererModeKey,
          AndroidVideoRendererMode.directMediaCodec.storageKey,
        );
      }
      await prefs.setBool(_androidVideoRendererGpuMigrationKey, true);
    }
    return AndroidVideoRendererMode.fromStorage(
      prefs.getString(_androidVideoRendererModeKey),
    );
  }

  static Future<void> setAndroidVideoRendererMode(
    AndroidVideoRendererMode mode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_androidVideoRendererModeKey, mode.storageKey);
    await prefs.setBool(_androidVideoRendererGpuMigrationKey, true);
  }

  /// Whether the Debrify Player should request community timestamps and show
  /// manual skip buttons. Manual buttons are enabled by default; this setting
  /// never authorizes automatic seeking.
  static Future<bool> getSkipSegmentsEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_skipSegmentsEnabledKey) ?? true;
  }

  static Future<void> setSkipSegmentsEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_skipSegmentsEnabledKey, enabled);
  }

  /// Timestamp source used by the Debrify Player. Unknown stored values fall
  /// back safely so removing a provider cannot strand the feature.
  static Future<String> getSkipSegmentProvider() async {
    final prefs = await ProfilePreferences.instance();
    final provider = prefs.getString(_skipSegmentProviderKey);
    return _supportedSkipSegmentProviders.contains(provider)
        ? provider!
        : skipSegmentProviderAuto;
  }

  static Future<void> setSkipSegmentProvider(String provider) async {
    final prefs = await ProfilePreferences.instance();
    final supported = _supportedSkipSegmentProviders.contains(provider)
        ? provider
        : skipSegmentProviderAuto;
    await prefs.setString(_skipSegmentProviderKey, supported);
  }

  /// Whether the phone player OPENS upright instead of turning the handset
  /// landscape for you. Off by default — a video wants the long edge, and that
  /// is what the player has always done. On, it opens portrait and the
  /// player's own Portrait/Landscape button is how the user turns it.
  /// Phone-only: a TV has no portrait and a desktop window ignores this
  /// entirely.
  ///
  /// [playerStartPortraitCached] mirrors it for SYNCHRONOUS reads. The player
  /// commits its orientation while building, so an async read there would set
  /// landscape and correct it a frame later — performing the exact flip this
  /// setting exists to prevent. Warmed in main() before runApp (the IPTV
  /// startup channel can open a player on the first frame) and kept in sync by
  /// the setter.
  static bool playerStartPortraitCached = false;

  static Future<bool> getPlayerStartPortrait() async {
    final prefs = await ProfilePreferences.instance();
    playerStartPortraitCached = prefs.getBool(_playerStartPortraitKey) ?? false;
    return playerStartPortraitCached;
  }

  static Future<void> setPlayerStartPortrait(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_playerStartPortraitKey, enabled);
    playerStartPortraitCached = enabled;
  }

  /// Whether native players silently align addon subtitles to the audio as
  /// playback runs. Android TV reads the same profile preference natively;
  /// MediaKit reads it in Dart (Android, macOS, Linux, tvOS — platforms whose
  /// bundled libmpv carries the analysis filters) and attaches its passive
  /// filter only while an addon subtitle is active. OFF by default on both
  /// engines — experimental opt-in. The default must stay in lock-step with
  /// the native read in AndroidTvTorrentPlayerActivity.isAutoSyncPrefEnabled.
  static Future<bool> getSubtitleAutoSyncEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_subtitleAutoSyncKey) ?? false;
  }

  static Future<void> setSubtitleAutoSyncEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_subtitleAutoSyncKey, enabled);
  }

  /// Get default subtitle language code
  /// Returns language code (e.g., 'en', 'es') or 'off' for disabled, null for no preference
  static Future<String?> getDefaultSubtitleLanguage() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_playerDefaultSubtitleLanguageKey);
  }

  /// Set default subtitle language code
  /// Pass language code (e.g., 'en', 'es'), 'off' for disabled, or null to clear preference
  static Future<void> setDefaultSubtitleLanguage(String? languageCode) async {
    final prefs = await ProfilePreferences.instance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultSubtitleLanguageKey);
    } else {
      await prefs.setString(_playerDefaultSubtitleLanguageKey, languageCode);
    }
  }

  /// Get default audio language code
  /// Returns language code (e.g., 'en', 'es') or null for no preference
  static Future<String?> getDefaultAudioLanguage() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_playerDefaultAudioLanguageKey);
  }

  /// Set default audio language code
  /// Pass language code (e.g., 'en', 'es') or null to clear preference
  static Future<void> setDefaultAudioLanguage(String? languageCode) async {
    final prefs = await ProfilePreferences.instance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultAudioLanguageKey);
    } else {
      await prefs.setString(_playerDefaultAudioLanguageKey, languageCode);
    }
  }
}
