import 'package:flutter/material.dart';

import 'schematic_kit.dart';

/// Schematics for the TV Home Layout row (`tv_home_style`). Every picture
/// keeps the TV sidebar at rest down the left edge (the rail column, x 0–20)
/// because that is the frame the home board is composed against.
List<Widget> tvHomeSchematic(SchematicKit k, String optionId) {
  const w = SchematicKit.w;
  const h = SchematicKit.h;
  final rail = k.at(0, 0, 20, h, k.rail());
  switch (optionId) {
    case 'spotlight':
      // Full-bleed hero you can page through; shelves on a flat ground.
      return [
        k.at(20, 0, w - 20, 108, k.art()),
        k.at(20, 40, w - 20, 68, k.scrim()),
        k.at(36, 52, 150, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        k.at(36, 92, 40, 6, k.dots(4)),
        k.at(36, 116, w - 52, 52, k.shelf(6, focused: 0, radius: 4)),
        rail,
      ];
    case 'canvas':
      // Full-screen art and trailers, one bottom shelf.
      return [
        k.at(20, 0, w - 20, h, k.art(seed: 1)),
        k.at(20, 50, w - 20, h - 50, k.scrim()),
        k.at(36, 92, 160, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        k.at(36, 126, 40, 9, k.button()),
        k.at(36, 142, w - 52, 28, k.shelf(5, focused: 0, radius: 3)),
        rail,
      ];
    case 'classic':
      // Hero spotlight with scrolling rows.
      return [
        k.at(20, 0, w - 20, 86, k.art(seed: 2)),
        k.at(20, 30, w - 20, 56, k.scrim()),
        k.at(36, 40, 140, 28, k.lines(const [0.85, 0.5], title: true)),
        k.at(36, 74, 40, 9, k.button()),
        k.at(36, 94, w - 52, 34, k.shelf(6, focused: 0, radius: 3)),
        k.at(36, 136, w - 52, 34, k.shelf(6, radius: 3, seed: 6)),
        rail,
      ];
    case 'atrium':
      // Split screen — details left, art and two rows of posters right.
      return [
        k.at(
          36,
          22,
          108,
          60,
          k.lines(const [0.9, 0.55, 0.45, 0.45], title: true),
        ),
        k.at(36, 92, 40, 9, k.button()),
        k.at(80, 92, 28, 9, k.ghost()),
        k.at(36, 112, 108, 40, k.lines(const [1, 0.9, 0.6], gap: 5)),
        k.at(160, 12, w - 172, 70, k.tile(seed: 3, radius: 6)),
        k.at(160, 90, w - 172, 38, k.shelf(4, focused: 0, radius: 3)),
        k.at(160, 134, w - 172, 38, k.shelf(4, radius: 3, seed: 4)),
        rail,
      ];
    case 'mosaic':
      // A wall of posters, no hero.
      return [
        k.at(36, 12, w - 52, h - 24, k.grid(6, 3, focused: 1, radius: 3)),
        rail,
      ];
    case 'promenade':
      // Centred art with a wide strip that slides through the middle.
      return [
        k.at(20, 0, w - 20, h, k.art(seed: 4)),
        k.at(20, 0, w - 20, h, k.scrim()),
        k.at(36, 18, 160, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        // Overhangs both edges on purpose — the strip slides; the stage clips.
        k.at(-10, 68, w + 20, 46, k.shelf(6, focused: 2, radius: 4)),
        k.at(36, 130, 40, 9, k.button()),
        k.at(36, 148, 120, 12, k.lines(const [1, 0.7], gap: 4)),
        rail,
      ];
    case 'deck':
      // The trailer plays in a card, the next titles stacked behind it.
      return [
        k.at(60, 4, 168, 96, k.panel(radius: 6)),
        k.at(48, 10, 168, 96, k.panel(radius: 6)),
        k.at(36, 16, 168, 96, k.tile(seed: 2, focused: true, radius: 6)),
        k.at(96, 54, 48, 14, k.button(width: 48, height: 14)),
        k.at(
          224,
          22,
          w - 236,
          60,
          k.lines(const [0.9, 0.55, 0.45, 0.45], title: true),
        ),
        k.at(36, 126, w - 52, 42, k.shelf(5, radius: 3, seed: 5)),
        rail,
      ];
    case 'tonight':
      // Resume first — a big Continue card, an Up Next queue, one row below.
      return [
        k.at(36, 14, 152, 80, k.tile(seed: 1, focused: true, radius: 6)),
        k.at(46, 74, 40, 9, k.button()),
        k.at(198, 14, w - 210, 80, k.list(3)),
        k.at(36, 106, w - 52, 60, k.shelf(5, radius: 4, seed: 3)),
        rail,
      ];
  }
  return [...k.generic(), rail];
}

/// Schematics for the TV Discover Layout row (`discover_layout`).
List<Widget> discoverSchematic(SchematicKit k, String optionId) {
  const w = SchematicKit.w;
  const h = SchematicKit.h;
  final rail = k.at(0, 0, 20, h, k.rail());
  switch (optionId) {
    case 'grid':
      // Detail rail beside a wall of posters — the most titles on screen.
      return [
        k.at(
          36,
          12,
          92,
          h - 24,
          k.panel(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    height: 62,
                    child: k.tile(seed: 2, radius: 4),
                  ),
                  const SizedBox(height: 8),
                  k.lines(const [0.9, 0.6, 0.45], title: true),
                  const Spacer(),
                  k.button(width: 36),
                ],
              ),
            ),
          ),
        ),
        k.at(138, 12, w - 150, h - 24, k.grid(4, 3, focused: 0, radius: 3)),
        rail,
      ];
    case 'stage':
      // Full-screen art and trailers, one bottom shelf — art first.
      return [
        k.at(20, 0, w - 20, h, k.art(seed: 3)),
        k.at(20, 50, w - 20, h - 50, k.scrim()),
        k.at(36, 90, 160, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
        k.at(36, 124, 40, 9, k.button()),
        k.at(80, 124, 28, 9, k.ghost()),
        k.at(36, 142, w - 52, 28, k.shelf(6, focused: 0, radius: 3)),
        rail,
      ];
  }
  return [...k.generic(), rail];
}
