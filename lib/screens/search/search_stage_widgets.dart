part of '../search_screen.dart';








/// What Tonight's big card says about the focused entry. Derived per focus —
/// the OK hint has to tell the truth: a part-watched title resumes, a catalog
/// title opens, a favourite is watched.

/// The caption block on Tonight's card: title art, what you are about to do,
/// the episode, how much is left and the progress bar. Everything is driven
/// by listenables so a DPAD move repaints this block alone.
class _TonightCardCaption extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final ValueListenable<CanvasFavFocus?> fav;
  final ValueListenable<TonightCardInfo?> info;

  const _TonightCardCaption({
    required this.item,
    required this.enriched,
    required this.fav,
    required this.info,
  });

  /// Minutes left from a '60 min'-shaped runtime and a 0..1 progress.
  static String? _timeLeft(String? runtime, double? progress) {
    if (runtime == null || progress == null || progress <= 0) return null;
    final m = RegExp(r'(\d+)').firstMatch(runtime);
    if (m == null) return null;
    final total = int.tryParse(m.group(1)!);
    if (total == null || total <= 0) return null;
    final left = ((1 - progress.clamp(0.0, 1.0)) * total).round();
    return left <= 0 ? null : '$left min left';
  }

  @override
  Widget build(BuildContext context) {
    // Hoisted: `fav` fires on every focus move across the Tonight rail.
    final tx = AppThemeScope.of(context).core.tx;
    return ValueListenableBuilder<CanvasFavFocus?>(
      valueListenable: fav,
      builder: (context, favFocus, _) {
        if (favFocus != null) {
          return _block(
            context,
            hold: null,
            titleWidget: Text(
              favFocus.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tx,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
              ),
            ),
            line: favFocus.subtitle,
            action: 'Watch',
            progress: null,
          );
        }
        return ValueListenableBuilder<StremioMeta?>(
          valueListenable: item,
          builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
            valueListenable: enriched,
            builder: (context, en, _) =>
                ValueListenableBuilder<TonightCardInfo?>(
                  valueListenable: info,
                  builder: (context, nfo, _) {
                    final it0 = it;
                    if (it0 == null) return const SizedBox.shrink();
                    final enr = (en != null && sameCanvasTitle(it0, en))
                        ? en
                        : null;
                    final logo =
                        firstNonEmpty(enr?.logo, it0.logo) ??
                        metahubLogoUrl(it0);
                    final runtime = firstNonEmpty(enr?.runtime, it0.runtime);
                    final left = _timeLeft(runtime, nfo?.progress);
                    final parts = <String>[
                      if (nfo?.episode != null) nfo!.episode!,
                      if (left != null) left else if (runtime != null) runtime,
                      if (nfo?.episode == null && left == null)
                        (it0.type == 'series' ? 'SERIES' : 'MOVIE'),
                    ];
                    return _block(
                      context,
                      hold: nfo?.holdAction,
                      titleWidget: logo != null
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 46,
                                maxWidth: 300,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: logo,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                memCacheWidth: 400,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) =>
                                    const SizedBox(height: 46),
                                errorWidget: (_, __, ___) =>
                                    _fallbackTitle(it0.name),
                              ),
                            )
                          : _fallbackTitle(it0.name),
                      line: parts.join('  ·  '),
                      action: nfo?.action ?? 'Open',
                      progress: nfo?.progress,
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  static Widget _fallbackTitle(String name) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
    ),
  );

  Widget _block(
    BuildContext context, {
    required Widget titleWidget,
    required String line,
    required String action,
    required String? hold,
    required double? progress,
  }) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.74),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (hold != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: app.fade(app.core.tx, 0.30)),
                  borderRadius: app.shape.br(20),
                ),
                child: Text(
                  'HOLD  $hold',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: app.core.tx.withValues(alpha: 0.92),
                borderRadius: app.shape.br(20),
              ),
              child: Text(
                'OK  $action',
                style: const TextStyle(
                  color: Color(0xFF12101F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        if (progress != null && progress > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: app.shape.br(3),
            child: SizedBox(
              height: 5,
              child: ColoredBox(
                color: app.core.tx.withValues(alpha: 0.22),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}






/// The Canvas stage's constant lighting: a left column scrim (identity
/// legibility), a bottom ramp (tabs/shelf legibility) and a bottom-left
/// "text pocket" — a soft radial wash under the identity block. Premium OTT
/// scrims are far heavier than they look (85-95% ink at the text baseline);
/// because the falloff is gradual and in the page's own ink colour it reads
/// as LIGHTING, never as a plate behind the text — bright art (snow, skies,
/// white key art) stays legible without the stage going flat. Painted ABOVE
/// both the idle art and the live video — plain gradient draws over the
/// punch hole, the same on-device-proven pattern as the region feathers.
/// How a stage lights its art. Every variant is a set of CONSTANT gradients
/// painted above the art AND the video — plain draws over the punch hole, the
/// on-device-proven pattern (never an Opacity wrapper, never a tween).
enum _StageScrimVariant {
  /// Canvas / Deck / Tonight: left column + bottom ramp + a bottom-left text
  /// pocket, seating an edge-anchored identity block.
  canvas,

  /// Promenade: symmetric — a bottom ramp for the strip, a centred pocket
  /// under the identity, and a light top wash so the trailer pill reads.
  centered,

  /// Atrium: the art is a COLUMN, so the only left lighting it needs is a
  /// narrow feather melting into the ink panel at the seam, plus a bottom
  /// ramp under the poster wall.
  seam,
}

class _CanvasScrims extends StatelessWidget {
  /// Theater mode: ALL the stage lighting fades — the left column scrim, the
  /// bottom ramp and the text pocket exist to seat text and shelf that have
  /// receded, so the video gets the truly clean frame (the logo, gliding to
  /// the top-left corner, carries its own art shadows).
  final bool theater;

  final _StageScrimVariant variant;

  const _CanvasScrims({
    this.theater = false,
    this.variant = _StageScrimVariant.canvas,
  });

  static const _canvasLayers = <Widget>[
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF00D0B1A), Color(0xA80D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.32, 0.66],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xC20D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.20, 0.50],
        ),
      ),
    ),
    // The text pocket: centred under the identity block (lower-left
    // quadrant), dissolving well before mid-screen so the art/video
    // keeps its glow everywhere else.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.72, 0.55),
          radius: 0.95,
          colors: [Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.12, 1.0],
        ),
      ),
    ),
  ];

  static const _centeredLayers = <Widget>[
    // Bottom ramp — deeper than Canvas's: the strip sits lower and the
    // identity stands directly on it.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF70D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.24, 0.56],
        ),
      ),
    ),
    // Centre pocket: the symmetric twin of Canvas's corner pocket, seating
    // the centred logo + meta without flattening the frame's edges.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.30),
          radius: 0.78,
          colors: [Color(0xB80D0B1A), Color(0x000D0B1A)],
          stops: [0.10, 1.0],
        ),
      ),
    ),
    // A whisper at the top so the TRAILER pill never sits on bright sky.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x730D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.22],
        ),
      ),
    ),
  ];

  static const _seamLayers = <Widget>[
    // The seam: a narrow melt into the ink panel on the left. Short, so the
    // art keeps its width — the panel beside it already carries the text.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF20D0B1A), Color(0x8C0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.07, 0.22],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.36, 0.76],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final layers = switch (variant) {
      _StageScrimVariant.canvas => _canvasLayers,
      _StageScrimVariant.centered => _centeredLayers,
      _StageScrimVariant.seam => _seamLayers,
    };
    return AnimatedOpacity(
      opacity: theater ? 0.0 : 1.0,
      duration: theater
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }
}




// The board's card focus chrome ([CardFocusRise]) moved to
// widgets/home/card_focus_rise.dart — the Discover stage's shelf wears the
// same grammar, and focus feel has to be tuned in exactly one place.

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
