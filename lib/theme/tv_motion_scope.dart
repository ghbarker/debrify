import 'package:flutter/material.dart';

import '../services/tv_motion_profile.dart';

/// Provides the live [TvMotionProfile] to the tree.
///
/// Installed ONCE, beside the root [AppThemeScope] in `MaterialApp.builder`,
/// under a `ValueListenableBuilder` on `TvMotionController.notifier` — so a
/// chip press republishes the profile and every widget that resolved
/// `AppMotion.of(context)` in `build` or `didChangeDependencies` re-runs and
/// retargets its tween. That is the same path a theme change takes, and it is
/// what lets the preference be read in build without a per-frame lookup.
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
