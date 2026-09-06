import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_calendar_service.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_item_transformer.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/simkl/simkl_calendar_service.dart';
import 'package:debrify/services/simkl/simkl_continue_watching_service.dart';
import 'package:debrify/services/simkl/simkl_item_transformer.dart';
import 'package:debrify/services/simkl/simkl_list_source.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_calendar_service.dart';
import 'package:debrify/services/trakt/trakt_continue_watching_service.dart';
import 'package:debrify/services/trakt/trakt_item_transformer.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins today's tracker-family shapes before T2 extracts shared interfaces.
///
/// HTTP clients are not exercised. These tests lock the quirks the registry
/// must keep: IMDb `tt` gating, type folding, empty-vs-failed list pages,
/// inverted calendar ranges, CW selection fields, and the policy switch
/// tables (local is not a "dedicated" progress source).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackerItemTransformer (Trakt)', () {
    test('drops items without a tt IMDb id', () {
      expect(
        TraktItemTransformer.transformItem({
          'type': 'movie',
          'movie': {
            'title': 'No Imdb',
            'ids': {'trakt': 1},
          },
        }),
        isNull,
      );
      expect(
        TraktItemTransformer.transformItem({
          'type': 'movie',
          'movie': {
            'title': 'Bad',
            'ids': {'imdb': 'nm123'},
          },
        }),
        isNull,
      );
    });

    test('maps show → series and falls back to metahub art', () {
      final meta = TraktItemTransformer.transformItem({
        'type': 'show',
        'show': {
          'title': 'Severance',
          'year': 2022,
          'overview': 'Work',
          'ids': {'imdb': 'tt11280740'},
        },
      });
      expect(meta, isNotNull);
      expect(meta!.type, 'series');
      expect(meta.id, 'tt11280740');
      expect(meta.imdbId, 'tt11280740');
      expect(meta.name, 'Severance');
      expect(
        meta.poster,
        'https://images.metahub.space/poster/medium/tt11280740/img',
      );
      expect(
        meta.background,
        'https://images.metahub.space/background/medium/tt11280740/img',
      );
    });

    test('rowDateMs prefers watched_at over later fields', () {
      final ms = TraktItemTransformer.rowDateMs({
        'watched_at': '2026-01-01T00:00:00Z',
        'listed_at': '2020-01-01T00:00:00Z',
        'movie': {'title': 'x'},
      });
      expect(ms, DateTime.parse('2026-01-01T00:00:00Z').millisecondsSinceEpoch);
    });

    test('transformList skips non-maps and invalid ids', () {
      final metas = TraktItemTransformer.transformList([
        'nope',
        {
          'movie': {
            'title': 'A',
            'ids': {'imdb': 'tt1'},
          },
        },
        {
          'movie': {
            'title': 'B',
            'ids': {'imdb': 'bad'},
          },
        },
      ], inferredType: 'movie');
      expect(metas, hasLength(1));
      expect(metas.single.name, 'A');
      expect(metas.single.type, 'movie');
    });

    test('transformPlaybackEpisodes dedupes shows by IMDb', () {
      final metas = TraktItemTransformer.transformPlaybackEpisodes([
        {
          'type': 'episode',
          'show': {
            'title': 'One',
            'ids': {'imdb': 'tt111'},
          },
        },
        {
          'type': 'episode',
          'show': {
            'title': 'One again',
            'ids': {'imdb': 'tt111'},
          },
        },
        {
          'type': 'episode',
          'show': {
            'title': 'Two',
            'ids': {'imdb': 'tt222'},
          },
        },
      ]);
      expect(metas.map((m) => m.id).toList(), ['tt111', 'tt222']);
    });
  });

  group('TrackerItemTransformer (Simkl)', () {
    test('drops IMDb-less anime and prefers added_to_watchlist_at', () {
      expect(
        SimklItemTransformer.transformItem({
          'show': {
            'title': 'Anime',
            'ids': {'mal': 1},
          },
        }),
        isNull,
      );
      expect(
        SimklItemTransformer.rowDateMs({
          'added_to_watchlist_at': '2010-01-20T20:09:04Z',
          'last_watched_at': '2014-11-06T22:05:52Z',
        }),
        DateTime.parse('2010-01-20T20:09:04Z').millisecondsSinceEpoch,
      );
    });

    test('anime_type movie wins over show wrapper', () {
      final meta = SimklItemTransformer.transformItem({
        'anime_type': 'movie',
        'show': {
          'title': 'Film',
          'ids': {'imdb': 'tt333'},
        },
      });
      expect(meta, isNotNull);
      expect(meta!.type, 'movie');
      expect(meta.name, 'Film');
    });

    test('flat ids shape uses inferredType', () {
      final meta = SimklItemTransformer.transformItem({
        'title': 'Flat',
        'ids': {'imdb': 'tt444'},
      }, inferredType: 'movie');
      expect(meta!.type, 'movie');
      expect(meta.name, 'Flat');
    });
  });

  group('TrackerItemTransformer (MDBList)', () {
    test('rejects episode-only rows and accepts nested show', () {
      expect(
        MdblistItemTransformer.transformItem({
          'type': 'episode',
          'episode': {'title': 'E1'},
        }),
        isNull,
      );
      final nested = MdblistItemTransformer.transformItem({
        'show': {
          'title': 'Show',
          'imdb_id': 'tt555',
        },
      });
      expect(nested, isNotNull);
      expect(nested!.type, 'series');
      expect(nested.name, 'Show');
    });

    test('transformItems skips invalid rows; inferredType is unused today', () {
      final metas = MdblistItemTransformer.transformItems([
        {'title': 'Movie', 'imdb_id': 'tt666', 'mediatype': 'movie'},
        {'title': 'Nope'},
        'skip',
      ]);
      expect(metas, hasLength(1));
      expect(metas.single.name, 'Movie');
      expect(metas.single.type, 'movie');
    });
  });

  group('TrackerCalendar.getRange', () {
    test('inverted range is empty for every family (no HTTP)', () async {
      final start = DateTime(2026, 5, 2);
      final end = DateTime(2026, 5, 1);
      expect(
        await TraktCalendarService.forTesting(
          fetcher: (_, __) async => throw StateError('must not fetch'),
        ).getRange(start, end),
        isEmpty,
      );
      expect(await SimklCalendarService.instance.getRange(start, end), isEmpty);
      expect(
        await MdblistCalendarService.forTesting(
          fetcher: (_, __) async =>
              throw StateError('must not fetch'),
          resolver: (_) async => throw StateError('must not resolve'),
        ).getRange(start, end),
        isEmpty,
      );
    });
  });

  group('TrackerListSource', () {
    test('Trakt Continue Watching is host-provided (no fetch)', () async {
      final cw = [
        StremioMeta(id: 'tt1', type: 'movie', name: 'Cached'),
      ];
      final page = await TraktListSource.instance.loadList(
        const TraktListChoice.builtin(TraktSeeAllList.continueWatching),
        cwItems: cw,
      );
      expect(page.failed, isFalse);
      expect(page.items, cw);
    });

    test('Simkl Continue Watching is host-provided and returns empty', () async {
      final page = await SimklListSource.instance.loadList(
        SimklSeeAllList.continueWatching,
      );
      expect(page.failed, isFalse);
      expect(page.items, isEmpty);
    });

    test('Trakt list flags: public / hidesWatched / time-ordered', () {
      expect(TraktSeeAllList.trending.isPublic, isTrue);
      expect(TraktSeeAllList.popular.isPublic, isTrue);
      expect(TraktSeeAllList.anticipated.isPublic, isTrue);
      expect(TraktSeeAllList.watchlist.isPublic, isFalse);
      expect(TraktSeeAllList.recommendations.hidesWatched, isTrue);
      expect(TraktSeeAllList.trending.hidesWatched, isTrue);
      expect(TraktSeeAllList.watchlist.hidesWatched, isFalse);
      expect(TraktSeeAllList.history.isTimeOrdered, isTrue);
      expect(TraktSeeAllList.ratings.isTimeOrdered, isTrue);
      expect(TraktSeeAllList.collection.isTimeOrdered, isTrue);
      expect(TraktSeeAllList.watchlist.isTimeOrdered, isFalse);
    });

    test('Simkl list flags: status slugs and movies-in-watching quirk', () {
      expect(SimklSeeAllList.planToWatch.statusValue, 'plantowatch');
      expect(SimklSeeAllList.watching.statusValue, 'watching');
      expect(SimklSeeAllList.onHold.statusValue, 'hold');
      expect(SimklSeeAllList.completed.statusValue, 'completed');
      expect(SimklSeeAllList.dropped.statusValue, 'dropped');
      expect(SimklSeeAllList.ratings.statusValue, isNull);
      expect(SimklSeeAllList.watching.includesMovies, isFalse);
      expect(SimklSeeAllList.onHold.includesMovies, isFalse);
      expect(SimklSeeAllList.planToWatch.includesMovies, isTrue);
      expect(SimklSeeAllList.trending.isPublic, isTrue);
    });

    test('MDBList choice fromJson untitled / equality by id', () {
      final untitled = MdblistListChoice.fromJson({'id': 9, 'name': '  '});
      expect(untitled.name, 'Untitled list');
      expect(untitled.id, 9);
      expect(
        untitled,
        MdblistListChoice.fromJson({'id': 9, 'name': 'Other'}),
      );
    });
  });

  group('TrackerContinueWatching.selectionForItem', () {
    test('Trakt movie selection stamps traktSource and hides 0/100 progress', () async {
      const item = TraktContinueWatchingItem(
        meta: StremioMeta(
          id: 'tt777',
          imdbId: 'tt777',
          type: 'movie',
          name: 'Film',
          year: '2024',
          poster: 'https://example.test/p.jpg',
        ),
        traktContentType: TraktContinueWatchingService.moviesContentType,
        progress: 100,
      );
      final selection = await TraktContinueWatchingService.instance
          .selectionForItem(item);
      expect(selection, isNotNull);
      expect(selection!.imdbId, 'tt777');
      expect(selection.traktSource, isTrue);
      expect(selection.traktProgressPercent, isNull);
      expect(selection.isSeries, isFalse);
    });

    test('Simkl selection is sync and stamps simklSource', () {
      final item = SimklContinueWatchingItem(
        meta: const StremioMeta(
          id: 'tt888',
          imdbId: 'tt888',
          type: 'series',
          name: 'Show',
          year: '2021',
        ),
        progress: 42,
        season: 2,
        episode: 3,
        pausedAtMs: 1,
        isMovie: false,
      );
      final selection = SimklContinueWatchingService.instance.selectionForItem(
        item,
      );
      expect(selection.imdbId, 'tt888');
      expect(selection.simklSource, isTrue);
      expect(selection.simklProgressPercent, 42);
      expect(selection.season, 2);
      expect(selection.episode, 3);
    });

    test('MDBList CW item already carries the selection', () {
      const selection = AdvancedSearchSelection(
        imdbId: 'tt999',
        isSeries: false,
        title: 'Film',
        mdblistSource: true,
        mdblistProgressPercent: 15,
      );
      const item = MdblistContinueWatchingItem(
        selection: selection,
        paused: true,
      );
      expect(item.selection.mdblistSource, isTrue);
      expect(item.selection.mdblistProgressPercent, 15);
    });
  });

  group('TrackingSourcePolicy switches', () {
    setUp(() {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(ProfileRuntime.debugReset);

    test('progressFrom table: smart / local / dedicated', () {
      const smart = TrackingSourcePolicy(
        scrobbleTargets: {},
        progressSource: WatchProgressSource.smart,
        homeTickSources: {},
      );
      const local = TrackingSourcePolicy(
        scrobbleTargets: {},
        progressSource: WatchProgressSource.local,
        homeTickSources: {},
      );
      const trakt = TrackingSourcePolicy(
        scrobbleTargets: {},
        progressSource: WatchProgressSource.trakt,
        homeTickSources: {},
      );
      for (final source in TrackingSource.values) {
        expect(smart.progressFrom(source), isTrue);
      }
      expect(local.progressFrom(TrackingSource.local), isTrue);
      expect(local.progressFrom(TrackingSource.trakt), isFalse);
      expect(trakt.progressFrom(TrackingSource.trakt), isTrue);
      expect(trakt.progressFrom(TrackingSource.local), isFalse);
    });

    test('scrobbles: local is always on; remotes follow the set', () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.simkl},
        progressSource: WatchProgressSource.smart,
        homeTickSources: {},
      );
      expect(policy.scrobbles(TrackingSource.local), isTrue);
      expect(policy.scrobbles(TrackingSource.simkl), isTrue);
      expect(policy.scrobbles(TrackingSource.trakt), isFalse);
      expect(policy.scrobbles(TrackingSource.mdblist), isFalse);
    });

    test('load: local progress is not dedicated and does not fall back', () async {
      await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
      final policy = await TrackingSourcePolicy.load();
      expect(policy.progressSource, WatchProgressSource.local);
      expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isFalse);
    });

    test('load: each disconnected remote dedicated source falls back to smart',
        () async {
      for (final source in const [
        WatchProgressSource.trakt,
        WatchProgressSource.simkl,
        WatchProgressSource.mdblist,
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        await TrackingPrefs.setWatchProgressSource(source);
        final policy = await TrackingSourcePolicy.load();
        expect(
          policy.progressSource,
          WatchProgressSource.smart,
          reason: '$source with no credential must fall back',
        );
        expect(await TrackingPrefs.takeTrackingProgressFallbackNotice(), isTrue);
      }
    });
  });
}
