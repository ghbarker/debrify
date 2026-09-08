import 'package:debrify/screens/settings/layout_options.dart';
import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/screens/settings/widgets/layout_preview_channel.dart';
import 'package:debrify/screens/settings/widgets/layout_preview_stage.dart';
import 'package:debrify/screens/settings/widgets/settings_option_row.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/text_brightness.dart';
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

/// The inline Screen-layouts rows: pointing at an option previews it on the
/// Appearance card, choosing one writes exactly that option's pref through
/// the opener page's own setter, and on TV each row is one pane node with
/// Left/Right inside it.
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

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 720,
    KeyEventResult Function(FocusNode, KeyEvent)? outerKey,
  }) {
    final theme = AppThemes.byId('spotlight');
    return tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, c) => AppThemeScope(theme: theme, child: c!),
        home: Scaffold(
          body: Focus(
            onKeyEvent: outerKey ?? (_, _) => KeyEventResult.ignored,
            child: Center(
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The Appearance column as production builds it, with a TV pane pool.
  Future<List<FocusNode>> pumpAppearance(
    WidgetTester tester, {
    required SettingsLayoutSurface surface,
    double width = 720,
    KeyEventResult Function(FocusNode, KeyEvent)? outerKey,
  }) async {
    final nodes = List.generate(30, (i) => FocusNode(debugLabel: 'pane-$i'));
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });
    final tv = surface == SettingsLayoutSurface.tv;
    final kids = buildSettingsCategoryChildren(
      registry: registry(tv: tv),
      surface: surface,
      category: 'Appearance',
      paneNodes: tv ? nodes : null,
    );
    await pump(
      tester,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
      width: width,
      outerKey: outerKey,
    );
    await tester.pumpAndSettle();
    return nodes;
  }

  Finder row(String id) =>
      find.byWidgetPredicate((w) => w is SettingsOptionRow && w.rowId == id);

  Finder chip(String rowId, String label) =>
      find.descendant(of: row(rowId), matching: find.text(label));

  (String, String)? shownLayout(WidgetTester tester) {
    final f = find.byType(LayoutPreviewStage);
    if (f.evaluate().isEmpty) return null;
    final s = tester.widget<LayoutPreviewStage>(f);
    return (s.rowId, s.optionId);
  }

  Future<Set<String>> prefKeys() async =>
      (await SharedPreferences.getInstance()).getKeys();

  testWidgets('the Screen layouts rows render inline, one pane node each', (
    tester,
  ) async {
    final nodes = await pumpAppearance(
      tester,
      surface: SettingsLayoutSurface.tv,
    );
    final claimed = <FocusNode>{};
    for (final id in ['tvHomeStyle', 'discoverLayout', 'detailPageStyle']) {
      expect(row(id), findsOneWidget, reason: id);
      final r = tester.widget<SettingsOptionRow>(row(id));
      expect(nodes, contains(r.focusNode), reason: '$id claims a pane node');
      expect(claimed.add(r.focusNode!), isTrue, reason: '$id shares a node');
      // Every option is a chip; the applied one is ticked.
      for (final o in r.options.options) {
        expect(chip(id, o.label), findsOneWidget, reason: '$id/${o.id}');
      }
    }
    // Nothing touched yet: the theme stage is up, exactly as before.
    expect(find.byType(ThemePreviewStage), findsOneWidget);
    expect(shownLayout(tester), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'choosing Marquee persists detail_page_style only and the stage shows it',
    (tester) async {
      await pumpAppearance(tester, surface: SettingsLayoutSurface.phone);
      final before = await prefKeys();

      // The row sits below the card and two groups: bring it on screen.
      await tester.ensureVisible(row('detailPageStyle'));
      await tester.pumpAndSettle();
      await tester.tap(chip('detailPageStyle', 'Marquee'));
      await tester.pumpAndSettle();

      expect(await AppStylePrefs.getDetailPageStyle(), 'marquee');
      final added = (await prefKeys()).difference(before);
      expect(added, hasLength(1), reason: 'exactly one pref written: $added');
      expect(added.single, endsWith('detail_page_style'));

      expect(shownLayout(tester), ('detailPageStyle', 'marquee'));
      expect(find.text('LIVE PREVIEW · DETAILS PAGE'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hovering an option previews it without persisting', (
    tester,
  ) async {
    await pumpAppearance(tester, surface: SettingsLayoutSurface.phone);
    await tester.ensureVisible(row('detailPageStyle'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(chip('detailPageStyle', 'Dossier')));
    await tester.pumpAndSettle();
    expect(shownLayout(tester), ('detailPageStyle', 'dossier'));
    expect(find.text('PREVIEWING · DETAILS PAGE'), findsOneWidget);
    expect(find.text('Not applied yet'), findsOneWidget);
    expect(
      (await prefKeys()).where((k) => k.endsWith('detail_page_style')),
      isEmpty,
      reason: 'a hover is a preview, never a write',
    );

    // Off the chip: the stage keeps the row's APPLIED layout rather than
    // snapping back to the theme stage.
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(shownLayout(tester), ('detailPageStyle', 'showcase'));
    expect(find.text('LIVE PREVIEW · DETAILS PAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV: Left/Right move inside the row; Down and Left-at-first leave it',
    (tester) async {
      final reached = <LogicalKeyboardKey>[];
      final nodes = await pumpAppearance(
        tester,
        surface: SettingsLayoutSurface.tv,
        outerKey: (_, e) {
          if (e is KeyDownEvent) reached.add(e.logicalKey);
          return KeyEventResult.handled;
        },
      );
      final r = tester.widget<SettingsOptionRow>(row('detailPageStyle'));
      final node = r.focusNode!;
      expect(nodes, contains(node));

      node.requestFocus();
      await tester.pumpAndSettle();
      // Focus lands on the applied option and previews it as applied.
      expect(shownLayout(tester), ('detailPageStyle', 'showcase'));
      expect(find.text('LIVE PREVIEW · DETAILS PAGE'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue, reason: 'Right stays inside the row');
      expect(shownLayout(tester), ('detailPageStyle', 'classic'));
      expect(find.text('PREVIEWING · DETAILS PAGE'), findsOneWidget);
      expect(reached, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(shownLayout(tester), ('detailPageStyle', 'showcase'));
      expect(reached, isEmpty);

      // At the first chip Left is left to the pane (it hands to the rail).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(reached, [LogicalKeyboardKey.arrowLeft]);

      // Up/Down are never the row's: the pane walks by node index.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(reached.last, LogicalKeyboardKey.arrowDown);

      // OK applies the highlighted option.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(await AppStylePrefs.getDetailPageStyle(), 'classic');
      expect(shownLayout(tester), ('detailPageStyle', 'classic'));
      expect(find.text('Applied'), findsOneWidget);

      // Blur: the applied layout stays on the stage, no longer a candidate.
      node.unfocus();
      await tester.pumpAndSettle();
      expect(shownLayout(tester), ('detailPageStyle', 'classic'));
      expect(find.text('LIVE PREVIEW · DETAILS PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV: the Details Page row is one scrolling strip, never a wrapped second '
    'row',
    (tester) async {
      await pumpAppearance(tester, surface: SettingsLayoutSurface.tv);
      expect(
        find.descendant(of: row('detailPageStyle'), matching: find.byType(Wrap)),
        findsNothing,
        reason: 'no wrapped second row on a D-pad surface',
      );
      final strip = find.descendant(
        of: row('detailPageStyle'),
        matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(strip, findsOneWidget);
      final stripRect = tester.getRect(strip);

      final r = tester.widget<SettingsOptionRow>(row('detailPageStyle'));
      final node = r.focusNode!;
      final optionCount = r.options.options.length;
      expect(
        optionCount,
        greaterThan(6),
        reason: 'the Details Page row is the long one this guards',
      );

      node.requestFocus();
      await tester.pumpAndSettle();
      for (var i = 1; i < optionCount; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final lastLabel = r.options.options.last.label;
      final lastChip = tester.getRect(chip('detailPageStyle', lastLabel));
      expect(
        lastChip.center.dx,
        inInclusiveRange(stripRect.left, stripRect.right),
        reason: 'the row scrolled to keep the last chip in view',
      );
      // Trapped at the end: one more Right stays put and throws nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(node.hasFocus, isTrue);
    },
  );

  testWidgets('desktop: the same row keeps a Wrap, not a scrolling strip', (
    tester,
  ) async {
    await pumpAppearance(tester, surface: SettingsLayoutSurface.desktop);
    expect(
      find.descendant(of: row('detailPageStyle'), matching: find.byType(Wrap)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('detailPageStyle'),
        matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
  });

  // Every other row: choosing its second option writes exactly that row's
  // pref (one new key, the expected suffix) through the writer, and the
  // stage shows the choice as applied.
  for (final (rowId, option, keySuffix, tv) in const [
    ('tvSidebarStyle', 'Island', 'tv_sidebar_style', true),
    ('iptvAppearance', 'First Edition', 'iptv_style', true),
    ('debrifyTvAppearance', 'Spotlight', 'debrify_tv_style', true),
    ('playerGuideStyle', 'Cinema Glass', 'iptv_player_guide_style', true),
    ('playLoaderStyle', 'Classic', 'play_loader_style', true),
    ('parentsGuideStyle', 'Classic', 'parents_guide_style', true),
    ('profileAppearance', 'Theater', 'profile_gate_style_v1', true),
    ('playerDock', 'Cinema Bar', 'player_dock_style', false),
    ('navigationStyleAppearance', 'Floating button', 'phone_nav_style', false),
    ('desktopSidebarStyle', 'Pill', 'desktop_sidebar_style', false),
  ]) {
    testWidgets('$rowId: choosing $option writes only $keySuffix', (
      tester,
    ) async {
      await pumpAppearance(
        tester,
        surface: tv ? SettingsLayoutSurface.tv : SettingsLayoutSurface.phone,
      );
      final before = await prefKeys();
      await tester.ensureVisible(row(rowId));
      await tester.pumpAndSettle();
      await tester.tap(chip(rowId, option));
      await tester.pumpAndSettle();

      final added = (await prefKeys()).difference(before);
      expect(added, hasLength(1), reason: 'exactly one pref written: $added');
      expect(added.single, endsWith(keySuffix));
      final r = tester.widget<SettingsOptionRow>(row(rowId));
      final chosen = r.options.options.firstWhere((o) => o.label == option);
      expect(shownLayout(tester), (rowId, chosen.id));
      expect(find.text('Applied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the More chip is the last stop on the row and opens the page', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    var opened = 0;
    final options = SettingsLayoutOptions(
      rowId: 'playerDock',
      options: const [
        LayoutOption('classic', 'Classic', 'a'),
        LayoutOption('auto', 'Adaptive', 'b'),
      ],
      current: () => 'classic',
      apply: (_) async {},
      moreLabel: 'Colour & size',
      onMore: () async => opened++,
    );
    await pump(
      tester,
      SettingsOptionRow(
        icon: Icons.tune_rounded,
        title: 'Player Controls',
        options: options,
        focusNode: node,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Colour & size'), findsOneWidget);

    node.requestFocus();
    await tester.pumpAndSettle();
    // Classic → Adaptive → More; Right traps there.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(find.text('More options'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(opened, 1);

    await tester.tap(find.text('Colour & size'));
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pane node reused after the row is gone carries no handler', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'pane-0');
    addTearDown(node.dispose);
    final options = SettingsLayoutOptions(
      rowId: 'detailPageStyle',
      options: const [
        LayoutOption('showcase', 'Showcase', 'a'),
        LayoutOption('classic', 'Classic', 'b'),
      ],
      current: () => 'showcase',
      apply: (_) async {},
    );

    await pump(
      tester,
      SettingsOptionRow(
        icon: Icons.article_rounded,
        title: 'Details Page',
        options: options,
        focusNode: node,
      ),
    );
    await tester.pumpAndSettle();
    node.requestFocus();
    await tester.pump();
    expect(node.onKeyEvent, isNotNull, reason: 'the row owns the node');
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
    expect(node.onKeyEvent, isNull, reason: 'dispose must release the node');

    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every option of every row renders at every width', (
    tester,
  ) async {
    final seen = <String>{};
    for (final tv in [true, false]) {
      for (final page in registry(tv: tv).pages) {
        final o = page.layoutOptions;
        if (o == null || !seen.add(o.rowId)) continue;
        for (final option in o.options) {
          final target = LayoutPreviewTarget(
            rowId: o.rowId,
            rowTitle: page.title,
            optionId: option.id,
            optionLabel: option.label,
            applied: true,
          );
          // Compact phone, the TV pane, a wide desktop pane.
          for (final width in const [288.0, 600.0, 1180.0]) {
            await pump(
              tester,
              AppearancePreviewCard(
                state: const AppearancePreviewState(
                  themeId: 'spotlight',
                  lookLabel: 'Spotlight',
                ),
                activeLookId: 'spotlight',
                layout: target,
                onApply: (_) async {},
              ),
              width: width,
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '${o.rowId}/${option.id} @ $width',
            );
            expect(find.byType(LayoutPreviewStage), findsOneWidget);
            // At least: a layout named like a Look ("Spotlight") is also on
            // the look strip.
            expect(find.text(option.label), findsAtLeastNWidgets(1));
          }
        }
      }
    }
    expect(
      seen,
      containsAll(['tvHomeStyle', 'discoverLayout', 'detailPageStyle']),
    );
  });

  testWidgets('an unknown row or option falls back to the generic picture', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 320,
        height: 180,
        child: LayoutSchematic(rowId: 'nope', optionId: 'nope'),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(LayoutSchematic), findsOneWidget);
  });

  testWidgets('a Look candidate wins over a layout on the stage', (
    tester,
  ) async {
    await pump(
      tester,
      AppearancePreviewCard(
        state: const AppearancePreviewState(themeId: 'noir', lookLabel: 'Noir'),
        activeLookId: 'spotlight',
        candidate: true,
        layout: const LayoutPreviewTarget(
          rowId: 'detailPageStyle',
          rowTitle: 'Details Page',
          optionId: 'showcase',
          optionLabel: 'Showcase',
          applied: true,
        ),
        onApply: (_) async {},
      ),
    );
    await tester.pump();
    expect(find.byType(LayoutPreviewStage), findsNothing);
    expect(find.text('PREVIEWING'), findsOneWidget);
  });

  testWidgets('phone Appearance with an inline layouts row', (tester) async {
    // The card and the Details Page row as the phone column builds them,
    // under one RepaintBoundary so the golden is those two and not the
    // scroll view around them.
    final kids = buildSettingsCategoryChildren(
      registry: registry(tv: false),
      surface: SettingsLayoutSurface.phone,
      category: 'Appearance',
    );
    SettingsOptionRow? detail;
    for (final k in kids) {
      if (k is SettingsSection) {
        for (final c in k.children) {
          if (c is SettingsOptionRow && c.rowId == 'detailPageStyle') {
            detail = c;
          }
        }
      }
    }
    expect(detail, isNotNull);
    LayoutPreviewChannel.instance.rest(
      const LayoutPreviewTarget(
        rowId: 'detailPageStyle',
        rowTitle: 'Details Page',
        optionId: 'showcase',
        optionLabel: 'Showcase',
        applied: true,
      ),
    );
    await pump(
      tester,
      RepaintBoundary(
        key: const Key('golden'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            kids.first,
            const SizedBox(height: 18),
            SettingsSection(title: 'Screen layouts', children: [detail!]),
          ],
        ),
      ),
      width: 390,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/settings_layout_options_phone.png'),
    );
  }, tags: ['golden']);
}
