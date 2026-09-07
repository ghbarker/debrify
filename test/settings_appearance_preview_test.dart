import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/appearance_preview.dart';
import 'package:debrify/theme/widgets/theme_preview_stage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/golden_harness.dart' show disableRuntimeFonts;

/// The Appearance live preview: pointing at a Look shows it, choosing one
/// applies it, and nothing in between touches the live theme.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppThemeController.instance.select(AppThemes.legacyId);
    await AppThemeController.instance.clearOverrides();
    TextBrightnessController.notifier.value = TextBrightness.bright;
  });

  Future<void> pump(WidgetTester tester, Widget child, {double width = 720}) {
    final theme = AppThemes.byId('spotlight');
    return tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }

  String shownId(WidgetTester tester) =>
      tester.widget<ThemePreviewStage>(find.byType(ThemePreviewStage)).theme.id;

  testWidgets('hovering a Look previews it without changing the controller', (
    tester,
  ) async {
    await pump(tester, const AppearancePreviewHost());
    await tester.pumpAndSettle();
    expect(shownId(tester), AppThemes.legacyId);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Cinema')));
    await tester.pumpAndSettle();
    expect(shownId(tester), 'cinemascope');
    expect(find.text('PREVIEWING'), findsOneWidget);
    expect(find.text('Not applied yet'), findsOneWidget);
    expect(
      AppThemeController.instance.id,
      AppThemes.legacyId,
      reason: 'a hover is a preview, never an apply',
    );

    await mouse.moveTo(tester.getCenter(find.text('Neon Arcade')));
    await tester.pumpAndSettle();
    expect(shownId(tester), 'aurora');
    expect(AppThemeController.instance.id, AppThemes.legacyId);

    // Off the strip: back to what the app is actually running.
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(shownId(tester), AppThemes.legacyId);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DPAD: Left/Right browse on one node, OK applies', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    final applied = <String>[];
    await pump(
      tester,
      AppearancePreviewHost(
        focusNode: node,
        applyLook: (look) async => applied.add(look.id),
      ),
    );
    await tester.pumpAndSettle();

    node.requestFocus();
    await tester.pumpAndSettle();
    // Focus lands on the applied Look (or the first chip for Custom), and
    // that is what the preview shows — still nothing applied.
    final start = AppLooks.all.indexWhere((l) => l.id == shownLook(tester));
    expect(start, greaterThanOrEqualTo(0));
    expect(applied, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final next = AppLooks.all[(start + 1).clamp(0, AppLooks.all.length - 1)];
    expect(shownId(tester), next.values['app_theme']);
    expect(node.hasFocus, isTrue, reason: 'Right stays inside the strip');
    expect(AppThemeController.instance.id, AppThemes.legacyId);
    expect(applied, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(applied, [next.id]);

    // Blur reverts the preview to the live options.
    node.unfocus();
    await tester.pumpAndSettle();
    expect(shownId(tester), AppThemes.legacyId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every Look renders at compact and expanded widths', (
    tester,
  ) async {
    for (final width in const [288.0, 1180.0]) {
      for (final look in AppLooks.all) {
        await pump(
          tester,
          AppearancePreviewCard(
            state: AppearancePreviewState.forLook(look),
            activeLookId: look.id,
            onApply: (_) async {},
          ),
          width: width,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${look.id} @ $width');
        expect(
          shownId(tester),
          look.values['app_theme'],
          reason: '${look.id} @ $width',
        );
        expect(find.text(look.label), findsNWidgets(2), reason: look.id);
      }
    }
  });

  test('the preview resolves like the controller, without applying', () async {
    for (final look in AppLooks.all) {
      final state = AppearancePreviewState.forLook(look);
      final theme = resolveAppearancePreview(state);
      expect(theme.id, look.values['app_theme'], reason: look.id);
      // Same derivation as the live path: apply it and compare the core.
      await AppThemeController.instance.select(state.themeId);
      TextBrightnessController.notifier.value = state.preset;
      final live = AppThemeController.instance.theme;
      expect(theme.core.tx, live.core.tx, reason: look.id);
      expect(theme.core.accent, live.core.accent, reason: look.id);
      expect(theme.focus.expression, live.focus.expression, reason: look.id);
    }
  });
}

/// Which Look the stage is showing, by theme id.
String shownLook(WidgetTester tester) {
  final id = tester
      .widget<ThemePreviewStage>(find.byType(ThemePreviewStage))
      .theme
      .id;
  return AppLooks.all.firstWhere((l) => l.values['app_theme'] == id).id;
}
