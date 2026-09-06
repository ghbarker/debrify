import 'package:debrify/screens/settings/stream_badges_settings_page.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('corrupt presets offer recovery instead of continuous loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StreamBadgesService.sourcesKey: 'broken',
    });
    StreamBadgesService.instance.resetProfileScope();
    await tester.pumpWidget(
      const MaterialApp(home: StreamBadgesSettingsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Reset presets'), findsOneWidget);
    await tester.tap(find.text('Reset presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Show stream badges'), findsOneWidget);
    expect(await StreamBadgesService.instance.getSources(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
