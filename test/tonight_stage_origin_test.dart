import 'dart:async';

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

// Production Home supplies every queue, rail and FocusNode. The only injected
// result is catalog HTTP data; no stage/controller or private State is called.
List<FocusNode> _queueNodes(WidgetTester tester) => tester
    .widgetList<Focus>(
      find.descendant(
        of: find.byKey(const ValueKey('tonight-queue')),
        matching: find.byType(Focus),
      ),
    )
    .map((widget) => widget.focusNode)
    .whereType<FocusNode>()
    .where((node) => node.debugLabel?.startsWith('search_cw_') ?? false)
    .toSet()
    .toList();

Future<void> _prepare(WidgetTester tester) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('tonight');
  await HomePrefs.setHomeHeroSource((
    mode: HomeHeroSourceMode.auto,
    ids: const [],
  ));
  await StorageService.setHomeContinueWatchingEnabled(true);
  await StorageService.setHomeCwHoldToQuickPlay(false);
  await PlaybackProgressStore.saveContinueWatchingItem(
    imdbId: 'tonight-first',
    title: 'Tonight first',
    contentType: 'movie',
  );
  await PlaybackProgressStore.saveContinueWatchingItem(
    imdbId: 'tonight-second',
    title: 'Tonight second',
    contentType: 'movie',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home Tonight queue and paged rail retain their borrowed focus', (
    tester,
  ) async {
    await _prepare(tester);
    await installCatalog();
    final release = Completer<http.Response>();
    var pageRequests = 0;
    await http.runWithClient(
      () async {
        try {
          await mountFavourites(tester);
          expect(find.text('Tonight'), findsOneWidget);
          expect(find.byKey(const ValueKey('tonight-queue')), findsOneWidget);
          final queue = _queueNodes(tester);
          expect(queue, hasLength(2));
          final railFirst = catalogNode(tester, 0, 0);
          expect(queue, isNot(contains(railFirst)));
          queue.first.requestFocus();
          await pumpFavourites(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(queue.last));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(railFirst));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(queue.last));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          for (var col = 1; col <= 11; col++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)),
            );
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
          expect(_queueNodes(tester), orderedEquals(queue));
          // Tonight's shared shelf cell does not arm deferred RIGHT: completing
          // the page leaves the current tail focused without a new keypress.
          expect(FocusManager.instance.primaryFocus, same(tail));
          // The first cell has left the lazy viewport. Walk it back into the
          // actual tree before checking the borrowed node's identity.
          for (var col = 10; col >= 0; col--) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)),
            );
          }
          expect(catalogNode(tester, 0, 0), same(railFirst));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(queue.last));
          await tester.pump();
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete(page(12, 12));
          await pumpFavourites(tester);
          await closeFavourites(tester);
        }
      },
      () => MockClient((request) async {
        expect(request.url.host, 'board-origin.invalid');
        if (request.url.path.endsWith('/rail.json')) return page(0, 12);
        if (request.url.path.endsWith('/rail/skip=12.json')) {
          pageRequests++;
          return release.future;
        }
        fail('Unexpected Tonight request: ${request.url}');
      }),
    );
  });

  testWidgets('Home Tonight queue-only hold menu dismisses to the same node', (
    tester,
  ) async {
    await _prepare(tester);
    try {
      await mountFavourites(tester);
      expect(find.text('Tonight'), findsOneWidget);
      final queue = _queueNodes(tester);
      expect(queue, hasLength(2));
      queue.last.requestFocus();
      await pumpFavourites(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await pumpFavourites(tester);
      expect(FocusManager.instance.primaryFocus, same(queue.last));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 650));
      await pumpFavourites(tester);
      expect(find.text('Remove from Continue Watching'), findsWidgets);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Remove from Continue Watching'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFavourites(tester);
      expect(find.text('Remove from Continue Watching'), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(queue.last));
      expect(_queueNodes(tester), orderedEquals(queue));
      expect(tester.takeException(), isNull);
    } finally {
      await closeFavourites(tester);
    }
  });
}
