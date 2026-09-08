import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/widgets/settings_option_row.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/tv_motion_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance → Display → "TV motion": the catalog wires the row through the
/// SAME [SettingsOptionRow] the Screen-layouts rows use (kind: options), so
/// this is mostly a wiring test — the chip mechanics themselves are covered
/// generically by test/settings_layout_options_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStylePrefs.tvMotionProfileCached = null;
    TvMotionController.debugReset();
  });
  tearDown(() => TvMotionController.debugReset());

  SettingsPageRegistry registry() => SettingsPageRegistry(
    pages: buildSettingsPages(
      SettingsPageBindings.noop(isAndroidTv: true, isTelevision: true),
    ),
  );

  Finder row() => find.byWidgetPredicate(
    (w) => w is SettingsOptionRow && w.rowId == 'tvMotion',
  );
  Finder chip(String label) =>
      find.descendant(of: row(), matching: find.text(label));

  Future<void> pump(
    WidgetTester tester,
    FocusNode node, {
    KeyEventResult Function(FocusNode, KeyEvent)? outerKey,
  }) async {
    final spec = registry().pages.firstWhere((p) => p.id == 'tvMotion');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, c) =>
            AppThemeScope(theme: AppThemes.legacy, child: c!),
        home: Scaffold(
          body: Focus(
            onKeyEvent: outerKey ?? (_, _) => KeyEventResult.ignored,
            child: Center(
              child: SizedBox(
                width: 500,
                child: settingsPageRow(
                  spec,
                  surface: SettingsLayoutSurface.tv,
                  focusNode: node,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the row is the shared SettingsOptionRow with two chips', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    await pump(tester, node);

    expect(row(), findsOneWidget);
    final r = tester.widget<SettingsOptionRow>(row());
    expect(r.options.options.map((o) => o.id), ['smooth', 'snappy']);
    expect(chip('Smooth'), findsOneWidget);
    expect(chip('Snappy'), findsOneWidget);
    // Snappy is the device default in a plain test host (no TV plugin).
    expect(TvMotionController.current, TvMotionProfile.snappy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing Smooth persists exactly tv_motion_profile', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    await pump(tester, node);

    final before = (await SharedPreferences.getInstance()).getKeys();
    await tester.tap(chip('Smooth'));
    await tester.pumpAndSettle();

    expect(TvMotionController.current, TvMotionProfile.smooth);
    expect(TvMotionController.isExplicit, isTrue);
    final added = (await SharedPreferences.getInstance()).getKeys()
        .difference(before);
    expect(added, hasLength(1), reason: 'exactly one pref written: $added');
    expect(added.single, endsWith('tv_motion_profile'));
    expect(await AppStylePrefs.getTvMotionProfile(), 'smooth');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV: Left/Right move inside the row; Down and Left-at-first leave it',
    (tester) async {
      final reached = <LogicalKeyboardKey>[];
      final node = FocusNode(debugLabel: 'pane-0');
      addTearDown(node.dispose);
      await pump(
        tester,
        node,
        outerKey: (_, e) {
          if (e is KeyDownEvent) reached.add(e.logicalKey);
          return KeyEventResult.handled;
        },
      );

      node.requestFocus();
      await tester.pumpAndSettle();

      // Snappy is applied; focus lands on it first.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue, reason: 'Right stays inside the row');
      expect(reached, isEmpty);

      // At the first chip Left is left to the pane.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(reached, [LogicalKeyboardKey.arrowLeft]);

      // Up/Down are never the row's.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(reached.last, LogicalKeyboardKey.arrowDown);

      // The walk left ("Left, Left") above landed the highlight back on
      // Smooth (index 0); OK applies it.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(TvMotionController.current, TvMotionProfile.smooth);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a pane node reused after the row is gone carries no key handler',
    (tester) async {
      final node = FocusNode(debugLabel: 'pane-0');
      addTearDown(node.dispose);
      await pump(tester, node);
      node.requestFocus();
      await tester.pump();
      expect(node.onKeyEvent, isNotNull, reason: 'the row owns the node');

      // Another category's first row now reuses the same pane node.
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: node, child: const SizedBox(width: 10, height: 10)),
        ),
      );
      await tester.pumpAndSettle();
      expect(node.onKeyEvent, isNull, reason: 'dispose must release the node');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a chip press rebuilds a real AppMotion.tvFocus consumer', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    final durations = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<TvMotionProfile>(
          valueListenable: TvMotionController.notifier,
          builder: (context, profile, child) => TvMotionScope(
            profile: profile,
            child: AppThemeScope(
              theme: AppThemes.legacy,
              child: Column(
                children: [
                  settingsPageRow(
                    registry().pages.firstWhere((p) => p.id == 'tvMotion'),
                    surface: SettingsLayoutSurface.tv,
                    focusNode: node,
                  ),
                  Builder(
                    builder: (context) {
                      durations.add(AppMotion.of(context).tvFocus);
                      return const SizedBox();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(durations.last, const Duration(milliseconds: 120));

    await tester.tap(chip('Smooth'));
    await tester.pumpAndSettle();

    expect(durations.last, const Duration(milliseconds: 220));
    expect(tester.takeException(), isNull);
  });
}
