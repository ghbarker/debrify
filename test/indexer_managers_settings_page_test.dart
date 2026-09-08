import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/screens/settings/indexer_managers_settings_page.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

// Synthetic-only credentials; no real indexer manager resources involved.
List<IndexerManagerConfig> _syntheticConfigs(int count) => [
  for (var i = 0; i < count; i++)
    IndexerManagerConfig(
      id: 'engine-$i',
      name: 'Engine $i',
      type: IndexerManagerType.jackett,
      baseUrl: 'https://synthetic-$i.invalid',
      apiKey: 'synthetic-test-only',
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'synthetic-indexer-focus-test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const IndexerManagersSettingsPage(),
        ),
      ),
    );
    // _loadConfigs awaits StorageService before its setState.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'DPAD focus on a bottom-row control scrolls it into a short viewport',
    (tester) async {
      final configs = _syntheticConfigs(6);
      await StorageService.setIndexerManagerConfigs(configs);

      // Shrink the surface well below the six-row list's natural height so
      // the page must scroll to reveal a bottom row, mirroring a real TV's
      // limited vertical space.
      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpPage(tester);

      final lastId = configs.last.id;
      final deleteFinder = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.focusNode?.debugLabel == 'indexer-delete-$lastId',
      );
      expect(deleteFinder, findsOneWidget);

      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      // Before focusing, the last row's Delete button is below the fold —
      // otherwise this test wouldn't be exercising the scroll-follow fix.
      final beforeRect = tester.getRect(deleteFinder);
      expect(beforeRect.bottom, greaterThan(viewportHeight));

      final node = tester.widget<IconButton>(deleteFinder).focusNode!;
      node.requestFocus();
      await tester.pumpAndSettle();

      final afterRect = tester.getRect(deleteFinder);
      expect(afterRect.top, greaterThanOrEqualTo(0));
      expect(afterRect.bottom, lessThanOrEqualTo(viewportHeight));
    },
  );

  testWidgets(
    'DPAD focus on the switch of the last row also scrolls it into view',
    (tester) async {
      final configs = _syntheticConfigs(6);
      await StorageService.setIndexerManagerConfigs(configs);

      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpPage(tester);

      final lastId = configs.last.id;
      final switchFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Switch &&
            widget.focusNode?.debugLabel == 'indexer-switch-$lastId',
      );
      expect(switchFinder, findsOneWidget);

      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      final node = tester.widget<Switch>(switchFinder).focusNode!;
      node.requestFocus();
      await tester.pumpAndSettle();

      final afterRect = tester.getRect(switchFinder);
      expect(afterRect.top, greaterThanOrEqualTo(0));
      expect(afterRect.bottom, lessThanOrEqualTo(viewportHeight));
    },
  );
}
