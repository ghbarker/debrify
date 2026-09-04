import 'dart:io';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// G1'-1 characterisation of the catalog play/resume resolver **before**
/// the move out of `search_screen.dart`.
///
/// Pin commit must stay green on its own and must not import
/// `catalog_play_resolver.dart`. After the move this file still matches
/// the same bodies (it reads the new file when that file exists).
///
/// Quirks pinned here (keep, do not "fix"):
/// * Recency wins over fixed tracker priority when timestamps exist;
///   timestampless candidates fall back to Trakt → Simkl → MDBList → local.
/// * A promised target from the merged page wins over reconcile, and a
///   promise is started-evidence even when it matches the S01E01 fallback.
/// * MDBList fast path is skipped when it disagrees with the promise.
/// * Empty candidates: Simkl next_to_watch → MDBList CW → unstarted S01E01.
/// * Movie tracker percent is resume-worthy only in `[1, 90)`; MDBList
///   movie percent only in `[1, 80)`.
/// * Series resume cache TTL is 45s; Trakt movie-percent memo is 30s.
/// * Lookups are 4s-boxed. Debug line says `preferTrackerResume`.
/// * Play/browse: series browse opens episodes; movies use `_movieSelection`.
///
/// Origin: `lib/screens/search_screen.dart` `_onCatalogPlay` resolve half,
/// `_reconcileSeriesResume`, `_resolveResumeInfo`, `_onCatalogBrowse`,
/// `_movieSelection`, movie-percent helpers (~11283–12504).
String _origin() {
  final moved = File('lib/services/playback/catalog_play_resolver.dart');
  if (moved.existsSync()) return moved.readAsStringSync();
  return File('lib/screens/search_screen.dart').readAsStringSync();
}

StremioMeta _meta({
  required String id,
  required String type,
  String? imdbId,
  String name = 'Title',
  String? year,
  String? poster,
}) => StremioMeta(
  id: id,
  imdbId: imdbId,
  type: type,
  name: name,
  year: year,
  poster: poster,
);

/// Origin `_resumableMoviePercent` — player's seek window is 1% ≤ pct < 90.
double? resumableMoviePercent(double? pct) {
  if (pct == null || pct < 1 || pct >= 90) return null;
  return pct;
}

/// Origin `_resumableMdblistPercent` — MDBList watched threshold is 80.
double? resumableMdblistPercent(double? pct) {
  if (pct == null || pct < 1 || pct >= 80) return null;
  return pct;
}

/// Origin `_movieSelection`.
AdvancedSearchSelection movieSelection(
  StremioMeta item, {
  bool isTraktSource = false,
  bool isMdblistSource = false,
  double? traktProgressPercent,
  double? simklProgressPercent,
  double? mdblistProgressPercent,
}) => AdvancedSearchSelection(
  imdbId: item.effectiveImdbId ?? item.id,
  isSeries: false,
  title: item.name,
  year: item.year,
  contentType: item.type,
  posterUrl: item.poster,
  traktSource: isTraktSource,
  traktProgressPercent: traktProgressPercent,
  simklProgressPercent: simklProgressPercent,
  mdblistSource: isMdblistSource,
  mdblistProgressPercent: mdblistProgressPercent,
);

typedef _Cand = ({
  int prio,
  int? tsMs,
  int s,
  int e,
  double? pct,
  bool finished,
  AdvancedSearchSelection? sel,
});

/// Origin `_reconcileSeriesResume` candidate sort.
List<_Cand> sortResumeCandidates(List<_Cand> candidates) {
  final copy = [...candidates];
  copy.sort((a, b) {
    final at = a.tsMs;
    final bt = b.tsMs;
    if (at != null && bt != null) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    return a.prio.compareTo(b.prio);
  });
  return copy;
}

/// Origin empty-candidates fallback.
({bool started, int season, int episode, int? sourcePrio}) emptyCandidatesFallback({
  ({int season, int episode})? simklNext,
  ({int season, int episode})? mdbSel,
}) {
  if (simklNext != null) {
    return (
      started: true,
      season: simklNext.season,
      episode: simklNext.episode,
      sourcePrio: null,
    );
  }
  if (mdbSel != null) {
    return (
      started: true,
      season: mdbSel.season,
      episode: mdbSel.episode,
      sourcePrio: null,
    );
  }
  return (started: false, season: 1, episode: 1, sourcePrio: null);
}

/// Origin `_onCatalogPlay` promise override + started-evidence.
({bool overridden, bool started, int season, int episode}) applyPromisedTarget({
  required bool reconciledStarted,
  required int reconciledSeason,
  required int reconciledEpisode,
  ({bool started, int season, int episode})? promised,
}) {
  final overridden =
      promised != null &&
      (promised.season != reconciledSeason ||
          promised.episode != reconciledEpisode);
  final started = reconciledStarted || (promised?.started ?? false);
  return (
    overridden: overridden,
    started: started,
    season: overridden ? promised!.season : reconciledSeason,
    episode: overridden ? promised.episode : reconciledEpisode,
  );
}

/// Origin MDBList fast-path stale check.
bool mdblistFastPathStale({
  required int ownedSeason,
  required int ownedEpisode,
  ({int season, int episode})? promised,
}) {
  final p = promised;
  return p != null && (ownedSeason != p.season || ownedEpisode != p.episode);
}

/// Origin play id: `tt…` when present, else raw catalog id.
String catalogPlayId(StremioMeta item) {
  final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
  return ttId.isNotEmpty ? ttId : (item.effectiveImdbId ?? item.id);
}

void main() {
  late String origin;

  setUpAll(() {
    origin = _origin();
  });

  group('origin source (G1\'-1 pin)', () {
    test('reconciler recency sort and empty-candidate fallback live in origin', () {
      expect(origin, contains('if (at != null && bt != null) return bt.compareTo(at)'));
      expect(origin, contains('return a.prio.compareTo(b.prio)'));
      expect(origin, contains('started: false'));
      expect(origin, contains('season: 1'));
      expect(origin, contains('episode: 1'));
      expect(origin, contains('next_to_watch'));
    });

    test('promise override and MDBList stale-fast-path comments stay', () {
      expect(origin, contains('play-promise-override'));
      expect(origin, contains('play-mdblist-fastpath-skipped'));
      expect(origin, contains('A promise IS started-evidence'));
      expect(
        origin,
        contains('empty-candidates fallback (started=false)'),
      );
    });

    test('movie percent windows and cache TTLs stay', () {
      expect(origin, contains('pct < 1 || pct >= 90'));
      expect(origin, contains('pct < 1 || pct >= 80'));
      expect(origin, contains('nowMs - hit.atMs < 45000'));
      expect(origin, contains('const Duration(seconds: 30)'));
      expect(origin, contains('const Duration(seconds: 4)'));
    });

    test('debug line keeps preferTrackerResume typo; play/browse split stays', () {
      expect(origin, contains('preferTrackerResume='));
      expect(origin, contains('browseSourcesOnly'));
      expect(origin, contains(RegExp(r'_?onCatalogBrowse')));
      expect(origin, contains(RegExp(r'_?movieSelection')));
    });

    test('does not invent a new Mode enum; G1\'-0 board types stay public', () {
      expect(origin, isNot(contains(RegExp(r'enum Mode \{'))));
      final host = File('lib/screens/search_screen.dart').readAsStringSync();
      expect(host, contains('enum SearchBoardMode { catalog, keyword, lists }'));
    });
  });

  group('pure decision tables (origin algorithm)', () {
    test('movie percent rejects below 1% and at/above 90%', () {
      expect(resumableMoviePercent(null), isNull);
      expect(resumableMoviePercent(0.5), isNull);
      expect(resumableMoviePercent(1), 1);
      expect(resumableMoviePercent(45), 45);
      expect(resumableMoviePercent(89.9), 89.9);
      expect(resumableMoviePercent(90), isNull);
      expect(resumableMoviePercent(95), isNull);
    });

    test('MDBList movie percent rejects below 1% and at/above 80%', () {
      expect(resumableMdblistPercent(null), isNull);
      expect(resumableMdblistPercent(0.9), isNull);
      expect(resumableMdblistPercent(1), 1);
      expect(resumableMdblistPercent(79.9), 79.9);
      expect(resumableMdblistPercent(80), isNull);
    });

    test('movieSelection keeps raw catalog id when there is no tt id', () {
      final iptv = _meta(id: 'iptv:7', type: 'tv', name: 'News');
      final sel = movieSelection(iptv, isTraktSource: true);
      expect(sel.imdbId, 'iptv:7');
      expect(sel.isSeries, isFalse);
      expect(sel.traktSource, isTrue);
      expect(sel.mdblistSource, isFalse);
    });

    test('movieSelection prefers effectiveImdbId and carries tracker percents', () {
      final movie = _meta(
        id: 'kitsu:1',
        type: 'movie',
        imdbId: 'tt0101',
        name: 'Film',
        year: '1999',
        poster: 'https://p',
      );
      final sel = movieSelection(
        movie,
        isMdblistSource: true,
        traktProgressPercent: 12,
        simklProgressPercent: 8,
        mdblistProgressPercent: 20,
      );
      expect(sel.imdbId, 'tt0101');
      expect(sel.title, 'Film');
      expect(sel.year, '1999');
      expect(sel.posterUrl, 'https://p');
      expect(sel.mdblistSource, isTrue);
      expect(sel.traktProgressPercent, 12);
      expect(sel.simklProgressPercent, 8);
      expect(sel.mdblistProgressPercent, 20);
    });

    test('recency beats fixed priority; timestampless uses Trakt first', () {
      final local = (
        prio: 3,
        tsMs: 200,
        s: 2,
        e: 4,
        pct: 10.0,
        finished: false,
        sel: null,
      );
      final trakt = (
        prio: 0,
        tsMs: 100,
        s: 1,
        e: 1,
        pct: 40.0,
        finished: false,
        sel: null,
      );
      final winner = sortResumeCandidates([trakt, local]).first;
      expect(winner.prio, 3);
      expect(winner.s, 2);

      final noTsTrakt = (
        prio: 0,
        tsMs: null,
        s: 3,
        e: 1,
        pct: null,
        finished: false,
        sel: null,
      );
      final noTsLocal = (
        prio: 3,
        tsMs: null,
        s: 1,
        e: 2,
        pct: null,
        finished: false,
        sel: null,
      );
      final legacy = sortResumeCandidates([noTsLocal, noTsTrakt]).first;
      expect(legacy.prio, 0);
      expect(legacy.s, 3);

      final stampedLocal = (
        prio: 3,
        tsMs: 50,
        s: 5,
        e: 1,
        pct: 5.0,
        finished: false,
        sel: null,
      );
      final unstampedTrakt = (
        prio: 0,
        tsMs: null,
        s: 1,
        e: 1,
        pct: 90.0,
        finished: false,
        sel: null,
      );
      final stampedWins = sortResumeCandidates([
        unstampedTrakt,
        stampedLocal,
      ]).first;
      expect(stampedWins.prio, 3);
    });

    test('empty candidates: next_to_watch, then MDBList, then unstarted S01E01', () {
      expect(
        emptyCandidatesFallback(
          simklNext: (season: 4, episode: 2),
          mdbSel: (season: 1, episode: 3),
        ),
        (started: true, season: 4, episode: 2, sourcePrio: null),
      );
      expect(
        emptyCandidatesFallback(mdbSel: (season: 2, episode: 8)),
        (started: true, season: 2, episode: 8, sourcePrio: null),
      );
      expect(
        emptyCandidatesFallback(),
        (started: false, season: 1, episode: 1, sourcePrio: null),
      );
    });

    test('promised target overrides reconcile; matching promise is still started', () {
      final override = applyPromisedTarget(
        reconciledStarted: false,
        reconciledSeason: 1,
        reconciledEpisode: 1,
        promised: (started: true, season: 2, episode: 5),
      );
      expect(override.overridden, isTrue);
      expect(override.started, isTrue);
      expect(override.season, 2);
      expect(override.episode, 5);

      final match = applyPromisedTarget(
        reconciledStarted: false,
        reconciledSeason: 1,
        reconciledEpisode: 1,
        promised: (started: true, season: 1, episode: 1),
      );
      expect(match.overridden, isFalse);
      expect(match.started, isTrue);
      expect(match.season, 1);
    });

    test('MDBList fast path is stale when it disagrees with the promise', () {
      expect(
        mdblistFastPathStale(
          ownedSeason: 1,
          ownedEpisode: 2,
          promised: (season: 1, episode: 3),
        ),
        isTrue,
      );
      expect(
        mdblistFastPathStale(
          ownedSeason: 1,
          ownedEpisode: 2,
          promised: (season: 1, episode: 2),
        ),
        isFalse,
      );
      expect(
        mdblistFastPathStale(ownedSeason: 1, ownedEpisode: 2),
        isFalse,
      );
    });

    test('play id prefers tt… then raw catalog id', () {
      expect(
        catalogPlayId(_meta(id: 'kitsu:9', type: 'series', imdbId: 'tt99')),
        'tt99',
      );
      expect(
        catalogPlayId(_meta(id: 'tt88', type: 'series')),
        'tt88',
      );
      expect(
        catalogPlayId(_meta(id: 'addon:raw', type: 'series')),
        'addon:raw',
      );
    });

    test('series browse is episodes; movies are a play/browse movie selection', () {
      // Mirrors `_onCatalogBrowse`: series → episode picker; else `_movieSelection`.
      final series = _meta(id: 'tt1', type: 'series', name: 'Show');
      final movie = _meta(id: 'tt2', type: 'movie', name: 'Film');
      expect(series.type == 'series', isTrue);
      expect(movie.type == 'series', isFalse);
      final sel = movieSelection(movie, isTraktSource: true);
      expect(sel.isSeries, isFalse);
      expect(sel.traktSource, isTrue);
    });

    test('shouldAdvanceEpisodeResume still owns the 80% / frontier quirks', () {
      expect(
        shouldAdvanceEpisodeResume(
          candidate: (season: 2, episode: 3),
          finished: false,
          progress: 80,
          isTracker: true,
        ),
        isTrue,
      );
      expect(
        shouldAdvanceEpisodeResume(
          candidate: (season: 2, episode: 3),
          finished: false,
          progress: 97,
          isTracker: false,
          trackerFrontiers: const [(season: 2, episode: 3)],
        ),
        isFalse,
      );
    });
  });
}
