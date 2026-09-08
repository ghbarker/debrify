import 'package:flutter/material.dart';

import '../services/tv_motion_profile.dart';
import '../widgets/detail/theme/detail_theme.dart';
import 'app_theme_scope.dart';
import 'tv_motion_scope.dart';

export '../services/tv_motion_profile.dart' show TvMotionProfile;

/// A theme's tempo.
///
/// The tree has ~680 hardcoded `Duration(milliseconds:)` sites and no token, so
/// there is no single place to turn motion down on a weak box — a live problem
/// on Amlogic/Xiaomi hardware. The defaults below are the durations already
/// most common in the tree, so adopting a token at a site is usually a no-op.
/// How motion FEELS, as opposed to how long it lasts.
///
/// The tempo scalar shipped in phase three is the weak version of this: a
/// theme that is 15% slower is not a different theme. Character changes the
/// curve and the duration together, which is what makes `snap` feel like a
/// terminal and `settle` feel like something with mass.
enum MotionCharacter {
  /// The shipped feel: ease-out cubic at the shipped durations.
  standard,

  /// No easing worth the name, minimum durations. Instruments do not glide.
  snap,

  /// Long decelerations. Everything arrives late and softly.
  glide,

  /// Slight overshoot, as though the thing has weight.
  settle,
}

/// The focus spring for [MotionCharacter.settle].
///
/// `damping` is spelled out rather than built with
/// `SpringDescription.withDampingRatio` because that factory is not `const`,
/// and [MotionTokens.of] must stay const. It is the same number:
/// `2ζ√(k·m)` = `2 × 0.82 × √210` ≈ 23.77.
///
/// ζ = 0.82 is the reference's damping, and it is under 1 on purpose — at 1.0
/// the spring is critically damped and settles without ever passing its mark,
/// which is exactly the "it moved" feeling this is meant to replace.
const SpringDescription kSettleFocusSpring = SpringDescription(
  mass: 1,
  stiffness: 210,
  damping: 23.77,
);

/// How a page's content arrives.
enum EntranceStyle {
  /// It is simply there. Today's app on TV, and the legacy pin.
  none,

  /// One cross-fade for the whole page.
  fadeUp,

  /// Rows arrive in sequence — the reveal the catalog detail already has, and
  /// already skips on TV.
  stagger,
}

@immutable
class MotionTokens {
  /// A state change the eye should barely register — a chip filling, a ring
  /// appearing.
  ///
  /// The named durations are the VOCABULARY; the sites adopted so far use
  /// [AppMotion.scaled] around their own literal instead, because that is what
  /// keeps legacy exact at a site whose shipped duration is 150 rather than
  /// one of these. New motion should reach for the names; existing motion
  /// migrates by keeping its number and gaining the theme's tempo.
  final Duration fast;

  /// The workhorse: sheets, dialogs, cross-fades.
  final Duration base;

  /// A deliberate, watchable move — a hero settling, a stage taking over.
  final Duration slow;

  /// Everything decelerating into place.
  final Curve standard;

  /// Something arriving with weight. Overshoots; never use it on a size that
  /// clips.
  final Curve emphasized;

  /// The theme's own tempo, deliberately a narrow range. A theme that takes 2×
  /// as long to open a sheet does not read as characterful, it reads as lag.
  final double scale;

  /// The feel. Sets curve and duration together — see [MotionCharacter].
  final MotionCharacter character;

  /// How page content arrives. Skipped on TV by [entranceFor], which is what
  /// the catalog detail's reveal controller already does by hand.
  final EntranceStyle entrance;

  /// Physics for focus travel, when the character has any.
  ///
  /// Null everywhere except [MotionCharacter.settle], whose whole definition
  /// is that things have mass — every other character keeps the curve path and
  /// `ParallaxFocus` falls back to [emphasized].
  ///
  /// A spring rather than a curve because of ONE property: it can be re-seeded
  /// mid-flight with its current velocity. Hold a direction down and travel
  /// six cards and a curve restarts from zero at each one; a spring carries
  /// through. That is the difference the reference has and an eased scale
  /// does not.
  final SpringDescription? focusSpring;

  const MotionTokens({
    required this.fast,
    required this.base,
    required this.slow,
    required this.standard,
    required this.emphasized,
    required this.scale,
    this.character = MotionCharacter.standard,
    this.entrance = EntranceStyle.none,
    this.focusSpring,
  });

  /// [character] resolved into the pair of curves and the tempo it implies.
  ///
  /// Derived rather than stored so a character can never disagree with the
  /// curves beside it — the failure mode where a theme says `snap` and then
  /// eases for 360ms because someone set the fields independently.
  factory MotionTokens.of(MotionCharacter c) => switch (c) {
    MotionCharacter.standard => legacy,
    MotionCharacter.snap => const MotionTokens(
      fast: Duration(milliseconds: 60),
      base: Duration(milliseconds: 90),
      slow: Duration(milliseconds: 140),
      standard: Curves.linear,
      emphasized: Curves.linear,
      // 1.0, NOT 0.85: the durations above already ARE the tempo. `AppMotion`
      // multiplies by `scale` on the way out, so a character that also scaled
      // would apply its own tempo twice — snap's advertised 90ms base would
      // arrive as 76.5ms. `scale` exists for a look that wants the standard
      // durations at a different pace, which is not what a character does.
      scale: 1,
      character: MotionCharacter.snap,
    ),
    MotionCharacter.glide => const MotionTokens(
      fast: Duration(milliseconds: 160),
      base: Duration(milliseconds: 300),
      slow: Duration(milliseconds: 520),
      standard: Curves.easeOutQuart,
      emphasized: Curves.easeOutQuint,
      scale: 1,
      character: MotionCharacter.glide,
    ),
    MotionCharacter.settle => const MotionTokens(
      fast: Duration(milliseconds: 140),
      base: Duration(milliseconds: 260),
      slow: Duration(milliseconds: 420),
      standard: Curves.easeOutCubic,
      emphasized: Curves.easeOutBack,
      scale: 1,
      character: MotionCharacter.settle,
      // ζ 0.82 — under-damped on purpose. At 1.0 the spring is critically
      // damped and never overshoots, which is the whole property `settle`
      // names.
      focusSpring: kSettleFocusSpring,
    ),
  };

  /// Entrance choreography is a full-screen animation on the one platform
  /// that cannot afford one — under the snappy profile. This is the RAW token
  /// policy; sites read [AppMotion.entrance], which also lets the smooth
  /// profile keep the reveal and collapses it under reduced motion.
  EntranceStyle entranceFor(bool isTv) => isTv ? EntranceStyle.none : entrance;

  /// Lives here rather than as a private extension elsewhere: a reconstruction
  /// helper that sits away from the constructor silently resets any field
  /// added later, and still compiles.
  /// NOTE: every field must be carried here. `ThemeSpec` builds its motion as
  /// `MotionTokens.of(character).copyWith(entrance: …)`, so a field this
  /// method forgets is silently dropped for every themed surface in the app —
  /// no error, just the feature quietly not working.
  MotionTokens copyWith({EntranceStyle? entrance, double? scale}) =>
      MotionTokens(
        fast: fast,
        base: base,
        slow: slow,
        standard: standard,
        emphasized: emphasized,
        scale: scale ?? this.scale,
        character: character,
        entrance: entrance ?? this.entrance,
        focusSpring: focusSpring,
      );

  static const MotionTokens legacy = MotionTokens(
    fast: Duration(milliseconds: 120),
    base: Duration(milliseconds: 220),
    slow: Duration(milliseconds: 360),
    standard: Curves.easeOutCubic,
    emphasized: Curves.easeOutBack,
    scale: 1,
  );

  factory MotionTokens.fromDetail(DetailTheme core) => MotionTokens(
    fast: legacy.fast,
    base: legacy.base,
    slow: legacy.slow,
    standard: legacy.standard,
    emphasized: legacy.emphasized,
    // Editorial themes — the ones with grain or set in caps — carry
    // themselves a little more slowly; technical ones (a hard cursor, no
    // elevation) snap. Everything else is the shipped tempo.
    scale: (core.grain > 0 || core.displayUpper)
        ? 1.15
        : (core.shadow.isEmpty && core.focusWidth <= 1.5)
        ? 0.85
        : 1.0,
  );
}

/// The only supported way to read a duration or curve from the theme.
///
/// Exists as a separate resolver rather than a raw token read because two
/// things can only be answered where a [BuildContext] is: the platform's
/// reduced-motion setting, and the fact that a theme change must retarget
/// controllers that are already alive.
///
/// ## Where a site may call this
///
/// 1. **A `State` that owns an `AnimationController`** resolves in
///    `didChangeDependencies` — build the controller in `initState` with a
///    literal, then assign `controller.duration` here. That is the one hook
///    that may depend on inherited widgets *and* re-runs when they change, so
///    a theme or accessibility switch retargets a live controller. Assigning
///    `duration` mid-flight is safe: Flutter reads it when the controller is
///    next started, and does not disturb a run in progress.
/// 2. **Stateless animated widgets** (`AnimatedContainer`, `AnimatedOpacity`,
///    `AnimatedSwitcher`) read it in `build`, hoisted above any builder
///    callback exactly like `AppThemeScope.of`.
/// 3. **Never inside a transition or `AnimatedBuilder` callback** — that is a
///    per-frame inherited lookup, and the house rule forbids it. Route curves
///    belong to the memoized `ThemeData`, not to a per-frame read.
///
/// ## What reduced motion does and does not reach
///
/// `MediaQuery.disableAnimations` collapses every duration THIS API vends to
/// zero. It cannot reach route-controller duration (a `PageTransitionsBuilder`
/// receives an animation the route already created — which is why
/// `AppPageTransitionsBuilder` renders a plain fast fade under reduced motion
/// instead) and it does not reach literals that have not been migrated. Both
/// are stated limits, not bugs.
///
/// **It applies under the legacy theme too, and that is deliberate.** The
/// house rule is that legacy renders byte-for-byte what it always has — and
/// this is the one considered exception, so it is written down rather than
/// discovered. A site that adopts a motion token stops animating on a device
/// whose owner has switched "Remove animations" on, whichever theme they are
/// using. Gating accessibility on a cosmetic preference would be the wrong
/// trade in the other direction, and the app already honours the flag in one
/// place (`stremio_tv_tuner.dart`). Legacy identity therefore means: **at the
/// platform's default motion setting.** `shape_type_motion_test.dart` pins
/// both halves of that sentence.
@immutable
class AppMotion {
  final MotionTokens tokens;

  /// True when the platform asks for reduced motion, or the caller is a
  /// surface that has opted out.
  final bool reduced;

  /// How much a television may move — see [TvMotionProfile]. Read from
  /// [TvMotionScope] by [of]; defaults to snappy (the shipped TV figures) for
  /// a hand-built instance, so every pin written against the old behaviour
  /// still describes it. Ignored by every non-TV getter.
  final TvMotionProfile profile;

  const AppMotion(
    this.tokens, {
    required this.reduced,
    this.profile = TvMotionProfile.snappy,
  });

  static AppMotion of(BuildContext context) => AppMotion(
    AppThemeScope.of(context).motion,
    reduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    profile: TvMotionScope.of(context),
  );

  bool get _smooth => profile == TvMotionProfile.smooth;

  Duration get fast => scaled(tokens.fast);
  Duration get base => scaled(tokens.base);
  Duration get slow => scaled(tokens.slow);

  Curve get standard => tokens.standard;
  Curve get emphasized => tokens.emphasized;

  /// The TV cursor's tempo: how long focus takes to LEAVE one control and
  /// ARRIVE on the next, as one shared figure for every control class.
  ///
  /// Every TV focus site used to snap (`Duration.zero`) for raster cost, and
  /// the snap is what a viewer reads as a flash: the old control drops its
  /// treatment in the very frame the new one gains it, so for one frame the
  /// eye sees two states swap rather than one cursor move. A short tween on
  /// BOTH ends — the loser and the gainer on the same duration and the same
  /// curve — is what makes the cursor read as travelling. The figure is the
  /// theme's `fast` (legacy 120ms): the shipped tempo of the board rise, the
  /// one TV control that already animated and the one nobody called laggy.
  /// Reduced motion collapses it to zero through [scaled], like every other
  /// duration this API vends; that is also the only way a TV site may snap.
  ///
  /// A site that animates on TV must stay GPU-cheap over the tween: a
  /// transform, a colour or an alpha — never a blur radius or a spread that
  /// changes, which re-derives a shadow every frame. Shadows keep their
  /// geometry on both ends and fade their colour; a transparent one costs
  /// nothing at rest. `CardFocusRise` is the reference shape.
  ///
  /// The [profile] picks the figure: snappy is `fast` (the 120ms above);
  /// smooth is `base` (legacy 220ms) — the pointer surfaces' own tempo, on a
  /// box that renders it without dropping frames. The raster rules above
  /// hold under both: a longer tween on the same cheap properties.
  Duration get tvFocus => scaled(_smooth ? tokens.base : tokens.fast);

  /// The curve a TV focus TRANSFORM runs on — the tile grow, the pill scale,
  /// the parallax lift. Snappy keeps the theme's `standard`; smooth is
  /// `emphasized`, the overshoot that makes a longer move read as arriving
  /// with weight rather than merely taking longer.
  ///
  /// TRANSFORMS ONLY, by the token's own rule ("never use it on a size that
  /// clips"). A colour or an alpha tween beside the transform stays on
  /// `standard`: `Color.lerp` clamps, but a lerped `BoxDecoration` does not
  /// — an overshooting `t` scales a departing shadow list negative and a
  /// changing border width past zero, which asserts. Both run the same
  /// [tvFocus] length, so the control still leaves and arrives as one.
  Curve get tvFocusCurve => _smooth ? tokens.emphasized : tokens.standard;

  /// [tvFocusCurve] on a TV; [otherwise] anywhere else — and under snappy,
  /// where the site's own curve IS today's value and stays byte-exact.
  Curve focusCurve(bool isTv, Curve otherwise) =>
      isTv && _smooth ? tokens.emphasized : otherwise;

  /// How long a TV scroll-follow (`Scrollable.ensureVisible` when the cursor
  /// lands on a row) takes. Snappy: zero — the shipped jump, chosen because
  /// even a short glide is a scrolled repaint on every frame of every step
  /// on a weak box. Smooth: ~260ms on `standard`, the figure the pointer
  /// surfaces' lists already follow at. Reduced motion collapses it to zero
  /// in both profiles; the pointer figure a site passes to [scrollTempo]
  /// gains the theme's scale and the same collapse.
  Duration get tvScroll =>
      _smooth ? scaled(const Duration(milliseconds: 260)) : Duration.zero;

  /// The curve for [tvScroll]. Always `standard`: a scroll that overshoots
  /// its target reads as a mis-scroll, not as weight.
  Curve get tvScrollCurve => tokens.standard;

  /// [tvScroll] on a TV; [otherwise] anywhere else, at the theme's tempo.
  ///
  /// [tvSnappy] is the TV figure the snappy profile keeps — zero for every
  /// site but the Apple TV board glide, which passes its own 140ms.
  Duration scrollTempo(
    bool isTv,
    Duration otherwise, {
    Duration tvSnappy = Duration.zero,
  }) => isTv ? (_smooth ? tvScroll : scaled(tvSnappy)) : scaled(otherwise);

  /// The entrance choreography a TV gets for [style]. Snappy: none — the
  /// full-screen reveal the weak box cannot afford. Smooth: [style] itself,
  /// the same choreography the theme plays off TV.
  EntranceStyle tvEntrance(EntranceStyle style) =>
      _smooth ? style : EntranceStyle.none;

  /// How this page's content arrives, everything considered: the theme's
  /// token, the TV profile, and reduced motion — under which nothing arrives
  /// with a fade or a rise, anywhere. The one entrance read a site may make.
  EntranceStyle entrance(bool isTv) {
    if (reduced) return EntranceStyle.none;
    return isTv ? tvEntrance(tokens.entrance) : tokens.entrance;
  }

  /// Whether a TV route runs the shared-axis transition (smooth) instead of
  /// the fast fade (snappy). Static because the one caller —
  /// `AppPageTransitionsBuilder.buildTransitions` — runs per frame and may
  /// not resolve an inherited [AppMotion]; it hands in the controller's
  /// current profile the way it reads `PlatformUtil.isTelevision`.
  static bool tvRoutesSharedAxis(TvMotionProfile profile) =>
      profile == TvMotionProfile.smooth;

  /// [tvFocus] on a TV; [otherwise] anywhere else, at the theme's tempo.
  ///
  /// The shape every focus site had by hand as `tv ? Duration.zero : literal`,
  /// with the TV branch routed through the one token. The pointer figure
  /// keeps its number and gains the theme's scale and the reduced-motion
  /// collapse — the same migration every other adopted literal made.
  Duration focusTempo(bool isTv, Duration otherwise) =>
      isTv ? tvFocus : scaled(otherwise);

  /// [d] at this theme's tempo — or nothing at all under reduced motion.
  ///
  /// Rounds to whole microseconds, so a scaled duration is still exact rather
  /// than carrying a float remainder into a controller.
  Duration scaled(Duration d) {
    if (reduced) return Duration.zero;
    if (tokens.scale == 1) return d;
    return Duration(
      microseconds: (d.inMicroseconds * tokens.scale).round(),
    );
  }
}
