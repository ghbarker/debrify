import 'dart:io';

import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/continue_watching_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors public [CwKind] so this pin never imports the god file or the
/// post-move units.
enum CwKind { local, trakt, simkl, mdblist, iptv }

/// G1'-4 characterisation of tracker + local continue-watching **before**
/// the move out of `search_screen.dart`.
///
/// Pin commit must stay green on its own and must not import
/// `continue_watching_controller.dart` or `continue_watching_row.dart`.
/// After the move this file still matches the same bodies (it reads the
/// new files when they exist).
///
/// Quirks pinned here (keep, do not "fix"):
/// * Generation tokens (`_cwLoadToken`, `_traktCwToken`, `_simklCwToken`,
///   `_mdblistCwToken`, `_iptvCwLoadToken`) drop a stale load after any
///   await; a newer run never has its nodes/state replaced.
/// * `_syncCwNodes` preserves the surviving prefix. Only a shrinking tail
///   is disposed; focus in that tail hands off to the last survivor.
/// * Local disabled frees nodes and clears every local map (including
///   artwork / addon ids).
/// * Trakt: `_traktCwLoading = true` is a plain assignment (initState-safe).
///   Unauthenticated clears rows. Transient error leaves existing rows and
///   only clears the loading flag. Resume refresh coalesces to 30s.
/// * `_traktReserving` requires Home board + authed + loading + empty
///   Trakt movies/series + no catalog search. Refresh with live rows
///   never shows skeletons.
/// * Simkl: `result == null` (transient) returns without clearing.
///   Disconnect returns empty lists and falls through.
/// * MDBList: `!result.isUsable` discards. Forced load stamps
///   `_mdblistCwForcedLoadAt`; `_mdblistCwForceFresh` is a 3s window.
///   Revision refresh waits for a current route (20×100ms) then 750ms.
/// * Progress: Smart keeps the row's own numbers; dedicated source
///   remaps. IPTV is exempt (routeKey, not imdbId).
/// * Merged providers ship the combined list through the MOVIES slot
///   (same row id / node list); Series row is suppressed.
/// * `_cwVisible` is allocation-free field checks, not `_cwRows`.
/// * Trakt/Simkl See-All merge sorts by paused_at newest-first;
///   timestamp-less last; ties use movies-then-shows origIndex
///   (Dart sort is not stable). MDBList sorts by updatedAt.
/// * `_seLabel` is null when season/episode is missing or ≤ 0.
/// * Card menu: IPTV series play label is "Open series"; PikPak-only
///   hides Play except IPTV. Hold-to-quick-play skips IPTV series.
///
/// Origin: `lib/screens/search_screen.dart` CW fields, `_loadContinueWatching`
/// through `_loadMdblistContinueWatching`, `_syncCwNodes`, `_cwRows` /
/// `_cwVisible` / `_traktReserving`, `_buildContinueWatchingRow`.
String _origin() {
  final controller = File(
    'lib/services/home/continue_watching_controller.dart',
  );
  final row = File('lib/widgets/home/continue_watching_row.dart');
  if (controller.existsSync() && row.existsSync()) {
    return '${controller.readAsStringSync()}\n${row.readAsStringSync()}';
  }
  // Pre-move: CW types live in the host part file.
  return File('lib/screens/search_screen.dart').readAsStringSync() +
      File('lib/screens/search/search_stage_widgets.dart').readAsStringSync();
}

/// Origin `_seLabel`.
String? seLabel(int? season, int? episode) {
  if (season == null || episode == null || season <= 0 || episode <= 0) {
    return null;
  }
  return 'S$season · E$episode';
}

/// Origin `_traktReserving`.
bool traktReserving({
  required bool searchMode,
  required bool discoverMode,
  required bool isTraktAuthenticated,
  required bool traktCwLoading,
  required bool traktMoviesEmpty,
  required bool traktSeriesEmpty,
  required String catalogQuery,
  required bool catalogSearching,
}) =>
    !searchMode &&
    !discoverMode &&
    isTraktAuthenticated &&
    traktCwLoading &&
    traktMoviesEmpty &&
    traktSeriesEmpty &&
    catalogQuery.isEmpty &&
    !catalogSearching;

/// Origin `_mdblistCwForceFresh` window.
bool mdblistCwForceFresh(DateTime? at, DateTime now) =>
    at != null && now.difference(at) < const Duration(seconds: 3);

/// Origin Progress-source remap (IPTV is never remapped).
CwKind effectiveCwKind(CwKind kind, WatchProgressSource source) {
  if (kind == CwKind.iptv) return kind;
  return switch (source) {
    WatchProgressSource.smart => kind,
    WatchProgressSource.local => CwKind.local,
    WatchProgressSource.trakt => CwKind.trakt,
    WatchProgressSource.simkl => CwKind.simkl,
    WatchProgressSource.mdblist => CwKind.mdblist,
  };
}

/// Origin local/Trakt/Simkl merge-aware movies-slot gate.
bool cwMoviesSlotVisible({
  required bool merge,
  required bool moviesEmpty,
  required bool allEmpty,
  required bool disabled,
}) => !(merge ? allEmpty : moviesEmpty) && !disabled;

/// Origin series-slot gate (suppressed when merged).
bool cwSeriesSlotVisible({
  required bool merge,
  required bool seriesEmpty,
  required bool disabled,
}) => !merge && !seriesEmpty && !disabled;

/// Origin paused_at / last-watched merge (Trakt + Simkl). Timestamp-less
/// items sort last; ties use the original movies-then-shows index.
List<T> sortByPausedAt<T>({
  required List<T> items,
  required int? Function(T) pausedAtMs,
}) {
  final origIndex = <T, int>{
    for (var i = 0; i < items.length; i++) items[i]: i,
  };
  final all = [...items];
  all.sort((a, b) {
    final pa = pausedAtMs(a);
    final pb = pausedAtMs(b);
    if (pa != null && pb != null) {
      final c = pb.compareTo(pa);
      if (c != 0) return c;
    } else if (pa == null && pb != null) {
      return 1;
    } else if (pa != null && pb == null) {
      return -1;
    }
    return origIndex[a]!.compareTo(origIndex[b]!);
  });
  return all;
}

/// Origin `_syncCwNodes` length math (no FocusNodes): grow vs shrink.
({int length, bool handoff}) syncCwNodeCount(int current, int count) {
  if (current == count) return (length: current, handoff: false);
  if (count < current) {
    return (length: count, handoff: count > 0);
  }
  return (length: count, handoff: false);
}

/// Origin card-menu play label + hold-to-quick-play gate.
({String playLabel, bool quickPlayAvailable}) cwCardMenuPlay({
  required CwKind kind,
  required bool isSeries,
  required bool playActionAvailable,
}) {
  final playLabel = (kind == CwKind.iptv && isSeries) ? 'Open series' : 'Play';
  final quickPlayAvailable =
      playActionAvailable && !(kind == CwKind.iptv && isSeries);
  return (playLabel: playLabel, quickPlayAvailable: quickPlayAvailable);
}

/// Origin play-action availability (PikPak-only hides Play except IPTV).
bool cwPlayActionAvailable({required CwKind kind, required bool pikpakOnly}) =>
    kind == CwKind.iptv || !pikpakOnly;

void main() {
  late String origin;

  setUpAll(() {
    origin = _origin();
  });

  group('origin source (G1\'-4 pin)', () {
    test('generation tokens stay on every per-source loader', () {
      expect(origin, contains(RegExp(r'_?cwLoadToken')));
      expect(origin, contains(RegExp(r'_?traktCwToken')));
      expect(origin, contains(RegExp(r'_?simklCwToken')));
      expect(origin, contains(RegExp(r'_?mdblistCwToken')));
      expect(origin, contains(RegExp(r'_?iptvCwLoadToken')));
      expect(origin, contains(RegExp(r'_?traktCwLoading')));
      expect(origin, contains(RegExp(r'_?traktReserving')));
      expect(origin, contains(RegExp(r'_?mdblistRevisionRefreshToken')));
      expect(origin, contains(RegExp(r'_?mdblistCwForcedLoadAt')));
      expect(origin, contains('Duration(seconds: 30)'));
    });

    test(
      'syncCwNodes preserves prefix and hands focus off a shrinking tail',
      () {
        expect(origin, contains(RegExp(r'void _?syncCwNodes\(')));
        expect(origin, contains('if (nodes.length == count) return'));
        expect(origin, contains('nodes.removeLast().dispose()'));
        expect(origin, contains('tailHadFocus'));
        expect(origin, contains('search_cw_'));
        expect(origin, contains('the dying node can\'t fight the handoff'));
      },
    );

    test('local disabled clears rows; trakt error leaves them', () {
      expect(origin, contains('getHomeContinueWatchingEnabled'));
      expect(origin, contains('getContinueWatchingItems'));
      expect(origin, contains('Free the focus nodes too'));
      expect(
        origin,
        contains('Leave any existing rows in place on a transient Trakt'),
      );
      expect(origin, contains('assignment, not setState'));
      expect(origin, contains('initState on cold'));
      expect(origin, contains('Null = a transient fetch failure'));
    });

    test('MDBList discard / force-fresh / revision delay stay', () {
      expect(origin, contains('!result.isUsable'));
      expect(origin, contains(RegExp(r'_?mdblistCwForceFresh')));
      expect(origin, contains('Duration(seconds: 3)'));
      expect(origin, contains('Duration(milliseconds: 750)'));
      expect(origin, contains('attempt < 20'));
      expect(origin, contains('Duration(milliseconds: 100)'));
      expect(origin, contains('synchronizeInvalidations'));
    });

    test('merge movies-slot + allocation-free _cwVisible stay', () {
      expect(origin, contains('one Continue Watching row'));
      expect(origin, contains('MOVIES slot'));
      expect(origin, contains(RegExp(r'_?cwMergeLocal')));
      expect(origin, contains(RegExp(r'_?cwMergeTrakt')));
      expect(origin, contains(RegExp(r'_?cwMergeSimkl')));
      expect(origin, contains(RegExp(r'_?cwMergeMdblist')));
      expect(origin, contains('allocation-free field'));
      expect(origin, contains('keep these conditions in lock-step'));
    });

    test('progress remap + IPTV exemption stay', () {
      expect(origin, contains('WatchProgressSource.smart'));
      expect(origin, contains('kind == CwKind.iptv'));
      expect(origin, contains('routeKey'));
      expect(origin, contains('IPTV rows are exempt'));
    });

    test('row builder + skeleton + card-menu quirks stay', () {
      expect(origin, contains('showWatchedBadge: false'));
      expect(origin, contains('cacheExtent: 400'));
      expect(origin, contains('Trakt Continue Watching'));
      expect(origin, contains('Open series'));
      expect(origin, contains('holdToQuickPlay'));
      expect(origin, contains('PikPak-only'));
    });
  });

  group('pure origin algorithms (G1\'-4 pin)', () {
    test('seLabel is null for missing or non-positive season/episode', () {
      expect(seLabel(2, 5), 'S2 · E5');
      expect(seLabel(null, 1), isNull);
      expect(seLabel(1, null), isNull);
      expect(seLabel(0, 1), isNull);
      expect(seLabel(1, 0), isNull);
      expect(seLabel(-1, 2), isNull);
    });

    test('traktReserving is Home-only, authed, loading, empty, no search', () {
      expect(
        traktReserving(
          searchMode: false,
          discoverMode: false,
          isTraktAuthenticated: true,
          traktCwLoading: true,
          traktMoviesEmpty: true,
          traktSeriesEmpty: true,
          catalogQuery: '',
          catalogSearching: false,
        ),
        isTrue,
      );
      expect(
        traktReserving(
          searchMode: true,
          discoverMode: false,
          isTraktAuthenticated: true,
          traktCwLoading: true,
          traktMoviesEmpty: true,
          traktSeriesEmpty: true,
          catalogQuery: '',
          catalogSearching: false,
        ),
        isFalse,
      );
      expect(
        traktReserving(
          searchMode: false,
          discoverMode: false,
          isTraktAuthenticated: true,
          traktCwLoading: true,
          traktMoviesEmpty: false,
          traktSeriesEmpty: true,
          catalogQuery: '',
          catalogSearching: false,
        ),
        isFalse,
        reason: 'live rows must not stack skeletons',
      );
      expect(
        traktReserving(
          searchMode: false,
          discoverMode: false,
          isTraktAuthenticated: true,
          traktCwLoading: false,
          traktMoviesEmpty: true,
          traktSeriesEmpty: true,
          catalogQuery: '',
          catalogSearching: false,
        ),
        isFalse,
      );
    });

    test('MDBList force-fresh window is 3 seconds, exclusive of the edge', () {
      final at = DateTime(2026, 9, 5, 1, 0, 0);
      expect(mdblistCwForceFresh(null, at), isFalse);
      expect(
        mdblistCwForceFresh(at, at.add(const Duration(seconds: 2))),
        isTrue,
      );
      expect(
        mdblistCwForceFresh(at, at.add(const Duration(seconds: 3))),
        isFalse,
      );
    });

    test('progress source remaps every kind except IPTV', () {
      expect(
        effectiveCwKind(CwKind.trakt, WatchProgressSource.local),
        CwKind.local,
      );
      expect(
        effectiveCwKind(CwKind.local, WatchProgressSource.smart),
        CwKind.local,
      );
      expect(
        effectiveCwKind(CwKind.iptv, WatchProgressSource.trakt),
        CwKind.iptv,
      );
      expect(
        effectiveCwKind(CwKind.simkl, WatchProgressSource.mdblist),
        CwKind.mdblist,
      );
    });

    test('merged providers use the movies slot; series is suppressed', () {
      expect(
        cwMoviesSlotVisible(
          merge: true,
          moviesEmpty: true,
          allEmpty: false,
          disabled: false,
        ),
        isTrue,
      );
      expect(
        cwSeriesSlotVisible(merge: true, seriesEmpty: false, disabled: false),
        isFalse,
      );
      expect(
        cwSeriesSlotVisible(merge: false, seriesEmpty: false, disabled: false),
        isTrue,
      );
      expect(
        cwMoviesSlotVisible(
          merge: false,
          moviesEmpty: true,
          allEmpty: false,
          disabled: false,
        ),
        isFalse,
      );
    });

    test(
      'paused_at sort: newest first, timestamp-less last, origIndex ties',
      () {
        const a = (id: 'a', ms: 10);
        const b = (id: 'b', ms: 30);
        const c = (id: 'c', ms: null);
        const d = (id: 'd', ms: 30);
        final sorted = sortByPausedAt(
          items: [a, b, c, d],
          pausedAtMs: (e) => e.ms,
        );
        expect(sorted.map((e) => e.id).toList(), ['b', 'd', 'a', 'c']);
      },
    );

    test('syncCwNodes only hands off when a shrinking tail had a survivor', () {
      expect(syncCwNodeCount(3, 3), (length: 3, handoff: false));
      expect(syncCwNodeCount(3, 5), (length: 5, handoff: false));
      expect(syncCwNodeCount(3, 1), (length: 1, handoff: true));
      expect(syncCwNodeCount(3, 0), (length: 0, handoff: false));
    });

    test('IPTV series play is Open series and skips hold-to-quick-play', () {
      final iptvSeries = cwCardMenuPlay(
        kind: CwKind.iptv,
        isSeries: true,
        playActionAvailable: true,
      );
      expect(iptvSeries.playLabel, 'Open series');
      expect(iptvSeries.quickPlayAvailable, isFalse);

      final localMovie = cwCardMenuPlay(
        kind: CwKind.local,
        isSeries: false,
        playActionAvailable: true,
      );
      expect(localMovie.playLabel, 'Play');
      expect(localMovie.quickPlayAvailable, isTrue);

      expect(
        cwPlayActionAvailable(kind: CwKind.trakt, pikpakOnly: true),
        isFalse,
      );
      expect(
        cwPlayActionAvailable(kind: CwKind.iptv, pikpakOnly: true),
        isTrue,
      );
    });

    test('minutes-left helpers stay the shared presentation functions', () {
      expect(
        continueWatchingMinutesLeft(
          positionMs: 30 * Duration.millisecondsPerMinute,
          durationMs: 60 * Duration.millisecondsPerMinute,
        ),
        30,
      );
      expect(
        continueWatchingMinutesLeftFromProgress(
          progress: 50,
          runtimeMinutes: 100,
        ),
        50,
      );
    });

    test('CwKind members stay the five origin sources', () {
      expect(
        origin,
        contains('enum CwKind { local, trakt, simkl, mdblist, iptv }'),
      );
    });
  });
}
