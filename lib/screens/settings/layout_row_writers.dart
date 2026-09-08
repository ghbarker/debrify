import 'package:debrify/services/storage/app_style_prefs.dart';

import '../../services/main_page_bridge.dart';
import '../../services/play_loader_style.dart';
import '../../services/storage_service.dart';
import '../../theme/app_looks.dart';
import '../profiles/profile_wall_screen.dart';

/// The write path behind each inline Screen-layouts row.
///
/// Each method is the opener page's `_select` body, verbatim in effect: the
/// same setter, the same `LookApplier.noteExternalWrite` (so an in-flight
/// Look apply does not stamp over a human's choice — see
/// `theme/app_looks.dart`) and the same `MainPageBridge` live-apply hook.
/// Kept in one place so the row and the page cannot drift apart, and so a
/// test can prove that choosing inline writes exactly one pref.
///
/// Where a page did NOT note the external write although the key is a Look
/// key (phone nav, desktop sidebar), the note is added here: it is purely
/// protective and the Looks page writes those keys too.
abstract final class LayoutRowWriters {
  static Future<void> detailPageStyle(String value) async {
    LookApplier.noteExternalWrite('detail_page_style');
    await AppStylePrefs.setDetailPageStyle(value);
  }

  static Future<void> tvHomeStyle(String value) async {
    LookApplier.noteExternalWrite('tv_home_style');
    await StorageService.setTvHomeStyle(value);
    // Live-apply: the Home board re-reads the pref and rebuilds.
    MainPageBridge.tvHomeStyleChanged?.call();
  }

  static Future<void> discoverLayout(String value) async {
    LookApplier.noteExternalWrite('discover_layout');
    await StorageService.setDiscoverLayout(value);
    // Live-apply: the Discover tab re-reads the pref and rebuilds.
    MainPageBridge.discoverLayoutChanged?.call();
  }

  static Future<void> tvSidebarStyle(String value) async {
    LookApplier.noteExternalWrite('tv_sidebar_style');
    await StorageService.setTvSidebarStyle(value);
    // Live-apply: the app shell re-reads the pref and reskins the rail.
    MainPageBridge.tvSidebarStyleChanged?.call();
  }

  static Future<void> desktopSidebarStyle(String value) async {
    LookApplier.noteExternalWrite('desktop_sidebar_style');
    await AppStylePrefs.setDesktopSidebarStyle(value);
    // Live-apply: the shell re-reads the pref and swaps the chrome.
    MainPageBridge.desktopSidebarStyleChanged?.call();
  }

  static Future<void> phoneNavStyle(String value) async {
    LookApplier.noteExternalWrite('phone_nav_style');
    await AppStylePrefs.setPhoneNavStyle(value);
    MainPageBridge.navPrefsChanged?.call();
  }

  static Future<void> iptvStyle(String value) async {
    LookApplier.noteExternalWrite('iptv_style');
    await StorageService.setIptvStyle(value);
  }

  static Future<void> debrifyTvStyle(String value) async {
    LookApplier.noteExternalWrite('debrify_tv_style');
    await StorageService.setDebrifyTvStyle(value);
  }

  static Future<void> playerGuideStyle(String value) =>
      StorageService.setIptvPlayerGuideStyle(value);

  static Future<void> playLoaderStyle(String value) =>
      PlayLoaderStyleController.select(value);

  static Future<void> playerDockStyle(String value) =>
      StorageService.setPlayerDockStyle(value);

  static Future<void> parentsGuideStyle(String value) async {
    LookApplier.noteExternalWrite('parents_guide_style');
    await AppStylePrefs.setParentsGuideStyle(value);
  }

  static Future<void> profileGateStyle(String value) =>
      ProfileGateStyle.set(value);
}
