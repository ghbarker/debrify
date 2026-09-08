import 'package:flutter/material.dart';

import 'schematic_kit.dart';

/// Schematics for the Live TV rows: the IPTV page look, the Debrify TV
/// channel screen, and the in-player guide (zap banner) skins.

const double _w = SchematicKit.w;
const double _h = SchematicKit.h;

/// A channel list: rows of number + name + a short programme bar.
Widget _channelList(
  SchematicKit k,
  int count, {
  int focused = 0,
  bool hairline = false,
}) {
  final app = k.app;
  return Column(
    children: [
      for (var i = 0; i < count; i++)
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: i == focused
                  ? app.fade(app.core.accent, 0.22)
                  : Colors.transparent,
              borderRadius: app.shape.br(3),
              border: hairline
                  ? Border(bottom: BorderSide(color: app.core.hair))
                  : (i == focused ? Border.all(color: app.core.focus) : null),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 8,
                  child: k.lines(const [1], height: 2.5, color: app.core.tx2),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: k.lines(
                    [0.7, 0.45],
                    gap: 2,
                    height: 2.2,
                    color: i == focused ? app.core.tx : null,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// An EPG: programme blocks across time, one row per channel, a playhead.
Widget _epg(SchematicKit k, int rows, {bool amber = false}) {
  final app = k.app;
  return Stack(
    children: [
      Column(
        children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    for (var c = 0; c < 3; c++) ...[
                      if (c > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: [3, 2, 4][(r + c) % 3],
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: app.fade(
                              app.core.tx,
                              r == 1 && c == 0 ? 0.16 : 0.07,
                            ),
                            borderRadius: app.shape.br(2),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
      Positioned(
        left: 44,
        top: 0,
        bottom: 0,
        child: Container(
          width: 1.5,
          color: amber ? app.core.accent : app.core.tx2,
        ),
      ),
    ],
  );
}

List<Widget> iptvSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  switch (optionId) {
    case 'edition':
      // First Edition: editorial ink and serif headlines, a hairline ledger.
      return [
        k.at(16, 12, 200, 14, k.lines(const [0.6], title: true, height: 5)),
        k.at(
          16,
          30,
          _w - 32,
          1,
          DecoratedBox(decoration: BoxDecoration(color: app.core.tx2)),
        ),
        k.at(
          16,
          38,
          120,
          _h - 50,
          _channelList(k, 6, focused: 1, hairline: true),
        ),
        k.at(148, 38, _w - 164, 70, k.tile(seed: 2, radius: 2)),
        k.at(148, 116, _w - 164, 52, _epg(k, 3)),
      ];
    case 'console':
      // Master Control: a broadcast console — pure black, mono numerals,
      // an amber playhead.
      return [
        k.at(
          0,
          0,
          _w,
          _h,
          DecoratedBox(
            decoration: BoxDecoration(color: app.core.railBg),
            child: const SizedBox.expand(),
          ),
        ),
        k.at(
          12,
          10,
          _w - 24,
          14,
          k.panel(
            radius: 2,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: k.lines(const [0.3], height: 5, color: app.core.accent),
            ),
          ),
        ),
        k.at(
          12,
          30,
          112,
          _h - 42,
          k.panel(
            radius: 2,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _channelList(k, 7, focused: 2),
            ),
          ),
        ),
        k.at(
          132,
          30,
          _w - 144,
          60,
          k.panel(
            radius: 2,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: k.tile(seed: 3, radius: 2),
            ),
          ),
        ),
        k.at(
          132,
          96,
          _w - 144,
          _h - 108,
          k.panel(
            radius: 2,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _epg(k, 4, amber: true),
            ),
          ),
        ),
      ];
    case 'command':
    default:
      // Command Center: the shipped cockpit — dense guide, gold focus.
      return [
        k.at(
          12,
          10,
          100,
          _h - 22,
          k.panel(
            radius: 8,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: _channelList(k, 7, focused: 1),
            ),
          ),
        ),
        k.at(120, 10, _w - 132, 74, k.tile(seed: 1, radius: 6)),
        k.at(130, 58, 120, 20, k.lines(const [0.8, 0.5], title: true)),
        k.at(
          120,
          90,
          _w - 132,
          _h - 102,
          k.panel(
            radius: 8,
            child: Padding(padding: const EdgeInsets.all(5), child: _epg(k, 4)),
          ),
        ),
      ];
  }
}

List<Widget> debrifyTvSchematic(SchematicKit k, String optionId) {
  switch (optionId) {
    case 'spotlight':
      // A standing channel rail and a stage — what a channel holds before
      // you press Play.
      return [
        k.at(
          12,
          12,
          96,
          _h - 24,
          k.panel(
            radius: 8,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: _channelList(k, 6, focused: 1),
            ),
          ),
        ),
        k.at(120, 0, _w - 120, _h, k.art(seed: 3)),
        k.at(120, 50, _w - 120, _h - 50, k.scrim()),
        k.at(136, 84, 150, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        k.at(136, 120, 40, 9, k.button()),
        k.at(136, 138, _w - 152, 30, k.shelf(5, focused: 0, radius: 3)),
      ];
    case 'grid':
    default:
      // The classic wall of channels — everything at once.
      return [
        k.at(16, 10, 120, 12, k.lines(const [0.6], title: true)),
        k.at(_w - 76, 10, 60, 10, k.ghost(width: 60, height: 10)),
        k.at(16, 30, _w - 32, _h - 42, k.grid(5, 3, focused: 1, radius: 4)),
      ];
  }
}

List<Widget> playerGuideSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  // Video behind, the zap banner along the bottom; the skins change the
  // banner's chrome, not its anatomy.
  final video = <Widget>[
    k.at(0, 0, _w, _h, k.art(seed: 2)),
    k.at(0, _h / 2, _w, _h / 2, k.scrim()),
  ];
  Widget banner({
    required Color fill,
    Color? border,
    bool glass = false,
    bool rule = false,
    Color? playhead,
    bool pill = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: glass ? app.fade(fill, 0.72) : fill,
        borderRadius: app.shape.br(pill ? 14 : 8),
        border: Border.all(color: border ?? app.core.hair),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pill ? app.core.tx : app.fade(app.core.tx, 0.1),
              borderRadius: app.shape.br(pill ? 13 : 5),
            ),
            child: k.lines(
              const [0.5],
              height: 3,
              color: pill ? app.inkOn(app.core.tx) : app.core.tx2,
              align: CrossAxisAlignment.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                k.lines(const [0.5, 0.75], title: true, height: 2.5),
                const SizedBox(height: 5),
                if (rule) Container(height: 1, color: app.core.tx2),
                if (rule) const SizedBox(height: 3),
                Stack(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.12),
                        borderRadius: app.shape.brPill,
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 0.42,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: playhead ?? app.core.accent,
                          borderRadius: app.shape.brPill,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 40, height: 22, child: k.tile(seed: 4, radius: 3)),
        ],
      ),
    );
  }

  switch (optionId) {
    case 'glass':
      // Cinema Glass: translucent panels, one violet accent.
      return [
        ...video,
        k.at(
          16,
          _h - 62,
          _w - 32,
          50,
          banner(fill: app.core.pane, glass: true),
        ),
      ];
    case 'edition':
      // Midnight Edition: ink panels and serif headlines.
      return [
        ...video,
        k.at(
          16,
          _h - 62,
          _w - 32,
          50,
          banner(fill: app.core.railBg, rule: true, border: app.core.tx2),
        ),
      ];
    case 'console':
      // Master Control: black instrument — mono numerals, amber machinery.
      return [
        ...video,
        k.at(
          16,
          _h - 62,
          _w - 32,
          50,
          banner(
            fill: app.core.railBg,
            playhead: app.core.accent,
            border: app.fade(app.core.accent, 0.5),
          ),
        ),
      ];
    case 'spotlight':
      // Spotlight: full-bleed black glass, white-pill focus.
      return [
        ...video,
        k.at(
          0,
          _h - 60,
          _w,
          60,
          banner(
            fill: app.core.ground,
            glass: true,
            pill: true,
            playhead: app.core.tx,
            border: Colors.transparent,
          ),
        ),
      ];
    case 'classic':
    default:
      return [
        ...video,
        k.at(16, _h - 62, _w - 32, 50, banner(fill: app.core.pane)),
      ];
  }
}
