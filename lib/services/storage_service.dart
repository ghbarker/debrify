export 'storage/ambient_trailer_prefs.dart' show AmbientTrailerSurface;

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'debrid_service.dart';
import 'remote_control/remote_device_prefs.dart';
import 'iptv_media_store.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/profile_onboarding_state.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_runtime.dart';
import 'storage/my_watchlist_store.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import 'secret_vault.dart';
import '../models/indexer_manager_config.dart';
import '../models/quick_play_rules.dart';
import '../models/sidebar_configuration.dart';
import '../models/stremio_addon.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/tv_hero_artwork_quality.dart';
import '../models/tracking_source.dart';
import '../utils/platform_util.dart';
import 'storage/cloud_secret_prefs.dart';
import 'storage/tracking_prefs.dart';
import 'storage/debrify_tv_prefs.dart';
import 'storage/home_prefs.dart';
import 'storage/default_torrent_filter_prefs.dart';
import 'storage/quick_play_policy_prefs.dart';
import 'storage/social_prefs.dart';
import 'storage/iptv_prefs.dart';
import 'storage/app_style_prefs.dart';
import 'storage/player_prefs.dart';
import 'storage/provider_credential_prefs.dart';
import 'storage/stremio_tv_prefs.dart';
import 'storage/playback_progress_store.dart';

export 'storage/home_prefs.dart'
    show
        HomeCardOrientation,
        HomeHeroSourceMode,
        HomeHeroSource,
        HomeExtraRow;

/// Which ambient-trailer surface a sound/volume preference belongs to.
///
/// A television now has both: the Home board's hero and the Showcase detail
/// page. They are separate preferences because they are separate experiences —
/// a muted Home hero should not mute a detail page you opened deliberately.

/// How the Android TV UI is rastered — see
/// [StorageService.getTvRenderQuality]. Three states, not a switch: the
/// automatic branch is the ABSENCE of the stored pref, because that absence is
/// what lets MainActivity keep making the device-capability call.
enum TvRenderQuality {
  /// Let MainActivity decide (GLES2-class hardware gets the 720p buffer).
  auto,

  /// Always raster at the panel's own resolution.
  sharp,

  /// Always raster at ~720p and let the TV's scaler upscale.
  fast,
}

class StorageService {

  static String get trackingScrobbleTargetsKey =>
      TrackingPrefs.trackingScrobbleTargetsKey;
  static String get watchProgressSourceKey =>
      TrackingPrefs.watchProgressSourceKey;

  /// Invalidates policy consumers that keep an in-memory snapshot.
  static ValueNotifier<int> get trackingSourceRevision =>
      TrackingPrefs.trackingSourceRevision;

  /// Tracker/account watched-title invalidation. Kept separate from local
  /// playback so finishing an episode never reloads entire remote histories.
  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier(0);

  /// Local movie, episode, and derived-series completion invalidation.
  static ValueNotifier<int> get localCompletionRevision =>
      PlaybackProgressStore.localCompletionRevision;



  static Future<bool> profileAllowsAdultContent() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return true;
    }
    try {
      final scope = ProfileRuntime.capture();
      final profile = await ProfileBootstrap.registry.getProfile(
        scope.profileId,
      );
      return profile?.allows(ProfileFeature.allowAdultContent) == true;
    } catch (_) {
      return false;
    }
  }

  // ── Update-aware defaults ─────────────────────────────────────────────
  //
  // "Default" in this app has always meant "what an unset pref falls back
  // to" — which never reaches users who installed before a redesign. The
  // defaults GENERATION makes a flagship-look change reach them once:
  // on the first launch at a new generation, every look pref the user
  // NEVER wrote adopts the current bundle; every stored key — an explicit
  // choice, since all these setters write unconditionally — is untouched.
  // After migration the adopted values are stored too, so switching away
  // later sticks forever.
  //
  // Generation 1 (2026-08): the Spotlight era — Spotlight theme, Showcase
  // details, Spotlight TV home, pill rails on TV and desktop/tablet.
  // (text_brightness is deliberately absent: its unset default is already
  // the Look's value.)
  //
  // Generation 2 (2026-08): ambient trailers on, everywhere. Both surfaces
  // used to default by form factor — the hero off on phones and tablets,
  // the detail backdrop off on televisions — so most installs only ever saw
  // one of them. Both now default on for every device, and this generation
  // carries that to installs already in the field.
  //
  // Generation 3 (2026-08): Debrify TV joins the flagship bundle. Installs
  // wearing the Spotlight THEME (via the Look or a custom mix) adopt the
  // rail+stage layout; every other install keeps the grid it has always had.
  //
  // To roll out a future flagship look: bump the generation, append its
  // bundle under a `gen < N` block below.
  static const int _currentDefaultsGeneration = 3;
  static const String _defaultsGenerationKey = 'defaults_generation';

  /// MUST run before [TextBrightnessController.warm] / theme warms in
  /// `main()`: the first frame has to already be the migrated look.
  static Future<void> migrateDefaultsGeneration() async {
    final prefs = await ProfilePreferences.instance();
    final gen = prefs.getInt(_defaultsGenerationKey) ?? 0;
    if (gen >= _currentDefaultsGeneration) return;
    if (gen < 1) {
      await AppStylePrefs.migrateDefaultsGeneration1Theme(prefs);
      await HomePrefs.migrateDefaultsGeneration1TvHome(prefs);
      await AppStylePrefs.migrateDefaultsGeneration1Sidebars(prefs);
    }
    if (gen < 2) {
      await HomePrefs.migrateDefaultsGeneration2Trailers(prefs);
      // This residual key remains host-owned; explicit false is preserved.
      if (!prefs.containsKey('detail_trailer_autoplay_enabled')) {
        await prefs.setBool('detail_trailer_autoplay_enabled', true);
      }
    }
    if (gen < 3) {
      await AppStylePrefs.migrateDefaultsGeneration3TvStyle(prefs);
    }
    await prefs.setInt(_defaultsGenerationKey, _currentDefaultsGeneration);
  }


  static const String _torboxApiKey = CloudSecretPrefs.torboxApiKey;
  static const String _premiumizeApiKey = CloudSecretPrefs.premiumizeApiKey;
  static const String _allDebridApiKey = CloudSecretPrefs.allDebridApiKey;
  static const String _batteryOptStatusKey =
      'battery_opt_status_v1'; // granted|denied|never|unknown

  static const String localSeriesCompletionStateKey =
      PlaybackProgressStore.localSeriesCompletionStateKey;
  static const String localSeriesCalendarCheckedAtKey =
      PlaybackProgressStore.localSeriesCalendarCheckedAtKey;
  static const String localSeriesCalendarAttemptedAtKey =
      PlaybackProgressStore.localSeriesCalendarAttemptedAtKey;

  static const String _supportRemoteConfigCacheKey =
      'support_remote_config_cache_v1';
  static const String _dismissedDonationCampaignIdsKey =
      'dismissed_donation_campaign_ids_v1';

  // Startup settings
  static const String _startupAutoLaunchEnabledKey =
      'startup_auto_launch_enabled';
  static const String _startupChannelIdKey = 'startup_channel_id';
  static const String _startupStremioTvChannelIdKey =
      'startup_stremio_tv_channel_id';
  static const String _startupModeKey =
      'startup_mode'; // 'channel', 'stremio_tv', 'playlist', 'continue_watching', 'trakt_continue_watching_movies', or 'trakt_continue_watching_shows'
  static const String _startupPlaylistItemIdKey = 'startup_playlist_item_id';
  static const String _startupContinueWatchingItemIdKey =
      'startup_continue_watching_item_id';
  static const String _startupTraktContinueWatchingMovieIdKey =
      'startup_trakt_continue_watching_movie_id';
  static const String _startupTraktContinueWatchingShowIdKey =
      'startup_trakt_continue_watching_show_id';

  static const String _updateAutoCheckEnabledKey = 'update_auto_check_enabled';
  static const String _updateIgnoredVersionKey = 'update_ignored_version';


  /// Completion thresholds selectable in Settings → Playback. A lower bound
  /// avoids treating a brief accidental play as watched; 95% still lets users
  /// finish a title without waiting through every trailing credit frame.
  static const List<int> localCompletionThresholdOptions =
      PlaybackProgressStore.localCompletionThresholdOptions;
  static const int defaultLocalCompletionThreshold =
      PlaybackProgressStore.defaultLocalCompletionThreshold;


  // PikPak secret key aliases — CloudSecretPrefs owns the strings.
  static const String _pikpakEmailKey = CloudSecretPrefs.pikpakEmail;
  static const String _pikpakPasswordKey = CloudSecretPrefs.pikpakPassword;

  // TVMaze series mapping keys

  // Playlist poster override storage key






  // Torrent Search History

  // Default Torrent Filter Settings

  // Default Torrent Provider Settings — key lives on ProviderCredentialPrefs.
  // Values: 'none' (ask every time), 'torbox', 'debrid', 'pikpak'
  static const String _indexerManagerConfigsKey = 'indexer_manager_configs_v1';

  // Quick Play VR Settings
  // VR Player Mode: 'disabled' (always regular player), 'auto' (detect VR content), 'always' (always use DeoVR)

  // Quick Play Cache Fallback Settings
  // When enabled, if first torrent is not cached, try next torrents until one works

  // Series auto-pin: on a series play with no pinned source, search packs
  // first (complete series → season pack), and pin whatever source plays so
  // subsequent episode plays go straight through the bound path.
  /// The moved legacy mirror is written by [setQuickPlayRules] to carry
  /// `preferSeriesPacks` for downgrade builds, and read once by
  /// `QuickPlayPolicyPrefs` legacy decoder to migrate pre-v2 profiles. Nothing on the live
  /// playback path may read it — see [_seriesAutoPinOnPlayKey].

  /// Whether a series play pins the source that played. Split out of
  /// `auto_bind_series_packs_on_play` because that key doubles as the legacy mirror of
  /// `preferSeriesPacks`: turning OFF "Prefer season packs" in Quick Play also
  /// silently disabled all series auto-pinning, so Smart mode never found a pin
  /// and Quick Play lost its fast path. Deliberately does NOT inherit the old
  /// key's value — a `false` there was the packs toggle bleeding through, never
  /// an auto-pin choice (no UI ever wrote it directly).
  static const String _seriesAutoPinOnPlayKey = 'series_auto_pin_on_play';

  // Remote Control Settings

  static Future<String?> getApiKey({bool forRemoteTransfer = false}) =>
      CloudSecretPrefs.read(
        CloudSecretPrefs.realDebridApiKey,
        forRemoteTransfer: forRemoteTransfer,
      );

  static Future<bool> hasRealDebridCredential() =>
      CloudSecretPrefs.isConfigured(CloudSecretPrefs.realDebridApiKey);

  static Future<void> saveApiKey(String apiKey) =>
      CloudSecretPrefs.write(CloudSecretPrefs.realDebridApiKey, apiKey);

  static Future<void> deleteApiKey() =>
      CloudSecretPrefs.delete(CloudSecretPrefs.realDebridApiKey);

  // Real-Debrid endpoint preference (for fallback to backup endpoint)



  // Torbox API key helpers
  static Future<String?> getTorboxApiKey({
    bool forRemoteTransfer = false,
  }) =>
      CloudSecretPrefs.read(
        _torboxApiKey,
        forRemoteTransfer: forRemoteTransfer,
      );

  static Future<bool> hasTorboxCredential() =>
      CloudSecretPrefs.isConfigured(_torboxApiKey);

  static Future<void> saveTorboxApiKey(String apiKey) =>
      CloudSecretPrefs.write(_torboxApiKey, apiKey);

  static Future<void> deleteTorboxApiKey() =>
      CloudSecretPrefs.delete(_torboxApiKey);

  static Future<bool> getSeriesBrowserDenseView() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('series_browser_dense_view') ?? false;
  }

  static Future<void> setSeriesBrowserDenseView(bool dense) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('series_browser_dense_view', dense);
  }

  /// Route series & movies to the merged detail+episodes page (the Stremio-styled
  /// single screen) instead of the separate detail → episodes flow. On by
  /// default; can be turned off per-device via [setMergedSeriesPageEnabled].
  static Future<bool> getMergedSeriesPageEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('merged_series_page_enabled') ?? true;
  }

  static Future<void> setMergedSeriesPageEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('merged_series_page_enabled', enabled);
  }

  /// Use the in-app DPAD keyboard for text fields on TV (TvTextField) instead
  /// of the system IME, which can't be navigated with the remote on many
  /// devices (flutter/flutter#177360 — Chromecast/Google TV, some
  /// Philips/Samsung panels). On by default on Android TV. Apple TV defaults
  /// to its system keyboard; the Settings toggle still lets users opt into the
  /// Debrify keyboard.
  ///
  /// [tvKeyboardEnabledCached] mirrors the stored value for synchronous widget
  /// builds — warmed at startup (main.dart) and kept in sync by the setter.
  static bool tvKeyboardEnabledCached = !PlatformUtil.isTvOS;

  // Apple TV keyboard default, generation 1 (2026-08): disable the Debrify
  // keyboard once for every profile, including profiles whose user explicitly
  // enabled it in an older build. The generation is committed only after the
  // new value, so a failed/interrupted write retries safely next launch. Once
  // committed, [setTvKeyboardEnabled] is authoritative and later user changes
  // are never overwritten.
  static const int _currentTvosKeyboardDefaultGeneration = 1;
  static const String _tvosKeyboardDefaultGenerationKey =
      'tvos_keyboard_default_generation';

  static Future<bool> getTvKeyboardEnabled({
    @visibleForTesting bool? tvOs,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final runningOnTvOs = tvOs ?? PlatformUtil.isTvOS;
    final generation = prefs.getInt(_tvosKeyboardDefaultGenerationKey) ?? 0;
    if (runningOnTvOs && generation < _currentTvosKeyboardDefaultGeneration) {
      final disabled = await prefs.setBool('tv_keyboard_enabled', false);
      if (disabled) {
        await prefs.setInt(
          _tvosKeyboardDefaultGenerationKey,
          _currentTvosKeyboardDefaultGeneration,
        );
      }
    }
    tvKeyboardEnabledCached =
        prefs.getBool('tv_keyboard_enabled') ?? !runningOnTvOs;
    return tvKeyboardEnabledCached;
  }

  static Future<void> setTvKeyboardEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tv_keyboard_enabled', enabled);
    tvKeyboardEnabledCached = enabled;
  }


  /// Android TV rendering mode — whether the Flutter UI is rastered at the
  /// panel's own resolution or at a ~720p buffer the TV's scaler blows back
  /// up for free.
  ///
  /// GLES2-class boxes are fill-rate bound: the same build at 720p feels near
  /// native on hardware that judders at 1080p. MainActivity decides this in
  /// `computeRenderScale` and has always been able to be overridden by
  /// `flutter.tv_low_res_render` — there was simply no way to set it. This is
  /// that way.
  ///
  /// TRI-STATE, and the absence of the key is load-bearing: native reads it as
  /// `getBoolean(key, auto)` where `auto` IS the device decision, so
  /// [TvRenderQuality.auto] must REMOVE the key rather than write `false`.
  /// Writing `false` on a weak TV would strip the 720p subsidy off the very
  /// devices that need it — a silent, permanent regression on the hardware
  /// least able to absorb it.
  ///
  /// Read natively before the engine is built, so a change lands on the next
  /// cold start. Android TV only; ignored everywhere else.
  static const String _tvRenderQualityKey = 'tv_low_res_render';

  static Future<TvRenderQuality> getTvRenderQuality() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getBool(_tvRenderQualityKey);
    if (stored == null) return TvRenderQuality.auto;
    return stored ? TvRenderQuality.fast : TvRenderQuality.sharp;
  }

  static Future<void> setTvRenderQuality(TvRenderQuality quality) async {
    final prefs = await ProfilePreferences.instance();
    switch (quality) {
      case TvRenderQuality.auto:
        await prefs.remove(_tvRenderQualityKey);
      case TvRenderQuality.sharp:
        await prefs.setBool(_tvRenderQualityKey, false);
      case TvRenderQuality.fast:
        await prefs.setBool(_tvRenderQualityKey, true);
    }
  }

  /// What MainActivity ACTUALLY decided for the engine currently running —
  /// written natively on every launch (`renderScale < 0.999f`), so under
  /// [TvRenderQuality.auto] it's the only way to see which branch this TV
  /// landed on. Also the honest answer after a change that hasn't been cold-
  /// started into yet: the pref says what will happen, this says what is.
  ///
  /// Written on every ANDROID launch, phones included (the `putBoolean` sits
  /// outside any TV guard) — off TV `renderScale` stays 1.0, so a phone reads
  /// `false`, not null. Null means MainActivity never ran at all: iOS, macOS,
  /// desktop. Callers must treat null as "unknown", never as "full res".
  static Future<bool?> getTvLowResRenderActive() async {
    final device = await DevicePreferences.instance();
    return device.getBool(DevicePreferences.tvLowResRenderActiveKey);
  }


  /// Show the new Stremio-styled Addons hub (single list + source/type filters,
  /// purple Discover theme, 1-click marketplace) instead of the classic two-tab
  /// Addons screen. On by default; can be turned off per-device via
  /// [setStremioAddonHubEnabled].
  static Future<bool> getStremioAddonHubEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('stremio_addon_hub_enabled') ?? true;
  }

  static Future<void> setStremioAddonHubEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('stremio_addon_hub_enabled', enabled);
  }

  /// Autoplay a trailer behind the detail-page backdrop (OTT-style), when the
  /// metadata addon provides one.
  ///
  /// **Defaults ON everywhere** (generation 2). Two earlier rules are retired
  /// here, and neither should be reintroduced without the reason returning:
  /// "exactly one ambient surface per platform" existed because the process
  /// has a single video output, which [VideoOutputLease] plus a covered
  /// trailer releasing its decoder now enforces directly; and the later
  /// hold-back of OFF-on-TV existed only so an existing box wouldn't start
  /// playing trailers on a page that never did, which the generation
  /// migration now handles deliberately rather than by omission.
  static Future<bool> getDetailTrailerAutoplayEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('detail_trailer_autoplay_enabled') ?? true;
  }

  static Future<void> setDetailTrailerAutoplayEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('detail_trailer_autoplay_enabled', enabled);
  }

  static Future<bool> getHomeHeroTrailerEnabled() =>
      HomePrefs.getHomeHeroTrailerEnabled();

  static Future<void> setHomeHeroTrailerEnabled(bool enabled) =>
      HomePrefs.setHomeHeroTrailerEnabled(enabled);





  /// Android TV: render ambient trailers on a native SurfaceView *under* a
  /// translucent Flutter surface (a hardware overlay plane — Flutter never
  /// composites the video frames) instead of a Flutter Texture. Default on;
  /// the toggle is the escape hatch back to the Texture path for boxes where
  /// the underlay misbehaves. MainActivity reads the same key natively (the
  /// surface mode is fixed at activity creation), so changes take effect on
  /// the next app start.
  static Future<bool> getTvTrailerUnderlayEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('tv_trailer_underlay_enabled') ?? true;
  }

  static Future<void> setTvTrailerUnderlayEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tv_trailer_underlay_enabled', enabled);
  }

  /// First-read-wins snapshot for engine selection. The native side decides
  /// the EFFECTIVE underlay mode at activity creation (user toggle AND device
  /// capability — GLES2-class GPUs can't afford the permanently-translucent
  /// surface, so MainActivity keeps them opaque) and persists it under
  /// `tv_trailer_underlay_effective` BEFORE the first Dart frame. Trust that
  /// over the raw toggle so both sides always agree — an underlay hole
  /// against an opaque Flutter surface would render a black region instead
  /// of video (and the reverse would silently fall back to Texture, which at
  /// least works). Restarting the app applies changes to both sides together.
  static bool? _tvTrailerUnderlaySession;
  static Future<bool> getTvTrailerUnderlayEnabledAtLaunch() async {
    if (_tvTrailerUnderlaySession != null) return _tvTrailerUnderlaySession!;
    final device = await DevicePreferences.instance();
    final effective = device.getBool(
      DevicePreferences.tvTrailerUnderlayEffectiveKey,
    );
    if (effective != null) {
      return _tvTrailerUnderlaySession = effective;
    }
    final prefs = await ProfilePreferences.instance();
    return _tvTrailerUnderlaySession =
        prefs.getBool('tv_trailer_underlay_enabled') ?? true;
  }

  @visibleForTesting
  static void debugResetTvTrailerUnderlaySession() {
    _tvTrailerUnderlaySession = null;
  }






  static const Set<String> kTvHomeStyles = HomePrefs.kTvHomeStyles;

  static String get tvHomeStyleCached => HomePrefs.tvHomeStyleCached;
  static set tvHomeStyleCached(String value) =>
      HomePrefs.tvHomeStyleCached = value;

  static Future<String> getTvHomeStyle() => HomePrefs.getTvHomeStyle();

  static Future<void> setTvHomeStyle(String style) =>
      HomePrefs.setTvHomeStyle(style);




  // App style — forwarding façade; bodies live on AppStylePrefs.
  static const List<int> kTvUiScaleOptions = AppStylePrefs.kTvUiScaleOptions;
  static const int kTvUiScaleDefault = AppStylePrefs.kTvUiScaleDefault;
  static const Set<String> kDebrifyTvStyles = AppStylePrefs.kDebrifyTvStyles;
  static const Set<String> kDetailPageStyles = AppStylePrefs.kDetailPageStyles;
  static const String kDetailPageStyleDefault = AppStylePrefs.kDetailPageStyleDefault;
  static const Set<String> kDetailThemes = AppStylePrefs.kDetailThemes;
  static const Set<String> kParentsGuideStyles = AppStylePrefs.kParentsGuideStyles;
  static const String discoverDefaultRememberLast = AppStylePrefs.discoverDefaultRememberLast;
  @visibleForTesting
  static Set<String> get launchAnimationValues => AppStylePrefs.launchAnimationValues;

  static String get debrifyTvStyleCached => AppStylePrefs.debrifyTvStyleCached;
  static set debrifyTvStyleCached(String value) => AppStylePrefs.debrifyTvStyleCached = value;
  static String get detailPageStyleCached => AppStylePrefs.detailPageStyleCached;
  static set detailPageStyleCached(String value) => AppStylePrefs.detailPageStyleCached = value;
  static String get detailThemeCached => AppStylePrefs.detailThemeCached;
  static set detailThemeCached(String value) => AppStylePrefs.detailThemeCached = value;
  static String get appThemeCached => AppStylePrefs.appThemeCached;
  static set appThemeCached(String value) => AppStylePrefs.appThemeCached = value;
  static String get themeOverridesCached => AppStylePrefs.themeOverridesCached;
  static set themeOverridesCached(String value) => AppStylePrefs.themeOverridesCached = value;
  static String get parentsGuideStyleCached => AppStylePrefs.parentsGuideStyleCached;
  static set parentsGuideStyleCached(String value) => AppStylePrefs.parentsGuideStyleCached = value;
  static String get iptvStyleCached => AppStylePrefs.iptvStyleCached;
  static set iptvStyleCached(String value) => AppStylePrefs.iptvStyleCached = value;
  static String get discoverLayoutCached => AppStylePrefs.discoverLayoutCached;
  static set discoverLayoutCached(String value) => AppStylePrefs.discoverLayoutCached = value;
  static String get launchAnimationCached => AppStylePrefs.launchAnimationCached;
  static set launchAnimationCached(String value) => AppStylePrefs.launchAnimationCached = value;
  static String get launchIdentPaletteCached => AppStylePrefs.launchIdentPaletteCached;
  static set launchIdentPaletteCached(String value) => AppStylePrefs.launchIdentPaletteCached = value;
  static String get tvSidebarStyleCached => AppStylePrefs.tvSidebarStyleCached;
  static set tvSidebarStyleCached(String value) => AppStylePrefs.tvSidebarStyleCached = value;
  static String get desktopSidebarStyleCached => AppStylePrefs.desktopSidebarStyleCached;
  static set desktopSidebarStyleCached(String value) => AppStylePrefs.desktopSidebarStyleCached = value;
  static SidebarConfiguration get sidebarConfigurationCached => AppStylePrefs.sidebarConfigurationCached;
  static set sidebarConfigurationCached(SidebarConfiguration value) => AppStylePrefs.sidebarConfigurationCached = value;

  static Future<int> getTvUiScalePercent() => AppStylePrefs.getTvUiScalePercent();
  static Future<void> setTvUiScalePercent(int percent) => AppStylePrefs.setTvUiScalePercent(percent);
  static Future<TvHeroArtworkQuality> getTvHeroArtworkQuality() => AppStylePrefs.getTvHeroArtworkQuality();
  static Future<void> setTvHeroArtworkQuality(TvHeroArtworkQuality quality) => AppStylePrefs.setTvHeroArtworkQuality(quality);
  static Future<String> getPhoneNavStyle() => AppStylePrefs.getPhoneNavStyle();
  static Future<void> setPhoneNavStyle(String style) => AppStylePrefs.setPhoneNavStyle(style);
  static Future<List<int>?> getPhoneNavBarIndices() => AppStylePrefs.getPhoneNavBarIndices();
  static Future<void> setPhoneNavBarIndices(List<int> indices) => AppStylePrefs.setPhoneNavBarIndices(indices);
  static Future<String> getDebrifyTvStyle() => AppStylePrefs.getDebrifyTvStyle();
  static Future<void> setDebrifyTvStyle(String style) => AppStylePrefs.setDebrifyTvStyle(style);
  static Future<String> getDetailPageStyle() => AppStylePrefs.getDetailPageStyle();
  static Future<void> setDetailPageStyle(String value) => AppStylePrefs.setDetailPageStyle(value);
  static Future<String> getDetailTheme() => AppStylePrefs.getDetailTheme();
  static Future<void> setDetailTheme(String value) => AppStylePrefs.setDetailTheme(value);
  static Future<String> getAppTheme() => AppStylePrefs.getAppTheme();
  static Future<void> setAppTheme(String value) => AppStylePrefs.setAppTheme(value);
  static Future<String> getThemeOverrides() => AppStylePrefs.getThemeOverrides();
  static Future<void> setThemeOverrides(String raw) => AppStylePrefs.setThemeOverrides(raw);
  static Future<String> getParentsGuideStyle() => AppStylePrefs.getParentsGuideStyle();
  static Future<void> setParentsGuideStyle(String value) => AppStylePrefs.setParentsGuideStyle(value);
  static Future<bool> getIptvChannelPreviewEnabled() => AppStylePrefs.getIptvChannelPreviewEnabled();
  static Future<void> setIptvChannelPreviewEnabled(bool enabled) => AppStylePrefs.setIptvChannelPreviewEnabled(enabled);
  static Future<String> getIptvStyle() => AppStylePrefs.getIptvStyle();
  static Future<void> setIptvStyle(String style) => AppStylePrefs.setIptvStyle(style);
  static Future<String> getPlayerDockStyle() => AppStylePrefs.getPlayerDockStyle();
  static Future<void> setPlayerDockStyle(String style) => AppStylePrefs.setPlayerDockStyle(style);
  static Future<String> getPlayerDockPalette() => AppStylePrefs.getPlayerDockPalette();
  static Future<void> setPlayerDockPalette(String palette) => AppStylePrefs.setPlayerDockPalette(palette);
  static Future<String> getPlayerDockSize() => AppStylePrefs.getPlayerDockSize();
  static Future<void> setPlayerDockSize(String size) => AppStylePrefs.setPlayerDockSize(size);
  static Future<String> getIptvPlayerGuideStyle() => AppStylePrefs.getIptvPlayerGuideStyle();
  static Future<void> setIptvPlayerGuideStyle(String style) => AppStylePrefs.setIptvPlayerGuideStyle(style);
  static Future<String> getPlayLoaderStyle() => AppStylePrefs.getPlayLoaderStyle();
  static Future<void> setPlayLoaderStyle(String style) => AppStylePrefs.setPlayLoaderStyle(style);
  static Future<String> getTvPlayerControlsStyle() => AppStylePrefs.getTvPlayerControlsStyle();
  static Future<void> setTvPlayerControlsStyle(String style) => AppStylePrefs.setTvPlayerControlsStyle(style);
  static Future<String> getDebrifyTvPlayerStyle() => AppStylePrefs.getDebrifyTvPlayerStyle();
  static Future<void> setDebrifyTvPlayerStyle(String style) => AppStylePrefs.setDebrifyTvPlayerStyle(style);
  static Future<String> getDiscoverDefaultSource() => AppStylePrefs.getDiscoverDefaultSource();
  static Future<void> setDiscoverDefaultSource(String value) => AppStylePrefs.setDiscoverDefaultSource(value);
  static Future<String> getDiscoverLastSource() => AppStylePrefs.getDiscoverLastSource();
  static Future<void> setDiscoverLastSource(String value) => AppStylePrefs.setDiscoverLastSource(value);
  static Future<String> getDiscoverLayout() => AppStylePrefs.getDiscoverLayout();
  static Future<void> setDiscoverLayout(String layout) => AppStylePrefs.setDiscoverLayout(layout);
  static Future<String> getLaunchAnimation() => AppStylePrefs.getLaunchAnimation();
  static Future<void> setLaunchAnimation(String value) => AppStylePrefs.setLaunchAnimation(value);
  static Future<String> getLaunchIdentPalette() => AppStylePrefs.getLaunchIdentPalette();
  static Future<void> setLaunchIdentPalette(String value) => AppStylePrefs.setLaunchIdentPalette(value);
  static Future<String> getTextBrightness() => AppStylePrefs.getTextBrightness();
  static Future<void> setTextBrightness(String value) => AppStylePrefs.setTextBrightness(value);
  static Future<String> getTvSidebarStyle() => AppStylePrefs.getTvSidebarStyle();
  static Future<void> setTvSidebarStyle(String style) => AppStylePrefs.setTvSidebarStyle(style);
  static Future<String> getDesktopSidebarStyle() => AppStylePrefs.getDesktopSidebarStyle();
  static Future<void> setDesktopSidebarStyle(String style) => AppStylePrefs.setDesktopSidebarStyle(style);
  static Future<SidebarConfiguration> getSidebarConfiguration() => AppStylePrefs.getSidebarConfiguration();
  static Future<bool> setSidebarConfiguration(SidebarConfiguration configuration) => AppStylePrefs.setSidebarConfiguration(configuration);
  static Future<bool> resetSidebarConfiguration() => AppStylePrefs.resetSidebarConfiguration();











  // Premiumize API key helpers
  static Future<String?> getPremiumizeApiKey({
    bool forRemoteTransfer = false,
  }) =>
      CloudSecretPrefs.read(
        _premiumizeApiKey,
        forRemoteTransfer: forRemoteTransfer,
      );

  static Future<bool> hasPremiumizeCredential() =>
      CloudSecretPrefs.isConfigured(_premiumizeApiKey);

  static Future<void> savePremiumizeApiKey(String apiKey) =>
      CloudSecretPrefs.write(_premiumizeApiKey, apiKey);

  static Future<void> deletePremiumizeApiKey() =>
      CloudSecretPrefs.delete(_premiumizeApiKey);






  // AllDebrid API key helpers
  static Future<String?> getAllDebridApiKey({
    bool forRemoteTransfer = false,
  }) =>
      CloudSecretPrefs.read(
        _allDebridApiKey,
        forRemoteTransfer: forRemoteTransfer,
      );

  static Future<bool> hasAllDebridCredential() =>
      CloudSecretPrefs.isConfigured(_allDebridApiKey);

  static Future<void> saveAllDebridApiKey(String apiKey) =>
      CloudSecretPrefs.write(_allDebridApiKey, apiKey);

  static Future<void> deleteAllDebridApiKey() =>
      CloudSecretPrefs.delete(_allDebridApiKey);

  // MDBList — forwarding façade; bodies live on TrackingPrefs.
  static Future<String?> getMdblistApiKey({bool forRemoteTransfer = false}) =>
      TrackingPrefs.getMdblistApiKey(forRemoteTransfer: forRemoteTransfer);
  static Future<bool> hasMdblistCredential() => TrackingPrefs.hasMdblistCredential();
  static Future<void> saveMdblistApiKey(String apiKey) => TrackingPrefs.saveMdblistApiKey(apiKey);
  static Future<String?> getMdblistUsername() => TrackingPrefs.getMdblistUsername();
  static Future<void> setMdblistUsername(String? username) => TrackingPrefs.setMdblistUsername(username);
  static Future<void> clearMdblistAuth() => TrackingPrefs.clearMdblistAuth();
  static Future<Map<int, int>> getMdblistSavedClones() => TrackingPrefs.getMdblistSavedClones();
  static Future<void> setMdblistSavedClone(int sourceId, int clonedId) => TrackingPrefs.setMdblistSavedClone(sourceId, clonedId);
  static Future<void> removeMdblistSavedClone(int sourceId) => TrackingPrefs.removeMdblistSavedClone(sourceId);
  static Future<void> retireMdblistSavedCloneMarkers() => TrackingPrefs.retireMdblistSavedCloneMarkers();
  static Future<Map<String, dynamic>?> getMdblistSyncCheckpoint() => TrackingPrefs.getMdblistSyncCheckpoint();
  static Future<void> setMdblistSyncCheckpoint(Map<String, dynamic>? value) => TrackingPrefs.setMdblistSyncCheckpoint(value);



  // AllDebrid post-torrent action methods


  // AllDebrid hide-from-navigation



  static Future<bool> isInitialSetupComplete() =>
      ProfileOnboardingState.isInitialSetupComplete();

  static Future<void> setInitialSetupComplete(bool value) =>
      ProfileOnboardingState.setInitialSetupComplete(value);

  // File Selection methods


  // Post-torrent action methods


  // TorBox post-torrent action methods


  // PikPak post-torrent action methods


  // Premiumize post-torrent action methods




  // Battery optimization status
  static Future<String> getBatteryOptimizationStatus() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_batteryOptStatusKey) ?? 'unknown';
  }

  static Future<void> setBatteryOptimizationStatus(String status) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_batteryOptStatusKey, status);
  }

  // Download settings - Fixed to 1 parallel download
  static Future<int> getMaxParallelDownloads() async {
    return 1; // Always return 1 for single download at a time
  }

  static Future<void> setMaxParallelDownloads(int value) async {
    // No-op: parallel downloads are fixed to 1
  }

  // ── Custom download location (Android SAF tree) ─────────────────────────
  static const String _downloadTreeUriKey = 'download_tree_uri_v1';
  static const String _downloadTreeNameKey = 'download_tree_display_name_v1';

  /// The persisted SAF tree URI for the user-chosen download folder, or null
  /// when downloads go to the default location (Downloads/Debrify).
  static Future<String?> getDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeUriKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<String?> getDownloadTreeDisplayName() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeNameKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadTreeUri(
    String treeUri,
    String displayName,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadTreeUriKey, treeUri);
    await prefs.setString(_downloadTreeNameKey, displayName);
  }

  static Future<void> clearDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadTreeUriKey);
    await prefs.remove(_downloadTreeNameKey);
  }

  // ── Custom download location (desktop: plain filesystem path) ───────────
  // Windows/Linux only. macOS is deliberately excluded: the app is sandboxed
  // with a read-only user-selected-files entitlement, so a picked folder
  // needs security-scoped bookmarks to survive relaunch — separate feature.
  static const String _downloadDirPathKey = 'download_dir_path_v1';

  /// The persisted absolute directory for the user-chosen download folder on
  /// desktop, or null when downloads go to the platform default.
  static Future<String?> getDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadDirPathKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadDirPath(String dirPath) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadDirPathKey, dirPath);
  }

  static Future<void> clearDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadDirPathKey);
  }




































  static Future<Map<String, dynamic>?> getVideoPlaybackState({
    required String videoTitle,
  }) =>
      PlaybackProgressStore.getVideoPlaybackState(videoTitle: videoTitle);








  static Future<Map<String, dynamic>?> getVideoResume(String key) {
    return IptvMediaStore.videoResume(key);
  }

  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry,
  ) {
    return IptvMediaStore.upsertVideoResume(key, entry);
  }

  static Future<void> removeVideoResume(String key) {
    return IptvMediaStore.removeVideoResume(key);
  }




  // Debrify TV settings — forwarding façade; bodies live on DebrifyTvPrefs.
  static Future<String> getDebrifyTvProvider() =>
      DebrifyTvPrefs.getDebrifyTvProvider();

  static Future<void> saveDebrifyTvProvider(String value) =>
      DebrifyTvPrefs.saveDebrifyTvProvider(value);

  static Future<bool> hasDebrifyTvProvider() =>
      DebrifyTvPrefs.hasDebrifyTvProvider();

  static Future<bool> getDebrifyTvStartRandom() =>
      DebrifyTvPrefs.getDebrifyTvStartRandom();

  static Future<void> saveDebrifyTvStartRandom(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvStartRandom(value);

  static Future<int> getDebrifyTvRandomStartPercent() =>
      DebrifyTvPrefs.getDebrifyTvRandomStartPercent();

  static Future<void> saveDebrifyTvRandomStartPercent(int value) =>
      DebrifyTvPrefs.saveDebrifyTvRandomStartPercent(value);

  static Future<bool> getDebrifyTvHideSeekbar() =>
      DebrifyTvPrefs.getDebrifyTvHideSeekbar();

  static Future<void> saveDebrifyTvHideSeekbar(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvHideSeekbar(value);

  static Future<bool> getDebrifyTvShowChannelName() =>
      DebrifyTvPrefs.getDebrifyTvShowChannelName();

  static Future<void> saveDebrifyTvShowChannelName(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvShowChannelName(value);

  static Future<bool> getDebrifyTvShowVideoTitle() =>
      DebrifyTvPrefs.getDebrifyTvShowVideoTitle();

  static Future<void> saveDebrifyTvShowVideoTitle(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvShowVideoTitle(value);

  static Future<bool> getDebrifyTvHideOptions() =>
      DebrifyTvPrefs.getDebrifyTvHideOptions();

  static Future<void> saveDebrifyTvHideOptions(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvHideOptions(value);

  static Future<bool> getDebrifyTvHideBackButton() =>
      DebrifyTvPrefs.getDebrifyTvHideBackButton();

  static Future<void> saveDebrifyTvHideBackButton(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvHideBackButton(value);

  static Future<bool> getDebrifyTvAvoidNsfw() =>
      DebrifyTvPrefs.getDebrifyTvAvoidNsfw();

  static Future<void> saveDebrifyTvAvoidNsfw(bool value) =>
      DebrifyTvPrefs.saveDebrifyTvAvoidNsfw(value);

  static Future<List<Map<String, dynamic>>> getDebrifyTvChannels() =>
      DebrifyTvPrefs.getDebrifyTvChannels();

  static Future<void> saveDebrifyTvChannels(
    List<Map<String, dynamic>> channels,
  ) => DebrifyTvPrefs.saveDebrifyTvChannels(channels);










  static Future<void> clearAllStartupSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_startupAutoLaunchEnabledKey);
    await prefs.remove(_startupChannelIdKey);
    await prefs.remove(_startupStremioTvChannelIdKey);
    await prefs.remove(_startupModeKey);
    await prefs.remove(_startupPlaylistItemIdKey);
    await prefs.remove(_startupContinueWatchingItemIdKey);
    await prefs.remove(_startupTraktContinueWatchingMovieIdKey);
    await prefs.remove(_startupTraktContinueWatchingShowIdKey);
    // The startup-channel memory is a startup reference too — Reset must wipe
    // it, or a fresh setup would inherit the previous install's channel.
    await IptvPrefs.clearStartupIptvKeys();
  }

  /// Clear integration enabled states (RD, TorBox)

  /// Clear Debrify TV provider and legacy channels key
  static Future<void> clearDebrifyTvProviderAndLegacy() =>
      DebrifyTvPrefs.clearDebrifyTvProviderAndLegacy();


  /// Clear filter settings (qualities, rip sources, languages)
  static Future<void> clearAllFilterSettings() async {
    final prefs = await ProfilePreferences.instance();
    await DefaultTorrentFilterPrefs.clearDefaults(prefs);
    await ProviderCredentialPrefs.clearDefaultTorrentProvider();
  }

  /// Clear torrent engine toggles and limits
  static Future<void> clearAllTorrentEngineSettings() async {
    final prefs = await ProfilePreferences.instance();
    final keys = prefs.getKeys().where(
      (key) =>
          (key.startsWith('engine_') && !key.startsWith('engine_tv_')) ||
          (key.startsWith('default_') && key.endsWith('_enabled')) ||
          (key.startsWith('max_') && key.endsWith('_results')),
    );
    for (final key in keys.toList()) {
      await prefs.remove(key);
    }
  }

  /// Clear post-torrent action preferences

  /// Clear all Debrify TV display and engine settings
  static Future<void> clearAllDebrifyTvSettings() =>
      DebrifyTvPrefs.clearAllDebrifyTvSettings();


  /// Update an existing playlist item with poster URL






  // My Watchlist (movies + series)
  // ========================================================================

  /// Stable identity for Debrify's local movie/series watchlist. Prefer IMDb
  /// so the same title coming from two addons is one entry; fall back to the
  /// source addon + its content id for titles that do not expose IMDb metadata.
  /// Addon ids are part of that fallback because content ids are addon-local.

  /// Returns the identity-bearing item used by both watchlist reads and
  /// writes. A stored source is authoritative for non-IMDb ids; [fallback]
  /// only fills in a source for a newly opened source-less item.

  static String myWatchlistItemKey(StremioMeta item) =>
      MyWatchlistStore.myWatchlistItemKey(item);

  /// tvOS durability ceiling for the encoded watchlist. The recovery envelope
  /// silently skips any single value over its per-value limit, which would
  /// resurrect the wipe-on-restart bug; the 16KiB margin covers the
  /// JSON-escaping inflation the value picks up inside the envelope.
  static const int myWatchlistTvOsCapBytes =
      MyWatchlistStore.myWatchlistTvOsCapBytes;

  /// Test seam: `PlatformUtil.isTvOS` is a `static final` and cannot be
  /// overridden, so tests drive the cap through this instead.
  @visibleForTesting
  static bool? get debugMyWatchlistTvOsCapOverride =>
      MyWatchlistStore.debugMyWatchlistTvOsCapOverride;
  @visibleForTesting
  static set debugMyWatchlistTvOsCapOverride(bool? value) =>
      MyWatchlistStore.debugMyWatchlistTvOsCapOverride = value;





  /// Saved titles, newest first. Corrupt individual rows are ignored so one
  /// bad addon payload cannot make the whole shelf disappear.


  /// Adds, refreshes, or removes a title. Adding stores the full presentation
  /// metadata needed by Home, not just an id, so My Watchlist paints instantly
  /// offline and can route back through the source addon when it is installed.

  /// Removes a saved movie/series once actual playback is about to launch.
  /// IMDb is authoritative. Older/addon-local items without IMDb metadata use
  /// a conservative title/source fallback and are removed only when unique.
  static Future<bool> removeMyWatchlistItemForPlayback({
    String? imdbId,
    required String contentType,
    required String title,
    String? addonId,
  }) => MyWatchlistStore.removeMyWatchlistItemForPlayback(
    imdbId: imdbId,
    contentType: contentType,
    title: title,
    addonId: addonId,
  );


  // Debrify TV Channel Favorites — forwarding façade; bodies live on DebrifyTvPrefs.
  static Future<bool> isDebrifyTvChannelFavorited(String channelId) =>
      DebrifyTvPrefs.isDebrifyTvChannelFavorited(channelId);

  static Future<void> setDebrifyTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) => DebrifyTvPrefs.setDebrifyTvChannelFavorited(channelId, isFavorited);

  static Future<Set<String>> getDebrifyTvFavoriteChannelIds() =>
      DebrifyTvPrefs.getDebrifyTvFavoriteChannelIds();


  // ==========================================================================
  // IPTV Channel Favorites — forwarding façade; bodies live on IptvPrefs.
  // ==========================================================================




  static Future<void> setIptvChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) => IptvPrefs.setIptvChannelFavorited(
    channelUrl,
    isFavorited,
    channelName: channelName,
    logoUrl: logoUrl,
    group: group,
    playlistId: playlistId,
    channelNumber: channelNumber,
    contentType: contentType,
    duration: duration,
    httpHeaders: httpHeaders,
  );






  static Future<void> setIptvChannelInList(
    String listId,
    String channelUrl,
    bool inList, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) => IptvPrefs.setIptvChannelInList(
    listId,
    channelUrl,
    inList,
    channelName: channelName,
    logoUrl: logoUrl,
    group: group,
    playlistId: playlistId,
    channelNumber: channelNumber,
    contentType: contentType,
    duration: duration,
    httpHeaders: httpHeaders,
  );









  static Future<Set<String>> getIptvListsForChannel(String channelUrl) =>
      IptvPrefs.getIptvListsForChannel(channelUrl);








  static Future<void> recordIptvWatch(
    String channelUrl, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
    String? seriesId,
    String? seriesName,
    int? season,
    int? episode,
    bool? hasNextEpisode,
  }) => IptvPrefs.recordIptvWatch(
    channelUrl,
    channelName: channelName,
    logoUrl: logoUrl,
    group: group,
    playlistId: playlistId,
    httpHeaders: httpHeaders,
    seriesId: seriesId,
    seriesName: seriesName,
    season: season,
    episode: episode,
    hasNextEpisode: hasNextEpisode,
  );




  static Future<Map<String, int>> getIptvResumePositions(
    Iterable<String> urls,
  ) => IptvPrefs.getIptvResumePositions(urls);




  /// Build progress map for playlist items
  /// Maps playlist dedupe keys to their playback progress data

  // Startup auto-launch was removed; only [clearAllStartupSettings] remains
  // (used by Reset) to wipe the old persisted keys.

  // Home Page Default Settings — forwarding façade; bodies live on HomePrefs.
  static Future<String?> getHomeDefaultSourceType() =>
      HomePrefs.getHomeDefaultSourceType();

  static Future<void> setHomeDefaultSourceType(String? value) =>
      HomePrefs.setHomeDefaultSourceType(value);

  static Future<String?> getHomeDefaultAddonUrl() =>
      HomePrefs.getHomeDefaultAddonUrl();

  static Future<void> setHomeDefaultAddonUrl(String? value) =>
      HomePrefs.setHomeDefaultAddonUrl(value);

  static Future<String?> getHomeDefaultCatalogId() =>
      HomePrefs.getHomeDefaultCatalogId();

  static Future<void> setHomeDefaultCatalogId(String? value) =>
      HomePrefs.setHomeDefaultCatalogId(value);

  static Future<String?> getHomeDefaultTraktListType() =>
      HomePrefs.getHomeDefaultTraktListType();

  static Future<void> setHomeDefaultTraktListType(String? value) =>
      HomePrefs.setHomeDefaultTraktListType(value);

  static Future<String?> getHomeDefaultTraktContentType() =>
      HomePrefs.getHomeDefaultTraktContentType();

  static Future<void> setHomeDefaultTraktContentType(String? value) =>
      HomePrefs.setHomeDefaultTraktContentType(value);

  static Future<bool> getHomeHideProviderCards() =>
      HomePrefs.getHomeHideProviderCards();

  static Future<void> setHomeHideProviderCards(bool value) =>
      HomePrefs.setHomeHideProviderCards(value);

  static Future<bool> getHomeContinueWatchingEnabled() =>
      HomePrefs.getHomeContinueWatchingEnabled();

  static Future<void> setHomeContinueWatchingEnabled(bool value) =>
      HomePrefs.setHomeContinueWatchingEnabled(value);

  static Future<bool> getHomeCwHoldToQuickPlay() =>
      HomePrefs.getHomeCwHoldToQuickPlay();

  static Future<void> setHomeCwHoldToQuickPlay(bool value) =>
      HomePrefs.setHomeCwHoldToQuickPlay(value);

  static Future<bool> getHomeCwMergedRows(String provider) =>
      HomePrefs.getHomeCwMergedRows(provider);

  static Future<void> setHomeCwMergedRows(String provider, bool value) =>
      HomePrefs.setHomeCwMergedRows(provider, value);

  static Future<String> getHomeFavoritesTapAction() =>
      HomePrefs.getHomeFavoritesTapAction();

  static Future<void> setHomeFavoritesTapAction(String value) =>
      HomePrefs.setHomeFavoritesTapAction(value);

  static Future<HomeCardOrientation> getHomeCardOrientation() =>
      HomePrefs.getHomeCardOrientation();

  static Future<void> setHomeCardOrientation(
    HomeCardOrientation orientation,
  ) => HomePrefs.setHomeCardOrientation(orientation);

  static Future<bool> getHomeHideCardTitlesAndRatings() =>
      HomePrefs.getHomeHideCardTitlesAndRatings();

  static Future<void> setHomeHideCardTitlesAndRatings(bool value) =>
      HomePrefs.setHomeHideCardTitlesAndRatings(value);

  static Future<bool> getHomeHideCatalogAddonNames() =>
      HomePrefs.getHomeHideCatalogAddonNames();

  static Future<void> setHomeHideCatalogAddonNames(bool value) =>
      HomePrefs.setHomeHideCatalogAddonNames(value);

  static Future<void> clearAllHomePageSettings() =>
      HomePrefs.clearAllHomePageSettings();

  // Reddit Settings — forwarding façade; bodies live on SocialPrefs.
  static Future<String?> getRedditAccessToken() =>
      SocialPrefs.getRedditAccessToken();

  static Future<void> setRedditAccessToken(String token) =>
      SocialPrefs.setRedditAccessToken(token);

  static Future<String?> getRedditRefreshToken() =>
      SocialPrefs.getRedditRefreshToken();

  static Future<void> setRedditRefreshToken(String token) =>
      SocialPrefs.setRedditRefreshToken(token);

  static Future<String?> getRedditUsername() => SocialPrefs.getRedditUsername();

  static Future<void> setRedditUsername(String username) =>
      SocialPrefs.setRedditUsername(username);

  static Future<bool> getRedditEnabled() => SocialPrefs.getRedditEnabled();

  static Future<void> setRedditEnabled(bool value) =>
      SocialPrefs.setRedditEnabled(value);

  static Future<bool> getRedditHiddenFromNav() =>
      SocialPrefs.getRedditHiddenFromNav();

  static Future<void> setRedditHiddenFromNav(bool value) =>
      SocialPrefs.setRedditHiddenFromNav(value);


  // Tracking source policy — forwarding façade; bodies live on TrackingPrefs.
  static Future<Set<TrackingSource>> getTrackingScrobbleTargets() => TrackingPrefs.getTrackingScrobbleTargets();
  static Future<void> setTrackingScrobbleTargets(Set<TrackingSource> value) => TrackingPrefs.setTrackingScrobbleTargets(value);
  static Future<void> enableTrackingScrobbleTarget(TrackingSource source) => TrackingPrefs.enableTrackingScrobbleTarget(source);
  static Future<WatchProgressSource> getWatchProgressSource() => TrackingPrefs.getWatchProgressSource();
  static Future<void> setWatchProgressSource(WatchProgressSource value) => TrackingPrefs.setWatchProgressSource(value);
  static Future<bool> fallbackDisconnectedProgressSource(TrackingSource disconnected) => TrackingPrefs.fallbackDisconnectedProgressSource(disconnected);
  static Future<bool> takeTrackingProgressFallbackNotice() => TrackingPrefs.takeTrackingProgressFallbackNotice();
  static Future<Set<TrackingSource>> getHomeTickSources() => TrackingPrefs.getHomeTickSources();
  static Future<void> setHomeTickSources(Set<TrackingSource> value) => TrackingPrefs.setHomeTickSources(value);
  static Future<Map<String, dynamic>> buildTrackingPreferencesPayload() => TrackingPrefs.buildTrackingPreferencesPayload();
  static Future<void> reseedTrackingScrobbleTargetsFromLegacy() => TrackingPrefs.reseedTrackingScrobbleTargetsFromLegacy();
  static Future<void> applyTrackingPreferencesPayload(Map<dynamic, dynamic> payload) => TrackingPrefs.applyTrackingPreferencesPayload(payload);

  static Future<String?> getRedditLastSubreddit() =>
      SocialPrefs.getRedditLastSubreddit();

  static Future<void> setRedditLastSubreddit(String subreddit) =>
      SocialPrefs.setRedditLastSubreddit(subreddit);

  static Future<void> clearRedditAuth() => SocialPrefs.clearRedditAuth();


  // Trakt / Simkl / MDBList catalog + credentials — TrackingPrefs façade.
  static Future<bool> getTraktSyncCatalogItems() => TrackingPrefs.getTraktSyncCatalogItems();
  static Future<void> setTraktSyncCatalogItems(bool value) => TrackingPrefs.setTraktSyncCatalogItems(value);
  static Future<String?> getTraktAccessToken({bool forRemoteTransfer = false}) =>
      TrackingPrefs.getTraktAccessToken(forRemoteTransfer: forRemoteTransfer);
  static Future<bool> hasTraktCredential() => TrackingPrefs.hasTraktCredential();
  static Future<void> setTraktAccessToken(String token) => TrackingPrefs.setTraktAccessToken(token);
  static Future<String?> getTraktRefreshToken({bool forRemoteTransfer = false}) =>
      TrackingPrefs.getTraktRefreshToken(forRemoteTransfer: forRemoteTransfer);
  static Future<void> setTraktRefreshToken(String token) => TrackingPrefs.setTraktRefreshToken(token);
  static Future<String?> getTraktUsername() => TrackingPrefs.getTraktUsername();
  static Future<void> setTraktUsername(String username) => TrackingPrefs.setTraktUsername(username);
  static Future<int?> getTraktTokenExpiry() => TrackingPrefs.getTraktTokenExpiry();
  static Future<void> setTraktTokenExpiry(int expiryMs) => TrackingPrefs.setTraktTokenExpiry(expiryMs);
  static Future<bool> clearTraktAuth() => TrackingPrefs.clearTraktAuth();
  static Future<void> setSimklSyncCatalogItems(bool value) => TrackingPrefs.setSimklSyncCatalogItems(value);
  static Future<bool> getSimklSyncCatalogItems() => TrackingPrefs.getSimklSyncCatalogItems();
  static Future<void> setMdblistSyncCatalogItems(bool value) => TrackingPrefs.setMdblistSyncCatalogItems(value);
  static Future<bool> getMdblistSyncCatalogItems() => TrackingPrefs.getMdblistSyncCatalogItems();
  static Future<String?> getSimklAccessToken({bool forRemoteTransfer = false}) =>
      TrackingPrefs.getSimklAccessToken(forRemoteTransfer: forRemoteTransfer);
  static Future<bool> hasSimklCredential() => TrackingPrefs.hasSimklCredential();
  static Future<void> setSimklAccessToken(String token) => TrackingPrefs.setSimklAccessToken(token);
  static Future<String?> getSimklUsername() => TrackingPrefs.getSimklUsername();
  static Future<void> setSimklUsername(String username) => TrackingPrefs.setSimklUsername(username);
  static Future<void> clearSimklAuth() => TrackingPrefs.clearSimklAuth();

  static Future<List<String>> getRedditRecentSubreddits() =>
      SocialPrefs.getRedditRecentSubreddits();

  static Future<void> setRedditRecentSubreddits(List<String> subreddits) =>
      SocialPrefs.setRedditRecentSubreddits(subreddits);

  static Future<bool> getRedditAllowNsfw() => SocialPrefs.getRedditAllowNsfw();

  static Future<void> setRedditAllowNsfw(bool value) =>
      SocialPrefs.setRedditAllowNsfw(value);

  static Future<List<String>> getRedditFavoriteSubreddits() =>
      SocialPrefs.getRedditFavoriteSubreddits();

  static Future<void> setRedditFavoriteSubreddits(
    List<String> subreddits,
  ) => SocialPrefs.setRedditFavoriteSubreddits(subreddits);

  static Future<String?> getRedditDefaultSubreddit() =>
      SocialPrefs.getRedditDefaultSubreddit();

  static Future<void> setRedditDefaultSubreddit(String? subreddit) =>
      SocialPrefs.setRedditDefaultSubreddit(subreddit);

  // Lemmy Settings — forwarding façade; bodies live on SocialPrefs.
  static Future<String> getLemmyInstance() => SocialPrefs.getLemmyInstance();

  static Future<void> setLemmyInstance(String instance) =>
      SocialPrefs.setLemmyInstance(instance);

  static Future<bool> getLemmyAllowNsfw() => SocialPrefs.getLemmyAllowNsfw();

  static Future<void> setLemmyAllowNsfw(bool value) =>
      SocialPrefs.setLemmyAllowNsfw(value);

  static Future<List<String>> getLemmyFavoriteCommunities() =>
      SocialPrefs.getLemmyFavoriteCommunities();

  static Future<void> setLemmyFavoriteCommunities(
    List<String> communities,
  ) => SocialPrefs.setLemmyFavoriteCommunities(communities);

  static Future<String?> getLemmyDefaultCommunity() =>
      SocialPrefs.getLemmyDefaultCommunity();

  static Future<void> setLemmyDefaultCommunity(String? community) =>
      SocialPrefs.setLemmyDefaultCommunity(community);

  // YouTube Settings — forwarding façade; bodies live on SocialPrefs.
  static Future<int> getYoutubeMaxHeight() => SocialPrefs.getYoutubeMaxHeight();

  static Future<void> setYoutubeMaxHeight(int height) =>
      SocialPrefs.setYoutubeMaxHeight(height);


  /// Android TV IPTV video decoder: 'auto' | 'hardware' | 'software'.
  static Future<String> getIptvDecoderMode() => IptvPrefs.getIptvDecoderMode();


  // Network tuning (Debrify player) — forwarding façade; bodies live on PlayerPrefs.
  static Future<String> getNetworkConnectPatience() =>
      PlayerPrefs.getNetworkConnectPatience();

  static Future<void> setNetworkConnectPatience(String value) =>
      PlayerPrefs.setNetworkConnectPatience(value);

  static Future<String> getNetworkBufferSize() =>
      PlayerPrefs.getNetworkBufferSize();

  static Future<void> setNetworkBufferSize(String value) =>
      PlayerPrefs.setNetworkBufferSize(value);


  /// Percentage of a movie that must be watched before the local player marks
  /// it complete. Tracker-backed sessions retain Trakt/Simkl's own semantics.


  /// Percentage of an episode that must be watched before the local player
  /// marks it complete. Kept separate from movies because users commonly want
  /// a different rule for episode credits.


  /// Re-arms the resume-ghost purge for a restore/transfer preference overlay.
  ///
  /// A restore applies the package key-by-key over the destination profile, so
  /// a key the package does NOT carry keeps its destination value. A backup or
  /// device transfer taken on a pre-purge build carries `playback_state_v1`
  /// (ghosts and all) but no purge marker — so a destination that already ran
  /// the purge would keep `generation = 1` and never inspect the playback state
  /// it just imported, stranding those ghosts forever. Resetting the marker
  /// alongside imported playback lets the one-shot purge run once more against
  /// the new data.
  ///
  /// A package that DOES carry a marker came from a build that already purged
  /// at the source, so its value is honoured untouched.

  /// One-time, per-profile purge of the resume "ghosts" older builds minted
  /// when an episode was unwatched.
  ///
  /// Until [_clearEpisodeCompletion] learned to drop the row, unwatching a
  /// fully-watched episode zeroed its `positionMs` and stamped `updatedAt` to
  /// now. The leftover row reads as "played, 0% in, not finished", which is the
  /// newest thing in the series — so it won `getLastPlayedEpisode*` and pinned
  /// Continue Watching (home card, detail pill, and Play alike) to an episode
  /// the user had just declared unwatched. Repeating mark→unmark to shake it
  /// loose only re-stamped it fresher.
  ///
  /// This runs ONCE rather than filtering on every read. A zero-position row is
  /// indistinguishable from an episode legitimately opened and closed before
  /// the first autosave tick, and permanently ignoring that shape would make a
  /// pack reopen the previous (already-watched) episode. Bounding the cleanup
  /// to one pass fixes the installs carrying a ghost — including ones that
  /// received it over a device transfer — while leaving normal playback
  /// bookkeeping exactly as it was.
  ///
  /// Rows marked in `finishedEpisodes` are kept: a mark-only watch stores the
  /// dummy 0ms/1ms shape and still means "watched".

  /// One-time, per-profile adoption of the local completion thresholds for
  /// playback recorded before threshold-based watched status existed.
  ///
  /// Movies at/above their threshold become locally finished and leave local
  /// Continue Watching. Series episodes at/above their threshold are folded
  /// into the existing `finishedEpisodes` structure used by episode ticks.
  /// Tracker data is deliberately untouched; this migration only rewrites the
  /// app's local playback state.

  // PikPak API Settings


  static Future<String?> getPikPakEmail({
    bool forRemoteTransfer = false,
  }) =>
      CloudSecretPrefs.read(
        _pikpakEmailKey,
        forRemoteTransfer: forRemoteTransfer,
      );

  static Future<void> setPikPakEmail(String email) =>
      CloudSecretPrefs.write(_pikpakEmailKey, email);

  static Future<String?> getPikPakPassword() =>
      CloudSecretPrefs.read(_pikpakPasswordKey);

  static Future<void> setPikPakPassword(String password) =>
      CloudSecretPrefs.write(_pikpakPasswordKey, password);






  // PikPak Device ID and Captcha Token








  // PikPak Show Videos Only


  // PikPak Ignore Small Videos (under 100MB)


  // PikPak Restricted Folder




  // PikPak Subfolder ID caching (for debrify-torrents and debrify-tv folders)





  // PikPak Hidden from Navigation



  // WebDAV Settings





















  // TVMaze Series Mapping Methods


  /// Save a TVMaze series mapping for a playlist item

  /// Get TVMaze series mapping for a playlist item

  /// Clear TVMaze series mapping for a playlist item

  /// Clear all TVMaze series mappings

  // Playlist Poster Override Methods

  /// Save a poster URL override for a playlist item
  /// This ensures the poster persists across app restarts

  /// Get poster URL override for a playlist item
  /// Returns null if no override exists

  /// Get all poster overrides as a map of item unique key → poster URL.
  /// Reads and parses the overrides blob once for batch lookups.

  /// Get the unique key for a playlist item (public accessor for batch lookups)

  /// Clear poster URL override for a playlist item

  /// Clear all playlist poster overrides

  // ============================================================================
  // Torrent Search History Methods
  // ============================================================================

  /// Get torrent search history
  /// Returns list of maps containing torrent JSON + service + timestamp

  /// Add torrent to search history with deduplication
  /// Deduplicates by infohash, keeps max 5 items (FIFO)

  /// Clear all search history

  /// Get whether search history tracking is enabled

  /// Set whether search history tracking is enabled

  /// Whether quick-play ranks candidates by the default filters (the
  /// FilterLadder). ON by default — the ladder only reorders, never drops.
  static Future<bool> getQuickPlayHonorsFilters() =>
      QuickPlayPolicyPrefs.getQuickPlayHonorsFilters();

  /// Legacy global preference retained for migration and profile-less callers.
  /// The Quick Play page owns the independent Movie and Series `useFilters`
  /// values; a global write must never silently rewrite either profile.
  static Future<void> setQuickPlayHonorsFilters(bool value) =>
      QuickPlayPolicyPrefs.setQuickPlayHonorsFilters(value);

  // Default Torrent Filter Settings










  // Debrify TV Filter Settings — forwarding façade; bodies live on DebrifyTvPrefs.
  static Future<List<String>> getDebrifyTvFilterQualities() =>
      DebrifyTvPrefs.getDebrifyTvFilterQualities();

  static Future<void> setDebrifyTvFilterQualities(
    List<String> qualities,
  ) => DebrifyTvPrefs.setDebrifyTvFilterQualities(qualities);

  static Future<List<String>> getDebrifyTvFilterSizes() =>
      DebrifyTvPrefs.getDebrifyTvFilterSizes();

  static Future<void> setDebrifyTvFilterSizes(List<String> sizes) =>
      DebrifyTvPrefs.setDebrifyTvFilterSizes(sizes);

  static Future<bool> getDebrifyTvExternalNoticeDismissed() =>
      DebrifyTvPrefs.getDebrifyTvExternalNoticeDismissed();

  static Future<void> setDebrifyTvExternalNoticeDismissed(bool value) =>
      DebrifyTvPrefs.setDebrifyTvExternalNoticeDismissed(value);


  // Default Torrent Provider methods
  // Returns: 'none' (ask every time), 'torbox', 'debrid', or 'pikpak'



  static Future<List<IndexerManagerConfig>> getIndexerManagerConfigs({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows.map(IndexerManagerConfig.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final rawList = await SecretVault.getStringList(
      prefs,
      _indexerManagerConfigsKey,
    );
    return rawList
        .map((raw) {
          try {
            return IndexerManagerConfig.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
          } catch (e) {
            debugPrint('Error loading indexer manager config: $e');
            return null;
          }
        })
        .whereType<IndexerManagerConfig>()
        .toList();
  }

  static Future<List<IndexerManagerConfig>> setIndexerManagerConfigs(
    List<IndexerManagerConfig> configs,
  ) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.replaceAndRead(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
        items: <ResourceCollectionItem>[
          for (final config in configs)
            ResourceCollectionItem(
              type: config.type == IndexerManagerType.prowlarr
                  ? ConnectionResourceType.prowlarr
                  : ConnectionResourceType.jackett,
              label: config.displayName,
              publicConfig: <String, dynamic>{
                'managerName': config.displayName,
              },
              secretConfig: config.toJson(),
              sourceResourceId: config.connectionResourceId,
            ),
        ],
        forSettings: true,
      );
      return rows.map(IndexerManagerConfig.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final rawList = configs
        .map((config) => jsonEncode(config.toJson()))
        .toList();
    await SecretVault.setStringList(prefs, _indexerManagerConfigsKey, rawList);
    return List<IndexerManagerConfig>.unmodifiable(configs);
  }

  static Future<String?> getSupportRemoteConfigCache() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_supportRemoteConfigCacheKey);
  }

  static Future<void> setSupportRemoteConfigCache(String json) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_supportRemoteConfigCacheKey, json);
  }

  static Future<List<String>> getDismissedDonationCampaignIds() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
  }

  static Future<void> dismissDonationCampaign(String campaignId) async {
    final prefs = await DevicePreferences.instance();
    final ids =
        prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
    if (ids.contains(campaignId)) return;
    ids.add(campaignId);
    await prefs.setStringList(_dismissedDonationCampaignIdsKey, ids);
  }

  // Quick Play VR Settings methods

  /// Get VR player mode: 'disabled', 'auto', or 'always'
  static Future<String> getQuickPlayVrMode() =>
      PlayerPrefs.getQuickPlayVrMode();

  static Future<void> setQuickPlayVrMode(String mode) =>
      PlayerPrefs.setQuickPlayVrMode(mode);

  /// Get default VR screen type (dome, sphere, flat, fisheye, mkx200, rf52)
  static Future<String> getQuickPlayVrDefaultScreenType() =>
      PlayerPrefs.getQuickPlayVrDefaultScreenType();

  static Future<void> setQuickPlayVrDefaultScreenType(String screenType) =>
      PlayerPrefs.setQuickPlayVrDefaultScreenType(screenType);

  /// Get default VR stereo mode (sbs, tb, off)
  static Future<String> getQuickPlayVrDefaultStereoMode() =>
      PlayerPrefs.getQuickPlayVrDefaultStereoMode();

  static Future<void> setQuickPlayVrDefaultStereoMode(String stereoMode) =>
      PlayerPrefs.setQuickPlayVrDefaultStereoMode(stereoMode);

  /// Get whether to auto-detect VR format from filename
  static Future<bool> getQuickPlayVrAutoDetectFormat() =>
      PlayerPrefs.getQuickPlayVrAutoDetectFormat();

  static Future<void> setQuickPlayVrAutoDetectFormat(bool autoDetect) =>
      PlayerPrefs.setQuickPlayVrAutoDetectFormat(autoDetect);

  /// Get whether to show VR format selection dialog before launching DeoVR
  static Future<bool> getQuickPlayVrShowDialog() =>
      PlayerPrefs.getQuickPlayVrShowDialog();

  static Future<void> setQuickPlayVrShowDialog(bool showDialog) =>
      PlayerPrefs.setQuickPlayVrShowDialog(showDialog);

  /// Clear all Quick Play VR settings
  static Future<void> clearQuickPlayVrSettings() =>
      PlayerPrefs.clearQuickPlayVrSettings();

  // Quick Play Cache Fallback Settings methods

  /// What the Play button does — NOT what it looks like. The button keeps its
  /// label, icon and position in every mode; only the behavior behind the press
  /// changes:
  ///
  ///  * `quick`  — the shipped contract: reuse a pinned source, else search and
  ///               auto-play the best match.
  ///  * `smart`  — reuse a pinned source; when none is usable, hand the user the
  ///               source list instead of auto-picking.
  ///  * `always` — skip pinned sources entirely and always hand over the list.
  ///
  /// Absent key means `quick`, so existing installs are untouched. Only the
  /// user's own Play press honors this ([TorrentPlaybackService.playFromSelection]
  /// applies it solely when a picker opener is supplied) — binge auto-advance and
  /// post-failure recovery keep auto-selecting, since re-prompting mid-chain is
  /// exactly what those paths exist to avoid.
  static Future<String> getPlayButtonMode() =>
      QuickPlayPolicyPrefs.getPlayButtonMode();

  static Future<void> setPlayButtonMode(String value) =>
      QuickPlayPolicyPrefs.setPlayButtonMode(value);

  /// Loads the per-content Quick Play profile. When no v2 profile exists,
  /// legacy filter/retry/series-pack preferences are folded into one without
  /// changing what the next play will do. Non-default legacy values are
  /// labelled Custom; an untouched install is Debrify default.
  static Future<QuickPlayRules> getQuickPlayRules({
    required bool isMovie,
  }) =>
      QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: isMovie);



  static Future<void> setQuickPlayRules(
    QuickPlayRules rules, {
    required bool isMovie,
  }) =>
      QuickPlayPolicyPrefs.setQuickPlayRules(rules, isMovie: isMovie);

  static Future<void> restoreQuickPlayDefaults() =>
      QuickPlayPolicyPrefs.restoreQuickPlayDefaults();

  /// Get whether to try multiple torrents if first is not cached
  /// Default: true (try next torrent on failure)
  static Future<bool> getQuickPlayTryMultipleTorrents() =>
      QuickPlayPolicyPrefs.getQuickPlayTryMultipleTorrents();

  static Future<void> setQuickPlayTryMultipleTorrents(bool tryMultiple) =>
      QuickPlayPolicyPrefs.setQuickPlayTryMultipleTorrents(tryMultiple);

  /// Whether a series play pins the source that played, so later episodes go
  /// straight through the bound path. Defaults ON.
  ///
  /// Independent of "Prefer season packs" — the two shared a key until this
  /// split, which meant turning packs off silently killed pinning. See
  /// [_seriesAutoPinOnPlayKey].
  static Future<bool> getSeriesAutoPinOnPlay() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_seriesAutoPinOnPlayKey) ?? true;
  }

  static Future<void> setSeriesAutoPinOnPlay(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_seriesAutoPinOnPlayKey, enabled);
  }

  /// Get max number of torrents to try before giving up
  /// Default: 5, Range: 2-10
  static Future<int> getQuickPlayMaxRetries() =>
      QuickPlayPolicyPrefs.getQuickPlayMaxRetries();

  static Future<void> setQuickPlayMaxRetries(int maxRetries) =>
      QuickPlayPolicyPrefs.setQuickPlayMaxRetries(maxRetries);

  static const String _quickPlaySearchTimeoutKey = 'quick_play_search_timeout';

  static Future<int> getQuickPlaySearchTimeout() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_quickPlaySearchTimeoutKey) ?? 5;
  }

  static Future<void> setQuickPlaySearchTimeout(int seconds) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_quickPlaySearchTimeoutKey, seconds);
  }

  static const String _stremioSourcesTimeoutKey = 'stremio_sources_timeout';

  static Future<int> getStremioSourcesTimeout() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioSourcesTimeoutKey) ?? 15;
  }

  static Future<void> setStremioSourcesTimeout(int seconds) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioSourcesTimeoutKey, seconds);
  }

  /// Clear all Quick Play Cache Fallback settings
  static Future<void> clearQuickPlayCacheFallbackSettings() =>
      QuickPlayPolicyPrefs.clearQuickPlayCacheFallbackSettings();

  // External Player Settings — forwarding façade; bodies live on PlayerPrefs.
  static const String skipSegmentProviderAuto = PlayerPrefs.skipSegmentProviderAuto;
  static const String skipSegmentProviderSkipDb =
      PlayerPrefs.skipSegmentProviderSkipDb;
  static const String skipSegmentProviderIntroDb =
      PlayerPrefs.skipSegmentProviderIntroDb;
  static const String skipSegmentProviderTheIntroDb =
      PlayerPrefs.skipSegmentProviderTheIntroDb;

  static bool get playerStartPortraitCached =>
      PlayerPrefs.playerStartPortraitCached;
  static set playerStartPortraitCached(bool value) =>
      PlayerPrefs.playerStartPortraitCached = value;

  static bool get uiSoundsCached => PlayerPrefs.uiSoundsCached;
  static set uiSoundsCached(bool value) => PlayerPrefs.uiSoundsCached = value;

  static bool get uiHapticsCached => PlayerPrefs.uiHapticsCached;
  static set uiHapticsCached(bool value) => PlayerPrefs.uiHapticsCached = value;

  static Future<String> getDefaultPlayerMode() =>
      PlayerPrefs.getDefaultPlayerMode();

  static Future<void> setDefaultPlayerMode(String mode) =>
      PlayerPrefs.setDefaultPlayerMode(mode);

  static Future<String> getPreferredExternalPlayer() =>
      PlayerPrefs.getPreferredExternalPlayer();

  static Future<void> setPreferredExternalPlayer(String playerKey) =>
      PlayerPrefs.setPreferredExternalPlayer(playerKey);

  static Future<String?> getCustomExternalPlayerPath() =>
      PlayerPrefs.getCustomExternalPlayerPath();

  static Future<void> setCustomExternalPlayerPath(String? path) =>
      PlayerPrefs.setCustomExternalPlayerPath(path);

  static Future<String?> getCustomExternalPlayerName() =>
      PlayerPrefs.getCustomExternalPlayerName();

  static Future<void> setCustomExternalPlayerName(String? name) =>
      PlayerPrefs.setCustomExternalPlayerName(name);

  static Future<String?> getCustomExternalPlayerCommand() =>
      PlayerPrefs.getCustomExternalPlayerCommand();

  static Future<void> setCustomExternalPlayerCommand(String? command) =>
      PlayerPrefs.setCustomExternalPlayerCommand(command);

  static Future<String> getPreferredIOSExternalPlayer() =>
      PlayerPrefs.getPreferredIOSExternalPlayer();

  static Future<void> setPreferredIOSExternalPlayer(String playerKey) =>
      PlayerPrefs.setPreferredIOSExternalPlayer(playerKey);

  static Future<String?> getIOSCustomSchemeTemplate() =>
      PlayerPrefs.getIOSCustomSchemeTemplate();

  static Future<void> setIOSCustomSchemeTemplate(String? template) =>
      PlayerPrefs.setIOSCustomSchemeTemplate(template);

  static Future<String> getPreferredLinuxExternalPlayer() =>
      PlayerPrefs.getPreferredLinuxExternalPlayer();

  static Future<void> setPreferredLinuxExternalPlayer(String playerKey) =>
      PlayerPrefs.setPreferredLinuxExternalPlayer(playerKey);

  static Future<String?> getLinuxCustomCommand() =>
      PlayerPrefs.getLinuxCustomCommand();

  static Future<void> setLinuxCustomCommand(String? command) =>
      PlayerPrefs.setLinuxCustomCommand(command);

  static Future<String> getPreferredWindowsExternalPlayer() =>
      PlayerPrefs.getPreferredWindowsExternalPlayer();

  static Future<void> setPreferredWindowsExternalPlayer(String playerKey) =>
      PlayerPrefs.setPreferredWindowsExternalPlayer(playerKey);

  static Future<String?> getWindowsCustomCommand() =>
      PlayerPrefs.getWindowsCustomCommand();

  static Future<void> setWindowsCustomCommand(String? command) =>
      PlayerPrefs.setWindowsCustomCommand(command);

  static Future<void> clearExternalPlayerSettings() =>
      PlayerPrefs.clearExternalPlayerSettings();

  static Future<int> getPlayerDefaultAspectIndex() =>
      PlayerPrefs.getPlayerDefaultAspectIndex();

  static Future<void> setPlayerDefaultAspectIndex(int index) =>
      PlayerPrefs.setPlayerDefaultAspectIndex(index);

  static Future<int> getPlayerDefaultAspectIndexTv() =>
      PlayerPrefs.getPlayerDefaultAspectIndexTv();

  static Future<void> setPlayerDefaultAspectIndexTv(int index) =>
      PlayerPrefs.setPlayerDefaultAspectIndexTv(index);

  static Future<int> getPlayerNightModeIndex() =>
      PlayerPrefs.getPlayerNightModeIndex();

  static Future<void> setPlayerNightModeIndex(int index) =>
      PlayerPrefs.setPlayerNightModeIndex(index);

  static Future<bool> getPlayerSystemAudioEffects() =>
      PlayerPrefs.getPlayerSystemAudioEffects();

  static Future<void> setPlayerSystemAudioEffects(bool enabled) =>
      PlayerPrefs.setPlayerSystemAudioEffects(enabled);

  static Future<bool> getAudioPassthroughEnabled() =>
      PlayerPrefs.getAudioPassthroughEnabled();

  static Future<void> setAudioPassthroughEnabled(bool enabled) =>
      PlayerPrefs.setAudioPassthroughEnabled(enabled);

  static Future<bool> getAppleMultichannelAudio() =>
      PlayerPrefs.getAppleMultichannelAudio();

  static Future<void> setAppleMultichannelAudio(bool enabled) =>
      PlayerPrefs.setAppleMultichannelAudio(enabled);

  static Future<bool> getTvosForceStereoAudio() =>
      PlayerPrefs.getTvosForceStereoAudio();

  static Future<void> setTvosForceStereoAudio(bool enabled) =>
      PlayerPrefs.setTvosForceStereoAudio(enabled);

  static Future<bool> getTvosLegacyAudioOutput() =>
      PlayerPrefs.getTvosLegacyAudioOutput();

  static Future<void> setTvosLegacyAudioOutput(bool enabled) =>
      PlayerPrefs.setTvosLegacyAudioOutput(enabled);

  static Future<bool> getTvosForceSoftwareDecode() =>
      PlayerPrefs.getTvosForceSoftwareDecode();

  static Future<void> setTvosForceSoftwareDecode(bool enabled) =>
      PlayerPrefs.setTvosForceSoftwareDecode(enabled);

  static Future<AndroidVideoRendererMode> getAndroidVideoRendererMode() =>
      PlayerPrefs.getAndroidVideoRendererMode();

  static Future<void> setAndroidVideoRendererMode(
    AndroidVideoRendererMode mode,
  ) => PlayerPrefs.setAndroidVideoRendererMode(mode);

  static Future<bool> getSkipSegmentsEnabled() =>
      PlayerPrefs.getSkipSegmentsEnabled();

  static Future<void> setSkipSegmentsEnabled(bool enabled) =>
      PlayerPrefs.setSkipSegmentsEnabled(enabled);

  static Future<String> getSkipSegmentProvider() =>
      PlayerPrefs.getSkipSegmentProvider();

  static Future<void> setSkipSegmentProvider(String provider) =>
      PlayerPrefs.setSkipSegmentProvider(provider);

  static Future<bool> getPlayerStartPortrait() =>
      PlayerPrefs.getPlayerStartPortrait();

  static Future<void> setPlayerStartPortrait(bool enabled) =>
      PlayerPrefs.setPlayerStartPortrait(enabled);

  static Future<bool> getUiSounds() => PlayerPrefs.getUiSounds();

  static Future<void> setUiSounds(bool enabled) =>
      PlayerPrefs.setUiSounds(enabled);

  static Future<bool> getUiHaptics() => PlayerPrefs.getUiHaptics();

  static Future<void> setUiHaptics(bool enabled) =>
      PlayerPrefs.setUiHaptics(enabled);

  static Future<bool> getSubtitleAutoSyncEnabled() =>
      PlayerPrefs.getSubtitleAutoSyncEnabled();

  static Future<void> setSubtitleAutoSyncEnabled(bool enabled) =>
      PlayerPrefs.setSubtitleAutoSyncEnabled(enabled);

  static Future<String?> getDefaultSubtitleLanguage() =>
      PlayerPrefs.getDefaultSubtitleLanguage();

  static Future<void> setDefaultSubtitleLanguage(String? languageCode) =>
      PlayerPrefs.setDefaultSubtitleLanguage(languageCode);

  static Future<String?> getDefaultAudioLanguage() =>
      PlayerPrefs.getDefaultAudioLanguage();

  static Future<void> setDefaultAudioLanguage(String? languageCode) =>
      PlayerPrefs.setDefaultAudioLanguage(languageCode);

  // IPTV Settings — forwarding façade; bodies live on IptvPrefs.
  static const List<String> iptvDecoderModes = IptvPrefs.iptvDecoderModes;
  static const double iptvWatchFinishedFraction =
      IptvPrefs.iptvWatchFinishedFraction;
  static const String iptvFavoritesListId = IptvPrefs.iptvFavoritesListId;
  static const String startupIptvModeLast = IptvPrefs.startupIptvModeLast;
  static const String startupIptvModePinned = IptvPrefs.startupIptvModePinned;
  static const String startupIptvFirstAvailable =
      IptvPrefs.startupIptvFirstAvailable;

  static Map<String, dynamic>? get startupIptvChannelCached =>
      IptvPrefs.startupIptvChannelCached;
  static set startupIptvChannelCached(Map<String, dynamic>? value) =>
      IptvPrefs.startupIptvChannelCached = value;


  static Future<void> setIptvSeriesAudioLanguage(
    String seriesKey,
    String languageCode,
  ) => IptvPrefs.setIptvSeriesAudioLanguage(seriesKey, languageCode);








  static Future<void> setIptvLastLiveChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) => IptvPrefs.setIptvLastLiveChannel(
    url,
    name: name,
    playlistId: playlistId,
    channelNumber: channelNumber,
    group: group,
    logoUrl: logoUrl,
    httpHeaders: httpHeaders,
  );











  // ============================================================================
  // Remote Control Settings
  // ============================================================================

  /// Get whether remote control feature is enabled
  static Future<bool> getRemoteControlEnabled() =>
      RemoteDevicePrefs.getRemoteControlEnabled();

  static Future<bool> getUpdateAutoCheckEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_updateAutoCheckEnabledKey) ?? true;
  }

  static Future<void> setUpdateAutoCheckEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_updateAutoCheckEnabledKey, enabled);
  }

  static Future<String?> getIgnoredUpdateVersion() async {
    final prefs = await DevicePreferences.instance();
    final value = prefs.getString(_updateIgnoredVersionKey);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> setIgnoredUpdateVersion(String? version) async {
    final prefs = await DevicePreferences.instance();
    if (version == null || version.trim().isEmpty) {
      await prefs.remove(_updateIgnoredVersionKey);
    } else {
      await prefs.setString(_updateIgnoredVersionKey, version);
    }
  }

  /// Set whether remote control feature is enabled
  static Future<void> setRemoteControlEnabled(bool enabled) =>
      RemoteDevicePrefs.setRemoteControlEnabled(enabled);

  /// Get whether remote intro dialog has been shown
  static Future<bool> getRemoteIntroShown() =>
      RemoteDevicePrefs.getRemoteIntroShown();

  /// Set whether remote intro dialog has been shown
  static Future<void> setRemoteIntroShown(bool shown) =>
      RemoteDevicePrefs.setRemoteIntroShown(shown);

  /// Get TV device name for remote control (TV only)
  static Future<String?> getRemoteTvDeviceName() =>
      RemoteDevicePrefs.getRemoteTvDeviceName();

  /// Set TV device name for remote control (TV only)
  static Future<void> setRemoteTvDeviceName(String name) =>
      RemoteDevicePrefs.setRemoteTvDeviceName(name);

  /// Get last connected device info (Mobile only)
  static Future<Map<String, dynamic>?> getRemoteLastDevice() =>
      RemoteDevicePrefs.getRemoteLastDevice();

  /// Save last connected device info (Mobile only)
  static Future<void> setRemoteLastDevice(Map<String, dynamic> device) =>
      RemoteDevicePrefs.setRemoteLastDevice(device);

  /// Clear last connected device info
  static Future<void> clearRemoteLastDevice() =>
      RemoteDevicePrefs.clearRemoteLastDevice();

  // Stremio TV Settings — forwarding façade; bodies live on StremioTvPrefs.
  static Future<int> getStremioTvRotationMinutes() =>
      StremioTvPrefs.getStremioTvRotationMinutes();

  static Future<void> setStremioTvRotationMinutes(int value) =>
      StremioTvPrefs.setStremioTvRotationMinutes(value);

  static Future<int> getStremioTvSeriesRotationMinutes() =>
      StremioTvPrefs.getStremioTvSeriesRotationMinutes();

  static Future<void> setStremioTvSeriesRotationMinutes(int value) =>
      StremioTvPrefs.setStremioTvSeriesRotationMinutes(value);

  static Future<bool> getStremioTvRandomEpisodes() =>
      StremioTvPrefs.getStremioTvRandomEpisodes();

  static Future<void> setStremioTvRandomEpisodes(bool value) =>
      StremioTvPrefs.setStremioTvRandomEpisodes(value);

  static Future<bool> getStremioTvAutoRefresh() =>
      StremioTvPrefs.getStremioTvAutoRefresh();

  static Future<void> setStremioTvAutoRefresh(bool value) =>
      StremioTvPrefs.setStremioTvAutoRefresh(value);

  static Future<bool> getStremioTvHideNowPlaying() =>
      StremioTvPrefs.getStremioTvHideNowPlaying();

  static Future<void> setStremioTvHideNowPlaying(bool value) =>
      StremioTvPrefs.setStremioTvHideNowPlaying(value);

  static Future<bool> getStremioTvTorrentsFirst() =>
      StremioTvPrefs.getStremioTvTorrentsFirst();

  static Future<void> setStremioTvTorrentsFirst(bool value) =>
      StremioTvPrefs.setStremioTvTorrentsFirst(value);

  static Future<String> getStremioTvPreferredQuality() =>
      StremioTvPrefs.getStremioTvPreferredQuality();

  static Future<void> setStremioTvPreferredQuality(String value) =>
      StremioTvPrefs.setStremioTvPreferredQuality(value);

  static Future<String> getStremioTvDebridProvider() =>
      StremioTvPrefs.getStremioTvDebridProvider();

  static Future<void> setStremioTvDebridProvider(String value) =>
      StremioTvPrefs.setStremioTvDebridProvider(value);

  static Future<int> getStremioTvMaxStartPercent() =>
      StremioTvPrefs.getStremioTvMaxStartPercent();

  static Future<void> setStremioTvMaxStartPercent(int value) =>
      StremioTvPrefs.setStremioTvMaxStartPercent(value);

  static Future<bool> isStremioTvChannelFavorited(String channelId) =>
      StremioTvPrefs.isStremioTvChannelFavorited(channelId);

  static Future<void> setStremioTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) => StremioTvPrefs.setStremioTvChannelFavorited(channelId, isFavorited);

  static Future<Set<String>> getStremioTvFavoriteChannelIds() =>
      StremioTvPrefs.getStremioTvFavoriteChannelIds();

  static Future<List<Map<String, dynamic>>> getStremioTvLocalCatalogs() =>
      StremioTvPrefs.getStremioTvLocalCatalogs();

  static Future<void> setStremioTvLocalCatalogs(
    List<Map<String, dynamic>> catalogs,
  ) => StremioTvPrefs.setStremioTvLocalCatalogs(catalogs);

  static Future<bool> addStremioTvLocalCatalog(
    Map<String, dynamic> catalog,
  ) => StremioTvPrefs.addStremioTvLocalCatalog(catalog);

  static Future<void> removeStremioTvLocalCatalog(String catalogId) =>
      StremioTvPrefs.removeStremioTvLocalCatalog(catalogId);

  static Future<bool> updateStremioTvLocalCatalog(
    Map<String, dynamic> catalog,
  ) => StremioTvPrefs.updateStremioTvLocalCatalog(catalog);

  static Future<List<String>> getStremioTvCatalogRepoUrls() =>
      StremioTvPrefs.getStremioTvCatalogRepoUrls();

  static Future<void> setStremioTvCatalogRepoUrls(List<String> urls) =>
      StremioTvPrefs.setStremioTvCatalogRepoUrls(urls);

  static Future<bool> addStremioTvCatalogRepoUrl(String url) =>
      StremioTvPrefs.addStremioTvCatalogRepoUrl(url);

  static Future<void> removeStremioTvCatalogRepoUrl(String url) =>
      StremioTvPrefs.removeStremioTvCatalogRepoUrl(url);

  static Future<Set<String>> getStremioTvDisabledFilters() =>
      StremioTvPrefs.getStremioTvDisabledFilters();

  static Future<void> setStremioTvDisabledFilters(Set<String> disabled) =>
      StremioTvPrefs.setStremioTvDisabledFilters(disabled);


  static const String _catalogSearchDisabledAddonsKey =
      'catalog_search_disabled_addons_v1';

  /// Get the set of addon IDs the user has DISABLED for catalog search on the
  /// Search tab (empty = every searchable addon is queried).
  static Future<Set<String>> getCatalogSearchDisabledAddons() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_catalogSearchDisabledAddonsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading catalog search disabled addons: $e');
      return {};
    }
  }

  /// Save the set of addon IDs disabled for catalog search.
  static Future<void> setCatalogSearchDisabledAddons(
    Set<String> disabled,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_catalogSearchDisabledAddonsKey);
    } else {
      await prefs.setString(
        _catalogSearchDisabledAddonsKey,
        jsonEncode(disabled.toList()),
      );
    }
  }

  static Future<Set<String>> getHomeDisabledSections() =>
      HomePrefs.getHomeDisabledSections();

  static Future<void> setHomeDisabledSections(Set<String> disabled) =>
      HomePrefs.setHomeDisabledSections(disabled);

  static Future<List<HomeExtraRow>> getHomeExtraRows() =>
      HomePrefs.getHomeExtraRows();

  static Future<void> setHomeExtraRows(List<HomeExtraRow> rows) =>
      HomePrefs.setHomeExtraRows(rows);

  static Future<List<String>> getHomeRowOrder() => HomePrefs.getHomeRowOrder();

  static Future<void> setHomeRowOrder(List<String> order) =>
      HomePrefs.setHomeRowOrder(order);

  static Future<HomeHeroSource> getHomeHeroSource() =>
      HomePrefs.getHomeHeroSource();

  static Future<void> setHomeHeroSource(HomeHeroSource source) =>
      HomePrefs.setHomeHeroSource(source);

  /// Clears synchronous mirrors before a profile activation is published.
  /// The target bootstrap immediately warms them from its captured scope.
  static void resetProfileCaches() {
    tvKeyboardEnabledCached = !PlatformUtil.isTvOS;
    tvHomeStyleCached = 'canvas';
    debrifyTvStyleCached = 'grid';
    detailPageStyleCached = kDetailPageStyleDefault;
    detailThemeCached = 'signal';
    appThemeCached = 'legacy';
    themeOverridesCached = '';
    parentsGuideStyleCached = 'compass';
    iptvStyleCached = 'command';
    discoverLayoutCached = 'stage';
    launchAnimationCached = 'trace';
    launchIdentPaletteCached = 'ident';
    tvSidebarStyleCached = 'ghost';
    desktopSidebarStyleCached = 'rail';
    sidebarConfigurationCached = SidebarConfiguration.defaults();
    AppStylePrefs.resetCaches();
    playerStartPortraitCached = false;
    uiSoundsCached = true;
    uiHapticsCached = true;
    startupIptvChannelCached = null;
  }
}

class ApiKeyValidator {
  static bool isValidFormat(String apiKey) {
    // Real Debrid API keys are typically 40 characters
    return apiKey.length == 40 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(apiKey);
  }

  static Future<bool> validateApiKey(String apiKey) async {
    if (!isValidFormat(apiKey)) return false;

    try {
      await DebridService.getUserInfo(apiKey);
      return true; // If we get here, the API key is valid
    } catch (e) {
      return false;
    }
  }
}
