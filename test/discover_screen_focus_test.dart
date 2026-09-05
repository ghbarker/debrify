import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
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
  testWidgets(
    'origin Discover theater waits five seconds and cancels on frames stopping',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverLayout('grid');
      await mountDiscover(tester, tv: true);
      final stage = tester.widget<DiscoverTrailerStage>(
        find.byType(DiscoverTrailerStage),
      );
      final theater = tester
          .widgetList<ValueListenableBuilder<bool>>(
            find.ancestor(
              of: find.byType(DiscoverDetailRail),
              matching: find.byWidgetPredicate(
                (w) => w is ValueListenableBuilder<bool>,
              ),
            ),
          )
          .first
          .valueListenable;
      expect(theater.value, isFalse);
      stage.showing!.value = true;
      await tester.pump(const Duration(milliseconds: 4999));
      expect(theater.value, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(theater.value, isTrue);
      stage.showing!.value = false;
      expect(theater.value, isFalse);
      stage.showing!.value = true;
      await tester.pump(const Duration(seconds: 2));
      stage.showing!.value = false;
      await tester.pump(const Duration(seconds: 4));
      expect(theater.value, isFalse);
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('origin Discover narrow canvas resets chrome after frame', (
    tester,
  ) async {
    await prepareFavourites(tester);
    StremioService.instance.invalidateCache();
    addTearDown(StremioService.instance.invalidateCache);
    await mountDiscover(tester, tv: true);
    final stage = tester.widget<DiscoverTrailerStage>(
      find.byType(DiscoverTrailerStage),
    );
    stage.takeover!.value = 0.6;
    stage.showing!.value = true;
    expect(MainPageBridge.tvChromeDim.value, 0.6);
    tester.view.physicalSize = const Size(640, 1080);
    // Size invalidation itself must not synchronously write shell state.
    expect(MainPageBridge.tvChromeDim.value, 0.6);
    await tester.pump();
    expect(MainPageBridge.tvChromeDim.value, 0);
    expect(stage.takeover!.value, 0);
    expect(stage.showing!.value, isFalse);
    expect(find.byType(DiscoverTrailerStage), findsNothing);
    await closeFavourites(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'origin Discover watchlist refresh retains focus and live bound reader',
    (tester) async {
      await prepareFavourites(tester);
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt1234567',
        title: 'Bound origin',
        contentType: 'movie',
      );
      await mountDiscover(tester, tv: true);
      final sourceFocus = discoverSource(tester).focusNode!;
      sourceFocus.requestFocus();
      await tester.pump();
      CatalogItemTile tile() =>
          tester.widget<CatalogItemTile>(find.byType(CatalogItemTile));
      final item = tile().item;
      final retainedIsBound = tester
          .widget<ContinueWatchingSeeAllScreen>(
            find.byType(ContinueWatchingSeeAllScreen),
          )
          .isBound!;
      expect(tile().hasBoundSource, isFalse);
      expect(retainedIsBound(item), isFalse);
      // The real return listener executes the favourites adapter while Discover
      // stays mounted. Seed both partitions after startup; do not substitute the
      // loader or manufacture a controller with copied host callbacks.
      const savedMovie = StremioMeta(
        id: 'saved-movie',
        type: 'movie',
        name: 'Saved movie',
      );
      const savedSeries = StremioMeta(
        id: 'saved-series',
        type: 'series',
        name: 'Saved series',
      );
      await StorageService.setMyWatchlistItem(savedMovie, true);
      await StorageService.setMyWatchlistItem(savedSeries, true);
      await SeriesSourceService.addSource(
        'tt1234567',
        const SeriesSource(
          torrentHash: 'origin',
          torrentName: 'Origin',
          debridService: 'real_debrid',
          debridTorrentId: 'origin',
          boundAt: 1,
        ),
      );
      MainPageBridge.notifyPlaybackReturned();
      await pumpFavourites(tester);
      expect(tile().hasBoundSource, isTrue);
      expect(retainedIsBound(item), isTrue);
      expect(identical(discoverSource(tester).focusNode, sourceFocus), isTrue);
      expect(sourceFocus.hasFocus, isTrue);
      await StorageService.setMyWatchlistItem(savedMovie, false);
      await StorageService.setMyWatchlistItem(savedSeries, false);
      await SeriesSourceService.removeSourceByHash('tt1234567', 'origin');
      MainPageBridge.notifyPlaybackReturned();
      await pumpFavourites(tester);
      expect(tile().hasBoundSource, isFalse);
      expect(retainedIsBound(item), isFalse);
      expect(sourceFocus.hasFocus, isTrue);
      // Finite observation: populated then emptied persisted watchlist does not
      // steal Source focus during return refresh, and a pre-refresh bound callback
      // remains live in both directions. Hidden Fav list commits/unattached nodes
      // and the independent watchlist-await order are NOT observable here. This
      // cannot justify replacing the adapter with a bare loader or prove physical
      // bound-map identity (a callback could read a replacement map).
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );
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
