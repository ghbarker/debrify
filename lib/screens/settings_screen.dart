import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/torrent_search_history_store.dart';
import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_version_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/webdav_item.dart';
import '../models/profiles/profile_policy.dart';
import '../models/profiles/user_profile.dart';
import '../services/main_page_bridge.dart';
import '../services/play_loader_style.dart';
import '../services/text_brightness.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/profiles/connection_resource_service.dart';
import '../services/profiles/profile_app_lifecycle_participant.dart';
import '../services/profiles/profile_lifecycle.dart';
import '../services/profiles/profile_lock_controller.dart';
import '../services/profiles/profile_authorization.dart';
import '../services/profiles/profile_bootstrap.dart';
import '../services/profiles/profile_device_reset_service.dart';
import '../services/profiles/profile_reset_service.dart';
import '../utils/platform_util.dart';
import '../services/external_player_service.dart';

import '../services/analytics_service.dart';
import '../services/diagnostic_log.dart';
import '../services/account_service.dart';
import '../services/download_service.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/storage/device_maintenance_prefs.dart';
import '../services/storage_service.dart';
import '../services/support_remote_config_service.dart';
import '../services/torbox_account_service.dart';
import '../services/premiumize_account_service.dart';
import '../services/alldebrid_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/stremio_service.dart';
import '../services/android_native_downloader.dart';
import '../services/live_recording_service.dart';
import '../services/desktop_schedule_service.dart';
import '../services/update_service.dart';
import '../widgets/support_donation_chooser_dialog.dart';
import '../widgets/tv_text_field.dart';
import 'settings/debrify_tv_settings_page.dart';
import 'settings/settings_tv_layout.dart';
import 'settings/settings_spotlight_shell.dart';
import 'settings/settings_search.dart';
import 'settings/settings_catalog.dart';
import 'settings/settings_page_registry.dart';
import 'settings/settings_page_spec.dart';
import 'settings/discover_layout_page.dart';
import 'settings/discover_settings_page.dart';
import 'settings/iptv_style_page.dart';
import 'settings/debrify_tv_style_page.dart';
import 'settings/text_brightness_page.dart';
import 'settings/launch_animation_page.dart';
import '../widgets/launch/launch_ident.dart';
import 'settings/detail_page_style_page.dart';
import 'settings/app_theme_page.dart';
import 'settings/looks_page.dart';
import 'settings/theme_tokens_page.dart';
import 'settings/theme_lab_page.dart';
import 'settings/detail_theme_page.dart';
import '../widgets/detail/theme/detail_themes.dart';
import '../theme/app_theme_controller.dart';
import 'settings/parents_guide_style_page.dart';
import 'settings/player_dock_page.dart';
import 'settings/play_loader_style_page.dart';
import 'settings/player_guide_style_page.dart';
import 'settings/tv_player_controls_style_page.dart';
import 'settings/debrify_tv_player_style_page.dart';
import 'settings/tv_home_style_page.dart';
import 'settings/tv_render_quality_page.dart';
import 'settings/tv_hero_artwork_quality_page.dart';
import 'settings/tv_screen_size_page.dart';
import 'settings/recordings_page.dart';
import 'settings/desktop_sidebar_style_page.dart';
import 'settings/tv_sidebar_style_page.dart';
import 'settings/sidebar_customization_page.dart';
import 'settings/profile_backup_flows.dart';
import 'settings/backup_restore_page.dart';
import 'settings/download_location_controller.dart';
import 'settings/profile_appearance_page.dart';
import 'settings/widgets/settings_widgets.dart';
import 'settings/pikpak_settings_page.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/iptv_settings_page.dart';
import 'settings/iptv_channel_order_page.dart';
import 'settings/collections_settings_page.dart';
import 'settings/home_page_settings_page.dart';
import 'settings/torbox_settings_page.dart';
import 'settings/premiumize_settings_page.dart';
import 'settings/alldebrid_settings_page.dart';
import 'settings/torrent_settings_page.dart';
import 'settings/filter_settings_page.dart';
import 'settings/indexer_managers_settings_page.dart';
import 'settings/provider_settings_page.dart';
import 'settings/quick_play_settings_page.dart';
import 'settings/external_player_settings_page.dart';
import 'settings/profiles_settings_page.dart';
import 'profiles/profile_wall_screen.dart';
import 'settings/trakt_settings_page.dart';
import 'settings/simkl_settings_page.dart';
import 'settings/mdblist_settings_page.dart';
import 'settings/tracking_settings_page.dart';
import 'settings/webdav_settings_page.dart';
import 'settings/stremio_tv_settings_page.dart';
import '../widgets/remote/remote_role_picker_screen.dart';
import '../theme/app_looks.dart';
import '../theme/app_theme_scope.dart';
import '../models/tv_hero_artwork_quality.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _isAndroidTv = false;

  // Focus node for the first connection card (Real-Debrid) for TV navigation
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'firstCardFocus');

  /// IPTV recording engine availability (Android 10+); gates its search entry.
  bool _recordingSearchable = false;

  // ── Platform gates for search entries ───────────────────────────────────
  // A search result must never open a page that has no matching control, so
  // any indexed row whose page renders it conditionally is gated on the SAME
  // condition the page uses.

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isTelevision => PlatformUtil.isTelevision;

  /// Handsets only. The player's start-orientation control is hidden on TV
  /// (no portrait to open in) and on desktop (the orientation call is a no-op
  /// there) — see ExternalPlayerSettingsPage.
  bool get _isPhone => PlatformUtil.isPhone;

  /// The IPTV Appearance picker renders only where the cockpit does (Android
  /// TV, desktop) — the SAME gate IptvSettingsPage uses for its section
  /// (PlatformUtil's cache, not this screen's own `_isAndroidTv`, which
  /// handles probe failures differently and could disagree).
  bool get _iptvAppearanceSearchable =>
      PlatformUtil.isAndroidTvCached ||
      (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows));

  /// Custom launch command (macOS/Linux/Windows) or custom URL scheme (iOS).
  /// Android's external-player branch offers neither — it only explains the
  /// system app chooser. See ExternalPlayerSettingsPage's platform branches.
  bool get _customPlayerCommandSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isIOS);

  /// A named preferred-player picker exists on Apple platforms and desktop.
  /// Android delegates this choice to the system app chooser instead.
  bool get _preferredExternalPlayerSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isIOS);

  /// The recordings page has a working backend: the Android engine (tracked by
  /// [_recordingSearchable]) or the desktop recorder. On iOS it has neither —
  /// scheduling only raises a storage error and the library is always empty.
  bool get _recordingSupported =>
      _recordingSearchable || DesktopScheduleService.instance.isSupported;

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  bool _realDebridConnected = false;
  String _realDebridStatus = 'Not connected';
  String _realDebridCaption = 'Tap to connect';

  bool _torboxConnected = false;
  String _torboxStatus = 'Not connected';
  String _torboxCaption = 'Tap to connect';

  bool _premiumizeConnected = false;
  String _premiumizeStatus = 'Not connected';
  String _premiumizeCaption = 'Tap to connect';

  bool _allDebridConnected = false;
  String _allDebridStatus = 'Not connected';
  String _allDebridCaption = 'Tap to connect';

  bool _pikpakConnected = false;
  String _pikpakStatus = 'Not connected';
  String _pikpakCaption = 'Tap to connect';

  bool _webDavConnected = false;
  String _webDavStatus = 'Not connected';
  String _webDavCaption = 'Tap to connect';

  bool _traktConnected = false;
  String _traktStatus = 'Not connected';
  String _traktCaption = 'Tap to connect';

  bool _simklConnected = false;
  String _simklStatus = 'Not connected';
  String _simklCaption = 'Tap to connect';

  bool _mdblistConnected = false;
  String _mdblistStatus = 'Not connected';
  String _mdblistCaption = 'Tap to connect';

  bool _indexerManagersConfigured = false;
  String _indexerManagersStatus = 'Not configured';
  String _indexerManagersCaption = 'Connect Jackett or Prowlarr';

  String _appVersion = '';
  String _currentVersionName = '';
  bool _checkingUpdates = false;
  String _updateSubtitle = 'Check for new builds from GitHub releases';
  StreamSubscription<Map<String, dynamic>>? _updateDownloadSub;
  String? _updateDownloadTaskId;
  bool _autoUpdateChecksEnabled = true;
  bool _diagnosticExportVisible = false;
  bool _exportingDiagnostics = false;
  bool _tvKeyboardEnabled = true;
  int _tvUiScalePercent = StorageService.kTvUiScaleDefault;
  TvRenderQuality _tvRenderQuality = TvRenderQuality.auto;
  TvHeroArtworkQuality _tvHeroArtworkQuality = TvHeroArtworkQuality.automatic;
  String _tvHomeStyle = 'canvas';
  String _discoverLayout = 'stage';
  String _tvSidebarStyle = 'ghost';
  String _iptvStyle = 'command';
  String _debrifyTvStyle = 'grid';
  String _playerGuideStyle = 'classic';
  String _playLoaderStyle = PlayLoaderStyleController.defaultStyle;
  String _tvPlayerControlsStyle = 'marquee';
  String _debrifyTvPlayerStyle = 'cinema';
  String _playerDockStyle = 'classic';
  String _playerDockPalette = 'ultraviolet';
  String _playerDockSize = 'auto';
  // The placeholder the Appearance row shows for the one frame before the
  // async load lands; a literal here would flash the wrong label.
  String _detailPageStyle = StorageService.kDetailPageStyleDefault;
  String _detailTheme = 'signal';
  String _parentsGuideStyle = 'compass';
  String _phoneNavStyle = 'classic';
  String _desktopSidebarStyle = 'rail';
  String _textBrightness = 'bright';
  String _launchAnimation = 'trace';
  late final DownloadLocationController _downloadLocation;
  SupportDonationConfig _supportDonation = SupportDonationConfig.empty;
  String _supportSettingsLabel = 'Support Debrify';
  String _supportSettingsSubtitle = 'Help fund development with a donation';

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('settings');
    _loadSummaries();
    _loadSupportConfig();
    _downloadLocation = DownloadLocationController(
      isMounted: () => mounted,
      setState: setState,
      contextOf: () => context,
    );
    _downloadLocation.loadDownloadLocation();
    // IPTV recording exists where its engine can run (Android 10+, or pre-Q
    // with the grantable legacy storage path) — the search index must not
    // advertise it elsewhere.
    if (!kIsWeb && Platform.isAndroid) {
      LiveRecordingService.engineSupport().then((support) {
        if (support != 'unsupported' && mounted) {
          setState(() => _recordingSearchable = true);
        }
      });
    }

    // Register TV sidebar focus handler (tab index 8 = Settings)
    _tvContentFocusHandler = () {
      _firstCardFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(8, _tvContentFocusHandler!);
  }

  @override
  void dispose() {
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        8,
        _tvContentFocusHandler!,
      );
    }
    _firstCardFocusNode.dispose();
    _updateDownloadSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSummaries() async {
    final startingScope = ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    try {
      await _loadSummariesForCurrentProfile();
    } on ResourceAuthorizationException {
      // ProfileGate replaces this subtree before switching authority. Reads
      // revoked while this disposed settings page winds down are expected.
      if (!mounted ||
          ProfileLockController.instance.lockedProfileId.value != null ||
          (startingScope != null &&
              ProfileRuntime.scope.value != startingScope)) {
        return;
      }
      rethrow;
    }
  }

  Future<bool> _activeProfileMayExportDiagnostics() async {
    // saveBackupFile has no user-retrievable destination on physical tvOS.
    // Keep this hidden until diagnostics use the authenticated Remote
    // transfer flow, as profile backups already do on Apple TV.
    if (PlatformUtil.isTvOS) return false;
    try {
      if (ProfileRuntime.mode == ProfileRuntimeMode.legacyCompatibility) {
        // A legacy install has one implicit device owner/admin.
        return true;
      }
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      return actor.role == UserProfileRole.admin;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadSummariesForCurrentProfile() async {
    // Phase 1: Load cached/local state instantly (no network)
    final results = await Future.wait([
      StorageService.hasRealDebridCredential(),
      StorageService.hasTorboxCredential(),
      PikPakApiService.instance.isAuthenticated(),
      ProviderCredentialPrefs.getWebDavEnabled(),
      ProviderCredentialPrefs.getWebDavServers(forSettings: true),
      TrackingPrefs.hasTraktCredential(),
      TrackingPrefs.getTraktTokenExpiry(),
      TrackingPrefs.getTraktUsername(),
      AppVersionInfo.get(),
      AndroidNativeDownloader.isTelevision(),
      DeviceMaintenancePrefs.getUpdateAutoCheckEnabled(),
      StorageService.getIndexerManagerConfigs(forSettings: true),
      StorageService.hasPremiumizeCredential(),
      StorageService.hasAllDebridCredential(),
      TrackingPrefs.hasSimklCredential(),
      TrackingPrefs.getSimklUsername(),
      TrackingPrefs.hasMdblistCredential(),
      TrackingPrefs.getMdblistUsername(),
      StorageService.getTvKeyboardEnabled(),
      StorageService.getTvUiScalePercent(),
      StorageService.getTvHomeStyle(),
      StorageService.getTvSidebarStyle(),
      StorageService.getDiscoverLayout(),
      StorageService.getIptvStyle(),
      StorageService.getIptvPlayerGuideStyle(),
      AppStylePrefs.getPhoneNavStyle(),
      AppStylePrefs.getTextBrightness(),
      AppStylePrefs.getLaunchAnimation(),
      AppStylePrefs.getDetailPageStyle(),
      StorageService.getTvRenderQuality(),
      AppStylePrefs.getDetailTheme(),
      AppStylePrefs.getParentsGuideStyle(),
      StorageService.getTvHeroArtworkQuality(),
      StorageService.getPlayerDockStyle(),
      StorageService.getPlayerDockPalette(),
      StorageService.getPlayerDockSize(),
      AppStylePrefs.getDesktopSidebarStyle(),
      StorageService.getDebrifyTvStyle(),
      StorageService.getTvPlayerControlsStyle(),
      StorageService.getDebrifyTvPlayerStyle(),
      StorageService.getPlayLoaderStyle(),
      _activeProfileMayExportDiagnostics(),
    ]);

    if (!mounted) return;

    final rdConnected = results[0] as bool;
    final torConnected = results[1] as bool;
    final pikpakAuth = results[2] as bool;
    final webDavEnabled = results[3] as bool;
    final webDavServers = results[4] as List<WebDavConfig>;
    final traktConnected = results[5] as bool;
    final traktExpiry = results[6] as int?;
    final traktUsername = results[7] as String?;
    final packageInfo = results[8] as PackageInfo;
    final isAndroidTv = results[9] as bool;
    final autoCheckEnabled = results[10] as bool;
    final indexerManagers = results[11] as List;
    final premiumizeConnected = results[12] as bool;
    final allDebridConnected = results[13] as bool;
    final simklConnected = results[14] as bool;
    final simklUsername = results[15] as String?;
    final mdblistConnected = results[16] as bool;
    final mdblistUsername = results[17] as String?;
    final tvKeyboardEnabled = results[18] as bool;
    final tvUiScalePercent = results[19] as int;
    final tvHomeStyle = results[20] as String;
    final tvSidebarStyle = results[21] as String;
    final discoverLayout = results[22] as String;
    final iptvStyle = results[23] as String;
    final playerGuideStyle = results[24] as String;
    final phoneNavStyle = results[25] as String;
    final textBrightness = results[26] as String;
    final launchAnimation = results[27] as String;
    final detailPageStyle = results[28] as String;
    final tvRenderQuality = results[29] as TvRenderQuality;
    final detailTheme = results[30] as String;
    final parentsGuideStyle = results[31] as String;
    final tvHeroArtworkQuality = results[32] as TvHeroArtworkQuality;
    // Appended at the END of the Future.wait above, so no existing index
    // moves. The list holds 33 entries (0..32) as of b525f2dc.
    final playerDockStyle = results[33] as String;
    final playerDockPalette = results[34] as String;
    final playerDockSize = results[35] as String;
    final desktopSidebarStyle = results[36] as String;
    final debrifyTvStyle = results[37] as String;
    final tvPlayerControlsStyle = results[38] as String;
    final debrifyTvPlayerStyle = results[39] as String;
    final playLoaderStyle = results[40] as String;
    final diagnosticExportVisible = results[41] as bool;

    // Set initial state from cached data
    // Use cached account info if available
    if (rdConnected) {
      final user = AccountService.currentUser;
      _realDebridConnected = true;
      if (user != null) {
        _applyRdUserInfo(user);
      } else {
        _realDebridStatus = 'Connected';
        _realDebridCaption = 'Loading account info...';
      }
    }

    if (torConnected) {
      final torboxUser = TorboxAccountService.currentUser;
      _torboxConnected = true;
      if (torboxUser != null) {
        _applyTorboxUserInfo(torboxUser);
      } else {
        _torboxStatus = 'Connected';
        _torboxCaption = 'Loading account info...';
      }
    }

    if (premiumizeConnected) {
      final premiumizeUser = PremiumizeAccountService.currentUser;
      _premiumizeConnected = true;
      if (premiumizeUser != null) {
        _applyPremiumizeUserInfo(premiumizeUser);
      } else {
        _premiumizeStatus = 'Connected';
        _premiumizeCaption = 'Loading account info...';
      }
    }

    if (allDebridConnected) {
      final allDebridUser = AllDebridAccountService.currentUser;
      _allDebridConnected = true;
      if (allDebridUser != null) {
        _applyAllDebridUserInfo(allDebridUser);
      } else {
        _allDebridStatus = 'Connected';
        _allDebridCaption = 'Loading account info...';
      }
    }

    if (pikpakAuth) {
      _pikpakConnected = true;
      _pikpakStatus = 'Active';
      _pikpakCaption = 'Logged in';
    }

    if (webDavEnabled && webDavServers.isNotEmpty) {
      _webDavConnected = true;
      _webDavStatus = 'Active';
      final first = webDavServers.first;
      final host = Uri.tryParse(first.baseUrl)?.host;
      final label = (host != null && host.isNotEmpty) ? host : first.baseUrl;
      _webDavCaption = webDavServers.length == 1
          ? label
          : '$label (+${webDavServers.length - 1} more)';
    } else {
      _webDavConnected = false;
      _webDavStatus = 'Not connected';
      _webDavCaption = 'Tap to connect';
    }

    if (traktConnected) {
      final traktExpired =
          traktExpiry != null &&
          DateTime.now().millisecondsSinceEpoch >= traktExpiry;
      if (!traktExpired) {
        _traktConnected = true;
        _traktStatus = 'Active';
        _traktCaption = traktUsername != null
            ? 'Logged in as $traktUsername'
            : 'Logged in';
      } else {
        _traktStatus = 'Expired';
        _traktCaption = 'Tap to reconnect';
      }
    }

    // Simkl's PIN-issued tokens don't expire, so unlike Trakt there's no
    // "Expired" branch here — a stored token means connected.
    if (simklConnected) {
      _simklConnected = true;
      _simklStatus = 'Active';
      _simklCaption = simklUsername != null
          ? 'Logged in as $simklUsername'
          : 'Logged in';
    } else {
      _simklConnected = false;
      _simklStatus = 'Not connected';
      _simklCaption = 'Tap to connect';
    }

    // MDBList uses a plain API key (no expiry) — a stored key means connected.
    // Reset on the empty branch (like WebDAV above) so the card clears after a
    // logout, since this method re-runs when returning from the settings page.
    if (mdblistConnected) {
      _mdblistConnected = true;
      _mdblistStatus = 'Active';
      _mdblistCaption = mdblistUsername != null
          ? 'Logged in as $mdblistUsername'
          : 'Logged in';
    } else {
      _mdblistConnected = false;
      _mdblistStatus = 'Not connected';
      _mdblistCaption = 'Tap to connect';
    }

    if (indexerManagers.isNotEmpty) {
      _indexerManagersConfigured = true;
      _indexerManagersStatus = 'Active';
      _indexerManagersCaption =
          '${indexerManagers.length} engine${indexerManagers.length == 1 ? '' : 's'} configured';
    }

    _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    _currentVersionName = packageInfo.version;
    _isAndroidTv = isAndroidTv;
    DiagnosticLog.instance.recordEvent(
      source: 'app',
      event: 'app_metadata',
      fields: <String, Object?>{
        'version': DiagnosticLabel(packageInfo.version),
        'build': DiagnosticLabel(packageInfo.buildNumber),
        'androidTv': isAndroidTv,
      },
    );
    _loading = false;
    _autoUpdateChecksEnabled = autoCheckEnabled;
    _tvKeyboardEnabled = tvKeyboardEnabled;
    _tvUiScalePercent = tvUiScalePercent;
    _tvRenderQuality = tvRenderQuality;
    _tvHomeStyle = tvHomeStyle;
    _tvSidebarStyle = tvSidebarStyle;
    _discoverLayout = discoverLayout;
    _iptvStyle = iptvStyle;
    _debrifyTvStyle = debrifyTvStyle;
    _playerGuideStyle = playerGuideStyle;
    _playLoaderStyle = playLoaderStyle;
    _tvPlayerControlsStyle = tvPlayerControlsStyle;
    _debrifyTvPlayerStyle = debrifyTvPlayerStyle;
    _playerDockStyle = playerDockStyle;
    _playerDockPalette = playerDockPalette;
    _playerDockSize = playerDockSize;
    _phoneNavStyle = phoneNavStyle;
    _desktopSidebarStyle = desktopSidebarStyle;
    _textBrightness = textBrightness;
    _launchAnimation = launchAnimation;
    _detailPageStyle = detailPageStyle;
    _detailTheme = detailTheme;
    _parentsGuideStyle = parentsGuideStyle;
    _tvHeroArtworkQuality = tvHeroArtworkQuality;
    _diagnosticExportVisible = diagnosticExportVisible;

    setState(() {});

    // Phase 2: Refresh account info from network in background
    if (rdConnected) {
      AccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final user = AccountService.currentUser;
        if (user != null) {
          setState(() => _applyRdUserInfo(user));
        }
      });
    }

    if (torConnected) {
      TorboxAccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final torboxUser = TorboxAccountService.currentUser;
        if (torboxUser != null) {
          setState(() => _applyTorboxUserInfo(torboxUser));
        }
      });
    }

    if (premiumizeConnected) {
      PremiumizeAccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final premiumizeUser = PremiumizeAccountService.currentUser;
        if (premiumizeUser != null) {
          setState(() => _applyPremiumizeUserInfo(premiumizeUser));
        }
      });
    }

    if (allDebridConnected) {
      AllDebridAccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final allDebridUser = AllDebridAccountService.currentUser;
        if (allDebridUser != null) {
          setState(() => _applyAllDebridUserInfo(allDebridUser));
        }
      });
    }
  }

  Future<void> _loadSupportConfig() async {
    final service = SupportRemoteConfigService.instance;
    final cached = await service.loadCachedOrFallback();
    if (mounted) {
      setState(() {
        _applySupportConfig(cached);
      });
    }

    final fresh = await service.loadConfig();
    if (!mounted) return;
    setState(() {
      _applySupportConfig(fresh);
    });
  }

  void _applySupportConfig(SupportRemoteConfig config) {
    _supportDonation = config.donation;
    _supportSettingsLabel = config.donation.settingsLabel;
    _supportSettingsSubtitle = config.donation.settingsSubtitle;
  }

  Future<void> _openSupportDonation() async {
    await showSupportDonationChooserDialog(
      context,
      donation: _supportDonation,
      title: _supportSettingsLabel,
      // Match the settings palette (the dialog is shown from the State's
      // context, which sits above the scoped theme in build()).
      theme: settingsPageTheme(context),
    );
  }

  void _applyRdUserInfo(dynamic user) {
    final expiry = _tryParseDate(user.expiration);
    final bool isPremium = user.isPremium;
    final bool active =
        isPremium && (expiry == null || expiry.isAfter(DateTime.now()));
    _realDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _realDebridCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _realDebridCaption = 'Premium account';
    } else if (isPremium && expiry != null) {
      _realDebridCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _realDebridCaption = 'Premium not active';
    }
  }

  void _applyTorboxUserInfo(dynamic torboxUser) {
    final expiry = torboxUser.premiumExpiresAt;
    final bool active = torboxUser.hasActiveSubscription;
    _torboxStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _torboxCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _torboxCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _torboxCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _torboxCaption = 'Premium not active';
    }
  }

  void _applyPremiumizeUserInfo(dynamic premiumizeUser) {
    final expiry = premiumizeUser.premiumUntil;
    final bool active = premiumizeUser.hasActivePremium;
    _premiumizeStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _premiumizeCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _premiumizeCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _premiumizeCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _premiumizeCaption = 'Premium not active';
    }
  }

  void _applyAllDebridUserInfo(dynamic allDebridUser) {
    final expiry = allDebridUser.premiumUntil;
    final bool active = allDebridUser.hasActivePremium;
    _allDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _allDebridCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _allDebridCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _allDebridCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _allDebridCaption = 'Premium not active';
    }
  }

  @override
  Widget build(BuildContext context) {
    // The whole tab renders under the scoped settings theme so inline
    // Material widgets (progress spinners, switches) match the subpages.
    // Dialogs shown from this State's context sit ABOVE this Theme, so they
    // go through showSettingsDialog instead.
    if (_loading) {
      return Theme(
        data: settingsPageTheme(context),
        child: const SettingsSkeleton(),
      );
    }

    return Theme(
      data: settingsPageTheme(context),
      child: _isAndroidTv ? _buildTvLayout() : _buildLayout(context),
    );
  }

  // Connection cards in canonical order (matches the phone grid rows).
  ConnectionInfo get _rdInfo => ConnectionInfo(
    title: 'Real Debrid',
    connected: _realDebridConnected,
    status: _realDebridStatus,
    caption: _realDebridCaption,
    onTap: _openRealDebridSettings,
  );
  ConnectionInfo get _torboxInfo => ConnectionInfo(
    title: 'Torbox',
    connected: _torboxConnected,
    status: _torboxStatus,
    caption: _torboxCaption,
    onTap: _openTorboxSettings,
  );
  ConnectionInfo get _premiumizeInfo => ConnectionInfo(
    title: 'Premiumize',
    connected: _premiumizeConnected,
    status: _premiumizeStatus,
    caption: _premiumizeCaption,
    onTap: _openPremiumizeSettings,
  );
  ConnectionInfo get _allDebridInfo => ConnectionInfo(
    title: 'AllDebrid',
    connected: _allDebridConnected,
    status: _allDebridStatus,
    caption: _allDebridCaption,
    onTap: _openAllDebridSettings,
  );
  ConnectionInfo get _pikpakInfo => ConnectionInfo(
    title: 'PikPak',
    connected: _pikpakConnected,
    status: _pikpakStatus,
    caption: _pikpakCaption,
    onTap: _openPikPakSettings,
  );
  ConnectionInfo get _webDavInfo => ConnectionInfo(
    title: 'WebDAV',
    connected: _webDavConnected,
    status: _webDavStatus,
    caption: _webDavCaption,
    onTap: _openWebDavSettings,
  );
  ConnectionInfo get _iptvInfo => ConnectionInfo(
    title: 'IPTV',
    connected: true,
    status: 'Active',
    caption: 'M3U playlist channels',
    onTap: _openIptvSettings,
  );
  ConnectionInfo get _traktInfo => ConnectionInfo(
    title: 'Trakt',
    connected: _traktConnected,
    status: _traktStatus,
    caption: _traktCaption,
    onTap: _openTraktSettings,
  );
  ConnectionInfo get _simklInfo => ConnectionInfo(
    title: 'Simkl',
    connected: _simklConnected,
    status: _simklStatus,
    caption: _simklCaption,
    onTap: _openSimklSettings,
  );
  ConnectionInfo get _mdblistInfo => ConnectionInfo(
    title: 'MDBList',
    connected: _mdblistConnected,
    status: _mdblistStatus,
    caption: _mdblistCaption,
    onTap: _openMdblistSettings,
  );
  ConnectionInfo get _trackingInfo => ConnectionInfo(
    title: 'Tracking',
    connected: true,
    status: 'Configured',
    caption: 'Scrobble, progress source & Home ticks',
    onTap: _openTrackingSettings,
  );
  ConnectionInfo get _indexerManagersInfo => ConnectionInfo(
    title: 'Jackett & Prowlarr',
    connected: _indexerManagersConfigured,
    status: _indexerManagersStatus,
    caption: _indexerManagersCaption,
    onTap: _openIndexerManagersSettings,
  );

  List<String> _settingsLabels(Iterable<String> values) => [
    for (final value in values) value.toLowerCase(),
  ];

  List<SettingsPageSpec> get _settingsPages => buildSettingsPages(
    SettingsPageBindings(
      openHomePage: _openHomePageSettings,
      openCollections: _openCollectionsSettings,
      openExternalPlayer: _openExternalPlayerSettings,
      openRemote: _openRemoteControl,
      openSwitchProfile: () async {
        await ProfileSettingsRailActions(context).openHub();
        if (!mounted) return;
        final diagnosticExportVisible =
            await _activeProfileMayExportDiagnostics();
        if (!mounted) return;
        setState(() => _diagnosticExportVisible = diagnosticExportVisible);
      },
      openAddProfile: () => ProfileSettingsRailActions(
        context,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ).addProfile(),
      openEditProfile: () => ProfileSettingsRailActions(
        context,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ).editActiveProfile(),
      openNavigation: _openNavigationSettings,
      openTorrentSettings: _openTorrentSettings,
      openFilterSettings: _openFilterSettings,
      openProviderSettings: _openProviderSettings,
      openQuickPlay: _openQuickPlaySettings,
      openDiscover: _openDiscoverSettings,
      openDebrifyTv: _openDebrifyTvSettings,
      openRecordings: _openRecordings,
      openIptv: _openIptvSettings,
      openDownloadLocation: _downloadLocation.downloadLocationSupported
          ? _downloadLocation.openDownloadLocationSettings
          : null,
      clearDownloads: _clearDownloadData,
      clearPlayback: _clearPlaybackData,
      createBackup: () => BackupRestorePage(
        context,
        onRestored: _afterBackupRestore,
      ).createBackup(),
      restoreBackup: () => BackupRestorePage(
        context,
        onRestored: _afterBackupRestore,
      ).restoreBackup(),
      exportDiagnosticLogs: _diagnosticExportVisible
          ? _exportDiagnosticLogs
          : null,
      resetApp: _resetAppData,
      checkUpdates: _checkForAppUpdates,
      openSupportDonation: _openSupportDonation,
      openTextBrightness: _openTextBrightnessPage,
      openLaunchAnimation: _openLaunchAnimationPage,
      openTvScreenSize: _openTvScreenSize,
      openTvRenderQuality: _openTvRenderQuality,
      openTvHeroArtworkQuality: _openTvHeroArtworkQuality,
      openTvHomeStyle: _openTvHomeStyle,
      openDiscoverLayout: _openDiscoverLayout,
      openTvSidebarStyle: _openTvSidebarStyle,
      openDesktopSidebarStyle: _openDesktopSidebarStyle,
      openIptvStyle: _openIptvStylePage,
      openDebrifyTvStyle: _openDebrifyTvStylePage,
      openPlayerGuideStyle: _openPlayerGuideStylePage,
      openPlayLoaderStyle: _openPlayLoaderStylePage,
      openTvPlayerControlsStyle: _openTvPlayerControlsStylePage,
      openDebrifyTvPlayerStyle: _openDebrifyTvPlayerStylePage,
      openPlayerDock: _openPlayerDockPage,
      openThemeTokens: _openThemeTokensPage,
      openLooks: _openLooksPage,
      openThemeLab: _openThemeLab,
      openAppTheme: _openAppThemePage,
      openDetailTheme: _openDetailThemePage,
      openSidebarCustomization: _openSidebarCustomization,
      openParentsGuideStyle: _openParentsGuideStylePage,
      openDetailPageStyle: _openDetailPageStylePage,
      openProfileAppearance: _openProfileAppearance,
      openStremioTv: _openStremioTvSettings,
      openAddons: () async =>
          MainPageBridge.switchTab?.call(MainTab.addons),
      openIptvAddSource: _openIptvAddSource,
      openIptvChannelOrder: _openIptvChannelOrder,
      openTorbox: _openTorboxSettings,
      openPremiumize: _openPremiumizeSettings,
      openRealDebrid: _openRealDebridSettings,
      openAllDebrid: _openAllDebridSettings,
      openPikPak: _openPikPakSettings,
      openWebDav: _openWebDavSettings,
      openIndexerManagers: _openIndexerManagersSettings,
      openTrakt: _openTraktSettings,
      openTracking: _openTrackingSettings,
      openSimkl: _openSimklSettings,
      openMdblist: _openMdblistSettings,
      textBrightnessLabel: textBrightnessLabel(_textBrightness),
      launchAnimationLabel: launchIdentLabel(_launchAnimation),
      tvUiScaleLabel: tvUiScaleLabel(_tvUiScalePercent),
      tvRenderQualityLabel: tvRenderQualityLabel(_tvRenderQuality),
      tvHeroArtworkQualityLabel: tvHeroArtworkQualityLabel(
        _tvHeroArtworkQuality,
      ),
      tvHomeStyleLabel: tvHomeStyleLabel(
        _isAndroidTv ? _tvHomeStyle : effectiveOffTvHomeStyle(_tvHomeStyle),
      ),
      discoverLayoutLabel: discoverLayoutLabel(_discoverLayout),
      tvSidebarStyleLabel: tvSidebarStyleLabel(_tvSidebarStyle),
      desktopSidebarStyleLabel: desktopSidebarStyleLabel(_desktopSidebarStyle),
      iptvStyleLabel: iptvStyleLabel(_iptvStyle),
      debrifyTvStyleLabel: debrifyTvStyleLabel(_debrifyTvStyle),
      playerGuideStyleLabel: playerGuideStyleLabel(_playerGuideStyle),
      playLoaderStyleLabel: playLoaderStyleLabel(_playLoaderStyle),
      tvPlayerControlsStyleLabel: tvPlayerControlsStyleLabel(
        _tvPlayerControlsStyle,
      ),
      debrifyTvPlayerStyleLabel: debrifyTvPlayerStyleLabel(
        _debrifyTvPlayerStyle,
      ),
      playerDockLabel: playerDockLabel(
        _playerDockStyle,
        _playerDockPalette,
        _playerDockSize,
      ),
      themeTokensLabel: _themeTokensLabel,
      looksLabel: AppLooks.active()?.label ?? 'Custom',
      detailThemeLabel: detailThemeLabel(_detailTheme),
      parentsGuideStyleLabel: parentsGuideStyleLabel(_parentsGuideStyle),
      detailPageStyleLabel: detailPageStyleLabel(_detailPageStyle),
      profileAppearanceLabel: ProfileGateStyle.labelFor(ProfileGateStyle.cached),
      phoneNavStyleLabel: _phoneNavStyle == 'floating'
          ? 'Floating button'
          : 'Classic bar',
      downloadLocationSubtitle: _downloadLocation.downloadLocationSubtitle,
      updateSubtitle: _updateSubtitle,
      supportDonationLabel: _supportSettingsLabel,
      supportDonationSubtitle: _supportSettingsSubtitle,
      appVersion: _appVersion,
      checkingUpdates: _checkingUpdates,
      autoUpdateChecksEnabled: _autoUpdateChecksEnabled,
      onToggleAutoUpdateChecks: _toggleAutoUpdateChecks,
      tvKeyboardEnabled: _tvKeyboardEnabled,
      onToggleTvKeyboard: _toggleTvKeyboard,
      isAndroidTv: _isAndroidTv,
      isTelevision: _isTelevision,
      isAndroid: _isAndroid,
      isPhone: _isPhone,
      showSwitchProfile:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      downloadLocationSupported: _downloadLocation.downloadLocationSupported,
      diagnosticExportVisible: _diagnosticExportVisible,
      showSupportDonation: _supportDonation.hasProviders,
      iptvAppearanceSearchable: _iptvAppearanceSearchable,
      recordingSearchable: _recordingSearchable,
      recordingSupported: _recordingSupported,
      preferredExternalPlayerSupported: _preferredExternalPlayerSupported,
      customPlayerCommandSupported: _customPlayerCommandSupported,
      mdblistEnabled: kMdblistEnabled,
      profileCommitted:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      supportsSubtitleAutoSync: PlatformUtil.supportsSubtitleAutoSync,
      isTvOS: PlatformUtil.isTvOS,
      isIosMobile: PlatformUtil.isIosMobile,
      extraTextBrightnessKeywords: () =>
          _settingsLabels(TextBrightness.values.map((c) => c.label)),
      extraLaunchAnimationKeywords: () =>
          _settingsLabels(kLaunchIdents.map((i) => i.label)),
      extraTvScreenSizeKeywords: () =>
          _settingsLabels(kTvUiScaleChoices.map((c) => c.label)),
      extraTvRenderQualityKeywords: () =>
          _settingsLabels(kTvRenderQualityChoices.map((c) => c.label)),
      extraTvHeroArtworkKeywords: () =>
          _settingsLabels(kTvHeroArtworkQualityChoices.map((c) => c.label)),
      extraTvHomeStyleKeywords: () => _settingsLabels(
        (_isTelevision ? kTvHomeStyleChoices : kOffTvHomeStyleChoices).map(
          (c) => c.label,
        ),
      ),
      extraDiscoverLayoutKeywords: () =>
          _settingsLabels(kDiscoverLayoutChoices.map((c) => c.label)),
      extraTvSidebarKeywords: () =>
          _settingsLabels(kTvSidebarStyleChoices.map((c) => c.label)),
      extraDesktopSidebarKeywords: () =>
          _settingsLabels(kDesktopSidebarStyleChoices.map((c) => c.label)),
      extraIptvStyleKeywords: () =>
          _settingsLabels(kIptvStyleChoices.map((c) => c.label)),
      extraDebrifyTvStyleKeywords: () =>
          _settingsLabels(kDebrifyTvStyleChoices.map((c) => c.label)),
      extraPlayerGuideKeywords: () => _settingsLabels(
        playerGuideStyleChoicesForPlatform().map((c) => c.label),
      ),
      extraPlayLoaderKeywords: () => _settingsLabels(
        PlayLoaderStyleController.options.map((c) => c.label),
      ),
      extraTvPlayerControlsKeywords: () =>
          _settingsLabels(kTvPlayerControlsStyleChoices.map((c) => c.label)),
      extraDebrifyTvPlayerKeywords: () =>
          _settingsLabels(kDebrifyTvPlayerStyleChoices.map((c) => c.label)),
      extraPlayerKeywords: () {
        if (kIsWeb) return const <String>[];
        if (Platform.isMacOS) {
          return _settingsLabels(
            ExternalPlayer.values.map((player) => player.displayName),
          );
        }
        if (Platform.isLinux) {
          return _settingsLabels(
            LinuxExternalPlayer.values.map((player) => player.displayName),
          );
        }
        if (Platform.isWindows) {
          return _settingsLabels(
            WindowsExternalPlayer.values.map((player) => player.displayName),
          );
        }
        if (Platform.isIOS) {
          return _settingsLabels(
            iOSExternalPlayer.values
                .where(
                  (player) => !PlatformUtil.isTvOS || player.availableOnTvos,
                )
                .map((player) => player.displayName),
          );
        }
        return const <String>[];
      },
      extraPlayerDockKeywords: () => [
        ..._settingsLabels(kPlayerDockStyleChoices.map((c) => c.label)),
        ..._settingsLabels(kPlayerDockPaletteChoices.map((c) => c.label)),
        ..._settingsLabels(kPlayerDockSizeChoices.map((c) => c.label)),
      ],
      extraLooksKeywords: () => [
        ..._settingsLabels(AppLooks.all.map((look) => look.label)),
        for (final t in DetailThemes.catalogue) t.label.toLowerCase(),
      ],
      extraParentsGuideKeywords: () =>
          _settingsLabels(kParentsGuideStyleChoices.map((c) => c.label)),
      extraDetailPageKeywords: () =>
          _settingsLabels(kDetailPageStyleChoices.map((c) => c.label)),
      extraProfileAppearanceKeywords: () =>
          _settingsLabels(ProfileGateStyle.options.map((o) => o.label)),
    ),
  );

  SettingsPageRegistry get _settingsRegistry =>
      SettingsPageRegistry(pages: _settingsPages);

  Widget _buildTvLayout() {
    return SettingsTvLayout(
      connections: [
        _rdInfo,
        _torboxInfo,
        _premiumizeInfo,
        _allDebridInfo,
        _pikpakInfo,
        _webDavInfo,
        _iptvInfo,
        _indexerManagersInfo,
      ],
      // Watch history lives on its own rail category — Connections had grown
      // to ten cards covering five unrelated jobs.
      tracking: _trackingInfo,
      trackers: [
        _traktInfo,
        _simklInfo,
        // MDBList hidden for the alpha (unfinished) — see [kMdblistEnabled].
        if (kMdblistEnabled) _mdblistInfo,
      ],
      firstFocusNode: _firstCardFocusNode,
      onOpenSearch: _openSettingsSearch,
      showSwitchProfile:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      showSupportDonation: _supportDonation.hasProviders,
      pages: _settingsPages,
    );
  }

  Widget _buildLayout(BuildContext context) {
    return _SettingsLayout(
      connections: ConnectionsSummary(
        realDebrid: _rdInfo,
        torbox: _torboxInfo,
        premiumize: _premiumizeInfo,
        allDebrid: _allDebridInfo,
        pikpak: _pikpakInfo,
        webDav: _webDavInfo,
        iptv: _iptvInfo,
        trakt: _traktInfo,
        simkl: _simklInfo,
        tracking: _trackingInfo,
        // MDBList hidden for the alpha (unfinished) — see [kMdblistEnabled].
        mdblist: kMdblistEnabled ? _mdblistInfo : null,
        indexerManagers: _indexerManagersInfo,
        firstCardFocusNode: _firstCardFocusNode,
      ),
      onOpenSearch: _openSettingsSearch,
      pages: _settingsPages,
    );
  }

  Future<void> _openSettingsSearch() async {
    await pushSettingsPage(
      context,
      SettingsSearchPage(entries: _buildSearchIndex()),
    );
    if (!mounted) return;
    // A deep-linked page may have changed a connection/login; refresh so the
    // underlying settings surface is current when search closes.
    setState(() {});
  }

  /// Flat, searchable index of every settings destination. Built fresh on open
  /// so dynamic copy (download folder, update status, connection captions) and
  /// live toggle values are current. Navigable entries reuse the same
  /// `_openXxx` handlers the layouts wire, so actions never drift; toggle
  /// entries read/write the same state fields as their inline rows.
  ///
  /// Connection cards stay live [conn] entries so status/captions stay
  /// current. Everything else — pages, search-only destinations, and in-page
  /// leaves — is derived from [SettingsPageRegistry.searchIndex]. Trackers
  /// follow Connections so the two headings stay contiguous (see
  /// SettingsSearchPage first-appearance grouping).
  List<SettingsSearchEntry> _buildSearchIndex() {
    SettingsSearchEntry conn(
      ConnectionInfo info,
      List<String> keywords, {
      // Trakt/Simkl/MDBList now live under their own heading; search results
      // must say where the thing actually is.
      String category = 'Connections',
    }) => SettingsSearchEntry(
      icon: Icons.link_rounded,
      title: info.title,
      subtitle: info.caption,
      category: category,
      keywords: ['integration', ...keywords],
      onTap: info.onTap,
    );

    return [
      conn(_rdInfo, const [
        'debrid',
        'real-debrid',
        'rd',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_torboxInfo, const [
        'debrid',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_premiumizeInfo, const [
        'debrid',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_allDebridInfo, const [
        'debrid',
        'ad',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_pikpakInfo, const [
        'cloud',
        'storage',
        'login',
        'account',
        'email',
        'password',
        'logout',
        'change account',
        'remove account',
      ]),
      conn(_webDavInfo, const [
        'cloud',
        'nas',
        'server',
        'seedbox',
        'url',
        'username',
        'password',
        'app token',
      ]),
      conn(_iptvInfo, const [
        'live tv',
        'm3u',
        'playlist',
        'channels',
        'epg',
        'xtream',
      ]),
      conn(_indexerManagersInfo, const [
        'indexer',
        'torznab',
        'jackett',
        'prowlarr',
        'engines',
      ]),
      // Trackers — keep this block last in the Connections neighbourhood so
      // the two categories stay contiguous; see SettingsSearchPage.
      conn(_traktInfo, const [
        'scrobble',
        'sync',
        'watch history',
        'watchlist',
        'login',
        'activate',
        'device code',
        'logout',
      ], category: 'Trackers'),
      conn(_trackingInfo, const [
        'scrobble',
        'sync catalog',
        'watch progress',
        'continue watching source',
        'home ticks',
      ], category: 'Trackers'),
      conn(_simklInfo, const [
        'scrobble',
        'sync',
        'watch history',
        'login',
        'pin',
        'device code',
        'logout',
      ], category: 'Trackers'),
      if (kMdblistEnabled)
        conn(_mdblistInfo, const ['lists', 'ratings'], category: 'Trackers'),
      ..._settingsRegistry.searchIndex(),
    ];
  }

  Future<void> _openTorrentSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.torrentSearch)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const TorrentSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openIndexerManagersSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.torrentSearch)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const IndexerManagersSettingsPage());
    if (!mounted) return;

    final configs = await StorageService.getIndexerManagerConfigs(
      forSettings: true,
    );
    if (!mounted) return;
    setState(() {
      _indexerManagersConfigured = configs.isNotEmpty;
      _indexerManagersStatus = configs.isNotEmpty ? 'Active' : 'Not configured';
      _indexerManagersCaption = configs.isNotEmpty
          ? '${configs.length} engine${configs.length == 1 ? '' : 's'} configured'
          : 'Connect Jackett or Prowlarr';
    });
  }

  Future<void> _openDebrifyTvSettings() async {
    await pushSettingsPage(context, const DebrifyTvSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  /// Stremio TV's channel settings. The row lives on the Stremio TV screen
  /// (not in Settings), but the page is self-contained — search deep-links
  /// into it so "random episodes"/"rotation" are findable from Settings.
  Future<void> _openStremioTvSettings() async {
    await pushSettingsPage(context, const StremioTvSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openPikPakSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const PikPakSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openWebDavSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const WebDavSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openTraktSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const TraktSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openTrackingSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const TrackingSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openSimklSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const SimklSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openMdblistSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const MdblistSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  /// Phone/small-window chrome choice: classic bottom bar (default) vs the
  /// floating glass button. Applies live — MainPageBridge tells the shell.
  Future<void> _openNavigationSettings() async {
    final current = await AppStylePrefs.getPhoneNavStyle();
    if (!mounted) return;

    // The dialog RETURNS the choice; the write is awaited here before the
    // bridge fires. Popping first and writing unawaited (the old shape)
    // let an immediate pref re-read race the write.
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required String value,
        }) {
          final selected = current == value;
          return ListTile(
            leading: Icon(
              icon,
              color: selected ? const Color(0xFFC7BFFF) : null,
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            trailing: selected
                ? const Icon(Icons.check_rounded, color: Color(0xFFC7BFFF))
                : null,
            onTap: () => Navigator.of(dialogContext).pop(value),
          );
        }

        return AlertDialog(
          title: const Text('Navigation'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                icon: Icons.call_to_action_rounded,
                title: 'Classic bar',
                subtitle:
                    'Bottom tabs \u2014 Home, three slots you pick, More '
                    'holds the rest',
                value: 'classic',
              ),
              option(
                icon: Icons.blur_on_rounded,
                title: 'Floating button',
                subtitle: 'The glass button with the expanding menu',
                value: 'floating',
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || chosen == current || !mounted) return;
    await AppStylePrefs.setPhoneNavStyle(chosen);
    if (!mounted) return;
    setState(() => _phoneNavStyle = chosen);
    MainPageBridge.navPrefsChanged?.call();
  }

  Future<void> _openIptvSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const IptvSettingsPage());
    if (!mounted) return;
    // IPTV settings hosts its own Appearance/Player guide sections — keep
    // the Appearance row captions honest.
    await _reloadAppearanceSummaries();
  }

  Future<void> _openIptvChannelOrder() async {
    if (!await _ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const IptvChannelOrderPage());
  }

  /// IPTV settings landing on the add-source form — what a search for "add
  /// playlist" is actually after. Without the flag the wide (TV/desktop)
  /// layout opens its source rail instead, and the form is another hop away.
  Future<void> _openIptvAddSource() async {
    if (!await _ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!mounted) return;
    await pushSettingsPage(
      context,
      const IptvSettingsPage(openAddSource: true),
    );
    if (!mounted) return;
    // The two-pane reached from here still exposes the Appearance/Player
    // guide sections — keep the Appearance row captions honest.
    await _reloadAppearanceSummaries();
  }

  /// Live TV & DVR › Recordings — the same page IPTV settings and the
  /// recording dialogs open, promoted to a first-class settings row.
  Future<void> _openRecordings() async {
    if (!await _ensureProfileFeature(ProfileFeature.recordings)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const RecordingsPage());
  }

  Future<void> _openCollectionsSettings() async {
    await pushSettingsPage(context, const CollectionsSettingsPage());
  }

  Future<void> _openHomePageSettings() async {
    await pushSettingsPage(context, const HomePageSettingsPage());
    if (!mounted) return;
    // The Home Screen page hosts its own TV home layout row — keep the
    // Appearance row caption honest.
    await _reloadAppearanceSummaries();
  }

  Future<void> _openExternalPlayerSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.externalPlayers)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const ExternalPlayerSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openRemoteControl() async {
    if (!await _ensureProfileFeature(ProfileFeature.remoteControl)) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteRolePickerScreen()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openFilterSettings() async {
    await pushSettingsPage(context, const FilterSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProviderSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const ProviderSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openQuickPlaySettings() async {
    await pushSettingsPage(context, const QuickPlaySettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openDiscoverSettings() async {
    await pushSettingsPage(context, const DiscoverSettingsPage());
  }

  Future<void> _openRealDebridSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const RealDebridSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openTorboxSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const TorboxSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openPremiumizeSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const PremiumizeSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openAllDebridSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const AllDebridSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  void _focusFirstCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstCardFocusNode.requestFocus();
      }
    });
  }

  /// Route checks are defense in depth; services still validate their own
  /// capabilities. Keeping this helper fail-closed also protects search/deep
  /// links that call an opener while a policy edit is propagating.
  Future<bool> _ensureProfileFeature(ProfileFeature feature) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return true;
    }
    var allowed = false;
    try {
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      allowed = actor.allows(feature);
    } catch (_) {
      allowed = false;
    }
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This feature is disabled for this profile.'),
        ),
      );
    }
    return allowed;
  }

  Future<void> _afterBackupRestore() async {
    await _loadSummaries();
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _exportDiagnosticLogs() async {
    if (_exportingDiagnostics) return;
    if (!await _activeProfileMayExportDiagnostics()) {
      if (!mounted) return;
      setState(() => _diagnosticExportVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only an admin can export diagnostic logs.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _exportingDiagnostics = true);

    try {
      DiagnosticLog.instance.recordEvent(
        source: 'settings',
        event: 'diagnostic_export_requested',
      );
      final exported = await DiagnosticLog.instance.exportLastWindow();
      if (!mounted) return;

      if (kIsWeb) {
        final savedReference = await FilePicker.platform.saveFile(
          dialogTitle: 'Save diagnostic logs',
          fileName: exported.fileName,
          type: FileType.custom,
          allowedExtensions: const <String>['jsonl'],
          bytes: exported.bytes,
        );
        if (!mounted || savedReference == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${exported.entryCount} privacy-filtered diagnostic entries.',
            ),
          ),
        );
      } else {
        await ProfileBackupFlows(context).saveBackupFile(
          fileName: exported.fileName,
          bytes: exported.bytes,
          mimeType: 'application/x-ndjson',
          artifactLabel: 'diagnostic log',
        );
      }
      DiagnosticLog.instance.recordEvent(
        source: 'settings',
        event: 'diagnostic_export_saved',
        fields: <String, Object?>{'entries': exported.entryCount},
      );
    } catch (error, stackTrace) {
      DiagnosticLog.instance.recordError(
        source: 'settings',
        event: 'diagnostic_export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export diagnostic logs.')),
      );
    } finally {
      if (mounted) setState(() => _exportingDiagnostics = false);
    }
  }

  // Download location lives on DownloadLocationController (G2).
  Future<void> _clearDownloadData() async {
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear download data?'),
        content: const Text(
          'This removes queued entries and download history. Files already saved to disk stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService.instance.clearDownloadDatabase();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download data cleared')));
    }
  }

  Future<void> _clearPlaybackData() async {
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear playback data?'),
        content: const Text(
          'This resets resume positions and cached playback preferences.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PlaybackProgressStore.clearAllPlaybackData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Playback data cleared')));
    }
  }

  Future<void> _resetAppData() async {
    final profileMode =
        ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted;
    ProfileAuthorizationContext? authorization;
    UserProfile? actor;
    if (profileMode) {
      authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      actor = await authorization.validate(ProfileBootstrap.registry);
    }
    final mayResetDevice =
        actor?.role == UserProfileRole.admin &&
        actor!.allows(ProfileFeature.manageProfiles) &&
        actor.allows(ProfileFeature.backupRestore);
    final action = await showSettingsDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profileMode ? 'Reset this profile?' : 'Reset Debrify?'),
        content: Text(
          profileMode
              ? 'This clears this profile\'s settings, history, playlists, and private app data. The profile, PIN, shared connections, active jobs, downloads, and recordings remain untouched.'
              : 'This removes saved connections, playback history, download queue, and onboarding completion. Files already saved to disk remain untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (mayResetDevice)
            TextButton(
              onPressed: () => Navigator.of(context).pop('device'),
              child: const Text('Reset device…'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('profile'),
            child: Text(profileMode ? 'Reset profile' : 'Reset app'),
          ),
        ],
      ),
    );

    if (action == null) return;

    if (profileMode && action == 'device') {
      if (!await ProfileBackupFlows(
        context,
      ).reauthenticateSensitiveProfile(actor!)) {
        return;
      }
      final typed = TextEditingController();
      final confirmed = await showSettingsDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Reset this Debrify installation?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All profiles, connections, jobs, schedules, private data, remote pairings, and device keys will be removed. Downloaded and recorded files remain on disk. The app will close and start fresh next launch.',
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: typed,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Reset device',
                  decoration: const InputDecoration(
                    labelText: 'Type RESET to continue',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (typed.text == 'RESET') {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: typed.text == 'RESET'
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Reset device'),
              ),
            ],
          ),
        ),
      );
      typed
        ..clear()
        ..dispose();
      if (confirmed != true) return;
      await ProfileDeviceResetService.reset(
        registry: ProfileBootstrap.registry,
        authorization: authorization!,
      );
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        exit(0);
      }
      await SystemNavigator.pop();
      return;
    }

    if (profileMode && action == 'profile') {
      await ProfileResetService(
        registry: ProfileBootstrap.registry,
        lifecycleParticipants: <ProfileLifecycleParticipant>[
          ProfileAppLifecycleParticipant(),
        ],
      ).resetActiveProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile data reset. Connections and files were kept.'),
        ),
      );
      await _loadSummaries();
      return;
    }

    await StorageService.deleteApiKey();
    AccountService.clearUserInfo();
    await StorageService.deleteTorboxApiKey();
    TorboxAccountService.clearUserInfo();
    await StorageService.deletePremiumizeApiKey();
    await StorageService.deleteAllDebridApiKey();
    AllDebridAccountService.clearUserInfo();
    await ProviderCredentialPrefs.clearPikPakAuth();
    await ProviderCredentialPrefs.clearWebDav();
    await TrackingPrefs.clearTraktAuth();
    // Clears the token + username AND the in-memory library cache.
    await SimklService.instance.logout();
    // Clears the key + username AND the in-memory list/items cache.
    await MdblistService.instance.logout();
    await DownloadService.instance.clearDownloadDatabase();
    await PlaybackProgressStore.clearAllPlaybackData();
    await PlaybackProgressStore.clearContinueWatching();
    await PlaybackProgressStore.clearPlaylist();
    await PlaybackProgressStore.clearAllPlaylistMetadata();
    await MyWatchlistStore.clearMyWatchlist();
    await TorrentSearchHistoryStore.clearTorrentSearchHistory();
    await StorageService.clearAllStartupSettings();
    await HomePrefs.clearAllHomePageSettings();
    await ProviderCredentialPrefs.clearAllIntegrationStates();
    await DebrifyTvPrefs.clearDebrifyTvProviderAndLegacy();
    await StorageService.clearAllFilterSettings();
    await StorageService.clearAllTorrentEngineSettings();
    await ProviderCredentialPrefs.clearAllPostTorrentActions();
    await DebrifyTvPrefs.clearAllDebrifyTvSettings();
    await DebrifyTvRepository.instance.clearAll();
    await StremioService.instance.clearAllAddons();
    await StorageService.setInitialSetupComplete(false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App data reset. You can reconnect services anytime.'),
      ),
    );

    await _loadSummaries();
  }

  Future<void> _checkForAppUpdates() async {
    if (_checkingUpdates) return;
    if (_currentVersionName.isEmpty) return;
    await DeviceMaintenancePrefs.setIgnoredUpdateVersion(null);

    setState(() {
      _checkingUpdates = true;
      _updateSubtitle = 'Checking GitHub releases...';
    });

    try {
      final summary = await UpdateService.checkForUpdates(
        currentVersion: _currentVersionName,
      );
      if (!mounted) return;
      setState(() {
        _updateSubtitle = summary.updateAvailable
            ? 'Update available (${summary.release.versionLabel})'
            : 'You are on the latest build';
        _checkingUpdates = false;
      });
      await _showReleaseDetails(summary);
    } on UpdateException catch (err) {
      _showSnack(err.message);
      if (mounted) {
        setState(() {
          _updateSubtitle = 'Unable to reach GitHub releases';
          _checkingUpdates = false;
        });
      }
    } catch (_) {
      _showSnack('Could not check for updates. Please try again later.');
      if (mounted) {
        setState(() {
          _updateSubtitle = 'Unable to reach GitHub releases';
          _checkingUpdates = false;
        });
      }
    }
  }

  Future<void> _showReleaseDetails(UpdateSummary summary) async {
    final app = AppThemeScope.of(context);
    if (!mounted) return;
    final release = summary.release;
    final theme = Theme.of(context);
    final bool isAndroidDevice = !kIsWeb && Platform.isAndroid;
    final bool canInstallDirectly =
        summary.updateAvailable &&
        isAndroidDevice &&
        release.androidApkAsset != null;
    final String latestLabel = release.versionLabel.isNotEmpty
        ? release.versionLabel
        : 'Latest release';
    final String notes = release.body.trim().isNotEmpty
        ? release.body.trim()
        : 'Release notes will appear here once published.';
    final String? publishedLabel = release.publishedAt != null
        ? DateFormat.yMMMd().format(release.publishedAt!.toLocal())
        : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final baseTheme = Theme.of(sheetContext);
        final textTheme = baseTheme.textTheme;
        final Color bodyColor = app.fade(app.core.tx, 0.85);
        final markdownStyle = MarkdownStyleSheet.fromTheme(baseTheme).copyWith(
          h1: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: app.core.tx,
          ),
          h2: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: app.core.tx,
          ),
          h3: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: app.core.tx,
          ),
          p: textTheme.bodyMedium?.copyWith(color: bodyColor, height: 1.45),
          strong: const TextStyle(fontWeight: FontWeight.w700),
          listBullet: textTheme.bodyMedium?.copyWith(color: bodyColor),
          blockquote: textTheme.bodyMedium?.copyWith(
            color: app.fade(app.core.tx, 0.7),
          ),
        );
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.2),
                        borderRadius: app.shape.br(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    summary.updateAvailable
                        ? 'Update available'
                        : 'You are up to date',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Installed: $_appVersion',
                    style: textTheme.bodyMedium?.copyWith(
                      color: app.fade(app.core.tx, 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Latest: $latestLabel',
                    style: textTheme.bodyMedium?.copyWith(
                      color: app.fade(app.core.tx, 0.6),
                    ),
                  ),
                  if (publishedLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Published $publishedLabel',
                      style: textTheme.bodySmall?.copyWith(
                        color: app.fade(app.core.tx, 0.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Release notes',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: notes,
                        selectable: true,
                        onTapLink: (text, href, title) {
                          if (href == null) return;
                          final uri = Uri.tryParse(href);
                          if (uri != null) {
                            launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        styleSheet: markdownStyle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (canInstallDirectly)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _startAndroidUpdateDownload(release);
                          },
                          icon: const Icon(Icons.system_update_alt_rounded),
                          label: const Text('Download & Install'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openReleasesPage(release.htmlUrl);
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open Releases Page'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleAutoUpdateChecks(bool enabled) async {
    setState(() {
      _autoUpdateChecksEnabled = enabled;
    });
    await DeviceMaintenancePrefs.setUpdateAutoCheckEnabled(enabled);
  }

  Future<void> _toggleTvKeyboard(bool enabled) async {
    setState(() {
      _tvKeyboardEnabled = enabled;
    });
    await StorageService.setTvKeyboardEnabled(enabled);
  }

  /// The page writes the pref itself (and says a restart is needed — the
  /// engine is built with the factor in MainActivity.onCreate); re-read it on
  /// the way back so the rail row's caption matches.
  Future<void> _openTvScreenSize() async {
    await pushSettingsPage(context, const TvScreenSizePage());
    if (!mounted) return;
    final percent = await StorageService.getTvUiScalePercent();
    if (!mounted) return;
    setState(() {
      _tvUiScalePercent = percent;
    });
  }

  /// Same contract as [_openTvScreenSize] — MainActivity reads the render
  /// pref in `onCreate` too, so the page owns the write and the restart
  /// notice; we only re-read for the row's caption.
  Future<void> _openTvRenderQuality() async {
    await pushSettingsPage(context, const TvRenderQualityPage());
    if (!mounted) return;
    final quality = await StorageService.getTvRenderQuality();
    if (!mounted) return;
    setState(() {
      _tvRenderQuality = quality;
    });
  }

  Future<void> _openTvHeroArtworkQuality() async {
    await pushSettingsPage(context, const TvHeroArtworkQualityPage());
    if (!mounted) return;
    final quality = await StorageService.getTvHeroArtworkQuality();
    if (!mounted) return;
    setState(() {
      _tvHeroArtworkQuality = quality;
    });
  }

  /// The page writes the pref and live-applies via MainPageBridge; re-read it
  /// on the way back so the rail row's caption matches.
  Future<void> _openTvHomeStyle() async {
    await pushSettingsPage(context, const TvHomeStylePage());
    if (!mounted) return;
    final style = await StorageService.getTvHomeStyle();
    if (!mounted) return;
    setState(() {
      _tvHomeStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the Discover layout picker.
  Future<void> _openDiscoverLayout() async {
    await pushSettingsPage(context, const DiscoverLayoutPage());
    if (!mounted) return;
    final layout = await StorageService.getDiscoverLayout();
    if (!mounted) return;
    setState(() {
      _discoverLayout = layout;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the sidebar chrome picker.
  Future<void> _openTvSidebarStyle() async {
    await pushSettingsPage(context, const TvSidebarStylePage());
    if (!mounted) return;
    final style = await StorageService.getTvSidebarStyle();
    if (!mounted) return;
    setState(() {
      _tvSidebarStyle = style;
    });
  }

  /// Same contract, for the desktop/tablet sidebar picker.
  Future<void> _openDesktopSidebarStyle() async {
    await pushSettingsPage(context, const DesktopSidebarStylePage());
    if (!mounted) return;
    final style = await AppStylePrefs.getDesktopSidebarStyle();
    if (!mounted) return;
    setState(() {
      _desktopSidebarStyle = style;
    });
  }

  Future<void> _openSidebarCustomization() async {
    await pushSettingsPage(context, const SidebarCustomizationPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProfileAppearance() async {
    await pushSettingsPage(context, const ProfileAppearancePage());
    if (!mounted) return;
    await ProfileGateStyle.warm();
    if (mounted) setState(() {});
  }

  /// Same contract as [_openTvHomeStyle], for the IPTV page look picker.
  Future<void> _openIptvStylePage() async {
    await pushSettingsPage(context, const IptvStylePage());
    if (!mounted) return;
    final style = await StorageService.getIptvStyle();
    if (!mounted) return;
    setState(() {
      _iptvStyle = style;
    });
  }

  Future<void> _openDebrifyTvStylePage() async {
    await pushSettingsPage(context, const DebrifyTvStylePage());
    if (!mounted) return;
    final style = await StorageService.getDebrifyTvStyle();
    if (!mounted) return;
    setState(() {
      _debrifyTvStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the in-player guide picker.
  Future<void> _openPlayerGuideStylePage() async {
    await pushSettingsPage(context, const PlayerGuideStylePage());
    if (!mounted) return;
    final style = await StorageService.getIptvPlayerGuideStyle();
    if (!mounted) return;
    setState(() {
      _playerGuideStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the play loader look. Also
  /// re-warms the synchronous mirror the play path reads, so a change picked
  /// here applies to the very next play.
  Future<void> _openPlayLoaderStylePage() async {
    await pushSettingsPage(context, const PlayLoaderStylePage());
    if (!mounted) return;
    await PlayLoaderStyleController.warm();
    if (!mounted) return;
    setState(() {
      _playLoaderStyle = PlayLoaderStyleController.cached;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the native TV control skin.
  Future<void> _openTvPlayerControlsStylePage() async {
    await pushSettingsPage(context, const TvPlayerControlsStylePage());
    if (!mounted) return;
    final style = await StorageService.getTvPlayerControlsStyle();
    if (!mounted) return;
    setState(() {
      _tvPlayerControlsStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the Debrify TV playback screen.
  Future<void> _openDebrifyTvPlayerStylePage() async {
    await pushSettingsPage(context, const DebrifyTvPlayerStylePage());
    if (!mounted) return;
    final style = await StorageService.getDebrifyTvPlayerStyle();
    if (!mounted) return;
    setState(() {
      _debrifyTvPlayerStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the player control dock.
  Future<void> _openPlayerDockPage() async {
    await pushSettingsPage(context, const PlayerDockPage());
    if (!mounted) return;
    final style = await StorageService.getPlayerDockStyle();
    final palette = await StorageService.getPlayerDockPalette();
    final size = await StorageService.getPlayerDockSize();
    if (!mounted) return;
    setState(() {
      _playerDockStyle = style;
      _playerDockPalette = palette;
      _playerDockSize = size;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the details-page layout picker.
  Future<void> _openDetailPageStylePage() async {
    await pushSettingsPage(context, const DetailPageStylePage());
    if (!mounted) return;
    final style = await AppStylePrefs.getDetailPageStyle();
    if (!mounted) return;
    setState(() {
      _detailPageStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the details-page theme picker.
  Future<void> _openDetailThemePage() async {
    await pushSettingsPage(context, const DetailThemePage());
    if (!mounted) return;
    final theme = await AppStylePrefs.getDetailTheme();
    if (!mounted) return;
    setState(() {
      _detailTheme = theme;
    });
  }

  /// Appearance → Theme Lab. The setState on return covers the feedback
  /// toggles the lab hosts — their values are read from the synchronous
  /// mirrors, so one rebuild is the whole refresh.
  Future<void> _openThemeLab() async {
    await pushSettingsPage(context, const ThemeLabPage());
    if (!mounted) return;
    setState(() {});
  }

  /// Appearance → Looks. Re-reads nothing on return: the row's subtitle is
  /// COMPUTED from the live prefs (`AppLooks.active()`), so one setState is
  /// the whole refresh — there is no stored "current Look" that could drift.
  Future<void> _openLooksPage() async {
    await pushSettingsPage(context, const LooksPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openThemeTokensPage() async {
    await pushSettingsPage(context, const ThemeTokensPage());
    if (!mounted) return;
    setState(() {});
  }

  /// How many tokens have been taken over, or the invitation when none have.
  ///
  /// Computed from the live overrides rather than stored, for the same reason
  /// `AppLooks.active()` is: there is nothing to keep in sync and no way for a
  /// remembered answer to go stale.
  String get _themeTokensLabel {
    final n = AppThemeController.instance.overrides.count;
    if (n == 0) return 'Colour, shape, motion — one token at a time';
    return '$n ${n == 1 ? "token" : "tokens"} changed';
  }

  Future<void> _openAppThemePage() async {
    await pushSettingsPage(context, const AppThemePage());
    if (!mounted) return;
    final theme = await AppStylePrefs.getDetailTheme();
    if (!mounted) return;
    setState(() {
      _detailTheme = theme;
    });
  }

  Future<void> _openParentsGuideStylePage() async {
    await pushSettingsPage(context, const ParentsGuideStylePage());
    if (!mounted) return;
    final style = await AppStylePrefs.getParentsGuideStyle();
    if (!mounted) return;
    setState(() {
      _parentsGuideStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the text brightness picker.
  Future<void> _openTextBrightnessPage() async {
    await pushSettingsPage(context, const TextBrightnessPage());
    if (!mounted) return;
    final value = await AppStylePrefs.getTextBrightness();
    if (!mounted) return;
    setState(() {
      _textBrightness = value;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the launch ident picker.
  Future<void> _openLaunchAnimationPage() async {
    await pushSettingsPage(context, const LaunchAnimationPage());
    if (!mounted) return;
    final value = await AppStylePrefs.getLaunchAnimation();
    if (!mounted) return;
    setState(() {
      _launchAnimation = value;
    });
  }

  /// The Appearance rows quote live pref labels, but three of those prefs
  /// also have feature-local editors (the Home Screen page's layout row, the
  /// IPTV page's Appearance/Player guide sections). Re-read JUST those after
  /// any route that can reach them, so the captions never go stale. Never
  /// the full [_loadSummaries] — this is three pref reads, no network.
  Future<void> _reloadAppearanceSummaries() async {
    final tvHomeStyle = await StorageService.getTvHomeStyle();
    final iptvStyle = await StorageService.getIptvStyle();
    final playerGuideStyle = await StorageService.getIptvPlayerGuideStyle();
    final playLoaderStyle = await StorageService.getPlayLoaderStyle();
    final tvPlayerControlsStyle =
        await StorageService.getTvPlayerControlsStyle();
    final debrifyTvStyle = await StorageService.getDebrifyTvStyle();
    if (!mounted) return;
    setState(() {
      _tvHomeStyle = tvHomeStyle;
      _iptvStyle = iptvStyle;
      _playerGuideStyle = playerGuideStyle;
      _playLoaderStyle = playLoaderStyle;
      _tvPlayerControlsStyle = tvPlayerControlsStyle;
      _debrifyTvStyle = debrifyTvStyle;
    });
  }

  Future<void> _startAndroidUpdateDownload(AppRelease release) async {
    if (kIsWeb) {
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    if (!Platform.isAndroid) {
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    if (_updateDownloadTaskId != null) {
      _showSnack('An update download is already running.');
      return;
    }
    final asset = release.androidApkAsset;
    if (asset == null) {
      _showSnack('No Android APK is attached to this release yet.');
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    final hasPermission = await _ensureInstallPermission();
    if (!hasPermission) return;

    if (mounted) {
      setState(() {
        _updateSubtitle = 'Downloading ${release.versionLabel}...';
      });
    }

    String? taskId;
    const mime = 'application/vnd.android.package-archive';
    try {
      taskId = await AndroidNativeDownloader.startUpdate(
        url: asset.downloadUrl.toString(),
        fileName: asset.name.isNotEmpty
            ? asset.name
            : 'Debrify-${release.versionLabel}.apk',
        subDir: 'Debrify/Updates',
        mimeType: mime,
      );
    } catch (_) {
      taskId = null;
    }

    if (taskId == null) {
      _showSnack(
        'Could not start the update download. Please try again later.',
      );
      if (mounted) {
        setState(() {
          _updateSubtitle = 'Download failed to start';
        });
      }
      return;
    }

    _updateDownloadTaskId = taskId;
    _updateDownloadSub?.cancel();
    _updateDownloadSub = AndroidNativeDownloader.events.listen((event) async {
      final String eventTaskId = (event['taskId'] ?? '').toString();
      if (eventTaskId != _updateDownloadTaskId) return;
      final type = event['type']?.toString();
      if (type == 'complete') {
        final contentUri = (event['contentUri'] ?? '').toString();
        final eventMime = (event['mimeType'] ?? '').toString().isNotEmpty
            ? (event['mimeType'] ?? '').toString()
            : mime;
        try {
          _showSnack('Update downloaded. Opening installer...');
          if (contentUri.isNotEmpty) {
            final ok = await AndroidNativeDownloader.openContentUri(
              contentUri,
              eventMime,
            );
            if (!ok) {
              _showSnack('Installer was opened from Downloads instead.');
            }
          }
        } catch (_) {
          _showSnack(
            'Could not launch the installer. Check your Downloads app.',
          );
        } finally {
          _clearUpdateDownloadListener();
          if (mounted) {
            setState(() {
              _updateSubtitle = 'Installer ready for ${release.versionLabel}';
            });
          }
        }
      } else if (type == 'error' || type == 'canceled') {
        _showSnack('Update download did not finish. Please try again.');
        _clearUpdateDownloadListener();
        if (mounted) {
          setState(() {
            _updateSubtitle = 'Download failed';
          });
        }
      }
    });

    _showSnack(
      'Downloading the update in the background. Check notifications for progress.',
    );
  }

  Future<bool> _ensureInstallPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final currentStatus = await Permission.requestInstallPackages.status;
    if (currentStatus.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied || result.isRestricted) {
      _showSnack('Allow Debrify to install apps from your settings.');
      unawaited(openAppSettings());
    } else {
      _showSnack('Permission required to install the downloaded update.');
    }
    return false;
  }

  Future<void> _openReleasesPage(Uri url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showSnack('Unable to open the releases page right now.');
    }
  }

  void _clearUpdateDownloadListener() {
    _updateDownloadSub?.cancel();
    _updateDownloadSub = null;
    _updateDownloadTaskId = null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  DateTime? _tryParseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

final List<SettingsCategoryDefinition> _kAdaptiveSettingsCategories = [
  for (final c in kSettingsCategories) c.toDesktop(),
];

class _SettingsLayout extends StatelessWidget {
  final ConnectionsSummary connections;
  final VoidCallback onOpenSearch;
  final List<SettingsPageSpec> pages;

  const _SettingsLayout({
    required this.connections,
    required this.onOpenSearch,
    this.pages = const [],
  });

  List<Widget> _phoneCategory(SettingsCategorySpec cat, Color danger) {
    final kids = buildSettingsCategoryChildren(
      registry: SettingsPageRegistry(pages: pages),
      surface: SettingsLayoutSurface.phone,
      category: cat.label,
      accentColor: cat.destructive
          ? danger.withValues(alpha: 0.85)
          : null,
    );
    if (kids.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      ...kids,
    ];
  }

  List<ConnectionInfo> get _providerConnections => [
    connections.realDebrid,
    connections.torbox,
    connections.premiumize,
    connections.allDebrid,
    connections.pikpak,
    connections.webDav,
    connections.indexerManagers,
    connections.iptv,
  ];

  List<ConnectionInfo> get _trackerServices => [
    connections.trakt,
    connections.simkl,
    if (connections.mdblist != null) connections.mdblist!,
  ];

  Widget _buildSpotlight(BuildContext context) {
    final attention = _providerConnections.where(
      settingsConnectionNeedsAttention,
    );
    final attentionCount = attention.length;
    final readyCount = _providerConnections
        .where(settingsConnectionIsReady)
        .length;
    final firstAttention = attention.isEmpty ? null : attention.first;
    final summaryTone = attentionCount == 0
        ? SettingsSummaryTone.good
        : SettingsSummaryTone.attention;
    final summaryTitle = attentionCount > 0
        ? '$attentionCount connection${attentionCount == 1 ? '' : 's'} need attention.'
        : readyCount > 0
        ? 'Everything connected looks ready.'
        : 'Connect a playback service.';
    final summarySubtitle = attentionCount > 0
        ? '${firstAttention!.title} reports ${firstAttention.status.toLowerCase()}. '
              'Review it before your next playback.'
        : readyCount > 0
        ? '$readyCount services are configured on this device.'
        : 'Add a debrid, cloud, or IPTV service to get started.';
    final summaryTarget = firstAttention ?? _providerConnections.first;
    return SettingsSpotlightShell(
      categories: _kAdaptiveSettingsCategories,
      onOpenSearch: onOpenSearch,
      compactSummary: SettingsSpotlightSummaryCard(
        eyebrow: attentionCount > 0 ? 'Connection check' : 'Service health',
        title: summaryTitle,
        subtitle: summarySubtitle,
        actionLabel: attentionCount > 0
            ? 'Review ${summaryTarget.title}'
            : readyCount > 0
            ? 'Manage connections'
            : 'Connect a service',
        tone: summaryTone,
        onTap: () => unawaited(summaryTarget.onTap()),
      ),
      categoryBuilder: _buildSpotlightCategory,
    );
  }

  Widget _buildConnectionGrid(
    BuildContext context,
    List<ConnectionInfo> items, {
    bool singleFullWidth = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >= 680 &&
            !(singleFullWidth && items.length == 1);
        final width = twoColumns
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final info in items)
              SizedBox(
                width: width,
                child: ConnectionCard(info: info, isLeftColumn: false),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSpotlightCategory(BuildContext context, int category) {
    final t = AppThemeScope.of(context).settings;
    switch (category) {
      case 0:
        return _buildConnectionGrid(context, _providerConnections);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionLabel('Tracking'),
            _buildConnectionGrid(context, [
              connections.tracking,
            ], singleFullWidth: true),
            const SizedBox(height: 22),
            const SettingsSectionLabel('Tracker services'),
            _buildConnectionGrid(context, _trackerServices),
          ],
        );
      default:
        if (category < 0 || category >= kSettingsCategories.length) {
          return const SizedBox.shrink();
        }
        final label = kSettingsCategories[category].label;
        final kids = buildSettingsCategoryChildren(
          registry: SettingsPageRegistry(pages: pages),
          surface: SettingsLayoutSurface.desktop,
          category: label,
          accentColor: label == 'Danger Zone' ? t.danger : null,
        );
        if (kids.isEmpty && label == 'Profiles') {
          return SettingsSection(
            title: '',
            children: [
              SettingsTile.spec(
                SettingsRowContent(
                  icon: Icons.info_outline_rounded,
                  title: 'Profiles unavailable',
                  subtitle: ProfileBootstrap.legacyReasonSummary
                      .split('\n')
                      .first,
                ),
                onTap: () => showLegacyModeInfoDialog(context),
              ),
            ],
          );
        }
        if (kids.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: kids,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    if (app.id == 'spotlight') return _buildSpotlight(context);
    final t = app.settings;
    return SettingsBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsHeader(),
                const SizedBox(height: 18),
                _SettingsSearchBar(onTap: onOpenSearch),
                const SizedBox(height: 24),
                // Connections section with cards
                connections,
                ...[
                  for (final cat in kSettingsCategories)
                    if (cat.id != 'connections' && cat.id != 'trackers')
                      ..._phoneCategory(cat, t.danger),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable search affordance on the phone/desktop settings root. Looks like a
/// search field but opens the dedicated [SettingsSearchPage] (which owns the
/// live field) so the root layout stays a cheap StatelessWidget.
class _SettingsSearchBar extends StatefulWidget {
  final VoidCallback onTap;
  const _SettingsSearchBar({required this.onTap});

  @override
  State<_SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<_SettingsSearchBar> {
  final FocusNode _node = FocusNode(debugLabel: 'settingsSearchBar');
  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final bool lit = _focused || _hovered;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        focusNode: _node,
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onFocusChange: (_) => setState(() {}),
        onHover: (h) => setState(() => _hovered = h),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: lit ? t.panel2 : t.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? t.accent : t.line,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: lit ? t.accent2 : t.dim,
              ),
              const SizedBox(width: 12),
              Text(
                'Search settings',
                style: TextStyle(fontSize: 13.5, color: t.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
