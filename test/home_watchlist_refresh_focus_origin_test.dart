import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'discover_screen_origin_test.dart' show HeldBoundMigration;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home deferred down reaches watchlist before bound IO completes', (
    tester,
  ) async {
    await prepareFavourites(tester);
    const movie = StremioMeta(
      id: 'home-origin',
      type: 'movie',
      name: 'Home origin',
      poster: '',
    );
    const series = StremioMeta(
      id: 'home-arrival',
      type: 'series',
      name: 'Home arrival',
      poster: '',
    );
    await MyWatchlistStore.setMyWatchlistItem(movie, true);
    await mountFavourites(tester);
    ArtPoster poster(String title) => tester
        .widgetList<ArtPoster>(find.byType(ArtPoster))
        .singleWhere((widget) => widget.title == title);
    final origin = poster(movie.name).focusNode;
    origin.requestFocus();
    await pumpFavourites(tester);
    // The actual mounted card handles Down; no controller pending fields or
    // private host methods are invoked by this test.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(origin.hasFocus, isTrue);

    await MyWatchlistStore.setMyWatchlistItem(series, true);
    await StorageService.setHomeContinueWatchingEnabled(true);
    await PlaybackProgressStore.saveContinueWatchingItem(
      imdbId: 'tt1234567',
      title: 'Returned CW',
      contentType: 'movie',
    );
    final prefs = await SharedPreferences.getInstance();
    final hold = HeldBoundMigration({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      'flutter.series_source_tt1234567': jsonEncode({
        'torrentHash': 'home-origin',
        'torrentName': 'Home origin',
        'debridService': 'real_debrid',
        'debridTorrentId': 'home-origin',
        'boundAt': 1,
      }),
    });
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = hold;
    try {
      MainPageBridge.notifyPlaybackReturned();
      await pumpFavourites(tester);
      expect(hold.entered.isCompleted, isTrue);
      expect(hold.release.isCompleted, isFalse);
      final arriving = poster(series.name).focusNode;
      expect(poster(movie.name).focusNode, same(origin));
      expect(arriving.hasFocus, isTrue);
      expect(FocusManager.instance.primaryFocus, same(arriving));

      hold.release.complete();
      await pumpFavourites(tester);
      expect(poster(series.name).focusNode, same(arriving));
      expect(FocusManager.instance.primaryFocus, same(arriving));
      await tester.pump();
      expect(arriving.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      // Home-only: real watchlist focus effects precede completion of the
      // downstream bound write. This does not expose Discover's hidden nodes,
      // isolate the watchlist await, or prove exact CW/focus microtask order.
    } finally {
      if (!hold.release.isCompleted) hold.release.complete();
      try {
        await pumpFavourites(tester);
        await closeFavourites(tester);
      } finally {
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
      }
    }
  });
}
