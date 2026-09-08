import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../utils/platform_util.dart';

/// Wraps a focusable widget to ensure proper scroll positioning on Android TV.
///
/// When a descendant widget gains focus, this wrapper ensures the item is
/// scrolled into view with appropriate padding from the top (to avoid being
/// hidden behind AppBar/headers).
///
/// This fixes an issue where D-pad navigation up would scroll the first item
/// behind the AppBar because Flutter's default alignment is 0.0 (top of viewport).
class TvFocusScrollWrapper extends StatelessWidget {
  final Widget child;

  /// Alignment for scroll positioning (0.0 = top, 0.5 = center, 1.0 = bottom).
  /// Default is 0.2 to keep ~20% padding from top, accounting for headers.
  final double alignment;

  /// Duration for scroll animation off a television — unaffected by the TV
  /// motion profile, which pointer/keyboard surfaces never read.
  final Duration duration;

  const TvFocusScrollWrapper({
    super.key,
    required this.child,
    this.alignment = 0.2,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final isTv = PlatformUtil.isTelevision;
    return Focus(
      // Don't intercept focus - just observe descendant focus changes
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          // Ensure this item is visible with proper alignment. On TV this
          // was a flat 200ms regardless of the Smooth/Snappy profile — the
          // one shared scroll-follow site every YouTube/Reddit/Lemmy/IPTV
          // results row, episode list, and file-browser row goes through,
          // never wired to AppMotion.tvScroll like the row-widget sites are.
          // Snappy keeps the shipped 200ms glide unchanged (`tvSnappy:
          // duration`, matching the convention every other scroll-follow
          // site already migrated under); only smooth is new, resolving to
          // the profile's own 260ms glide via `AppMotion.tvScroll`.
          Scrollable.ensureVisible(
            context,
            alignment: alignment,
            duration: motion.scrollTempo(isTv, duration, tvSnappy: duration),
            curve: isTv ? motion.tvScrollCurve : Curves.easeOutCubic,
          );
        }
      },
      child: child,
    );
  }
}
