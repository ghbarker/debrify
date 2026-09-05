import 'dart:convert';

import 'package:debrify/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'discover_playback_selection_origin_test.dart'
    show PlaybackTransport, preparePlayback, playbackPanel, saveReturnMarker;
import 'discover_screen_origin_test.dart' show HeldBoundMigration;
import 'favourites_rows_origin_test.dart' show pumpFavourites;

// Actual Discover -> quick play -> launcher route -> pop -> CW/bound refresh.
// Existing fixtures substitute terminal media rendering/network/preferences IO;
// no refresh body, controller, route completion, or bridge event is fabricated.
// This does not isolate the Fav await or observe its private node/focus effects.
void main() {
  for (final dispose in [false, true]) {
    testWidgets(
      'Discover route pop exposes refreshed CW before held bound commit; dispose=$dispose',
      (tester) async {
        final fixture = await preparePlayback(tester);
        final panel = playbackPanel(tester);
        final item = panel.items.single;
        final isBound = panel.isBound!;
        expect(isBound(item), isFalse);

        panel.onQuickPlay!(item);
        await pumpFavourites(tester);
        expect(find.byKey(PlaybackTransport.playerKey), findsOneWidget);
        expect(fixture.launches.single.contentImdbId, item.imdbId);
        expect(fixture.requests, contains('/stream/movie/tt1234567.json'));
        expect(fixture.external, 0);

        // Persist new CW while the actual launcher Future is pending. The
        // terminal widget does not perform this write or trigger refresh.
        await saveReturnMarker();
        final prefs = await SharedPreferences.getInstance();
        final hold = HeldBoundMigration({
          for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
          'flutter.series_source_tt1234567': jsonEncode({
            'torrentHash': 'route-return',
            'torrentName': 'Return binding',
            'debridService': 'real_debrid',
            'debridTorrentId': 'route-return',
            'boundAt': 1,
          }),
        });
        final previousStore = SharedPreferencesStorePlatform.instance;
        final previousPrint = debugPrint;
        final messages = <String>[];
        // Register before installing globals, and release/drain held work before
        // restoring them, including when an assertion fails.
        addTearDown(() async {
          try {
            if (!hold.release.isCompleted) hold.release.complete();
            await fixture.close();
          } finally {
            SharedPreferencesStorePlatform.instance = previousStore;
            SharedPreferences.resetStatic();
            debugPrint = previousPrint;
          }
        });
        try {
          SharedPreferences.resetStatic();
          SharedPreferencesStorePlatform.instance = hold;
          debugPrint = (message, {wrapWidth}) {
            if (message != null) messages.add(message);
            previousPrint(message, wrapWidth: wrapWidth);
          };

          await pumpFavourites(tester);
          expect(hold.entered.isCompleted, isFalse);
          expect(isBound(item), isFalse);
          expect(
            playbackPanel(tester).items.map((m) => m.name),
            isNot(contains('Return marker')),
          );
          // Confirm the marker exists in storage, so the absence above is an
          // observable stale panel while the player route still covers Discover.
          expect(
            (await StorageService.getContinueWatchingItems()).map(
              (m) => m['title'],
            ),
            contains('Return marker'),
          );

          Navigator.of(
            tester.element(find.byKey(PlaybackTransport.playerKey)),
          ).pop();
          await pumpFavourites(tester);
          expect(find.byKey(PlaybackTransport.playerKey), findsNothing);
          expect(hold.entered.isCompleted, isTrue);
          expect(hold.release.isCompleted, isFalse);
          expect(
            playbackPanel(tester).items.map((m) => m.name),
            contains('Return marker'),
          );
          expect(isBound(item), isFalse);

          if (dispose) await tester.pumpWidget(const SizedBox.shrink());
          hold.release.complete();
          await pumpFavourites(tester);
          // Retain the actual public callback into the host's live map; this
          // detects a late cache commit even when its widget has been disposed.
          expect(isBound(item), !dispose);
          if (!dispose) {
            expect(playbackPanel(tester).isBound!(item), isTrue);
            expect(
              playbackPanel(tester).items.map((m) => m.name),
              contains('Return marker'),
            );
          }
          expect(
            messages.where((m) => m.contains('post-playback refresh failed')),
            isEmpty,
          );
          await fixture.close();
          expect(tester.takeException(), isNull);
        } finally {
          // Flutter checks this invariant before addTearDown callbacks run.
          debugPrint = previousPrint;
        }
      },
    );
  }
}
