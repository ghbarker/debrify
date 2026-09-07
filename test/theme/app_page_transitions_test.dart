import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_page_transitions.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/utils/platform_util.dart';

import 'golden_harness.dart';

/// Pins the one route-transition decision (`AppPageTransitionsBuilder`): the
/// TV fade is byte-for-byte what shipped, reduced motion collapses to that
/// same fade, iPhone keeps the Cupertino swipe-back slide, everything else is
/// shared axis — and every TargetPlatform is covered so no platform falls
/// through to a Flutter default.
void main() {
  setUpAll(disableRuntimeFonts);

  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  /// Pumps a production-wired MaterialApp, pushes a MaterialPageRoute and
  /// stops a third of the way through the transition so both the incoming
  /// ('detail') and the exiting ('home') pages are mid-animation.
  ///
  /// [platform] goes through `ThemeData.platform` — the field both the
  /// PageTransitionsTheme lookup and the builder itself read — rather than
  /// the global `debugDefaultTargetPlatformOverride`, which the test binding
  /// asserts is unset before tearDown runs.
  Future<ThemeData> pumpAndPush(
    WidgetTester tester, {
    bool reducedMotion = false,
    bool fullscreenDialog = false,
    TargetPlatform? platform,
  }) async {
    final theme = AppThemeAdapter.legacy(
      TextBrightness.bright,
    ).copyWith(platform: platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: reducedMotion
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: true),
                child: child!,
              )
            : null,
        home: const Scaffold(body: Text('home')),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(
        fullscreenDialog: fullscreenDialog,
        builder: (_) => const Scaffold(body: Text('detail')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return theme;
  }

  Finder transitionOf(String page, Type type) =>
      find.ancestor(of: find.text(page), matching: find.byType(type));

  /// The fast fade: a FadeTransition driven by the pinned curve, and nothing
  /// that scales, slides or snapshots.
  void expectFastFade(WidgetTester tester, String page) {
    final fades = tester.widgetList<FadeTransition>(
      transitionOf(page, FadeTransition),
    );
    final pinned = fades.where(
      (f) =>
          f.opacity is CurvedAnimation &&
          identical(
            (f.opacity as CurvedAnimation).curve,
            AppPageTransitionsBuilder.fastFadeCurve,
          ),
    );
    expect(pinned, hasLength(1), reason: 'exactly one fast-fade layer');
    expect(transitionOf(page, SharedAxisTransition), findsNothing);
    expect(transitionOf(page, ScaleTransition), findsNothing);
    expect(transitionOf(page, SlideTransition), findsNothing);
    expect(transitionOf(page, CupertinoPageTransition), findsNothing);
  }

  group('PageTransitionsTheme coverage', () {
    test('every TargetPlatform routes through AppPageTransitionsBuilder', () {
      final builders = AppThemeAdapter.pageTransitions.builders;
      expect(builders.keys.toSet(), TargetPlatform.values.toSet());
      expect(builders.values, everyElement(isA<AppPageTransitionsBuilder>()));
    });

    test('the TV fade window is what shipped', () {
      // 40% of the route animation, ease-out: ~120ms of the standard 300ms.
      final curve = AppPageTransitionsBuilder.fastFadeCurve as Interval;
      expect(curve.begin, 0.0);
      expect(curve.end, 0.4);
      expect(curve.curve, same(Curves.easeOut));
    });

    test('both ThemeData paths share the one theme', () {
      expect(
        AppThemeAdapter.legacy(TextBrightness.bright).pageTransitionsTheme,
        same(AppThemeAdapter.pageTransitions),
      );
    });
  });

  group('television', () {
    testWidgets('Android TV gets the plain fast fade', (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      await pumpAndPush(tester);
      expectFastFade(tester, 'detail');
    });

    testWidgets('a fullscreenDialog on TV is still just the fade', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      await pumpAndPush(tester, fullscreenDialog: true);
      expectFastFade(tester, 'detail');
    });
  });

  group('reduced motion', () {
    testWidgets('collapses to the fast fade — no scale, no slide', (
      tester,
    ) async {
      await pumpAndPush(tester, reducedMotion: true);
      expectFastFade(tester, 'detail');
    });

    testWidgets('wins over the iPhone Cupertino slide', (tester) async {
      await pumpAndPush(
        tester,
        reducedMotion: true,
        platform: TargetPlatform.iOS,
      );
      expectFastFade(tester, 'detail');
    });
  });

  group('shared axis', () {
    testWidgets('a phone push drills in (scaled) through the theme ground', (
      tester,
    ) async {
      final theme = await pumpAndPush(tester);
      final incoming = tester.widget<SharedAxisTransition>(
        transitionOf('detail', SharedAxisTransition),
      );
      expect(incoming.transitionType, SharedAxisTransitionType.scaled);
      expect(incoming.fillColor, theme.scaffoldBackgroundColor);
      expect(transitionOf('detail', CupertinoPageTransition), findsNothing);
    });

    testWidgets('the exiting page animates too (secondaryAnimation)', (
      tester,
    ) async {
      await pumpAndPush(tester);
      // Mid-push the home route is still on stage and wrapped in the same
      // transition, which is what moves it out of the way.
      expect(transitionOf('home', SharedAxisTransition), findsOneWidget);

      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(transitionOf('detail', SharedAxisTransition), findsOneWidget);
      expect(transitionOf('home', SharedAxisTransition), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
    });

    testWidgets('a fullscreenDialog is presented vertically', (tester) async {
      await pumpAndPush(tester, fullscreenDialog: true);
      final incoming = tester.widget<SharedAxisTransition>(
        transitionOf('detail', SharedAxisTransition),
      );
      expect(incoming.transitionType, SharedAxisTransitionType.vertical);
    });

    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.fuchsia,
    ]) {
      testWidgets('$platform uses the shared axis, not a Flutter default', (
        tester,
      ) async {
        await pumpAndPush(tester, platform: platform);
        expect(transitionOf('detail', SharedAxisTransition), findsOneWidget);
        expect(transitionOf('detail', CupertinoPageTransition), findsNothing);
      });
    }
  });

  group('iPhone', () {
    testWidgets('keeps the Cupertino slide so swipe-back survives', (
      tester,
    ) async {
      await pumpAndPush(tester, platform: TargetPlatform.iOS);
      expect(transitionOf('detail', CupertinoPageTransition), findsOneWidget);
      expect(transitionOf('detail', SharedAxisTransition), findsNothing);
    });
  });
}
