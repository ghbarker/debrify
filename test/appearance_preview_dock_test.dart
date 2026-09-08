import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/settings_spotlight_shell.dart';
import 'package:debrify/screens/settings/settings_tv_layout.dart';
import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/screens/settings/widgets/layout_preview_channel.dart';
import 'package:debrify/screens/settings/widgets/layout_preview_stage.dart';
import 'package:debrify/screens/settings/widgets/settings_option_row.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/golden_harness.dart' show disableRuntimeFonts;

/// The pinned Appearance preview (Shield feedback, 2026-09-07): "the live
/// preview also needs changed, it should stay pinned at the top of the
/// screen and change based on what is hovered/last selected. The current way
/// is way too small."
///
/// This replaces the old top-of-pane card (which scrolled away with the rest
/// of the pane) and its separate, cramped 78px-tall compact copy
/// (`AppearancePreviewDock`, since removed) with ONE preview —
/// [AppearancePreviewHost] — that a shell pins as a genuine, non-scrolling
/// header. Which stage it shows (a Look on the strip, or a Screen-layouts
/// row elsewhere in the pane) comes from [LayoutPreviewChannel]'s
/// pointed/resting model, the single source of truth both write to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LayoutPreviewChannel.instance.reset();
    await AppThemeController.instance.select(AppThemes.legacyId);
    await AppThemeController.instance.clearOverrides();
    TextBrightnessController.notifier.value = TextBrightness.bright;
  });

  Future<void> noop() async {}
  void voidNoop() {}

  ConnectionInfo connection(String title) => ConnectionInfo(
    title: title,
    connected: true,
    status: 'Active',
    caption: 'Ready for playback',
    onTap: noop,
  );

  /// The real TV two-pane shell, navigated onto the Appearance category —
  /// the rail order is Connections, Trackers, Home & Display, Appearance.
  Future<FocusNode> pumpTv(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entry = FocusNode(debugLabel: 'preview-test-entry');
    addTearDown(entry.dispose);
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(
          body: SettingsTvLayout(
            connections: [connection('Real Debrid')],
            tracking: connection('Tracking'),
            trackers: [connection('Trakt')],
            firstFocusNode: entry,
            onOpenSearch: voidNoop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    entry.requestFocus();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    return entry;
  }

  /// The real spotlight shell, wired the way `settings_screen.dart` wires
  /// it: the preview supplied through `pinnedHeaderBuilder`, the rest of the
  /// category (Look strip excluded from the header) through
  /// `categoryBuilder`.
  Future<void> pumpDesktop(
    WidgetTester tester, {
    double width = 1280,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final registry = SettingsPageRegistry(
      pages: buildSettingsPages(
        SettingsPageBindings.noop(isAndroidTv: false, isTelevision: false),
      ),
    );
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(
          body: SettingsSpotlightShell(
            categories: const [
              SettingsCategoryDefinition(
                icon: Icons.auto_awesome_rounded,
                label: 'Appearance',
                subtitle: 'Look and layout',
                eyebrow: 'Appearance',
                title: 'Make it feel like yours.',
                description: 'Choose a Look, then tune only what matters.',
              ),
            ],
            onOpenSearch: () {},
            categoryBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: buildSettingsCategoryChildren(
                registry: registry,
                surface: SettingsLayoutSurface.desktop,
                category: 'Appearance',
                includeAppearancePreview: false,
              ),
            ),
            pinnedHeaderBuilder: (context, index) =>
                const AppearancePreviewHost(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rowFinder(String id) =>
      find.byWidgetPredicate((w) => w is SettingsOptionRow && w.rowId == id);

  SettingsOptionRow? focusedRow(WidgetTester tester) {
    for (final e in find.byType(SettingsOptionRow).evaluate()) {
      final w = e.widget as SettingsOptionRow;
      if (w.focusNode?.hasFocus ?? false) return w;
    }
    return null;
  }

  for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
    testWidgets(
      'TV @ $size: the pinned header stays put while DPAD scrolls the pane, '
      'and shows the focused row',
      (tester) async {
        await pumpTv(tester, size);

        // Entering the pane lands on the preview's own node (the strip);
        // nothing is pointed at yet.
        expect(find.byType(AppearancePreviewHost), findsOneWidget);
        expect(find.byType(LayoutPreviewStage), findsNothing);
        final headerRectBefore = tester.getRect(
          find.byType(AppearancePreviewHost),
        );

        // Walk Down until the Details Page row is focused — this scrolls
        // the pane well past where the header used to sit.
        var guard = 0;
        while (focusedRow(tester)?.rowId != 'detailPageStyle' && guard < 40) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          guard++;
        }
        expect(
          focusedRow(tester)?.rowId,
          'detailPageStyle',
          reason: 'the row must be reachable within a bounded number of '
              'DPAD steps',
        );

        // The header's on-screen TOP-LEFT is UNCHANGED — it is a fixed
        // header, not a scroll-position-relative overlay. (Its height can
        // legitimately shift by a pixel or two between captions of
        // different lengths; position is what "pinned" promises.)
        expect(
          tester.getRect(find.byType(AppearancePreviewHost)).topLeft,
          headerRectBefore.topLeft,
          reason: 'scrolling the pane must not move the pinned preview',
        );

        // It shows the focused row's applied option, in the SAME slot — no
        // second, duplicate preview anywhere in the tree.
        expect(find.byType(AppearancePreviewHost), findsOneWidget);
        final stageFinder = find.byType(LayoutPreviewStage);
        expect(stageFinder, findsOneWidget);
        final stage = tester.widget<LayoutPreviewStage>(stageFinder);
        expect(stage.rowId, 'detailPageStyle');
        expect(stage.optionId, 'showcase');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'desktop @ 1280: the pinned header stays put while the pane scrolls, and '
    'the SAME slot shows a Look hover then a Screen-layouts hover',
    (tester) async {
      await pumpDesktop(tester);

      final headerFinder = find.byType(AppearancePreviewHost);
      final headerState = tester.state(headerFinder);
      final headerRectBefore = tester.getRect(headerFinder);
      expect(find.byType(LayoutPreviewStage), findsNothing);
      expect(find.text('LIVE PREVIEW'), findsOneWidget);

      final detailRow = rowFinder('detailPageStyle');
      await tester.ensureVisible(detailRow);
      await tester.pumpAndSettle();

      // Scrolling to reach the row must not move the header.
      expect(tester.getRect(headerFinder).topLeft, headerRectBefore.topLeft);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // Hover a Screen-layouts row: the header swaps to the layout stage.
      await mouse.moveTo(tester.getCenter(find.text('Marquee').first));
      await tester.pumpAndSettle();
      expect(find.byType(AppearancePreviewHost), findsOneWidget);
      final layoutStage = tester.widget<LayoutPreviewStage>(
        find.byType(LayoutPreviewStage),
      );
      expect(layoutStage.rowId, 'detailPageStyle');
      expect(layoutStage.optionId, 'marquee');
      // The stage genuinely reads at size — meaningfully bigger than the old
      // dock's 78px-tall compact box.
      expect(
        tester.getRect(find.byType(LayoutPreviewStage)).height,
        greaterThan(150),
      );

      // Hover off, onto a Look chip instead: the SAME header slot now shows
      // the theme stage — never a second preview appearing alongside it.
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Cinema')));
      await tester.pumpAndSettle();
      expect(find.byType(AppearancePreviewHost), findsOneWidget);
      expect(find.byType(LayoutPreviewStage), findsNothing);
      expect(find.text('PREVIEWING'), findsOneWidget);

      // Still the exact same State instance — a genuinely unified preview,
      // not two systems swapped in and out.
      expect(identical(tester.state(headerFinder), headerState), isTrue);
      expect(tester.getRect(headerFinder).topLeft, headerRectBefore.topLeft);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid hover across the Look strip and a Screen-layouts row does not '
    'flicker: no infinite rebuild, and nothing under the pointer shifts',
    (tester) async {
      await pumpDesktop(tester);
      final detailRow = rowFinder('detailPageStyle');
      await tester.ensureVisible(detailRow);
      await tester.pumpAndSettle();

      final rowRectBefore = tester.getRect(detailRow);
      final headerRectBefore = tester.getRect(
        find.byType(AppearancePreviewHost),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // The exact shape of the old bug: a reflow that moves content out from
      // under the cursor exits the hover, which changes the preview, which
      // reflows again — repeating forever. A genuinely pinned header cannot
      // reflow anything when its content changes (it never pushes what is
      // below it), so this sweep must settle, not hang.
      final points = [
        tester.getCenter(find.text('Cinema')),
        tester.getCenter(find.text('Showcase').first),
        tester.getCenter(find.text('Marquee').first),
        tester.getCenter(find.text('Classic').first),
      ];
      for (var round = 0; round < 4; round++) {
        for (final p in points) {
          await mouse.moveTo(p);
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      // A resurrected flicker loop would never settle here.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        tester.getRect(detailRow),
        rowRectBefore,
        reason: 'hovering never reflows a row below the pinned header',
      );
      expect(
        tester.getRect(find.byType(AppearancePreviewHost)).topLeft,
        headerRectBefore.topLeft,
      );

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test('the pinned stage is meaningfully larger than the old dock', () {
    // The old AppearancePreviewDock fitted either stage into a 78px-tall
    // compact box; LayoutPreviewStage's own design canvas is 320x180. The
    // pinned header's slot is a named-constant multiple of both.
    const oldDockHeight = 78.0;
    expect(kAppearancePreviewStageMaxHeight, greaterThan(oldDockHeight * 2.5));
    expect(
      kAppearancePreviewStageMaxHeight,
      greaterThan(LayoutPreviewStage.canvasHeight),
    );
    expect(
      kAppearancePreviewStageMaxWidth,
      greaterThan(LayoutPreviewStage.canvasWidth),
    );
    expect(
      kAppearancePreviewStageMaxWidth / kAppearancePreviewStageMaxHeight,
      closeTo(kAppearancePreviewStageAspectRatio, 0.01),
    );
  });
}
