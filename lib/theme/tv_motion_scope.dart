import 'package:flutter/material.dart';

import '../services/tv_motion_profile.dart';

/// Provides the live [TvMotionProfile] to the tree.
///
/// Installed ONCE, beside the root [AppThemeScope] in `MaterialApp.builder`,
/// reading `TvMotionController.current`. `_DebrifyAppState` subscribes to
/// `TvMotionController.notifier` explicitly (`addListener` in `initState`,
/// the same contract `AppThemeController` and `TextBrightnessController`
/// use) and calls `setState` on change, so a chip press — or a profile
/// switch's re-warm — republishes the profile here and every widget that
/// resolved `AppMotion.of(context)` in `build` or `didChangeDependencies`
/// re-runs and retargets its tween. `_DebrifyAppState` sits above
/// `ProfileGate`, which rekeys only its child, so this explicit subscription
/// is what keeps an incoming profile from inheriting the outgoing profile's
/// tempo (see `stale_runtime_guard_test.dart`).
///
/// An [InheritedTheme] so `InheritedTheme.capture` carries it into dialogs
/// and bare overlays, exactly like the theme scope.
class TvMotionScope extends InheritedTheme {
  final TvMotionProfile profile;

  const TvMotionScope({
    super.key,
    required this.profile,
    required super.child,
  });

  @override
  Widget wrap(BuildContext context, Widget child) =>
      TvMotionScope(profile: profile, child: child);

  @override
  bool updateShouldNotify(TvMotionScope oldWidget) =>
      oldWidget.profile != profile;

  /// The profile in force. Falls back to the controller's current value so a
  /// widget pumped outside the root scope (tests, tooling) reads the same
  /// answer production would rather than throwing.
  static TvMotionProfile of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvMotionScope>()?.profile ??
      TvMotionController.current;
}
