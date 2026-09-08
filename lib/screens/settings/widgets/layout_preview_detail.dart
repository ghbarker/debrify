import 'package:flutter/material.dart';

import 'schematic_kit.dart';

/// Schematics for the Details Page row (`detail_page_style`), one per
/// shipped layout. Each mirrors the real layout's block order and
/// proportions on the 320×180 canvas: where the art sits, where the title
/// reads, and how the season is presented (bands, a list, a grid, a deck).
List<Widget> detailPageSchematic(SchematicKit k, String optionId) {
  const w = SchematicKit.w;
  const h = SchematicKit.h;
  switch (optionId) {
    case 'showcase':
      // Full-bleed art dissolving into the colour field; then bands —
      // episodes, cast, sources.
      return [
        k.at(0, 0, w, 100, k.art()),
        k.at(0, 34, w, 66, k.scrim()),
        k.at(16, 50, 150, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        k.at(16, 86, 40, 9, k.button()),
        k.at(60, 86, 28, 9, k.ghost()),
        k.at(16, 104, w - 32, 36, k.shelf(4, focused: 0, radius: 4)),
        k.at(
          16,
          150,
          w - 32,
          20,
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                SizedBox(width: 20, child: k.circle(seed: i)),
              ],
            ],
          ),
        ),
      ];
    case 'classic':
      // The original: info column beside a full-height episode list. Drawn
      // in the preview theme's tokens although the real page keeps its own
      // look — the picture is about where things sit.
      return [
        k.at(16, 14, 50, 74, k.tile(seed: 1, radius: 4)),
        k.at(74, 16, 52, 40, k.lines(const [1, 0.7, 0.5, 0.5], title: true)),
        k.at(16, 98, 40, 9, k.button()),
        k.at(60, 98, 28, 9, k.ghost()),
        k.at(16, 118, 110, 48, k.lines(const [1, 0.9, 0.95, 0.6], gap: 5)),
        k.at(140, 12, w - 156, h - 24, k.list(6, focused: 1)),
      ];
    case 'marquee':
      // Art fills the screen; the season is a row of wide episode cards.
      return [
        k.at(0, 0, w, h, k.art(seed: 2)),
        k.at(0, 40, w, h - 40, k.scrim()),
        k.at(16, 78, 160, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        k.at(16, 112, 40, 9, k.button()),
        k.at(16, 128, w - 32, 40, k.shelf(4, focused: 0, radius: 4)),
      ];
    case 'dossier':
      // A fixed title card that never scrolls, beside a pure episode list.
      return [
        k.at(
          12,
          12,
          118,
          h - 24,
          k.panel(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 50,
                    height: 70,
                    child: k.tile(seed: 3, radius: 4),
                  ),
                  const SizedBox(height: 10),
                  k.lines(const [0.9, 0.6, 0.45], title: true),
                  const Spacer(),
                  k.button(),
                ],
              ),
            ),
          ),
        ),
        k.at(
          142,
          12,
          w - 154,
          h - 24,
          k.list(7, thumbs: false, numbered: true, focused: 1),
        ),
      ];
    case 'stage':
      // Artwork on top, everything else in a tabbed deck below.
      return [
        k.at(0, 0, w, 84, k.art(seed: 1)),
        k.at(0, 36, w, 48, k.scrim()),
        k.at(16, 46, 150, 30, k.lines(const [0.85, 0.5], title: true)),
        k.at(16, 92, 120, 6, k.tabs(4, active: 1)),
        k.at(16, 106, w - 32, h - 118, k.list(3, focused: 0)),
      ];
    case 'console':
      // Resume first — a big continue card — then the season as a grid.
      return [
        k.at(16, 14, 156, 60, k.tile(seed: 4, focused: true, radius: 6)),
        k.at(66, 36, 56, 14, k.button(width: 56, height: 14)),
        k.at(
          184,
          18,
          120,
          52,
          k.lines(const [0.9, 0.6, 0.45, 0.45], title: true),
        ),
        k.at(16, 86, w - 32, h - 98, k.grid(4, 2, radius: 4)),
      ];
    case 'vista':
      // Cinematic art above a polished, glass-like episode shelf.
      return [
        k.at(0, 0, w, 104, k.art(seed: 3)),
        k.at(0, 50, w, 54, k.scrim()),
        k.at(16, 60, 150, 30, k.lines(const [0.85, 0.5], title: true)),
        k.at(
          12,
          108,
          w - 24,
          h - 120,
          k.panel(
            glass: true,
            radius: 10,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: k.shelf(5, focused: 1, radius: 4),
            ),
          ),
        ),
      ];
    case 'monolith':
      // A monumental title canvas beside a deep vertical season deck.
      return [
        k.at(0, 0, 144, h, k.art(seed: 1)),
        k.at(0, 60, 144, h - 60, k.scrim()),
        k.at(14, 118, 112, 46, k.lines(const [0.9, 0.55, 0.4], title: true)),
        k.at(156, 12, w - 168, h - 24, k.list(5, focused: 0)),
      ];
    case 'mosaic':
      // Bento tiles: identity, metadata, guide, episodes.
      return [
        k.at(12, 12, 150, 84, k.tile(seed: 2, radius: 8)),
        k.at(
          170,
          12,
          w - 182,
          38,
          k.panel(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: k.lines(const [0.8, 0.5], title: true),
            ),
          ),
        ),
        k.at(
          170,
          58,
          w - 182,
          38,
          k.panel(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: k.lines(const [0.9, 0.7, 0.5], gap: 4),
            ),
          ),
        ),
        k.at(
          12,
          104,
          w - 24,
          h - 116,
          k.panel(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: k.shelf(5, focused: 0, radius: 4),
            ),
          ),
        ),
      ];
    case 'halo':
      // Centred cinematic identity with a luminous floating content dock.
      return [
        k.at(0, 0, w, h, k.art(seed: 4)),
        k.at(0, 0, w, h, k.scrim()),
        k.at(w / 2 - 20, 14, 40, 56, k.tile(seed: 2, radius: 4)),
        k.at(
          w / 2 - 60,
          76,
          120,
          24,
          k.lines(
            const [0.8, 0.5],
            title: true,
            align: CrossAxisAlignment.center,
          ),
        ),
        k.at(
          44,
          112,
          w - 88,
          h - 124,
          k.panel(
            glass: true,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: k.shelf(4, focused: 1, radius: 4),
            ),
          ),
        ),
      ];
    case 'premiere':
      // Editorial opening-night typography with an episode ledger.
      return [
        k.at(
          16,
          16,
          200,
          40,
          k.lines(const [1, 0.6, 0.3], title: true, height: 5),
        ),
        k.at(
          16,
          62,
          w - 32,
          1,
          DecoratedBox(decoration: BoxDecoration(color: k.app.core.tx2)),
        ),
        k.at(
          16,
          70,
          w - 32,
          h - 82,
          k.list(5, thumbs: false, numbered: true, focused: 0),
        ),
      ];
  }
  return k.generic();
}
