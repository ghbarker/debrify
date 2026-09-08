import 'package:debrify/screens/settings/settings_tv_layout.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void _voidNoop() {}

/// [pages] defaults to the production catalog (via [SettingsTvLayout]'s
/// noop-binding fallback) — Connections is a plain registry-driven category
/// like every other one now, so these tests exercise the real Storage
/// Providers row order rather than a synthetic fixture.
SettingsTvLayout _layout(FocusNode entry) =>
    SettingsTvLayout(firstFocusNode: entry, onOpenSearch: _voidNoop);

Future<void> _pumpTv(
  WidgetTester tester,
  Size size,
  FocusNode entry, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = AppThemes.byId('spotlight');
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
      builder: (context, child) => AppThemeScope(
        theme: theme,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(body: _layout(entry)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TV pane keeps deterministic single-column DPAD movement', (
    tester,
  ) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry');
    addTearDown(entry.dispose);
    await _pumpTv(tester, const Size(960, 540), entry);

    entry.requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-rail-0',
    );

    // Right enters the pane on the Connections category's first row
    // (Real-Debrid, the first Storage Providers row).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-0',
    );

    // Down/Up walk the single column one row at a time — no grid geometry.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-1',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-2',
    );

    // Right does nothing — the pane traps it, there is nothing beside a row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-2',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-1',
    );

    // Left always returns to the rail item for the category being viewed.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-rail-0',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV pane survives a compact TV width without exceptions', (
    tester,
  ) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry-compact');
    addTearDown(entry.dispose);
    await _pumpTv(tester, const Size(720, 480), entry);

    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV Spotlight settings visual', (tester) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry-golden');
    addTearDown(entry.dispose);
    await _pumpTv(tester, const Size(960, 540), entry);

    entry.requestFocus();
    await tester.pump();
    await expectLater(
      find.byType(SettingsTvLayout),
      matchesGoldenFile('goldens/settings_spotlight_tv.png'),
    );
  }, tags: ['golden']);

  testWidgets('Theme opens on the live preview; one node, Left/Right inside', (
    tester,
  ) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry-theme');
    addTearDown(entry.dispose);
    await _pumpTv(tester, const Size(960, 540), entry);

    entry.requestFocus();
    await tester.pump();
    // Rail: Connections → Layout → Theme. The pane follows rail focus, so
    // the preview is already up before entering.
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tv-rail-2');
    expect(find.text('LIVE PREVIEW'), findsOneWidget);

    // Enter: the first pane node is the preview's Look strip.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tv-pane-0');

    // Right browses Looks WITHOUT leaving the node or applying anything.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tv-pane-0');
    expect(find.text('PREVIEWING'), findsOneWidget);
    expect(find.text('Not applied yet'), findsOneWidget);

    // Down reaches Theme's first row (Looks — Theme has no sub-groups); Up
    // comes back to the strip.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tv-pane-1');
    expect(find.text('PREVIEWING'), findsNothing, reason: 'blur reverts');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tv-pane-0');

    await expectLater(
      find.byType(SettingsTvLayout),
      matchesGoldenFile('goldens/settings_spotlight_tv_appearance.png'),
    );

    // Left from the first chip hands back to the SELECTED rail item.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tv-rail-2');
    expect(tester.takeException(), isNull);
  }, tags: ['golden']);

  testWidgets('TV layout tolerates enlarged system text', (tester) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry-large-text');
    addTearDown(entry.dispose);
    await _pumpTv(tester, const Size(960, 540), entry, textScale: 1.5);

    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-0',
    );
    expect(tester.takeException(), isNull);
  });
}
