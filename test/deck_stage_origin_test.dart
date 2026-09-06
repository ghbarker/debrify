import 'dart:async';
import 'dart:convert';

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

// Actual Home owns the rails, cells, nodes and menu. Fixtures supply only
// persisted inputs and catalog HTTP results; no private host callback is used.
List<FocusNode> _cwNodes(WidgetTester tester) => tester
    .widgetList<Focus>(find.byType(Focus))
    .map((widget) => widget.focusNode)
    .whereType<FocusNode>()
    .where((node) => node.debugLabel?.startsWith('search_cw_') ?? false)
    .toSet()
    .toList();

Future<void> _prepare(WidgetTester tester) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('deck');
  await HomePrefs.setHomeHeroSource((
    mode: HomeHeroSourceMode.auto,
    ids: const [],
  ));
  await StorageService.setHomeContinueWatchingEnabled(true);
  await StorageService.setHomeCwHoldToQuickPlay(false);
  for (var i = 0; i < 2; i++) {
    await PlaybackProgressStore.saveContinueWatchingItem(
      imdbId: 'deck-cw-$i',
      title: 'Deck continue $i',
      contentType: 'movie',
    );
  }
}

http.Response _artPage() => http.Response(jsonEncode({
  'metas': [
    for (var i = 0; i < 4; i++)
      {
        'id': 'board-$i',
        'type': 'movie',
        'name': 'Catalog $i',
        'poster': '',
        'background': 'https://deck-art.invalid/$i.png',
      },
  ],
}), 200, headers: {'content-type': 'application/json'});

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

  testWidgets('Home Deck focus updates peeks and restores the catalog column',
      (tester) async {
    await _prepare(tester);
    await installCatalog();
    final unexpected = <String>[];
    var exhaustedPageRequests = 0;
    const failedImages = {
      'https://deck-art.invalid/0.png',
      'https://deck-art.invalid/1.png',
      'https://deck-art.invalid/2.png',
      'https://deck-art.invalid/3.png',
      'https://images.metahub.space/background/medium/deck-cw-0/img',
      'https://images.metahub.space/background/medium/deck-cw-1/img',
      'https://images.metahub.space/logo/medium/deck-cw-1/img',
    };
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        final cw = _cwNodes(tester);
        expect(cw, hasLength(2));
        cw.first.requestFocus();
        await pumpFavourites(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 0, 0)));
        expect(find.byKey(const ValueKey(
            'deck-peek-1-https://deck-art.invalid/1.png')), findsOneWidget);
        expect(find.byKey(const ValueKey(
            'deck-peek-2-https://deck-art.invalid/2.png')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await pumpFavourites(tester);
        final second = catalogNode(tester, 0, 1);
        expect(FocusManager.instance.primaryFocus, same(second));
        expect(find.byKey(const ValueKey(
            'deck-peek-1-https://deck-art.invalid/2.png')), findsOneWidget);
        expect(find.byKey(const ValueKey(
            'deck-peek-2-https://deck-art.invalid/3.png')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus, same(cw.first));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        expect(catalogNode(tester, 0, 1), same(second));
        expect(FocusManager.instance.primaryFocus, same(second));
        expect(unexpected, isEmpty);
        expect(exhaustedPageRequests, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      // These exact observed artwork requests intentionally fail through the
      // production image error path. Every other unexpected URL still fails.
      if (request.method == 'GET' &&
          failedImages.contains(request.url.toString())) {
        return http.Response('', 404);
      }
      if (request.method == 'GET' && request.url.toString() ==
          'https://board-origin.invalid/catalog/movie/rail/skip=4.json') {
        exhaustedPageRequests++;
        return page(4, 0);
      }
      if (request.url.host == 'board-origin.invalid' &&
          request.url.path.endsWith('/rail.json')) {
        return _artPage();
      }
      unexpected.add(request.url.toString());
      return http.Response('{}', 404);
    }));
  });

  testWidgets('Home Deck CW hold opens one menu and dismisses to its borrowed node',
      (tester) async {
    await _prepare(tester);
    final routes = _Routes();
    try {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [routes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: const SearchScreen(isTelevision: true),
      ));
      await pumpFavourites(tester);
      final nodes = _cwNodes(tester);
      expect(nodes, hasLength(2));
      nodes.first.requestFocus();
      await pumpFavourites(tester);
      routes.pushes.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(routes.pushes, isEmpty);
      // Pinned Flutter 3.44.8 completes the hold strictly after 500ms.
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
      expect(_cwNodes(tester), orderedEquals(nodes));
      expect(routes.pushes, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await closeFavourites(tester);
    }
  });

  testWidgets('Home Deck held catalog append requires a new Right and retains tail identity',
      (tester) async {
    await _prepare(tester);
    await installCatalog();
    final release = Completer<http.Response>();
    final unexpected = <String>[];
    var pageRequests = 0;
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        _cwNodes(tester).first.requestFocus();
        await pumpFavourites(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 0, 0)));
        for (var col = 1; col <= 11; col++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)));
        }
        final tail = catalogNode(tester, 0, 11);
        expect(pageRequests, 1);
        expect(release.isCompleted, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(tail));
        expect(pageRequests, 1);
        release.complete(page(12, 12));
        await pumpFavourites(tester);
        expect(catalogNode(tester, 0, 11), same(tail));
        expect(FocusManager.instance.primaryFocus, same(tail));
        // The actual shared shelf does not arm automatic Right on completion.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 0, 12)));
        expect(pageRequests, 1);
        expect(unexpected, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete(page(12, 12));
        await pumpFavourites(tester);
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      if (request.url.host == 'board-origin.invalid') {
        if (request.url.path.endsWith('/rail.json')) return page(0, 12);
        if (request.url.path.endsWith('/rail/skip=12.json')) {
          pageRequests++;
          return release.future;
        }
      }
      unexpected.add(request.url.toString());
      return http.Response('{}', 404);
    }));
  });
}
