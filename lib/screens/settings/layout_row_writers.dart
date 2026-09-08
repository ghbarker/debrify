import 'package:debrify/services/storage/app_style_prefs.dart';

import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../theme/app_looks.dart';

/// The write path behind each inline Screen-layouts row.
///
/// Each method is the opener page's `_select` body, verbatim in effect: the
/// same setter, the same `LookApplier.noteExternalWrite` (so an in-flight
/// Look apply does not stamp over a human's choice — see
/// `theme/app_looks.dart`) and the same `MainPageBridge` live-apply hook.
/// Kept in one place so the row and the page cannot drift apart, and so a
/// test can prove that choosing inline writes exactly one pref.
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
}
