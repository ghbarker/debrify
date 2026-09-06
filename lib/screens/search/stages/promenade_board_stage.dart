import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/skeleton_poster.dart';
import '../fav_row_ref.dart';
import '../search_board_runtime.dart';
import '../stage_visuals.dart';

typedef PromenadeStageBindings = ({
  StageRailView? Function() resolveRail,
  VoidCallback seedFocus,
  int Function(FavRowRef) favouriteCount,
  bool Function() readTheater,
  bool Function() readTrailerActive,
  int Function() cacheWidth,
  int Function() cacheHeight,
  ValueListenable<StremioMeta?> heroItem,
  ValueListenable<StremioMeta?> enriched,
  ValueListenable<CanvasFavFocus?> favourite,
  ValueListenable<bool> trailerShowing,
  Widget Function(double) buildTrailer,
  Widget Function(double) buildLive,
  Widget Function(bool) buildScrims,
  double Function(BuildContext, double, {required double maxH}) railBoxHeight,
  double Function(BuildContext, double) favouriteWidth,
  double Function(BuildContext) labelHeight,
  Widget Function(StageRailView) railLabel,
  Widget Function(FavRowRef, String, int) favouriteCell,
  Widget Function(CanvasRail, String, List<StremioMeta>, List<FocusNode>, int) cell,
});

/// Gap between the centred rail label and the strip below it.
const double _kPromLabelGap = 14;

/// Trailing spacer under the strip.
const double _kPromStripTail = 24;

/// Air between the identity block and the label row under it.
const double _kPromIdentityGap = 26;

class PromenadeStage extends StatelessWidget {
  const PromenadeStage({super.key, required this.bindings, required this.isTelevision});
  final PromenadeStageBindings bindings;
  final bool isTelevision;

  // ── PROMENADE view ───────────────────────────────────────────────────────

  /// PROMENADE: Canvas's stage, symmetric. The identity sits centred in the
  /// lower third and the rail becomes a CENTRE-LOCKED strip — the focused
  /// cell is pinned to the middle of the board and the strip travels under
  /// it. Centre-lock is free: board cards already
  /// `ensureVisible(alignment: 0.5)`; the half-viewport pads below simply let
  /// the FIRST and LAST cell reach the middle too, which a plain list can't.
  @override
  Widget build(BuildContext context) {
    final view = bindings.resolveRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: isTelevision);
    }
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    bindings.seedFocus();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        // ONE box height for every rail kind; the kinds fill it differently
        // (see [bindings.favouriteWidth]) so neither wastes the other's space.
        final double stripBoxH = bindings.railBoxHeight(
          context,
          boardH * 0.27,
          maxH: boardH * 0.42,
        );
        final double cellW = favRail
            ? bindings.favouriteWidth(context, stripBoxH)
            : stripBoxH * 16 / 9;
        // Measured bottom-up, exactly like Canvas's shelfColumnH, so the
        // identity's clearance is DERIVED and can never drift into the strip.
        final columnH =
            _kPromStripTail +
            stripBoxH +
            _kPromLabelGap +
            bindings.labelHeight(context);
        // Half-viewport pads: without them the list clamps at its ends and
        // the first/last cell can never reach the centre lock.
        final double sidePad = ((boardW - cellW) / 2).clamp(0.0, boardW / 2);
        final itemCount = favRail
            ? bindings.favouriteCount(rail.favKind!)
            : items.length;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art, BELOW the punch hole so the
            // video replaces it in place when the trailer starts.
            CanvasArtLayer(
              item: bindings.heroItem,
              enriched: bindings.enriched,
              fav: bindings.favourite,
              cacheWidth: bindings.cacheWidth(),
              cacheHeight: bindings.cacheHeight(),
            ),
            if (bindings.readTrailerActive())
              bindings.buildTrailer(boardH),
            if (bindings.readTrailerActive())
              bindings.buildLive(boardH),
            IgnorePointer(
              child: bindings.buildScrims(bindings.readTheater()),
            ),
            // Centred identity — which glides to the TOP-LEFT in theater, the
            // Netflix billboard move Canvas already makes. A logo parked in
            // the middle of a clean full-screen trailer reads as something
            // left behind; in the corner it reads as a signature. Meta and
            // synopsis have already faded by then (they go with
            // trailerShowing, before the dwell), so what travels is the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: bindings.readTheater() ? 36 : 0,
                    bottom: bindings.readTheater() ? 0 : columnH + _kPromIdentityGap,
                  ),
                  duration: bindings.readTheater()
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: bindings.readTheater()
                        ? Alignment.topLeft
                        : Alignment.bottomCenter,
                    duration: bindings.readTheater()
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedScale(
                      scale: bindings.readTheater() ? 0.7 : 1.0,
                      alignment: Alignment.topLeft,
                      duration: bindings.readTheater()
                          ? const Duration(milliseconds: 900)
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      child: ValueListenableBuilder<CanvasFavFocus?>(
                        valueListenable: bindings.favourite,
                        builder: (context, fav, _) => fav != null
                            ? StageFavIdentity(fav: fav, centered: true)
                            : CanvasIdentity(
                                item: bindings.heroItem,
                                enriched: bindings.enriched,
                                trailerShowing: bindings.trailerShowing,
                                variant: StageIdentityVariant.centered,
                                maxWidth: boardW - 96,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail label + the strip. Theater recede: slide + fade, cells stay
            // MOUNTED so focus survives and the wake keypress still moves.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: bindings.readTheater() ? const Offset(0, 0.12) : Offset.zero,
                duration: bindings.readTheater()
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: bindings.readTheater() ? 0.0 : 1.0,
                  duration: bindings.readTheater()
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kPromLabelGap,
                        ),
                        child: bindings.railLabel(view),
                      ),
                      SizedBox(
                        height: stripBoxH,
                        child: ListView.builder(
                          // Keyed by rail IDENTITY: insertions above the
                          // active rail must never read as a content swap.
                          key: ValueKey('prom-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          padding: EdgeInsets.symmetric(horizontal: sidePad),
                          itemCount: itemCount,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: cellW,
                                child: favRail
                                    ? bindings.favouriteCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: stripBoxH,
                                        child: bindings.cell(
                                          rail,
                                          railKey,
                                          items,
                                          nodes,
                                          col,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kPromStripTail),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
