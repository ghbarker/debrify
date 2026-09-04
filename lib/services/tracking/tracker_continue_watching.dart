/// Shared Continue Watching snapshot. [movies] / [shows] keep the family's
/// own item type; callers that need Trakt/Simkl/MDBList fields cast.
class TrackerContinueWatchingPage {
  const TrackerContinueWatchingPage({
    required this.movies,
    required this.shows,
  });

  final List<Object> movies;
  final List<Object> shows;
}

/// Shared CW fetch. Each family implements this by wrapping its existing
/// fetch (HTTP code stays in the family).
abstract class TrackerContinueWatching {
  Future<TrackerContinueWatchingPage?> fetchContinueWatching();
}
