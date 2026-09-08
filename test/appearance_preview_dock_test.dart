import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/screens/settings/widgets/layout_preview_channel.dart';
import 'package:debrify/screens/settings/widgets/layout_preview_stage.dart';
import 'package:debrify/screens/settings/widgets/settings_option_row.dart';
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

/// The pinned Appearance preview dock (Shield feedback, 2026-09-07): by the
/// time D-pad focus (or a pointer) reaches a Screen-layouts row, the live
/// preview card at the top of the pane has scrolled away, so highlighting a
/// chip changes a preview nobody can see. [AppearancePreviewDock] mounts a
/// compact, strip-less copy of the card above the scrolling pane, visible
/// only while [LayoutPreviewChannel.active] — a row is pointed at.
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

  SettingsPageRegistry registry({required bool tv}) => SettingsPageRegistry(
    pages: buildSettingsPages(
      SettingsPageBindings.noop(isAndroidTv: tv, isTelevision: tv),
    ),
  );

  /// The pane shape [SettingsTvLayout]/[SettingsSpotlightShell] actually
  /// build for Layout (a live-preview-hosting category, like Theme): the
  /// dock above a scrolling column of the category's real rows, sharing
  /// one [LayoutPreviewChannel].
  Future<List<FocusNode>> pumpPane(
    WidgetTester tester, {
    required bool tv,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nodes = List.generate(30, (i) => FocusNode(debugLabel: 'pane-$i'));
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });
    final surface = tv ? SettingsLayoutSurface.tv : SettingsLayoutSurface.desktop;
    final kids = buildSettingsCategoryChildren(
      registry: registry(tv: tv),
      surface: surface,
      category: 'Layout',
      paneNodes: tv ? nodes : null,
    );
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            // Same shape as _buildPane/_buildWide: the dock OVERLAYS the
            // scrollable pane rather than pushing it down, so showing it
            // never shifts a just-hovered chip out from under the pointer
            // (which would exit -> collapse -> re-enter -> show, forever).
            child: Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: kids,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AppearancePreviewDock(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return nodes;
  }

  Finder rowFinder(String id) =>
      find.byWidgetPredicate((w) => w is SettingsOptionRow && w.rowId == id);

  Finder dockCaption() => find.descendant(
    of: find.byType(AppearancePreviewDock),
    matching: find.textContaining('PREVIEWING'),
  );

  for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
    testWidgets(
      'TV @ $size: focusing the Details Page row docks the preview above the pane',
      (tester) async {
        await pumpPane(tester, tv: true, size: size);

        // Nothing pointed at yet: the dock is collapsed.
        expect(find.byType(LayoutPreviewStage), findsNothing);
        expect(dockCaption(), findsNothing);

        final row = tester.widget<SettingsOptionRow>(
          rowFinder('detailPageStyle'),
        );
        final node = row.focusNode!;
        node.requestFocus();
        await tester.pumpAndSettle();

        // The dock is on screen and names the row and the highlighted chip.
        final dockStage = find.descendant(
          of: find.byType(AppearancePreviewDock),
          matching: find.byType(LayoutPreviewStage),
        );
        expect(dockStage, findsOneWidget);
        expect(find.textContaining('DETAILS PAGE'), findsWidgets);
        final stage = tester.widget<LayoutPreviewStage>(dockStage);
        expect(stage.rowId, 'detailPageStyle');
        expect(stage.optionId, 'showcase');
        final dockRect = tester.getRect(find.byType(AppearancePreviewDock));
        expect(dockRect.top, greaterThanOrEqualTo(0));
        expect(dockRect.bottom, lessThanOrEqualTo(size.height));

        // Highlighting a different chip changes the dock's layout id, with
        // no pref written.
        final before = (await SharedPreferences.getInstance()).getKeys();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        final stage2 = tester.widget<LayoutPreviewStage>(
          find.descendant(
            of: find.byType(AppearancePreviewDock),
            matching: find.byType(LayoutPreviewStage),
          ),
        );
        expect(stage2.optionId, isNot('showcase'));
        final after = (await SharedPreferences.getInstance()).getKeys();
        expect(after, before, reason: 'a highlight never writes a pref');

        // No new focusable was introduced by the dock: its host claims no
        // focus node of its own (unlike the resting card's Look strip),
        // and never shows one — a stray decorative Focus can still surface
        // inside the invisible-but-mounted ThemePreviewStage underneath the
        // layout stage (same as on the resting card; see
        // AppearancePreviewCard's own Visibility(maintainState: true)), but
        // it is wrapped in ExcludeFocus and was never reachable by D-pad.
        final dockHost = tester.widget<AppearancePreviewHost>(
          find.descendant(
            of: find.byType(AppearancePreviewDock),
            matching: find.byType(AppearancePreviewHost),
          ),
        );
        expect(dockHost.dock, isTrue);
        expect(dockHost.focusNode, isNull);
        expect(
          find.descendant(
            of: find.byType(AppearancePreviewDock),
            matching: find.byType(ExcludeFocus),
          ),
          findsWidgets,
          reason: 'the one decorative Focus left mounted is excluded',
        );

        // Leaving the row (Up, to a non-layout row in production; here,
        // simply losing focus) hides the dock again — even though the
        // RESTING top-of-pane card keeps showing the row's applied layout
        // (existing behaviour, not this dock's concern).
        node.unfocus();
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AppearancePreviewDock),
            matching: find.byType(LayoutPreviewStage),
          ),
          findsNothing,
        );
        expect(dockCaption(), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('desktop @ 1280: hovering the row docks the preview too', (
    tester,
  ) async {
    await pumpPane(tester, tv: false, size: const Size(1280, 800));
    expect(
      find.descendant(
        of: find.byType(AppearancePreviewDock),
        matching: find.byType(LayoutPreviewStage),
      ),
      findsNothing,
    );

    // The Details Page row sits below Presets/Theme — scroll it into view
    // before hovering, same as a real pointer would need to.
    await tester.ensureVisible(rowFinder('detailPageStyle'));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Marquee').first));
    await tester.pumpAndSettle();

    final dockStage = find.descendant(
      of: find.byType(AppearancePreviewDock),
      matching: find.byType(LayoutPreviewStage),
    );
    expect(dockStage, findsOneWidget);
    expect(
      tester.widget<LayoutPreviewStage>(dockStage).optionId,
      'marquee',
    );

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppearancePreviewDock),
        matching: find.byType(LayoutPreviewStage),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the dock never appears for the Look strip — the resting card reveals '
    'itself instead',
    (tester) async {
      final nodes = await pumpPane(tester, tv: true, size: const Size(960, 540));
      // Node zero is the live preview's Look strip (see
      // settings_appearance_groups_test.dart).
      nodes[0].requestFocus();
      await tester.pumpAndSettle();
      // Step off the applied Look so the resting card switches to
      // "PREVIEWING".
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('PREVIEWING'),
        findsOneWidget,
        reason: 'only the resting card previews a Look — never a second, '
            'redundant copy in the dock',
      );
      expect(
        find.descendant(
          of: find.byType(AppearancePreviewDock),
          matching: find.byType(LayoutPreviewStage),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
