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

/// TV ergonomics of the Appearance preview (Shield feedback, 2026-09-07): the
/// preview is a genuine fixed header — structurally OUTSIDE the pane's
/// scrollable body, the same shape `settings_tv_layout.dart` and
/// `settings_spotlight_shell.dart` build — so scrolling the rows below it
/// can never carry it off screen; there is nothing to reveal because it
/// never left. The chips must also stay one Left/Right row — a wrapped
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

  /// The pinned shape every TV/desktop surface now builds: the preview as a
  /// fixed `Column` header, an `Expanded` scrolling body below it — never one
  /// scrollable holding both (see the `_buildPane`/`_buildCategoryBody` note
  /// on why: a pushed-down header would carry a just-hovered chip out from
  /// under the pointer, the old flicker bug).
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
            child: Column(
              children: [
                AppearancePreviewHost(focusNode: node, singleRow: true),
                Expanded(
                  child: SingleChildScrollView(
                    controller: pane,
                    // The Presets/Theme rows that sit under the header.
                    child: Column(
                      children: [
                        for (var i = 0; i < 12; i++)
                          SizedBox(height: 56, child: Text('row $i')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'the header stays fully on screen no matter how far the pane below it '
    'is scrolled',
    (tester) async {
      final node = FocusNode(debugLabel: 'pane-0');
      addTearDown(node.dispose);
      final pane = ScrollController();
      addTearDown(pane.dispose);
      await pump(tester, node: node, pane: pane);
      await tester.pumpAndSettle();

      final stageRectBefore = tester.getRect(find.byType(ThemePreviewStage));
      expect(stageRectBefore.top, greaterThanOrEqualTo(0));

      // Scroll the body all the way down, as a D-pad user who has walked
      // through every row below the header.
      pane.jumpTo(pane.position.maxScrollExtent);
      await tester.pump();
      expect(
        pane.offset,
        greaterThan(0),
        reason: 'the body actually scrolled',
      );

      // The header did not move even a pixel — it was never part of the
      // scrolled body to begin with.
      final stageRectAfter = tester.getRect(find.byType(ThemePreviewStage));
      expect(stageRectAfter, stageRectBefore);

      node.requestFocus();
      await tester.pumpAndSettle();
      final stage = tester.getRect(find.byType(ThemePreviewStage));
      expect(stage, stageRectBefore, reason: 'focusing the strip moves nothing');
      // The caption reads LIVE PREVIEW or PREVIEWING depending on which chip
      // the highlight landed on; either way it sits above the stage and must
      // be on screen too.
      final caption = find.textContaining('PREVIEW');
      expect(caption, findsOneWidget);
      expect(tester.getRect(caption).top, greaterThanOrEqualTo(0));
    },
  );

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
