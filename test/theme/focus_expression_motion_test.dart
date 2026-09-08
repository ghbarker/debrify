import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_art.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_light.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/theme_spec.dart';
import 'package:debrify/theme/widgets/focus_expression.dart';
import 'package:debrify/utils/platform_util.dart';

/// The cursor's TEMPO, pinned at its one source of truth.
///
/// `FocusExpressionBox` used to snap on TV (`Duration.zero`) — the policy the
/// two TV focus widgets it replaced both carried. The snap is what a viewer
/// reads as a flash: the old control drops its ring in the very frame the new
/// one gains it. Now every TV cursor runs on `AppMotion.tvFocus`, the same
/// non-zero beat for focus OUT and focus IN, and reduced motion is the only
/// thing that collapses it. Off TV nothing moved: the cursor keeps `fast`.
void main() {
  /// A theme whose only interesting property is its focus expression, built
  /// through `ThemeSpec` so it travels the derivation the shipped looks do.
  /// `standard` character: `fast` is the legacy 120ms.
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
    motion: MotionCharacter.standard,
    radius: 7,
  ).build();

  const childKey = ValueKey('cursor-child');

  Widget host(
    AppTheme theme, {
    required bool focused,
    bool reduceMotion = false,
    bool grow = false,
    Widget Function(BuildContext, Color)? inverted,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: AppThemeScope(
        theme: theme,
        child: Material(
          child: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: FocusExpressionBox(
                focused: focused,
                radius: 8,
                grow: grow,
                inverted: inverted,
                child: const SizedBox.expand(key: childKey),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Every implicit tween the box mounts, as its duration — the ring, the
  /// underline bar, the lift, the cursor scale, the tile grow.
  List<Duration> tempos(WidgetTester tester) => [
    ...tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(FocusExpressionBox),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((w) => w.duration),
    ...tester
        .widgetList<AnimatedScale>(
          find.descendant(
            of: find.byType(FocusExpressionBox),
            matching: find.byType(AnimatedScale),
          ),
        )
        .map((w) => w.duration),
    ...tester
        .widgetList<AnimatedOpacity>(
          find.descendant(
            of: find.byType(FocusExpressionBox),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .map((w) => w.duration),
  ];

  const animated = [
    FocusExpression.ring,
    FocusExpression.underline,
    FocusExpression.lift,
    FocusExpression.scale,
  ];

  group('on TV', () {
    setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
    tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

    for (final e in animated) {
      testWidgets('${e.name}: focus in and focus out share the TV beat', (
        tester,
      ) async {
        final theme = themeWith(e);
        final beat = AppMotion(theme.motion, reduced: false).tvFocus;
        expect(beat, const Duration(milliseconds: 120));
        expect(beat, isNot(Duration.zero), reason: 'not a snap');

        await tester.pumpWidget(host(theme, focused: true));
        final gain = tempos(tester);
        expect(gain, isNotEmpty, reason: 'the cursor draws something');
        expect(gain, everyElement(beat));

        await tester.pumpWidget(host(theme, focused: false));
        final loss = tempos(tester);
        expect(loss, hasLength(gain.length), reason: 'same tree, both ways');
        expect(loss, everyElement(beat), reason: 'out matches in');
      });
    }

    testWidgets('the tile grow rides the same beat as the cursor', (
      tester,
    ) async {
      final theme = themeWith(FocusExpression.ring);
      await tester.pumpWidget(host(theme, focused: true, grow: true));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, FocusTokens.tvHoverScale);
      expect(scale.duration, AppMotion(theme.motion, reduced: false).tvFocus);
      expect(tempos(tester), everyElement(scale.duration));
    });

    testWidgets('reduced motion collapses the beat to zero, both ways', (
      tester,
    ) async {
      for (final e in animated) {
        final theme = themeWith(e);
        await tester.pumpWidget(host(theme, focused: true, reduceMotion: true));
        expect(tempos(tester), everyElement(Duration.zero), reason: e.name);
        await tester.pumpWidget(
          host(theme, focused: false, reduceMotion: true),
        );
        expect(tempos(tester), everyElement(Duration.zero), reason: e.name);
      }
    });

    testWidgets('the theme\'s tempo reaches the beat', (tester) async {
      // `settle` carries a 140ms fast; the cursor follows the theme.
      final theme = ThemeSpec(
        id: 'settle',
        label: 'Settle',
        subtitle: 'test fixture',
        ground: const Color(0xFF101010),
        sunken: const Color(0xFF0A0A0A),
        raised: const Color(0xFF1A1A1A),
        ink: const Color(0xFFFFFFFF),
        accent: const Color(0xFFFFFFFF),
        separation: SeparationModel.fill,
        scrim: ScrimStyle.bottomGradient,
        frame: ArtFrame.bleed,
        focusExpression: FocusExpression.ring,
        motion: MotionCharacter.settle,
        radius: 7,
      ).build();
      await tester.pumpWidget(host(theme, focused: true));
      expect(tempos(tester), everyElement(const Duration(milliseconds: 140)));
    });

    testWidgets('invert cross-fades over the SAME child — never remounts it', (
      tester,
    ) async {
      final theme = themeWith(FocusExpression.invert);
      Widget inverted(BuildContext _, Color ink) =>
          Center(child: Text('inverted', style: TextStyle(color: ink)));

      await tester.pumpWidget(
        host(theme, focused: false, inverted: inverted),
      );
      final before = tester.element(find.byKey(childKey));
      final rest = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(rest.opacity, 0, reason: 'the inverted face is hidden at rest');
      // Mounted but inert: it may not act, and it may not take the cursor.
      expect(find.text('inverted'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('inverted'),
          matching: find.byType(ExcludeFocus),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('inverted'),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );

      await tester.pumpWidget(host(theme, focused: true, inverted: inverted));
      final after = tester.element(find.byKey(childKey));
      expect(identical(before, after), isTrue,
          reason: 'focus must not swap the child — that IS the flash');
      final lit = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(lit.opacity, 1);
      expect(lit.duration, AppMotion(theme.motion, reduced: false).tvFocus);
    });
  });

  group('off TV, nothing moved', () {
    setUp(() => PlatformUtil.debugSetAndroidTvCached(false));
    tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

    for (final e in animated) {
      testWidgets('${e.name}: the cursor keeps the theme\'s fast', (
        tester,
      ) async {
        final theme = themeWith(e);
        await tester.pumpWidget(host(theme, focused: true));
        expect(tempos(tester), everyElement(MotionTokens.legacy.fast));
        await tester.pumpWidget(host(theme, focused: false));
        expect(tempos(tester), everyElement(MotionTokens.legacy.fast));
      });
    }

    testWidgets('the tile grow keeps its own `base`', (tester) async {
      final theme = themeWith(FocusExpression.ring);
      await tester.pumpWidget(host(theme, focused: true, grow: true));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 1.12);
      expect(scale.duration, MotionTokens.legacy.base);
    });

    testWidgets('the bloom stays mounted, so focus never remounts the child', (
      tester,
    ) async {
      // A lit theme: the spec derives a bloom for the ring off TV.
      final theme = themeWith(FocusExpression.ring);
      if (theme.light.bloomFor(false) <= 0) return;
      await tester.pumpWidget(host(theme, focused: false));
      final before = tester.element(find.byKey(childKey));
      await tester.pumpWidget(host(theme, focused: true));
      expect(identical(before, tester.element(find.byKey(childKey))), isTrue);
    });
  });
}
