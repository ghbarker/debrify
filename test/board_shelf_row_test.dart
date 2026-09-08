import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/screens/search/board_shelf_row.dart';
import 'package:debrify/widgets/home/card_focus_rise.dart';

/// [BoardShelfRow] is the widget the collection folder screen's rails now
/// render through — the same [BoardCell] (and its [CardFocusRise] chrome)
/// Home's own board rows paint, pulled out as a standalone row so a screen
/// outside the board can use it too. These pin that the row really is built
/// from those exact classes (not a lookalike) and that its DPAD row grammar
/// (left/right walk, up/down exit, focusFirst) survives the extraction.
void main() {
  List<StremioMeta> items(int n) => [
    for (var i = 0; i < n; i++)
      StremioMeta(id: 'tt$i', imdbId: 'tt$i', type: 'movie', name: 'Title $i'),
  ];

  Widget harness(Widget child, {Size size = const Size(1920, 1080)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Material(
                color: const Color(0xFF000000),
                child: SizedBox.fromSize(size: size, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('renders one BoardCell (with CardFocusRise) per item', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        BoardShelfRow(
          items: items(3),
          isTelevision: true,
          posterW: 118,
          cellH: 177,
          onOpen: (_) {},
        ),
      ),
    );
    expect(find.byType(BoardCell), findsNWidgets(3));
    expect(find.byType(CardFocusRise), findsNWidgets(3));
  });

  testWidgets('SELECT opens the focused item', (tester) async {
    StremioMeta? opened;
    final key = GlobalKey<BoardShelfRowState>();
    await tester.pumpWidget(
      harness(
        BoardShelfRow(
          key: key,
          items: items(3),
          isTelevision: true,
          posterW: 118,
          cellH: 177,
          onOpen: (item) => opened = item,
        ),
      ),
    );
    key.currentState!.focusFirst();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(opened?.id, 'tt0');
  });

  testWidgets('RIGHT walks across cards, LEFT at column 0 is swallowed', (
    tester,
  ) async {
    final key = GlobalKey<BoardShelfRowState>();
    await tester.pumpWidget(
      harness(
        BoardShelfRow(
          key: key,
          items: items(3),
          isTelevision: true,
          posterW: 118,
          cellH: 177,
          onOpen: (_) {},
        ),
      ),
    );
    key.currentState!.focusFirst();
    await tester.pump();
    final first = FocusManager.instance.primaryFocus;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final second = FocusManager.instance.primaryFocus;
    expect(second, isNot(same(first)));
    // Back to column 0, then LEFT: no ancestor sidebar to reach for, so this
    // must not throw and must leave focus exactly where it was.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(first));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(FocusManager.instance.primaryFocus, same(first));
  });

  testWidgets('UP/DOWN from any card call onExitTop/onExitBottom', (
    tester,
  ) async {
    var upCalls = 0;
    var downCalls = 0;
    final key = GlobalKey<BoardShelfRowState>();
    await tester.pumpWidget(
      harness(
        BoardShelfRow(
          key: key,
          items: items(3),
          isTelevision: true,
          posterW: 118,
          cellH: 177,
          onOpen: (_) {},
          onExitTop: () => upCalls++,
          onExitBottom: () => downCalls++,
        ),
      ),
    );
    key.currentState!.focusFirst();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(upCalls, 1);
    expect(downCalls, 1);
  });

  testWidgets('loadingMore adds a trailing spinner cell', (tester) async {
    await tester.pumpWidget(
      harness(
        BoardShelfRow(
          items: items(2),
          isTelevision: true,
          posterW: 118,
          cellH: 177,
          loadingMore: true,
          onOpen: (_) {},
        ),
      ),
    );
    expect(find.byType(BoardCell), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('focusFirst on an empty row is a no-op', (tester) async {
    final key = GlobalKey<BoardShelfRowState>();
    await tester.pumpWidget(
      harness(
        BoardShelfRow(
          key: key,
          items: const [],
          isTelevision: true,
          posterW: 118,
          cellH: 177,
          onOpen: (_) {},
        ),
      ),
    );
    key.currentState!.focusFirst();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
