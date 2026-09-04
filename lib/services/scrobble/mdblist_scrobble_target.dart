import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mdblist/mdblist_models.dart';
import '../mdblist/mdblist_scrobble_session.dart';
import '../mdblist/mdblist_service.dart';
import '../profiles/profile_async_authorization.dart';
import '../tracking_source_policy.dart';
import 'scrobble_playback.dart';
import 'scrobble_target.dart';

typedef MdblistSessionFactory =
    MdblistScrobbleSession Function({
      required MdblistScrobbleTarget target,
      required ProfileAsyncAuthorization? capability,
    });

/// Player-side wrapper that drives [MdblistScrobbleSession] as a
/// [ScrobbleTarget]. The session still owns pause-centric HTTP; this
/// class is the moved `_initMdblistScrobble` / play / pause / stop /
/// seek / switchTarget hunk, not a rewrite of MDBList POST paths.
class MdblistScrobbleSessionTarget implements ScrobbleTarget {
  MdblistScrobbleSessionTarget({
    required this.requested,
    required this.playback,
    required this.playerReady,
    required this.featureEnabled,
    required this.loadPolicy,
    required this.captureCapability,
    required this.createSession,
  });

  factory MdblistScrobbleSessionTarget.production({
    required bool requested,
    required ScrobblePlayback playback,
    required Future<void>? playerReady,
  }) => MdblistScrobbleSessionTarget(
    requested: requested,
    playback: playback,
    playerReady: playerReady,
    featureEnabled: kMdblistEnabled,
    loadPolicy: TrackingSourcePolicy.load,
    captureCapability: MdblistService.instance.capturePlaybackCapability,
    createSession: ({required target, required capability}) =>
        MdblistScrobbleSession.forService(
          service: MdblistService.instance,
          target: target,
          capability: capability,
        ),
  );

  final bool requested;
  final ScrobblePlayback playback;
  final Future<void>? playerReady;
  final bool featureEnabled;
  final Future<TrackingSourcePolicy> Function() loadPolicy;
  final Future<ProfileAsyncAuthorization?> Function() captureCapability;
  final MdblistSessionFactory createSession;

  @override
  TrackingSource get source => TrackingSource.mdblist;

  MdblistScrobbleSession? session;

  MdblistScrobbleTarget? _mdblistTarget() {
    final imdbId = playback.imdbId;
    if (imdbId == null || imdbId.isEmpty) return null;
    final ids = MdblistMediaIds(imdb: imdbId);
    if (playback.contentType == 'movie') {
      return MdblistScrobbleTarget.movie(ids);
    }
    if (playback.contentType != 'series') return null;
    final se = playback.seasonEpisode;
    if (se.season == null || se.episode == null) return null;
    return MdblistScrobbleTarget.episode(
      ids,
      season: se.season!,
      episode: se.episode!,
    );
  }

  @override
  Future<void> init() async {
    debugPrint(
      '[MDBListDiag] player init requested=$requested '
      'flag=$featureEnabled imdb=${playback.imdbId} '
      'type=${playback.contentType}',
    );
    if (!requested || !featureEnabled) {
      debugPrint('[MDBListDiag] player init skipped: tracking not requested');
      return;
    }
    final policy = await loadPolicy();
    if (!policy.scrobbles(TrackingSource.mdblist)) return;
    // Playlist launches resolve their requested/resume episode asynchronously.
    // Before that finishes `_currentIndex` is still zero, so constructing the
    // MDBList target here used to scrobble S1E1 while the player actually
    // opened (for example) S1E8. Wait until `_initializePlayer` publishes the
    // real initial index; its playing-state check below still starts tracking
    // immediately when media became ready during the wait.
    try {
      await playerReady;
    } catch (e) {
      debugPrint('[MDBListDiag] player init skipped: player setup failed $e');
      return;
    }
    if (!playback.mounted) return;
    // The launcher already resolved the effective sync+authentication setting
    // before deciding both remote ownership and local-completion suppression.
    // Re-resolving it here could disagree with that launch snapshot and leave
    // the play tracked nowhere; the session capability below still prevents a
    // stale profile/account from receiving writes.
    final target = _mdblistTarget();
    if (target == null) {
      debugPrint('[MDBListDiag] player init skipped: invalid target metadata');
      return;
    }
    final capability = await captureCapability();
    if (!playback.mounted) {
      debugPrint('[MDBListDiag] player init abandoned: player unmounted');
      return;
    }
    final created = createSession(target: target, capability: capability);
    created.updatePosition(playback.position, playback.duration);
    session = created;
    debugPrint(
      '[MDBListDiag] player session ready imdb=${target.ids.imdb} '
      'episode=${target.isEpisode} playing=${playback.isPlaying} '
      'positionMs=${playback.position.inMilliseconds} '
      'durationMs=${playback.duration.inMilliseconds}',
    );
    if (!playback.validationGateActive &&
        playback.isPlaying &&
        playback.duration > Duration.zero) {
      created.play();
    }
  }

  void _play() {
    if (playback.validationGateActive) return;
    updatePosition();
    session?.play();
  }

  void _pause() {
    if (playback.validationGateActive) return;
    updatePosition();
    session?.pause();
  }

  void _stop({bool complete = false}) {
    if (playback.validationGateActive) return;
    updatePosition();
    debugPrint(
      '[MDBListDiag] player stop complete=$complete '
      'session=${session != null} '
      'positionMs=${playback.position.inMilliseconds} '
      'durationMs=${playback.duration.inMilliseconds}',
    );
    if (complete) {
      session?.complete();
    } else {
      session?.exit();
    }
  }

  @override
  void onPlaying(
    bool playing, {
    required bool wasPlaying,
    required bool isTransitioning,
  }) {
    if (playback.validationGateActive) return;
    if (playing && playback.duration > Duration.zero) {
      _play();
    } else if (!playing && wasPlaying && !isTransitioning) {
      _pause();
    }
  }

  @override
  void onSeek(Duration seekTarget) {
    if (playback.validationGateActive) return;
    session?.seek(seekTarget, playback.duration);
  }

  @override
  void onEnded() {
    _stop(complete: true);
  }

  @override
  void onOutgoingEpisode() {
    // Keep the MDBList session's playing bit until switchTarget captures it.
    // Calling exit here would make the incoming episode look paused and would
    // prevent its initial checkpoint/timer from starting.
    updatePosition();
  }

  @override
  Future<void> switchIdentity() async {
    if (playback.validationGateActive) return;
    final target = _mdblistTarget();
    if (target == null) {
      session?.exit();
      return;
    }
    await session?.switchTarget(target);
  }

  @override
  void onDispose() {
    _stop();
    unawaited(session?.close() ?? Future.value());
  }

  @override
  void updatePosition() {
    if (playback.validationGateActive) return;
    // Held-target substitution, same reason as _traktProgress.
    session?.updatePosition(playback.persistablePosition, playback.duration);
  }

  @override
  void onDurationBecameReady() {
    if (!playback.isPlaying) return;
    _play();
  }

  @override
  void resumeAfterValidationGate() {
    if (!playback.isPlaying || playback.duration <= Duration.zero) return;
    _play();
  }
}
