import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/settings_tv_layout.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accept: a new page registered once appears in phone, desktop, TV, and
/// search. The three layouts all iterate [SettingsPageRegistry]; search
/// is derived from the same list.
void main() {
  late SettingsPageSpec fake;
  late SettingsPageRegistry registry;

  setUp(() {
    fake = SettingsPageSpec(
      id: 'fakeLanePage',
      row: const SettingsRowContent(
        icon: Icons.science_rounded,
        title: 'Fake Lane Page',
        subtitle: 'Registered once for S1',
      ),
      category: 'Playback',
      opener: () async {},
      keywords: const ['fake-lane-keyword'],
      phoneOrder: 20,
      desktopOrder: 20,
      tvOrder: 20,
    );
    registry = SettingsPageRegistry(
      pages: [
        ...buildSettingsPages(
          SettingsPageBindings.noop(showSwitchProfile: true),
        ),
        fake,
      ],
    );
  });

  test('one registration lights up titlesOn for phone, desktop and TV', () {
    expect(
      registry.titlesOn(SettingsLayoutSurface.phone, category: 'Playback'),
      contains('Fake Lane Page'),
    );
    expect(
      registry.titlesOn(SettingsLayoutSurface.desktop, category: 'Playback'),
      contains('Fake Lane Page'),
    );
    expect(
      registry.titlesOn(SettingsLayoutSurface.tv, category: 'Playback'),
      contains('Fake Lane Page'),
    );
  });

  test('one registration lights up the derived search index', () {
    final hit = registry.searchIndex().where(
      (e) => e.title == 'Fake Lane Page',
    );
    expect(hit, isNotEmpty);
    expect(hit.first.category, 'Playback');
    expect(hit.first.matches(['fake-lane-keyword']), isTrue);
  });

  testWidgets('phone, desktop and TV renderers all show the new row', (
    tester,
  ) async {
    final theme = AppThemes.byId('spotlight');
    Widget wrap(List<Widget> children) => MaterialApp(
      theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
      builder: (context, child) => AppThemeScope(theme: theme, child: child!),
      home: Scaffold(body: ListView(children: children)),
    );

    for (final surface in SettingsLayoutSurface.values) {
      await tester.pumpWidget(
        wrap(
          buildSettingsCategoryChildren(
            registry: registry,
            surface: surface,
            category: 'Playback',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Fake Lane Page'), findsOneWidget, reason: '$surface');
    }
  });

  testWidgets('TV two-pane layout shows the page after one registration', (
    tester,
  ) async {
    final entry = FocusNode(debugLabel: 'settings-test-entry');
    addTearDown(entry.dispose);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: Scaffold(
          body: SettingsTvLayout(
            connections: [
              ConnectionInfo(
                title: 'Real Debrid',
                connected: true,
                status: 'Active',
                caption: 'Ready',
                onTap: () async {},
              ),
            ],
            tracking: ConnectionInfo(
              title: 'Tracking',
              connected: true,
              status: 'Active',
              caption: 'Ready',
              onTap: () async {},
            ),
            trackers: const [],
            firstFocusNode: entry,
            onOpenSearch: () {},
            pages: registry.pages,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rail: 0 Connections, 1 Trackers, 2 Home, 3 Appearance, 4 Playback.
    entry.requestFocus();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(find.text('Fake Lane Page'), findsOneWidget);
  });

  testWidgets('search page lists the new row under Playback', (tester) async {
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: SettingsSearchPage(entries: registry.searchIndex()),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'fake-lane-keyword');
    await tester.pump();
    expect(find.text('Fake Lane Page'), findsOneWidget);
  });
}
