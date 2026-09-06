import 'dart:async';

import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/screens/search/stage_visuals.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/skeleton_poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart'
    show installCatalog, page, catalogNode;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home Mosaic held first catalog becomes a grid with live identity',
      (tester) async {
    await prepareFavourites(tester);
    await StorageService.setTvHomeStyle('mosaic');
    await HomePrefs.setHomeHeroSource((
      mode: HomeHeroSourceMode.auto,
      ids: const [],
    ));
    await installCatalog();
    final release = Completer<void>();
    var firstRequests = 0;
    var tailRequests = 0;
    final grid = find.byWidgetPredicate((widget) => widget is GridView &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('mosaic-rail-'));
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        expect(firstRequests, 1);
        expect(release.isCompleted, isFalse);
        // This is the shared host loading guard, not proof of Mosaic's
        // separate unresolved-rail early return.
        expect(find.byType(BrandLoadingStage), findsOneWidget);
        expect(grid, findsNothing);
        release.complete();
        await pumpFavourites(tester);
        expect(find.byType(BrandLoadingStage), findsNothing);
        expect(grid, findsOneWidget);
        final gridKey = tester.widget<GridView>(grid).key;
        final first = catalogNode(tester, 0, 0);
        first.requestFocus();
        await pumpFavourites(tester);
        final cell = tester.widgetList<BoardCell>(find.byType(BoardCell))
            .singleWhere((cell) => identical(cell.focusNode, first));
        final identity = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
        expect(identity.variant, StageIdentityVariant.headline);
        expect(identity.item.value, same(cell.item));
        expect(FocusManager.instance.primaryFocus, same(first));
        final borrowedItem = identity.item;
        await pumpFavourites(tester);
        expect(tester.widget<GridView>(grid).key, gridKey);
        expect(catalogNode(tester, 0, 0), same(first));
        expect(tester.widget<CanvasIdentity>(find.byType(CanvasIdentity)).item,
            same(borrowedItem));
        expect(firstRequests, 1);
        expect(tailRequests, lessThanOrEqualTo(1));
      } finally {
        if (!release.isCompleted) release.complete();
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      expect(request.url.host, 'board-origin.invalid');
      if (request.url.path == '/catalog/movie/rail.json') {
        firstRequests++;
        await release.future;
        return page(0, 12);
      }
      if (request.url.path == '/catalog/movie/rail/skip=12.json') {
        tailRequests++;
        return page(12, 0);
      }
      fail('Unexpected Mosaic composition request: ${request.url}');
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
