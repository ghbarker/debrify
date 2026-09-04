/// Live player clock the scrobble machines read on every event.
///
/// Getters, not a snapshot: the original State fields were read at POST
/// time (`_traktProgress`, `_isPlaying`, `_duration`, …).
class ScrobblePlayback {
  ScrobblePlayback({
    required this.imdbIdOf,
    required this.contentTypeOf,
    required this.durationOf,
    required this.positionOf,
    required this.persistablePositionOf,
    required this.isPlayingOf,
    required this.validationGateActiveOf,
    required this.mountedOf,
    required this.seasonEpisodeOf,
  });

  final String? Function() imdbIdOf;
  final String? Function() contentTypeOf;
  final Duration Function() durationOf;
  final Duration Function() positionOf;
  final Duration Function() persistablePositionOf;
  final bool Function() isPlayingOf;
  final bool Function() validationGateActiveOf;
  final bool Function() mountedOf;
  final ({int? season, int? episode}) Function() seasonEpisodeOf;

  String? get imdbId => imdbIdOf();
  String? get contentType => contentTypeOf();
  Duration get duration => durationOf();
  Duration get position => positionOf();
  Duration get persistablePosition => persistablePositionOf();
  bool get isPlaying => isPlayingOf();
  bool get validationGateActive => validationGateActiveOf();
  bool get mounted => mountedOf();
  ({int? season, int? episode}) get seasonEpisode => seasonEpisodeOf();

  /// Moved from `VideoPlayerScreenState._traktProgress`.
  ///
  /// Uses the persistable position (held resume target when the write
  /// guard is armed) so a ~0 live clock cannot reset remote resume.
  double get progress {
    if (duration.inMilliseconds <= 0) return 0.0;
    return (persistablePosition.inMilliseconds / duration.inMilliseconds * 100)
        .clamp(0.0, 100.0);
  }
}
