import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/theme_preview_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/golden_harness.dart' show disableRuntimeFonts;

/// TV ergonomics of the Appearance look strip (Shield feedback, 2026-09-07):
/// landing on the strip from the rows below must bring the WHOLE preview
/// back into view, and the chips must stay one Left/Right row — a wrapped
/// second row is unreachable with a D-pad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppThemeController.instance.select(AppThemes.legacyId);
    await AppThemeController.instance.clearOverrides();
    TextBrightnessController.notifier.value = TextBrightness.bright;
  });

  Future<void> pump(
    WidgetTester tester, {
    required FocusNode node,
    required ScrollController pane,
    double width = 420,
  }) {
    final theme = AppThemes.byId('spotlight');
    return tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 400,
            // A Column, as the TV pane keeps every row mounted (nodes are
            // positional) — a lazy list would unmount the card offscreen.
            child: SingleChildScrollView(
              controller: pane,
              child: Column(
                children: [
                  AppearancePreviewHost(focusNode: node, singleRow: true),
                  // The Presets/Theme rows that sit under the card on TV.
                  for (var i = 0; i < 12; i++)
                    SizedBox(height: 56, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('focusing the strip from below reveals the whole card', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    final pane = ScrollController();
    addTearDown(pane.dispose);
    await pump(tester, node: node, pane: pane);
    await tester.pumpAndSettle();

    // Scrolled down past the stage, as a D-pad user arriving from the rows.
    pane.jumpTo(pane.position.maxScrollExtent);
    await tester.pump();
    expect(
      pane.offset,
      greaterThan(0),
      reason: 'the card starts scrolled away',
    );

    node.requestFocus();
    await tester.pumpAndSettle();
    final stage = tester.getRect(find.byType(ThemePreviewStage));
    expect(stage.top, greaterThanOrEqualTo(0));
    // The caption reads LIVE PREVIEW or PREVIEWING depending on which chip
    // the highlight landed on; either way it sits above the stage and must
    // be on screen too.
    final caption = find.textContaining('PREVIEW');
    expect(caption, findsOneWidget);
    expect(tester.getRect(caption).top, greaterThanOrEqualTo(0));
  });

  testWidgets(
    'chips are one scrolling row and Right keeps the highlight in view',
    (tester) async {
      final node = FocusNode(debugLabel: 'pane-0');
      addTearDown(node.dispose);
      final pane = ScrollController();
      addTearDown(pane.dispose);
      await pump(tester, node: node, pane: pane, width: 360);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppearancePreviewCard),
          matching: find.byType(Wrap),
        ),
        findsNothing,
        reason: 'no wrapped second row on a D-pad surface',
      );
      final strip = find.descendant(
        of: find.byType(AppearancePreviewCard),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(strip, findsOneWidget);
      final stripRect = tester.getRect(strip);

      node.requestFocus();
      await tester.pumpAndSettle();
      final lookCount = tester
          .widget<AppearancePreviewCard>(find.byType(AppearancePreviewCard))
          .looks
          .length;
      for (var i = 1; i < lookCount; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      // The last chip is highlighted; its centre must lie inside the strip's
      // viewport — the row scrolled to follow the highlight.
      final lastLabel = tester
          .widget<AppearancePreviewCard>(find.byType(AppearancePreviewCard))
          .looks
          .last
          .label;
      final chip = tester.getRect(find.text(lastLabel).last);
      expect(chip.center.dx, inInclusiveRange(stripRect.left, stripRect.right));
      // Trapped at the end: one more Right stays put and throws nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
