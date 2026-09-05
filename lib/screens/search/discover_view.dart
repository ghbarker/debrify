import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../widgets/home/home_theme.dart';
import '../../widgets/see_all/discover_card_settings_scope.dart';
import '../../widgets/see_all/discover_detail_rail.dart';
import '../../widgets/see_all/discover_shelf_scope.dart';
import '../../widgets/see_all/discover_trailer_stage.dart';
import 'discover_lifecycle.dart';
import 'trailer_status_chips.dart';

/// Discover STAGE: the air between the identity block and the shelf column
/// below it. The block's clearance is [DiscoverShelfMetrics.columnHeight] plus
/// this — derived from what the shelf actually occupies, never guessed.
const double _kDiscStageIdentityGap = 22;

/// Discover STAGE: the band the quiet filter line owns at the top of the
/// panel — its 16px top padding, one line of segments and its 10px tail,
/// measuring ~56, plus a little air. It never needs a second row: the quiet
/// bar scrolls its segments horizontally rather than wrapping.
const double _kDiscStageFilterBand = 62;

/// Discover presentation over the host's existing lifecycle and source panel.
/// The containing host retains construction, listeners, actions and disposal.
class DiscoverView extends StatelessWidget {
  const DiscoverView({
    super.key,
    required this.isTelevision,
    required this.lifecycle,
    required this.panel,
  });

  final bool isTelevision;
  final DiscoverLifecycle lifecycle;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final panel = DiscoverCardSettingsScope(
      showTypeTags: lifecycle.showTypeTags,
      showRatings: lifecycle.showRatings,
      showTitles: lifecycle.showTitles,
      child: this.panel,
    );
    // Touch has no persistent focus, so a reactive detail rail has nothing to
    // react to — keep the full-width grid there. TV gets the glass-stage
    // two-pane layout.
    if (!isTelevision) return panel;
    return LayoutBuilder(
      builder: (layoutContext, c) {
        // Guard a degenerate canvas: too narrow leaves no room for a usable grid
        // beside the rail; too short and the rail's fixed identity block can't
        // fit. Either way, fall back to the full-width panel.
        if (c.maxWidth < 720 || c.maxHeight < 420) {
          // The trailer stage (which drives lifecycle.takeover → sidebar chrome-dim,
          // and lifecycle.trailerShowing → the AMBIENT chip) is unmounted in this
          // branch. Clear both post-frame so nothing sticks across the drop.
          lifecycle.resetForNarrowCanvas();
          return panel;
        }
        if (lifecycle.layout == 'stage') {
          return _buildDiscoverStage(context, c, panel);
        }
        final railW = (c.maxWidth * 0.375).clamp(320.0, 460.0);
        final panelW = c.maxWidth - railW;
        final mq = MediaQuery.of(layoutContext);
        final twoPane = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: railW,
              // Theater: the identity block ghosts to 15% so the trailer owns
              // the art zone. AnimatedOpacity is acceptable here — the layer is
              // rail-sized (not full-screen), pays its saveLayer only during
              // the ~1.2s ease, and composites as a cached raster once settled.
              // It wraps a SIBLING of the video layer, so the underlay punch is
              // untouched. Lights-up is fast to match the veils' cadence.
              child: ValueListenableBuilder<bool>(
                valueListenable: lifecycle.theater,
                // RepaintBoundary: the rail rebuilds on every DPAD step (new
                // title, logo, plot) — keep that raster confined to the rail
                // column instead of dirtying the stage layer behind it.
                child: RepaintBoundary(
                  child: ValueListenableBuilder<StremioMeta?>(
                    valueListenable: lifecycle.focused,
                    builder: (_, item, __) => DiscoverDetailRail(
                      item: item,
                      trailerStreams: lifecycle.trailerStreams,
                      trailerLoading: lifecycle.trailerLoading,
                      trailerVolume: lifecycle.trailerVolume,
                      trailerMeta: lifecycle.trailerMeta,
                      shownItem: lifecycle.shown,
                    ),
                  ),
                ),
                builder: (_, theater, child) => AnimatedOpacity(
                  opacity: theater ? 0.15 : 1.0,
                  duration: theater
                      ? const Duration(milliseconds: 1200)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: child,
                ),
              ),
            ),
            // The grid derives its column count from MediaQuery width; report
            // the panel's (narrower) width so it lays out for its real box
            // instead of the full screen and overflowing.
            SizedBox(
              width: panelW,
              // Theater: the grid itself ghosts to ~12% — fading the CONTENT is
              // the only way to unveil the trailer on this side (any ink wash
              // painted over the panel darkens the video with it, and the
              // opaque posters block it regardless). Same layer rules as the
              // rail's fade: sibling of the video layer (punch untouched),
              // saveLayer only during the ~1.2s ease, cached raster after.
              child: ValueListenableBuilder<bool>(
                valueListenable: lifecycle.theater,
                // RepaintBoundary: the filter line's focus pills repaint on
                // every DPAD move across it (the grid viewport below is its own
                // boundary already) — keep panel chrome out of the stage layer.
                child: RepaintBoundary(
                  child: MediaQuery(
                    data: mq.copyWith(size: Size(panelW, mq.size.height)),
                    child: panel,
                  ),
                ),
                builder: (_, theater, child) => AnimatedOpacity(
                  opacity: theater ? 0.12 : 1.0,
                  duration: theater
                      ? const Duration(milliseconds: 1200)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: child,
                ),
              ),
            ),
          ],
        );
        // The glass stage (bottom → top): base ink wash → the focused title's
        // full-frame backdrop → the ambient trailer (which replaces the still,
        // frame one, across the whole canvas) → the tint veils that keep both
        // panes legible (direct translucent paint — never an Opacity layer, and
        // safe over the underlay video's punched hole, exactly like the Home
        // hero's feathers) → the panes themselves → status chips.
        //
        // Layer discipline (the Home hero's): each stage stratum sits in its
        // own RepaintBoundary so a rail swap (every DPAD step) or a veil
        // transition frame re-rasters only itself. Without the boundaries they
        // all share one picture and every keypress re-records + re-rasters the
        // full-screen backdrop AND both veil gradients on the weak TV GPU —
        // the whole page reads as laggy. These are plain composited layers,
        // not saveLayers, so the underlay video's punch is unaffected.
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(decoration: BoxDecoration(gradient: app.home.wash)),
            RepaintBoundary(
              child: _DiscoverStageBackdrop(shown: lifecycle.shown),
            ),
            DiscoverTrailerStage(
              trailer: lifecycle.trailerStreams,
              loading: lifecycle.trailerLoading,
              volume: lifecycle.trailerVolume,
              meta: lifecycle.trailerMeta,
              railRect: Rect.zero,
              takeover: lifecycle.takeover,
              fullStage: true,
              showing: lifecycle.trailerShowing,
            ),
            RepaintBoundary(
              child: _DiscoverStageVeils(
                showing: lifecycle.trailerShowing,
                theater: lifecycle.theater,
              ),
            ),
            twoPane,
            // Lights-off over the grid side while the trailer plays — the Home
            // rows' recede, transplanted. Above the panes (it dims the posters
            // and filter line), feathered on its left edge so no seam cuts the
            // stage. Animated as a baked color (direct paint), never Opacity.
            _DiscoverGridDim(
              showing: lifecycle.trailerShowing,
              theater: lifecycle.theater,
              leftInset: railW,
            ),
            // Recede the two-pane as the trailer takes over — a baked scrim, not
            // an Opacity layer (whose mid-values force a per-frame full-screen
            // saveLayer on weak TV GPUs). Dormant while the takeover stays
            // disabled, kept wired for its revival.
            ValueListenableBuilder<double>(
              valueListenable: lifecycle.takeover,
              builder: (_, t, __) => t <= 0.001
                  ? const SizedBox.shrink()
                  : IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: app.fade(app.home.bg, 0.92 * t),
                        ),
                      ),
                    ),
            ),
            // Status corner: the Home hero's chip pair, handing over in place —
            // equalizer TRAILER pill while resolving/buffering, AMBIENT chip
            // once frames are up. Anchored bottom-left, in the rail column's
            // permanently-empty zone (the plot is capped at 6 lines, so the
            // identity block never reaches it) — the top-right corner belongs
            // to the filter line, which can wrap two rows on 5-segment sources.
            Positioned(
              bottom: 22,
              left: 24,
              child: ValueListenableBuilder<bool>(
                valueListenable: lifecycle.trailerLoading,
                builder: (_, loading, __) =>
                    HeroTrailerLoadingPill(visible: loading),
              ),
            ),
            Positioned(
              bottom: 22,
              left: 24,
              child: ValueListenableBuilder<bool>(
                valueListenable: lifecycle.trailerShowing,
                builder: (_, showing, __) => ValueListenableBuilder<bool>(
                  valueListenable: lifecycle.trailerLoading,
                  builder: (_, loading, __) =>
                      HeroAmbientChip(visible: showing && !loading),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The Discover STAGE layout (`discover_layout` = 'stage', TV only).
  ///
  /// Same stage as the grid's two-pane — same backdrop, same full-canvas
  /// trailer, same theater ladder — with the rail dissolved: the focused
  /// title's art owns the whole frame, its identity block sits bottom-left over
  /// it, and the results become ONE shelf across the bottom. The filter line
  /// stays exactly where the grid put it (top-left of the panel), so UP from
  /// the shelf lands on it just as UP from the grid does.
  ///
  /// It is the SAME panel widget as the grid layout: the See-All screen keeps
  /// owning fetch, filters and paging, and only the arrangement of its results
  /// changes — declared by the [DiscoverShelfScope] wrapped around it here.
  Widget _buildDiscoverStage(
    BuildContext context,
    BoxConstraints c,
    Widget panel,
  ) {
    final app = AppThemeScope.of(context);
    // Canvas's poster proportion (30% of the board, clamped) so the two
    // full-bleed shelves on this TV read as the same furniture.
    final cardH = (c.maxHeight * 0.30).clamp(140.0, 200.0);
    final metrics = DiscoverShelfMetrics(cardHeight: cardH, hPad: 24);
    // The identity block never crosses the middle of the frame — the art on
    // the right half is the point of this layout.
    final identityMax = (c.maxWidth * 0.5).clamp(320.0, 560.0);
    // What the identity block may occupy while BROWSING: the canvas less the
    // filter band above and the shelf column below. Computed here and handed
    // down, because theater animates that box open — a block that measured
    // its live constraint would gain a plot line mid-glide and jump.
    final identityBudget =
        c.maxHeight -
        _kDiscStageFilterBand -
        (metrics.columnHeight + _kDiscStageIdentityGap);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: app.home.wash)),
        RepaintBoundary(
          child: _DiscoverStageBackdrop(
            shown: lifecycle.shown,
            // The identity block settles this feed upstream, so no second
            // dwell here — art and title land together, and they crossfade
            // like the Home board's own full-bleed stage.
            dwell: Duration.zero,
            crossfade: true,
          ),
        ),
        DiscoverTrailerStage(
          trailer: lifecycle.trailerStreams,
          loading: lifecycle.trailerLoading,
          volume: lifecycle.trailerVolume,
          meta: lifecycle.trailerMeta,
          railRect: Rect.zero,
          takeover: lifecycle.takeover,
          fullStage: true,
          showing: lifecycle.trailerShowing,
        ),
        RepaintBoundary(
          child: _DiscoverStageVeils(
            showing: lifecycle.trailerShowing,
            theater: lifecycle.theater,
            stage: true,
          ),
        ),
        // The identity block, bottom-left, clearing exactly what the shelf
        // column below occupies — derived from the same metrics the shelf lays
        // itself out with, never guessed.
        //
        // THEATER: the block glides to the top-left and shrinks — the Canvas
        // board's billboard move, so a clean full-bleed trailer still carries
        // a quiet signature. What actually travels is the title art alone:
        // meta and plot faded out earlier, with [lifecycle.trailerShowing], inside
        // the rail widget. Padding/Align/Scale animate on ONE cadence (slow
        // lights-down, instant lights-up) — three transforms and a layout
        // inset, no repaint of the stage under them.
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: lifecycle.theater,
              child: RepaintBoundary(
                child: ValueListenableBuilder<StremioMeta?>(
                  valueListenable: lifecycle.focused,
                  builder: (_, item, __) => DiscoverDetailRail(
                    item: item,
                    layout: DiscoverDetailLayout.stage,
                    trailerShowing: lifecycle.trailerShowing,
                    stageMaxWidth: identityMax,
                    stageBudget: identityBudget,
                    // The Home board's billboard settle: holding a direction
                    // across the shelf costs only the cards' focus visuals,
                    // never an identity rebuild plus a full-bleed decode per
                    // step. The trailer still releases on the first keypress.
                    settleDelay: const Duration(milliseconds: 260),
                    trailerStreams: lifecycle.trailerStreams,
                    trailerLoading: lifecycle.trailerLoading,
                    trailerVolume: lifecycle.trailerVolume,
                    trailerMeta: lifecycle.trailerMeta,
                    shownItem: lifecycle.shown,
                  ),
                ),
              ),
              builder: (_, deep, kid) => AnimatedPadding(
                // Browse — top: the filter line's band, so a short canvas
                // makes the block shed its plot rather than grow up under the
                // filters; bottom: exactly what the shelf column occupies.
                // Theater — the block rides up to the top corner instead.
                padding: EdgeInsets.only(
                  top: deep ? 30 : _kDiscStageFilterBand,
                  bottom: deep
                      ? 0
                      : metrics.columnHeight + _kDiscStageIdentityGap,
                ),
                duration: deep
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: AnimatedAlign(
                  alignment: deep ? Alignment.topLeft : Alignment.bottomLeft,
                  duration: deep
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedScale(
                    scale: deep ? 0.7 : 1.0,
                    alignment: Alignment.topLeft,
                    duration: deep
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: kid,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Filter line + shelf. Theater recede: the Canvas cadence — slow
        // lights-down, instant lights-up — as a slide + fade. The children
        // stay MOUNTED (opacity only), so DPAD focus survives the dark and the
        // wake keypress still performs its normal move. This is the one
        // full-canvas Opacity on the page; it pays its saveLayer during the
        // ease and composites as a cached raster at rest, exactly like the
        // two-pane's panel fade it replaces.
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: lifecycle.theater,
            child: RepaintBoundary(
              child: DiscoverShelfScope(metrics: metrics, child: panel),
            ),
            builder: (_, deep, kid) => AnimatedSlide(
              offset: deep ? const Offset(0, 0.12) : Offset.zero,
              duration: deep
                  ? const Duration(milliseconds: 900)
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: deep ? 0.0 : 1.0,
                duration: deep
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: kid,
              ),
            ),
          ),
        ),
        // Recede everything as the trailer promotes to a fullscreen takeover —
        // a baked scrim, never an Opacity layer. Dormant while the takeover
        // stays disabled, kept wired for its revival (as in the two-pane).
        ValueListenableBuilder<double>(
          valueListenable: lifecycle.takeover,
          builder: (_, t, __) => t <= 0.001
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: app.fade(app.home.bg, 0.92 * t),
                    ),
                  ),
                ),
        ),
        // Status corner: the same TRAILER→AMBIENT chip pair the two-pane
        // shows, moved to the TOP-right — the bottom-left corner belongs to
        // the identity block here.
        Positioned(
          top: 16,
          right: 22,
          child: ValueListenableBuilder<bool>(
            valueListenable: lifecycle.trailerLoading,
            builder: (_, loading, __) =>
                HeroTrailerLoadingPill(visible: loading),
          ),
        ),
        Positioned(
          top: 16,
          right: 22,
          child: ValueListenableBuilder<bool>(
            valueListenable: lifecycle.trailerShowing,
            builder: (_, showing, __) => ValueListenableBuilder<bool>(
              valueListenable: lifecycle.trailerLoading,
              builder: (_, loading, __) =>
                  HeroAmbientChip(visible: showing && !loading),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Discover glass stage's still backdrop: the focused (rail-shown) title's
/// backdrop drawn full-frame behind both panes, veiled by [_DiscoverStageVeils]
/// above it. Adoption is dwell-debounced (~380ms) so rapid DPAD arrowing never
/// decodes a full-bleed image per step — the first artwork after an empty stage
/// paints immediately. Only real `background` art is used (never a blown-up
/// poster); titles without it browse on the plain ink wash.
class _DiscoverStageBackdrop extends StatefulWidget {
  final ValueListenable<StremioMeta?> shown;

  /// How long the DPAD must rest before this adopts a new backdrop. The STAGE
  /// layout passes ZERO: its feed is already settled upstream (the identity
  /// block's own settle), so a second dwell here would only make the art trail
  /// the title it belongs to.
  final Duration dwell;

  /// Crossfade swaps instead of snapping them. The two-pane keeps the snap —
  /// a full-screen crossfade is a saveLayer on weak TV GPUs, and behind a
  /// grid it buys little. The STAGE turns it on: the art IS the layout there,
  /// and its swaps are already rate-limited by the settle, so this matches the
  /// Home board's own full-bleed art, which crossfades on the same cadence.
  final bool crossfade;

  const _DiscoverStageBackdrop({
    required this.shown,
    this.dwell = const Duration(milliseconds: 380),
    this.crossfade = false,
  });

  @override
  State<_DiscoverStageBackdrop> createState() => _DiscoverStageBackdropState();
}

class _DiscoverStageBackdropState extends State<_DiscoverStageBackdrop> {
  String? _url;
  Timer? _dwell;

  static String? _bgOf(StremioMeta? m) {
    final bg = m?.background;
    return (bg != null && bg.isNotEmpty) ? bg : null;
  }

  @override
  void initState() {
    super.initState();
    widget.shown.addListener(_onShown);
    _url = _bgOf(widget.shown.value);
  }

  @override
  void dispose() {
    _dwell?.cancel();
    widget.shown.removeListener(_onShown);
    super.dispose();
  }

  void _onShown() {
    final next = _bgOf(widget.shown.value);
    if (next == _url) return;
    _dwell?.cancel();
    // Cleared (source swap) or the focused title has no backdrop: drop to ink
    // now — holding another title's art behind the wrong detail reads wrong.
    if (next == null) {
      setState(() => _url = null);
      return;
    }
    // First art onto an empty stage: no dwell, the page should dress itself
    // promptly. Subsequent moves debounce.
    if (_url == null) {
      setState(() => _url = next);
      return;
    }
    if (widget.dwell == Duration.zero) {
      setState(() => _url = next);
      return;
    }
    _dwell = Timer(widget.dwell, () {
      if (!mounted) return;
      final cur = _bgOf(widget.shown.value);
      if (cur != null && cur != _url) setState(() => _url = cur);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    // Per-IMAGE fades stay off in both modes (a CachedNetworkImage crossfade
    // runs on every arrival, including cache hits). Slight upward bias keeps
    // faces/titles in the art's clear zone.
    final art = url == null
        ? const SizedBox.shrink()
        : CachedNetworkImage(
            key: ValueKey(url),
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.4),
            memCacheWidth: HomeTheme.heroBackdropCacheWidthTv,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          );
    if (!widget.crossfade) return art;
    // Android TV keeps the two-pane's SNAP even on the stage: the switcher's
    // crossfade is a full-screen saveLayer on that GLES2 pipeline — the exact
    // cost the two-pane documented when it declined the fade — and a rest can
    // pay it twice (the raw list art, then the /meta-enriched background a
    // moment later). On an Amlogic box those frames land right when the user
    // is about to move again, which reads as navigation lag.
    if (PlatformUtil.isAndroidTvCached) return art;
    // Between two SETTLED titles — at most one swap per rest — so the
    // saveLayer this costs is bounded, exactly as on the Home board's stage.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      // LOSING the art snaps instead of fading. Catalog list items usually
      // arrive with no `background` at all — it comes with the /meta
      // enrichment a moment later — so a symmetric crossfade would dip the
      // whole frame to ink and back on nearly every rest. Only the arrival is
      // worth animating.
      reverseDuration: url == null
          ? Duration.zero
          : const Duration(milliseconds: 240),
      // EXPAND, not the default centre-and-shrink-wrap: a switcher's stock
      // layout hands its children loose constraints, which would let each
      // backdrop paint at its own intrinsic size instead of covering the
      // frame — outgoing and incoming art must both be the same full-bleed
      // crop, or the swap reads as a jump in zoom.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: art,
    );
  }
}

/// The Discover glass stage's tint veils — the mock's gradient recipe, painted
/// in the page ink so the art dissolves into the canvas: loudest art behind the
/// detail column, near-opaque under the grid, plus a vertical top kiss and deep
/// bottom melt.
///
/// Three states on a lights ladder, eased between so every step feels staged:
/// browse (art dressed in the mock's tint), playback ([showing] — art-zone
/// stops thin to ~.35 so the video actually reads, 900ms in), and theater
/// ([theater], a few seconds into uninterrupted playback — the veils fall to
/// near-clear (~.12) and the whole page commits to the picture, on a slow
/// 1.2s ease). Lights-up from any state is a snappy 250ms (a DPAD move means
/// the user is browsing again). Direct translucent paint (DecoratedBox with
/// lerped colors, never an Opacity layer), so it is safe over the underlay
/// trailer's punched hole; the gradient only re-paints during the transitions,
/// never at idle.
class _DiscoverStageVeils extends StatelessWidget {
  final ValueListenable<bool> showing;
  final ValueListenable<bool> theater;

  /// STAGE layout: there is no pane divide to light for, so the tint moves to
  /// where the text actually is — a left column and a bottom ramp under the
  /// shelf, with the right/upper art left clear. Same browse→playback→theater
  /// ladder and the same baked-alpha paint (never an Opacity layer, which
  /// forces a per-frame full-screen saveLayer on weak TV GPUs).
  final bool stage;

  const _DiscoverStageVeils({
    required this.showing,
    required this.theater,
    this.stage = false,
  });

  /// Page ink at an alpha walked along the browse→playback→theater ladder by
  /// [phase] (0..2). [base] is the page ink, captured once at build — this
  /// runs per transition frame. withValues (not fade): the ladder's alphas
  /// are ABSOLUTE, and the ground token is opaque on every theme, so the two
  /// are equivalent here.
  static Color _ink(
    Color base,
    double browse,
    double play,
    double deep,
    double phase,
  ) {
    final a = phase <= 1.0
        ? browse + (play - browse) * phase
        : play + (deep - play) * (phase - 1.0);
    return base.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppThemeScope.of(context).home.bg;
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, on, __) => ValueListenableBuilder<bool>(
          valueListenable: theater,
          builder: (_, deep, __) => TweenAnimationBuilder<double>(
            tween: Tween(end: deep ? 2.0 : (on ? 1.0 : 0.0)),
            duration: deep
                ? const Duration(milliseconds: 1200)
                : on
                ? const Duration(milliseconds: 900)
                // Lights-up fires on the KEYPRESS that interrupts a
                // trailer, and each of its frames re-lerps and repaints
                // three full-screen gradients — on an Amlogic/Mali box
                // that lands as input lag on the exact frame the user
                // pressed. Snap it there; the slow lights-down legs run
                // at rest, where nobody is waiting on a frame.
                : PlatformUtil.isAndroidTvCached
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            builder: (_, t, __) => stage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Left column: seats the identity block. Dissolves by
                      // two thirds across so the art keeps the right half.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _ink(ink, 0.88, 0.56, 0.10, t),
                              _ink(ink, 0.60, 0.34, 0.06, t),
                              const Color(0x000D0B1A),
                            ],
                            stops: const [0.0, 0.32, 0.66],
                          ),
                        ),
                      ),
                      // Bottom ramp: seats the shelf and the filter line's
                      // opposite edge; top edge gets a whisper so the filter
                      // segments stay legible over bright art.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              _ink(ink, 0.94, 0.70, 0.16, t),
                              _ink(ink, 0.74, 0.46, 0.10, t),
                              const Color(0x000D0B1A),
                              _ink(ink, 0.30, 0.14, 0.04, t),
                            ],
                            stops: const [0.0, 0.20, 0.52, 1.0],
                          ),
                        ),
                      ),
                      // The text pocket, straight off the Canvas board: the
                      // identity block's meta line and plot are allowed to run
                      // to half the frame, past where the left column has
                      // dissolved, and the bottom ramp alone leaves their
                      // right end sitting on bare artwork. Centred under the
                      // block, gone well before mid-screen so the art keeps
                      // its glow everywhere else.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.72, 0.55),
                            radius: 0.95,
                            colors: [
                              _ink(ink, 0.80, 0.45, 0.06, t),
                              const Color(0x000D0B1A),
                            ],
                            stops: const [0.12, 1.0],
                          ),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _ink(
                                ink,
                                0.58,
                                0.34,
                                0.10,
                                t,
                              ), // art zone / rail text
                              _ink(ink, 0.62, 0.38, 0.12, t),
                              // Theater goes near-clear on the grid side too — the
                              // panel content fades itself, so the video must not be
                              // buried under ink there ("black right side").
                              _ink(ink, 0.84, 0.68, 0.18, t), // the pane divide
                              _ink(ink, 0.94, 0.86, 0.24, t), // under the grid
                              _ink(ink, 1.0, 0.92, 0.30, t),
                            ],
                            stops: const [0.0, 0.34, 0.52, 0.74, 1.0],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _ink(
                                ink,
                                0.34,
                                0.15,
                                0.06,
                                t,
                              ), // settle the top edge
                              const Color(0x000D0B1A),
                              const Color(0x000D0B1A),
                              _ink(
                                ink,
                                0.88,
                                0.58,
                                0.28,
                                t,
                              ), // melt into the bottom
                            ],
                            stops: const [0.0, 0.26, 0.55, 0.92],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Lights-off over the grid while the trailer PLAYS (pre-theater): an animated
/// baked-color wash covering the panel side (posters + filter line recede,
/// Home-rows style), feathered over its first 15% so no hard seam cuts the
/// stage at the pane divide. In THEATER the wash dissolves back to zero — there
/// the panel content fades itself (host-side AnimatedOpacity) and ink here
/// would just bury the now-unveiled video. Sits ABOVE the two-pane. Any DPAD
/// move drops the signals and the lights snap back up in 250ms.
class _DiscoverGridDim extends StatelessWidget {
  final ValueListenable<bool> showing;
  final ValueListenable<bool> theater;
  final double leftInset;

  const _DiscoverGridDim({
    required this.showing,
    required this.theater,
    required this.leftInset,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppThemeScope.of(context).home.bg;
    return Positioned(
      left: leftInset,
      top: 0,
      right: 0,
      bottom: 0,
      // RepaintBoundary inside the Positioned (which must stay a direct Stack
      // child): the dim animates a panel-wide gradient per frame during the
      // 250/900ms transitions — keep those frames off the stage layer.
      child: RepaintBoundary(
        child: IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: showing,
            builder: (_, on, __) => ValueListenableBuilder<bool>(
              valueListenable: theater,
              builder: (_, deep, __) => TweenAnimationBuilder<double>(
                tween: Tween(end: deep ? 2.0 : (on ? 1.0 : 0.0)),
                duration: deep
                    ? const Duration(milliseconds: 1200)
                    : on
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                builder: (_, t, __) {
                  // 0→1: 0 → .52 (playback); 1→2: .52 → 0 (theater unveils).
                  final a = t <= 1.0 ? 0.52 * t : 0.52 * (2.0 - t);
                  if (a <= 0.001) return const SizedBox.shrink();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        // withValues (not fade): absolute alphas over an
                        // always-opaque ground token — equivalent, and the
                        // ramp's 0.0 end must stay a true clear.
                        colors: [
                          ink.withValues(alpha: 0.0),
                          ink.withValues(alpha: a),
                        ],
                        stops: const [0.0, 0.15],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
