import 'cloud_capabilities.dart';

/// Magic TV live HTTP unlock / PreferVideos add.
///
/// Distinct from [CloudUnlock.unlockPlaybackEntry] (PlaylistEntry → String
/// URL), [CloudMagnetAdd.addMagnet] (playback [CloudPlaybackResult]), and
/// [CloudMagicTvLockedLinks] (still-locked queue fill). Do not unify.
///
/// Adapters look up the API key via CloudCredentials. Magic TV currently
/// passes `apiKey` into the origin HTTP methods.
abstract class CloudMagicTvUnlock implements CloudMagicTv {}

/// Real-Debrid Magic TV live unlock. Return maps match
/// `DebridService.unrestrictLink` / `addTorrentToDebridPreferVideos`.
abstract class CloudMagicTvRdUnlock implements CloudMagicTvUnlock {
  /// Same Map as `DebridService.unrestrictLink(apiKey, link)`.
  Future<Map<String, dynamic>> unrestrictLink(String link);

  /// Same Map as `DebridService.addTorrentToDebridPreferVideos(apiKey, magnet)`.
  Future<Map<String, dynamic>> addTorrentPreferVideos(String magnet);
}

/// AllDebrid Magic TV live unlock. Return String matches
/// `AllDebridService.unlockLink(apiKey, lockedLink)`.
abstract class CloudMagicTvAdUnlock implements CloudMagicTvUnlock {
  /// Same String as `AllDebridService.unlockLink(apiKey, lockedLink)`.
  Future<String> unlockLink(String lockedLink);
}
