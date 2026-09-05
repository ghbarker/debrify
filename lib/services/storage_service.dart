import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:convert';
import 'debrid_service.dart';
import 'hide_watched_prefs.dart';
import 'iptv_channel_order.dart';
import 'iptv_media_store.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_credential_facade.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/profile_authorization.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/tvos_recovery_limits.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import 'secret_vault.dart';
import '../models/iptv_playlist.dart';
import '../models/indexer_manager_config.dart';
import '../models/quick_play_rules.dart';
import '../models/sidebar_configuration.dart';
import '../models/stremio_addon.dart';
import '../models/webdav_item.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/tv_hero_artwork_quality.dart';
import '../models/tracking_source.dart';
import '../utils/json_isolate.dart';
import '../utils/platform_util.dart';
import 'tracking_scrobble_preferences.dart';
import 'storage/cloud_secret_prefs.dart';
import 'storage/debrify_tv_prefs.dart';
import 'storage/home_prefs.dart';
import 'storage/social_prefs.dart';
import 'storage/iptv_prefs.dart';
import 'storage/app_style_prefs.dart';
import 'storage/player_prefs.dart';
import 'storage/provider_credential_prefs.dart';
import 'storage/stremio_tv_prefs.dart';

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
enum AmbientTrailerSurface { homeHero, detail }

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
  static const String _explicitlyWatchedSeriesKey =
      'explicitly_watched_series_v1';
  static const String trackingScrobbleTargetsKey =
      TrackingScrobblePreferences.key;
  static const String watchProgressSourceKey = 'watch_progress_source';

  /// Invalidates policy consumers that keep an in-memory snapshot.
  static final ValueNotifier<int> trackingSourceRevision = ValueNotifier(0);

  /// Tracker/account watched-title invalidation. Kept separate from local
  /// playback so finishing an episode never reloads entire remote histories.
  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier(0);

  /// Local movie, episode, and derived-series completion invalidation.
  static final ValueNotifier<int> localCompletionRevision = ValueNotifier(0);

  /// The tracker snapshots are each stored as one JSON object containing every
  /// show. Serializing their read/modify/write cycle prevents two concurrent
  /// show refreshes from both reading the same old object and dropping whichever
  /// write finishes first.
  static final Lock _episodeTrackerSnapshotWriteLock = Lock();

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
      // Dormant prefs are written too (desktop pill on a phone, TV home
      // style off-TV): harmless where they don't apply, correct if the
      // device class — or a window size — ever changes.
      //
      // The theme and its `detail_theme` mirror move as a PAIR, in the
      // controller's write-through order (mirror first — old builds read
      // only the mirror, and Showcase resolves its palette from it). The
      // pairing also means an explicit legacy pick (app_theme stored, no
      // mirror by design) keeps its details page untouched.
      if (!prefs.containsKey(AppStylePrefs.appThemeKey)) {
        if (!prefs.containsKey(AppStylePrefs.detailThemeKey)) {
          await prefs.setString(AppStylePrefs.detailThemeKey, 'spotlight');
        }
        await prefs.setString(AppStylePrefs.appThemeKey, 'spotlight');
      }
      const bundle = <String, String>{
        AppStylePrefs.detailPageStyleKey: 'showcase',
        HomePrefs.tvHomeStyleKey: 'spotlight',
        AppStylePrefs.tvSidebarStyleKey: 'pill',
        AppStylePrefs.desktopSidebarStyleKey: 'pill',
      };
      for (final entry in bundle.entries) {
        if (!prefs.containsKey(entry.key)) {
          await prefs.setString(entry.key, entry.value);
        }
      }
    }
    if (gen < 2) {
      // Both ambient trailer surfaces, for installs whose form factor used to
      // default one of them off. An explicit off — the toggles write
      // unconditionally, so a stored `false` is always a real choice — is left
      // alone: this turns trailers on for people who never had an opinion, not
      // for people who said no.
      const trailers = <String, bool>{
        'home_hero_trailer_enabled': true,
        'detail_trailer_autoplay_enabled': true,
      };
      for (final entry in trailers.entries) {
        if (!prefs.containsKey(entry.key)) {
          await prefs.setBool(entry.key, entry.value);
        }
      }
    }
    if (gen < 3) {
      // Debrify TV joins the flagship bundle. Raw prefs only — this runs
      // before any mirror is warmed, so `app_theme` is read directly rather
      // than through `appThemeCached`. The gen<1 block above has already
      // written `app_theme` for anyone who never chose, including a fresh
      // install, so this read is never against an absent key on a migrated
      // install.
      //
      // NOT unconditional the way generation 1 was: this key has never
      // existed, so `!containsKey` is true for every install on earth, and a
      // blanket 'spotlight' would restyle every Classic user AND flip their
      // Presets picker to Custom (Classic pins this key). The proxy is the
      // THEME, not Look activity — a Custom mix that kept the Spotlight
      // theme adopts the layout the theme implies; everyone else keeps grid.
      if (!prefs.containsKey(AppStylePrefs.debrifyTvStyleKey)) {
        final theme = prefs.getString(AppStylePrefs.appThemeKey);
        await prefs.setString(
          AppStylePrefs.debrifyTvStyleKey,
          theme == 'spotlight' ? 'spotlight' : 'grid',
        );
      }
    }
    await prefs.setInt(_defaultsGenerationKey, _currentDefaultsGeneration);
  }

  static const String _torboxApiKey = CloudSecretPrefs.torboxApiKey;
  static const String _premiumizeApiKey = CloudSecretPrefs.premiumizeApiKey;
  static const String _allDebridApiKey = CloudSecretPrefs.allDebridApiKey;
  static const String _batteryOptStatusKey =
      'battery_opt_status_v1'; // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _playbackStateKey = 'playback_state_v1';
  static const String _continueWatchingKey = 'continue_watching_v1';
  static const String localSeriesCompletionStateKey =
      'local_series_completion_v1';
  static const String localSeriesCalendarCheckedAtKey =
      'local_series_completion_calendar_checked_at_v1';
  static const String localSeriesCalendarAttemptedAtKey =
      'local_series_completion_calendar_attempted_at_v1';
  static const String _finishedMoviesKey = 'finished_movies_v1';

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

  static const String _movieCompletionThresholdKey =
      'movie_completion_threshold';
  static const String _episodeCompletionThresholdKey =
      'episode_completion_threshold';
  static const String _playbackCompletionMigrationGenerationKey =
      'playback_completion_migration_generation';
  static const int _currentPlaybackCompletionMigrationGeneration = 1;
  static const String _resumeGhostPurgeGenerationKey =
      'resume_ghost_purge_generation';
  static const int _currentResumeGhostPurgeGeneration = 1;

  /// Completion thresholds selectable in Settings → Playback. A lower bound
  /// avoids treating a brief accidental play as watched; 95% still lets users
  /// finish a title without waiting through every trailing credit frame.
  static const List<int> localCompletionThresholdOptions = <int>[
    50,
    60,
    70,
    75,
    80,
    85,
    90,
    95,
  ];
  static const int defaultLocalCompletionThreshold = 80;


  // PikPak secret key aliases — CloudSecretPrefs owns the strings.
  static const String _pikpakEmailKey = CloudSecretPrefs.pikpakEmail;
  static const String _pikpakPasswordKey = CloudSecretPrefs.pikpakPassword;

  // TVMaze series mapping keys
  static const String _tvMazeSeriesMappingKey = 'tvmaze_series_mappings';

  // Playlist poster override storage key
  static const String _playlistPosterOverridesKey =
      'playlist_poster_overrides_v1';


  static const String _playlistKey = 'user_playlist_v1';
  static const String _playlistViewModesKey = 'playlist_view_modes_v1';
  static const String _playlistFavoritesKey = 'playlist_favorites_v1';
  static const String _myWatchlistKey =
      TvOsRecoveryLimits.myWatchlistPreferenceKey;
  static const String _onboardingCompleteKey = 'initial_setup_complete_v1';

  // Torrent Search History
  static const String _torrentSearchHistoryKey = 'torrent_search_history_v1';
  static const String _torrentSearchHistoryEnabledKey =
      'torrent_search_history_enabled';

  // Default Torrent Filter Settings
  static const String _defaultFilterQualitiesKey =
      'default_filter_qualities_v1';
  static const String _defaultFilterRipSourcesKey =
      'default_filter_rip_sources_v1';
  static const String _defaultFilterLanguagesKey =
      'default_filter_languages_v1';
  static const String _defaultFilterSizesKey = 'default_filter_sizes_v1';
  static const String _defaultFilterDynamicRangesKey =
      'default_filter_dynamic_ranges_v1';
  static const String _quickPlayHonorsFiltersKey =
      'quick_play_honors_filters_v1';

  // Default Torrent Provider Settings — key lives on ProviderCredentialPrefs.
  // Values: 'none' (ask every time), 'torbox', 'debrid', 'pikpak'
  static const String _indexerManagerConfigsKey = 'indexer_manager_configs_v1';

  // Quick Play VR Settings
  // VR Player Mode: 'disabled' (always regular player), 'auto' (detect VR content), 'always' (always use DeoVR)
  static const String _quickPlayVrModeKey = 'quick_play_vr_mode';
  static const String _quickPlayVrDefaultScreenTypeKey =
      'quick_play_vr_default_screen_type';
  static const String _quickPlayVrDefaultStereoModeKey =
      'quick_play_vr_default_stereo_mode';
  static const String _quickPlayVrAutoDetectFormatKey =
      'quick_play_vr_auto_detect_format';
  static const String _quickPlayVrShowDialogKey = 'quick_play_vr_show_dialog';

  // Quick Play Cache Fallback Settings
  // When enabled, if first torrent is not cached, try next torrents until one works
  static const String _quickPlayTryMultipleTorrentsKey =
      'quick_play_try_multiple_torrents';
  static const String _quickPlayMaxRetriesKey = 'quick_play_max_retries';
  static const String _quickPlayMovieRulesKey = 'quick_play_movie_rules_v2';
  static const String _quickPlaySeriesRulesKey = 'quick_play_series_rules_v2';
  static const String _playButtonModeKey = 'play_button_mode';

  // Series auto-pin: on a series play with no pinned source, search packs
  // first (complete series → season pack), and pin whatever source plays so
  // subsequent episode plays go straight through the bound path.
  /// LEGACY MIRROR ONLY. Written by [setQuickPlayRules] to carry
  /// `preferSeriesPacks` for downgrade builds, and read once by
  /// [_quickPlayRulesFromPrefs] to migrate pre-v2 profiles. Nothing on the live
  /// playback path may read it — see [_seriesAutoPinOnPlayKey].
  static const String _autoBindSeriesPacksKey =
      'auto_bind_series_packs_on_play';

  /// Whether a series play pins the source that played. Split out of
  /// [_autoBindSeriesPacksKey] because that key doubles as the legacy mirror of
  /// `preferSeriesPacks`: turning OFF "Prefer season packs" in Quick Play also
  /// silently disabled all series auto-pinning, so Smart mode never found a pin
  /// and Quick Play lost its fast path. Deliberately does NOT inherit the old
  /// key's value — a `false` there was the packs toggle bleeding through, never
  /// an auto-pin choice (no UI ever wrote it directly).
  static const String _seriesAutoPinOnPlayKey = 'series_auto_pin_on_play';

  // Trakt settings
  static const String _traktAccessTokenKey = 'trakt_access_token';
  static const String _traktRefreshTokenKey = 'trakt_refresh_token';
  static const String _traktUsernameKey = 'trakt_username';
  static const String _traktTokenExpiryKey = 'trakt_token_expiry';

  // Simkl settings. No refresh-token/expiry keys — PIN-issued Simkl tokens
  // don't expire (see SimklService).
  static const String _simklAccessTokenKey = 'simkl_access_token';
  static const String _simklUsernameKey = 'simkl_username';

  // MDBList settings. Auth is a single API key (from mdblist.com/preferences),
  // so there's no token/expiry — just the key and a cached display username.
  static const String _mdblistApiKeyKey = 'mdblist_api_key';
  static const String _mdblistUsernameKey = 'mdblist_username';

  // Remote Control Settings
  static const String _remoteControlEnabledKey = 'remote_control_enabled';
  static const String _remoteIntroShownKey = 'remote_intro_shown';
  static const String _remoteTvDeviceNameKey = 'remote_tv_device_name';
  static const String _remoteLastDeviceKey = 'remote_last_device';

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
  static Future<String> getRdEndpoint() =>
      ProviderCredentialPrefs.getRdEndpoint();

  static Future<void> saveRdEndpoint(String endpoint) =>
      ProviderCredentialPrefs.saveRdEndpoint(endpoint);

  static Future<void> deleteRdEndpoint() =>
      ProviderCredentialPrefs.deleteRdEndpoint();

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

  /// Pref key for the ambient-trailer sound pair, resolved per platform.
  /// Resolves to exactly four keys, spelled out here because the returns
  /// below are interpolated and a grep for a literal name would otherwise
  /// find nothing: `home_hero_trailer_audio_enabled`,
  /// `home_hero_trailer_volume`, `detail_trailer_audio_enabled`,
  /// `detail_trailer_volume`. Any future backup allowlist, reset sweep or
  /// migration has to name all four — enumerating one surface silently drops
  /// the other platform's settings.
  /// Each ambient surface owns its own key even though only one of them can
  /// be live on a device: the TV hero/Discover stage keeps the legacy
  /// `home_hero_` pair (renaming would reset every TV install), the non-TV
  /// detail backdrop gets its own. That separation matters because the old
  /// Settings page offered the hero sound rows on EVERY platform — a phone
  /// user could store "sound off" for a hero that never rendered there, and
  /// with one shared key that dead value would now silently mute their detail
  /// backdrop. Per-surface keys make such writes unreadable instead, so
  /// non-TV starts at the defaults its backdrop has always used.
  ///
  /// Now selected by SURFACE rather than by platform. Picking by platform was
  /// sound while a television could only ever have the Home hero; with the
  /// Showcase detail page also playing trailers, a platform pick would have the
  /// detail backdrop silently reading the Home hero's sound and volume.
  static String _ambientTrailerKeyFor(
    AmbientTrailerSurface surface,
    String suffix,
  ) => switch (surface) {
    AmbientTrailerSurface.homeHero => 'home_hero_trailer_$suffix',
    AmbientTrailerSurface.detail => 'detail_trailer_$suffix',
  };

  /// Whether this platform's ambient trailer plays sound (false = video only).
  /// See [_ambientTrailerKey] for which surface that is. Note the IPTV live
  /// preview is a channel feed, not a trailer, and stays at full volume.
  static Future<bool> getAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      return HomePrefs.getHomeHeroTrailerAudioEnabled();
    }
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_ambientTrailerKeyFor(surface, 'audio_enabled')) ??
        true;
  }

  static Future<void> setAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
    bool enabled,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      await HomePrefs.setHomeHeroTrailerAudioEnabled(enabled);
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _ambientTrailerKeyFor(surface, 'audio_enabled'),
      enabled,
    );
  }

  /// Ambient trailer volume, percent 10–100. Default 70 — audible but under
  /// the UI, and the level the detail backdrop has always run at. Same
  /// one-surface-per-platform scope as [getAmbientTrailerAudioEnabled].
  static Future<int> getAmbientTrailerVolume(
    AmbientTrailerSurface surface,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      return HomePrefs.getHomeHeroTrailerVolume();
    }
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_ambientTrailerKeyFor(surface, 'volume')) ?? 70;
    return v.clamp(10, 100);
  }

  static Future<void> setAmbientTrailerVolume(
    AmbientTrailerSurface surface,
    int percent,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      await HomePrefs.setHomeHeroTrailerVolume(percent);
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _ambientTrailerKeyFor(surface, 'volume'),
      percent.clamp(10, 100),
    );
  }

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

  static Future<bool> getTorboxCacheCheckEnabled() =>
      ProviderCredentialPrefs.getTorboxCacheCheckEnabled();

  static Future<void> setTorboxCacheCheckEnabled(bool enabled) =>
      ProviderCredentialPrefs.setTorboxCacheCheckEnabled(enabled);

  static Future<bool> getRealDebridIntegrationEnabled() =>
      ProviderCredentialPrefs.getRealDebridIntegrationEnabled();

  static Future<void> setRealDebridIntegrationEnabled(bool enabled) =>
      ProviderCredentialPrefs.setRealDebridIntegrationEnabled(enabled);


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

  static Future<bool> getRealDebridHiddenFromNav() =>
      ProviderCredentialPrefs.getRealDebridHiddenFromNav();

  static Future<void> setRealDebridHiddenFromNav(bool hidden) =>
      ProviderCredentialPrefs.setRealDebridHiddenFromNav(hidden);

  static Future<void> clearRealDebridHiddenFromNav() =>
      ProviderCredentialPrefs.clearRealDebridHiddenFromNav();

  static Future<bool> getRdSkipBlockedTorrents() =>
      ProviderCredentialPrefs.getRdSkipBlockedTorrents();

  static Future<void> setRdSkipBlockedTorrents(bool enabled) =>
      ProviderCredentialPrefs.setRdSkipBlockedTorrents(enabled);

  static Future<bool> getTorboxIntegrationEnabled() =>
      ProviderCredentialPrefs.getTorboxIntegrationEnabled();

  static Future<void> setTorboxIntegrationEnabled(bool enabled) =>
      ProviderCredentialPrefs.setTorboxIntegrationEnabled(enabled);

  static Future<bool> getTorboxHiddenFromNav() =>
      ProviderCredentialPrefs.getTorboxHiddenFromNav();

  static Future<void> setTorboxHiddenFromNav(bool hidden) =>
      ProviderCredentialPrefs.setTorboxHiddenFromNav(hidden);

  static Future<void> clearTorboxHiddenFromNav() =>
      ProviderCredentialPrefs.clearTorboxHiddenFromNav();

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

  static Future<bool> getPremiumizeIntegrationEnabled() =>
      ProviderCredentialPrefs.getPremiumizeIntegrationEnabled();

  static Future<void> setPremiumizeIntegrationEnabled(bool enabled) =>
      ProviderCredentialPrefs.setPremiumizeIntegrationEnabled(enabled);

  static Future<bool> getPremiumizeHiddenFromNav() =>
      ProviderCredentialPrefs.getPremiumizeHiddenFromNav();

  static Future<void> setPremiumizeHiddenFromNav(bool hidden) =>
      ProviderCredentialPrefs.setPremiumizeHiddenFromNav(hidden);

  static Future<void> clearPremiumizeHiddenFromNav() =>
      ProviderCredentialPrefs.clearPremiumizeHiddenFromNav();

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

  // MDBList API key + cached username helpers
  static Future<String?> getMdblistApiKey({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _mdblistApiKeyKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _mdblistApiKeyKey);
  }

  static Future<bool> hasMdblistCredential() =>
      _credentialConfigured(_mdblistApiKeyKey, () => getMdblistApiKey());

  static Future<bool> _credentialConfigured(
    String key,
    Future<String?> Function() legacyRead,
  ) async {
    final presence = await ProfileCredentialFacade.isConfigured(key);
    if (presence.handled) return presence.configured;
    final value = await legacyRead();
    return value != null && value.isNotEmpty;
  }

  static Future<void> saveMdblistApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _mdblistApiKeyKey, apiKey);
  }

  static Future<String?> getMdblistUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_mdblistUsernameKey);
  }

  static Future<void> setMdblistUsername(String? username) async {
    final prefs = await ProfilePreferences.instance();
    if (username == null || username.isEmpty) {
      await prefs.remove(_mdblistUsernameKey);
    } else {
      await prefs.setString(_mdblistUsernameKey, username);
    }
  }

  /// Clears all stored MDBList auth (key + cached username).
  static Future<void> clearMdblistAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_mdblistApiKeyKey)) {
      await prefs.remove(_mdblistApiKeyKey);
    }
    await prefs.remove(_mdblistUsernameKey);
    await prefs.remove(_mdblistSavedClonesKey);
    await prefs.remove(_mdblistSyncCheckpointKey);
    await fallbackDisconnectedProgressSource(TrackingSource.mdblist);
  }

  // Maps a source MDBList list id -> the id of the static list we CLONED it
  // into on the user's account (the "Save" action). Lets the Save button know a
  // list is already saved and which clone to delete on un-save. JSON object of
  // {"<sourceId>": clonedId}.
  static const String _mdblistSavedClonesKey = 'mdblist_saved_clones';

  static Future<Map<int, int>> getMdblistSavedClones() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_mdblistSavedClonesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, int>{};
      decoded.forEach((k, v) {
        final sid = int.tryParse(k.toString());
        final cid = v is int ? v : (v is num ? v.toInt() : null);
        if (sid != null && cid != null) out[sid] = cid;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> setMdblistSavedClone(int sourceId, int clonedId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map[sourceId] = clonedId;
    await prefs.setString(
      _mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  static Future<void> removeMdblistSavedClone(int sourceId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map.remove(sourceId);
    await prefs.setString(
      _mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  /// Retire the old clone-as-like UI bookkeeping. Remote lists are deliberately
  /// untouched: an old clone is now simply a normal user-owned list.
  static Future<void> retireMdblistSavedCloneMarkers() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_mdblistSavedClonesKey);
  }

  static const String _mdblistSyncCheckpointKey = 'mdblist_sync_checkpoint_v1';

  static Future<Map<String, dynamic>?> getMdblistSyncCheckpoint() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_mdblistSyncCheckpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setMdblistSyncCheckpoint(
    Map<String, dynamic>? value,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_mdblistSyncCheckpointKey);
    } else {
      await prefs.setString(_mdblistSyncCheckpointKey, jsonEncode(value));
    }
  }

  static Future<bool> getAllDebridIntegrationEnabled() =>
      ProviderCredentialPrefs.getAllDebridIntegrationEnabled();

  static Future<void> setAllDebridIntegrationEnabled(bool enabled) =>
      ProviderCredentialPrefs.setAllDebridIntegrationEnabled(enabled);

  // AllDebrid post-torrent action methods
  static Future<String> getAllDebridPostTorrentAction() =>
      ProviderCredentialPrefs.getAllDebridPostTorrentAction();

  static Future<void> saveAllDebridPostTorrentAction(String action) =>
      ProviderCredentialPrefs.saveAllDebridPostTorrentAction(action);

  // AllDebrid hide-from-navigation
  static Future<bool> getAllDebridHiddenFromNav() =>
      ProviderCredentialPrefs.getAllDebridHiddenFromNav();

  static Future<void> setAllDebridHiddenFromNav(bool hidden) =>
      ProviderCredentialPrefs.setAllDebridHiddenFromNav(hidden);

  static Future<void> clearAllDebridHiddenFromNav() =>
      ProviderCredentialPrefs.clearAllDebridHiddenFromNav();

  static Future<bool> isInitialSetupComplete() async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      return prefs.getBool(_onboardingCompleteKey) ?? false;
    }

    final scope = ProfileRuntime.capture();
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (profile == null ||
        !profile.isEnabled ||
        profile.visibleDataGeneration != scope.dataGeneration) {
      throw StateError('Active profile onboarding state is unavailable');
    }

    // Builds that first introduced profiles wrote onboarding state to two
    // places. Honor an explicitly stored value once (notably `false` from a
    // profile reset), reconcile it into the registry, then remove the
    // compatibility value. If the key is absent, the registry was already
    // correct for migrated Admins and Admin-created profiles.
    if (!prefs.containsKey(_onboardingCompleteKey)) {
      return profile.setupComplete;
    }
    final compatibilityValue = prefs.getBool(_onboardingCompleteKey);
    if (compatibilityValue == null) {
      throw const FormatException('Invalid onboarding completion state');
    }
    if (compatibilityValue != profile.setupComplete) {
      final authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      if (ProfileRuntime.capture() != scope ||
          authorization.profileId != scope.profileId) {
        throw StateError('Active profile onboarding session has changed');
      }
      await ProfileBootstrap.registry.setActiveProfileSetupComplete(
        profileId: authorization.profileId,
        setupComplete: compatibilityValue,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
    }
    if (!await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    return compatibilityValue;
  }

  static Future<void> setInitialSetupComplete(bool value) async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      await prefs.setBool(_onboardingCompleteKey, value);
      return;
    }

    final authorization = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await authorization.validate(ProfileBootstrap.registry);
    // Remove the retired compatibility value before the canonical write. If
    // authority changes, the stale scoped wrapper fails and no other profile
    // can be mutated. A later retry safely starts from the registry value.
    if (prefs.containsKey(_onboardingCompleteKey) &&
        !await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    if (profile.setupComplete == value) return;
    await ProfileBootstrap.registry.setActiveProfileSetupComplete(
      profileId: authorization.profileId,
      setupComplete: value,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
  }

  // File Selection methods
  static Future<String> getFileSelection() =>
      ProviderCredentialPrefs.getFileSelection();

  static Future<void> saveFileSelection(String selection) =>
      ProviderCredentialPrefs.saveFileSelection(selection);

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() =>
      ProviderCredentialPrefs.getPostTorrentAction();

  static Future<void> savePostTorrentAction(String action) =>
      ProviderCredentialPrefs.savePostTorrentAction(action);

  // TorBox post-torrent action methods
  static Future<String> getTorboxPostTorrentAction() =>
      ProviderCredentialPrefs.getTorboxPostTorrentAction();

  static Future<void> saveTorboxPostTorrentAction(String action) =>
      ProviderCredentialPrefs.saveTorboxPostTorrentAction(action);

  // PikPak post-torrent action methods
  static Future<String> getPikPakPostTorrentAction() =>
      ProviderCredentialPrefs.getPikPakPostTorrentAction();

  static Future<void> savePikPakPostTorrentAction(String action) =>
      ProviderCredentialPrefs.savePikPakPostTorrentAction(action);

  // Premiumize post-torrent action methods
  static Future<String> getPremiumizePostTorrentAction() =>
      ProviderCredentialPrefs.getPremiumizePostTorrentAction();

  static Future<void> savePremiumizePostTorrentAction(String action) =>
      ProviderCredentialPrefs.savePremiumizePostTorrentAction(action);

  static Future<bool> getPremiumizeCacheCheckEnabled() =>
      ProviderCredentialPrefs.getPremiumizeCacheCheckEnabled();

  static Future<void> setPremiumizeCacheCheckEnabled(bool enabled) =>
      ProviderCredentialPrefs.setPremiumizeCacheCheckEnabled(enabled);

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

  // ── Continue Watching (recently watched items for home screen) ──────────

  /// Get all continue watching items, sorted by most recent first.
  static Future<List<Map<String, dynamic>>> getContinueWatchingItems() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      items.sort(
        (a, b) => ((b['updatedAt'] as int?) ?? 0).compareTo(
          (a['updatedAt'] as int?) ?? 0,
        ),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Add or update a continue watching entry.
  /// Deduplicates by IMDB ID — updates existing entry if found.
  static Future<void> saveContinueWatchingItem({
    required String imdbId,
    required String title,
    required String contentType,
    String? posterUrl,
    String? addonId,
    String? year,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    List<Map<String, dynamic>> items = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = await decodeJsonAsync(raw);
        items = list
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }

    // Remove existing entry with same IMDB ID
    items.removeWhere((e) => e['imdbId'] == imdbId);

    // Add at front
    items.insert(0, {
      'imdbId': imdbId,
      'title': title,
      'contentType': contentType,
      'posterUrl': posterUrl,
      'addonId': addonId,
      'year': year,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep max 50 items
    if (items.length > 50) items = items.sublist(0, 50);

    await prefs.setString(_continueWatchingKey, jsonEncode(items));
  }

  /// Remove a continue watching entry by IMDB ID.
  static Future<void> removeContinueWatchingItem(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      items.removeWhere(
        (e) => (e['imdbId'] as String?)?.trim().toLowerCase() == normalized,
      );
      await prefs.setString(_continueWatchingKey, jsonEncode(items));
    } catch (_) {}
  }

  /// Clear all continue watching items.
  static Future<void> clearContinueWatching() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_continueWatchingKey);
  }

  /// Movies finished locally by the Debrify player. This intentionally stays
  /// separate from Trakt and Simkl: tracker-backed sessions use the tracker as
  /// their source of truth, while offline/local sessions still need a durable
  /// completed state for the detail screen.
  static Future<Set<String>> _getFinishedMovieIds() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(_finishedMoviesKey) ?? const <String>[];
    return {
      for (final raw in stored)
        if (raw.trim().isNotEmpty) raw.trim().toLowerCase(),
    };
  }

  /// Snapshot used by poster badges. Returned IDs are normalized lowercase.
  static Future<Set<String>> getFinishedMovieIds() => _getFinishedMovieIds();

  static Future<bool> isMovieFinished(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return (await _getFinishedMovieIds()).contains(normalized);
  }

  /// Mark a locally tracked movie finished, remove it from Continue Watching,
  /// and clear its resumable state. The finished record itself remains so the
  /// detail action can accurately read "Rewatch".
  static Future<void> markMovieAsFinished(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (finished.add(normalized)) {
      final prefs = await ProfilePreferences.instance();
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
      localCompletionRevision.value++;
    }
    await Future.wait([
      removeContinueWatchingItem(normalized),
      clearPlaybackStateByImdbId(normalized),
    ]);
    debugPrint('StorageService: markMovieAsFinished imdbId="$normalized"');
  }

  /// Start a local rewatch. The caller saves a fresh resume point afterwards,
  /// so only the completed marker is removed here.
  static Future<void> unmarkMovieAsFinished(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (!finished.remove(normalized)) return;

    final prefs = await ProfilePreferences.instance();
    if (finished.isEmpty) {
      await prefs.remove(_finishedMoviesKey);
    } else {
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
    }
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkMovieAsFinished imdbId="$normalized"');
  }

  static Future<Set<String>> getExplicitlyWatchedSeriesIds() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getStringList(_explicitlyWatchedSeriesKey) ?? const [])
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> setSeriesExplicitlyWatched(
    String imdbId, {
    required bool watched,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final ids = await getExplicitlyWatchedSeriesIds();
    final changed = watched ? ids.add(normalized) : ids.remove(normalized);
    if (!changed) return;
    final prefs = await ProfilePreferences.instance();
    if (ids.isEmpty) {
      await prefs.remove(_explicitlyWatchedSeriesKey);
    } else {
      await prefs.setStringList(
        _explicitlyWatchedSeriesKey,
        ids.toList()..sort(),
      );
    }
    localCompletionRevision.value++;
  }

  // Enhanced Playback State methods
  static Future<Map<String, dynamic>> _getPlaybackStateMap() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playbackStateKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Remove all playback state entries (series progress, video progress) for an IMDB ID.
  static Future<void> clearPlaybackStateByImdbId(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final map = await _getPlaybackStateMap();
    final keysToRemove = <String>[];
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic> &&
          (entry.value['imdbId'] as String?)?.trim().toLowerCase() ==
              normalized) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isEmpty) return;
    for (final key in keysToRemove) {
      map.remove(key);
    }
    await _savePlaybackStateMap(map);
    // Series finished-episode markers share this map, so clearing a Continue
    // Watching item must also invalidate derived series completion.
    localCompletionRevision.value++;
    debugPrint(
      'StorageService: Cleared ${keysToRemove.length} playback state entries for "$imdbId"',
    );
  }

  static Future<void> _savePlaybackStateMap(Map<String, dynamic> map) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playbackStateKey, jsonEncode(map));
  }

  /// Save playback state for series content
  static Future<void> saveSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {'type': 'series', 'title': seriesTitle, 'seasons': {}};
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided (enables lookup by IMDB ID)
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    seriesData['seasons'][season.toString()][episode.toString()] = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    debugPrint(
      'StorageService: saveSeriesPlaybackState title="$seriesTitle" S${season}E$episode position=${positionMs}ms duration=${durationMs}ms',
    );

    await _savePlaybackStateMap(map);
  }

  /// Mark an episode as finished (watched completely)
  static Future<void> markEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'finishedEpisodes': {},
      };
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }

    // Ensure seasons map exists
    if (!seriesData.containsKey('seasons')) {
      seriesData['seasons'] = {};
    }

    // Ensure finishedEpisodes map exists
    if (!seriesData.containsKey('finishedEpisodes')) {
      seriesData['finishedEpisodes'] = {};
    }

    if (!seriesData['finishedEpisodes'].containsKey(season.toString())) {
      seriesData['finishedEpisodes'][season.toString()] = {};
    }

    seriesData['finishedEpisodes'][season.toString()][episode.toString()] = {
      'finishedAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Also add/update in seasons map so it appears in getEpisodeProgress()
    // This ensures UI can find the episode even if it was never played
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    final episodeData =
        seriesData['seasons'][season.toString()][episode.toString()];

    if (episodeData == null) {
      // Episode was never played - add dummy data to mark as watched
      seriesData['seasons'][season.toString()][episode.toString()] = {
        'positionMs': 0,
        'durationMs': 1,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
    } else {
      // Episode has existing progress - update it to show as finished
      // Set position = duration to show 100% progress
      final existingData = episodeData as Map<String, dynamic>;
      final durationMs = existingData['durationMs'] as int? ?? 1;
      existingData['positionMs'] = durationMs; // Mark as fully watched
      existingData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    }

    debugPrint(
      'StorageService: markEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
    );

    await _savePlaybackStateMap(map);
    localCompletionRevision.value++;
  }

  /// Unmark an episode as finished (mark as unwatched)
  static Future<void> unmarkEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final currentTitleKey =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;
    var changed = false;
    var aliasesChanged = 0;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      if (_clearEpisodeCompletion(
        seriesData: seriesData,
        season: season,
        episode: episode,
      )) {
        changed = true;
        aliasesChanged++;
      }
    }

    if (!changed) return;

    debugPrint(
      'StorageService: unmarkEpisodeAsFinished title="$seriesTitle" '
      'S${season}E$episode aliases=$aliasesChanged',
    );

    await _savePlaybackStateMap(map);
    localCompletionRevision.value++;
  }

  /// Clear every completed episode owned by a stable series identity.
  ///
  /// This is the local equivalent of removing a show from tracker history.
  /// Synthetic watched rows and completed checkpoints are cleared across all
  /// release-title aliases, while genuine partial rewatch progress survives.
  static Future<void> unmarkSeriesAsFinished(
    String imdbId, {
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final normalizedTitle = seriesTitle?.trim().toLowerCase();
    final map = await _getPlaybackStateMap();
    var changed = false;

    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      final storedTitle = raw['title']?.toString().trim().toLowerCase();
      final matchesStableId = storedId == normalized;
      final matchesLegacyTitle =
          normalizedTitle != null &&
          normalizedTitle.isNotEmpty &&
          storedTitle == normalizedTitle;
      if (!matchesStableId && !matchesLegacyTitle) continue;

      final coordinates = <({int season, int episode})>{};
      void collect(Object? seasons) {
        if (seasons is! Map) return;
        for (final seasonEntry in seasons.entries) {
          final season = int.tryParse(seasonEntry.key.toString());
          final episodes = seasonEntry.value;
          if (season == null || episodes is! Map) continue;
          for (final episodeKey in episodes.keys) {
            final episode = int.tryParse(episodeKey.toString());
            if (episode != null) {
              coordinates.add((season: season, episode: episode));
            }
          }
        }
      }

      collect(raw['finishedEpisodes']);
      collect(raw['seasons']);
      for (final coordinate in coordinates) {
        if (_clearEpisodeCompletion(
          seriesData: raw,
          season: coordinate.season,
          episode: coordinate.episode,
        )) {
          changed = true;
        }
      }
    }

    if (!changed) return;
    await _savePlaybackStateMap(map);
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkSeriesAsFinished imdbId="$normalized"');
  }

  /// Remove one episode's explicit completion and any synthetic/completed
  /// progress produced by marking it watched. Genuine partial progress remains
  /// intact, including a rewatch in progress under another title alias.
  static bool _clearEpisodeCompletion({
    required Map<String, dynamic> seriesData,
    required int season,
    required int episode,
  }) {
    final seasonKey = season.toString();
    final episodeKey = episode.toString();
    var changed = false;

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes is Map) {
      final seasonData = finishedEpisodes[seasonKey];
      if (seasonData is Map && seasonData.containsKey(episodeKey)) {
        seasonData.remove(episodeKey);
        if (seasonData.isEmpty) finishedEpisodes.remove(seasonKey);
        changed = true;
      }
    }

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return changed;
    final seasonData = seasons[seasonKey];
    if (seasonData is! Map) return changed;
    final episodeData = seasonData[episodeKey];
    if (episodeData is! Map) return changed;

    final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
    final isDummy = positionMs == 0 && durationMs == 1;
    final isCompleted = durationMs > 0 && positionMs >= durationMs;
    // Unwatching a fully-watched episode DROPS its row. Zeroing the offset
    // instead used to leave a "played, 0% in, not finished" ghost carrying a
    // fresh updatedAt, which then won `getLastPlayedEpisode*` and pinned
    // Continue Watching to an episode the user had just declared unwatched —
    // and every repeat of mark→unmark re-stamped it fresher.
    if (isDummy || isCompleted) {
      seasonData.remove(episodeKey);
      if (seasonData.isEmpty) seasons.remove(seasonKey);
      return true;
    }
    // Reached only for rows that were never marked watched through
    // [markEpisodeAsFinished] (it overwrites positionMs with durationMs, so a
    // marked row always lands in the branch above). A genuine partial — e.g. a
    // rewatch in progress under another title alias, swept by
    // [unmarkSeriesAsFinished] — keeps its offset.
    return changed;
  }

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final currentTitleKey =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      final finishedEpisodes = seriesData['finishedEpisodes'];
      if (finishedEpisodes is! Map) continue;
      final seasonData = finishedEpisodes[season.toString()];
      if (seasonData is Map && seasonData.containsKey(episode.toString())) {
        return true;
      }
    }
    return false;
  }

  /// Get all finished episodes for a series
  static Future<Map<String, Set<int>>> getFinishedEpisodes({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes == null) return {};

    final result = <String, Set<int>>{};

    for (final seasonEntry in finishedEpisodes.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;
      result[season] = episodes.keys.map((e) => int.parse(e)).toSet();
    }

    return result;
  }

  /// Resolve finished episodes by stable title identity, falling back to the
  /// historical title-keyed record for installs created before IMDb IDs were
  /// persisted with series playback.
  static Future<Map<String, Set<int>>> getFinishedEpisodesByImdbId({
    required String imdbId,
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    final map = await _getPlaybackStateMap();
    final result = <String, Set<int>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      if (storedId != normalized) continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      for (final entry in finished.entries) {
        final episodes = entry.value;
        if (episodes is! Map) continue;
        result.putIfAbsent(entry.key.toString(), () => <int>{}).addAll({
          for (final episode in episodes.keys)
            if (int.tryParse(episode.toString()) case final value?) value,
        });
      }
    }
    if (result.isNotEmpty) return result;
    if (seriesTitle != null && seriesTitle.isNotEmpty) {
      return getFinishedEpisodes(seriesTitle: seriesTitle);
    }
    return {};
  }

  /// One-pass index for derived series completion. IMDb keys are preferred;
  /// title keys preserve older playback records that predate stable IDs.
  static Future<Map<String, Map<String, Set<int>>>>
  getFinishedSeriesEpisodeIndex() async {
    final map = await _getPlaybackStateMap();
    final result = <String, Map<String, Set<int>>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      final parsed = <String, Set<int>>{
        for (final entry in finished.entries)
          entry.key.toString(): {
            if (entry.value is Map)
              for (final episode in (entry.value as Map).keys)
                if (int.tryParse(episode.toString()) case final value?) value,
          },
      };
      void mergeInto(String key) {
        final target = result.putIfAbsent(key, () => <String, Set<int>>{});
        for (final season in parsed.entries) {
          target.putIfAbsent(season.key, () => <int>{}).addAll(season.value);
        }
      }

      final imdbId = raw['imdbId']?.toString().trim().toLowerCase();
      if (imdbId != null && imdbId.isNotEmpty) mergeInto(imdbId);
      final title = raw['title']?.toString().trim().toLowerCase();
      if (title != null && title.isNotEmpty) mergeInto('title:$title');
    }
    return result;
  }

  /// Get episode progress for a series
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgress({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final seasons = seriesData['seasons'];
    if (seasons == null) return {};

    final result = <String, Map<String, dynamic>>{};

    for (final seasonEntry in seasons.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;

      for (final episodeEntry in episodes.entries) {
        final episode = episodeEntry.key;
        final episodeData = episodeEntry.value as Map<String, dynamic>;
        final episodeKey = '${season}_$episode';
        result[episodeKey] = episodeData;
      }
    }

    return result;
  }

  // v2: keyed by IMDb id (stable, unambiguous) instead of the normalized series
  // title. Title-keying silently broke the playlist bars whenever the writer's
  // and readers' title derivations diverged; the seed and every reader always
  // have the show's IMDb id, so we key on that. Bumped from _v1 so stale
  // title-keyed data is dropped (it re-seeds on the next series launch).
  static const String _episodeTraktProgressKey = 'episode_trakt_progress_v2';

  /// Normalized storage key for the per-episode Trakt store (keyed by IMDb id).
  static String _episodeTraktKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Trakt playback progress per episode (percent, 0–100), kept
  /// SEPARATE from the ms-based resume state. It drives the playlist progress
  /// bars only — never a resume seek directly (the players convert % → ms at
  /// play time once the real duration is known, so we never store a fake
  /// position). Keyed by the show's IMDb id; episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeTraktProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeTraktProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Trakt per-episode percents for the show [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeTraktProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeTraktProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  // Kept separate from both local playback state and Trakt. This is a
  // replace-on-launch snapshot of Simkl's remote truth, so marking an episode
  // unwatched on Simkl can clear the player tick without mutating local
  // history.
  static const String _episodeSimklProgressKey = 'episode_simkl_progress_v1';

  static String _episodeSimklKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Simkl progress per episode (percent, 0–100), keyed by the
  /// show's IMDb id. Episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeSimklProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeSimklProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeSimklKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Simkl per-episode snapshot for [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeSimklProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeSimklProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  static const String _episodeMdblistProgressKey =
      'episode_mdblist_progress_v1';

  static Future<Map<String, double>> getEpisodeMdblistProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeMdblistProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      return {
        for (final entry in series.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveEpisodeMdblistProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeMdblistProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  /// Replace one show's entry inside a provider's whole-store snapshot.
  /// Capture the originating profile before this operation queues so a profile
  /// switch cannot redirect a delayed write into the newly active profile.
  static Future<void> _saveEpisodeTrackerProgress({
    required String storeKey,
    required String imdbId,
    required Map<String, double> percents,
  }) {
    if (imdbId.isEmpty) return Future.value();
    final normalizedKey = _episodeTraktKeyFor(imdbId);
    final snapshot = Map<String, double>.from(percents);
    final profileScope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;

    Future<void> commit() =>
        _episodeTrackerSnapshotWriteLock.synchronized(() async {
          final prefs = await ProfilePreferences.instance();
          final raw = prefs.getString(storeKey);
          Map<String, dynamic> all = {};
          if (raw != null && raw.isNotEmpty) {
            try {
              final decoded = await decodeJsonAsync(raw);
              if (decoded is Map<String, dynamic>) all = decoded;
            } catch (_) {}
          }
          all[normalizedKey] = snapshot;
          await prefs.setString(storeKey, jsonEncode(all));
        });

    return profileScope == null
        ? commit()
        : ProfileRuntime.withCapturedScope(profileScope, commit);
  }

  /// Get episode progress by IMDB ID (scans playback state for matching imdbId)
  /// Also checks single-file video entries and parses season/episode from title.
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgressByImdbId(
    String imdbId,
  ) async {
    final map = await _getPlaybackStateMap();
    final normalizedImdbId = imdbId.trim().toLowerCase();

    // Merge every legacy title-keyed series entry with this IMDb id. Older
    // builds could save the same show under multiple release-derived titles;
    // stopping at the first record silently hid episodes from the others.
    final seriesResult = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> &&
          entry['imdbId']?.toString().trim().toLowerCase() ==
              normalizedImdbId) {
        if (entry['type'] == 'series') {
          final seasons = entry['seasons'];
          if (seasons is! Map) continue;
          for (final seasonEntry in seasons.entries) {
            final episodes = seasonEntry.value;
            if (episodes is! Map) continue;
            for (final episodeEntry in episodes.entries) {
              final episodeData = episodeEntry.value;
              if (episodeData is! Map) continue;
              final episodeKey = '${seasonEntry.key}_${episodeEntry.key}';
              final candidate = Map<String, dynamic>.from(episodeData);
              final existing = seriesResult[episodeKey];
              final candidateUpdatedAt =
                  (candidate['updatedAt'] as num?)?.toInt() ?? 0;
              final existingUpdatedAt =
                  (existing?['updatedAt'] as num?)?.toInt() ?? -1;
              if (candidateUpdatedAt >= existingUpdatedAt) {
                seriesResult[episodeKey] = candidate;
              }
            }
          }
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesResult.isNotEmpty) return seriesResult;

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        return {
          '${season}_$episode': {
            'positionMs': videoFallback['positionMs'] ?? 0,
            'durationMs': videoFallback['durationMs'] ?? 1,
            'updatedAt': videoFallback['updatedAt'] ?? 0,
          },
        };
      }
    }

    return {};
  }

  /// Merge local episode progress across stable IMDb identity and the current
  /// title-keyed record. The newest update wins duplicate coordinates. Equal
  /// or missing timestamps prefer the current title deterministically, which
  /// preserves legacy behavior without letting an older title record move a
  /// newer cross-alias resume position backwards.
  static Future<Map<String, Map<String, dynamic>>> getMergedEpisodeProgress({
    required String seriesTitle,
    String? imdbId,
  }) async {
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getEpisodeProgressByImdbId(imdbId)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
      if (seriesTitle.isNotEmpty)
        getEpisodeProgress(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
    ]);
    int updatedAt(Map<String, dynamic> state) {
      final value = state['updatedAt'];
      if (value is! num || !value.isFinite) return 0;
      final timestamp = value.toInt();
      return timestamp > 0 ? timestamp : 0;
    }

    final merged = Map<String, Map<String, dynamic>>.from(reads[0]);
    for (final entry in reads[1].entries) {
      final previous = merged[entry.key];
      if (previous == null || updatedAt(entry.value) >= updatedAt(previous)) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  /// IMDb-aware counterpart to [getFinishedEpisodes], unioning historical
  /// release-title records with the current title record.
  static Future<Map<String, Set<int>>> getMergedFinishedEpisodes({
    required String seriesTitle,
    String? imdbId,
  }) async {
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getFinishedEpisodesByImdbId(imdbId: imdbId)
      else
        Future.value(const <String, Set<int>>{}),
      if (seriesTitle.isNotEmpty)
        getFinishedEpisodes(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Set<int>>{}),
    ]);
    final merged = <String, Set<int>>{};
    for (final snapshot in reads) {
      for (final entry in snapshot.entries) {
        merged.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }
    return merged;
  }

  /// Get finished episodes for a specific season
  static Future<Set<int>> getFinishedEpisodesForSeason({
    required String seriesTitle,
    required int season,
  }) async {
    final allFinished = await getFinishedEpisodes(seriesTitle: seriesTitle);
    return allFinished[season.toString()] ?? <int>{};
  }

  /// Get playback state for series content
  static Future<Map<String, dynamic>?> getSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;

    final seasonData = seriesData['seasons'][season.toString()];
    if (seasonData == null) return null;

    final episodeData = seasonData[episode.toString()];
    if (episodeData == null) return null;

    return episodeData as Map<String, dynamic>;
  }

  /// Save playback state for non-series content (movies, single videos)
  static Future<void> saveVideoPlaybackState({
    required String videoTitle,
    required String videoUrl,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    map[key] = {
      'type': 'video',
      'title': videoTitle,
      'url': videoUrl,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      if (imdbId != null) 'imdbId': imdbId,
    };

    await _savePlaybackStateMap(map);
  }

  /// Get playback state for non-series content
  static Future<Map<String, dynamic>?> getVideoPlaybackState({
    required String videoTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    final imdbId = (videoData['imdbId'] as String?)?.trim();
    // A finished movie can have a stale source-specific state from a final
    // autosave tick. Its local completion record wins over that stale resume.
    if (imdbId != null && imdbId.isNotEmpty && await isMovieFinished(imdbId)) {
      return null;
    }

    return videoData as Map<String, dynamic>;
  }

  /// Get video playback state by IMDB ID (scans all video entries, returns most recent).
  static Future<Map<String, dynamic>?> getVideoPlaybackStateByImdbId(
    String imdbId,
  ) async {
    // A blank id would match every record saved without one and hand back an
    // unrelated movie's position.
    final wanted = imdbId.trim();
    if (wanted.isEmpty) return null;
    // A completion write and the periodic player autosave can overlap by one
    // tick. The finished marker is authoritative for movies, so never expose
    // a stale resume record that slipped back in during that tiny window.
    if (await isMovieFinished(wanted)) return null;
    final map = await _getPlaybackStateMap();
    Map<String, dynamic>? best;
    int bestUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is! Map<String, dynamic> || entry['type'] != 'video') continue;
      // Pattern-matched, not cast: one malformed legacy record must not throw
      // out of a scan over every saved video.
      final recorded = entry['imdbId'];
      if (recorded is String && recorded.trim() == wanted) {
        final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
        if (updatedAt > bestUpdatedAt) {
          bestUpdatedAt = updatedAt;
          best = entry;
        }
      }
    }
    return best;
  }

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData is! Map || seriesData['type'] != 'series') return null;

    // Find the most recently updated episode. Parse defensively (matching
    // getVideoPlaybackStateByImdbId above): a corrupt or old-schema entry
    // must skip, not throw, on this resume hot path.
    Map<String, dynamic>? lastEpisode;
    int lastUpdated = 0;

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return null;
    for (final seasonEntry in seasons.entries) {
      final season = int.tryParse(seasonEntry.key.toString());
      final episodes = seasonEntry.value;
      if (season == null || episodes is! Map) continue;

      for (final episodeEntry in episodes.entries) {
        final episode = int.tryParse(episodeEntry.key.toString());
        final episodeData = episodeEntry.value;
        if (episode == null || episodeData is! Map) continue;
        final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

        if (updatedAt > lastUpdated) {
          lastUpdated = updatedAt;
          lastEpisode = {
            'season': season,
            'episode': episode,
            ...Map<String, dynamic>.from(episodeData),
          };
        }
      }
    }

    if (lastEpisode != null) {
      debugPrint(
        'StorageService: getLastPlayedEpisode found S${lastEpisode['season']}E${lastEpisode['episode']} for "$seriesTitle"',
      );
    } else {
      debugPrint(
        'StorageService: getLastPlayedEpisode no episodes for "$seriesTitle"',
      );
    }

    return lastEpisode;
  }

  /// Get all episode watch progress for a series by IMDB ID.
  /// Returns a map of "season-episode" → progress percentage (0-100).
  static Future<Map<String, double>> getEpisodeWatchProgressByImdbId(
    String imdbId,
  ) async {
    final map = await _getPlaybackStateMap();
    final result = <String, double>{};

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys). Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (seriesEntries.isEmpty && videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        final posMs = (videoFallback['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (videoFallback['durationMs'] as num?)?.toInt() ?? 1;
        if (durMs > 0 && posMs > 0) {
          result['$season-$episode'] = (posMs / durMs * 100).clamp(0.0, 100.0);
        }
        return result;
      }
    }

    if (seriesEntries.isEmpty) return result;

    // Aggregate progress across ALL matching series entries
    for (final seriesData in seriesEntries) {
      final finishedMap =
          seriesData['finishedEpisodes'] as Map<String, dynamic>?;

      final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
      for (final seasonEntry in seasons.entries) {
        final seasonNum = seasonEntry.key;
        final episodes = seasonEntry.value as Map<String, dynamic>? ?? {};

        // Get finished episodes for this season
        final finishedEps = finishedMap?[seasonNum] as Map<String, dynamic>?;

        for (final episodeEntry in episodes.entries) {
          final epNum = episodeEntry.key;
          final epData = episodeEntry.value as Map<String, dynamic>;
          final key = '$seasonNum-$epNum';

          // Check if finished first
          if (finishedEps != null && finishedEps.containsKey(epNum)) {
            result[key] = 100.0;
            continue;
          }

          final positionMs = (epData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (epData['durationMs'] as num?)?.toInt() ?? 1;
          if (durationMs > 0 && positionMs > 0) {
            final progress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
            // Keep higher progress if duplicate across entries
            if (!result.containsKey(key) || progress > result[key]!) {
              result[key] = progress;
            }
          }
        }
      }
    }

    return result;
  }

  /// Look up the last played episode by IMDB ID.
  /// Scans all series entries for a matching imdbId field.
  /// Also checks single-file video entries (type=video) as a fallback,
  /// parsing season/episode from the title.
  static Future<Map<String, dynamic>?> getLastPlayedEpisodeByImdbId(
    String imdbId,
  ) async {
    final map = await _getPlaybackStateMap();

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys, e.g. "young sheldon (2017)" vs "young sheldon").
    // Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesEntries.isNotEmpty) {
      // Find most recently updated episode across ALL matching series entries
      Map<String, dynamic>? lastEpisode;
      Map<String, dynamic>?
      lastEpisodeSeriesData; // track which entry it came from
      int lastUpdated = 0;

      for (final seriesData in seriesEntries) {
        final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
        for (final seasonEntry in seasons.entries) {
          final season = int.parse(seasonEntry.key);
          final episodes = seasonEntry.value as Map<String, dynamic>;

          for (final episodeEntry in episodes.entries) {
            final episode = int.parse(episodeEntry.key);
            final episodeData = episodeEntry.value as Map<String, dynamic>;
            final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

            if (updatedAt > lastUpdated) {
              lastUpdated = updatedAt;
              lastEpisode = {
                'season': season,
                'episode': episode,
                ...episodeData,
              };
              lastEpisodeSeriesData = seriesData;
            }
          }
        }
      }

      if (lastEpisode != null && lastEpisodeSeriesData != null) {
        // Check if this episode is marked as finished (in its own series entry)
        final finishedEpisodes =
            lastEpisodeSeriesData['finishedEpisodes'] as Map<String, dynamic>?;
        if (finishedEpisodes != null) {
          final seasonFinished =
              finishedEpisodes[lastEpisode['season'].toString()]
                  as Map<String, dynamic>?;
          if (seasonFinished != null &&
              seasonFinished.containsKey(lastEpisode['episode'].toString())) {
            lastEpisode['finished'] = true;
          }
        }
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId found S${lastEpisode['season']}E${lastEpisode['episode']} for "$imdbId"${lastEpisode['finished'] == true ? ' (finished)' : ''}',
        );
      }
      return lastEpisode;
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!);
        final episode = int.parse(match.group(2)!);
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId (video fallback) parsed S${season}E$episode from "$title" for "$imdbId"',
        );
        return {
          'season': season,
          'episode': episode,
          'positionMs': videoFallback['positionMs'] ?? 0,
          'durationMs': videoFallback['durationMs'] ?? 1,
          'updatedAt': videoFallback['updatedAt'] ?? 0,
        };
      }
    }

    return null;
  }

  /// Clean up old playback state data (older than 30 days)
  static Future<void> cleanupOldPlaybackState() async {
    final map = await _getPlaybackStateMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);

    final keysToRemove = <String>[];

    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final updatedAt = data['updatedAt'] as int?;

      if (updatedAt != null && updatedAt < thirtyDaysAgo) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      map.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      await _savePlaybackStateMap(map);
    }
  }

  /// Clear all playback-related data (series and video states, track prefs, legacy resume)
  static Future<void> clearAllPlaybackData() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_playbackStateKey);
    await prefs.remove(_finishedMoviesKey);
    await prefs.remove(localSeriesCompletionStateKey);
    await prefs.remove(localSeriesCalendarCheckedAtKey);
    await prefs.remove(localSeriesCalendarAttemptedAtKey);
    localCompletionRevision.value++;
    // Resume lives in the DB now; the prefs key only still exists for users
    // who wipe before the one-time import has run.
    await prefs.remove(_videoResumeKey);
    await IptvMediaStore.clearVideoResume();
    debugPrint(
      'StorageService: cleared playback state, completed movies, and video resume data',
    );
  }

  /// Clear all progress data for a specific playlist/series
  static Future<void> clearPlaylistProgress({required String title}) async {
    final map = await _getPlaybackStateMap();

    debugPrint('StorageService: clearPlaylistProgress called for "$title"');

    final keysToRemove = <String>[];

    // Use the SAME matching logic as when finding series progress
    // Try multiple title variations to find all matching entries

    // Variation 1: Use the full playlist item title
    final fullTitleKey =
        'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final fullVideoKey =
        'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    // Variation 2: Try extracting clean title (like "breaking bad" from "Breaking.Bad.SEASON.01.S01...")
    // This matches how SeriesPlaylist extracts the title
    String cleanedTitle = title;

    // Remove common patterns to extract series name
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.S\d{2}.*', caseSensitive: false),
      '',
    ); // Remove S01-S08 and everything after
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.Season\..*', caseSensitive: false),
      '',
    ); // Remove Season.1-8
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
      '',
    ); // Remove quality
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
      '',
    ); // Remove codec
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
      '',
    ); // Remove source
    cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

    final cleanTitleKey =
        'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final cleanVideoKey =
        'video_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    debugPrint(
      'StorageService: checking keys - full: $fullTitleKey / $fullVideoKey, clean: $cleanTitleKey / $cleanVideoKey',
    );
    debugPrint('StorageService: available keys: ${map.keys.toList()}');

    // Check for exact key matches first
    for (final key in [
      cleanTitleKey,
      cleanVideoKey,
      fullTitleKey,
      fullVideoKey,
    ]) {
      if (map.containsKey(key) && !keysToRemove.contains(key)) {
        keysToRemove.add(key);
        debugPrint('StorageService: exact key match: "$key"');
      }
    }

    // Fallback: Search through all series/video entries
    // Check if the input title contains the stored series title
    // This handles cases where playlist title is "Game of Thrones - Season 3" but stored title is "game of thrones"
    for (final entry in map.entries) {
      if ((entry.key.startsWith('series_') || entry.key.startsWith('video_')) &&
          entry.value is Map<String, dynamic> &&
          !keysToRemove.contains(entry.key)) {
        final storedTitle =
            (entry.value['title'] as String?)?.toLowerCase() ?? '';
        if (storedTitle.isEmpty) continue;

        final titleLower = title.toLowerCase();
        final cleanedTitleLower = cleanedTitle.toLowerCase();

        // Check if the stored series title matches in several ways:
        // 1. Exact match with cleaned title (e.g., "game of thrones" == "game of thrones")
        // 2. Input title contains the stored series title (e.g., "game of thrones - season 3" contains "game of thrones")
        // 3. Cleaned title contains the stored series title
        if (storedTitle == cleanedTitleLower ||
            storedTitle == titleLower ||
            (titleLower.contains(storedTitle) &&
                storedTitle.split(' ').length >= 2)) {
          keysToRemove.add(entry.key);
          debugPrint(
            'StorageService: stored title match - key: "${entry.key}", storedTitle: "$storedTitle"',
          );
        }
      }
    }

    // Remove all matching keys
    for (final key in keysToRemove) {
      map.remove(key);
      debugPrint('StorageService: removed progress entry with key: "$key"');
    }

    // Save the updated map if anything was removed
    if (keysToRemove.isNotEmpty) {
      await _savePlaybackStateMap(map);
      // Finished episodes live in this same map. Re-derive local series
      // completion so watched badges and Continue Watching update immediately.
      localCompletionRevision.value++;
      debugPrint(
        'StorageService: clearPlaylistProgress completed - removed ${keysToRemove.length} entries for "$title"',
      );
    } else {
      debugPrint('StorageService: no progress data found for "$title"');
    }
  }

  // Video resume — one row per item in debrify_tv.db (see IptvMediaStore).
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

  /// Save audio and subtitle preferences for series content
  static Future<void> saveSeriesTrackPreferences({
    required String seriesTitle,
    required String audioTrackId,
    required String subtitleTrackId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'trackPreferences': {},
      };
    }

    final seriesData = map[key] as Map<String, dynamic>;
    if (!seriesData.containsKey('trackPreferences')) {
      seriesData['trackPreferences'] = {};
    }

    seriesData['trackPreferences'] = {
      'audioTrackId': audioTrackId,
      'subtitleTrackId': subtitleTrackId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await _savePlaybackStateMap(map);
  }

  /// Get audio and subtitle preferences for series content
  static Future<Map<String, dynamic>?> getSeriesTrackPreferences({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;

    final trackPreferences = seriesData['trackPreferences'];
    if (trackPreferences == null) return null;

    return trackPreferences as Map<String, dynamic>;
  }

  /// Save audio and subtitle preferences for non-series content
  static Future<void> saveVideoTrackPreferences({
    required String videoTitle,
    required String audioTrackId,
    required String subtitleTrackId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {'type': 'video', 'title': videoTitle, 'trackPreferences': {}};
    }

    final videoData = map[key] as Map<String, dynamic>;
    if (!videoData.containsKey('trackPreferences')) {
      videoData['trackPreferences'] = {};
    }

    videoData['trackPreferences'] = {
      'audioTrackId': audioTrackId,
      'subtitleTrackId': subtitleTrackId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await _savePlaybackStateMap(map);
  }

  /// Get audio and subtitle preferences for non-series content
  static Future<Map<String, dynamic>?> getVideoTrackPreferences({
    required String videoTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    final trackPreferences = videoData['trackPreferences'];
    if (trackPreferences == null) return null;

    return trackPreferences as Map<String, dynamic>;
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


  // Playlist storage (local-only MVP)
  static Future<List<Map<String, dynamic>>> getPlaylistItemsRaw() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playlistKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> savePlaylistItemsRaw(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playlistKey, jsonEncode(items));
  }

  static String computePlaylistDedupeKey(Map<String, dynamic> item) {
    final providerRaw = (item['provider'] as String?) ?? 'realdebrid';
    final provider = providerRaw.toLowerCase();
    if (provider == 'webdav') {
      final server = (item['webdavServerId'] ?? item['webdavBaseUrl'] ?? '')
          .toString();
      final path = (item['webdavPath'] ?? item['webdavFolderPath'] ?? '')
          .toString();
      if (server.isNotEmpty && path.isNotEmpty) {
        return '$provider|server:${server.toLowerCase()}|path:$path';
      }
    }
    final String? torrentHash = item['torrent_hash'] as String?;
    if (torrentHash != null && torrentHash.isNotEmpty) {
      return '$provider|hash:${torrentHash.toLowerCase()}';
    }
    final dynamic torboxIdRaw = item['torboxTorrentId'];
    if (torboxIdRaw != null) {
      final String torboxId = torboxIdRaw.toString();
      final dynamic singleFileId = item['torboxFileId'];
      if (singleFileId != null) {
        final fileKey = 'torbox:$torboxId:file:${singleFileId.toString()}';
        return '$provider|${fileKey.toLowerCase()}';
      }
      final dynamic multiFileIds = item['torboxFileIds'];
      if (multiFileIds is List && multiFileIds.isNotEmpty) {
        final joined = multiFileIds.map((e) => e.toString()).join(',');
        final filesKey = 'torbox:$torboxId:files:$joined';
        return '$provider|${filesKey.toLowerCase()}';
      }
      return '$provider|torbox:${torboxId.toLowerCase()}';
    }
    // PikPak file ID based key
    final dynamic pikpakFileId = item['pikpakFileId'];
    if (pikpakFileId != null) {
      return '$provider|pikpak:file:${pikpakFileId.toString().toLowerCase()}';
    }
    final dynamic pikpakFileIds = item['pikpakFileIds'];
    if (pikpakFileIds is List && pikpakFileIds.isNotEmpty) {
      final joined = pikpakFileIds.map((e) => e.toString()).join(',');
      return '$provider|pikpak:files:${joined.toLowerCase()}';
    }
    // Premiumize cloud-browser items are keyed by cloud item id (they have no
    // torrent hash, unlike items added from search).
    final dynamic premiumizeItemId = item['premiumizeItemId'];
    if (premiumizeItemId != null && premiumizeItemId.toString().isNotEmpty) {
      return '$provider|premiumize:item:${premiumizeItemId.toString().toLowerCase()}';
    }
    final dynamic premiumizeItemIds = item['premiumizeItemIds'];
    if (premiumizeItemIds is List && premiumizeItemIds.isNotEmpty) {
      final joined = premiumizeItemIds.map((e) => e.toString()).join(',');
      return '$provider|premiumize:items:${joined.toLowerCase()}';
    }
    final String? rdId = (item['rdTorrentId'] as String?);
    if (rdId != null && rdId.isNotEmpty) {
      return '$provider|rd:${rdId.toLowerCase()}';
    }
    final String source =
        (item['restrictedLink'] as String?)?.trim() ??
        (item['url'] as String?)?.trim() ??
        '';
    final String title = (item['title'] as String?)?.trim() ?? '';
    final legacyKey = '$source|$title'.toLowerCase();
    return '$provider|$legacyKey';
  }

  /// Add a new playlist item if it does not already exist.
  /// Expected item shape (MVP): { url, title, restrictedLink, rdTorrentId }
  /// Returns true if inserted, false if duplicate.
  static Future<bool> addPlaylistItemRaw(Map<String, dynamic> item) async {
    final items = await getPlaylistItemsRaw();
    final initialKey = computePlaylistDedupeKey(item);
    debugPrint('Playlist dedupe: initialKey=$initialKey');
    for (final existing in items) {
      final existingKey = computePlaylistDedupeKey(existing);
      final existingProvider = (existing['provider'] as String?) ?? 'unknown';
      debugPrint(
        'Playlist dedupe: existingKey=$existingKey provider=$existingProvider',
      );
    }
    final initialExists = items.any(
      (entry) => computePlaylistDedupeKey(entry) == initialKey,
    );
    if (initialExists) {
      debugPrint('Playlist dedupe: blocked by initial key match');
      return false;
    }

    final enriched = Map<String, dynamic>.from(item);
    enriched['addedAt'] = DateTime.now().millisecondsSinceEpoch;
    enriched['provider'] = ((item['provider'] as String?)?.isNotEmpty ?? false)
        ? item['provider']
        : 'realdebrid';

    final bool isTorbox =
        (enriched['provider'] as String?)?.toLowerCase() == 'torbox';

    // Fetch and add torrent hash if we have a torrent ID
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? apiKey = await getApiKey();

    if (!isTorbox &&
        rdTorrentId != null &&
        rdTorrentId.isNotEmpty &&
        apiKey != null &&
        apiKey.isNotEmpty) {
      try {
        // Import DebridService here to avoid circular dependency
        final response = await http.get(
          Uri.parse(
            'https://api.real-debrid.com/rest/1.0/torrents/info/$rdTorrentId',
          ),
          headers: {'Authorization': 'Bearer $apiKey'},
        );

        if (response.statusCode == 200) {
          final torrentInfo = json.decode(response.body);
          final String? hash = torrentInfo['hash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            enriched['torrent_hash'] = hash;
            debugPrint(
              '✅ Torrent hash fetched and stored: $hash for torrent ID: $rdTorrentId',
            );
          } else {
            debugPrint(
              '⚠️ No hash found in torrent info for torrent ID: $rdTorrentId',
            );
          }
        } else {
          debugPrint(
            '❌ Failed to fetch torrent info. Status code: ${response.statusCode} for torrent ID: $rdTorrentId',
          );
        }
      } catch (e) {
        debugPrint(
          '❌ Error fetching torrent hash for torrent ID: $rdTorrentId - $e',
        );
        // Silently continue without hash if fetch fails
        // This ensures playlist addition doesn't fail due to hash fetch issues
      }
    } else {
      debugPrint(
        'ℹ️ Skipping torrent hash fetch - missing rdTorrentId or API key',
      );
    }

    // Log what's being saved to database
    debugPrint('📝 Adding playlist item to database:');
    debugPrint('   Title: ${enriched['title']}');
    debugPrint('   Kind: ${enriched['kind']}');
    debugPrint('   rdTorrentId: ${enriched['rdTorrentId']}');
    debugPrint('   torrent_hash: ${enriched['torrent_hash'] ?? 'null'}');
    debugPrint('   restrictedLink: ${enriched['restrictedLink'] ?? 'null'}');
    debugPrint(
      '   addedAt: ${DateTime.fromMillisecondsSinceEpoch(enriched['addedAt']).toIso8601String()}',
    );

    final finalKey = computePlaylistDedupeKey(enriched);
    if (finalKey != initialKey) {
      final finalExists = items.any(
        (entry) => computePlaylistDedupeKey(entry) == finalKey,
      );
      if (finalExists) {
        debugPrint('Playlist dedupe: blocked by final key match ($finalKey)');
        return false;
      }
    }

    items.insert(0, enriched);
    await savePlaylistItemsRaw(items);

    return true;
  }

  static Future<void> removePlaylistItemByKey(String dedupeKey) async {
    final items = await getPlaylistItemsRaw();
    items.removeWhere((e) => computePlaylistDedupeKey(e) == dedupeKey);
    await savePlaylistItemsRaw(items);
  }

  /// Update lastPlayedAt timestamp for a playlist item
  /// Call this when user starts playing a playlist item
  static Future<void> updatePlaylistItemLastPlayed(
    Map<String, dynamic> item,
  ) async {
    final items = await getPlaylistItemsRaw();
    final dedupeKey = computePlaylistDedupeKey(item);
    final index = items.indexWhere(
      (e) => computePlaylistDedupeKey(e) == dedupeKey,
    );

    if (index != -1) {
      items[index]['lastPlayedAt'] = DateTime.now().millisecondsSinceEpoch;
      await savePlaylistItemsRaw(items);
      debugPrint(
        'StorageService: Updated lastPlayedAt for "${items[index]['title']}"',
      );
    }
  }

  /// Get lastPlayedAt timestamp for a playlist item
  /// Returns null if item has never been played
  static int? getPlaylistItemLastPlayed(Map<String, dynamic> item) {
    return item['lastPlayedAt'] as int?;
  }

  static Future<void> clearPlaylist() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_playlistKey);
  }

  /// Clear all playlist-related metadata (view modes, favorites, poster overrides)
  static Future<void> clearAllPlaylistMetadata() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_playlistViewModesKey);
    await prefs.remove(_playlistFavoritesKey);
    await prefs.remove(_playlistPosterOverridesKey);
    await prefs.remove(_tvMazeSeriesMappingKey);
  }

  /// Clear all startup settings (auto-launch, channel/playlist references)
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
  static Future<void> clearAllIntegrationStates() =>
      ProviderCredentialPrefs.clearAllIntegrationStates();

  /// Clear Debrify TV provider and legacy channels key
  static Future<void> clearDebrifyTvProviderAndLegacy() =>
      DebrifyTvPrefs.clearDebrifyTvProviderAndLegacy();


  /// Clear filter settings (qualities, rip sources, languages)
  static Future<void> clearAllFilterSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultFilterQualitiesKey);
    await prefs.remove(_defaultFilterRipSourcesKey);
    await prefs.remove(_defaultFilterLanguagesKey);
    await prefs.remove(_defaultFilterSizesKey);
    await prefs.remove(_defaultFilterDynamicRangesKey);
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
  static Future<void> clearAllPostTorrentActions() =>
      ProviderCredentialPrefs.clearAllPostTorrentActions();

  /// Clear all Debrify TV display and engine settings
  static Future<void> clearAllDebrifyTvSettings() =>
      DebrifyTvPrefs.clearAllDebrifyTvSettings();


  /// Update an existing playlist item with poster URL
  /// Supports both RealDebrid (rdTorrentId) and PikPak (pikpakCollectionId)
  static Future<bool> updatePlaylistItemPoster(
    String posterUrl, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
  }) async {
    debugPrint('🎨 updatePlaylistItemPoster called with:');
    debugPrint('  posterUrl: $posterUrl');
    debugPrint('  rdTorrentId: $rdTorrentId');
    debugPrint('  torboxTorrentId: $torboxTorrentId');
    debugPrint('  pikpakCollectionId: $pikpakCollectionId');
    debugPrint('  webDavServerId: $webDavServerId');
    debugPrint('  webDavPath: $webDavPath');

    final items = await getPlaylistItemsRaw();
    debugPrint('  Total playlist items: ${items.length}');

    int itemIndex = -1;

    // Search by rdTorrentId if provided (RealDebrid)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by rdTorrentId at index $itemIndex');
      }
    }

    // Search by torboxTorrentId if provided and not found yet (Torbox)
    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      debugPrint('  Searching for torboxTorrentId: $torboxTorrentId');
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final torboxId = item['torboxTorrentId'];
        debugPrint(
          '    Item[$i] torboxTorrentId: $torboxId (type: ${torboxId.runtimeType})',
        );
        if (torboxId != null &&
            torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          debugPrint('  ✅ Found item by torboxTorrentId at index $itemIndex');
          break;
        }
      }
    }

    // Search by pikpakCollectionId if provided and not found yet (PikPak)
    if (itemIndex == -1 &&
        pikpakCollectionId != null &&
        pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        // Check single PikPak files
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) {
          return true;
        }

        // Check PikPak collections (first file ID in array)
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          final firstId = pikpakFileIds[0].toString();
          if (firstId == pikpakCollectionId) {
            return true;
          }
        }

        return false;
      });
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by pikpakCollectionId at index $itemIndex');
      }
    }

    // Search by Premiumize infohash if provided and not found yet (Premiumize)
    if (itemIndex == -1 &&
        premiumizeHash != null &&
        premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                premiumizeHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeHash at index $itemIndex');
      }
    }

    // Search by Premiumize cloud item id if provided and not found yet
    // (cloud-browser items have no torrent hash).
    if (itemIndex == -1 &&
        premiumizeItemId != null &&
        premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeItemId at index $itemIndex');
      }
    }

    // Search by AllDebrid infohash if provided and not found yet.
    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                allDebridHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by allDebridHash at index $itemIndex');
      }
    }

    if (itemIndex == -1 &&
        webDavPath != null &&
        webDavPath.isNotEmpty &&
        ((webDavServerId != null && webDavServerId.isNotEmpty) ||
            (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty))) {
      final webDavKey = computePlaylistDedupeKey({
        'provider': 'webdav',
        if (webDavServerId != null && webDavServerId.isNotEmpty)
          'webdavServerId': webDavServerId,
        if (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty)
          'webdavBaseUrl': webDavBaseUrl,
        'webdavPath': webDavPath,
      });
      itemIndex = items.indexWhere(
        (item) => computePlaylistDedupeKey(item) == webDavKey,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by WebDAV key at index $itemIndex');
      }
    }

    if (itemIndex == -1) {
      debugPrint('  ❌ Item not found in playlist!');
      return false;
    }

    debugPrint('  💾 Saving poster to item at index $itemIndex');
    items[itemIndex]['posterUrl'] = posterUrl;
    await savePlaylistItemsRaw(items);
    debugPrint('  ✅ Poster saved successfully!');
    return true;
  }

  static Future<bool> updatePlaylistItemImdbId(
    String imdbId, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    bool force = false,
  }) async {
    final items = await getPlaylistItemsRaw();
    int itemIndex = -1;

    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
    }

    if (itemIndex == -1 &&
        premiumizeHash != null &&
        premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                premiumizeHash.toLowerCase(),
      );
    }

    if (itemIndex == -1 &&
        premiumizeItemId != null &&
        premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
    }

    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        final torboxId = items[i]['torboxTorrentId'];
        if (torboxId != null &&
            torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          break;
        }
      }
    }

    if (itemIndex == -1 &&
        pikpakCollectionId != null &&
        pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) return true;
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          return pikpakFileIds[0].toString() == pikpakCollectionId;
        }
        return false;
      });
    }

    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                allDebridHash.toLowerCase(),
      );
    }

    if (itemIndex == -1) return false;

    if (!force) {
      final existing = items[itemIndex]['imdbId'] as String?;
      if (existing != null && existing.isNotEmpty) return true;
    }

    items[itemIndex]['imdbId'] = imdbId;
    await savePlaylistItemsRaw(items);
    debugPrint(
      'StorageService: Saved imdbId $imdbId to playlist item "${items[itemIndex]['title']}"',
    );
    return true;
  }

  /// Get saved view mode for a playlist item
  /// Returns null if no view mode has been saved for this item
  static Future<String?> getPlaylistItemViewMode(
    Map<String, dynamic> item,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    if (viewModesJson == null) return null;

    try {
      final viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
      return viewModes[dedupeKey] as String?;
    } catch (e) {
      debugPrint('Error reading playlist view modes: $e');
      return null;
    }
  }

  /// Save view mode for a playlist item
  static Future<void> savePlaylistItemViewMode(
    Map<String, dynamic> item,
    String viewMode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    Map<String, dynamic> viewModes = {};
    if (viewModesJson != null) {
      try {
        viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist view modes: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    viewModes[dedupeKey] = viewMode;

    await prefs.setString(_playlistViewModesKey, jsonEncode(viewModes));
  }

  /// Check if a playlist item is favorited
  static Future<bool> isPlaylistItemFavorited(Map<String, dynamic> item) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
      return favorites[dedupeKey] == true;
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a playlist item
  static Future<void> setPlaylistItemFavorited(
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist favorites: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    if (isFavorited) {
      favorites[dedupeKey] = true;
    } else {
      favorites.remove(dedupeKey);
    }

    await prefs.setString(_playlistFavoritesKey, jsonEncode(favorites));
  }

  /// Get all favorite dedupe keys
  static Future<Set<String>> getPlaylistFavoriteKeys() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return {};
    }
  }

  // ========================================================================
  // My Watchlist (movies + series)
  // ========================================================================

  /// Stable identity for Debrify's local movie/series watchlist. Prefer IMDb
  /// so the same title coming from two addons is one entry; fall back to the
  /// source addon + its content id for titles that do not expose IMDb metadata.
  /// Addon ids are part of that fallback because content ids are addon-local.
  static bool supportsMyWatchlistItem(StremioMeta item) {
    final type = item.type.trim().toLowerCase();
    return type == 'movie' || type == 'series';
  }

  /// Returns the identity-bearing item used by both watchlist reads and
  /// writes. A stored source is authoritative for non-IMDb ids; [fallback]
  /// only fills in a source for a newly opened source-less item.
  static StremioMeta withMyWatchlistSource(
    StremioMeta item,
    StremioAddon fallback,
  ) => item.sourceAddon == null ? item.withSourceAddon(fallback) : item;

  static String myWatchlistItemKey(StremioMeta item) {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final type = item.type.trim().toLowerCase();
    final imdbId = item.effectiveImdbId?.trim();
    if (imdbId != null && imdbId.isNotEmpty) return '$type:$imdbId';

    final sourceId = item.sourceAddon?.id.trim();
    final namespace = (sourceId == null || sourceId.isEmpty)
        ? 'unknown'
        : sourceId;
    return '$type:addon:${Uri.encodeComponent(namespace)}:'
        '${Uri.encodeComponent(item.id)}';
  }

  /// tvOS durability ceiling for the encoded watchlist. The recovery envelope
  /// silently skips any single value over its per-value limit, which would
  /// resurrect the wipe-on-restart bug; the 16KiB margin covers the
  /// JSON-escaping inflation the value picks up inside the envelope.
  static const int myWatchlistTvOsCapBytes =
      TvOsRecoveryLimits.envelopeValueBytes - 16 * 1024;

  /// Test seam: `PlatformUtil.isTvOS` is a `static final` and cannot be
  /// overridden, so tests drive the cap through this instead.
  @visibleForTesting
  static bool? debugMyWatchlistTvOsCapOverride;

  static bool get _myWatchlistCapEnforced =>
      debugMyWatchlistTvOsCapOverride ?? PlatformUtil.isTvOS;

  static int _myWatchlistAddedAt(Map<String, dynamic> row) {
    final raw = row['addedAt'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  /// Recomputes keys from stored metadata so rows written by the original
  /// un-namespaced fallback scheme migrate in memory immediately. The next
  /// mutation persists the canonical key.
  static void _canonicalizeMyWatchlistRowKey(Map<String, dynamic> row) {
    final raw = row['item'];
    if (raw is! Map) return;
    try {
      final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
      if (supportsMyWatchlistItem(item)) {
        row['key'] = myWatchlistItemKey(item);
      }
    } catch (_) {
      // The item loader below will ignore the malformed row.
    }
  }

  static Future<List<Map<String, dynamic>>> _readMyWatchlistRows() async {
    final prefs = await ProfilePreferences.instance();
    final encoded = prefs.getString(_myWatchlistKey);
    if (encoded == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final rows = [
        for (final row in decoded)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      for (final row in rows) {
        _canonicalizeMyWatchlistRowKey(row);
      }
      return rows;
    } catch (e) {
      debugPrint('Error reading My Watchlist: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Saved titles, newest first. Corrupt individual rows are ignored so one
  /// bad addon payload cannot make the whole shelf disappear.
  static Future<List<StremioMeta>> getMyWatchlistItems() async {
    final rows = await _readMyWatchlistRows();
    rows.sort(
      (a, b) => _myWatchlistAddedAt(b).compareTo(_myWatchlistAddedAt(a)),
    );
    final items = <StremioMeta>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.id.isEmpty || !supportsMyWatchlistItem(item)) {
          continue;
        }
        items.add(item);
      } catch (_) {
        // Skip only the malformed row.
      }
    }
    return items;
  }

  static Future<bool> isInMyWatchlist(StremioMeta item) async {
    if (!supportsMyWatchlistItem(item)) return false;
    final key = myWatchlistItemKey(item);
    final rows = await _readMyWatchlistRows();
    return rows.any((row) => row['key'] == key);
  }

  /// Adds, refreshes, or removes a title. Adding stores the full presentation
  /// metadata needed by Home, not just an id, so My Watchlist paints instantly
  /// offline and can route back through the source addon when it is installed.
  static Future<void> setMyWatchlistItem(StremioMeta item, bool saved) async {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final key = myWatchlistItemKey(item);
    final existing = rows.where((row) => row['key'] == key).firstOrNull;
    rows.removeWhere((row) => row['key'] == key);
    if (saved) {
      rows.insert(0, {
        'key': key,
        'addedAt': existing == null
            ? DateTime.now().millisecondsSinceEpoch
            : _myWatchlistAddedAt(existing),
        'item': item.toJson(),
      });
    }
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      var encoded = jsonEncode(rows);
      if (_myWatchlistCapEnforced) {
        // Oldest rows go first. The scan starts past index 0 because the row
        // just written sits there — a re-save keeps its original addedAt, so
        // an oldest-by-timestamp scan could otherwise evict exactly it.
        while (rows.length > 1 &&
            utf8.encode(encoded).length > myWatchlistTvOsCapBytes) {
          var oldest = 1;
          for (var i = 2; i < rows.length; i++) {
            if (_myWatchlistAddedAt(rows[i]) <
                _myWatchlistAddedAt(rows[oldest])) {
              oldest = i;
            }
          }
          rows.removeAt(oldest);
          encoded = jsonEncode(rows);
        }
      }
      await prefs.setString(_myWatchlistKey, encoded);
    }
  }

  /// Removes a saved movie/series once actual playback is about to launch.
  /// IMDb is authoritative. Older/addon-local items without IMDb metadata use
  /// a conservative title/source fallback and are removed only when unique.
  static Future<bool> removeMyWatchlistItemForPlayback({
    String? imdbId,
    required String contentType,
    required String title,
    String? addonId,
  }) async {
    final type = contentType.trim().toLowerCase();
    if (type != 'movie' && type != 'series') return false;
    final normalizedImdb = imdbId?.trim().toLowerCase();
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedAddon = addonId?.trim().toLowerCase();
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.type.trim().toLowerCase() != type) continue;
        final itemImdb = item.effectiveImdbId?.trim().toLowerCase();
        if (normalizedImdb != null && normalizedImdb.isNotEmpty) {
          if (itemImdb == normalizedImdb) matches.add(row);
          continue;
        }
        if (itemImdb != null && itemImdb.isNotEmpty) continue;
        if (normalizedTitle.isEmpty ||
            item.name.trim().toLowerCase() != normalizedTitle) {
          continue;
        }
        final itemAddon = item.sourceAddon?.id.trim().toLowerCase();
        if (normalizedAddon != null &&
            normalizedAddon.isNotEmpty &&
            itemAddon != normalizedAddon) {
          continue;
        }
        matches.add(row);
      } catch (_) {
        // Malformed rows are ignored rather than making playback fail.
      }
    }
    if (matches.length != 1) return false;
    rows.remove(matches.single);
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      await prefs.setString(_myWatchlistKey, jsonEncode(rows));
    }
    return true;
  }

  static Future<void> clearMyWatchlist() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_myWatchlistKey);
  }

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

  static String canonicalIptvChannelKey(String url) =>
      IptvPrefs.canonicalIptvChannelKey(url);

  static Future<void> reconcileIptvFavoriteUrls(List<IptvChannel> channels) =>
      IptvPrefs.reconcileIptvFavoriteUrls(channels);

  static Future<void> reconcileIptvFavoriteUrlsForCatalog(String catalogKey) =>
      IptvPrefs.reconcileIptvFavoriteUrlsForCatalog(catalogKey);

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

  static Future<List<IptvListMeta>> getIptvLists() => IptvPrefs.getIptvLists();

  static Future<String> createIptvList(String name) =>
      IptvPrefs.createIptvList(name);

  static Future<void> renameIptvList(String listId, String name) =>
      IptvPrefs.renameIptvList(listId, name);

  static Future<void> deleteIptvList(String listId) =>
      IptvPrefs.deleteIptvList(listId);

  static Future<void> reorderIptvLists(List<String> orderedIds) =>
      IptvPrefs.reorderIptvLists(orderedIds);

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

  static Future<Map<String, Map<String, dynamic>>> getIptvListChannels(
    String listId,
  ) => IptvPrefs.getIptvListChannels(listId);

  static Future<void> reorderIptvListChannels(
    String listId,
    Iterable<String> orderedUrls,
  ) => IptvPrefs.reorderIptvListChannels(listId, orderedUrls);

  static Future<List<IptvChannelOrderEntry>> getIptvCategoryOrderEntries(
    String sourceId,
    Iterable<IptvChannel> channels,
    String group,
  ) => IptvPrefs.getIptvCategoryOrderEntries(sourceId, channels, group);

  static Future<void> setIptvCategoryChannelOrder(
    String sourceId,
    String group,
    Iterable<IptvChannelOrderIdentity> ordered,
  ) => IptvPrefs.setIptvCategoryChannelOrder(sourceId, group, ordered);

  static Future<List<IptvChannel>> applyIptvCategoryChannelOrders(
    String sourceId,
    List<IptvChannel> channels,
  ) => IptvPrefs.applyIptvCategoryChannelOrders(sourceId, channels);

  static Future<void> removeIptvCategoryOrdersForSource(String sourceId) =>
      IptvPrefs.removeIptvCategoryOrdersForSource(sourceId);

  static Future<Map<String, Set<String>>> getIptvChannelMembership() =>
      IptvPrefs.getIptvChannelMembership();

  static Future<
    ({
      Map<String, Set<String>> membership,
      Map<(String, String), String> origins,
    })
  >
  getIptvMembershipSnapshot() => IptvPrefs.getIptvMembershipSnapshot();

  static Future<Set<String>> getIptvListsForChannel(String channelUrl) =>
      IptvPrefs.getIptvListsForChannel(channelUrl);

  static Future<void> removeIptvListChannelsByPlaylistId(String playlistId) =>
      IptvPrefs.removeIptvListChannelsByPlaylistId(playlistId);

  static Map<String, String> iptvFavoriteHeaders(Map<String, dynamic> meta) =>
      IptvPrefs.iptvFavoriteHeaders(meta);

  static Future<void> removeIptvFavoritesByPlaylistId(String playlistId) =>
      IptvPrefs.removeIptvFavoritesByPlaylistId(playlistId);

  static Future<Map<String, Map<String, dynamic>>> getIptvFavoriteChannels() =>
      IptvPrefs.getIptvFavoriteChannels();

  static Future<Set<String>> getIptvFavoriteChannelUrls() =>
      IptvPrefs.getIptvFavoriteChannelUrls();

  static Future<bool> getIptvTrackContinueWatching() =>
      IptvPrefs.getIptvTrackContinueWatching();

  static Future<void> setIptvTrackContinueWatching(bool value) =>
      IptvPrefs.setIptvTrackContinueWatching(value);

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

  static Future<Map<String, Map<String, dynamic>>> getIptvWatchHistory() =>
      IptvPrefs.getIptvWatchHistory();

  static Future<List<Map<String, dynamic>>> getIptvContinueWatching() =>
      IptvPrefs.getIptvContinueWatching();

  static Future<Map<String, double>> getIptvProgressForUrls(
    Iterable<String> urls,
  ) => IptvPrefs.getIptvProgressForUrls(urls);

  static Future<Map<String, int>> getIptvResumePositions(
    Iterable<String> urls,
  ) => IptvPrefs.getIptvResumePositions(urls);

  static Future<void> removeIptvWatchHistoryByPlaylistId(String playlistId) =>
      IptvPrefs.removeIptvWatchHistoryByPlaylistId(playlistId);

  static Future<void> removeIptvContinueWatchingItem(String url) =>
      IptvPrefs.removeIptvContinueWatchingItem(url);

  static Future<void> removeIptvContinueWatchingSeries({
    required String playlistId,
    required String seriesId,
  }) => IptvPrefs.removeIptvContinueWatchingSeries(
    playlistId: playlistId,
    seriesId: seriesId,
  );

  /// Build progress map for playlist items
  /// Maps playlist dedupe keys to their playback progress data
  static Future<Map<String, Map<String, dynamic>>> buildPlaylistProgressMap(
    List<Map<String, dynamic>> playlistItems,
  ) async {
    final progressMap = <String, Map<String, dynamic>>{};
    final playbackStateMap = await _getPlaybackStateMap();

    for (final item in playlistItems) {
      final dedupeKey = computePlaylistDedupeKey(item);
      final title = (item['title'] as String?) ?? '';

      // Try to find progress data for this item
      Map<String, dynamic>? progressData;

      // Check if it's stored as a video (single file)
      final videoKey =
          'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      final videoState = playbackStateMap[videoKey];
      if (videoState != null && videoState['type'] == 'video') {
        progressData = {
          'positionMs': videoState['positionMs'] ?? 0,
          'durationMs': videoState['durationMs'] ?? 0,
          'updatedAt': videoState['updatedAt'] ?? 0,
        };
      }

      // Check if it's stored as a series
      if (progressData == null) {
        // Try multiple title variations to find the series state
        String? matchingSeriesKey;
        Map<String, dynamic>? seriesState;

        // Variation 1: Use the full playlist item title
        final fullTitleKey =
            'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Variation 2: Try extracting clean title (like "game of thrones" from torrent name)
        // This matches how SeriesPlaylist extracts the title
        String cleanedTitle = title;

        // Remove common patterns to extract series name
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.S\d{2}.*', caseSensitive: false),
          '',
        ); // Remove S01-S08 and everything after
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.Season\..*', caseSensitive: false),
          '',
        ); // Remove Season.1-8
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
          '',
        ); // Remove quality
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
          '',
        ); // Remove codec
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
          '',
        ); // Remove source
        cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

        final cleanTitleKey =
            'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Try both variations - PRIORITIZE clean title first (where playback state is actually saved)
        if (playbackStateMap[cleanTitleKey] != null &&
            playbackStateMap[cleanTitleKey]['type'] == 'series') {
          matchingSeriesKey = cleanTitleKey;
          seriesState = playbackStateMap[cleanTitleKey] as Map<String, dynamic>;
        } else if (playbackStateMap[fullTitleKey] != null &&
            playbackStateMap[fullTitleKey]['type'] == 'series') {
          matchingSeriesKey = fullTitleKey;
          seriesState = playbackStateMap[fullTitleKey] as Map<String, dynamic>;
        } else {
          // Fallback: Search through all series entries for a partial match
          for (final entry in playbackStateMap.entries) {
            if (entry.key.startsWith('series_') &&
                entry.value['type'] == 'series') {
              final seriesTitle =
                  (entry.value['title'] as String?)?.toLowerCase() ?? '';
              final itemTitleLower = title.toLowerCase();

              // Check if the series title is contained in the item title or vice versa
              if (itemTitleLower.contains(seriesTitle) ||
                  seriesTitle.contains(cleanedTitle.toLowerCase())) {
                matchingSeriesKey = entry.key;
                seriesState = entry.value as Map<String, dynamic>;
                break;
              }
            }
          }
        }

        if (seriesState != null && matchingSeriesKey != null) {
          debugPrint(
            '📺 Matched series state for "$title" using key: $matchingSeriesKey',
          );

          // Calculate overall series progress (Option 2)
          // Formula: (finished episodes + partial episode progress) / total episodes

          int totalEpisodes =
              (item['fileCount'] as int?) ?? (item['count'] as int?) ?? 0;
          if (totalEpisodes == 0) {
            // Try to count from the playlist item structure
            totalEpisodes = 1; // Fallback to at least 1
          }

          // Count finished episodes from both finishedEpisodes and seasons maps
          // Use a Set to track which episodes are finished to avoid double-counting
          final Set<String> finishedEpisodeKeys = {};
          int finishedEpisodeCount = 0;

          // First, count episodes explicitly marked as finished (TV series)
          final finishedEpisodes =
              seriesState['finishedEpisodes'] as Map<String, dynamic>?;
          if (finishedEpisodes != null) {
            for (final seasonEntry in finishedEpisodes.entries) {
              final seasonKey = seasonEntry.key;
              final seasonFinished = seasonEntry.value as Map<String, dynamic>;
              for (final episodeKey in seasonFinished.keys) {
                final key = '${seasonKey}_$episodeKey';
                finishedEpisodeKeys.add(key);
                finishedEpisodeCount++;
              }
            }
          }

          // Find the most recently played episode (for timestamp and partial progress)
          int latestPosition = 0;
          int latestDuration = 0;
          int latestUpdatedAt = 0;
          String? latestEpisodeKey;

          final seasons = seriesState['seasons'] as Map<String, dynamic>?;
          if (seasons != null) {
            for (final seasonEntry in seasons.entries) {
              final seasonKey = seasonEntry.key;
              final episodes = seasonEntry.value as Map<String, dynamic>;
              for (final episodeEntry in episodes.entries) {
                final episodeKey = episodeEntry.key;
                final episodeData = episodeEntry.value as Map<String, dynamic>;
                final positionMs = episodeData['positionMs'] as int? ?? 0;
                final durationMs = episodeData['durationMs'] as int? ?? 0;
                final updatedAt = episodeData['updatedAt'] as int? ?? 0;

                // Count as finished if >= 95% watched AND not already counted
                final key = '${seasonKey}_$episodeKey';
                if (durationMs > 0 && (positionMs / durationMs) >= 0.95) {
                  if (!finishedEpisodeKeys.contains(key)) {
                    finishedEpisodeKeys.add(key);
                    finishedEpisodeCount++;
                  }
                }

                // Track latest episode for partial progress
                if (updatedAt > latestUpdatedAt) {
                  latestUpdatedAt = updatedAt;
                  latestPosition = positionMs;
                  latestDuration = durationMs;
                  latestEpisodeKey = key;
                }
              }
            }
          }

          // Calculate partial progress from latest episode ONLY if not already counted as finished
          double partialEpisodeProgress = 0.0;
          bool hasPartialProgress = false;
          if (latestDuration > 0 &&
              latestPosition > 0 &&
              latestEpisodeKey != null) {
            partialEpisodeProgress = latestPosition / latestDuration;
            // Only count as partial if < 95% (not already counted as finished)
            if (partialEpisodeProgress < 0.95 &&
                !finishedEpisodeKeys.contains(latestEpisodeKey)) {
              hasPartialProgress = true;
            }
          }

          if (latestUpdatedAt > 0 && totalEpisodes > 0) {
            // Calculate overall series progress
            double totalEpisodesWatched = finishedEpisodeCount.toDouble();
            if (hasPartialProgress) {
              totalEpisodesWatched += partialEpisodeProgress;
            }

            // Create synthetic position/duration representing series progress
            final syntheticDuration =
                totalEpisodes * 1000000; // 1M ms per episode (arbitrary)
            final syntheticPosition = (totalEpisodesWatched * 1000000).toInt();

            progressData = {
              'positionMs': syntheticPosition,
              'durationMs': syntheticDuration,
              'updatedAt': latestUpdatedAt,
            };

            debugPrint(
              'Series "$title": $finishedEpisodeCount finished + ${partialEpisodeProgress.toStringAsFixed(2)} partial = ${totalEpisodesWatched.toStringAsFixed(2)} / $totalEpisodes episodes (${((totalEpisodesWatched / totalEpisodes) * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      }

      if (progressData != null) {
        progressMap[dedupeKey] = progressData;
        debugPrint(
          'StorageService: Found progress for "$title" - ${progressData['positionMs']}ms / ${progressData['durationMs']}ms (${((progressData['positionMs'] / progressData['durationMs']) * 100).toStringAsFixed(1)}%)',
        );
      }
    }

    debugPrint(
      'StorageService: Built progress map with ${progressMap.length} entries',
    );
    return progressMap;
  }

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


  // Tracking source policy -------------------------------------------------

  /// Reads the new master scrobble switches. On first read, adopt the retired
  /// per-tracker catalog switches once. An absent legacy value means ON: that
  /// matches interactive connection and old Trakt/Simkl restore behavior.
  static Future<Set<TrackingSource>> getTrackingScrobbleTargets() =>
      TrackingScrobblePreferences.readCurrent();

  static Future<void> setTrackingScrobbleTargets(
    Set<TrackingSource> value,
  ) async {
    await TrackingScrobblePreferences.writeCurrent(value);
    trackingSourceRevision.value++;
  }

  /// Turns on scrobbling for a newly connected tracker without disturbing the
  /// user's choices for any other tracker. Connection flows call this after
  /// authentication succeeds so reconnecting restores the provider's default
  /// ON state even when it had previously been unticked.
  static Future<void> enableTrackingScrobbleTarget(
    TrackingSource source,
  ) async {
    final changed = await TrackingScrobblePreferences.enableCurrent(source);
    if (changed) trackingSourceRevision.value++;
  }

  static Future<WatchProgressSource> getWatchProgressSource() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getString(watchProgressSourceKey);
    return WatchProgressSource.values.firstWhere(
      (source) => source.name == stored,
      orElse: () => WatchProgressSource.smart,
    );
  }

  static Future<void> setWatchProgressSource(WatchProgressSource value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(watchProgressSourceKey, value.name);
    trackingSourceRevision.value++;
  }

  static Future<bool> fallbackDisconnectedProgressSource(
    TrackingSource disconnected,
  ) async {
    final current = await getWatchProgressSource();
    final owns = switch (current) {
      WatchProgressSource.trakt => disconnected == TrackingSource.trakt,
      WatchProgressSource.simkl => disconnected == TrackingSource.simkl,
      WatchProgressSource.mdblist => disconnected == TrackingSource.mdblist,
      _ => false,
    };
    if (!owns) return false;
    await setWatchProgressSource(WatchProgressSource.smart);
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tracking_progress_fallback_notice', true);
    return true;
  }

  static Future<bool> takeTrackingProgressFallbackNotice() async {
    final prefs = await ProfilePreferences.instance();
    final pending = prefs.getBool('tracking_progress_fallback_notice') ?? false;
    if (pending) await prefs.remove('tracking_progress_fallback_notice');
    return pending;
  }

  static Future<Set<TrackingSource>> getHomeTickSources() =>
      HomePrefs.getHomeTickSources();

  static Future<void> setHomeTickSources(Set<TrackingSource> value) async {
    await HomePrefs.setHomeTickSources(value);
    trackingSourceRevision.value++;
  }

  static Future<Map<String, dynamic>> buildTrackingPreferencesPayload() async {
    final scrobble = await getTrackingScrobbleTargets();
    final progress = await getWatchProgressSource();
    final ticks = await getHomeTickSources();
    return <String, dynamic>{
      'scrobble_targets': scrobble
          .map((source) => source.storageName)
          .toList(growable: false),
      'progress_source': progress.name,
      'home_tick_sources': ticks
          .map((source) => source.storageName)
          .toList(growable: false),
      'hide_watched': await HideWatchedPrefs.read(),
    };
  }

  /// Re-adopts the legacy per-tracker switches after restoring an OLD backup
  /// with no tracking payload. The masters were already seeded on first policy
  /// read at app start, so without this the restored legacy values — notably an
  /// MDBList sync-catalog OFF — would be silently ignored.
  static Future<void> reseedTrackingScrobbleTargetsFromLegacy() async {
    await TrackingScrobblePreferences.reseedCurrentFromLegacy();
    trackingSourceRevision.value++;
  }

  /// Applies only explicitly present new-format preferences. Old backups omit
  /// this object; [reseedTrackingScrobbleTargetsFromLegacy] runs on that
  /// restore path instead so the restored legacy switches are re-adopted by
  /// [getTrackingScrobbleTargets], preserving the absent-key migration rule.
  static Future<void> applyTrackingPreferencesPayload(
    Map<dynamic, dynamic> payload,
  ) async {
    final scrobble = payload['scrobble_targets'];
    if (scrobble is List) {
      await setTrackingScrobbleTargets(<TrackingSource>{
        for (final value in scrobble.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final progress = payload['progress_source'];
    if (progress is String) {
      final parsed = WatchProgressSource.values
          .where((source) => source.name == progress)
          .firstOrNull;
      if (parsed != null) await setWatchProgressSource(parsed);
    }
    final ticks = payload['home_tick_sources'];
    if (ticks is List) {
      await setHomeTickSources(<TrackingSource>{
        for (final value in ticks.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final hideWatched = payload['hide_watched'];
    if (hideWatched is bool) await HideWatchedPrefs.setEnabled(hideWatched);
  }

  static Future<String?> getRedditLastSubreddit() =>
      SocialPrefs.getRedditLastSubreddit();

  static Future<void> setRedditLastSubreddit(String subreddit) =>
      SocialPrefs.setRedditLastSubreddit(subreddit);

  static Future<void> clearRedditAuth() => SocialPrefs.clearRedditAuth();


  // Trakt Settings
  static Future<bool> getTraktSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('trakt_sync_catalog_items') ?? false;
  }

  static Future<void> setTraktSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('trakt_sync_catalog_items', value);
  }

  static Future<String?> getTraktAccessToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _traktAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _traktAccessTokenKey);
  }

  static Future<bool> hasTraktCredential() =>
      _credentialConfigured(_traktAccessTokenKey, () => getTraktAccessToken());

  static Future<void> setTraktAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _traktAccessTokenKey, token);
  }

  static Future<String?> getTraktRefreshToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _traktRefreshTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _traktRefreshTokenKey);
  }

  static Future<void> setTraktRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _traktRefreshTokenKey, token);
  }

  static Future<String?> getTraktUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_traktUsernameKey);
  }

  static Future<void> setTraktUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_traktUsernameKey, username);
  }

  static Future<int?> getTraktTokenExpiry() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_traktTokenExpiryKey);
  }

  static Future<void> setTraktTokenExpiry(int expiryMs) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_traktTokenExpiryKey, expiryMs);
  }

  /// Clears the local Trakt connection first and reports whether this profile
  /// was its unshared owner. Only that disposition may revoke the upstream
  /// token; a borrower must never invalidate the account for other profiles.
  static Future<bool> clearTraktAuth() async {
    final prefs = await ProfilePreferences.instance();
    final disposition = await ProfileCredentialFacade.disconnectWithDisposition(
      _traktAccessTokenKey,
    );
    if (!disposition.handled) {
      await prefs.remove(_traktAccessTokenKey);
      await prefs.remove(_traktRefreshTokenKey);
    }
    await prefs.remove(_traktUsernameKey);
    await prefs.remove(_traktTokenExpiryKey);
    await fallbackDisconnectedProgressSource(TrackingSource.trakt);
    return !disposition.handled || disposition.shouldRevokeRemote;
  }

  static Future<void> setSimklSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('simkl_sync_catalog_items', value);
  }

  static Future<bool> getSimklSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('simkl_sync_catalog_items') ?? false;
  }

  static Future<void> setMdblistSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('mdblist_sync_catalog_items', value);
  }

  static Future<bool> getMdblistSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('mdblist_sync_catalog_items') ?? false;
  }

  static Future<String?> getSimklAccessToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _simklAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _simklAccessTokenKey);
  }

  static Future<bool> hasSimklCredential() =>
      _credentialConfigured(_simklAccessTokenKey, () => getSimklAccessToken());

  static Future<void> setSimklAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _simklAccessTokenKey, token);
  }

  static Future<String?> getSimklUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_simklUsernameKey);
  }

  static Future<void> setSimklUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_simklUsernameKey, username);
  }

  static Future<void> clearSimklAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_simklAccessTokenKey)) {
      await prefs.remove(_simklAccessTokenKey);
    }
    await prefs.remove(_simklUsernameKey);
    await fallbackDisconnectedProgressSource(TrackingSource.simkl);
  }

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

  static Future<void> setIptvDecoderMode(String value) =>
      IptvPrefs.setIptvDecoderMode(value);

  // Network tuning (Debrify player) — forwarding façade; bodies live on PlayerPrefs.
  static Future<String> getNetworkConnectPatience() =>
      PlayerPrefs.getNetworkConnectPatience();

  static Future<void> setNetworkConnectPatience(String value) =>
      PlayerPrefs.setNetworkConnectPatience(value);

  static Future<String> getNetworkBufferSize() =>
      PlayerPrefs.getNetworkBufferSize();

  static Future<void> setNetworkBufferSize(String value) =>
      PlayerPrefs.setNetworkBufferSize(value);

  static int _normalizeLocalCompletionThreshold(int value) {
    return localCompletionThresholdOptions.contains(value)
        ? value
        : defaultLocalCompletionThreshold;
  }

  /// Percentage of a movie that must be watched before the local player marks
  /// it complete. Tracker-backed sessions retain Trakt/Simkl's own semantics.
  static Future<int> getMovieCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_movieCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setMovieCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _movieCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Percentage of an episode that must be watched before the local player
  /// marks it complete. Kept separate from movies because users commonly want
  /// a different rule for episode credits.
  static Future<int> getEpisodeCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_episodeCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setEpisodeCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _episodeCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

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
  static void rearmGhostPurgeForImportedPlayback(
    Map<String, Object?> preferences,
  ) {
    if (!preferences.containsKey(_playbackStateKey)) return;
    if (preferences.containsKey(_resumeGhostPurgeGenerationKey)) return;
    preferences[_resumeGhostPurgeGenerationKey] = 0;
  }

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
  static Future<void> purgeUnwatchedResumeGhosts() async {
    final prefs = await ProfilePreferences.instance();
    final generation = prefs.getInt(_resumeGhostPurgeGenerationKey) ?? 0;
    if (generation >= _currentResumeGhostPurgeGeneration) return;

    final playback = await _getPlaybackStateMap();
    var purged = 0;

    for (final stateEntry in playback.values) {
      if (stateEntry is! Map<String, dynamic> ||
          stateEntry['type'] != 'series') {
        continue;
      }
      final seasons = stateEntry['seasons'];
      if (seasons is! Map) continue;
      final finishedEpisodes = stateEntry['finishedEpisodes'];

      for (final seasonKey in seasons.keys.toList()) {
        final episodes = seasons[seasonKey];
        if (episodes is! Map) continue;
        final seasonFinished = finishedEpisodes is Map
            ? finishedEpisodes[seasonKey]
            : null;

        for (final episodeKey in episodes.keys.toList()) {
          final episodeData = episodes[episodeKey];
          if (episodeData is! Map) continue;
          if (seasonFinished is Map && seasonFinished.containsKey(episodeKey)) {
            continue;
          }
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          // durationMs > 1 skips the mark-only dummy shape, which is already
          // excluded above whenever its completion record survived.
          if (positionMs == 0 && durationMs > 1) {
            episodes.remove(episodeKey);
            purged++;
          }
        }
        if (episodes.isEmpty) seasons.remove(seasonKey);
      }
    }

    if (purged > 0) {
      await _savePlaybackStateMap(playback);
      localCompletionRevision.value++;
      debugPrint(
        'StorageService: purged $purged unwatched resume ghost(s) from playback state',
      );
    }
    await prefs.setInt(
      _resumeGhostPurgeGenerationKey,
      _currentResumeGhostPurgeGeneration,
    );
  }

  /// One-time, per-profile adoption of the local completion thresholds for
  /// playback recorded before threshold-based watched status existed.
  ///
  /// Movies at/above their threshold become locally finished and leave local
  /// Continue Watching. Series episodes at/above their threshold are folded
  /// into the existing `finishedEpisodes` structure used by episode ticks.
  /// Tracker data is deliberately untouched; this migration only rewrites the
  /// app's local playback state.
  static Future<void> migrateExistingPlaybackCompletionThresholds() async {
    final prefs = await ProfilePreferences.instance();
    final generation =
        prefs.getInt(_playbackCompletionMigrationGenerationKey) ?? 0;
    if (generation >= _currentPlaybackCompletionMigrationGeneration) return;

    final movieThreshold = await getMovieCompletionThreshold();
    final episodeThreshold = await getEpisodeCompletionThreshold();
    final playback = await _getPlaybackStateMap();
    final completedMovieIds = await _getFinishedMovieIds();
    final newlyCompletedMovieIds = <String>{};
    final completedMovieStateKeys = <String>{};
    final completedMovieResumeKeys = <String>{};
    var completedEpisodeCount = 0;
    var playbackChanged = false;

    for (final stateEntry in playback.entries) {
      final rawState = stateEntry.value;
      if (rawState is! Map<String, dynamic>) continue;

      if (rawState['type'] == 'video') {
        final imdbId = (rawState['imdbId'] as String?)?.trim().toLowerCase();
        final positionMs = (rawState['positionMs'] as num?)?.toInt() ?? 0;
        final durationMs = (rawState['durationMs'] as num?)?.toInt() ?? 0;
        if (imdbId == null ||
            imdbId.isEmpty ||
            durationMs <= 0 ||
            positionMs <= 0 ||
            positionMs * 100.0 / durationMs < movieThreshold) {
          continue;
        }
        completedMovieIds.add(imdbId);
        newlyCompletedMovieIds.add(imdbId);
        continue;
      }

      if (rawState['type'] != 'series') continue;
      final seasons = rawState['seasons'];
      if (seasons is! Map<String, dynamic>) continue;
      final finishedEpisodes = rawState['finishedEpisodes'] is Map
          ? Map<String, dynamic>.from(rawState['finishedEpisodes'] as Map)
          : <String, dynamic>{};

      for (final seasonEntry in seasons.entries) {
        final episodesRaw = seasonEntry.value;
        if (episodesRaw is! Map) continue;
        final seasonFinished = finishedEpisodes[seasonEntry.key] is Map
            ? Map<String, dynamic>.from(
                finishedEpisodes[seasonEntry.key] as Map,
              )
            : <String, dynamic>{};

        for (final episodeEntry in episodesRaw.entries) {
          if (episodeEntry.value is! Map) continue;
          final episodeData = Map<String, dynamic>.from(
            episodeEntry.value as Map,
          );
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          if (durationMs <= 0 ||
              positionMs <= 0 ||
              positionMs * 100.0 / durationMs < episodeThreshold ||
              seasonFinished.containsKey(episodeEntry.key)) {
            continue;
          }

          seasonFinished[episodeEntry.key.toString()] = {
            'finishedAt':
                (episodeData['updatedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          };
          // Keep the episode's historical updatedAt so migration does not
          // reorder a show's "last played" episode.
          episodeData['positionMs'] = durationMs;
          episodesRaw[episodeEntry.key] = episodeData;
          completedEpisodeCount++;
          playbackChanged = true;
        }

        if (seasonFinished.isNotEmpty) {
          finishedEpisodes[seasonEntry.key] = seasonFinished;
        }
      }
      rawState['finishedEpisodes'] = finishedEpisodes;
    }

    if (newlyCompletedMovieIds.isNotEmpty) {
      for (final stateEntry in playback.entries) {
        final state = stateEntry.value;
        if (state is! Map<String, dynamic> || state['type'] != 'video') {
          continue;
        }
        final imdbId = (state['imdbId'] as String?)?.trim().toLowerCase();
        if (imdbId != null && newlyCompletedMovieIds.contains(imdbId)) {
          completedMovieStateKeys.add(stateEntry.key);
          final resumeKey = (state['title'] as String?)?.trim();
          if (resumeKey != null && resumeKey.isNotEmpty) {
            completedMovieResumeKeys.add(resumeKey);
          }
        }
      }
      playback.removeWhere((key, _) => completedMovieStateKeys.contains(key));
      playbackChanged = true;
      await prefs.setStringList(
        _finishedMoviesKey,
        completedMovieIds.toList()..sort(),
      );
      localCompletionRevision.value++;

      final rawContinueWatching = prefs.getString(_continueWatchingKey);
      if (rawContinueWatching != null && rawContinueWatching.isNotEmpty) {
        try {
          final decoded = await decodeJsonAsync(rawContinueWatching);
          if (decoded is List) {
            final items = decoded
                .whereType<Map<String, dynamic>>()
                .map(Map<String, dynamic>.from)
                .where((item) {
                  final imdbId = (item['imdbId'] as String?)
                      ?.trim()
                      .toLowerCase();
                  return imdbId == null ||
                      !newlyCompletedMovieIds.contains(imdbId);
                })
                .toList();
            await prefs.setString(_continueWatchingKey, jsonEncode(items));
          }
        } catch (_) {
          // Leave malformed legacy data untouched; the normal CW reader also
          // treats it as empty, and completion migration can still succeed.
        }
      }
    }

    // The older player resume store uses the playback state's title as its
    // key. Clear it as part of the same migration so a later rewatch cannot
    // resurrect a near-credits position after the enhanced state is removed.
    // Do this before saving the removal so a database failure leaves enough
    // playback metadata for the next startup to retry the cleanup.
    for (final resumeKey in completedMovieResumeKeys) {
      await removeVideoResume(resumeKey);
    }
    if (playbackChanged) await _savePlaybackStateMap(playback);
    await prefs.setInt(
      _playbackCompletionMigrationGenerationKey,
      _currentPlaybackCompletionMigrationGeneration,
    );
    debugPrint(
      'StorageService: completion migration marked '
      '${newlyCompletedMovieIds.length} movies and '
      '$completedEpisodeCount episodes watched',
    );
  }

  // PikPak API Settings
  static Future<bool> getPikPakEnabled() =>
      ProviderCredentialPrefs.getPikPakEnabled();

  static Future<void> setPikPakEnabled(bool value) =>
      ProviderCredentialPrefs.setPikPakEnabled(value);

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

  static Future<String?> getPikPakAccessToken() =>
      ProviderCredentialPrefs.getPikPakAccessToken();

  static Future<void> setPikPakAccessToken(String token) =>
      ProviderCredentialPrefs.setPikPakAccessToken(token);

  static Future<String?> getPikPakRefreshToken() =>
      ProviderCredentialPrefs.getPikPakRefreshToken();

  static Future<void> setPikPakRefreshToken(String token) =>
      ProviderCredentialPrefs.setPikPakRefreshToken(token);

  static Future<void> clearPikPakAuth() =>
      ProviderCredentialPrefs.clearPikPakAuth();

  // PikPak Device ID and Captcha Token
  static Future<void> setPikPakDeviceId(String deviceId) =>
      ProviderCredentialPrefs.setPikPakDeviceId(deviceId);

  static Future<String?> getPikPakDeviceId() =>
      ProviderCredentialPrefs.getPikPakDeviceId();

  static Future<void> deletePikPakDeviceId() =>
      ProviderCredentialPrefs.deletePikPakDeviceId();

  static Future<void> setPikPakCaptchaToken(String token) =>
      ProviderCredentialPrefs.setPikPakCaptchaToken(token);

  static Future<String?> getPikPakCaptchaToken() =>
      ProviderCredentialPrefs.getPikPakCaptchaToken();

  static Future<void> clearPikPakCaptchaToken() =>
      ProviderCredentialPrefs.clearPikPakCaptchaToken();

  static Future<void> setPikPakUserId(String userId) =>
      ProviderCredentialPrefs.setPikPakUserId(userId);

  static Future<String?> getPikPakUserId() =>
      ProviderCredentialPrefs.getPikPakUserId();

  // PikPak Show Videos Only
  static Future<bool> getPikPakShowVideosOnly() =>
      ProviderCredentialPrefs.getPikPakShowVideosOnly();

  static Future<void> setPikPakShowVideosOnly(bool value) =>
      ProviderCredentialPrefs.setPikPakShowVideosOnly(value);

  // PikPak Ignore Small Videos (under 100MB)
  static Future<bool> getPikPakIgnoreSmallVideos() =>
      ProviderCredentialPrefs.getPikPakIgnoreSmallVideos();

  static Future<void> setPikPakIgnoreSmallVideos(bool value) =>
      ProviderCredentialPrefs.setPikPakIgnoreSmallVideos(value);

  // PikPak Restricted Folder
  static Future<String?> getPikPakRestrictedFolderId() =>
      ProviderCredentialPrefs.getPikPakRestrictedFolderId();

  static Future<String?> getPikPakRestrictedFolderName() =>
      ProviderCredentialPrefs.getPikPakRestrictedFolderName();

  static Future<void> setPikPakRestrictedFolder(
    String? folderId,
    String? folderName,
  ) => ProviderCredentialPrefs.setPikPakRestrictedFolder(folderId, folderName);

  static Future<void> clearPikPakRestrictedFolder() =>
      ProviderCredentialPrefs.clearPikPakRestrictedFolder();

  // PikPak Subfolder ID caching (for debrify-torrents and debrify-tv folders)
  static Future<String?> getPikPakTorrentsFolderId() =>
      ProviderCredentialPrefs.getPikPakTorrentsFolderId();

  static Future<void> setPikPakTorrentsFolderId(String folderId) =>
      ProviderCredentialPrefs.setPikPakTorrentsFolderId(folderId);

  static Future<String?> getPikPakTvFolderId() =>
      ProviderCredentialPrefs.getPikPakTvFolderId();

  static Future<void> setPikPakTvFolderId(String folderId) =>
      ProviderCredentialPrefs.setPikPakTvFolderId(folderId);

  static Future<void> clearPikPakSubfolderCaches() =>
      ProviderCredentialPrefs.clearPikPakSubfolderCaches();

  // PikPak Hidden from Navigation
  static Future<bool> getPikPakHiddenFromNav() =>
      ProviderCredentialPrefs.getPikPakHiddenFromNav();

  static Future<void> setPikPakHiddenFromNav(bool hidden) =>
      ProviderCredentialPrefs.setPikPakHiddenFromNav(hidden);

  static Future<void> clearPikPakHiddenFromNav() =>
      ProviderCredentialPrefs.clearPikPakHiddenFromNav();

  // WebDAV Settings
  static Future<bool> getWebDavEnabled() =>
      ProviderCredentialPrefs.getWebDavEnabled();

  static Future<void> setWebDavEnabled(bool value) =>
      ProviderCredentialPrefs.setWebDavEnabled(value);

  static Future<bool> getWebDavHiddenFromNav() =>
      ProviderCredentialPrefs.getWebDavHiddenFromNav();

  static Future<void> setWebDavHiddenFromNav(bool hidden) =>
      ProviderCredentialPrefs.setWebDavHiddenFromNav(hidden);

  static Future<void> clearWebDavHiddenFromNav() =>
      ProviderCredentialPrefs.clearWebDavHiddenFromNav();

  static Future<String?> getWebDavBaseUrl() =>
      ProviderCredentialPrefs.getWebDavBaseUrl();

  static Future<void> setWebDavBaseUrl(String value) =>
      ProviderCredentialPrefs.setWebDavBaseUrl(value);

  static Future<String?> getWebDavUsername() =>
      ProviderCredentialPrefs.getWebDavUsername();

  static Future<void> setWebDavUsername(String value) =>
      ProviderCredentialPrefs.setWebDavUsername(value);

  static Future<String?> getWebDavPassword() =>
      ProviderCredentialPrefs.getWebDavPassword();

  static Future<void> setWebDavPassword(String value) =>
      ProviderCredentialPrefs.setWebDavPassword(value);

  static Future<bool> getWebDavShowVideosOnly() =>
      ProviderCredentialPrefs.getWebDavShowVideosOnly();

  static Future<void> setWebDavShowVideosOnly(bool value) =>
      ProviderCredentialPrefs.setWebDavShowVideosOnly(value);

  static Future<void> clearWebDav() => ProviderCredentialPrefs.clearWebDav();

  static Future<List<WebDavConfig>> getWebDavServers({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) => ProviderCredentialPrefs.getWebDavServers(
    forSettings: forSettings,
    forRemoteTransfer: forRemoteTransfer,
  );

  static Future<List<WebDavConfig>> saveWebDavServers(
    List<WebDavConfig> servers,
  ) => ProviderCredentialPrefs.saveWebDavServers(servers);

  static Future<String?> getSelectedWebDavServerId() =>
      ProviderCredentialPrefs.getSelectedWebDavServerId();

  static Future<void> setSelectedWebDavServerId(String? id) =>
      ProviderCredentialPrefs.setSelectedWebDavServerId(id);

  static Future<WebDavConfig?> getSelectedWebDavServer({
    bool forSettings = true,
  }) => ProviderCredentialPrefs.getSelectedWebDavServer(
    forSettings: forSettings,
  );

  static Future<WebDavConfig> upsertWebDavServer(WebDavConfig config) =>
      ProviderCredentialPrefs.upsertWebDavServer(config);

  static Future<void> deleteWebDavServer(String id) =>
      ProviderCredentialPrefs.deleteWebDavServer(id);

  // TVMaze Series Mapping Methods

  /// Get a unique key for a playlist item based on available identifiers
  static String _getPlaylistItemUniqueKey(Map<String, dynamic> playlistItem) {
    final provider = ((playlistItem['provider'] as String?) ?? 'realdebrid')
        .toLowerCase();

    if (provider == 'webdav') {
      return computePlaylistDedupeKey(playlistItem);
    }

    // Try different identifiers in order of preference
    if (playlistItem['rdTorrentId'] != null) {
      return 'rd_${playlistItem['rdTorrentId']}';
    }
    if (playlistItem['torrent_hash'] != null) {
      return 'hash_${playlistItem['torrent_hash']}';
    }
    if (playlistItem['torboxTorrentId'] != null) {
      return 'torbox_${playlistItem['torboxTorrentId']}';
    }
    if (playlistItem['pikpakFileId'] != null) {
      return 'pikpak_${playlistItem['pikpakFileId']}';
    }
    // Fallback to title if nothing else is available
    final title =
        (playlistItem['title'] as String?)?.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '_',
        ) ??
        'unknown';
    return 'title_$title';
  }

  /// Save a TVMaze series mapping for a playlist item
  static Future<void> saveTVMazeSeriesMapping({
    required Map<String, dynamic> playlistItem,
    required int tvmazeShowId,
    required String showName,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    Map<String, dynamic> mappings = {};
    if (mappingsJson != null) {
      try {
        mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing TVMaze series mappings: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    mappings[key] = {
      'tvmazeShowId': tvmazeShowId,
      'showName': showName,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
    debugPrint(
      '✅ Saved TVMaze mapping for $key -> Show ID: $tvmazeShowId ($showName)',
    );
  }

  /// Get TVMaze series mapping for a playlist item
  static Future<Map<String, dynamic>?> getTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return null;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
      final mapping = mappings[key];

      if (mapping != null && mapping is Map<String, dynamic>) {
        debugPrint(
          '✅ Found TVMaze mapping for $key -> Show ID: ${mapping['tvmazeShowId']} (${mapping['showName']})',
        );
        return mapping;
      }
    } catch (e) {
      debugPrint('Error reading TVMaze series mappings: $e');
    }

    return null;
  }

  /// Clear TVMaze series mapping for a playlist item
  static Future<void> clearTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (mappings.containsKey(key)) {
        mappings.remove(key);
        await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
        debugPrint('✅ Cleared TVMaze mapping for $key');
      }
    } catch (e) {
      debugPrint('Error clearing TVMaze series mapping: $e');
    }
  }

  /// Clear all TVMaze series mappings
  static Future<void> clearAllTVMazeSeriesMappings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_tvMazeSeriesMappingKey);
    debugPrint('✅ Cleared all TVMaze series mappings');
  }

  // Playlist Poster Override Methods

  /// Save a poster URL override for a playlist item
  /// This ensures the poster persists across app restarts
  static Future<void> savePlaylistPosterOverride({
    required Map<String, dynamic> playlistItem,
    required String posterUrl,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    Map<String, dynamic> overrides = {};
    if (overridesJson != null) {
      try {
        overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist poster overrides: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    overrides[key] = {
      'posterUrl': posterUrl,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_playlistPosterOverridesKey, jsonEncode(overrides));
    debugPrint('✅ Saved poster override for $key -> $posterUrl');
  }

  /// Get poster URL override for a playlist item
  /// Returns null if no override exists
  static Future<String?> getPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return null;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
      final override = overrides[key];

      if (override != null && override is Map<String, dynamic>) {
        final posterUrl = override['posterUrl'] as String?;
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return posterUrl;
        }
      }
    } catch (e) {
      debugPrint('Error reading playlist poster override: $e');
    }

    return null;
  }

  /// Get all poster overrides as a map of item unique key → poster URL.
  /// Reads and parses the overrides blob once for batch lookups.
  static Future<Map<String, String>> getAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);
    if (overridesJson == null) return {};

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final result = <String, String>{};
      for (final entry in overrides.entries) {
        if (entry.value is Map<String, dynamic>) {
          final posterUrl =
              (entry.value as Map<String, dynamic>)['posterUrl'] as String?;
          if (posterUrl != null && posterUrl.isNotEmpty) {
            result[entry.key] = posterUrl;
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading playlist poster overrides: $e');
      return {};
    }
  }

  /// Get the unique key for a playlist item (public accessor for batch lookups)
  static String getPlaylistItemUniqueKey(Map<String, dynamic> item) =>
      _getPlaylistItemUniqueKey(item);

  /// Clear poster URL override for a playlist item
  static Future<void> clearPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (overrides.containsKey(key)) {
        overrides.remove(key);
        await prefs.setString(
          _playlistPosterOverridesKey,
          jsonEncode(overrides),
        );
        debugPrint('✅ Cleared poster override for $key');
      }
    } catch (e) {
      debugPrint('Error clearing playlist poster override: $e');
    }
  }

  /// Clear all playlist poster overrides
  static Future<void> clearAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_playlistPosterOverridesKey);
    debugPrint('✅ Cleared all playlist poster overrides');
  }

  // ============================================================================
  // Torrent Search History Methods
  // ============================================================================

  /// Get torrent search history
  /// Returns list of maps containing torrent JSON + service + timestamp
  static Future<List<Map<String, dynamic>>> getTorrentSearchHistory() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_torrentSearchHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error loading torrent search history: $e');
      return [];
    }
  }

  /// Add torrent to search history with deduplication
  /// Deduplicates by infohash, keeps max 5 items (FIFO)
  static Future<void> addTorrentToHistory(
    Map<String, dynamic> torrentJson,
    String service,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final history = await getTorrentSearchHistory();

    final infohash = torrentJson['infohash'] as String?;
    if (infohash == null || infohash.isEmpty) return;

    // Remove existing entry with same infohash (deduplicate)
    history.removeWhere((entry) {
      final entryTorrent = entry['torrent'] as Map<String, dynamic>?;
      return entryTorrent?['infohash'] == infohash;
    });

    // Add new entry at start
    history.insert(0, {
      'torrent': torrentJson,
      'service': service,
      'clickedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep only last 5
    if (history.length > 5) {
      history.removeRange(5, history.length);
    }

    await prefs.setString(_torrentSearchHistoryKey, jsonEncode(history));
  }

  /// Clear all search history
  static Future<void> clearTorrentSearchHistory() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_torrentSearchHistoryKey);
  }

  /// Get whether search history tracking is enabled
  static Future<bool> getTorrentSearchHistoryEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torrentSearchHistoryEnabledKey) ?? true;
  }

  /// Set whether search history tracking is enabled
  static Future<void> setTorrentSearchHistoryEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torrentSearchHistoryEnabledKey, enabled);
  }

  /// Whether quick-play ranks candidates by the default filters (the
  /// FilterLadder). ON by default — the ladder only reorders, never drops.
  static Future<bool> getQuickPlayHonorsFilters() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayHonorsFiltersKey) ?? true;
  }

  /// Legacy global preference retained for migration and profile-less callers.
  /// The Quick Play page owns the independent Movie and Series `useFilters`
  /// values; a global write must never silently rewrite either profile.
  static Future<void> setQuickPlayHonorsFilters(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayHonorsFiltersKey, value);
  }

  // Default Torrent Filter Settings
  static Future<List<String>> getDefaultFilterQualities() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterQualities(List<String> qualities) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDefaultFilterRipSources() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterRipSourcesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterRipSources(
    List<String> ripSources,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterRipSourcesKey, jsonEncode(ripSources));
  }

  static Future<List<String>> getDefaultFilterLanguages() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterLanguagesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterLanguages(List<String> languages) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterLanguagesKey, jsonEncode(languages));
  }

  static Future<List<String>> getDefaultFilterSizes() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterSizesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterSizes(List<String> sizes) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterSizesKey, jsonEncode(sizes));
  }

  static Future<List<String>> getDefaultFilterDynamicRanges() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterDynamicRangesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterDynamicRanges(List<String> ranges) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterDynamicRangesKey, jsonEncode(ranges));
  }

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
  static Future<String> getDefaultTorrentProvider() =>
      ProviderCredentialPrefs.getDefaultTorrentProvider();

  static Future<void> setDefaultTorrentProvider(String provider) =>
      ProviderCredentialPrefs.setDefaultTorrentProvider(provider);

  static Future<void> clearDefaultTorrentProvider() =>
      ProviderCredentialPrefs.clearDefaultTorrentProvider();

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
  static Future<String> getQuickPlayVrMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_quickPlayVrModeKey) ?? 'disabled';
  }

  static Future<void> setQuickPlayVrMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_quickPlayVrModeKey, mode);
  }

  /// Get default VR screen type (dome, sphere, flat, fisheye, mkx200, rf52)
  static Future<String> getQuickPlayVrDefaultScreenType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_quickPlayVrDefaultScreenTypeKey) ?? 'dome';
  }

  static Future<void> setQuickPlayVrDefaultScreenType(String screenType) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_quickPlayVrDefaultScreenTypeKey, screenType);
  }

  /// Get default VR stereo mode (sbs, tb, off)
  static Future<String> getQuickPlayVrDefaultStereoMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_quickPlayVrDefaultStereoModeKey) ?? 'sbs';
  }

  static Future<void> setQuickPlayVrDefaultStereoMode(String stereoMode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_quickPlayVrDefaultStereoModeKey, stereoMode);
  }

  /// Get whether to auto-detect VR format from filename
  static Future<bool> getQuickPlayVrAutoDetectFormat() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayVrAutoDetectFormatKey) ?? true;
  }

  static Future<void> setQuickPlayVrAutoDetectFormat(bool autoDetect) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayVrAutoDetectFormatKey, autoDetect);
  }

  /// Get whether to show VR format selection dialog before launching DeoVR
  static Future<bool> getQuickPlayVrShowDialog() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayVrShowDialogKey) ?? true;
  }

  static Future<void> setQuickPlayVrShowDialog(bool showDialog) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayVrShowDialogKey, showDialog);
  }

  /// Clear all Quick Play VR settings
  static Future<void> clearQuickPlayVrSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_quickPlayVrModeKey);
    await prefs.remove(_quickPlayVrDefaultScreenTypeKey);
    await prefs.remove(_quickPlayVrDefaultStereoModeKey);
    await prefs.remove(_quickPlayVrAutoDetectFormatKey);
    await prefs.remove(_quickPlayVrShowDialogKey);
  }

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
  static Future<String> getPlayButtonMode() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playButtonModeKey);
    return (raw == 'smart' || raw == 'always') ? raw! : 'quick';
  }

  static Future<void> setPlayButtonMode(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playButtonModeKey, value);
  }

  /// Loads the per-content Quick Play profile. When no v2 profile exists,
  /// legacy filter/retry/series-pack preferences are folded into one without
  /// changing what the next play will do. Non-default legacy values are
  /// labelled Custom; an untouched install is Debrify default.
  static Future<QuickPlayRules> getQuickPlayRules({
    required bool isMovie,
  }) async {
    final prefs = await ProfilePreferences.instance();
    return _quickPlayRulesFromPrefs(prefs, isMovie: isMovie);
  }

  static QuickPlayRules _quickPlayRulesFromPrefs(
    SharedPreferences prefs, {
    required bool isMovie,
  }) {
    final key = isMovie ? _quickPlayMovieRulesKey : _quickPlaySeriesRulesKey;
    final stored = prefs.getString(key);
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is Map<String, dynamic>) {
          return QuickPlayRules.fromJson(decoded, isMovie: isMovie);
        }
        if (decoded is Map) {
          return QuickPlayRules.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
            isMovie: isMovie,
          );
        }
      } catch (e) {
        debugPrint('Invalid Quick Play profile, using legacy values: $e');
      }
    }

    final defaults = QuickPlayRules.debrifyDefault(isMovie: isMovie);
    final migrated = defaults.copyWith(
      preset: QuickPlayPreset.debrifyDefault,
      useFilters: prefs.getBool(_quickPlayHonorsFiltersKey) ?? true,
      tryNextOnFailure: prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? true,
      maxAttempts: prefs.getInt(_quickPlayMaxRetriesKey) ?? 5,
      preferSeriesPacks:
          !isMovie && (prefs.getBool(_autoBindSeriesPacksKey) ?? true),
    );
    return migrated == defaults
        ? migrated
        : migrated.copyWith(preset: QuickPlayPreset.custom);
  }

  static Future<void> setQuickPlayRules(
    QuickPlayRules rules, {
    required bool isMovie,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final siblingIsMovie = !isMovie;
    final siblingKey = siblingIsMovie
        ? _quickPlayMovieRulesKey
        : _quickPlaySeriesRulesKey;
    // Snapshot an as-yet-unpersisted sibling BEFORE updating the legacy global
    // mirrors below. Otherwise saving Movies first could make a later Series
    // migration inherit the movie retry count (and vice versa).
    final sibling = prefs.containsKey(siblingKey)
        ? null
        : _quickPlayRulesFromPrefs(prefs, isMovie: siblingIsMovie);
    await prefs.setString(
      isMovie ? _quickPlayMovieRulesKey : _quickPlaySeriesRulesKey,
      jsonEncode(rules.toJson()),
    );
    if (sibling != null) {
      await prefs.setString(siblingKey, jsonEncode(sibling.toJson()));
    }

    // Keep old readers and downgrade builds safe. Media-specific values can't
    // be represented perfectly by the legacy global keys, so the active v2
    // playback path never reads these; they are compatibility mirrors only.
    //
    // That invariant was violated once: series auto-pinning read
    // _autoBindSeriesPacksKey, so writing this mirror turned pinning off
    // whenever the user turned off "Prefer season packs". Auto-pin now owns
    // _seriesAutoPinOnPlayKey. Before adding a reader for any key below, check
    // it is genuinely write-only on this path.
    await prefs.setBool(
      _quickPlayTryMultipleTorrentsKey,
      rules.tryNextOnFailure,
    );
    await prefs.setInt(_quickPlayMaxRetriesKey, rules.maxAttempts);
    if (!isMovie) {
      await prefs.setBool(_autoBindSeriesPacksKey, rules.preferSeriesPacks);
    }
  }

  static Future<void> restoreQuickPlayDefaults() async {
    await setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true),
      isMovie: true,
    );
    await setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: false),
      isMovie: false,
    );
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayHonorsFiltersKey, true);
    // The page's reset button reads as "reset this page", and this function
    // already resets a non-per-tab key above, so the Play button mode goes back
    // to the shipped Quick Play too. Leaving it would restore defaults while
    // Play kept behaving differently.
    await prefs.remove(_playButtonModeKey);
  }

  /// Get whether to try multiple torrents if first is not cached
  /// Default: true (try next torrent on failure)
  static Future<bool> getQuickPlayTryMultipleTorrents() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? true;
  }

  static Future<void> setQuickPlayTryMultipleTorrents(bool tryMultiple) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayTryMultipleTorrentsKey, tryMultiple);
  }

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
  static Future<int> getQuickPlayMaxRetries() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_quickPlayMaxRetriesKey) ?? 5;
  }

  static Future<void> setQuickPlayMaxRetries(int maxRetries) async {
    final prefs = await ProfilePreferences.instance();
    // Clamp between 2 and 10
    await prefs.setInt(_quickPlayMaxRetriesKey, maxRetries.clamp(2, 10));
  }

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
  static Future<void> clearQuickPlayCacheFallbackSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_quickPlayTryMultipleTorrentsKey);
    await prefs.remove(_quickPlayMaxRetriesKey);
    await prefs.remove(_quickPlayMovieRulesKey);
    await prefs.remove(_quickPlaySeriesRulesKey);
  }

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

  static Future<String?> getIptvSeriesAudioLanguage(String seriesKey) =>
      IptvPrefs.getIptvSeriesAudioLanguage(seriesKey);

  static Future<void> setIptvSeriesAudioLanguage(
    String seriesKey,
    String languageCode,
  ) => IptvPrefs.setIptvSeriesAudioLanguage(seriesKey, languageCode);

  static Future<List<IptvPlaylist>> getIptvPlaylists({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) => IptvPrefs.getIptvPlaylists(
    forSettings: forSettings,
    forRemoteTransfer: forRemoteTransfer,
  );

  static Future<void> setIptvPlaylists(
    List<IptvPlaylist> playlists, {
    bool revokeBorrowers = false,
  }) => IptvPrefs.setIptvPlaylists(
    playlists,
    revokeBorrowers: revokeBorrowers,
  );

  static Future<List<IptvPlaylist>> setIptvPlaylistsAndReload(
    List<IptvPlaylist> playlists, {
    required bool forSettings,
    bool revokeBorrowers = false,
  }) => IptvPrefs.setIptvPlaylistsAndReload(
    playlists,
    forSettings: forSettings,
    revokeBorrowers: revokeBorrowers,
  );

  static Future<String?> getIptvDefaultPlaylist() =>
      IptvPrefs.getIptvDefaultPlaylist();

  static Future<void> setIptvDefaultPlaylist(String? playlistId) =>
      IptvPrefs.setIptvDefaultPlaylist(playlistId);

  static Future<bool> getIptvDefaultsInitialized() =>
      IptvPrefs.getIptvDefaultsInitialized();

  static Future<void> setIptvDefaultsInitialized(bool initialized) =>
      IptvPrefs.setIptvDefaultsInitialized(initialized);

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

  static Future<Map<String, dynamic>?> getIptvLastLiveChannel() =>
      IptvPrefs.getIptvLastLiveChannel();

  static Future<void> clearIptvLastLiveChannel() =>
      IptvPrefs.clearIptvLastLiveChannel();

  static Future<bool> getStartupIptvEnabled() =>
      IptvPrefs.getStartupIptvEnabled();

  static Future<void> setStartupIptvEnabled(bool enabled) =>
      IptvPrefs.setStartupIptvEnabled(enabled);

  static Future<String> getStartupIptvMode() => IptvPrefs.getStartupIptvMode();

  static Future<void> setStartupIptvMode(String mode) =>
      IptvPrefs.setStartupIptvMode(mode);

  static Future<Map<String, dynamic>?> getStartupIptvChannel() =>
      IptvPrefs.getStartupIptvChannel();

  static Future<void> setStartupIptvChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) => IptvPrefs.setStartupIptvChannel(
    url,
    name: name,
    playlistId: playlistId,
    channelNumber: channelNumber,
    group: group,
    logoUrl: logoUrl,
    httpHeaders: httpHeaders,
  );

  static Future<void> clearStartupIptvChannel() =>
      IptvPrefs.clearStartupIptvChannel();

  static Future<void> warmStartupIptv() => IptvPrefs.warmStartupIptv();

  // ============================================================================
  // Remote Control Settings
  // ============================================================================

  /// Get whether remote control feature is enabled
  static Future<bool> getRemoteControlEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteControlEnabledKey) ?? true;
  }

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
  static Future<void> setRemoteControlEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteControlEnabledKey, enabled);
  }

  /// Get whether remote intro dialog has been shown
  static Future<bool> getRemoteIntroShown() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteIntroShownKey) ?? false;
  }

  /// Set whether remote intro dialog has been shown
  static Future<void> setRemoteIntroShown(bool shown) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteIntroShownKey, shown);
  }

  /// Get TV device name for remote control (TV only)
  static Future<String?> getRemoteTvDeviceName() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_remoteTvDeviceNameKey);
  }

  /// Set TV device name for remote control (TV only)
  static Future<void> setRemoteTvDeviceName(String name) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteTvDeviceNameKey, name);
  }

  /// Get last connected device info (Mobile only)
  static Future<Map<String, dynamic>?> getRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    final raw = prefs.getString(_remoteLastDeviceKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Save last connected device info (Mobile only)
  static Future<void> setRemoteLastDevice(Map<String, dynamic> device) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteLastDeviceKey, jsonEncode(device));
  }

  /// Clear last connected device info
  static Future<void> clearRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    await prefs.remove(_remoteLastDeviceKey);
  }

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
