import 'package:flutter/material.dart';

import 'schematic_kit.dart';

/// Schematics for the navigation-chrome rows — the TV sidebar, the
/// desktop/tablet sidebar, the phone navigation — and the profile picker.
/// The chrome rows draw the same home behind every option so what changes
/// is only the chrome.

const double _w = SchematicKit.w;
const double _h = SchematicKit.h;

/// A home board behind the chrome, inset by [left].
List<Widget> _home(SchematicKit k, double left) => [
  k.at(left, 0, _w - left, 96, k.art(seed: 2)),
  k.at(left, 34, _w - left, 62, k.scrim()),
  k.at(left + 16, 48, 140, 30, k.lines(const [0.85, 0.5, 0.35], title: true)),
  k.at(left + 16, 84, 40, 9, k.button()),
  k.at(left + 16, 104, _w - left - 32, 34, k.shelf(6, focused: 0, radius: 3)),
  k.at(left + 16, 144, _w - left - 32, 30, k.shelf(6, radius: 3, seed: 6)),
];

/// Icon dots with a label bar beside each — the Badge rail's anatomy.
Widget _labelledRail(SchematicKit k, {required bool badge}) {
  final app = k.app;
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Container(
            width: 30,
            height: 12,
            decoration: BoxDecoration(
              color: badge && i == 1 ? app.core.tx : Colors.transparent,
              borderRadius: app.shape.br(4),
            ),
            child: Row(
              children: [
                const SizedBox(width: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == 1
                        ? (badge ? app.inkOn(app.core.tx) : app.core.tx)
                        : app.fade(app.core.tx, 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Container(
                  width: 13,
                  height: 2,
                  decoration: BoxDecoration(
                    color: i == 1
                        ? (badge ? app.inkOn(app.core.tx) : app.core.tx)
                        : app.fade(app.core.tx, 0.35),
                    borderRadius: app.shape.brPill,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// The capsule naming the current tab — the Pill styles' whole chrome.
Widget _tabPill(SchematicKit k) {
  final app = k.app;
  return Container(
    decoration: BoxDecoration(
      color: app.fade(app.core.pane, 0.85),
      borderRadius: app.shape.brPill,
      border: Border.all(color: app.core.hair),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: app.core.tx, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Expanded(child: k.lines(const [1], height: 2.5, color: app.core.tx)),
      ],
    ),
  );
}

List<Widget> tvSidebarSchematic(SchematicKit k, String optionId) {
  switch (optionId) {
    case 'ghost':
      // No chrome: floating icons, the active one a white coin.
      return [..._home(k, 20), k.at(0, 0, 20, _h, k.rail())];
    case 'classic':
      // The original liquid-glass rail.
      return [
        ..._home(k, 20),
        k.at(0, 0, 22, _h, k.panel(glass: true, radius: 0)),
        k.at(0, 0, 22, _h, k.rail()),
      ];
    case 'island':
      // A floating glass capsule, detached from the edge.
      return [
        ..._home(k, 20),
        k.at(4, 50, 16, 80, k.panel(glass: true, radius: 8)),
        k.at(4, 50, 16, 80, k.rail()),
      ];
    case 'marquee':
      // Ghost icons at rest; opened, an oversized text menu over the room.
      return [
        ..._home(k, 20),
        k.at(
          0,
          0,
          _w,
          _h,
          k.scrim(begin: Alignment.centerRight, end: Alignment.centerLeft),
        ),
        k.at(0, 0, 20, _h, k.rail()),
        k.at(
          30,
          28,
          120,
          124,
          k.lines(
            const [0.5, 0.7, 0.55, 0.8, 0.45],
            height: 7,
            gap: 12,
            color: k.app.fade(k.app.core.tx, 0.55),
          ),
        ),
        k.at(
          30,
          47,
          84,
          7,
          k.lines(const [1], height: 7, color: k.app.core.tx),
        ),
      ];
    case 'badge':
      // Labelled icons; the active tab wears a white badge.
      return [
        ..._home(k, 36),
        k.at(2, 0, 34, _h, _labelledRail(k, badge: true)),
      ];
    case 'pill':
      // No rail at all — content fills the screen, a capsule names the tab.
      return [..._home(k, 0), k.at(10, 8, 52, 12, _tabPill(k))];
  }
  return [..._home(k, 20), k.at(0, 0, 20, _h, k.rail())];
}

List<Widget> desktopSidebarSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  switch (optionId) {
    case 'pill':
      // No rail — a floating pill shows the current tab; clicking it opens
      // the menu over the page.
      return [..._home(k, 0), k.at(10, 8, 52, 12, _tabPill(k))];
    case 'rail':
    default:
      // The fixed icon rail down the left, logo on top.
      return [
        ..._home(k, 36),
        k.at(
          0,
          0,
          36,
          _h,
          DecoratedBox(
            decoration: BoxDecoration(
              color: app.shell.railBg,
              border: Border(right: BorderSide(color: app.core.hair)),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        k.at(
          13,
          10,
          10,
          10,
          DecoratedBox(
            decoration: BoxDecoration(
              color: app.core.accent,
              borderRadius: app.shape.br(3),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        k.at(0, 20, 36, _h - 20, k.rail()),
      ];
  }
}

List<Widget> phoneNavSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  // A phone, portrait, centred on the stage; the home board inside it.
  const px = 108.0, py = 4.0, pw = 104.0, ph = 172.0;
  final phone = <Widget>[
    k.at(
      px,
      py,
      pw,
      ph,
      DecoratedBox(
        decoration: BoxDecoration(
          color: app.core.ground,
          borderRadius: app.shape.br(10),
          border: Border.all(color: app.core.hair, width: 1.5),
        ),
        child: const SizedBox.expand(),
      ),
    ),
    k.at(
      px + 2,
      py + 2,
      pw - 4,
      62,
      ClipRRect(borderRadius: app.shape.br(9), child: k.art(seed: 1)),
    ),
    k.at(px + 2, py + 30, pw - 4, 34, k.scrim()),
    k.at(px + 10, py + 40, 70, 18, k.lines(const [0.85, 0.5], title: true)),
    k.at(px + 10, py + 72, pw - 20, 28, k.shelf(3, focused: 0, radius: 3)),
    k.at(px + 10, py + 106, pw - 20, 28, k.shelf(3, radius: 3, seed: 3)),
  ];
  switch (optionId) {
    case 'floating':
      // The glass button, bottom right, with the expanding menu.
      return [
        ...phone,
        k.at(
          px + pw - 30,
          py + ph - 30,
          20,
          20,
          DecoratedBox(
            decoration: BoxDecoration(
              color: app.core.accent,
              shape: BoxShape.circle,
              border: Border.all(color: app.core.hair),
            ),
            child: Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: app.inkOn(app.core.accent),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ];
    case 'classic':
    default:
      // Bottom tabs — Home, three slots you pick, More.
      return [
        ...phone,
        k.at(
          px + 2,
          py + ph - 22,
          pw - 4,
          20,
          DecoratedBox(
            decoration: BoxDecoration(
              color: app.core.pane,
              border: Border(top: BorderSide(color: app.core.hair)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 5; i++)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? app.core.accent
                          : app.fade(app.core.tx, 0.35),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ];
  }
}

List<Widget> profilePickerSchematic(SchematicKit k, String optionId) {
  final app = k.app;
  Widget avatar(int i, {bool focused = false}) =>
      k.circle(seed: i, focused: focused);
  Widget portraitCard(int i, {bool focused = false, bool glass = true}) =>
      Container(
        decoration: BoxDecoration(
          color: glass ? app.fade(app.core.pane, 0.72) : app.core.pane,
          borderRadius: app.shape.br(8),
          border: Border.all(
            color: focused ? app.core.focus : app.core.hair,
            width: focused ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(child: AspectRatio(aspectRatio: 1, child: avatar(i))),
            const SizedBox(height: 5),
            k.lines(const [0.8], height: 2.5, align: CrossAxisAlignment.center),
          ],
        ),
      );
  final title = k.at(
    _w / 2 - 50,
    14,
    100,
    12,
    k.lines(
      const [0.7],
      title: true,
      height: 3,
      align: CrossAxisAlignment.center,
    ),
  );
  switch (optionId) {
    case 'stage_cards':
      // Glass portrait cards that light the room.
      return [
        k.at(0, 0, _w, _h, k.art(seed: 4)),
        k.at(0, 0, _w, _h, k.scrim()),
        title,
        for (var i = 0; i < 4; i++)
          k.at(56 + i * 56, 46, 48, 96, portraitCard(i, focused: i == 1)),
        k.at(_w / 2 - 22, 152, 44, 8, k.ghost(width: 44, height: 8)),
      ];
    case 'marquee':
      // Lighthouse: a cinematic welcome — the room is the poster.
      return [
        k.at(0, 0, _w, _h, k.art(seed: 1)),
        k.at(0, 40, _w, _h - 40, k.scrim()),
        k.at(
          16,
          60,
          160,
          30,
          k.lines(const [0.9, 0.5], title: true, height: 4),
        ),
        for (var i = 0; i < 4; i++)
          k.at(16 + i * 34, 120, 28, 28, avatar(i, focused: i == 0)),
        k.at(16, 156, 140, 8, k.lines(const [0.6], height: 2.5)),
      ];
    case 'theater':
      // The chosen profile lights the whole room.
      return [
        k.at(0, 0, _w, _h, k.art(seed: 3)),
        k.at(0, 0, _w, _h, k.scrim()),
        k.at(_w / 2 - 28, 30, 56, 56, avatar(0, focused: true)),
        k.at(
          _w / 2 - 40,
          94,
          80,
          10,
          k.lines(
            const [0.8],
            title: true,
            height: 3,
            align: CrossAxisAlignment.center,
          ),
        ),
        for (var i = 0; i < 4; i++)
          k.at(_w / 2 - 62 + i * 34, 126, 22, 22, avatar(i + 1)),
      ];
    case 'row':
      // A simple row of portraits.
      return [
        title,
        for (var i = 0; i < 4; i++)
          k.at(64 + i * 52, 60, 44, 44, avatar(i, focused: i == 1)),
        for (var i = 0; i < 4; i++)
          k.at(70 + i * 52, 112, 32, 6, k.lines(const [1], height: 2.5)),
        k.at(_w / 2 - 22, 148, 44, 8, k.ghost(width: 44, height: 8)),
      ];
    case 'wall':
      // Tall posters, colour-washed room.
      return [
        k.at(0, 0, _w, _h, k.art(seed: 2)),
        k.at(
          0,
          0,
          _w,
          _h,
          k.scrim(begin: Alignment.bottomCenter, end: Alignment.topCenter),
        ),
        title,
        for (var i = 0; i < 4; i++)
          k.at(
            52 + i * 58,
            36,
            50,
            124,
            k.tile(seed: i + 1, focused: i == 1, radius: 6),
          ),
      ];
    case 'classic':
    default:
      // The original card grid.
      return [
        title,
        for (var i = 0; i < 3; i++)
          k.at(
            56 + i * 74,
            40,
            64,
            56,
            portraitCard(i, focused: i == 0, glass: false),
          ),
        for (var i = 0; i < 3; i++)
          k.at(56 + i * 74, 104, 64, 56, portraitCard(i + 3, glass: false)),
      ];
  }
}
