import 'dart:async';

import 'package:flutter/foundation.dart';

import '../simkl/simkl_service.dart';
import '../tracking_source_policy.dart';
import 'scrobble_playback.dart';
import 'scrobble_send.dart';
import 'scrobble_target.dart';

/// Verbatim Simkl scrobble machine from `video_player_screen.dart`.
///
/// Quirks kept: pause-centric — do NOT POST `/scrobble/start` (it returns
/// id:0 and wipes `/sync/playback`). Play stamps a local `'start'` marker
/// so a later pause/stop is not dedup-suppressed. Heartbeat force-sends
/// pause and leaves the marker `'start'`. Incomplete season/episode on a
/// series is skipped (would send a movie-shaped show id). Seek is
/// transition-only (cross 80% → stop; seek back after stop → pause).
class SimklScrobbleTarget implements ScrobbleTarget {
  SimklScrobbleTarget({
    required this.requested,
    required this.playback,
    required this.scrobblePause,
    required this.scrobbleStop,
    required this.isAuthenticated,
    required this.loadPolicy,
  });

  factory SimklScrobbleTarget.production({
    required bool requested,
    required ScrobblePlayback playback,
  }) => SimklScrobbleTarget(
    requested: requested,
    playback: playback,
    scrobblePause: SimklService.instance.scrobblePause,
    scrobbleStop: SimklService.instance.scrobbleStop,
    isAuthenticated: SimklService.instance.isAuthenticated,
    loadPolicy: TrackingSourcePolicy.load,
  );

  final bool requested;
  final ScrobblePlayback playback;
  final ScrobbleSend scrobblePause;
  final ScrobbleSend scrobbleStop;
  final Future<bool> Function() isAuthenticated;
  final Future<TrackingSourcePolicy> Function() loadPolicy;

  @override
  TrackingSource get source => TrackingSource.simkl;

  bool enabled = false;
  String? lastScrobbleAction;
  Timer? _heartbeatTimer;

  @override
  Future<void> init() async {
    if (!requested) return;
    if (playback.imdbId == null) return;
    if (playback.contentType != 'movie' && playback.contentType != 'series') {
      return;
    }
    final policy = await loadPolicy();
    enabled = policy.scrobbles(TrackingSource.simkl) && await isAuthenticated();
    if (!playback.mounted) return;
    // Pause-centric model: do NOT POST Simkl's /scrobble/start. Unlike Trakt,
    // it persists NO resumable position AND deletes the existing /sync/playback
    // entry (verified: returns id:0, wipes the session). We leave the resume
    // point untouched and let the pause-based heartbeat keep it current.
    // BUT still stamp the marker 'start' (no POST) — the local action marker
    // must read "playing" so a later user-pause / exit-stop isn't dedup-
    // suppressed at _simklScrobble's guard. Mirrors the Trakt block and the TV
    // launcher's self-healing marker. (Field assignment, NOT _simklScrobble
    // ('start'), which now routes to a pause POST.)
    if (!playback.validationGateActive &&
        enabled &&
        playback.isPlaying &&
        playback.duration > Duration.zero) {
      lastScrobbleAction = 'start';
      _startHeartbeat();
    }
  }

  /// A series whose season/episode can't be resolved must NOT be scrobbled to
  /// Simkl: [SimklService._scrobble] would send the show id in a movie-shaped
  /// body, recording a bogus movie on the account. A movie legitimately has
  /// (null, null), so this only blocks the series case. (Trakt has the same
  /// latent gap; this guard is Simkl-only per the no-touch-Trakt convention.)
  bool seriesSEUnresolved(({int? season, int? episode}) se) =>
      playback.contentType == 'series' &&
      (se.season == null || se.episode == null);

  void _scrobble(String action) {
    if (playback.validationGateActive) return;
    if (!enabled || playback.imdbId == null) return;
    final imdbId = playback.imdbId!;
    final progress = playback.progress;
    final se = playback.seasonEpisode;
    if (seriesSEUnresolved(se)) return;
    // Simkl marks watched server-side at ≥80% on stop — mirror Trakt's rule
    // and finalize instead of keeping a start/pause session alive.
    if ((action == 'start' || action == 'pause') && progress > 80) {
      action = 'stop';
    }
    if (lastScrobbleAction == action) return;
    lastScrobbleAction = action;
    switch (action) {
      // 'start' shares the pause path (no caller passes it in the pause-centric
      // model; play stamps the marker directly). Kept defensive and merged so
      // the two can't silently diverge: NEVER send Simkl's /scrobble/start — it
      // persists nothing and wipes the resume point, so a 'start' intent maps to
      // a pause checkpoint.
      case 'start':
      case 'pause':
        scrobblePause(imdbId, progress, season: se.season, episode: se.episode);
        break;
      case 'stop':
        scrobbleStop(imdbId, progress, season: se.season, episode: se.episode);
        break;
    }
  }

  /// Periodic Simkl checkpoint — comfortably above Simkl's 20-second per-user
  /// scrobble rate lock. Uses /scrobble/pause (NOT /scrobble/start): on Simkl,
  /// start returns id:0 and persists NO resumable position — only pause/stop
  /// create the /sync/playback entry that Continue Watching + episode-card
  /// resume read. So the heartbeat pauses to keep a resume point current every
  /// interval; a hard kill (SIGINT/power-off, no graceful stop) then still
  /// resumes from the last checkpoint instead of the episode start.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (playback.validationGateActive ||
          !enabled ||
          playback.imdbId == null) {
        return;
      }
      if (!playback.isPlaying || playback.duration.inMilliseconds <= 0) return;
      final imdbId = playback.imdbId!;
      final progress = playback.progress;
      final se = playback.seasonEpisode;
      if (seriesSEUnresolved(se)) return;
      if (progress > 80) {
        lastScrobbleAction = 'stop';
        scrobbleStop(imdbId, progress, season: se.season, episode: se.episode);
        debugPrint(
          'Simkl: Heartbeat stop at ${progress.toStringAsFixed(1)}% (>80%)',
        );
        _stopHeartbeat();
        return;
      }
      // Force-send pause (direct call, bypasses dedup) to checkpoint a RESUMABLE
      // position. Simkl's /scrobble/start saves nothing (id:0); only pause/stop
      // persist to /sync/playback, so this must be pause to survive a hard kill.
      // Leave the marker 'start' (live), NOT 'pause': stamping 'pause' here would
      // make the user's real pause dedup-suppress at _simklScrobble and strand
      // the true pause position at this (older) heartbeat %.
      lastScrobbleAction = 'start';
      scrobblePause(imdbId, progress, season: se.season, episode: se.episode);
      debugPrint(
        'Simkl: Heartbeat pause checkpoint at ${progress.toStringAsFixed(1)}%',
      );
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void onPlaying(
    bool playing, {
    required bool wasPlaying,
    required bool isTransitioning,
  }) {
    if (playback.validationGateActive) return;
    if (enabled && playing && playback.duration > Duration.zero) {
      lastScrobbleAction = 'start';
      _startHeartbeat();
    } else if (!playing &&
        wasPlaying &&
        !isTransitioning &&
        lastScrobbleAction != 'stop') {
      _scrobble('pause');
      _stopHeartbeat();
    }
  }

  /// Simkl reaction to a user seek. Deliberately TRANSITION-ONLY, unlike
  /// Trakt's seek handler which re-sends start with fresh progress on every
  /// seek: Simkl's docs say not to call /scrobble/start on seek events (plus
  /// a 20s rate lock), so this only acts when the seek changes the effective
  /// action — crossing the 80% boundary (→ stop), or seeking back below it
  /// after a stop (→ a new start). The 2-minute heartbeat carries fresh
  /// progress either way.
  @override
  void onSeek(Duration seekTarget) {
    if (playback.validationGateActive) return;
    if (!enabled || playback.imdbId == null) return;
    if (!playback.isPlaying || playback.duration.inMilliseconds <= 0) return;
    final imdbId = playback.imdbId!;
    final progress =
        (seekTarget.inMilliseconds / playback.duration.inMilliseconds * 100)
            .clamp(0.0, 100.0);
    final se = playback.seasonEpisode;
    if (seriesSEUnresolved(se)) return;
    if (progress > 80 && lastScrobbleAction != 'stop') {
      lastScrobbleAction = 'stop';
      scrobbleStop(imdbId, progress, season: se.season, episode: se.episode);
      _stopHeartbeat();
    } else if (progress <= 80 && lastScrobbleAction == 'stop') {
      // Seeked back under 80% after a finalize — re-establish a RESUMABLE
      // session via pause (start would wipe it and persist nothing) and resume
      // the heartbeat.
      lastScrobbleAction = 'pause';
      scrobblePause(imdbId, progress, season: se.season, episode: se.episode);
      _startHeartbeat();
    }
  }

  @override
  void onEnded() {
    _stopHeartbeat();
    _scrobble('stop');
  }

  @override
  void onOutgoingEpisode() {
    _stopHeartbeat();
    _scrobble('stop');
  }

  @override
  Future<void> switchIdentity() async {}

  @override
  void onDispose() {
    _stopHeartbeat();
    _scrobble('stop');
  }

  @override
  void updatePosition() {}

  @override
  void onDurationBecameReady() {}

  @override
  void resumeAfterValidationGate() {
    if (!playback.isPlaying || playback.duration <= Duration.zero) return;
    if (enabled) {
      // Simkl uses a local playing marker and pause-based checkpoints; sending
      // its remote "start" would erase the resumable playback entry.
      lastScrobbleAction = 'start';
      _startHeartbeat();
    }
  }
}
