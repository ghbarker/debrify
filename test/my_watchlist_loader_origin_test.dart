import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/search/fav_rows_controller.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Holds the real StorageService preference read; no controller body is copied.
class HeldWatchlistPreferences extends InMemorySharedPreferencesStore {
  HeldWatchlistPreferences(super.data) : super.withData();
  final release = Completer<void>();
  final events = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.startsWith('flutter.series_source_')) events.add('bound migration');
    return super.setValue(valueType, key, value);
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    events.add('read');
    await release.future;
    events.add('read complete');
    return super.getAllWithParameters(parameters);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final outcome in ['live', 'disposed', 'commit throws']) {
    testWidgets('origin watchlist read/partition/focus order: $outcome', (
      tester,
    ) async {
      final previous = SharedPreferencesStorePlatform.instance;
      final store = HeldWatchlistPreferences({
        'flutter.my_watchlist_v1': jsonEncode([
          {
            'addedAt': 1,
            'item': {'id': 'old', 'type': 'movie', 'name': 'Old'},
          },
          {
            'addedAt': 3,
            'item': {'id': 'series', 'type': 'SERIES', 'name': 'Series'},
          },
          {
            'addedAt': 2,
            'item': {'id': 'new', 'type': 'movie', 'name': 'New'},
          },
          {'addedAt': 4, 'item': null},
        ]),
      });
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = store;
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
        ProfileRuntime.debugReset();
      });
      var live = true;
      final observations = <Object>[];
      late FavRowsController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              controller = FavRowsController(
                readContext: () => context,
                isLive: () => live,
                readIsTelevision: () => true,
                commit: (apply) {
                  store.events.add('commit');
                  observations.add(controller.watchlistMovieNodes.length);
                  apply();
                  observations.add(
                    controller.watchlistMovieItems.map((e) => e.id).toList(),
                  );
                  observations.add(
                    controller.watchlistSeriesItems.map((e) => e.id).toList(),
                  );
                  observations.add(controller.watchlistMovieNodes.length);
                  if (outcome == 'commit throws') {
                    throw StateError('host commit failed');
                  }
                },
                homeRowIds: () => [],
                addonForContinue: (_) => throw UnimplementedError(),
                readCatalogQuery: () => '',
                readCatalogSearching: () => false,
                focusContent: () {},
                focusHomeRailAt: (_, __) => false,
                focusRelativeHomeRail: (_, __, ___) {},
                focusRow: (_, __) => false,
                readHomeDisabled: () => {},
                maybeAutoFocusBoard: () {
                  observations.add(controller.watchlistMovieNodes.length);
                  observations.add(controller.watchlistSeriesNodes.length);
                  store.events.add('focus after nodes');
                },
                openItem: (_, __) {},
                refreshAfterPlayback: () async {},
                requestRowFocus: (_, __) {},
              );
              return const SizedBox();
            },
          ),
        ),
      );
      final oldMovies = controller.watchlistMovieItems;
      final oldSeries = controller.watchlistSeriesItems;
      final movieNodes = controller.watchlistMovieNodes;
      final seriesNodes = controller.watchlistSeriesNodes;
      final progressMap = controller.playlistProgress;
      final pending = controller.loadMyWatchlist();
      await tester.pump();
      expect(store.events, ['read']);
      expect(identical(controller.watchlistMovieItems, oldMovies), isTrue);
      if (outcome == 'disposed') {
        live = false;
        await tester.pumpWidget(const SizedBox());
      }
      store.release.complete();
      await pending;
      expect(store.events, [
        'read',
        'read complete',
        if (outcome != 'disposed') 'commit',
        if (outcome == 'live') 'focus after nodes',
      ]);
      expect(
        observations,
        outcome == 'disposed'
            ? []
            : [
                0,
                ['new', 'old'],
                ['series'],
                0,
                if (outcome == 'live') ...[2, 1],
              ],
      );
      expect(
        identical(controller.watchlistMovieItems, oldMovies),
        outcome == 'disposed',
      );
      expect(
        identical(controller.watchlistSeriesItems, oldSeries),
        outcome == 'disposed',
      );
      expect(identical(controller.watchlistMovieNodes, movieNodes), isTrue);
      expect(identical(controller.watchlistSeriesNodes, seriesNodes), isTrue);
      expect(identical(controller.playlistProgress, progressMap), isTrue);
      for (final node in [...movieNodes, ...seriesNodes]) {
        node.dispose();
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
