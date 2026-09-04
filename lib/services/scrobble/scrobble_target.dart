import '../../models/tracking_source.dart';

/// One tracker scrobble state machine driven by ScrobbleCoordinator.
///
/// Trakt and Simkl are the two duplicated player machines. MDBList is the
/// existing MdblistScrobbleSession wrapped as a target — not a rewrite
/// of MDBList HTTP.
abstract class ScrobbleTarget {
  TrackingSource get source;

  Future<void> init();

  /// Playing-stream listener branch for this target.
  void onPlaying(
    bool playing, {
    required bool wasPlaying,
    required bool isTransitioning,
  });

  void onSeek(Duration seekTarget);

  /// EOF / finished-item path (`_onPlaybackEnded`).
  void onEnded();

  /// Playlist index change: Trakt/Simkl stop the outgoing episode;
  /// MDBList only updates position so [switchIdentity] can keep playing.
  void onOutgoingEpisode();

  Future<void> switchIdentity();

  void onDispose();

  void updatePosition();

  /// First usable duration while already playing (MDBList-only edge).
  void onDurationBecameReady();

  /// Re-arm after the startup validation gate drops.
  /// Caller has already checked mounted / gate, and playing+duration
  /// for the start/heartbeat half; [updatePosition] is called first.
  void resumeAfterValidationGate();
}
