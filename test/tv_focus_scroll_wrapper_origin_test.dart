import 'package:debrify/screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Keep the old import and these origin pins unchanged through any owner move.
// This fixture supplies geometry/nodes only; the lib widget handles all focus
// observation and scrolling. Nothing calls its onFocusChange callback directly.
Future<({ScrollController scroll, FocusNode first, FocusNode second, FocusNode outside})>
    mountScrollFixture(
  WidgetTester tester,
  TvFocusScrollWrapper Function(Widget child) wrap,
) async {
  final scroll = ScrollController();
  final first = FocusNode(debugLabel: 'first descendant');
  final second = FocusNode(debugLabel: 'second descendant');
  final outside = FocusNode(debugLabel: 'outside wrapper');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    first.dispose();
    second.dispose();
    outside.dispose();
  });
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: FocusScope(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Column(children: [
                    const SizedBox(height: 500),
                    wrap(SizedBox(
                      key: const ValueKey('target'),
                      height: 50,
                      child: Row(children: [
                        Focus(focusNode: first, child: const SizedBox(width: 50)),
                        Focus(focusNode: second, child: const SizedBox(width: 50)),
                      ]),
                    )),
                    const SizedBox(height: 500),
                  ]),
                ),
              ),
              Focus(focusNode: outside, child: const SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  expect(scroll.offset, 0);
  return (scroll: scroll, first: first, second: second, outside: outside);
}

void main() {
  testWidgets('defaults preserve child/key and observe real focus without claiming it',
      (tester) async {
    final node = FocusNode();
    final outside = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      node.dispose();
      outside.dispose();
    });
    final child = Focus(focusNode: node, child: const SizedBox(height: 50));
    const key = ValueKey('wrapper');
    final wrapper = TvFocusScrollWrapper(key: key, child: child);
    expect(wrapper.key, key);
    expect(identical(wrapper.child, child), isTrue);
    expect(wrapper.alignment, 0.2);
    expect(wrapper.duration, const Duration(milliseconds: 200));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: FocusScope(child: Column(children: [
        wrapper,
        Focus(focusNode: outside, child: const SizedBox(height: 20)),
      ])),
    ));
    await tester.pump();
    final observer = tester.widget<Focus>(find.descendant(
      of: find.byKey(key), matching: find.byType(Focus),
    ).first);
    expect(observer.canRequestFocus, isFalse);
    expect(observer.skipTraversal, isTrue);
    expect(identical(observer.child, child), isTrue);
    node.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(node.hasPrimaryFocus, isTrue);
    expect(Focus.of(tester.element(find.byWidget(child))).hasPrimaryFocus, isFalse);
    outside.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isFalse);
    expect(outside.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull); // No ancestor Scrollable is a no-op.
  });

  testWidgets('default focus gain scrolls own 50px target to 20 percent in 200ms',
      (tester) async {
    final f = await mountScrollFixture(tester, (child) => TvFocusScrollWrapper(child: child));
    f.first.requestFocus();
    await tester.pump();
    await tester.pump(); // Start the animation clock without advancing time.
    expect(f.first.hasPrimaryFocus, isTrue);
    expect(f.scroll.offset, 0);
    await tester.pump(const Duration(milliseconds: 100));
    // Target top 500, viewport 300, target height 50: final offset is 450.
    expect(f.scroll.offset, closeTo(450 * Curves.easeOutCubic.transform(0.5), 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.scroll.offset, closeTo(450, 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isTrue);
    // Flutter finishes the driven activity only strictly after its duration.
    await tester.pump(const Duration(microseconds: 1));
    expect(f.scroll.offset, closeTo(450, 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom alignment and duration retain the easeOutCubic trajectory',
      (tester) async {
    final f = await mountScrollFixture(tester, (child) => TvFocusScrollWrapper(
      alignment: 0.75, duration: const Duration(milliseconds: 400), child: child,
    ));
    f.first.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.scroll.offset, closeTo(312.5 * Curves.easeOutCubic.transform(0.25), 0.05));
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.scroll.offset, closeTo(312.5 * Curves.easeOutCubic.transform(0.5), 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.scroll.offset, closeTo(312.5, 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isTrue);
    // Flutter finishes the driven activity only strictly after its duration.
    await tester.pump(const Duration(microseconds: 1));
    expect(f.scroll.offset, closeTo(312.5, 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('zero duration applies custom alignment without animation', (tester) async {
    final f = await mountScrollFixture(tester, (child) => TvFocusScrollWrapper(
      alignment: 1, duration: Duration.zero, child: child,
    ));
    f.first.requestFocus();
    await tester.pump();
    expect(f.scroll.offset, closeTo(250, 0.05));
    expect(f.scroll.position.isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.scroll.offset, closeTo(250, 0.05));
  });

  testWidgets('descendant transfer and loss do not reposition; a new gain does',
      (tester) async {
    final f = await mountScrollFixture(tester, (child) => TvFocusScrollWrapper(child: child));
    f.first.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.scroll.offset, closeTo(450, 0.05));
    f.scroll.jumpTo(100);
    f.second.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.second.hasPrimaryFocus, isTrue);
    expect(f.first.hasPrimaryFocus, isFalse);
    expect(f.scroll.offset, 100);
    f.outside.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.outside.hasPrimaryFocus, isTrue);
    expect(f.scroll.offset, 100);
    f.first.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.scroll.offset, closeTo(450, 0.05));
  });

  testWidgets('focus loss does not cancel an already running scroll', (tester) async {
    final f = await mountScrollFixture(tester, (child) => TvFocusScrollWrapper(child: child));
    f.first.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(f.scroll.offset, closeTo(450 * Curves.easeOutCubic.transform(0.25), 0.05));
    f.outside.requestFocus();
    await tester.pump();
    expect(f.outside.hasPrimaryFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 150));
    expect(f.scroll.offset, closeTo(450, 0.05));
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.scroll.offset, closeTo(450, 0.05));
  });

  testWidgets('wrapping a child scrollable does not scroll that descendant', (tester) async {
    final scroll = ScrollController(initialScrollOffset: 100);
    final childNode = FocusNode();
    final outside = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      childNode.dispose();
      outside.dispose();
    });
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: FocusScope(child: Column(children: [
        TvFocusScrollWrapper(child: SizedBox(
          height: 300,
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(children: [
              const SizedBox(height: 500),
              Focus(focusNode: childNode, child: const SizedBox(height: 50)),
              const SizedBox(height: 500),
            ]),
          ),
        )),
        Focus(focusNode: outside, child: const SizedBox(height: 20)),
      ])),
    ));
    await tester.pump();
    expect(scroll.offset, 100);
    childNode.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(childNode.hasPrimaryFocus, isTrue);
    expect(scroll.offset, 100);
    outside.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(outside.hasPrimaryFocus, isTrue);
    expect(scroll.offset, 100);
    expect(tester.takeException(), isNull);
  });
}
