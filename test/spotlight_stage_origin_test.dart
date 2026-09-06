import 'dart:async';

import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart' show installCatalog, page;

// Actual public Home composition and transport fixtures. The test reads the
// mounted SpotlightBoard's public inputs; it never constructs that board or
// calls its callbacks/State methods. Existing board tests cover its unit DPAD
// grammar; these cases characterize the Home assembly and real paging/menu.
SpotlightBoard _board(WidgetTester tester) =>
    tester.widget<SpotlightBoard>(find.byType(SpotlightBoard));

Future<void> _prepare(WidgetTester tester) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('spotlight');
  await HomePrefs.setHomeHeroSource((
    mode: HomeHeroSourceMode.auto,
    ids: const [],
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Home Spotlight preserves borrowed focus across held row paging',
    (tester) async {
      await _prepare(tester);
      await installCatalog(rows: 2);
      final release = Completer<http.Response>();
      var pageRequests = 0;
      await http.runWithClient(
        () async {
          try {
            await mountFavourites(tester);
            expect(find.byType(SpotlightBoard), findsOneWidget);
            final initial = _board(tester);
            expect(initial.sections, hasLength(2));
            expect(initial.dpad, isTrue);
            final hero = initial.heroNode;
            final first = initial.sections[0].nodes[0];
            final firstId = initial.sections[0].id;
            hero.requestFocus();
            await pumpFavourites(tester);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await pumpFavourites(tester);
            expect(FocusManager.instance.primaryFocus, same(first));
            for (var col = 1; col <= 11; col++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
              await pumpFavourites(tester);
              expect(
                FocusManager.instance.primaryFocus,
                same(_board(tester).sections[0].nodes[col]),
              );
            }
            final tail = _board(tester).sections[0].nodes[11];
            expect(pageRequests, 1);
            expect(release.isCompleted, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus, same(tail));
            expect(pageRequests, 1);
            release.complete(page(12, 12));
            await pumpFavourites(tester);
            expect(_board(tester).sections[0].id, firstId);
            expect(_board(tester).sections[0].nodes[0], same(first));
            expect(_board(tester).sections[0].nodes[11], same(tail));
            expect(_board(tester).heroNode, same(hero));
            expect(FocusManager.instance.primaryFocus, same(tail));
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(_board(tester).sections[0].nodes[12]),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await pumpFavourites(tester);
            expect(
              _board(tester).sections[1].nodes,
              contains(FocusManager.instance.primaryFocus),
            );
            expect(_board(tester).sections[0].nodes[0], same(first));
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
          if (request.url.path.endsWith('/rail/skip=12.json')) {
            pageRequests++;
            return release.future;
          }
          if (request.url.path.endsWith('/rail.json')) return page(0, 12);
          if (request.url.path.endsWith('/rail1.json')) return page(100, 12);
          fail('Unexpected catalog request: ${request.url}');
        }),
      );
    },
  );

  testWidgets(
    'Home Spotlight CW hold opens the real options and returns focus',
    (tester) async {
      await _prepare(tester);
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.setHomeCwHoldToQuickPlay(false);
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'tt0000001',
        title: 'Spotlight saved movie',
        contentType: 'movie',
      );
      try {
        await mountFavourites(tester);
        expect(find.byType(SpotlightBoard), findsOneWidget);
        final row = _board(tester).sections.singleWhere(
          (shelf) =>
              shelf.items.any((item) => item.title == 'Spotlight saved movie'),
        );
        final node = row.nodes.single;
        node.requestFocus();
        await pumpFavourites(tester);
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
        expect(FocusManager.instance.primaryFocus, same(node));
        expect(
          _board(
            tester,
          ).sections.singleWhere((s) => s.id == row.id).nodes.single,
          same(node),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await closeFavourites(tester);
      }
    },
  );
}
