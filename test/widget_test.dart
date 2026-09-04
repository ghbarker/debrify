// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/main.dart';

void main() {
  testWidgets('Debrify app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DebrifyApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    // Migrations time-box at 4s; Home splash safety valve is 10s.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 10));
  });
}
