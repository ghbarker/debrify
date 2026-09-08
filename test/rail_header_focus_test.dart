import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/collections/rail_header_focus.dart';

/// [RailHeaderFocus] is what a collection rail's header (and the folder
/// screen's "All" row) uses in place of the old "See all ›" pill: the whole
/// header becomes the open/tap target, with no visible affordance text at
/// all. These pin that it never renders one, and that it still drives the
/// same DPAD ladder (up/down/select) the pill used to.
void main() {
  Widget harness(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders only the given child — no "See all" text anywhere', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      harness(
        RailHeaderFocus(
          node: node,
          isTelevision: true,
          onPressed: () {},
          onUp: () {},
          onDown: () {},
          onFocused: () {},
          child: const Text('Popular Movies'),
        ),
      ),
    );
    expect(find.text('Popular Movies'), findsOneWidget);
    expect(find.textContaining('See all'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('tap invokes onPressed', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var pressed = 0;
    await tester.pumpWidget(
      harness(
        RailHeaderFocus(
          node: node,
          isTelevision: false,
          onPressed: () => pressed++,
          onUp: () {},
          onDown: () {},
          onFocused: () {},
          child: const Text('A list'),
        ),
      ),
    );
    await tester.tap(find.text('A list'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('TV: focused DOWN/UP/SELECT drive the ladder callbacks', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'header');
    addTearDown(node.dispose);
    var ups = 0, downs = 0, pressed = 0, focused = 0;
    await tester.pumpWidget(
      harness(
        RailHeaderFocus(
          node: node,
          isTelevision: true,
          onPressed: () => pressed++,
          onUp: () => ups++,
          onDown: () => downs++,
          onFocused: () => focused++,
          child: const Text('A list'),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(focused, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(downs, 1);
    expect(ups, 0);
    expect(pressed, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(ups, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(pressed, 1);

    // Nothing beside the header — LEFT/RIGHT are swallowed, not forwarded.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(ups, 1);
    expect(downs, 1);
    expect(pressed, 1);
  });

  testWidgets(
    'TV: with no onPressed, SELECT does nothing and tap does nothing — a '
    'plain list title is a label, not a control',
    (tester) async {
      final node = FocusNode(debugLabel: 'header');
      addTearDown(node.dispose);
      var ups = 0, downs = 0;
      await tester.pumpWidget(
        harness(
          RailHeaderFocus(
            node: node,
            isTelevision: true,
            onUp: () => ups++,
            onDown: () => downs++,
            onFocused: () {},
            child: const Text('Popular Movies'),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Popular Movies'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // The ladder itself still works — only the press action is gone.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(downs, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(ups, 1);
    },
  );

  testWidgets('off TV, arrow keys are ignored (no ladder to walk)', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var downs = 0;
    await tester.pumpWidget(
      harness(
        RailHeaderFocus(
          node: node,
          isTelevision: false,
          onPressed: () {},
          onUp: () {},
          onDown: () => downs++,
          onFocused: () {},
          child: const Text('A list'),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(downs, 0);
  });
}
