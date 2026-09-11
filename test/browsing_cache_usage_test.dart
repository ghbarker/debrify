import 'dart:async';

import 'package:debrify/screens/settings/widgets/browsing_cache_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page({
    required Future<int> Function() titleBytes,
    Future<void> Function()? clearTitles,
  }) => MaterialApp(
    home: Scaffold(
      body: BrowsingCacheUsage(
        titleBytes: titleBytes,
        artworkBytes: () async => 2 * 1024 * 1024,
        clearTitles: clearTitles ?? () async {},
        clearArtwork: () async {},
      ),
    ),
  );

  testWidgets('late initial inventory cannot overwrite usage after clear', (
    tester,
  ) async {
    final initial = Completer<int>();
    final cleared = Completer<void>();
    var reads = 0;
    var clears = 0;
    await tester.pumpWidget(
      page(
        titleBytes: () => ++reads == 1 ? initial.future : Future.value(0),
        clearTitles: () {
          clears++;
          return cleared.future;
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Clear cached title lists'));
    await tester.pump();
    await tester.tap(find.text('Clear cached title lists'));
    expect(clears, 1);
    expect(find.text('Clearing…'), findsOneWidget);
    cleared.complete();
    await tester.pumpAndSettle();
    initial.complete(1024 * 1024);
    await tester.pumpAndSettle();
    expect(
      find.text('0 KB on this device. Downloads again when needed.'),
      findsOneWidget,
    );
    expect(
      find.text('2.0 MB on this device. Downloads again when needed.'),
      findsOneWidget,
    );
    expect(find.textContaining('1.0 MB'), findsNothing);
  });

  testWidgets('clear failure remains visible and allows retry', (tester) async {
    var fails = true;
    await tester.pumpWidget(
      page(
        titleBytes: () async => fails ? 1024 : 0,
        clearTitles: () async {
          if (fails) throw StateError('test failure');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear cached title lists'));
    await tester.pumpAndSettle();
    expect(find.text('Could not clear. Please try again.'), findsOneWidget);
    fails = false;
    await tester.tap(find.text('Clear cached title lists'));
    await tester.pumpAndSettle();
    expect(find.text('Could not clear. Please try again.'), findsNothing);
    expect(find.textContaining('0 KB'), findsOneWidget);
  });

  testWidgets('failed inventory and completion after leaving are harmless', (
    tester,
  ) async {
    final clear = Completer<void>();
    await tester.pumpWidget(
      page(
        titleBytes: () async => throw StateError('test failure'),
        clearTitles: () => clear.future,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Storage usage unavailable'), findsOneWidget);
    await tester.tap(find.text('Clear cached title lists'));
    await tester.pumpWidget(const SizedBox.shrink());
    clear.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
