import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/stremio_addon.dart';
import '../../theme/app_theme_scope.dart';

const double stageMosaicLogoHeight = 52;

/// The headline variant's text fallback is smaller than a stage title — it is
/// a caption over a wall, not a billboard. Shared with `_mosaicHeadHeight` on the host so
/// the band that reserves space for it can't drift.
const double stageHeadlineTitleSize = 24;


/// Metahub title-logo URL derived synchronously from an IMDb id (same trick
/// the hero uses) — lets the Canvas identity show studio title art without
/// waiting for /meta enrichment. Null when the item has no IMDb-shaped id.
String? metahubLogoUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null ? null : 'https://images.metahub.space/logo/medium/$tt/img';
}


/// Metahub 16:9 still, derived the same synchronous way — catalog items carry
/// a poster but rarely a backdrop, and the wide-cell layouts (Promenade's
/// strip, Tonight's queue) need landscape art the moment a rail paints, not
/// after /meta enrichment. Null when the item has no IMDb-shaped id.
String? metahubBackgroundUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null
      ? null
      : 'https://images.metahub.space/background/medium/$tt/img';
}


/// Best available wide art for a 16:9 cell: whatever the item already carries,
/// then the derived metahub still, then the poster (cover-cropped) so a cell
/// is never empty.
String? wideArtUrl(StremioMeta item) =>
    firstNonEmpty(item.background, metahubBackgroundUrl(item)) ??
    firstNonEmpty(item.poster, null);


/// Whether [enriched] describes the same title as [item]. Raw id equality is
/// not enough: an addon can list a title as `tmdb:603` while the /meta
/// record — fetched via the IMDb id the addon supplied — comes back as
/// `tt0133093`. Compare canonical IMDb identity too, or valid enrichment
/// gets rejected and Canvas loses its backdrop/description/rating.
bool sameCanvasTitle(StremioMeta item, StremioMeta enriched) {
  if (enriched.id == item.id) return true;
  final itTt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  final enTt =
      enriched.imdbId ?? (enriched.id.startsWith('tt') ? enriched.id : null);
  return itTt != null && itTt == enTt;
}


/// First non-empty of two optional strings (merge helper: enriched field
/// wins only when it actually carries a value).
String? firstNonEmpty(String? a, String? b) =>
    (a != null && a.isNotEmpty) ? a : ((b != null && b.isNotEmpty) ? b : null);


/// Paints the four corner "wedges" that make a rectangle read as a rounded
/// card — the area between the rect and its rounded inset, filled with the
/// page ink. Used instead of a ClipRRect wherever the box contains the
/// underlay trailer: a clip would introduce a saveLayer over the punch hole
/// and break its BlendMode.clear against the translucent surface, while a
/// plain fill painted ABOVE the hole is the proven pattern.
class CornerWedges extends CustomPainter {
  final double radius;
  final Color color;
  const CornerWedges({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(CornerWedges old) =>
      old.radius != radius || old.color != color;
}


/// What a stage board resolved for this frame (see
/// `_SearchScreenState._resolveStageRail` on the host) — the rail list, which one is
/// active, its identity key, its items and its focus nodes.

/// The identity block a stage shows while a FAVOURITES cell has focus.
/// Favourites aren't StremioMeta, so the logo/meta/synopsis pipeline has
/// nothing true to say about them — this is the favourite's own name and
/// source line, in the same type as the catalog identity above it.
class StageFavIdentity extends StatelessWidget {
  final CanvasFavFocus fav;
  final bool centered;

  const StageFavIdentity({super.key, required this.fav, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fav.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.core.tx,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          fav.subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.fade(app.core.tx, 0.6),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}


/// One row of Tonight's Continue queue: a 16:9 still, the title, the episode
/// and a progress bar. Carries the same focus grammar and the same hold-OK
/// menu as a Continue Watching card, so nothing is lost by laying the row out
/// horizontally instead of as a poster.


/// One row of Tonight's Continue Watching queue: which CW rail it came from
/// and which column within it (so the cell's FocusNode, progress, episode
/// label and open/remove actions all come from the row's own contract).

/// What the Canvas stage should show while a FAVOURITES cell has focus —
/// favourites aren't StremioMeta, so the hero pipeline can't describe them;
/// this lightweight override carries the focused item's own art + name
/// instead (null = a catalog/CW item owns the stage as usual).
class CanvasFavFocus {
  final String? art;
  final BoxFit fit;
  final String title;
  final String subtitle;
  const CanvasFavFocus({
    required this.art,
    this.fit = BoxFit.cover,
    required this.title,
    required this.subtitle,
  });
}


/// Canvas stage floor + full-bleed key art for the settled hero item. Sits
/// BELOW the underlay punch hole; the AnimatedSwitcher fade wraps only this
/// sibling, never the engine, so the hole's BlendMode.clear is untouched.
/// Metahub backdrop URLs that came back 404 this session — the same
/// memo the title-logo art keeps, for the same reason: without it every
/// focus on a title with no derived still re-requests a known-dead URL.
///
/// Bounded: a long session browsing paginated catalogs would otherwise keep
/// every miss for the life of the process. A full clear is fine — the cost of
/// forgetting is one re-request per title, exactly what the memo saves.
final Set<String> _deadBackdropUrls = <String>{};

const int _kDeadBackdropMemoMax = 512;


void _rememberDeadBackdrop(String url) {
  if (_deadBackdropUrls.length >= _kDeadBackdropMemoMax) {
    _deadBackdropUrls.clear();
  }
  _deadBackdropUrls.add(url);
}


class CanvasArtLayer extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final int cacheWidth;
  final int cacheHeight;

  /// Non-null while a favourites cell has focus: its art overrides the hero
  /// pipeline's (contain-fit logos render centred over the floor instead of
  /// being cover-stretched across the canvas).
  final ValueListenable<CanvasFavFocus?> fav;

  const CanvasArtLayer({
    super.key,
    required this.item,
    required this.enriched,
    required this.fav,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) => ValueListenableBuilder<CanvasFavFocus?>(
          valueListenable: fav,
          builder: (context, fav, _) {
            // Enrichment merged over the catalog item: matched by canonical
            // IMDb identity (ids can differ in form), and a sparse /meta
            // record can't erase a backdrop the catalog already carried.
            final enr = (it != null && en != null && sameCanvasTitle(it, en))
                ? en
                : null;
            // WIDE art first. The old chain fell straight from "no backdrop"
            // to the POSTER, which a 16:9 box has to crop to a horizontal
            // slice — on a title whose poster is a row of character portraits
            // that reads as several unrelated images stacked in one card. The
            // metahub still (derived synchronously from the IMDb id, exactly
            // like the title logo) is a real landscape frame and exists for
            // most titles; the poster stays as the last resort, applied by the
            // error branch below so a 404 still lands on something.
            final wide = it == null
                ? null
                : firstNonEmpty(enr?.background, it.background) ??
                      (_deadBackdropUrls.contains(
                            metahubBackgroundUrl(it) ?? '',
                          )
                          ? null
                          : metahubBackgroundUrl(it));
            final posterUrl = (it?.poster?.isNotEmpty ?? false)
                ? it!.poster
                : null;
            final bg = wide ?? posterUrl ?? '';
            final Widget art;
            final favArt = fav?.art;
            if (fav != null) {
              if (favArt == null || favArt.isEmpty) {
                art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
              } else if (fav.fit == BoxFit.contain) {
                art = Center(
                  key: ValueKey('canvas-fav-logo-$favArt'),
                  child: FractionallySizedBox(
                    widthFactor: 0.38,
                    heightFactor: 0.38,
                    child: CachedNetworkImage(
                      imageUrl: favArt,
                      fit: BoxFit.contain,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                );
              } else {
                art = CachedNetworkImage(
                  key: ValueKey(
                    'canvas-fav-art-$favArt-${cacheWidth}x$cacheHeight',
                  ),
                  imageUrl: favArt,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: cacheWidth,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
              }
            } else if (bg.isEmpty) {
              art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
            } else {
              // A derived metahub still can 404 (not every title has one).
              // Remember that so the next focus doesn't ask again, and fall
              // back to the poster in place rather than to an empty stage.
              final derived =
                  wide != null &&
                  wide != enr?.background &&
                  wide != it?.background;
              art = CachedNetworkImage(
                key: ValueKey('$bg-${cacheWidth}x$cacheHeight'),
                imageUrl: bg,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: wide != null ? cacheWidth : null,
                memCacheHeight: wide == null ? cacheHeight : null,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) {
                  if (derived) _rememberDeadBackdrop(bg);
                  if (posterUrl == null || bg == posterUrl) {
                    return const SizedBox.shrink();
                  }
                  return CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    memCacheHeight: cacheHeight,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  );
                },
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                // Opaque floor: the app shell can never show through a missing
                // or still-decoding backdrop.
                ColoredBox(color: app.home.bg),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  // AnimatedSwitcher's DEFAULT layout centres its children under
                  // LOOSE constraints, so a BoxFit.cover image sizes to its own
                  // aspect instead of the box. On Canvas the box is the whole
                  // 16:9 screen and it looked identical either way — but Atrium's
                  // art column is nearly square, and there the backdrop
                  // letterboxed with ink bands above and below it. Expand both
                  // the incoming and outgoing child so "cover" means the box.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: art,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


/// How a stage sets its identity block.
enum StageIdentityVariant {
  /// Canvas / Deck / Tonight: bottom-left, one meta line, three-line synopsis.
  stage,

  /// Atrium: a narrow ink column — the meta breaks onto two lines (facts, then
  /// genres) so it can never overrun the column, and the synopsis gets a
  /// fourth line because there is room for it.
  narrow,

  /// Promenade: centred, no synopsis — the composition is the point.
  centered,

  /// Mosaic: a fixed-height band above the wall — logo and one meta line,
  /// left-aligned, no synopsis (the grid is the content; this is a caption).
  headline,
}


/// The height a [StageIdentityVariant.narrow] block needs before its synopsis
/// is worth reserving: logo, two meta lines, the slot itself and the air
/// between them, at the current text scale. Below this the caller asks for
/// [StageIdentityVariant.headline] instead of clipping.
double stageNarrowIdentityH(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  return 56 + 10 + t.scale(23) * 1.3 * 2 + 6 + 10 + 78;
}


/// Canvas identity block: logo title-art (held EMPTY while loading, text only
/// when there's no URL or it 404s — the C5 "no text→logo flash" rule) over a
/// quiet meta line with the gold IMDb mark and a three-line synopsis. While
/// the ambient trailer plays, meta + synopsis fade away and the LOGO HOLDS
/// THE STAGE (the classic hero's premium move); any DPAD move brings them
/// back with the lights.
class CanvasIdentity extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;

  /// True while ambient video owns the stage — drives the meta/synopsis fade.
  final ValueListenable<bool> trailerShowing;

  final StageIdentityVariant variant;

  /// Width the block may occupy — the text column's real width, so the logo
  /// and synopsis are capped by geometry rather than by a guess.
  final double maxWidth;

  const CanvasIdentity({
    super.key,
    required this.item,
    required this.enriched,
    required this.trailerShowing,
    this.variant = StageIdentityVariant.stage,
    this.maxWidth = 430,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final centered = variant == StageIdentityVariant.centered;
    final narrow = variant == StageIdentityVariant.narrow;
    final headline = variant == StageIdentityVariant.headline;
    final noSynopsis = centered || headline;
    // The stage variant is Canvas's, and Canvas never capped its title or
    // meta line — only the synopsis. Keep that exactly, or long logo-less
    // titles start ellipsising where they never used to.
    final capWidth = variant != StageIdentityVariant.stage;
    Widget capped(Widget child) => capWidth
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          )
        : child;
    final cross = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final align = centered ? TextAlign.center : TextAlign.start;
    final double logoMaxW = centered
        ? 380
        : min(maxWidth, narrow ? 340 : (headline ? 360 : 300));
    final double logoMaxH = centered ? 66 : (headline ? stageMosaicLogoHeight : 56);
    // Fixed synopsis slot (see below) — 3 lines on a stage, 4 in a column.
    final int synLines = narrow ? 4 : 3;
    final double synSlot = narrow ? 78 : 58;

    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) {
          final it0 = it;
          if (it0 == null) return const SizedBox.shrink();
          // Enrichment merged over the catalog item FIELD BY FIELD: matched
          // by canonical IMDb identity (catalog ids can be tmdb:… while the
          // /meta record is tt…), and a sparse /meta response — it may carry
          // only a rating — can never erase what the catalog already knew.
          final enr = (en != null && sameCanvasTitle(it0, en)) ? en : null;
          final logo =
              firstNonEmpty(enr?.logo, it0.logo) ?? metahubLogoUrl(it0);
          final rating = enr?.imdbRating ?? it0.imdbRating;
          final year = firstNonEmpty(enr?.year, it0.year);
          final runtime = firstNonEmpty(enr?.runtime, it0.runtime);
          final genres = (enr?.genres != null && enr!.genres!.isNotEmpty)
              ? enr.genres
              : it0.genres;
          final description = firstNonEmpty(enr?.description, it0.description);
          final titleText = Text(
            it0.name,
            maxLines: narrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: app.core.tx,
              fontSize: headline ? stageHeadlineTitleSize : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.05,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
            ),
          );
          final genreText = (genres != null && genres.isNotEmpty)
              ? genres.take(2).join(' · ')
              : null;
          // The narrow column splits the line rather than ellipsising it.
          final metaParts = <String>[
            it0.type == 'series' ? 'SERIES' : 'MOVIE',
            if (year != null) year,
            if (runtime != null) runtime,
            if (!narrow && !headline && genreText != null) genreText,
          ];
          // Headline stands in for narrow on short columns, so it wraps the
          // genres the same way — in the facts row they would just be the
          // first thing ellipsised away.
          final wrapGenres = narrow || headline;
          final metaStyle = TextStyle(
            color: app.fade(app.core.tx, 0.7),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          );
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            // AnimatedSwitcher's DEFAULT layout centers its child — which
            // floated the whole identity block to mid-screen, off the left
            // scrim column it was designed to stand on. Pin it to the edge
            // the variant is anchored to.
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: centered
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: Column(
              key: ValueKey('canvas-id-${it0.id}'),
              crossAxisAlignment: cross,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: logoMaxW,
                      maxHeight: logoMaxH,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      alignment: centered
                          ? Alignment.bottomCenter
                          : Alignment.bottomLeft,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => SizedBox(height: logoMaxH),
                      errorWidget: (_, __, ___) => capped(titleText),
                    ),
                  )
                else
                  capped(titleText),
                const SizedBox(height: 10),
                // Meta + synopsis fade while the ambient trailer plays; the
                // logo above stays. Sibling-above-the-hole opacity — the
                // on-device-proven overlay pattern (region feathers/chip).
                ValueListenableBuilder<bool>(
                  valueListenable: trailerShowing,
                  builder: (context, showing, kid) => AnimatedOpacity(
                    opacity: showing ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOut,
                    child: kid,
                  ),
                  child: Column(
                    crossAxisAlignment: cross,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      capped(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: centered
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            if (rating != null) ...[
                              const Text(
                                'IMDb',
                                style: TextStyle(
                                  color: Color(0xFFF5C518),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: app.fade(app.core.tx, 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: app.fade(app.core.tx, 0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            Flexible(
                              child: Text(
                                metaParts.join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Narrow columns carry genres on their own line rather
                      // than ellipsising the facts away.
                      if (wrapGenres && genreText != null) ...[
                        const SizedBox(height: 6),
                        capped(
                          Text(
                            genreText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle.copyWith(
                              color: app.fade(app.core.tx, 0.46),
                            ),
                          ),
                        ),
                      ],
                      // Fixed-height synopsis slot: the description usually
                      // lands ~300ms after the settle (/meta enrichment), and
                      // this block is BOTTOM-anchored — reserving the lines
                      // keeps the logo from jumping when the text arrives.
                      // Promenade has no synopsis at all, so it reserves
                      // nothing.
                      if (!noSynopsis) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: synSlot,
                          child: description != null
                              ? ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxWidth,
                                  ),
                                  child: Text(
                                    description,
                                    maxLines: synLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: app.fade(app.core.tx, 0.78),
                                      fontSize: 12.5,
                                      height: 1.5,
                                      fontWeight: FontWeight.w500,
                                      // Crisp, tight shadow — a seasoning under
                                      // the scrim, never a smear (big radii
                                      // read as muddy text on TV panels).
                                      shadows: const [
                                        Shadow(
                                          color: Color(0xBF000000),
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
