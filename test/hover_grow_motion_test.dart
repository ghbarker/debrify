import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_art.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_light.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/theme_spec.dart';
import 'package:debrify/theme/widgets/focus_expression.dart';
import 'package:debrify/theme/widgets/hover_grow.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:debrify/widgets/detail/catalog_detail_rec_card.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/card_focus_rise.dart';

/// The "hovered box gets bigger" feedback, pinned at its one source of truth.
///
/// Four tile sites used to carry their own scale and their own duration; now
/// they all read `FocusTokens.hoverScaleFor` and `AppMotion`. These tests pin
/// the contract those sites rely on: a pointer and a non-TV keyboard cursor
/// grow by the shared figure at the theme's tempo, a TV keeps its calmer pop
/// and runs it on the shared TV focus beat (`AppMotion.tvFocus` — the same
/// non-zero duration for the tile losing focus and the tile gaining it, so
/// nothing snaps), and reduced motion collapses the tween to nothing.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The one TV tempo, as the legacy theme vends it at the default motion
  /// setting: the same figure every assertion below compares against.
  const tvFocus = AppMotion(MotionTokens.legacy, reduced: false);

  const item = StremioMeta(
    id: 'tt1',
    imdbId: 'tt1',
    type: 'movie',
    name: 'Tile',
  );

  Widget host(
    Widget child, {
    AppTheme? theme,
    bool reduceMotion = false,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: AppThemeScope(
        theme: theme ?? AppThemes.legacy,
        child: Material(
          child: Center(
            child: SizedBox(width: 200, height: 300, child: child),
          ),
        ),
      ),
    ),
  );

  Widget tile({required bool tv, FocusNode? node}) => CatalogItemTile(
    item: item,
    isTelevision: tv,
    focusNode: node,
    hasBoundSource: false,
    onOpen: () {},
  );

  /// The one AnimatedScale a tile builds — the shared grow.
  AnimatedScale scaleUnder(WidgetTester tester, Type of) =>
      tester.widget<AnimatedScale>(
        find
            .descendant(of: find.byType(of), matching: find.byType(AnimatedScale))
            .first,
      );

  Future<void> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
  }

  group('the shared figure', () {
    test('desktop is 1.12, TV is the calm 1.045, whatever a theme asks', () {
      expect(FocusTokens.legacy.hoverScale, 1.12);
      expect(FocusTokens.legacy.hoverScaleFor(false), 1.12);
      expect(FocusTokens.legacy.hoverScaleFor(true), FocusTokens.tvHoverScale);
      expect(FocusTokens.tvHoverScale, 1.045);
      // The TV figure is the platform's budget, not a theme choice.
      const loud = FocusTokens(
        expression: FocusExpression.ring,
        width: 2.5,
        offset: 0,
        scale: 1,
        lift: 0,
        hoverScale: 1.5,
      );
      expect(loud.hoverScaleFor(false), 1.5);
      expect(loud.hoverScaleFor(true), FocusTokens.tvHoverScale);
    });

    test('every shipped theme takes the default, so the app agrees with itself',
        () {
      for (final core in DetailThemes.all) {
        expect(AppTheme.fromDetail(core).focus.hoverScale, 1.12,
            reason: core.id);
      }
    });
  });

  group('the shared TV focus tempo', () {
    test('is the theme\'s fast — non-zero — and every TV grow runs on it', () {
      expect(tvFocus.tvFocus, MotionTokens.legacy.fast);
      expect(tvFocus.tvFocus, const Duration(milliseconds: 120));
      expect(tvFocus.tvFocus, isNot(Duration.zero));
      expect(HoverGrow.durationFor(tvFocus, true), tvFocus.tvFocus);
      // Off TV the grow keeps its own, longer beat.
      expect(HoverGrow.durationFor(tvFocus, false), MotionTokens.legacy.base);
      expect(HoverGrow.durationFor(tvFocus, false), isNot(tvFocus.tvFocus));
    });

    test('a theme tempo reaches it, and reduced motion collapses it', () {
      final sepia = AppTheme.fromDetail(DetailThemes.byId('sepia')).motion;
      expect(
        AppMotion(sepia, reduced: false).tvFocus,
        const Duration(milliseconds: 138), // 120 × 1.15
      );
      expect(const AppMotion(MotionTokens.legacy, reduced: true).tvFocus,
          Duration.zero);
      expect(
        const AppMotion(MotionTokens.legacy, reduced: true)
            .focusTempo(true, const Duration(milliseconds: 140)),
        Duration.zero,
      );
    });

    test('focusTempo routes the TV branch through it and scales the rest', () {
      const off = Duration(milliseconds: 140);
      expect(tvFocus.focusTempo(true, off), tvFocus.tvFocus);
      expect(tvFocus.focusTempo(false, off), off);
      final sepia = AppMotion(
        AppTheme.fromDetail(DetailThemes.byId('sepia')).motion,
        reduced: false,
      );
      expect(sepia.focusTempo(false, off), const Duration(milliseconds: 161));
    });
  });

  group('CatalogItemTile, classic chrome', () {
    testWidgets('rests at 1 and grows by the shared figure under a pointer', (
      tester,
    ) async {
      await tester.pumpWidget(host(tile(tv: false)));
      await tester.pump();
      expect(scaleUnder(tester, CatalogItemTile).scale, 1.0);

      await hover(tester, find.byType(CatalogItemTile));
      final grown = scaleUnder(tester, CatalogItemTile);
      expect(grown.scale, FocusTokens.legacy.hoverScaleFor(false));
      expect(grown.scale, 1.12);
      // The theme's tempo and curve, not a literal of the tile's own.
      expect(grown.duration, MotionTokens.legacy.base);
      expect(grown.duration, const Duration(milliseconds: 220));
      expect(grown.curve, MotionTokens.legacy.standard);
    });

    testWidgets('a keyboard cursor grows it by the same figure', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(host(tile(tv: false, node: node)));
      await tester.pump();
      node.requestFocus();
      // Focus is applied in a microtask after the frame; the tile's setState
      // therefore needs a second frame to paint the grow.
      await tester.pump();
      await tester.pump();
      expect(scaleUnder(tester, CatalogItemTile).scale, 1.12);
    });

    testWidgets('a TV keeps its calmer pop, on the shared focus beat both '
        'ways', (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(host(tile(tv: true, node: node)));
      await tester.pump();
      final rest = scaleUnder(tester, CatalogItemTile);
      expect(rest.scale, 1.0);
      node.requestFocus();
      // Focus is applied in a microtask after the frame; the tile's setState
      // therefore needs a second frame to paint the grow.
      await tester.pump();
      await tester.pump();
      final grown = scaleUnder(tester, CatalogItemTile);
      expect(grown.scale, FocusTokens.tvHoverScale);
      expect(grown.scale, 1.045);
      // Not a snap: the TV tempo, and the same tempo the cursor arrived on.
      expect(grown.duration, tvFocus.tvFocus);
      expect(grown.duration, const Duration(milliseconds: 120));
      expect(grown.curve, MotionTokens.legacy.standard);

      // Focus OUT runs on exactly the beat focus IN did — the pair is what
      // reads as one cursor moving instead of the old tile flashing off.
      node.unfocus();
      await tester.pump();
      await tester.pump();
      final shrunk = scaleUnder(tester, CatalogItemTile);
      expect(shrunk.scale, 1.0);
      expect(shrunk.duration, grown.duration);
      expect(rest.duration, grown.duration, reason: 'the tempo never changes');
    });

    testWidgets('a TV under reduced motion keeps the pop and snaps', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        host(tile(tv: true, node: node), reduceMotion: true),
      );
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await tester.pump();
      final grown = scaleUnder(tester, CatalogItemTile);
      expect(grown.scale, 1.045, reason: 'the cursor must still be visible');
      expect(grown.duration, Duration.zero);
    });

    testWidgets('reduced motion keeps the grow and drops the tween', (
      tester,
    ) async {
      await tester.pumpWidget(host(tile(tv: false), reduceMotion: true));
      await tester.pump();
      await hover(tester, find.byType(CatalogItemTile));
      final grown = scaleUnder(tester, CatalogItemTile);
      expect(grown.scale, 1.12, reason: 'the cursor must still be visible');
      expect(grown.duration, Duration.zero);
    });

    testWidgets('a theme tempo reaches the grow', (tester) async {
      // Sepia carries itself 15% slower; the grow follows.
      final sepia = AppTheme.fromDetail(DetailThemes.byId('sepia'));
      expect(sepia.motion.scale, 1.15);
      await tester.pumpWidget(host(tile(tv: false), theme: sepia));
      await tester.pump();
      await hover(tester, find.byType(CatalogItemTile));
      expect(
        scaleUnder(tester, CatalogItemTile).duration,
        const Duration(milliseconds: 253), // 220 × 1.15
      );
    });
  });

  group('the other tile sites read the same value', () {
    Widget rise({required bool active, required bool tv}) => CardFocusRise(
      active: active,
      isTelevision: tv,
      children: const [SizedBox.expand()],
    );

    testWidgets('CardFocusRise, legacy, off TV', (tester) async {
      await tester.pumpWidget(host(rise(active: true, tv: false)));
      final grown = scaleUnder(tester, CardFocusRise);
      expect(grown.scale, 1.12);
      expect(grown.duration, MotionTokens.legacy.base);
      expect(grown.curve, MotionTokens.legacy.standard);

      await tester.pumpWidget(host(rise(active: false, tv: false)));
      expect(scaleUnder(tester, CardFocusRise).scale, 1.0);
    });

    testWidgets('CardFocusRise on TV: 1.045 on the shared TV focus beat', (
      tester,
    ) async {
      // The board rise was the first TV control to animate, and its shipped
      // 120ms IS legacy's `fast` — the figure `tvFocus` now hands to every
      // other TV cursor, so the rise itself is unchanged.
      await tester.pumpWidget(host(rise(active: true, tv: true)));
      final grown = scaleUnder(tester, CardFocusRise);
      expect(grown.scale, FocusTokens.tvHoverScale);
      expect(grown.duration, tvFocus.tvFocus);
      expect(grown.duration, MotionTokens.legacy.fast);
      expect(grown.duration, const Duration(milliseconds: 120));
      await tester.pumpWidget(host(rise(active: false, tv: true)));
      final shrunk = scaleUnder(tester, CardFocusRise);
      expect(shrunk.scale, 1.0);
      expect(shrunk.duration, grown.duration, reason: 'out matches in');
    });

    testWidgets('CardFocusRise under reduced motion', (tester) async {
      await tester.pumpWidget(
        host(rise(active: true, tv: false), reduceMotion: true),
      );
      expect(scaleUnder(tester, CardFocusRise).duration, Duration.zero);
    });

    Widget rec({required bool tv}) => CatalogDetailRecCard(
      item: item,
      width: 120,
      posterHeight: 180,
      tv: tv,
      onTap: () {},
    );

    testWidgets('the recommendation card, under a pointer', (tester) async {
      await tester.pumpWidget(host(rec(tv: false)));
      await tester.pump();
      expect(scaleUnder(tester, CatalogDetailRecCard).scale, 1.0);
      await hover(tester, find.byType(CatalogDetailRecCard));
      final grown = scaleUnder(tester, CatalogDetailRecCard);
      expect(grown.scale, 1.12);
      expect(grown.duration, MotionTokens.legacy.base);
    });

    testWidgets('the recommendation card on TV: the calm pop on the shared '
        'focus beat, border and caption in step', (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        host(Focus(focusNode: node, child: rec(tv: true))),
      );
      await tester.pump();
      // The card owns its own Focus; reach it the way the detail pins do.
      Focus.of(tester.element(find.text('Tile').last)).requestFocus();
      await tester.pump();
      await tester.pump();
      final grown = scaleUnder(tester, CatalogDetailRecCard);
      expect(grown.scale, FocusTokens.tvHoverScale);
      expect(grown.duration, tvFocus.tvFocus);
      // The border used to be a plain Container that snapped while the grow
      // tweened; now it rides the same beat as the grow and the caption.
      final border = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(CatalogDetailRecCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(border.duration, grown.duration);
      final caption = tester.widget<AnimatedDefaultTextStyle>(
        find.descendant(
          of: find.byType(CatalogDetailRecCard),
          matching: find.byType(AnimatedDefaultTextStyle),
        ),
      );
      expect(caption.duration, grown.duration);
    });
  });
  group('under a premium look, the theme cursor grows the tile too', () {
    /// A theme whose only interesting property is its focus expression, built
    /// through `ThemeSpec` so it travels the same derivation the shipped looks
    /// do — `scale` 1.06 for the scale cursor, 1.02 + an 8px rise for lift.
    AppTheme themeWith(FocusExpression e) => ThemeSpec(
      id: 'probe',
      label: 'Probe',
      subtitle: 'test fixture',
      ground: const Color(0xFF101010),
      sunken: const Color(0xFF0A0A0A),
      raised: const Color(0xFF1A1A1A),
      ink: const Color(0xFFFFFFFF),
      accent: const Color(0xFFFFFFFF),
      separation: SeparationModel.fill,
      scrim: ScrimStyle.bottomGradient,
      frame: ArtFrame.bleed,
      focusExpression: e,
      motion: MotionCharacter.settle,
      radius: 7,
    ).build();

    /// The board chrome: `CatalogItemTile` -> `CardFocusRise` -> the theme's
    /// `FocusExpressionBox`. The same path the home board's cells and the
    /// favourites strip take.
    Widget boardTile({required bool tv, FocusNode? node}) => CatalogItemTile(
      item: item,
      isTelevision: tv,
      focusNode: node,
      hasBoundSource: false,
      onOpen: () {},
      boardChrome: true,
    );

    List<AnimatedScale> scalesUnder(WidgetTester tester, Type of) => tester
        .widgetList<AnimatedScale>(
          find.descendant(
            of: find.byType(of),
            matching: find.byType(AnimatedScale),
          ),
        )
        .toList();

    Iterable<AnimatedContainer> cursorBoxes(WidgetTester tester) =>
        tester.widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(FocusExpressionBox),
            matching: find.byType(AnimatedContainer),
          ),
        );

    /// The ring: a foreground border with a visible colour.
    bool ringLit(WidgetTester tester) => cursorBoxes(tester).any((c) {
      final d = c.foregroundDecoration;
      final border = d is BoxDecoration ? d.border : null;
      return border is Border && border.top.color.a > 0;
    });

    /// The underline: a bar of the cursor's width, filled.
    bool barLit(WidgetTester tester, AppTheme theme) =>
        cursorBoxes(tester).any((c) {
          final d = c.decoration;
          final fill = d is BoxDecoration ? d.color : null;
          return c.constraints?.maxHeight == theme.focus.widthFor(false) &&
              fill != null &&
              fill.a > 0;
        });

    /// The lift: a translation by the theme's rise.
    bool lifted(WidgetTester tester, AppTheme theme) =>
        cursorBoxes(tester).any(
          (c) => c.transform?.getTranslation().y == -theme.focus.lift,
        );

    for (final e in [
      FocusExpression.ring,
      FocusExpression.underline,
      FocusExpression.invert,
      FocusExpression.flood,
      FocusExpression.lift,
    ]) {
      testWidgets(
        '${e.name}: a pointer grows the board card 1.12 and the cursor still '
        'draws',
        (tester) async {
          final theme = themeWith(e);
          await tester.pumpWidget(host(boardTile(tv: false), theme: theme));
          await tester.pump();

          // Rest state: one scale transform, at the identity — the legacy
          // HoverGrow is disabled off legacy, so the tile is not scaled twice.
          expect(
            find.descendant(
              of: find.byType(CardFocusRise),
              matching: find.byType(FocusExpressionBox),
            ),
            findsOneWidget,
          );
          final rest = scalesUnder(tester, CardFocusRise);
          expect(rest, hasLength(1), reason: 'exactly one scale transform');
          expect(rest.single.scale, 1.0);

          await hover(tester, find.byType(CatalogItemTile));
          final grown = scalesUnder(tester, CardFocusRise);
          expect(grown, hasLength(1), reason: 'exactly one scale transform');
          expect(grown.single.scale, theme.focus.hoverScaleFor(false));
          expect(grown.single.scale, 1.12);
          // The grow's tempo, from the theme: the same figure the classic
          // grids and the recommendation row run on.
          expect(grown.single.duration, theme.motion.base);
          expect(grown.single.curve, theme.motion.standard);

          // And the expression is still drawn ON the grown tile.
          switch (e) {
            case FocusExpression.ring:
            // Invert and flood need `inverted` to replace the surface; a
            // poster has none to offer, so they degrade to the ring — which
            // must still be there.
            case FocusExpression.invert:
            case FocusExpression.flood:
              expect(ringLit(tester), isTrue, reason: 'the ring still draws');
            case FocusExpression.underline:
              expect(barLit(tester, theme), isTrue, reason: 'the bar draws');
            case FocusExpression.lift:
              expect(lifted(tester, theme), isTrue, reason: 'the rise stays');
              expect(theme.focus.scale, 1.02, reason: 'the cursor scale…');
              expect(grown.single.scale, isNot(1.02),
                  reason: '…yields to the tile figure, not stacked on it');
            case FocusExpression.scale:
            case FocusExpression.parallax:
              fail('not a non-scaling expression');
          }
        },
      );
    }

    testWidgets('scale: the tile figure replaces the 1.06 cursor scale — one '
        'transform, not two', (tester) async {
      final theme = themeWith(FocusExpression.scale);
      expect(theme.focus.scale, 1.06);
      await tester.pumpWidget(host(boardTile(tv: false), theme: theme));
      await tester.pump();
      expect(scalesUnder(tester, CardFocusRise), hasLength(1));

      await hover(tester, find.byType(CatalogItemTile));
      final grown = scalesUnder(tester, CardFocusRise);
      expect(grown, hasLength(1), reason: 'no double scaling');
      // A poster tile has its own gap to grow into, so it takes the shared
      // tile figure; the small cursor scale stays for settings rows and pills.
      expect(grown.single.scale, 1.12);
    });

    testWidgets('parallax: ParallaxFocus owns the lift; no HoverGrow at all', (
      tester,
    ) async {
      final theme = themeWith(FocusExpression.parallax);
      await tester.pumpWidget(host(boardTile(tv: false), theme: theme));
      await tester.pump();
      await hover(tester, find.byType(CatalogItemTile));
      expect(scalesUnder(tester, CardFocusRise), isEmpty,
          reason: 'the spring lift is the only scale on the card');
      expect(
        find.descendant(
          of: find.byType(CardFocusRise),
          matching: find.byType(ParallaxFocus),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a keyboard cursor takes the same path as the pointer', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        host(
          boardTile(tv: false, node: node),
          theme: themeWith(FocusExpression.ring),
        ),
      );
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await tester.pump();
      final grown = scalesUnder(tester, CardFocusRise);
      expect(grown, hasLength(1));
      expect(grown.single.scale, 1.12);
      expect(ringLit(tester), isTrue);
    });

    testWidgets('reduced motion keeps the grow and drops the tween', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          boardTile(tv: false),
          theme: themeWith(FocusExpression.ring),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      await hover(tester, find.byType(CatalogItemTile));
      final grown = scalesUnder(tester, CardFocusRise).single;
      expect(grown.scale, 1.12);
      expect(grown.duration, Duration.zero);
    });

    testWidgets('a TV keeps the calm 1.045 on the shared focus beat, like the '
        'rest of the cursor', (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      final theme = themeWith(FocusExpression.ring);
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        host(boardTile(tv: true, node: node), theme: theme),
      );
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await tester.pump();
      final grown = scalesUnder(tester, CardFocusRise).single;
      expect(grown.scale, FocusTokens.tvHoverScale);
      expect(grown.scale, 1.045);
      // `settle` is the probe theme's character: its `fast` is 140ms, and
      // the TV beat follows the theme rather than a literal.
      final expected = AppMotion(theme.motion, reduced: false).tvFocus;
      expect(expected, const Duration(milliseconds: 140));
      expect(grown.duration, expected);
      // The ring beside the grow runs on the very same beat — one cursor.
      expect(
        cursorBoxes(tester).map((c) => c.duration),
        everyElement(expected),
      );
      // …and so does the ring fading OUT when focus leaves.
      node.unfocus();
      await tester.pump();
      await tester.pump();
      expect(scalesUnder(tester, CardFocusRise).single.scale, 1.0);
      expect(scalesUnder(tester, CardFocusRise).single.duration, expected);
      expect(
        cursorBoxes(tester).map((c) => c.duration),
        everyElement(expected),
      );
      expect(ringLit(tester), isFalse);
    });

    testWidgets('the cursor on anything that is NOT a tile is unchanged', (
      tester,
    ) async {
      // A settings row or a pill: `grow` is off by default, so `scale` keeps
      // its small 1.06 and `ring` adds no transform at all.
      await tester.pumpWidget(
        host(
          const FocusExpressionBox(
            focused: true,
            radius: 8,
            child: SizedBox.expand(),
          ),
          theme: themeWith(FocusExpression.scale),
        ),
      );
      final small = scalesUnder(tester, FocusExpressionBox);
      expect(small, hasLength(1));
      expect(small.single.scale, 1.06);

      await tester.pumpWidget(
        host(
          const FocusExpressionBox(
            focused: true,
            radius: 8,
            child: SizedBox.expand(),
          ),
          theme: themeWith(FocusExpression.ring),
        ),
      );
      expect(scalesUnder(tester, FocusExpressionBox), isEmpty);
    });
  });
}
