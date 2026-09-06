import 'dart:async';
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

Future<void> _prepare(WidgetTester tester, {bool cw = false}) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('canvas');
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
  if (cw) {
    await HomePrefs.setHomeContinueWatchingEnabled(true);
    await HomePrefs.setHomeCwHoldToQuickPlay(false);
    for (var i = 0; i < 2; i++) {
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'canvas-cw-$i', title: 'Canvas continue $i', contentType: 'movie');
    }
  }
}

Finder _strip() => find.byWidgetPredicate((widget) => widget is ListView &&
    widget.key is ValueKey<String> &&
    (widget.key! as ValueKey<String>).value.startsWith('canvas-rail-'));

List<FocusNode> _cwNodes(WidgetTester tester) => tester
    .widgetList<BoardCell>(find.byType(BoardCell))
    .map((cell) => cell.focusNode).whereType<FocusNode>()
    .where((node) => node.debugLabel?.startsWith('search_cw_') ?? false).toList();

final _cwImages = {
  for (var i = 0; i < 2; i++) ...[
    'https://images.metahub.space/background/medium/canvas-cw-$i/img',
    'https://images.metahub.space/logo/medium/canvas-cw-$i/img',
  ],
};

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

  testWidgets('Home Canvas held append retains tail until a fresh Right',
      (tester) async {
    await _prepare(tester);
    await installCatalog();
    final release = Completer<http.Response>();
    final unexpected = <String>[];
    var pageRequests = 0;
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        catalogNode(tester, 0, 0).requestFocus();
        await pumpFavourites(tester);
        for (var col = 1; col <= 11; col++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)));
        }
        final tail = catalogNode(tester, 0, 11);
        final key = tester.widget<ListView>(_strip()).key;
        expect(pageRequests, 1);
        expect(release.isCompleted, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(tail));
        release.complete(page(12, 12));
        await pumpFavourites(tester);
        expect(catalogNode(tester, 0, 11), same(tail));
        expect(FocusManager.instance.primaryFocus, same(tail));
        expect(tester.widget<ListView>(_strip()).key, key);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 0, 12)));
        expect(pageRequests, 1);
        expect(unexpected, isEmpty);
      } finally {
        if (!release.isCompleted) release.complete(page(12, 12));
        await pumpFavourites(tester);
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      if (request.url.toString() ==
          'https://board-origin.invalid/catalog/movie/rail.json') {
        return page(0, 12);
      }
      if (request.url.toString() ==
          'https://board-origin.invalid/catalog/movie/rail/skip=12.json') {
        pageRequests++;
        return release.future;
      }
      unexpected.add(request.url.toString());
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Home Canvas CW catalog crossfade retains rail keys and column',
      (tester) async {
    await _prepare(tester, cw: true);
    await installCatalog();
    final unexpected = <String>[];
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        final cw = _cwNodes(tester);
        expect(cw, hasLength(2));
        cw.first.requestFocus();
        await pumpFavourites(tester);
        final cwKey = tester.widget<ListView>(_strip()).key;
        final shelfHeight = tester.getSize(_strip()).height;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        // Inspect the actual outgoing and incoming children in a finite frame.
        final during = tester.widgetList<ListView>(_strip()).toList();
        expect(during, hasLength(2));
        expect(during.map((view) => view.key), contains(cwKey));
        final catalogKey = during.singleWhere((view) => view.key != cwKey).key;
        await pumpFavourites(tester);
        expect(_strip(), findsOneWidget);
        expect(tester.widget<ListView>(_strip()).key, catalogKey);
        expect(tester.getSize(_strip()).height, shelfHeight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await pumpFavourites(tester);
        final second = catalogNode(tester, 0, 1);
        expect(FocusManager.instance.primaryFocus, same(second));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus, same(cw.first));
        expect(tester.widget<ListView>(_strip()).key, cwKey);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        expect(catalogNode(tester, 0, 1), same(second));
        expect(FocusManager.instance.primaryFocus, same(second));
        expect(tester.widget<ListView>(_strip()).key, catalogKey);
        expect(unexpected, isEmpty);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      final url = request.url.toString();
      if (_cwImages.contains(url)) return http.Response('', 404);
      if (url == 'https://board-origin.invalid/catalog/movie/rail.json') return page(0, 12);
      if (url == 'https://board-origin.invalid/catalog/movie/rail/skip=12.json') return page(12, 0);
      unexpected.add(url);
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Home Canvas CW hold opens one menu and restores borrowed focus',
      (tester) async {
    await _prepare(tester);
    await HomePrefs.setHomeContinueWatchingEnabled(true);
    await HomePrefs.setHomeCwHoldToQuickPlay(false);
    for (var i = 0; i < 2; i++) {
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'canvas-cw-$i', title: 'Canvas continue $i', contentType: 'movie');
    }
    final routes = _Routes();
    final unexpected = <String>[];
    final expectedImages = {
      for (var i = 0; i < 2; i++) ...[
        'https://images.metahub.space/background/medium/canvas-cw-$i/img',
        'https://images.metahub.space/logo/medium/canvas-cw-$i/img',
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
