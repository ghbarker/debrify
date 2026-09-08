import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:debrify/services/storage/app_style_prefs.dart';
import '../utils/platform_util.dart';

/// How much a television is allowed to move (Appearance → TV motion).
///
/// Every TV focus site runs on one shared tempo (`AppMotion.tvFocus`), and the
/// figure that tempo should be is a property of the BOX, not of a theme: a
/// Shield renders a 220ms eased cursor without dropping a frame, and the same
/// tween on an Amlogic stick is exactly the lag the short beat was chosen to
/// avoid. After the shared beat landed at 120ms the Shield owner's verdict was
/// "everything just feels so snappy instead of smooth" — and, earlier, "my
/// settings may not be for everyone". So: two profiles, a per-device default,
/// and a row to override it.
///
/// Off a television the profile is irrelevant — pointer surfaces keep the
/// theme's `base` and `standard` — so a phone never reads it.
enum TvMotionProfile {
  /// Longer, eased focus and page motion. The pointer surfaces' tempo
  /// (`base`, 220ms legacy) with the theme's `emphasized` curve on transforms,
  /// a ~260ms scroll-follow, shared-axis route transitions and the theme's
  /// entrance choreography — for Shield-class boxes.
  smooth(
    'smooth',
    'Smooth',
    'Longer, eased focus and page motion — for Shield-class boxes',
  ),

  /// The shipped TV figures: the short `fast` beat, an instant scroll-follow,
  /// the fast route fade and no entrance reveal — for low-power boxes.
  snappy(
    'snappy',
    'Snappy',
    'Instant focus, minimal motion — for low-power boxes',
  );

  const TvMotionProfile(this.value, this.label, this.blurb);

  /// The stored pref value (`tv_motion_profile`).
  final String value;

  /// Chip caption.
  final String label;

  /// One-line row blurb.
  final String blurb;

  /// Null for anything that is not a known spelling — the caller falls back
  /// to the device default, never to a fixed profile.
  static TvMotionProfile? fromPref(String? value) => switch (value) {
    'smooth' => smooth,
    'snappy' => snappy,
    _ => null,
  };

  /// The device default, as a pure function of what the box reports.
  ///
  /// Apple TV: smooth — every generation the app supports runs the tvOS
  /// spring already. Android TV: smooth on the NVIDIA Shield (any of
  /// manufacturer, model, board or the user-visible device name naming it —
  /// the model is "SHIELD Android TV", the boards `darcy`/`mdarcy`/`foster`/
  /// `sif`, and a factory device name is plain "SHIELD"), snappy on every
  /// other box — Chromecast, Fire TV, Mi Box and the Amlogic panels are the
  /// hardware the short beat was measured on. Not a TV: snappy, and unread.
  static TvMotionProfile defaultFor({
    required bool isTvOs,
    required bool isAndroidTv,
    String? manufacturer,
    String? model,
    String? board,
    String? hardware,
    String? deviceName,
  }) {
    if (isTvOs) return smooth;
    if (!isAndroidTv) return snappy;
    final maker = (manufacturer ?? '').toLowerCase();
    if (maker.contains('nvidia')) return smooth;
    for (final s in [model, board, hardware, deviceName]) {
      final lower = (s ?? '').toLowerCase();
      if (lower.contains('shield')) return smooth;
      if (kShieldBoards.contains(lower)) return smooth;
    }
    return snappy;
  }

  /// `Build.BOARD` / `Build.HARDWARE` spellings of the Shield family.
  static const Set<String> kShieldBoards = {'darcy', 'mdarcy', 'foster', 'sif'};
}

/// Owns the live profile. `AppMotion.of` reads it through `TvMotionScope`, an
/// inherited widget the root rebuilds when [notifier] fires, so a chip press
/// retargets every focus tween on the spot — the same propagation the
/// text-brightness preset uses.
abstract final class TvMotionController {
  /// Snappy until [warm] resolves: the shipped TV behaviour, so a site that
  /// reads before the warm lands (or a test that never warms) sees exactly
  /// what it saw before this preference existed.
  static final ValueNotifier<TvMotionProfile> notifier =
      ValueNotifier<TvMotionProfile>(TvMotionProfile.snappy);

  static TvMotionProfile get current => notifier.value;

  /// True when the profile in force is the user's own choice rather than the
  /// device default.
  static bool get isExplicit => _explicit;
  static bool _explicit = false;

  /// The device default, detected once per process. Detection is two plugin
  /// calls that cannot change while the app runs.
  static TvMotionProfile? _deviceDefault;

  /// Load the stored choice, or resolve the device default when there is
  /// none. Called in main() before runApp and again on every profile switch
  /// (the pref is per profile; the device default is not). Swallows storage
  /// and plugin failures: a cosmetic pref must never keep the app from
  /// starting, and the notifier already holds the safe (snappy) value.
  static Future<void> warm() async {
    try {
      final stored = TvMotionProfile.fromPref(
        await AppStylePrefs.getTvMotionProfile(),
      );
      _explicit = stored != null;
      notifier.value = stored ?? await deviceDefault();
    } catch (e) {
      debugPrint('TvMotionController: warm failed, staying snappy: $e');
    }
  }

  /// The profile this box gets when the user has not chosen. Memoized.
  static Future<TvMotionProfile> deviceDefault() async {
    final cached = _deviceDefault;
    if (cached != null) return cached;
    final isTvOs = PlatformUtil.isTvOS;
    final isAndroidTv = !isTvOs && PlatformUtil.isAndroidTvCached;
    String? manufacturer, model, board, hardware, deviceName;
    if (isAndroidTv) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        manufacturer = info.manufacturer;
        model = info.model;
        board = info.board;
        hardware = info.hardware;
      } catch (_) {
        // The plugin is absent in tests and can fail on odd OEM builds;
        // the device-name channel below is the fallback.
      }
      try {
        deviceName = await PlatformUtil.getDeviceName();
      } catch (_) {}
    }
    return _deviceDefault = TvMotionProfile.defaultFor(
      isTvOs: isTvOs,
      isAndroidTv: isAndroidTv,
      manufacturer: manufacturer,
      model: model,
      board: board,
      hardware: hardware,
      deviceName: deviceName,
    );
  }

  /// Apply the choice live, then persist it. Publish-first, like the
  /// text-brightness controller: the notifier assignment is synchronous, so
  /// rapid re-selections apply in tap order, and a failed write costs only
  /// stickiness across restart.
  static Future<void> select(TvMotionProfile choice) async {
    _explicit = true;
    notifier.value = choice;
    try {
      await AppStylePrefs.setTvMotionProfile(choice.value);
    } catch (e) {
      debugPrint('TvMotionController: persist failed: $e');
    }
  }

  /// TEST-ONLY: back to the unwarmed state, optionally pinning the device
  /// default so a test can exercise the resolution without a plugin.
  @visibleForTesting
  static void debugReset({TvMotionProfile? deviceDefault}) {
    notifier.value = TvMotionProfile.snappy;
    _explicit = false;
    _deviceDefault = deviceDefault;
  }
}
