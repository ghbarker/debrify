import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:flutter/foundation.dart';

import '../../models/advanced_search_selection.dart';
import '../../models/stremio_addon.dart';
import '../../utils/episode_progress_merge.dart';
import '../episode_tracker_snapshot_revision.dart';
import '../mdblist/mdblist_continue_watching_service.dart';
import '../next_episode_service.dart';
import '../simkl/simkl_service.dart';
import '../tracking_source_policy.dart';
import '../trakt/trakt_continue_watching_service.dart';

/// Ready-to-launch catalog selection. Same object the host already played
/// (`AdvancedSearchSelection`); named here so the G1'-1 seam is
/// meta + snapshots → [PlaySelection] / [ResumeInfo].
typedef PlaySelection = AdvancedSearchSelection;

/// Detail-button label: whether Play would resume, and where.
typedef ResumeInfo = ({bool started, int? season, int? episode});

/// Promised episode from the merged-page label. Wins over reconcile.
typedef PromisedTarget = ({bool started, int season, int episode});

/// Reconciled series-resume answer (2026-08-25 redesign).
typedef SeriesResume = ({
  bool started,
  int season,
  int episode,
  double? simklProgress,
  AdvancedSearchSelection? selection,
  int? sourcePrio,
});

/// Host-facing result of `_onCatalogPlay`'s resolve half.
sealed class CatalogPlayDecision {
  const CatalogPlayDecision();
}

/// Play or browse this [PlaySelection] (`browseSourcesOnly` → Sources).
final class CatalogPlayLaunch extends CatalogPlayDecision {
  const CatalogPlayLaunch(this.selection, {this.browseSourcesOnly = false});
  final PlaySelection selection;
  final bool browseSourcesOnly;
}

/// No-IMDb series: host opens the episode picker (except merged-page skip).
final class CatalogPlayOpenEpisodes extends CatalogPlayDecision {
  const CatalogPlayOpenEpisodes({
    required this.item,
    required this.addon,
    required this.isTraktSource,
    required this.isMdblistSource,
  });
  final StremioMeta item;
  final StremioAddon addon;
  final bool isTraktSource;
  final bool isMdblistSource;
}

/// Cancelled, unmounted, or no launch.
final class CatalogPlayAborted extends CatalogPlayDecision {
  const CatalogPlayAborted();
}

/// Play/browse selection — origin `_onCatalogBrowse`.
final class CatalogBrowseDecision {
  const CatalogBrowseDecision._({this.openEpisodes = false, this.selection});
  factory CatalogBrowseDecision.episodes() =>
      const CatalogBrowseDecision._(openEpisodes: true);
  factory CatalogBrowseDecision.movie(PlaySelection selection) =>
      CatalogBrowseDecision._(selection: selection);
  final bool openEpisodes;
  final PlaySelection? selection;
}

/// Catalog play/resume resolver extracted from `search_screen.dart` (G1'-1).
///
/// Inputs: catalog meta, tracker snapshots (`traktByImdb`), auth flags,
/// bound-source-aware ids. Outputs: [PlaySelection] / [ResumeInfo].
/// Pure Dart — no host-State privates, no part-file or State extension.
class CatalogPlayResolver {
  CatalogPlayResolver({
    required this.isTraktAuthenticated,
    required this.isSimklAuthenticated,
    required this.isMdblistAuthenticated,
    required this.traktByImdb,
    required this.imdbOf,
  });

  final bool Function() isTraktAuthenticated;
  final bool Function() isSimklAuthenticated;
  final bool Function() isMdblistAuthenticated;
  final Map<String, TraktContinueWatchingItem> traktByImdb;
  final String? Function(StremioMeta item) imdbOf;

  // ── Reconciled series resume ──────────────────────────────────────────────
  // ONE answer per title for "where does Resume land", shared VERBATIM by the
  // button label (resolveResumeInfo) and Play (resolvePlay) via a short
  // cache — so a tracker call that flakes between page-open and button-press
  // can never make the pill advertise one episode and playback open another.
  final Map<String, ({int atMs, String rev, SeriesResume r})>
  seriesResumeCache = {};

  /// Short-TTL memo for [traktMoviePercent]: the Resume label
  /// (resolveResumeInfo) and the Play press (resolvePlay) both need the
  /// percent seconds apart, and resolveSelection has no cache of its own — so
  /// without this every detail open cost two identical /sync/playback/movies
  /// fetches and Play blocked on the second. TTL matches SimklService's own
  /// 30s playback cache (which already gives the Simkl helper this behavior).
  final Map<String, (double?, DateTime)> traktMoviePctMemo = {};

  void clearSeriesResumeCache() => seriesResumeCache.clear();

  /// Combined cache identity: per-title tracker revisions (any scrobble/
  /// watched write bumps its provider's counter, so a cached reconciled
  /// answer is invalidated the moment a tracker mutation lands) PLUS the
  /// tracker-availability flags — auth settling, a connect/disconnect, or a
  /// Trakt-sourced reopen must recompute rather than reuse an answer built
  /// from a different set of eligible sources.
  String seriesResumeRev(
    String playId,
    bool isTraktSource,
    WatchProgressSource progressSource,
  ) =>
      '${EpisodeTrackerSnapshotRevision.identity('trakt', playId)}.'
      '${EpisodeTrackerSnapshotRevision.identity('simkl', playId)}.'
      '${EpisodeTrackerSnapshotRevision.identity('mdblist', playId)}.'
      // 'local' is bumped by in-page local-only mark watched/unwatched — the
      // one resume input with no tracker revision of its own.
      '${EpisodeTrackerSnapshotRevision.identity('local', playId)}.'
      '${isTraktAuthenticated() ? 1 : 0}${isSimklAuthenticated() ? 1 : 0}'
      '${isMdblistAuthenticated() ? 1 : 0}${isTraktSource ? 1 : 0}.'
      '${progressSource.name}';

  /// `_onCatalogPlay` resolve half: meta + snapshots → [PlaySelection] (or
  /// episode-picker / abort). Host keeps overlay, active addon id, launch.
  Future<CatalogPlayDecision> resolvePlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool skipEpisodeFallback = false,
    bool preferTraktResume = false,
    PromisedTarget? promisedTarget,
    bool browseSourcesOnly = false,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final trackingPolicy = await TrackingSourcePolicy.load();
    debugPrint(
      '[SeriesResume] play-pressed title="${item.name}" '
      'id=${item.effectiveImdbId ?? item.id} type=${item.type} '
      'traktSource=$isTraktSource mdblistSource=$isMdblistSource '
      'preferTrackerResume=$preferTraktResume',
    );

    if (isMdblistSource &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final owned = await mdblistResumeItemFor(item);
      if (cancelled()) return const CatalogPlayAborted();
      if (owned != null) {
        // This fast path skips the reconciler entirely, so it needs its own
        // promise check — otherwise an in-page watched mutation moves the
        // label while MDBList still reports the previous continue-watching
        // coordinate, and Resume replays the episode the label moved past.
        final p = promisedTarget;
        final stale =
            p != null &&
            (owned.selection.season != p.season ||
                owned.selection.episode != p.episode);
        if (!stale) {
          return CatalogPlayLaunch(
            owned.selection,
            browseSourcesOnly: browseSourcesOnly,
          );
        }
        debugPrint(
          '[SeriesResume] play-mdblist-fastpath-skipped title="${item.name}" '
          'owned=S${owned.selection.season}E${owned.selection.episode} '
          'promised=S${p.season}E${p.episode}',
        );
        // Fall through to the reconciled/promised path below.
      }
    }

    // Series on the detail Resume flow (or Trakt-sourced): the SAME
    // reconciled answer the label used (cached ~45s), so the pill and the
    // playback can never land on different episodes — recency across
    // trackers + local, watched-advance; see reconcileSeriesResume.
    if (item.type == 'series' && (preferTraktResume || isTraktSource)) {
      final r = await reconcileSeriesResume(item, isTraktSource: isTraktSource);
      if (cancelled()) return const CatalogPlayAborted();
      // The caller's button already promised an episode the reconciler can't
      // see. Honor it: the label is the promise the user acted on, and a
      // silent disagreement here replays an episode they already watched.
      final promised = promisedTarget;
      final overridden =
          promised != null &&
          (promised.season != r.season || promised.episode != r.episode);
      if (overridden) {
        debugPrint(
          '[SeriesResume] play-promise-override title="${item.name}" '
          'reconciled=S${r.season}E${r.episode}/started=${r.started} '
          'promised=S${promised.season}E${promised.episode}',
        );
      }
      // Winner's original selection (Trakt or MDBList) — launches with its
      // own progress percent intact. Unusable once overridden: it points at
      // the older coordinate, so it would re-open the episode we just moved
      // past, carrying that episode's resume percent with it.
      if (!overridden && r.selection != null) {
        return CatalogPlayLaunch(
          r.selection!,
          browseSourcesOnly: browseSourcesOnly,
        );
      }
      final rTtId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
      final rTracker = (r.sourcePrio ?? 3) <= 2;
      // A promise IS started-evidence — it is what made the button read
      // "Resume". Without this, the empty-candidates fallback (started=false)
      // drops through to the S01E01 tail below. Keyed on the promise itself
      // rather than on [overridden]: when the promised coordinate happens to
      // MATCH the reconciler's fallback, there is no override, yet the button
      // still said "Resume" and must not fall through.
      final started = r.started || (promised?.started ?? false);
      if (started && (rTtId.isNotEmpty || skipEpisodeFallback || rTracker)) {
        return CatalogPlayLaunch(
          AdvancedSearchSelection(
            imdbId: rTtId.isNotEmpty
                ? rTtId
                : (item.effectiveImdbId ?? item.id),
            isSeries: true,
            title: item.name,
            year: item.year,
            season: overridden ? promised.season : r.season,
            episode: overridden ? promised.episode : r.episode,
            contentType: item.type,
            posterUrl: item.poster,
            // Source flags from the WINNING provider (advanced or not) so
            // player scrobbling attribution follows the tracker that owned
            // the resume — not from how the page happened to be opened.
            traktSource: isTraktSource || r.sourcePrio == 0,
            // Belongs to the reconciled coordinate — carrying it onto a
            // different episode would seek the new one to a stale position.
            simklProgressPercent: overridden ? null : r.simklProgress,
            simklSource: r.sourcePrio == 1,
            // `isMdblistSource ||` mirrors the traktSource term above: when
            // the MDBList fast path is skipped as stale, the reconciler's
            // winner is usually the local candidate, and without this the
            // play would silently stop attributing to MDBList.
            mdblistSource: isMdblistSource || r.sourcePrio == 2,
          ),
          browseSourcesOnly: browseSourcesOnly,
        );
      }
      // Not started (or no usable id): fall through to the shared tail —
      // episode-picker fallback for id-less shows, default S01E01 otherwise.
    }

    // Trakt-sourced MOVIE keeps its cached-CW fast path (series resolve
    // through the reconciler above).
    if (item.type != 'series' &&
        isTraktSource &&
        trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final cw = traktByImdb[item.effectiveImdbId] ?? traktByImdb[item.id];
      if (cw != null) {
        final sel = await TraktContinueWatchingService.instance
            .selectionForItem(cw);
        if (cancelled()) return const CatalogPlayAborted();
        if (sel != null) {
          return CatalogPlayLaunch(sel, browseSourcesOnly: browseSourcesOnly);
        }
      }
    }

    if (item.type != 'series') {
      // Cross-device movie resume: on the detail-page Play/Resume flow
      // (preferTraktResume, or a tracker-sourced open), pull the movie's paused
      // tracker position and carry it on the selection. The player's resume
      // reconciliation then seeks the furthest of trakt%/simkl%/local — so a
      // movie paused on another device resumes here even when opened from a
      // plain catalog result (previously movies started at 00:00). Row
      // quick-play (no preferTraktResume) keeps its local-only resume.
      double? traktPct;
      double? simklPct;
      double? mdblistPct;
      if (preferTraktResume || isTraktSource) {
        // Concurrent and individually time-boxed: the Play press must never
        // stall behind a degraded tracker API (sequential awaits here could
        // previously block playback for the full HTTP timeouts). On timeout we
        // launch with local-only resume — the reconciliation in the player
        // degrades gracefully to the local position.
        final lookups = await Future.wait<double?>([
          trackingPolicy.progressFrom(TrackingSource.trakt) &&
                  (isTraktAuthenticated() || isTraktSource)
              ? traktMoviePercent(
                  item,
                ).timeout(const Duration(seconds: 4), onTimeout: () => null)
              : Future<double?>.value(null),
          trackingPolicy.progressFrom(TrackingSource.simkl) &&
                  isSimklAuthenticated()
              ? simklMoviePercent(
                  item,
                ).timeout(const Duration(seconds: 4), onTimeout: () => null)
              : Future<double?>.value(null),
          trackingPolicy.progressFrom(TrackingSource.mdblist) &&
                  isMdblistAuthenticated()
              ? mdblistMoviePercent(
                  item,
                ).timeout(const Duration(seconds: 4), onTimeout: () => null)
              : Future<double?>.value(null),
        ]);
        if (cancelled()) return const CatalogPlayAborted();
        traktPct = lookups[0];
        simklPct = lookups[1];
        mdblistPct = lookups[2];
      }
      // Rewatch (Simkl): a movie already marked `completed` on Simkl has no
      // resume session, and Simkl won't create one on replay — so it can never
      // re-enter Continue Watching. On the detail Play/Resume flow (the
      // "Rewatch" button surface, preferTraktResume), un-mark it watched first
      // so the upcoming catalog scrobble creates a fresh resume session; the
      // ≥80% stop re-marks it completed when the rewatch finishes. Gated on the
      // sync setting + auth so we never un-complete a movie that won't actually
      // be re-tracked. Row quick-play (no preferTraktResume) is left untouched.
      // WRITE-side action: gated on auth + the Scrobble master (below), NOT
      // the Progress source — a This-device user scrobbling to Simkl still
      // needs the replay session created.
      if (preferTraktResume && isSimklAuthenticated()) {
        // Same id resolution the detail screen's status loader uses (_imdbOf),
        // so the "Rewatch" label and this flip never disagree on the title.
        final imdb = imdbOf(item);
        final scrobblesSimkl = trackingPolicy.scrobbles(TrackingSource.simkl);
        if (cancelled()) return const CatalogPlayAborted();
        if (imdb != null && scrobblesSimkl) {
          // Time-boxed like the tracker-percent lookups above: a degraded Simkl
          // API must never stall the Play press. On timeout we just skip the
          // flip — worst case the rewatch doesn't surface in Continue Watching,
          // exactly today's behaviour.
          final status = await SimklService.instance
              .fetchTitleStatus(imdb)
              .timeout(const Duration(seconds: 4), onTimeout: () => null);
          if (cancelled()) return const CatalogPlayAborted();
          if (status?.currentStatus == 'completed') {
            await SimklService.instance
                .markUnwatched(imdb, 'movie')
                .timeout(const Duration(seconds: 4), onTimeout: () => false);
            if (cancelled()) return const CatalogPlayAborted();
          }
        }
      }
      // Keep the detail page underneath — the cinematic loading overlay covers
      // it, and after playback Back returns to the detail (like Home).
      return CatalogPlayLaunch(
        movieSelection(
          item,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
          traktProgressPercent: traktPct,
          simklProgressPercent: simklPct,
          mdblistProgressPercent: mdblistPct,
        ),
        browseSourcesOnly: browseSourcesOnly,
      );
    }

    final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    // Without an IMDb id we can't search torrents for a specific episode, so
    // fall back to the manual episode picker — except from the merged page
    // (episodes are inline there), where we play via the raw id's addon stream.
    if (ttId.isEmpty && !skipEpisodeFallback) {
      if (!cancelled()) {
        return CatalogPlayOpenEpisodes(
          item: item,
          addon: addon,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        );
      }
      return const CatalogPlayAborted();
    }
    // Play id: the `tt…` id when present (torrent-resolvable); otherwise the raw
    // catalog id, which playFromSelection routes to the addon /stream endpoint.
    final playId = ttId.isNotEmpty ? ttId : (item.effectiveImdbId ?? item.id);

    // Resolve where to resume, mirroring EpisodesScreen's landing logic:
    // last-played episode for this show (by imdbId, then by title), else S01E01.
    int? season;
    int? episode;
    final byId = trackingPolicy.progressFrom(TrackingSource.local)
        ? await PlaybackProgressStore.getLastPlayedEpisodeByImdbId(playId)
        : null;
    season = byId?['season'] as int?;
    episode = byId?['episode'] as int?;
    final lastFinished = byId?['finished'] == true;
    if (season == null || episode == null) {
      final byTitle = trackingPolicy.progressFrom(TrackingSource.local)
          ? await PlaybackProgressStore.getLastPlayedEpisode(seriesTitle: item.name)
          : null;
      season ??= byTitle?['season'] as int?;
      episode ??= byTitle?['episode'] as int?;
    }
    // No local history — last resort: Simkl's next-to-watch, mirroring the
    // label (resolveResumeInfo) so the two agree. Only on the detail Resume
    // flow, and TIME-BOXED (4s) like the movie branch so a slow Simkl API never
    // freezes the Play press — on timeout it falls through to S01E01.
    if ((season == null || episode == null) &&
        isSimklAuthenticated() &&
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
        preferTraktResume) {
      final next = await simklNextToWatchFor(
        item,
      ).timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (cancelled()) return const CatalogPlayAborted();
      if (next != null) {
        season = next.season;
        episode = next.episode;
      }
    }
    if ((season == null || episode == null) &&
        isMdblistAuthenticated() &&
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
        preferTraktResume) {
      final next = await mdblistResumeItemFor(
        item,
      ).timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (cancelled()) return const CatalogPlayAborted();
      if (next != null) {
        season = next.selection.season;
        episode = next.selection.episode;
      }
    }
    season ??= 1;
    episode ??= 1;
    // If the last-played episode is finished, resume the NEXT one instead of
    // re-opening it — parity with the deprecated home's continue-watching
    // quick-play (only the local, non-Trakt path; Trakt resolves its own next).
    if (lastFinished) {
      final next = await NextEpisodeService.findNextEpisode(
        playId,
        season,
        episode,
      );
      if (cancelled()) return const CatalogPlayAborted();
      if (next != null) {
        season = next.season;
        episode = next.episode;
      }
    }
    if (cancelled()) return const CatalogPlayAborted();

    return CatalogPlayLaunch(
      AdvancedSearchSelection(
        imdbId: playId,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: season,
        episode: episode,
        contentType: item.type,
        posterUrl: item.poster,
        traktSource: isTraktSource,
        mdblistSource: isMdblistSource,
      ),
      browseSourcesOnly: browseSourcesOnly,
    );
  }

  /// The reconciled series-resume answer (2026-08-25 redesign — fixes the
  /// home-card / pill / Play three-way disagreement):
  ///
  ///  - Candidates are gathered CONCURRENTLY, each 4s-boxed: Trakt paused/next
  ///    (when connected or Trakt-sourced), Simkl's newest paused session (with
  ///    `paused_at`), MDBList's paused entry (with `updatedAt`), and local
  ///    last-played (with its own timestamp).
  ///  - RECENCY wins, not fixed priority: any candidate carrying a timestamp
  ///    beats every timestampless one, newest first; timestampless candidates
  ///    fall back to the legacy order (Trakt → Simkl → MDBList → local). A
  ///    stale tracker session — orphaned by a failed scrobble stop — can no
  ///    longer outrank last night's actual position.
  ///  - A winner that is effectively DONE (locally finished, or progress ≥ 80,
  ///    the trackers' own watched threshold) advances to the next episode:
  ///    guide-aware [NextEpisodeService] first (handles season boundaries),
  ///    Simkl's server-computed `next_to_watch` as backup — the same signal
  ///    the home Continue Watching card shows, so the surfaces agree.
  ///  - Nothing anywhere: `next_to_watch` → MDBList CW coordinate → an
  ///    unstarted S01E01.
  /// `sourcePrio` names the winning provider (0 Trakt, 1 Simkl, 2 MDBList,
  /// 3 local, null fallback/none) — Play stamps the rebuilt selection's
  /// source flags from it, so an ADVANCED tracker winner keeps its player
  /// scrobbling attribution. The launcher's shared normalization still applies
  /// the independent Scrobble masters before any write reaches a tracker.
  Future<SeriesResume> reconcileSeriesResume(
    StremioMeta item, {
    bool isTraktSource = false,
  }) async {
    final trackingPolicy = await TrackingSourcePolicy.load();
    final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    final playId = ttId.isNotEmpty ? ttId : (item.effectiveImdbId ?? item.id);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rev = seriesResumeRev(
      playId,
      isTraktSource,
      trackingPolicy.progressSource,
    );
    final hit = seriesResumeCache[playId];
    if (hit != null && nowMs - hit.atMs < 45000 && hit.rev == rev) {
      debugPrint(
        '[SeriesResume] reconcile-cache-hit title="${item.name}" '
        'id=$playId ageMs=${nowMs - hit.atMs} rev=$rev '
        'result=S${hit.r.season}E${hit.r.episode} '
        'started=${hit.r.started} source=${resumeSourceName(hit.r.sourcePrio)}',
      );
      return hit.r;
    }
    debugPrint(
      '[SeriesResume] reconcile-start title="${item.name}" id=$playId '
      'rawId=${item.id} effectiveId=${item.effectiveImdbId} '
      'traktAuth=${isTraktAuthenticated()} simklAuth=${isSimklAuthenticated()} '
      'mdblistAuth=${isMdblistAuthenticated()} traktSource=$isTraktSource '
      'rev=$rev cache=${hit == null ? 'miss' : 'stale-or-revised'}',
    );
    seriesResumeCache.removeWhere((_, v) => nowMs - v.atMs >= 45000);

    // Kick everything off together; a degraded tracker API must never stall
    // the Play press (same 4s boxes the old chain used).
    final traktF =
        trackingPolicy.progressFrom(TrackingSource.trakt) &&
            (isTraktAuthenticated() || isTraktSource)
        ? traktSelectionFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<({AdvancedSearchSelection sel, int? tsMs})?>.value(null);
    final simklF =
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
            isSimklAuthenticated()
        ? simklResumeFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<
            ({int season, int episode, double? progress, DateTime? pausedAt})?
          >.value(null);
    final mdbF =
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
            isMdblistAuthenticated()
        ? mdblistResumeItemFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<MdblistContinueWatchingItem?>.value(null);
    final localF = trackingPolicy.progressFrom(TrackingSource.local)
        ? localSeriesResumeFor(item, playId)
        : Future<
            ({int season, int episode, double? pct, int? tsMs, bool finished})?
          >.value(null);
    final nextF =
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
            isSimklAuthenticated()
        ? simklNextToWatchFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<({int season, int episode})?>.value(null);

    final trakt = await traktF;
    final simkl = await simklF;
    final mdb = await mdbF;
    final local = await localF;
    final simklNext = await nextF;

    debugPrint(
      '[SeriesResume] reconcile-inputs title="${item.name}" id=$playId '
      'trakt=${formatTraktResume(trakt)} '
      'simkl=${formatSimklResume(simkl)} '
      'mdblist=${formatMdblistResume(mdb)} '
      'local=${formatLocalResume(local)} '
      'simklNext=${simklNext == null ? 'none' : 'S${simklNext.season}E${simklNext.episode}'}',
    );

    final candidates =
        <
          ({
            int prio,
            int? tsMs,
            int s,
            int e,
            double? pct,
            bool finished,
            AdvancedSearchSelection? sel,
          })
        >[];
    if (trakt != null &&
        trakt.sel.season != null &&
        trakt.sel.episode != null) {
      candidates.add((
        prio: 0,
        // Trakt's own activity timestamp.
        tsMs: trakt.tsMs,
        s: trakt.sel.season!,
        e: trakt.sel.episode!,
        pct: trakt.sel.traktProgressPercent,
        finished: false,
        sel: trakt.sel,
      ));
    }
    if (simkl != null) {
      candidates.add((
        prio: 1,
        tsMs: simkl.pausedAt?.millisecondsSinceEpoch,
        s: simkl.season,
        e: simkl.episode,
        pct: simkl.progress,
        finished: false,
        sel: null,
      ));
    }
    final mdbSel = mdb?.selection;
    if (mdb != null &&
        mdb.paused &&
        mdbSel!.season != null &&
        mdbSel.episode != null) {
      candidates.add((
        prio: 2,
        tsMs: mdb.updatedAt?.millisecondsSinceEpoch,
        s: mdbSel.season!,
        e: mdbSel.episode!,
        pct: mdbSel.mdblistProgressPercent,
        // The winner's ORIGINAL selection so a launch keeps its progress
        // percent (a rebuilt coordinate would restart at the local offset).
        finished: false,
        sel: mdbSel,
      ));
    }
    if (local != null) {
      candidates.add((
        prio: 3,
        tsMs: local.tsMs,
        s: local.season,
        e: local.episode,
        pct: local.pct,
        finished: local.finished,
        sel: null,
      ));
    }

    SeriesResume result;
    if (candidates.isEmpty) {
      // Fresh device / nothing anywhere. next_to_watch matches the home card;
      // the MDBList CW coordinate is the weaker backup (same as the old tail).
      if (simklNext != null) {
        result = (
          started: true,
          season: simklNext.season,
          episode: simklNext.episode,
          simklProgress: null,
          selection: null,
          sourcePrio: null,
        );
      } else if (mdbSel?.season != null && mdbSel?.episode != null) {
        result = (
          started: true,
          season: mdbSel!.season!,
          episode: mdbSel.episode!,
          simklProgress: null,
          selection: null,
          sourcePrio: null,
        );
      } else {
        result = (
          started: false,
          season: 1,
          episode: 1,
          simklProgress: null,
          selection: null,
          sourcePrio: null,
        );
      }
    } else {
      candidates.sort((a, b) {
        final at = a.tsMs;
        final bt = b.tsMs;
        if (at != null && bt != null) return bt.compareTo(at);
        if (at != null) return -1;
        if (bt != null) return 1;
        return a.prio.compareTo(b.prio);
      });
      final w = candidates.first;
      var season = w.s;
      var episode = w.e;
      var selection = w.sel;
      var simklProgress = w.prio == 1 ? w.pct : null;
      final isTracker = w.prio <= 2;
      final sourcePrio = w.prio;
      // Advance rules. Tracker sessions at ≥80% are the orphan pattern the
      // trackers themselves treat as watched — advance. A LOCAL position at
      // ≥80% only advances when the player marked it finished OR a tracker's
      // resume/up-next frontier confirms the episode is behind it. A local-only
      // pause in the last stretch stays resumable in place.
      final trackerFrontiers = <EpisodeCoordinate>[
        for (final candidate in candidates)
          if (candidate.prio <= 2) (season: candidate.s, episode: candidate.e),
        if (simklNext != null)
          (season: simklNext.season, episode: simklNext.episode),
      ];
      final trackerFrontierAhead = trackerFrontiers.any(
        (frontier) =>
            frontier.season > season ||
            (frontier.season == season && frontier.episode > episode),
      );
      final done = shouldAdvanceEpisodeResume(
        candidate: (season: season, episode: episode),
        finished: w.finished,
        progress: w.pct,
        isTracker: isTracker,
        trackerFrontiers: trackerFrontiers,
      );
      debugPrint(
        '[SeriesResume] reconcile-winner title="${item.name}" id=$playId '
        'source=${resumeSourceName(w.prio)} base=S${w.s}E${w.e} '
        'pct=${w.pct} timestamp=${formatResumeTimestamp(w.tsMs)} '
        'finished=${w.finished} trackerFrontierAhead=$trackerFrontierAhead '
        'willAdvance=$done '
        'progressPolicy=${trackingPolicy.progressSource.name}',
      );
      if (done) {
        // 4s-boxed like every other network hop here: the guide fetch's body
        // read is otherwise unbounded, and the PLAY path has no outer box —
        // a stalled read would hang the press. Timeout → null → the defined
        // "keep the winner / adjacent tracker frontier" fallback.
        final next = await NextEpisodeService.findNextEpisode(
          playId,
          season,
          episode,
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        // A tracker-frontier backup is safe ONLY when it is the winner's direct
        // successor. A frontier can be seasons ahead during a rewatch; trusting
        // that blindly when the guide flakes would teleport the rewatch.
        EpisodeCoordinate? adjacentTrackerFrontier;
        for (final frontier in trackerFrontiers) {
          final isDirectSuccessor =
              (frontier.season == season && frontier.episode == episode + 1) ||
              (frontier.season == season + 1 && frontier.episode == 1);
          if (isDirectSuccessor) {
            adjacentTrackerFrontier = frontier;
            break;
          }
        }
        final target = next ?? adjacentTrackerFrontier;
        debugPrint(
          '[SeriesResume] reconcile-advance title="${item.name}" id=$playId '
          'guideNext=${next == null ? 'none' : 'S${next.season}E${next.episode}'} '
          'adjacentTracker=${adjacentTrackerFrontier == null ? 'none' : 'S${adjacentTrackerFrontier.season}E${adjacentTrackerFrontier.episode}'} '
          'chosen=${target == null ? 'keep-S${w.s}E${w.e}' : 'S${target.season}E${target.episode}'}',
        );
        if (target != null) {
          season = target.season;
          episode = target.episode;
          selection = null;
          simklProgress = null;
        }
        // Both unknown (finale / no guide): keep the winner — playing its tail
        // is still truer than inventing an episode.
      }
      result = (
        started: true,
        season: season,
        episode: episode,
        simklProgress: simklProgress,
        selection: selection,
        // The BASE winner's provider survives an advance on purpose — the
        // next episode should scrobble to the tracker that owned the resume.
        sourcePrio: sourcePrio,
      );
    }
    debugPrint(
      '[SeriesResume] reconcile-result title="${item.name}" id=$playId '
      'started=${result.started} target=S${result.season}E${result.episode} '
      'source=${resumeSourceName(result.sourcePrio)} '
      'hasOriginalSelection=${result.selection != null} '
      'simklPct=${result.simklProgress}',
    );
    seriesResumeCache[playId] = (atMs: nowMs, rev: rev, r: result);
    return result;
  }

  String resumeSourceName(int? priority) => switch (priority) {
    0 => 'trakt',
    1 => 'simkl',
    2 => 'mdblist',
    3 => 'local',
    _ => 'fallback',
  };

  String formatResumeTimestamp(int? timestampMs) {
    if (timestampMs == null) return 'none';
    return DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String();
  }

  String formatTraktResume(({AdvancedSearchSelection sel, int? tsMs})? value) {
    if (value == null) return 'none';
    return 'S${value.sel.season}E${value.sel.episode}'
        '/pct=${value.sel.traktProgressPercent}'
        '/at=${formatResumeTimestamp(value.tsMs)}';
  }

  String formatSimklResume(
    ({int season, int episode, double? progress, DateTime? pausedAt})? value,
  ) {
    if (value == null) return 'none';
    return 'S${value.season}E${value.episode}'
        '/pct=${value.progress}'
        '/at=${value.pausedAt?.toIso8601String() ?? 'none'}';
  }

  String formatMdblistResume(MdblistContinueWatchingItem? value) {
    if (value == null) return 'none';
    return 'S${value.selection.season}E${value.selection.episode}'
        '/pct=${value.selection.mdblistProgressPercent}'
        '/paused=${value.paused}'
        '/at=${value.updatedAt?.toIso8601String() ?? 'none'}';
  }

  String formatLocalResume(
    ({int season, int episode, double? pct, int? tsMs, bool finished})? value,
  ) {
    if (value == null) return 'none';
    return 'S${value.season}E${value.episode}'
        '/pct=${value.pct}'
        '/finished=${value.finished}'
        '/at=${formatResumeTimestamp(value.tsMs)}';
  }

  /// Trakt candidate for the reconciler — the full ready-to-play selection
  /// (paused/next episode with Trakt progress) PLUS the item's `paused_at`,
  /// so a Trakt pause competes on recency like every other source. A Trakt
  /// win launches the exact selection Trakt resolved, never a re-derived
  /// coordinate.
  Future<({AdvancedSearchSelection sel, int? tsMs})?> traktSelectionFor(
    StremioMeta item,
  ) async {
    final cached = traktByImdb[item.effectiveImdbId] ?? traktByImdb[item.id];
    if (cached != null) {
      debugPrint(
        '[SeriesResume] trakt-home-card-hit title="${item.name}" '
        'lookupId=${item.effectiveImdbId ?? item.id} cardId=${cached.id} '
        'card=S${cached.season}E${cached.episode} '
        'cardPct=${cached.progress} '
        'cardPausedAt=${formatResumeTimestamp(cached.pausedAtMs)}',
      );
      final sel = await TraktContinueWatchingService.instance.selectionForItem(
        cached,
      );
      if (sel == null) return null;
      debugPrint(
        '[SeriesResume] trakt-home-card-selection title="${item.name}" '
        'resolved=S${sel.season}E${sel.episode} '
        'resolvedPct=${sel.traktProgressPercent}',
      );
      return (sel: sel, tsMs: cached.pausedAtMs);
    }
    if (item.type != 'series') return null;
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty) return null;
    // Mirror resolveSelection's lookup but keep the ITEM, so its Trakt activity
    // timestamp survives.
    final items = await TraktContinueWatchingService.instance.fetchItems(
      TraktContinueWatchingService.showsContentType,
    );
    debugPrint(
      '[SeriesResume] trakt-live-lookup title="${item.name}" id=$id '
      'homeCacheMiss=true fetchedItems=${items.length}',
    );
    TraktContinueWatchingItem? selected;
    for (final it in items) {
      if (it.id == id) {
        selected = it;
        break;
      }
    }
    if (selected == null) return null;
    debugPrint(
      '[SeriesResume] trakt-live-match title="${item.name}" id=$id '
      'card=S${selected.season}E${selected.episode} '
      'cardPct=${selected.progress} '
      'cardPausedAt=${formatResumeTimestamp(selected.pausedAtMs)}',
    );
    final sel = await TraktContinueWatchingService.instance.selectionForItem(
      selected,
    );
    if (sel == null) return null;
    return (sel: sel, tsMs: selected.pausedAtMs);
  }

  /// Local candidate for the reconciler: last-played episode by imdb id (then
  /// by title, same fallback the old chain used), with its progress percent
  /// and updatedAt so it can compete on recency.
  Future<({int season, int episode, double? pct, int? tsMs, bool finished})?>
  localSeriesResumeFor(StremioMeta item, String playId) async {
    Map<String, dynamic>? entry =
        await PlaybackProgressStore.getLastPlayedEpisodeByImdbId(playId);
    var finished = entry?['finished'] == true;
    if (entry?['season'] is! int || entry?['episode'] is! int) {
      entry = await PlaybackProgressStore.getLastPlayedEpisode(seriesTitle: item.name);
      finished = entry?['finished'] == true;
    }
    final season = entry?['season'];
    final episode = entry?['episode'];
    if (season is! int || episode is! int) return null;
    // Series records store positionMs/durationMs (see saveSeriesPlaybackState);
    // the bare names are kept as a fallback for the video-entry shape.
    final pos = ((entry?['positionMs'] ?? entry?['position']) as num?)
        ?.toDouble();
    final dur = ((entry?['durationMs'] ?? entry?['duration']) as num?)
        ?.toDouble();
    final pct = (pos != null && dur != null && dur > 0)
        ? (pos / dur * 100).clamp(0.0, 100.0)
        : null;
    final tsMs = (entry?['updatedAt'] as num?)?.toInt();
    return (
      season: season,
      episode: episode,
      pct: pct,
      tsMs: tsMs != null && tsMs > 0 ? tsMs : null,
      finished: finished,
    );
  }

  /// Trakt's authoritative resume position for [item], or null when
  /// disconnected / Trakt has no in-progress entry. Shared by the detail-button
  /// label ([resolveResumeInfo]) and the actual Play ([resolvePlay]) so the
  /// two never disagree ("Resume · S3E4" must play S3E4). Fast path: an
  /// already-loaded Continue Watching item; general path: a one-shot live
  /// playback lookup for any other title (progress made on another device).
  Future<({bool started, int? season, int? episode})?> traktResumeFor(
    StremioMeta item,
  ) async {
    // No auth-flag short-circuit here: callers gate entry, and both the cached
    // traktByImdb read and resolveSelection (which self-checks isAuthenticated)
    // are safe/null when disconnected — so a Trakt-sourced item still resolves
    // even if isTraktAuthenticated hasn't settled yet.
    final cached = traktByImdb[item.effectiveImdbId] ?? traktByImdb[item.id];
    if (cached != null) {
      final sel = await TraktContinueWatchingService.instance.selectionForItem(
        cached,
      );
      if (sel == null) return null;
      return (started: true, season: sel.season, episode: sel.episode);
    }
    // General (live) fallback only for SERIES here. An uncached movie returns
    // null from THIS helper on purpose — its cross-device resume is resolved by
    // the dedicated movie branch of resolveResumeInfo/resolvePlay (via
    // traktMoviePercent), which the player can now honour. So "null" means
    // "not handled here", not "no Trakt resume for movies".
    if (item.type != 'series') return null;
    // resolveSelection treats an empty itemId as "the first CW item", which would
    // match an unrelated title — so bail when we have no usable id.
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty) return null;
    // Use the SAME resolution resolvePlay's general series branch uses
    // (resolveSelection → fetchItems + selectionForItem). This includes Trakt's
    // Up Next augmentation, so the label matches Play even
    // when the title is only reachable via that augmentation and regardless of
    // whether traktByImdb has populated yet (fixes the open-before-CW-load race
    // where the cached Play branch and the live label branch disagreed).
    final sel = await TraktContinueWatchingService.instance.resolveSelection(
      traktContentType: TraktContinueWatchingService.showsContentType,
      itemId: id,
    );
    if (sel == null) return null;
    return (started: true, season: sel.season, episode: sel.episode);
  }

  /// Simkl's resume position for [item] — SERIES ONLY, from the show's most
  /// recently paused Simkl playback session. Consulted after Trakt returns
  /// nothing and before local history (episode pick is priority-ordered
  /// Trakt → Simkl → local). Shared by the detail-button label
  /// ([resolveResumeInfo]) and the actual Play ([resolvePlay]) so the two
  /// never disagree — same lock-step contract as [traktResumeFor]. Movies
  /// are excluded for the same reason as Trakt's uncached-movie rule: the
  /// movie play path resumes from the local byte offset and can't honour a
  /// tracker percent, so a Simkl-first label would over-promise.
  Future<({int season, int episode, double? progress, DateTime? pausedAt})?>
  simklResumeFor(StremioMeta item) async {
    if (item.type != 'series') return null;
    final id = item.effectiveImdbId ?? item.id;
    // Simkl lookups are IMDb-keyed — a non-IMDb catalog id can't match.
    if (id.isEmpty || !id.startsWith('tt')) return null;
    // The show's most recently paused session, WITH its paused_at timestamp —
    // it competes on recency inside [reconcileSeriesResume] rather than
    // holding a fixed slot above local history, so a stale orphaned session
    // (failed scrobble stop) can't outrank last night's actual position.
    return SimklService.instance.fetchShowPlaybackSelection(id);
  }

  /// Simkl's next unwatched episode (server-computed `next_to_watch`) for a
  /// series, or null. This is the WEAKEST resume signal — a computed "next"
  /// rather than a real position — so callers apply it only when neither a
  /// tracker session NOR local history resolved an episode (e.g. a fresh login
  /// on a new device): it turns the default S01E01 into "resume at the next
  /// unwatched episode", matching the Continue Watching up-next card.
  Future<({int season, int episode})?> simklNextToWatchFor(
    StremioMeta item,
  ) async {
    if (item.type != 'series') return null;
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty || !id.startsWith('tt')) return null;
    return SimklService.instance.fetchNextToWatch(id);
  }

  Future<MdblistContinueWatchingItem?> mdblistResumeItemFor(
    StremioMeta item,
  ) async {
    final id = (item.effectiveImdbId ?? item.id).toLowerCase();
    if (!id.startsWith('tt')) return null;
    final result = await MdblistContinueWatchingService.instance.fetch();
    if (!result.isUsable) return null;
    for (final candidate in [...result.data!.movies, ...result.data!.shows]) {
      if (candidate.selection.imdbId.toLowerCase() == id) return candidate;
    }
    return null;
  }

  /// Read-only mirror of [resolvePlay]'s resume resolution, used to label the
  /// detail screen's primary button. Returns whether the title has prior
  /// progress and, for a series, the season/episode a Play would actually land
  /// on (the next episode when the last one was finished). Never plays — keep in
  /// sync with [resolvePlay].
  Future<ResumeInfo> resolveResumeInfo(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final trackingPolicy = await TrackingSourcePolicy.load();
    debugPrint(
      '[SeriesResume] label-resolve-start title="${item.name}" '
      'id=${item.effectiveImdbId ?? item.id} type=${item.type} '
      'traktSource=$isTraktSource mdblistSource=$isMdblistSource',
    );
    if (isMdblistSource &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final owned = await mdblistResumeItemFor(item);
      if (cancelled()) return (started: false, season: null, episode: null);
      if (owned != null) {
        return (
          started: true,
          season: owned.selection.season,
          episode: owned.selection.episode,
        );
      }
    }
    // Series: the ONE reconciled answer — recency across trackers + local,
    // watched-advance, briefly cached — shared verbatim with resolvePlay
    // so the label and playback can never disagree (see
    // reconcileSeriesResume for the full rules).
    if (item.type == 'series') {
      final r = await reconcileSeriesResume(item, isTraktSource: isTraktSource);
      if (cancelled()) return (started: false, season: null, episode: null);
      debugPrint(
        '[SeriesResume] label-resolve-result title="${item.name}" '
        'started=${r.started} target=S${r.season}E${r.episode} '
        'source=${resumeSourceName(r.sourcePrio)}',
      );
      return (started: r.started, season: r.season, episode: r.episode);
    }

    // Trakt-sourced MOVIE: the cached CW selection carries Trakt's position —
    // same fast path the old Trakt-first arm gave movies (a non-Trakt-sourced
    // movie deliberately stays local-first; Play resumes it from the local
    // byte offset, so a tracker-first label would over-promise).
    if (isTraktSource && trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final resume = await traktResumeFor(item);
      if (cancelled()) return (started: false, season: null, episode: null);
      if (resume != null) return resume;
    }

    // Movie (series returned above): "started" if a local position OR a
    // cross-device tracker position exists — so the button reads "Resume" for
    // a movie paused on another device, matching what Play now seeks to (kept
    // in lock-step with the movie branch of resolvePlay).
    final playId = item.imdbId ?? item.effectiveImdbId ?? item.id;
    final st = trackingPolicy.progressFrom(TrackingSource.local)
        ? await PlaybackProgressStore.getVideoPlaybackStateByImdbId(playId)
        : null;
    if (cancelled()) return (started: false, season: null, episode: null);
    var started = st != null;
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.trakt) &&
        (isTraktAuthenticated() || isTraktSource)) {
      started = (await traktMoviePercent(item)) != null;
      if (cancelled()) return (started: false, season: null, episode: null);
    }
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
        isSimklAuthenticated()) {
      started = (await simklMoviePercent(item)) != null;
      if (cancelled()) return (started: false, season: null, episode: null);
    }
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
        isMdblistAuthenticated()) {
      started = (await mdblistMoviePercent(item)) != null;
      if (cancelled()) return (started: false, season: null, episode: null);
    }
    return (started: started, season: null, episode: null);
  }

  /// Play/browse selection — origin `_onCatalogBrowse`.
  CatalogBrowseDecision onCatalogBrowse(
    StremioMeta item, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    if (item.type == 'series') {
      return CatalogBrowseDecision.episodes();
    } else {
      return CatalogBrowseDecision.movie(
        movieSelection(
          item,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        ),
      );
    }
  }

  PlaySelection movieSelection(
    StremioMeta item, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Cross-device resume percents for a movie (0-100), when a tracker has a
    // paused position. Null = no tracker position → the player resumes from
    // the local byte offset as before.
    double? traktProgressPercent,
    double? simklProgressPercent,
    double? mdblistProgressPercent,
  }) => AdvancedSearchSelection(
    // Keep the raw catalog id when there's no `tt…` id — for IPTV/TV channels
    // AND tmdb/kitsu-only movies — so playback/Sources resolve the addon's own
    // /stream endpoint, matching old home (which passed effectiveImdbId ?? id).
    // The torrent engines can't resolve a non-`tt` id, but the addon stream can
    // (playFromSelection routes any non-`tt` id to _playAddonStream), so this
    // plays instead of dead-ending on "No IMDb match".
    imdbId: item.effectiveImdbId ?? item.id,
    isSeries: false,
    title: item.name,
    year: item.year,
    contentType: item.type,
    posterUrl: item.poster,
    // Trakt-sourced movies scrobble to Trakt like the old home view; catalog
    // movies leave this false so scrobble follows the Tracking master
    // setting.
    traktSource: isTraktSource,
    traktProgressPercent: traktProgressPercent,
    simklProgressPercent: simklProgressPercent,
    mdblistSource: isMdblistSource,
    mdblistProgressPercent: mdblistProgressPercent,
  );

  /// Trakt's paused position (0-100) for a movie, or null when it has none.
  /// Reuses the existing Continue Watching resolver (which fetches
  /// `/sync/playback/movies` and returns a selection carrying the percent) —
  /// no new Trakt service code. Trakt is IMDb-keyed, so a non-`tt` id can't
  /// match.
  Future<double?> traktMoviePercent(StremioMeta item) async {
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty || !id.startsWith('tt')) return null;
    final memo = traktMoviePctMemo[id];
    if (memo != null &&
        DateTime.now().difference(memo.$2) < const Duration(seconds: 30)) {
      return memo.$1;
    }
    final sel = await TraktContinueWatchingService.instance.resolveSelection(
      traktContentType: TraktContinueWatchingService.moviesContentType,
      itemId: id,
    );
    final pct = resumableMoviePercent(sel?.traktProgressPercent);
    traktMoviePctMemo[id] = (pct, DateTime.now());
    return pct;
  }

  /// Simkl's paused position (0-100) for a movie, or null when it has none.
  /// Mirror of [traktMoviePercent]; Simkl lookups are IMDb-keyed too.
  Future<double?> simklMoviePercent(StremioMeta item) async {
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty || !id.startsWith('tt')) return null;
    return resumableMoviePercent(
      await SimklService.instance.fetchMoviePlaybackProgress(id),
    );
  }

  Future<double?> mdblistMoviePercent(StremioMeta item) async {
    final candidate = await mdblistResumeItemFor(item);
    if (candidate == null ||
        !candidate.paused ||
        candidate.selection.isSeries) {
      return null;
    }
    return resumableMdblistPercent(candidate.selection.mdblistProgressPercent);
  }

  double? resumableMdblistPercent(double? pct) {
    if (pct == null || pct < 1 || pct >= 80) return null;
    return pct;
  }

  /// A movie tracker percent, narrowed to what the player will actually
  /// forward-seek, or null. The player's resume window is bounded on BOTH ends
  /// (video_player_screen.dart): it seeks only `loMs < traktMs < hiMs`, where
  /// hiMs = 90% of duration and loMs = the 2s minimum position. A percent
  /// outside that band makes the detail button read "Resume" while Play starts
  /// from 00:00 — a label↔Play mismatch. We only have the percent here (no
  /// duration), so the lower guard is a conservative 1%, which maps above 2s for
  /// any real-length movie (1% of even a 4-min clip is >2s). Keep both helpers
  /// on this filter so the label promises only a Resume that Play honours.
  double? resumableMoviePercent(double? pct) {
    if (pct == null || pct < 1 || pct >= 90) return null;
    return pct;
  }
}
