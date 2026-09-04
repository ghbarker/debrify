import 'package:debrify/screens/settings/settings_tv_layout.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _noop() async {}
void _voidNoop() {}

ConnectionInfo _connection(String title, {bool connected = true}) =>
    ConnectionInfo(
      title: title,
      connected: connected,
      status: connected ? 'Active' : 'Not connected',
      caption: connected ? 'Ready for playback' : 'Connect this service',
      onTap: _noop,
    );

SettingsTvLayout _layout(FocusNode entry) => SettingsTvLayout(
  connections: [
    _connection('Real Debrid'),
    _connection('Torbox'),
    _connection('Premiumize', connected: false),
    _connection('AllDebrid'),
  ],
  tracking: _connection('Tracking'),
  trackers: [_connection('Trakt'), _connection('Simkl', connected: false)],
  firstFocusNode: entry,
  onOpenSearch: _voidNoop,
);

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
  testWidgets('TV grid keeps deterministic two-dimensional DPAD movement', (
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

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-1',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-3',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-2',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-rail-0',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact logical TV falls back to one connection column', (
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

    // On compact TV the grid becomes a list, so Down advances by one.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tracker policy and services are separate DPAD sections', (
    tester,
  ) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry-trackers');
    addTearDown(entry.dispose);
    await _pumpTv(tester, const Size(960, 540), entry);

    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(find.text('TRACKING'), findsOneWidget);
    expect(find.text('TRACKER SERVICES'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-1',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'settings-tv-pane-2',
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
