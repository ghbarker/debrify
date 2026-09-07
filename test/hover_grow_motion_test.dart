import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
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
/// and snaps, and reduced motion collapses the tween to nothing.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    testWidgets('a TV keeps its calmer pop and snaps', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(host(tile(tv: true, node: node)));
      await tester.pump();
      node.requestFocus();
      // Focus is applied in a microtask after the frame; the tile's setState
      // therefore needs a second frame to paint the grow.
      await tester.pump();
      await tester.pump();
      final grown = scaleUnder(tester, CatalogItemTile);
      expect(grown.scale, FocusTokens.tvHoverScale);
      expect(grown.scale, 1.045);
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

    testWidgets('CardFocusRise on TV: 1.045 on the theme\'s fast tween', (
      tester,
    ) async {
      // The board rise animates on TV — its trio is cheap enough — and the
      // shipped 120ms IS legacy's `fast`, so the migration is a no-op there.
      await tester.pumpWidget(host(rise(active: true, tv: true)));
      final grown = scaleUnder(tester, CardFocusRise);
      expect(grown.scale, FocusTokens.tvHoverScale);
      expect(grown.duration, MotionTokens.legacy.fast);
      expect(grown.duration, const Duration(milliseconds: 120));
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

    testWidgets('the recommendation card on TV snaps to the calm pop', (
      tester,
    ) async {
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
      expect(grown.duration, Duration.zero);
    });
  });
}
