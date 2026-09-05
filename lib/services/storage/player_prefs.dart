import '../../models/android_video_renderer_mode.dart';
import '../profiles/profile_preferences.dart';

/// In-app player A/V, external-player, skip-segment, UI-feedback, and
/// network-tuning prefs. [StorageService] forwards to this store.
///
/// Style keys (dock, play-loader, TV controls, `debrify_tv_player_style`)
/// live on [AppStylePrefs] (S2-4). Completion thresholds /
/// `_getPlaybackStateMap` stay until S2-6. Key names and encodings are
/// frozen; do not rename a persisted string.
class PlayerPrefs {
  PlayerPrefs._();

  // Network tuning (Debrify player). 'standard' = leave the player's own
  // defaults completely untouched — see NetworkTuning.
  static const String _networkConnectPatienceKey = 'network_connect_patience';
  static const String _networkBufferSizeKey = 'network_buffer_size';

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
  static const String _uiSoundsKey = 'ui_sounds';
  static const String _uiHapticsKey = 'ui_haptics';
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

  static const Set<String> ownedKeys = {
    _networkConnectPatienceKey,
    _networkBufferSizeKey,
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
    _uiSoundsKey,
    _uiHapticsKey,
    _subtitleAutoSyncKey,
    _playerDefaultSubtitleLanguageKey,
    _playerDefaultAudioLanguageKey,
    _skipSegmentsEnabledKey,
    _skipSegmentProviderKey,
  };

  // Network tuning (Debrify player)
  /// 'standard' | 'extended' | 'patient'. Standard = player defaults untouched.
  static Future<String> getNetworkConnectPatience() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_networkConnectPatienceKey) ?? 'standard';
  }

  static Future<void> setNetworkConnectPatience(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_networkConnectPatienceKey, value);
  }

  /// 'standard' | 'large' | 'huge'. Standard = player defaults untouched.
  static Future<String> getNetworkBufferSize() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_networkBufferSizeKey) ?? 'standard';
  }

  static Future<void> setNetworkBufferSize(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_networkBufferSizeKey, value);
  }

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

  /// Whether interface sound and haptics are allowed at all.
  ///
  /// A VETO, not a switch: the theme decides whether there is anything to play
  /// and these decide whether the user wants to hear or feel it. Both default
  /// ON, because a theme that asks for silence — which is every look except
  /// Console and Warm Room — already produces none, so the default cannot
  /// surprise anybody who has not chosen a look that ticks.
  ///
  /// Synchronous mirrors because `UiFeedback` is consulted from a focus
  /// listener and a key handler, neither of which can await. Warmed in main()
  /// before runApp.
  static bool uiSoundsCached = true;
  static bool uiHapticsCached = true;

  static Future<bool> getUiSounds() async {
    final prefs = await ProfilePreferences.instance();
    uiSoundsCached = prefs.getBool(_uiSoundsKey) ?? true;
    return uiSoundsCached;
  }

  static Future<void> setUiSounds(bool enabled) async {
    // The mirror moves FIRST. `UiFeedback` reads it from a focus listener that
    // cannot await, so publishing after the platform write leaves a window in
    // which a user who has just switched sound off still hears the next tick.
    uiSoundsCached = enabled;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_uiSoundsKey, enabled);
  }

  static Future<bool> getUiHaptics() async {
    final prefs = await ProfilePreferences.instance();
    uiHapticsCached = prefs.getBool(_uiHapticsKey) ?? true;
    return uiHapticsCached;
  }

  static Future<void> setUiHaptics(bool enabled) async {
    uiHapticsCached = enabled;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_uiHapticsKey, enabled);
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
