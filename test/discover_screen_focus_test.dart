import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/see_all/discover_shelf_scope.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'discover_screen_origin_test.dart' show discoverSource, mountDiscover;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final layout in ['grid', 'stage']) {
    testWidgets(
      'origin Discover $layout walks Source filters and items then refocuses source on swap',
      (tester) async {
        await prepareFavourites(tester);
        StremioService.instance.invalidateCache();
        addTearDown(StremioService.instance.invalidateCache);
        final oldTab = MainPageBridge.activeTvTabIndex;
        addTearDown(() => MainPageBridge.setActiveTvTab(oldTab));
        await StorageService.setDiscoverDefaultSource('cw');
        await StorageService.setHomeContinueWatchingEnabled(true);
        await StorageService.setDiscoverLayout(layout);
        for (final id in ['origin-one', 'origin-two']) {
          await StorageService.saveContinueWatchingItem(
            imdbId: id,
            title: id,
            contentType: 'movie',
          );
        }
        await mountDiscover(tester, tv: true);
        MainPageBridge.setActiveTvTab(MainTab.discover);
        expect(MainPageBridge.requestTvContentFocus(), isTrue);
        await tester.pump();
        final sourceNode = discoverSource(tester).focusNode!;
        expect(sourceNode.hasFocus, isTrue);
        expect(
          DiscoverShelfScope.of(tester.element(find.byType(SeeAllPosterGrid))),
          layout == 'stage' ? isNotNull : isNull,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'cwsa_category');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final cells = tester
            .widgetList<CatalogItemTile>(find.byType(CatalogItemTile))
            .toList();
        expect(cells, hasLength(2));
        expect(cells.first.focusNode!.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(cells[1].focusNode!.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 260));
        final rail = tester.widget<DiscoverDetailRail>(
          find.byType(DiscoverDetailRail),
        );
        expect(rail.item!.id, cells[1].item.id);
        expect(rail.shownItem.value!.id, cells[1].item.id);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'cwsa_category');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(sourceNode.hasFocus, isTrue);

        final oldGrid = tester.element(find.byType(SeeAllPosterGrid));
        // The actual mounted dropdown callback owns revision, remount and the
        // post-frame refocus. No private State method or copied handler is used.
        discoverSource(tester).onSelected('trakt');
        await pumpFavourites(tester);
        expect(oldGrid.mounted, isFalse);
        expect(discoverSource(tester).value, 'trakt');
        expect(identical(discoverSource(tester).focusNode, sourceNode), isTrue);
        expect(sourceNode.hasFocus, isTrue);
        expect(
          tester
              .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
              .item,
          isNull,
        );
        expect(rail.shownItem.value, isNull);
        expect(await StorageService.getDiscoverLastSource(), 'trakt');

        discoverSource(tester).onSelected('cw');
        await pumpFavourites(tester);
        expect(sourceNode.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          tester
              .widgetList<CatalogItemTile>(find.byType(CatalogItemTile))
              .first
              .focusNode!
              .hasFocus,
          isTrue,
        );
        await closeFavourites(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
