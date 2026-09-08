import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/tv_motion_profile.dart';
import '../utils/platform_util.dart';
import 'app_motion.dart';

/// The one route transition every platform uses.
///
/// Registered under EVERY [TargetPlatform] key in
/// `AppThemeAdapter.pageTransitions`, so a `MaterialPageRoute` animates the
/// same way on a phone, a desktop and a TV, and the choice below is the only
/// place that decides how. Previously only Android was overridden (TV fade,
/// phone zoom); iOS/macOS ran the Cupertino slide and Windows/Linux fell
/// through to Flutter's zoom default, so Apple TV never got the TV fade and
/// desktop pushes snapshotted the page every time.
///
/// The decision, in priority order:
///
/// 1. **Television** ([PlatformUtil.isTelevision], Android TV and Apple TV)
///    under the SNAPPY motion profile: a plain fast fade — the incoming page
///    fades in over the first 40% of the route animation (~120ms of the
///    standard 300ms). Every push/pop on TV animates a full-screen layer, and
///    scale/snapshot transitions are visibly janky on weak TV GPUs; the fade
///    reads as an instant, native-style switch and costs one opacity layer.
///    This is byte-for-byte the fade Android TV has always had. Under the
///    SMOOTH profile (Apple TV, Shield-class boxes, or the user's choice) a
///    TV falls through to rule 4 and runs the same shared axis a desktop
///    does — see [AppMotion.tvRoutesSharedAxis].
/// 2. **Reduced motion** (`MediaQuery.disableAnimations`): the same fast
///    fade. A `PageTransitionsBuilder` receives an animation the route has
///    already created, so it cannot shorten the controller — the only lever
///    is to render something trivial. No scale, no slide, done within the
///    first ~120ms. Checked before the platform so an iPhone with "Reduce
///    Motion" on does not get the Cupertino parallax slide either.
/// 3. **iPhone / iPad** ([TargetPlatform.iOS] that is not tvOS): the stock
///    [CupertinoPageTransitionsBuilder]. Deliberately NOT the shared axis —
///    the Cupertino builder is what carries the interactive edge swipe-back
///    gesture (its detector is private to the framework), and losing that
///    on iOS is a regression users feel far more than a different push
///    curve. The Cupertino slide already animates the exiting page (the
///    parallax), so it is smooth in its own right.
/// 4. **Everything else** (Android phones/tablets, Windows, Linux, macOS,
///    Fuchsia): a Material shared-axis transition from the `animations`
///    package. `scaled` for ordinary routes — the incoming page fades in
///    while growing from 80%, the outgoing fades out while growing to 110%,
///    which is the spec's "drill in to a child" motion and matches how this
///    app navigates (catalog → detail → player). `vertical` for
///    `fullscreenDialog` routes — the page rises ~30px as it fades in, which
///    reads as "presented over", the meaning of a fullscreen dialog on both
///    Material and iOS. Both pushes and pops animate the exiting page too
///    (`secondaryAnimation`), fading it through the theme ground so nothing
///    behind the Navigator ever shows.
///
/// ## Why no AppMotion curves
///
/// Route curves belong to the memoized `ThemeData`, not to a per-frame read
/// (see `AppMotion`); Flutter rebuilds `buildTransitions` inside an
/// `AnimatedBuilder` on every frame of the route animation, so this is the
/// one place a theme-token lookup is explicitly forbidden.
/// `SharedAxisTransition` also owns its curve choreography per the Material
/// motion spec and takes no curve parameters. The two inherited reads here
/// (`Theme.of` for the fill colour, `MediaQuery` for reduced motion) are the
/// same O(1) aspect lookups the framework's own
/// `MaterialRouteTransitionMixin.buildTransitions` performs to find this
/// builder in the first place.
///
/// The TV check reads [PlatformUtil.isTelevision] and the motion profile
/// reads `TvMotionController.current` per transition build — both static,
/// both warmed in main() before runApp — so the `PageTransitionsTheme` stays
/// const and one instance serves every built theme.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  static const PageTransitionsBuilder _cupertino =
      CupertinoPageTransitionsBuilder();

  /// The TV fade window: the incoming page is fully opaque 40% of the way
  /// through the route animation. Public so the pin test can name it.
  static const Curve fastFadeCurve = Interval(
    0.0,
    0.4,
    curve: Curves.easeOut,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final tvFade = PlatformUtil.isTelevision &&
        !AppMotion.tvRoutesSharedAxis(TvMotionController.current);
    if (tvFade || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: fastFadeCurve),
        child: child,
      );
    }

    final theme = Theme.of(context);
    if (theme.platform == TargetPlatform.iOS && !PlatformUtil.isTvOS) {
      return _cupertino.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: route.fullscreenDialog
          ? SharedAxisTransitionType.vertical
          : SharedAxisTransitionType.scaled,
      // The colour the outgoing page fades THROUGH. Every page's Scaffold
      // paints this, so the fade-out lands on the ground the incoming page
      // then fades in over — not the package default `canvasColor`, which a
      // theme may not align with its ground.
      fillColor: theme.scaffoldBackgroundColor,
      child: child,
    );
  }
}
