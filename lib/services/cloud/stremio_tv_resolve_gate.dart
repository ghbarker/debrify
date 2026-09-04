import '../../models/torrent.dart';
import '../../utils/rd_blocked_filter.dart';
import '../storage_service.dart';

/// Per-torrent Stremio TV resolve skip. Not a CloudCredentials check
/// and not a fourth CloudConfiguredCheck.
///
/// Not [CloudCredentials.isStremioAvailable] (picker: RD/TB key, PikPak
/// enabled, PM/AD toggle+key). Not playback [isConfigured].
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
        return StorageService.getPremiumizeIntegrationEnabled();
      case 'alldebrid':
        return StorageService.getAllDebridIntegrationEnabled();
      default:
        return true;
    }
  }
}
