import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart'
    show installCatalog, page, catalogNode;

Future<void> _prepare(WidgetTester tester) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('promenade');
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
}

Finder _strip() => find.byWidgetPredicate((widget) => widget is ListView &&
    widget.key is ValueKey<String> &&
    (widget.key! as ValueKey<String>).value.startsWith('prom-rail-'));

void _expectCentered(WidgetTester tester, FocusNode node) {
  final cell = find.byWidgetPredicate((widget) =>
      widget is BoardCell && identical(widget.focusNode, node));
  expect(cell, findsOneWidget);
  // Compare actual rendered rectangles, not Promenade's private padding formula.
  expect(tester.getRect(cell).center.dx,
      closeTo(tester.getRect(_strip()).center.dx, 1));
}

class _Routes extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home Promenade centers first and last cells and restores rail focus',
      (tester) async {
    await _prepare(tester);
    await installCatalog(rows: 2);
    final unexpected = <String>[];
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        final first = catalogNode(tester, 0, 0);
        first.requestFocus();
        await pumpFavourites(tester);
        final key = tester.widget<ListView>(_strip()).key;
        expect(FocusManager.instance.primaryFocus, same(first));
        _expectCentered(tester, first);
        for (var col = 1; col <= 3; col++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)));
        }
        final last = catalogNode(tester, 0, 3);
        _expectCentered(tester, last);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus, same(catalogNode(tester, 1, 0)));
        expect(tester.widget<ListView>(_strip()).key, isNot(key));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await pumpFavourites(tester);
        expect(tester.widget<ListView>(_strip()).key, key);
        expect(catalogNode(tester, 0, 3), same(last));
        expect(FocusManager.instance.primaryFocus, same(last));
        _expectCentered(tester, last);
        expect(unexpected, isEmpty);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://board-origin.invalid/catalog/movie/rail.json') {
        return page(0, 4);
      }
      if (url == 'https://board-origin.invalid/catalog/movie/rail1.json') {
        return page(100, 4);
      }
      if (url == 'https://board-origin.invalid/catalog/movie/rail/skip=4.json' ||
          url == 'https://board-origin.invalid/catalog/movie/rail1/skip=4.json') {
        return page(4, 0);
      }
      unexpected.add(url);
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Home Promenade CW hold opens one menu and restores borrowed focus',
      (tester) async {
    await _prepare(tester);
    await StorageService.setHomeContinueWatchingEnabled(true);
    await StorageService.setHomeCwHoldToQuickPlay(false);
    for (var i = 0; i < 2; i++) {
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'prom-cw-$i', title: 'Promenade continue $i', contentType: 'movie');
    }
    final routes = _Routes();
    final unexpected = <String>[];
    final expectedImages = {
      for (var i = 0; i < 2; i++) ...[
        'https://images.metahub.space/background/medium/prom-cw-$i/img',
        'https://images.metahub.space/logo/medium/prom-cw-$i/img',
      ],
    };
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(MaterialApp(
          navigatorObservers: [routes],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.8)),
            child: child!,
          ),
          home: const SearchScreen(isTelevision: true),
        ));
        await pumpFavourites(tester);
        final nodes = tester.widgetList<BoardCell>(find.byType(BoardCell))
            .map((cell) => cell.focusNode)
            .whereType<FocusNode>()
            .where((node) => node.debugLabel?.startsWith('search_cw_') ?? false)
            .toList();
        expect(nodes, hasLength(2));
        nodes.first.requestFocus();
        await pumpFavourites(tester);
        final key = tester.widget<ListView>(_strip()).key;
        routes.pushes.clear();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 499));
        expect(routes.pushes, isEmpty);
        // Pinned SDK hold boundary is strictly greater than 500ms.
        await tester.pump(const Duration(milliseconds: 2));
        await pumpFavourites(tester);
        expect(routes.pushes, hasLength(1));
        expect(routes.pushes.single, isA<PopupRoute<dynamic>>());
        expect(find.text('Remove from Continue Watching'), findsWidgets);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(routes.pushes, hasLength(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFavourites(tester);
        expect(find.text('Remove from Continue Watching'), findsNothing);
        expect(FocusManager.instance.primaryFocus, same(nodes.first));
        expect(tester.widget<ListView>(_strip()).key, key);
        expect(routes.pushes, hasLength(1));
        expect(unexpected, isEmpty);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      if (request.method == 'GET' && expectedImages.contains(request.url.toString())) {
        return http.Response('', 404);
      }
      unexpected.add(request.url.toString());
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
