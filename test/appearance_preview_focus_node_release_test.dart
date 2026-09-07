import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/golden_harness.dart' show disableRuntimeFonts;

/// The TV settings layout owns the pane FocusNodes and reuses them across
/// categories. The Appearance look strip must not leave its key handler on
/// that node once it is gone: Focus never clears an external node's
/// onKeyEvent, and FocusNode.attach keeps the old handler when the next
/// Focus supplies none — which left node 0 routing every Left/Right to a
/// disposed State and broke D-pad navigation app-wide (Shield, 2026-09-07).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppThemeController.instance.select(AppThemes.legacyId);
    await AppThemeController.instance.clearOverrides();
    TextBrightnessController.notifier.value = TextBrightness.bright;
  });

  Future<void> pump(WidgetTester tester, Widget child) {
    final theme = AppThemes.byId('spotlight');
    return tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(body: SizedBox(width: 960, child: child)),
      ),
    );
  }

  testWidgets(
    'a pane node reused after the look strip is gone carries no stale handler',
    (tester) async {
      final node = FocusNode(debugLabel: 'pane-0');
      addTearDown(node.dispose);

      await pump(tester, AppearancePreviewHost(focusNode: node));
      await tester.pumpAndSettle();
      node.requestFocus();
      await tester.pump();
      expect(node.onKeyEvent, isNotNull, reason: 'the strip owns the node');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Another category's first row now reuses the same pane node, and it
      // registers no key handler of its own.
      await pump(
        tester,
        Focus(focusNode: node, child: const SizedBox(width: 10, height: 10)),
      );
      await tester.pumpAndSettle();
      expect(
        node.onKeyEvent,
        isNull,
        reason: 'dispose must release the external node',
      );

      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
