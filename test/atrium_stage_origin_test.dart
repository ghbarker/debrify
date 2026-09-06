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

// Only transport results are supplied here. Home constructs the real Atrium
// window, borrowed nodes and all key/deferred-completion handling.
Future<void> _prepare(WidgetTester tester, int rows) async {
  await prepareFavourites(tester);
  // Fixed-main restart uses the original viewport; historical failed logs remain.
  tester.view.physicalSize = const Size(1920, 1080);
  await StorageService.setTvHomeStyle('atrium');
  await HomePrefs.setHomeHeroSource((
    mode: HomeHeroSourceMode.auto,
    ids: const [],
  ));
  await installCatalog(rows: rows);
}

List<Key?> _wallKeys(WidgetTester tester) => tester
    .widgetList<ListView>(find.byType(ListView))
    .map((widget) => widget.key)
    .where(
      (key) => key is ValueKey<String> && key.value.startsWith('atrium-rail-'),
    )
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home Atrium crosses two rows then advances the real window', (
    tester,
  ) async {
    await _prepare(tester, 3);
    await http.runWithClient(
      () async {
        try {
          await mountFavourites(tester);
          final first = catalogNode(tester, 0, 0);
          final second = catalogNode(tester, 1, 0);
          final initialWindow = _wallKeys(tester);
          expect(initialWindow, hasLength(2));
          first.requestFocus();
          await pumpFavourites(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(second));
          expect(_wallKeys(tester), orderedEquals(initialWindow));
          expect(catalogNode(tester, 0, 0), same(first));

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await pumpFavourites(tester);
          final nextWindow = _wallKeys(tester);
          expect(nextWindow, hasLength(2));
          expect(nextWindow.first, initialWindow.last);
          expect(nextWindow.last, isNot(initialWindow.last));
          expect(catalogNode(tester, 1, 0), same(second));
          expect(
            FocusManager.instance.primaryFocus,
            same(catalogNode(tester, 2, 0)),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await pumpFavourites(tester);
          expect(FocusManager.instance.primaryFocus, same(second));
          expect(_wallKeys(tester), orderedEquals(nextWindow));
          expect(tester.takeException(), isNull);
        } finally {
          await closeFavourites(tester);
        }
      },
      () => MockClient((request) async {
        expect(request.url.host, 'board-origin.invalid');
        final match = RegExp(
          r'^rail([1-2]?)\.json$',
        ).firstMatch(request.url.pathSegments.last);
        if (match == null) fail('Unexpected Atrium request: ${request.url}');
        return page((int.tryParse(match.group(1)!) ?? 0) * 100, 12);
      }),
    );
  });

  for (final leaveOrigin in [false, true]) {
    testWidgets(
      leaveOrigin
          ? 'Home Atrium held board completion does not yank focus back'
          : 'Home Atrium held board completion advances the focused bottom row',
      (tester) async {
        await _prepare(tester, 9);
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
              final bottom = catalogNode(tester, 7, 0);
              final top = catalogNode(tester, 6, 0);
              final window = _wallKeys(tester);
              expect(window, hasLength(2));
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await pumpFavourites(tester);
              expect(finalRowRequests, 1);
              expect(release.isCompleted, isFalse);
              expect(FocusManager.instance.primaryFocus, same(bottom));
              expect(_wallKeys(tester), orderedEquals(window));
              if (leaveOrigin) {
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
                await pumpFavourites(tester);
                expect(FocusManager.instance.primaryFocus, same(top));
              }
              release.complete(page(800, 12));
              await pumpFavourites(tester);
              expect(finalRowRequests, 1);
              expect(catalogNode(tester, 7, 0), same(bottom));
              if (leaveOrigin) {
                expect(FocusManager.instance.primaryFocus, same(top));
                expect(catalogNode(tester, 6, 0), same(top));
                expect(_wallKeys(tester), orderedEquals(window));
              } else {
                expect(
                  FocusManager.instance.primaryFocus,
                  same(catalogNode(tester, 8, 0)),
                );
                expect(_wallKeys(tester).first, window.last);
              }
              final focused = FocusManager.instance.primaryFocus;
              await tester.pump();
              expect(FocusManager.instance.primaryFocus, same(focused));
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
            if (match == null) {
              fail('Unexpected Atrium request: ${request.url}');
            }
            return page((int.tryParse(match.group(1)!) ?? 0) * 100, 12);
          }),
        );
      },
    );
  }
}
