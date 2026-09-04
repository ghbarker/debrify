import '../../models/torrent.dart';
import '../../utils/rd_blocked_filter.dart';
import 'cloud_credentials.dart';
import 'cloud_provider_id.dart';

/// Per-torrent Stremio TV resolve skip, plus PM/AD [CloudSurface.stremioResolve].
///
/// Not [CloudSurface.stremioPicker] (picker: RD/TB key, PikPak enabled,
/// PM/AD toggle+key). Not playback [CloudSurface.playback].
/// Provider strings are Stremio ids (`realdebrid`), not `debrid`.
class StremioTvResolveGate {
  StremioTvResolveGate._();

  static Future<bool> canAttempt({
    required String provider,
    required String selected,
    required Torrent torrent,
    required bool skipBlockedRd,
    required Future<Set<String>> Function() torboxCachedHashes,
  }) async {
    switch (provider) {
      case 'realdebrid':
        return !skipBlockedRd || !isRdBlockedTorrent(torrent.name);
      case 'torbox':
        if (selected != 'auto') return true;
        final cachedHashes = await torboxCachedHashes();
        return cachedHashes.contains(torrent.infohash.trim().toLowerCase());
      case 'premiumize':
        return CloudCredentials.configured(
          CloudProviderId.premiumize,
          CloudSurface.stremioResolve,
        );
      case 'alldebrid':
        return CloudCredentials.configured(
          CloudProviderId.alldebrid,
          CloudSurface.stremioResolve,
        );
      default:
        return true;
    }
  }
}
