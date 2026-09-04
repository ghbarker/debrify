/// POST shape shared by Trakt and Simkl scrobble methods.
///
/// Matches `TraktService.scrobbleStart/Pause/Stop` and
/// `SimklService.scrobblePause/Stop`. G5 does not invent HTTP; production
/// targets tear off the existing service methods.
typedef ScrobbleSend =
    Future<bool> Function(
      String imdbId,
      double progress, {
      int? season,
      int? episode,
    });
