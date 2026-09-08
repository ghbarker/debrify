import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/services/tv_motion_profile.dart';

/// Pins the fix for the board's own DPAD scroll-follow (`_StremioCard` in
/// `board_cell.dart`), which predates the TV motion profile (added
/// 2026-09-05, PR #276 landed 2026-09-07) and hardcoded a flat 140ms glide
/// on every TV regardless of which profile was selected — so choosing
/// "Smooth" in Appearance never touched the single most visible TV scroll
/// interaction, the Home/Discover board.
///
/// Before the fix both profiles glide at the identical, unconditional 140ms
/// literal, so focusing an off-screen card settles within the same handful
/// of `pumpAndSettle` frames under either profile (observed: 5). After the
/// fix, snappy keeps that 140ms figure — still settling within 5 frames —
/// but smooth resolves to `AppMotion.tvScroll` (260ms) via
/// `AppMotion.scrollTempo`, a longer glide that needs more frames to land
/// (observed: 6). Comparing frame counts rather than sampling a fixed
/// elapsed time avoids coupling this test to exactly when the focus-driven
/// post-frame callback happens to start ticking; each profile runs in its
/// own `testWidgets` so neither test's fake clock leaks into the other's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TvMotionController.debugReset();
  });

  tearDown(() {
    TvMotionController.debugReset();
  });

  StremioMeta item(int i) => StremioMeta(
    id: 'tt200$i',
    imdbId: 'tt200$i',
    type: 'movie',
    name: 'Board $i',
    poster: null,
    background: null,
    description: null,
    year: '2020',
    genres: const [],
  );

  Future<List<FocusNode>> pumpBoard(WidgetTester tester) async {
    final nodes = List.generate(20, (i) => FocusNode(debugLabel: 'board-$i'));
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: nodes.length,
              itemBuilder: (context, i) => SizedBox(
                width: 150,
                child: BoardCell(
                  item: item(i),
                  isTelevision: true,
                  focusNode: nodes[i],
                  column: i,
                  rowNodes: nodes,
                  hasBoundSource: false,
                  onFocused: () {},
                  onUp: () {},
                  onDown: () {},
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return nodes;
  }

  /// Focuses the built-but-partially-off-screen card 5 (inside the default
  /// cache extent, but only half inside the 800-wide test viewport, so
  /// centring it under alignment 0.5 is a real, non-zero scroll) and settles
  /// the resulting glide.
  Future<(int pumps, double offset)> focusAndSettle(
    WidgetTester tester,
    Finder scrollable,
    List<FocusNode> nodes,
  ) async {
    nodes[5].requestFocus();
    final pumps = await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    return (pumps, offset);
  }

  // The shared ceiling the smooth test compares against — the number of
  // `pumpAndSettle` frames the snappy profile's shipped 140ms glide needs.
  const snappyCeilingPumps = 5;

  testWidgets(
    'snappy: keeps the shipped 140ms glide, settling within a handful of '
    'frames',
    (tester) async {
      final nodes = await pumpBoard(tester);
      final scrollable = find.byType(Scrollable);
      final (pumps, offset) = await focusAndSettle(tester, scrollable, nodes);

      expect(
        offset,
        isNot(0.0),
        reason: 'the board should have scrolled to reveal the focused card',
      );
      expect(
        pumps,
        lessThanOrEqualTo(snappyCeilingPumps),
        reason: 'the snappy profile keeps its shipped 140ms glide',
      );
    },
  );

  testWidgets(
    'smooth: the board glide is the profile figure (260ms), not the old '
    'flat 140ms — takes strictly more frames to settle than snappy',
    (tester) async {
      TvMotionController.select(TvMotionProfile.smooth);
      final nodes = await pumpBoard(tester);
      final scrollable = find.byType(Scrollable);
      final (pumps, offset) = await focusAndSettle(tester, scrollable, nodes);

      expect(offset, isNot(0.0));
      expect(
        pumps,
        greaterThan(snappyCeilingPumps),
        reason:
            'the smooth profile (260ms) should need more pumped frames to '
            "settle than snappy's shipped 140ms glide. A flat, "
            'profile-blind 140ms (the pre-fix behaviour) would settle in '
            'the same handful of frames as snappy.',
      );
    },
  );
}
