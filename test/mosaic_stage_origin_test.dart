import 'dart:async';

import 'package:debrify/services/storage/home_prefs.dart';
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

Future<void> _prepare(WidgetTester tester, int rows) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('mosaic');
  await HomePrefs.setHomeHeroSource((
    mode: HomeHeroSourceMode.auto,
    ids: const [],
  ));
  await installCatalog(rows: rows);
}

GridView _grid(WidgetTester tester) => tester
    .widgetList<GridView>(find.byType(GridView))
    .singleWhere(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('mosaic-rail-'),
    );

// This reads the actual rendered delegate; it does not reproduce Mosaic's
// column calculation or construct any stage/controller/private State.
int _columns(WidgetTester tester) =>
    (_grid(tester).gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home Mosaic wraps Right, steps a grid line and exits the last', (
    tester,
  ) async {
    await _prepare(tester, 2);
    await http.runWithClient(
      () async {
        try {
          await mountFavourites(tester);
          final columns = _columns(tester);
          expect(columns, inInclusiveRange(2, 8));
          final gridKey = _grid(tester).key;
          final first = catalogNode(tester, 0, 0);
          first.requestFocus();
          await pumpFavourites(tester);
          for (var col = 1; col <= columns; col++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)),
            );
          }
          // The last Right crossed the actual delegate's row boundary.
          expect(_grid(tester).key, gridKey);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(first));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(
            FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 0, columns)),
          );
          // The lazy grid has not necessarily mounted its last row yet.
          // Walk there publicly before obtaining that real borrowed node.
          for (var col = columns + 1; col <= 11; col++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await pumpFavourites(tester);
            expect(
              FocusManager.instance.primaryFocus,
              same(catalogNode(tester, 0, col)),
            );
          }
          final tail = catalogNode(tester, 0, 11);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(_grid(tester).key, isNot(gridKey));
          expect(
            FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 1, 0)),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await pumpFavourites(tester);
          expect(_grid(tester).key, gridKey);
          expect(FocusManager.instance.primaryFocus, same(tail));
          expect(catalogNode(tester, 0, 11), same(tail));
          expect(tester.takeException(), isNull);
        } finally {
          await closeFavourites(tester);
        }
      },
      () => MockClient((request) async {
        expect(request.url.host, 'board-origin.invalid');
        if (request.url.path.endsWith('/rail.json')) return page(0, 12);
        if (request.url.path.endsWith('/rail1.json')) return page(100, 12);
        if (request.url.path.endsWith('/skip=12.json')) return page(12, 0);
        fail('Unexpected Mosaic request: ${request.url}');
      }),
    );
  });

  for (final leaveOrigin in [false, true]) {
    testWidgets(
      leaveOrigin
          ? 'Home Mosaic held Right completion does not yank focus back'
          : 'Home Mosaic held Right completes onto the appended real node',
      (tester) async {
        await _prepare(tester, 1);
        final release = Completer<http.Response>();
        var pageRequests = 0;
        await http.runWithClient(
          () async {
            try {
              await mountFavourites(tester);
              expect(_columns(tester), inInclusiveRange(2, 8));
              final gridKey = _grid(tester).key;
              catalogNode(tester, 0, 0).requestFocus();
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
              final previous = catalogNode(tester, 0, 10);
              expect(pageRequests, 1);
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
              await pumpFavourites(tester);
              expect(FocusManager.instance.primaryFocus, same(tail));
              expect(release.isCompleted, isFalse);
              if (leaveOrigin) {
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
                await pumpFavourites(tester);
                expect(FocusManager.instance.primaryFocus, same(previous));
              }
              release.complete(page(12, 12));
              await pumpFavourites(tester);
              expect(pageRequests, 1);
              expect(_grid(tester).key, gridKey);
              expect(catalogNode(tester, 0, 11), same(tail));
              expect(catalogNode(tester, 0, 10), same(previous));
              if (leaveOrigin) {
                expect(FocusManager.instance.primaryFocus, same(previous));
              } else {
                expect(
                  FocusManager.instance.primaryFocus,
                  same(catalogNode(tester, 0, 12)),
                );
              }
              final focused = FocusManager.instance.primaryFocus;
              await tester.pump();
              expect(FocusManager.instance.primaryFocus, same(focused));
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
            if (request.url.path.endsWith('/skip=12.json')) {
              pageRequests++;
              return release.future;
            }
            fail('Unexpected Mosaic request: ${request.url}');
          }),
        );
      },
    );
  }
}
