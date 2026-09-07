import 'package:flutter/material.dart';

import '../../video_player/models/gesture_state.dart';
import '../../video_player/services/playback_ui_clock.dart';
import '../../video_player/widgets/dock_style.dart';
import '../../video_player/widgets/styled_dock.dart';
import 'schematic_kit.dart';

/// Schematics for the playback-adjacent rows — the play loader, the parents
/// guide — and the Player Controls row, whose styled arrangements are the
/// REAL dock (see [playerDockPreview]).

const double _w = SchematicKit.w;
const double _h = SchematicKit.h;

List<Widget> playLoaderSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  switch (optionId) {
    case 'classic':
      // Poster card with the stage checklist — the original look.
      return [
        k.at(
          60,
          30,
          _w - 120,
          _h - 60,
          k.panel(
            radius: 10,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(width: 50, child: k.tile(seed: 1, radius: 4)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        k.lines(const [0.8, 0.5], title: true),
                        const SizedBox(height: 10),
                        for (var i = 0; i < 4; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i < 2
                                        ? app.core.accent
                                        : app.fade(app.core.tx, 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: k.lines(
                                    [0.6 + (i % 2) * 0.2],
                                    height: 2.5,
                                    color: i < 2 ? app.core.tx : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    case 'marquee':
    default:
      // Full-bleed backdrop, title logo, stages on a segmented rail.
      return [
        k.at(0, 0, _w, _h, k.art(seed: 3)),
        k.at(0, 0, _w, _h, k.scrim()),
        k.at(
          _w / 2 - 70,
          58,
          140,
          30,
          k.lines(
            const [0.9, 0.5],
            title: true,
            height: 5,
            align: CrossAxisAlignment.center,
          ),
        ),
        k.at(
          _w / 2 - 50,
          104,
          100,
          8,
          k.lines(const [0.7], height: 2.5, align: CrossAxisAlignment.center),
        ),
        k.at(
          40,
          140,
          _w - 80,
          5,
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i < 2
                          ? app.core.accent
                          : app.fade(app.core.tx, 0.15),
                      borderRadius: app.shape.brPill,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ];
  }
}

List<Widget> parentsGuideSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  Widget meter(double f, {bool lit = false}) => Stack(
    children: [
      Container(
        height: 4,
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.1),
          borderRadius: app.shape.brPill,
        ),
      ),
      FractionallySizedBox(
        widthFactor: f,
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            color: lit ? app.core.accent : app.core.tx2,
            borderRadius: app.shape.brPill,
          ),
        ),
      ),
    ],
  );
  switch (optionId) {
    case 'classic':
      // The original compact expandable category list.
      return [
        k.at(16, 14, 160, 12, k.lines(const [0.55], title: true)),
        for (var i = 0; i < 5; i++)
          k.at(
            16,
            36 + i * 27,
            _w - 32,
            22,
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: app.core.hair)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: k.lines(
                      [0.3 + (i % 3) * 0.1],
                      height: 2.8,
                      color: app.core.tx,
                    ),
                  ),
                  SizedBox(width: 40, child: k.lines(const [1], height: 2.5)),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 10,
                    color: app.core.tx3,
                  ),
                ],
              ),
            ),
          ),
      ];
    case 'compass':
    default:
      // A severity dashboard: an overall dial, category signals, guidance.
      return [
        k.at(
          14,
          14,
          96,
          _h - 28,
          k.panel(
            radius: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: app.core.accent, width: 4),
                  ),
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 20,
                    child: k.lines(const [1], height: 4, color: app.core.tx),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 56,
                  child: k.lines(
                    const [1, 0.6],
                    height: 2.5,
                    align: CrossAxisAlignment.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < 2; i++)
          for (var j = 0; j < 2; j++)
            k.at(
              120 + j * 94,
              14 + i * 62,
              88,
              54,
              k.panel(
                radius: 8,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      k.lines(const [0.6], height: 2.8, color: app.core.tx),
                      const Spacer(),
                      meter(
                        [0.7, 0.3, 0.5, 0.15][i * 2 + j],
                        lit: i == 0 && j == 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        k.at(
          120,
          138,
          182,
          28,
          k.panel(
            radius: 8,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: k.lines(const [0.9, 0.7], height: 2.5, gap: 4),
            ),
          ),
        ),
      ];
  }
}

/// The Player Controls row.
///
/// The styled arrangements (Adaptive, Compact, Two-Tier, Cinema Bar) are the
/// REAL [StyledDock] laid out for a player viewport and scaled into the
/// canvas — the dock is a pure widget with its own fixed palette, no clock
/// ticker and no services, which is exactly what makes it embeddable.
/// Classic is the legacy control bar, drawn as a schematic.
///
/// [variant] is `palette|size`, the two secondary prefs the row itself does
/// not choose but the picture should honour.
List<Widget> playerDockPreview(
  SchematicKit k,
  String optionId,
  String? variant,
) {
  final style = PlayerDockStyle.fromPref(optionId);
  final parts = (variant ?? '').split('|');
  final palette = PlayerDockPalette.fromPref(
    parts.isNotEmpty ? parts[0] : null,
  );
  final size = PlayerDockSize.fromPref(parts.length > 1 ? parts[1] : null);
  if (!style.isStyled) return _classicDock(k);
  return [
    k.at(0, 0, _w, _h, k.art(seed: 2)),
    k.at(0, 0, _w, _h, DockPreview(style: style, palette: palette, size: size)),
  ];
}

/// Today's controls: a bottom bar with transport, seekbar and time.
List<Widget> _classicDock(SchematicKit k) {
  final app = k.app;
  return [
    k.at(0, 0, _w, _h, k.art(seed: 2)),
    k.at(0, _h / 2, _w, _h / 2, k.scrim()),
    k.at(
      12,
      10,
      10,
      10,
      Icon(Icons.arrow_back_rounded, size: 10, color: app.core.tx),
    ),
    k.at(28, 12, 120, 8, k.lines(const [0.8], height: 3, color: app.core.tx)),
    k.at(
      _w / 2 - 14,
      _h / 2 - 14,
      28,
      28,
      Icon(Icons.play_arrow_rounded, size: 28, color: app.core.tx),
    ),
    k.at(
      _w / 2 - 50,
      _h / 2 - 6,
      12,
      12,
      Icon(Icons.replay_10_rounded, size: 12, color: app.core.tx),
    ),
    k.at(
      _w / 2 + 38,
      _h / 2 - 6,
      12,
      12,
      Icon(Icons.forward_10_rounded, size: 12, color: app.core.tx),
    ),
    k.at(
      16,
      _h - 30,
      _w - 32,
      4,
      Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: app.fade(app.core.tx, 0.25),
              borderRadius: app.shape.brPill,
            ),
          ),
          FractionallySizedBox(
            widthFactor: 0.38,
            child: Container(
              decoration: BoxDecoration(
                color: app.core.tx,
                borderRadius: app.shape.brPill,
              ),
            ),
          ),
        ],
      ),
    ),
    k.at(
      16,
      _h - 20,
      30,
      6,
      k.lines(const [1], height: 2.5, color: app.core.tx2),
    ),
    k.at(
      _w - 46,
      _h - 20,
      30,
      6,
      k.lines(
        const [1],
        height: 2.5,
        color: app.core.tx2,
        align: CrossAxisAlignment.end,
      ),
    ),
    for (var i = 0; i < 4; i++)
      k.at(
        _w - 26 - i * 16,
        10,
        10,
        10,
        Icon(
          const [
            Icons.subtitles_rounded,
            Icons.speed_rounded,
            Icons.aspect_ratio_rounded,
            Icons.playlist_play_rounded,
          ][i],
          size: 10,
          color: app.core.tx,
        ),
      ),
  ];
}

/// The real styled dock for a player viewport, fitted into whatever box it
/// is given. Cinema Bar needs real width, so it is laid out for a 1280×720
/// player; the others for 960×540. If the dock cannot fit the requested
/// size (`DockMetrics.compute` returns null) the picture falls back to the
/// viewport's natural arrangement.
class DockPreview extends StatefulWidget {
  const DockPreview({
    super.key,
    required this.style,
    required this.palette,
    required this.size,
  });

  final PlayerDockStyle style;
  final PlayerDockPalette palette;
  final PlayerDockSize size;

  @override
  State<DockPreview> createState() => _DockPreviewState();
}

class _DockPreviewState extends State<DockPreview> {
  final ValueNotifier<PlaybackUiClockValue> _clock = ValueNotifier(
    const PlaybackUiClockValue(
      position: Duration(minutes: 41, seconds: 12),
      duration: Duration(hours: 1, minutes: 52, seconds: 30),
      generation: 0,
    ),
  );

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = widget.style == PlayerDockStyle.cinema
        ? const Size(1280, 720)
        : const Size(960, 540);
    final natural = DockArrangement.forViewport(viewport);
    final arrangement = widget.style.forcedArrangement ?? natural;
    DockLayoutInput input(DockArrangement a, PlayerDockSize s) =>
        DockLayoutInput(
          viewport: viewport,
          safeArea: EdgeInsets.zero,
          arrangement: a,
          infoPanelH: 0,
          textScale: 1.0,
          size: s,
        );
    var metrics = DockMetrics.compute(input(arrangement, widget.size));
    var used = arrangement;
    if (metrics == null) {
      metrics = DockMetrics.compute(input(natural, PlayerDockSize.auto));
      used = natural;
    }
    if (metrics == null) return const SizedBox.expand();
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: viewport.width,
        height: viewport.height,
        child: MediaQuery(
          data: MediaQueryData(size: viewport),
          child: StyledDock(
            metrics: metrics,
            palette: DockPalettes.of(widget.palette),
            arrangement: used,
            title: 'The Long Night',
            subtitle: 'S02 · E04 · 2160p HDR · Real-Debrid',
            infoPanel: null,
            clock: _clock,
            isPlaying: true,
            onPlayPause: () {},
            onBack: () {},
            onAspect: () {},
            onSpeed: () {},
            onSleepTimer: () {},
            onShowTracks: () {},
            onShowPlaylist: () {},
            onRandom: () {},
            onRotate: () {},
            onSeekBarChangedStart: () {},
            onSeekBarChanged: (_) {},
            onSeekBarChangeEnd: () {},
            onNext: () {},
            onPrevious: () {},
            onShowStremioSources: () {},
            onPip: () {},
            hasNext: true,
            hasPrevious: true,
            hasStremioSources: true,
            hasPlaylist: true,
            showPipButton: true,
            hideSeekbar: false,
            hideOptions: false,
            hideBackButton: false,
            speed: 1.0,
            aspectMode: AspectMode.aspect16_9,
            isLandscape: true,
            showRotate: false,
            volume: 0.7,
            onVolumeChanged: (_) {},
            showFullscreen: true,
            onFullscreen: () {},
          ),
        ),
      ),
    );
  }
}
