import '../../models/tracking_source.dart';
import 'scrobble_playback.dart';
import 'scrobble_target.dart';

/// Drives N [ScrobbleTarget]s from the player event sites.
///
/// Iterates the target list instead of `switch (source)`. Each target
/// still applies `TrackingSourcePolicy.scrobbles` for its own
/// [TrackingSource] during [init].
class ScrobbleCoordinator {
  ScrobbleCoordinator({
    required this.playback,
    required List<ScrobbleTarget> targets,
  }) : targets = List<ScrobbleTarget>.of(targets);

  final ScrobblePlayback playback;
  final List<ScrobbleTarget> targets;

  Future<void> init() async {
    for (final target in targets) {
      await target.init();
    }
  }

  void onPlaying(
    bool playing, {
    required bool wasPlaying,
    required bool isTransitioning,
  }) {
    for (final target in targets) {
      target.onPlaying(
        playing,
        wasPlaying: wasPlaying,
        isTransitioning: isTransitioning,
      );
    }
  }

  void onSeek(Duration seekTarget) {
    for (final target in targets) {
      target.onSeek(seekTarget);
    }
  }

  void onEnded() {
    for (final target in targets) {
      target.onEnded();
    }
  }

  void onOutgoingEpisode() {
    for (final target in targets) {
      target.onOutgoingEpisode();
    }
  }

  Future<void> switchIdentity() async {
    for (final target in targets) {
      await target.switchIdentity();
    }
  }

  void onDispose() {
    for (final target in targets) {
      target.onDispose();
    }
  }

  void updatePosition() {
    for (final target in targets) {
      target.updatePosition();
    }
  }

  void onDurationBecameReady() {
    for (final target in targets) {
      target.onDurationBecameReady();
    }
  }

  void resumeAfterValidationGate() {
    if (!playback.mounted || playback.validationGateActive) return;
    for (final target in targets) {
      target.updatePosition();
    }
    if (!playback.isPlaying || playback.duration <= Duration.zero) return;
    for (final target in targets) {
      target.resumeAfterValidationGate();
    }
  }

  ScrobbleTarget? of(TrackingSource source) {
    for (final target in targets) {
      if (target.source == source) return target;
    }
    return null;
  }
}
