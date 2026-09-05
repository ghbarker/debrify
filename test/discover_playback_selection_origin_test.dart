import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'discover_screen_origin_test.dart' show mountDiscover;
import 'my_watchlist_loader_origin_test.dart' show HeldWatchlistPreferences;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

void main() {
  for (final cancel in [false, true]) {
    testWidgets('origin Discover held detail play cancel=$cancel', (
      tester,
    ) async {
      await prepareFavourites(tester);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.setPlayButtonMode('always');
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt1234567',
        title: 'Cancel origin',
        contentType: 'movie',
      );
      await mountDiscover(tester);
      final panel = tester.widget<ContinueWatchingSeeAllScreen>(
        find.byType(ContinueWatchingSeeAllScreen),
      );
      panel.onOpen(panel.items.single);
      await pumpFavourites(tester);
      final detail = tester.widget<MergedDetailScreen>(
        find.byType(MergedDetailScreen),
      );
      final prefs = await SharedPreferences.getInstance();
      final hold = HeldWatchlistPreferences({
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      });
      final previous = SharedPreferencesStorePlatform.instance;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = hold;
      addTearDown(() {
        if (!hold.release.isCompleted) hold.release.complete();
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = previous;
      });
      // This callback belongs to the detail route opened by actual Discover.
      // The existing preference transport holds all reads, not a synthetic host
      // method or a claimed independently isolated quick-play-rules read.
      final completion = detail.onResume(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hold.events, contains('read'));
      expect(find.text('Cancel'), findsOneWidget);
      if (cancel) {
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Cancel'), findsNothing);
      }
      hold.release.complete();
      await completion;
      await pumpFavourites(tester);
      expect(
        find.byType(TvHeldKeyGuard),
        cancel ? findsNothing : findsOneWidget,
      );
      if (!cancel) {
        Navigator.of(tester.element(find.byType(TvHeldKeyGuard))).pop();
        await pumpFavourites(tester);
      }
      expect(find.byType(MergedDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeFavourites(tester);
    });
  }

  testWidgets(
    'origin Discover quick-play opens actual sources and return reloads CW',
    (tester) async {
      await prepareFavourites(tester);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.setPlayButtonMode('always');
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt1234567',
        title: 'Playback origin',
        contentType: 'movie',
      );
      await mountDiscover(tester);
      final panel = tester.widget<ContinueWatchingSeeAllScreen>(
        find.byType(ContinueWatchingSeeAllScreen),
      );
      expect(panel.items.single.name, 'Playback origin');
      // Invoke the mounted public widget's real host callback, not a private
      // State method or a reproduction of the resolver/route implementation.
      panel.onQuickPlay!(panel.items.single);
      await pumpFavourites(tester);
      expect(find.byType(TvHeldKeyGuard), findsOneWidget);
      // The route widget's public constructor values are observed through its
      // public wrapper. Its private class/State is neither constructed nor called.
      final dynamic sources = tester
          .widget<TvHeldKeyGuard>(find.byType(TvHeldKeyGuard))
          .child;
      expect(sources.selection.imdbId, 'tt1234567');
      expect(sources.selection.isSeries, isFalse);
      expect(sources.selection.title, 'Playback origin');
      expect(sources.meta.imdbId, 'tt1234567');
      expect(sources.forcePlayOnTap, isTrue);
      expect(sources.bindMode, isFalse);
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt7654321',
        title: 'Saved while sources open',
        contentType: 'movie',
      );
      Navigator.of(tester.element(find.byType(TvHeldKeyGuard))).pop();
      await pumpFavourites(tester);
      expect(find.byType(TvHeldKeyGuard), findsNothing);
      final returned = tester.widget<ContinueWatchingSeeAllScreen>(
        find.byType(ContinueWatchingSeeAllScreen),
      );
      expect(
        returned.items.map((item) => item.name),
        contains('Saved while sources open'),
      );
      // This proves a sources-route return, not a native player launch/return.
      expect(tester.takeException(), isNull);
      await closeFavourites(tester);
    },
  );
}
