import 'package:debrify/screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart' as legacy;
import 'package:debrify/widgets/tv_focus_scroll_wrapper.dart' as owner;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old and shared imports expose one canonical widget type', () {
    const child = SizedBox(height: 50);
    const key = ValueKey('same wrapper');
    const oldWidget = legacy.TvFocusScrollWrapper(key: key, child: child);
    const newWidget = owner.TvFocusScrollWrapper(key: key, child: child);
    final owner.TvFocusScrollWrapper throughOwner = oldWidget;
    final legacy.TvFocusScrollWrapper throughLegacy = newWidget;
    expect(identical(throughOwner, oldWidget), isTrue);
    expect(identical(throughLegacy, newWidget), isTrue);
    expect(legacy.TvFocusScrollWrapper, owner.TvFocusScrollWrapper);
  });

  testWidgets('replacing the old import with shared owner preserves mounted focus',
      (tester) async {
    final descendant = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      descendant.dispose();
    });
    final child = Focus(focusNode: descendant, child: const SizedBox(height: 50));
    const key = ValueKey('same wrapper');
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: legacy.TvFocusScrollWrapper(key: key, child: child),
    ));
    descendant.requestFocus();
    await tester.pump();
    final observerBefore = Focus.of(tester.element(find.byWidget(child)));
    expect(descendant.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: owner.TvFocusScrollWrapper(key: key, child: child),
    ));
    final observerAfter = Focus.of(tester.element(find.byWidget(child)));
    expect(identical(observerAfter, observerBefore), isTrue);
    expect(observerAfter.canRequestFocus, isFalse);
    expect(observerAfter.skipTraversal, isTrue);
    expect(descendant.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
