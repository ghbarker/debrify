import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;

// Transport data only. All rail assembly, paging, nodes and key handling run
// through the mounted production Home; no board/controller is constructed here.
http.Response page(int first, int count) => http.Response(
  jsonEncode({
    'metas': [
      for (var i = first; i < first + count; i++)
        {'id': 'board-$i', 'type': 'movie', 'name': 'Catalog $i', 'poster': ''},
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

FocusNode catalogNode(WidgetTester tester, int row, int col) => tester
    .widgetList<Focus>(find.byType(Focus))
    .map((widget) => widget.focusNode)
    .whereType<FocusNode>()
    .singleWhere((node) => node.debugLabel == 'search_r${row}_c$col');

Future<void> installCatalog({int rows = 1}) async {
  final addon = StremioAddon(
    id: 'board.origin',
    name: 'Board origin',
    manifestUrl: 'https://board-origin.invalid/manifest.json',
    baseUrl: 'https://board-origin.invalid',
    resources: ['catalog'],
    types: ['movie'],
    catalogs: [
      for (var row = 0; row < rows; row++)
        StremioAddonCatalog(
          id: row == 0 ? 'rail' : 'rail$row',
          type: 'movie',
          name: 'Origin rail',
          extraSupported: ['skip'],
        ),
    ],
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('stremio_addons_v1', jsonEncode([addon.toJson()]));
  StremioService.instance.invalidateCache();
  addTearDown(StremioService.instance.invalidateCache);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Home public Right holds one page and keeps existing node identity',
    (tester) async {
      await prepareFavourites(tester);
      await installCatalog();
      final release = Completer<http.Response>();
      final requests = <String>[];
      await http.runWithClient(
        () async {
          try {
            await mountFavourites(tester);
            final first = catalogNode(tester, 0, 0);
            first.requestFocus();
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
            expect(
              requests.where((url) => url.contains('skip=12')),
              hasLength(1),
            );
            expect(release.isCompleted, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus, same(tail));
            expect(
              requests.where((url) => url.contains('skip=12')),
              hasLength(1),
            );

            release.complete(page(12, 12));
            await pumpFavourites(tester);
            expect(catalogNode(tester, 0, 11), same(tail));
            expect(FocusManager.instance.primaryFocus, same(tail));
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, 12)),
            );
            expect(find.text('Catalog 12'), findsWidgets);
            expect(tester.takeException(), isNull);
          } finally {
            if (!release.isCompleted) release.complete(page(12, 12));
            await pumpFavourites(tester);
            await closeFavourites(tester);
          }
        },
        () => MockClient((request) async {
          requests.add(request.url.toString());
          expect(request.url.host, 'board-origin.invalid');
          if (request.url.path.endsWith('/rail.json')) return page(0, 12);
          if (request.url.path.endsWith('/skip=12.json')) return release.future;
          fail('Unexpected catalog request: ${request.url}');
        }),
      );
    },
  );

  testWidgets('Home saved mixed rail order drives Down and clamps column', (
    tester,
  ) async {
    await prepareFavourites(tester);
    await installCatalog();
    await StorageService.setMyWatchlistItem(
      const StremioMeta(
        id: 'saved',
        type: 'movie',
        name: 'Saved card',
        poster: '',
      ),
      true,
    );
    await StorageService.setHomeRowOrder([
      'board.origin:movie:rail',
      'watchlist:movies',
    ]);
    await http.runWithClient(
      () async {
        try {
          await mountFavourites(tester);
          final catalog = catalogNode(tester, 0, 2);
          final saved = tester
              .widgetList<ArtPoster>(find.byType(ArtPoster))
              .singleWhere((widget) => widget.title == 'Saved card')
              .focusNode;
          catalog.requestFocus();
          await pumpFavourites(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(saved));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await pumpFavourites(tester);
          expect(
            FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 0, 0)),
          );
          expect(catalogNode(tester, 0, 2), same(catalog));
          expect(tester.takeException(), isNull);
        } finally {
          await closeFavourites(tester);
        }
      },
      () => MockClient((request) async {
        expect(request.url.host, 'board-origin.invalid');
        return page(0, 12);
      }),
    );
  });

  testWidgets('Home Down waits for the next real board batch then focuses it', (
    tester,
  ) async {
    await prepareFavourites(tester);
    await installCatalog(rows: 9);
    final release = Completer<http.Response>();
    var finalRowRequests = 0;
    await http.runWithClient(
      () async {
        try {
          await mountFavourites(tester);
          catalogNode(tester, 0, 0).requestFocus();
          await pumpFavourites(tester);
          for (var row = 1; row <= 7; row++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(catalogNode(tester, row, 0)),
            );
          }
          final origin = catalogNode(tester, 7, 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(finalRowRequests, 1);
          expect(release.isCompleted, isFalse);
          expect(FocusManager.instance.primaryFocus, same(origin));
          release.complete(page(800, 12));
          await pumpFavourites(tester);
          expect(
            FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 8, 0)),
          );
          expect(catalogNode(tester, 7, 0), same(origin));
          expect(finalRowRequests, 1);
          await tester.pump();
          expect(
            FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 8, 0)),
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete(page(800, 12));
          await pumpFavourites(tester);
          await closeFavourites(tester);
        }
      },
      () => MockClient((request) async {
        expect(request.url.host, 'board-origin.invalid');
        final endpoint = request.url.pathSegments.last;
        if (endpoint == 'rail8.json') {
          finalRowRequests++;
          return release.future;
        }
        final match = RegExp(r'^rail([1-7]?)\.json$').firstMatch(endpoint);
        if (match == null) fail('Unexpected batch request: ${request.url}');
        return page((int.tryParse(match.group(1)!) ?? 0) * 100, 12);
      }),
    );
  });
}
