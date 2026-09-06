import 'package:debrify/screens/search/continue_watching_row.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

// Real classic Home -> ContinueWatchingRow -> production card. The observer
// measures actual routes; no card copy, private State call or callback override.
class _Routes extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
    super.didPush(route, previousRoute);
  }
}

Future<(_Routes, List<FocusNode>)> _mount(WidgetTester tester) async {
  await prepareFavourites(tester);
  await HomePrefs.setHomeContinueWatchingEnabled(true);
  await HomePrefs.setHomeCwHoldToQuickPlay(false);
  for (var i = 1; i <= 2; i++) {
    await PlaybackProgressStore.saveContinueWatchingItem(
      imdbId: 'tt000000$i',
      title: 'Card origin $i',
      contentType: 'movie',
    );
  }
  final routes = _Routes();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [routes],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(0.8)),
        child: child!,
      ),
      home: const SearchScreen(isTelevision: true),
    ),
  );
  await pumpFavourites(tester);
  final row = tester.widget<ContinueWatchingRow>(
    find.byType(ContinueWatchingRow),
  );
  final nodes = List<FocusNode>.of(row.row.nodes);
  expect(nodes, hasLength(2));
  nodes.first.requestFocus();
  await pumpFavourites(tester);
  expect(FocusManager.instance.primaryFocus, same(nodes.first));
  routes.pushes.clear();
  return (routes, nodes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('classic card short Select opens only on matching release', (
    tester,
  ) async {
    final (routes, _) = await _mount(tester);
    try {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(routes.pushes, isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      // Observe the synchronous actual navigation before rendering detail IO.
      expect(routes.pushes, hasLength(1));
      expect(routes.pushes.single, isA<PageRoute<dynamic>>());
      expect(find.text('Remove from Continue Watching'), findsNothing);
    } finally {
      await closeFavourites(tester);
    }
  });

  testWidgets(
    'classic card completed hold opens one menu and release does not open',
    (tester) async {
      final (routes, nodes) = await _mount(tester);
      try {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        // Establish the first frame. The pinned SDK completes interpolation only
        // strictly after its 500ms duration; this is not a popup deadline.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 499));
        expect(routes.pushes, isEmpty);
        // First fake frame strictly after the duration. Then use the existing
        // bounded fixture drain for the real asynchronous menu preference path.
        await tester.pump(const Duration(milliseconds: 2));
        await pumpFavourites(tester);
        expect(routes.pushes, hasLength(1));
        expect(routes.pushes.single, isA<PopupRoute<dynamic>>());
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.text('Remove from Continue Watching'), findsWidgets);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(routes.pushes, hasLength(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFavourites(tester);
        expect(find.text('Remove from Continue Watching'), findsNothing);
        expect(FocusManager.instance.primaryFocus, same(nodes.first));
        expect(routes.pushes, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await closeFavourites(tester);
      }
    },
  );

  testWidgets('classic card focus away cancels hold and stray release', (
    tester,
  ) async {
    final (routes, nodes) = await _mount(tester);
    try {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(nodes[1]));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(routes.pushes, isEmpty);
      expect(find.text('Remove from Continue Watching'), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(nodes[1]));
      expect(
        tester
            .widget<ContinueWatchingRow>(find.byType(ContinueWatchingRow))
            .row
            .nodes[1],
        same(nodes[1]),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await closeFavourites(tester);
    }
  });

  testWidgets(
    'classic card unmount while held leaves no later route or ticker error',
    (tester) async {
      final (routes, _) = await _mount(tester);
      try {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 650));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(routes.pushes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await closeFavourites(tester);
      }
    },
  );
}
