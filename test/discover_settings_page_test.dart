import 'package:debrify/screens/settings/discover_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/discover_prefs.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    DiscoverPrefs.debugReset();
  });

  tearDown(() {
    DiscoverPrefs.debugReset();
    ProfileRuntime.debugReset();
  });

  Future<SettingsSelectDropdown> pumpPage(
    WidgetTester tester, {
    required bool mdblistAuthenticated,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: DiscoverSettingsPage(
            mdblistAuthLoader: () async => mdblistAuthenticated,
            addonLoader: () async => const [],
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
    return tester.widget<SettingsSelectDropdown>(
      find.byType(SettingsSelectDropdown),
    );
  }

  testWidgets('offers MDBList when the integration is connected', (
    tester,
  ) async {
    final dropdown = await pumpPage(tester, mdblistAuthenticated: true);

    expect(dropdown.options.map((option) => option.value), contains('mdblist'));
  });

  // Show ratings / Show titles moved off this page — merged with Home's
  // "Hide Titles and Ratings" into Settings › Layout › Title & Ratings
  // Visibility (see title_ratings_visibility_page_test.dart).
  testWidgets('poster type-tags toggle is on by default', (tester) async {
    await pumpPage(tester, mdblistAuthenticated: false);

    final typeTags = tester.widget<SettingsToggleTile>(
      find.byKey(const ValueKey('discover-show-type-tags')),
    );
    expect(typeTags.value, isTrue);
  });

  testWidgets('poster type-tags toggle persists its choice', (tester) async {
    await pumpPage(tester, mdblistAuthenticated: false);

    final typeTags = tester.widget<SettingsToggleTile>(
      find.byKey(const ValueKey('discover-show-type-tags')),
    );
    typeTags.onChanged(false);
    await tester.pump();

    DiscoverPrefs.debugReset();
    await DiscoverPrefs.warmUp();
    expect(DiscoverPrefs.showTypeTags, isFalse);
  });

  testWidgets('keeps a restored MDBList default selectable when disconnected', (
    tester,
  ) async {
    await StorageService.setDiscoverDefaultSource('mdblist');

    final dropdown = await pumpPage(tester, mdblistAuthenticated: false);

    expect(dropdown.value, 'mdblist');
    expect(dropdown.options.map((option) => option.value), contains('mdblist'));
  });
}
