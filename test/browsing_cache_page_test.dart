import 'package:debrify/screens/settings/browsing_cache_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BrowsingCachePreferences.resetForTesting();
    PlatformUtil.debugSetAndroidTvCached(true);
  });
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets('remote enables saved lists and chooses a persisted size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: BrowsingCachePage()));
    await tester.pumpAndSettle();
    var rows = tester
        .widgetList<SettingsTile>(find.byType(SettingsTile))
        .toList();
    expect(rows.first.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.rememberTitles, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.titleSizeMb, 50);
    expect(find.text('50 MB'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    BrowsingCachePreferences.resetForTesting();
    await BrowsingCachePreferences.initialize();
    expect(BrowsingCachePreferences.current.titleSizeMb, 50);
  });

  testWidgets('artwork choices and stream toggle update independently', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BrowsingCachePage()));
    await tester.pumpAndSettle();
    final artwork = find.text('Custom artwork cache');
    await tester.ensureVisible(artwork);
    await tester.tap(artwork);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artwork storage'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('2 GB'));
    await tester.tap(find.text('2 GB'));
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.artworkSizeMb, 2048);
    final streams = find.text('Prepare movie streams');
    await tester.ensureVisible(streams);
    await tester.tap(streams);
    await tester.pumpAndSettle();
    expect(BrowsingCachePreferences.current.prefetchMovieStreams, isFalse);
    expect(BrowsingCachePreferences.current.rememberTitles, isFalse);
    expect(BrowsingCachePreferences.current.expandedArtwork, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
