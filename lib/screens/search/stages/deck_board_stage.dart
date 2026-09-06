import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/skeleton_poster.dart';
import '../fav_row_ref.dart';
import '../search_board_runtime.dart';
import '../stage_visuals.dart';
import 'stage_shelf_content.dart';

typedef DeckStageBindings = ({
  AppTheme Function() readTheme,
  StageRailView? Function() resolveRail,
  VoidCallback seedFocus,
  int Function(FavRowRef) favouriteCount,
  bool Function() readTheater,
  bool Function() readTrailerActive,
  int Function() cacheWidth,
  int Function() cacheHeight,
  ValueListenable<int> column,
  ValueListenable<CanvasFavFocus?> favourite,
  ValueListenable<StremioMeta?> heroItem,
  ValueListenable<StremioMeta?> enriched,
  ValueListenable<bool> trailerShowing,
  double Function(BuildContext, double, {required double maxH}) railBoxHeight,
  double Function(BuildContext) labelHeight,
  double Function(BuildContext, double) favouriteWidth,
  double Function(double) posterWidth,
  Widget Function(FavRowRef, String, int) favouriteCell,
  Widget Function(StageRailView) railLabel,
  Widget Function(double) buildTrailer,
  Widget Function(double) buildLive,
  StageShelfContent shelf,
});

// DECK metrics.
const double _kDeckPanelPad = 48;
const double _kDeckCardRightPad = 36;
const double _kDeckCardRadius = 22;
const double _kDeckRailGap = 18;
const double _kDeckRailTail = 26;

class DeckStage extends StatelessWidget {
  const DeckStage({super.key, required this.bindings, required this.isTelevision});
  final DeckStageBindings bindings;
  final bool isTelevision;

  // ── DECK view ────────────────────────────────────────────────────────────

  /// DECK: the trailer stops being wallpaper and becomes an OBJECT — a
  /// rounded 16:9 card floating on ink with the next two titles stacked
  /// behind it. The hole follows the card's laid-out rect (Canvas proved that
  /// needs no native work); the rounded corners are four ink wedges painted
  /// ABOVE the layers, because a clip would put a saveLayer over the hole.
  @override
  Widget build(BuildContext context) {
    final app = bindings.readTheme();
    final view = bindings.resolveRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: isTelevision);
    }
    bindings.seedFocus();
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail ? bindings.favouriteCount(rail.favKind!) : items.length;

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;
        // RESERVE THE RAIL FIRST, then let the card have what is left — the
        // other way round, a tall card on a short board silently pushes the
        // rail off the bottom edge.
        final railBoxH = bindings.railBoxHeight(
          context,
          boardH * 0.24,
          maxH: boardH * 0.34,
        );
        final railZoneH =
            bindings.labelHeight(context) +
            10 +
            railBoxH +
            _kDeckRailTail;
        final cardTop = boardH * 0.11;
        // The TRUE remainder — never clamped up, which would hand the card
        // height the rail has already been promised.
        var cardH = max(0.0, boardH - cardTop - railZoneH - _kDeckRailGap);
        var cardW = cardH * 16 / 9;
        final maxCardW = boardW * 0.56;
        if (cardW > maxCardW) {
          cardW = maxCardW;
          cardH = cardW * 9 / 16;
        }
        final cardLeft = boardW - cardW - _kDeckCardRightPad;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Constant ground — a single radial, never tweened.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.55, -0.35),
                    radius: 1.15,
                    colors: [
                      Color(0xFF1B1730),
                      Color(0xFF0C0A16),
                      Color(0xFF08070F),
                    ],
                    stops: [0.0, 0.62, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            // The deck's two peek cards — STATIC art of the next two titles
            // on this rail. Never a second video: one engine, one card.
            // Listens to the focused column so the stack DEALS as you move;
            // only this subtree rebuilds.
            ValueListenableBuilder<int>(
              valueListenable: bindings.column,
              builder: (context, focusedCol, _) => Stack(
                children: _deckPeeks(
                  items: items,
                  favRail: favRail,
                  focused: focusedCol,
                  left: cardLeft,
                  top: cardTop,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
            // THE CARD.
            Positioned(
              left: cardLeft,
              top: cardTop,
              width: cardW,
              height: cardH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CanvasArtLayer(
                    item: bindings.heroItem,
                    enriched: bindings.enriched,
                    fav: bindings.favourite,
                    cacheWidth: bindings.cacheWidth(),
                    cacheHeight: bindings.cacheHeight(),
                  ),
                  if (bindings.readTrailerActive())
                    bindings.buildTrailer(cardH),
                  if (bindings.readTrailerActive())
                    bindings.buildLive(cardH),
                  // Rounded corners WITHOUT a clip: four ink wedges painted
                  // over the layers. A ClipRRect here would wrap the punch
                  // hole in a saveLayer and break the blend.
                  IgnorePointer(
                    child: CustomPaint(
                      painter: const CornerWedges(
                        radius: _kDeckCardRadius,
                        color: Color(0xFF0C0A16),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // A hairline inside the wedges reads as the card's edge.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_kDeckCardRadius),
                        border: Border.all(
                          color: app.fade(app.core.tx, 0.10),
                          width: 1,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            // IDENTITY column, left of the card.
            Positioned(
              left: _kDeckPanelPad,
              top: 0,
              width: (cardLeft - _kDeckPanelPad - 40).clamp(140.0, 560.0),
              bottom: railZoneH,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<CanvasFavFocus?>(
                    valueListenable: bindings.favourite,
                    builder: (context, fav, _) => fav != null
                        ? StageFavIdentity(fav: fav)
                        : CanvasIdentity(
                            item: bindings.heroItem,
                            enriched: bindings.enriched,
                            trailerShowing: bindings.trailerShowing,
                            variant:
                                boardH - railZoneH >=
                                    stageNarrowIdentityH(context)
                                ? StageIdentityVariant.narrow
                                : StageIdentityVariant.headline,
                            maxWidth: (cardLeft - _kDeckPanelPad - 40).clamp(
                              140.0,
                              560.0,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            // The rail. Recedes with the lights in theater, cells still
            // MOUNTED so focus survives.
            Positioned(
              left: _kDeckPanelPad,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: _kDeckPanelPad),
                        child: bindings.railLabel(view),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: railBoxH,
                        child: ListView.builder(
                          key: ValueKey('deck-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          itemCount: count,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: favRail
                                    ? bindings.favouriteWidth(context, railBoxH)
                                    : bindings.posterWidth(railBoxH),
                                child: favRail
                                    ? bindings.favouriteCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: railBoxH,
                                        child: bindings.shelf.cell(
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
                      const SizedBox(height: _kDeckRailTail),
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

  /// The two cards stacked behind the hero — the NEXT two titles on this
  /// rail, drawn from the focused column so moving along the rail deals them
  /// forward. Static art, no focus, no video.
  List<Widget> _deckPeeks({
    required List<StremioMeta> items,
    required bool favRail,
    required int focused,
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    // Favourites rails have no StremioMeta to draw from — the deck simply
    // shows the single card, which is correct: a favourite has no "next".
    if (favRail || items.isEmpty) return const [];
    final at = focused.clamp(0, items.length - 1);
    final peeks = <Widget>[];
    // Painted far-to-near so the nearer card overlaps the farther one.
    for (final spec in const [
      (step: 2, dx: 0.19, scale: 0.87, alpha: 0.30),
      (step: 1, dx: 0.10, scale: 0.94, alpha: 0.52),
    ]) {
      final i = at + spec.step;
      if (i >= items.length) continue;
      final art = wideArtUrl(items[i]);
      if (art == null || art.isEmpty) continue;
      peeks.add(
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: spec.alpha,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: Offset(spec.dx, 0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: Transform.scale(
                  scale: spec.scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kDeckCardRadius),
                    child: CachedNetworkImage(
                      key: ValueKey('deck-peek-${spec.step}-$art'),
                      imageUrl: art,
                      fit: BoxFit.cover,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return peeks;
  }
}
