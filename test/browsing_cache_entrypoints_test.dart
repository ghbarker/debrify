import 'package:debrify/screens/settings/browsing_cache_page.dart';
import 'package:debrify/screens/settings/settings_tv_layout.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/screens/settings_screen.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scenario in [
    (
      name: 'legacy compact',
      theme: 'legacy',
      width: 500.0,
      tv: false,
      apple: false,
    ),
    (
      name: 'legacy wide',
      theme: 'legacy',
      width: 1280.0,
      tv: false,
      apple: false,
    ),
    (
      name: 'Spotlight compact',
      theme: 'spotlight',
      width: 500.0,
      tv: false,
      apple: false,
    ),
    (
      name: 'Spotlight medium',
      theme: 'spotlight',
      width: 900.0,
      tv: false,
      apple: false,
    ),
    (
      name: 'Spotlight wide',
      theme: 'spotlight',
      width: 1280.0,
      tv: false,
      apple: false,
    ),
    (
      name: 'Android TV remote',
      theme: 'spotlight',
      width: 1280.0,
      tv: true,
      apple: false,
    ),
    (
      name: 'Apple TV remote',
      theme: 'spotlight',
      width: 1280.0,
      tv: true,
      apple: true,
    ),
  ]) {
    testWidgets(
      '${scenario.name}: real Settings navigation and search reach cache controls',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        BrowsingCachePreferences.resetForTesting();
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        PlatformUtil.debugSetAndroidTvCached(scenario.tv && !scenario.apple);
        PlatformUtil.debugSetTvOS(scenario.apple);
        addTearDown(() {
          PlatformUtil.debugSetAndroidTvCached(null);
          PlatformUtil.debugSetTvOS(null);
          ProfileRuntime.debugReset();
          BrowsingCachePreferences.resetForTesting();
        });
        PackageInfo.setMockInitialValues(
          appName: 'Debrify',
          packageName: 'test.debrify',
          version: '1.0',
          buildNumber: '1',
          buildSignature: '',
        );
        await tester.binding.setSurfaceSize(Size(scenario.width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => AppThemeScope(
              theme: AppThemes.byId(scenario.theme),
              child: child!,
            ),
            home: Scaffold(
              body: SettingsScreen(
                summaryReadOverrides: {'TV detection': () async => scenario.tv},
              ),
            ),
          ),
        );
        // Native/plugin summaries are outside the fake widget clock. Keep the
        // real Settings entrypoint, but bound the wait for its loading state.
        for (
          var i = 0;
          i < 60 && find.byType(SettingsSkeleton).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(SettingsSkeleton), findsNothing);
        await tester.pumpAndSettle();
        if (scenario.tv) {
          tester
              .widget<SettingsTvLayout>(find.byType(SettingsTvLayout))
              .firstFocusNode!
              .requestFocus();
          await tester.pumpAndSettle();
          for (var i = 0; i < 14; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          final rows = tester
              .widgetList<SettingsTile>(find.byType(SettingsTile))
              .toList();
          final target = rows.singleWhere(
            (row) => row.title == 'Faster browsing',
          );
          // Optional download-location rows differ by device; walk the actual
          // focus route until the real destination is reached, with a hard cap.
          for (var i = 0; i < 5 && !target.focusNode!.hasFocus; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          expect(target.focusNode!.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          if (scenario.theme == 'spotlight') {
            final category = find.text('Data & Backup').first;
            await tester.ensureVisible(category);
            await tester.pumpAndSettle();
            await tester.tap(category);
            await tester.pumpAndSettle();
          }
          final entry = find.text('Faster browsing');
          await tester.ensureVisible(entry);
          await tester.tap(entry);
        }
        await tester.pumpAndSettle();
        expect(find.byType(BrowsingCachePage), findsOneWidget);
        expect(
          tester
              .widgetList<SettingsTile>(find.byType(SettingsTile))
              .map((row) => row.title),
          [
            'Remember title lists',
            'Title storage',
            'Custom artwork cache',
            'Artwork storage',
            'Prepare movie streams',
          ],
        );
        expect(
          tester
              .widget<SettingsTile>(find.byType(SettingsTile).first)
              .focusNode!
              .hasFocus,
          isTrue,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();

        final search = scenario.theme == 'spotlight' && scenario.width < 720
            ? find.byTooltip('Search settings')
            : find.text('Search settings').first;
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.tap(search);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'prefetch');
        await tester.pumpAndSettle();
        final result = find.text('Faster browsing');
        expect(result, findsOneWidget);
        await tester.tap(result);
        await tester.pumpAndSettle();
        expect(find.byType(BrowsingCachePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
