import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tracking_source_policy.dart';
import '../trakt/trakt_service.dart';
import 'scrobble_playback.dart';
import 'scrobble_send.dart';
import 'scrobble_target.dart';

/// Verbatim Trakt scrobble machine from `video_player_screen.dart`.
///
/// Quirks kept: POST `/scrobble/start` on play; start/pause above 80%
/// become stop; heartbeat every 2 minutes force-sends start (or stop at
/// >80% and ends the timer); seek always re-sends start (or stop);
/// scrobble-start-now if the player was already playing when auth
/// resolved.
class TraktScrobbleTarget implements ScrobbleTarget {
  TraktScrobbleTarget({
    required this.requested,
    required this.playback,
    required this.scrobbleStart,
    required this.scrobblePause,
    required this.scrobbleStop,
    required this.isAuthenticated,
    required this.loadPolicy,
  });

  factory TraktScrobbleTarget.production({
    required bool requested,
    required ScrobblePlayback playback,
  }) => TraktScrobbleTarget(
    requested: requested,
    playback: playback,
    scrobbleStart: TraktService.instance.scrobbleStart,
    scrobblePause: TraktService.instance.scrobblePause,
    scrobbleStop: TraktService.instance.scrobbleStop,
    isAuthenticated: TraktService.instance.isAuthenticated,
    loadPolicy: TrackingSourcePolicy.load,
  );

  final bool requested;
  final ScrobblePlayback playback;
  final ScrobbleSend scrobbleStart;
  final ScrobbleSend scrobblePause;
  final ScrobbleSend scrobbleStop;
  final Future<bool> Function() isAuthenticated;
  final Future<TrackingSourcePolicy> Function() loadPolicy;

  @override
  TrackingSource get source => TrackingSource.trakt;

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
    enabled = policy.scrobbles(TrackingSource.trakt) && await isAuthenticated();
    if (!playback.mounted) return;
    // If player started playing before auth resolved, scrobble start now
    if (enabled && playback.isPlaying && playback.duration > Duration.zero) {
      _scrobble('start');
      if (lastScrobbleAction == 'start') {
        _startHeartbeat();
      }
    }
  }

  void _scrobble(String action) {
    if (playback.validationGateActive) return;
    if (!enabled || playback.imdbId == null) return;
    final imdbId = playback.imdbId!;
    final progress = playback.progress;
    final se = playback.seasonEpisode;
    // Trakt rejects start/pause when progress > 80% — send stop instead
    if ((action == 'start' || action == 'pause') && progress > 80) {
      action = 'stop';
    }
    if (lastScrobbleAction == action) return;
    lastScrobbleAction = action;
    switch (action) {
      case 'start':
        scrobbleStart(imdbId, progress, season: se.season, episode: se.episode);
        break;
      case 'pause':
        scrobblePause(imdbId, progress, season: se.season, episode: se.episode);
        break;
      case 'stop':
        scrobbleStop(imdbId, progress, season: se.season, episode: se.episode);
        break;
    }
  }

  /// Start periodic heartbeat to checkpoint progress to Trakt every 2 minutes.
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
      // Trakt rejects start/pause above 80% — send stop and end heartbeat
      if (progress > 80) {
        lastScrobbleAction = 'stop';
        scrobbleStop(imdbId, progress, season: se.season, episode: se.episode);
        debugPrint(
          'Trakt: Heartbeat stop at ${progress.toStringAsFixed(1)}% (>80%)',
        );
        _stopHeartbeat();
        return;
      }
      // Force-send start (bypass dedup) to keep session alive and checkpoint progress
      lastScrobbleAction = 'start';
      scrobbleStart(imdbId, progress, season: se.season, episode: se.episode);
      debugPrint(
        'Trakt: Heartbeat scrobble at ${progress.toStringAsFixed(1)}%',
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
    if (playing && playback.duration > Duration.zero) {
      _scrobble('start');
      if (lastScrobbleAction == 'start') {
        _startHeartbeat();
      }
    } else if (!playing &&
        wasPlaying &&
        !isTransitioning &&
        lastScrobbleAction != 'stop') {
      _scrobble('pause');
      _stopHeartbeat();
    }
  }

  /// Send updated progress to Trakt after a user seek (bypasses dedup guard).
  ///
  /// `_resumeWriteGuard.noteUserSeek()` stays in the player — the original
  /// comment says the handover happens whether or not Trakt is connected.
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
    // Trakt rejects start above 80% — send stop instead
    if (progress > 80) {
      lastScrobbleAction = 'stop';
      scrobbleStop(imdbId, progress, season: se.season, episode: se.episode);
      _stopHeartbeat();
    } else {
      lastScrobbleAction = 'start';
      scrobbleStart(imdbId, progress, season: se.season, episode: se.episode);
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
    _scrobble('start');
    if (lastScrobbleAction == 'start') _startHeartbeat();
  }
}
