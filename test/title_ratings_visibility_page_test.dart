import 'package:debrify/screens/settings/title_ratings_visibility_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/discover_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiscoverPrefs.debugReset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TitleRatingsVisibilityPage()),
    );
    await tester.pump();
  }

  testWidgets('is on by default', (tester) async {
    await pumpPage(tester);

    final toggle = tester.widget<SettingsToggleTile>(
      find.byType(SettingsToggleTile),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('toggling off persists to DiscoverPrefs.titleRatingsVisible', (
    tester,
  ) async {
    await pumpPage(tester);

    final toggle = tester.widget<SettingsToggleTile>(
      find.byType(SettingsToggleTile),
    );
    toggle.onChanged(false);
    await tester.pump();

    final updated = tester.widget<SettingsToggleTile>(
      find.byType(SettingsToggleTile),
    );
    expect(updated.value, isFalse);

    DiscoverPrefs.debugReset();
    await DiscoverPrefs.warmUp();
    expect(DiscoverPrefs.titleRatingsVisible, isFalse);
  });
}
