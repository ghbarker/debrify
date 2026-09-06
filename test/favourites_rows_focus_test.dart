import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final cancel in [false, true]) {
    testWidgets(
      'origin deferred favourites down completes unless focus moved: $cancel',
      (tester) async {
        await prepareFavourites(tester);
        if (cancel) {
          await MyWatchlistStore.setMyWatchlistItem(
            const StremioMeta(
              id: 'other',
              type: 'movie',
              name: 'Other Card',
              poster: '',
            ),
            true,
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
        }
        await MyWatchlistStore.setMyWatchlistItem(
          const StremioMeta(
            id: 'movie',
            type: 'movie',
            name: 'First Row',
            poster: '',
          ),
          true,
        );
        await mountFavourites(tester);
        ArtPoster poster(String title) => tester
            .widgetList<ArtPoster>(find.byType(ArtPoster))
            .singleWhere((p) => p.title == title);
        final origin = poster('First Row').focusNode;
        origin.requestFocus();
        await pumpFavourites(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(origin.hasFocus, isTrue);
        FocusNode? movedTo;
        if (cancel) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          movedTo = FocusManager.instance.primaryFocus;
          expect(movedTo, isNot(same(origin)));
        }
        // A real playback-return refresh makes a previously absent row arrive.
        await MyWatchlistStore.setMyWatchlistItem(
          const StremioMeta(
            id: 'series',
            type: 'series',
            name: 'Arriving Row',
            poster: '',
          ),
          true,
        );
        MainPageBridge.notifyPlaybackReturned();
        await pumpFavourites(tester);
        final arriving = poster('Arriving Row').focusNode;
        expect(poster('First Row').focusNode, same(origin));
        expect(arriving.hasFocus, !cancel);
        if (cancel) expect(FocusManager.instance.primaryFocus, same(movedTo));
        expect(tester.takeException(), isNull);
        await closeFavourites(tester);
      },
    );
  }

  testWidgets('origin shrinking watchlist reanchors the removed last card', (
    tester,
  ) async {
    await prepareFavourites(tester);
    const first = StremioMeta(
      id: 'first',
      type: 'movie',
      name: 'First',
      poster: '',
    );
    const last = StremioMeta(
      id: 'last',
      type: 'movie',
      name: 'Last',
      poster: '',
    );
    await MyWatchlistStore.setMyWatchlistItem(last, true);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await MyWatchlistStore.setMyWatchlistItem(first, true);
    await mountFavourites(tester);
    final posters = tester
        .widgetList<ArtPoster>(find.byType(ArtPoster))
        .toList();
    expect(posters.map((p) => p.title), ['First', 'Last']);
    final survivor = posters.first.focusNode;
    posters.last.focusNode.requestFocus();
    await pumpFavourites(tester);
    await MyWatchlistStore.setMyWatchlistItem(last, false);
    MainPageBridge.notifyPlaybackReturned();
    await pumpFavourites(tester);
    final remaining = tester.widget<ArtPoster>(find.byType(ArtPoster));
    expect(remaining.title, 'First');
    expect(remaining.focusNode, same(survivor));
    expect(survivor.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await closeFavourites(tester);
  });
}
