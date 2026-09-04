import 'cloud/cloud_provider_id.dart';
import 'cloud/cloud_provider_port.dart';
import 'cloud/cloud_provider_registry.dart';
import 'series_source_service.dart';

/// Playback-pipeline provider-string dispatch.
///
/// Playback ids stay [CloudProviderId.fromPlaybackId] (`debrid`, not stored
/// `rd` / playlist `realdebrid` / Magic TV `real_debrid`). Bound-source
/// storage uses [CloudProviderId.fromStoredId] (`rd` for Real-Debrid).
///
/// Production adapters are routed with capability `is` checks. Fat-port
/// [FakeCloudProvider] (P1) does not implement those types, so [supports]
/// is the fallback — same dual path as [CloudProviderRegistry.prepareMagicTv].
class PlaybackServiceDispatch {
  PlaybackServiceDispatch._();

  static CloudProviderPort? portForPlayback(String provider) {
    final id = CloudProviderId.fromPlaybackId(provider);
    if (id == null) return null;
    return CloudProviderRegistry.instance[id];
  }

  /// Overlay cache-check stage and cache-first reorder gate. TorBox
  /// [CloudCachedHashes] or Premiumize [CloudCheckCache]. RD / AllDebrid /
  /// PikPak stay false. Lookup is [CloudProviderId.fromPlaybackId] so
  /// `realdebrid` / `rd` miss.
  static bool hasCacheCheck(String provider) {
    final port = portForPlayback(provider);
    if (port == null) return false;
    if (port is CloudCachedHashes || port is CloudCheckCache) return true;
    return port.supports(CloudPortFeature.cachedHashes) ||
        port.supports(CloudPortFeature.checkCache);
  }

  static bool isPikPak(String provider) =>
      CloudProviderId.fromPlaybackId(provider) == CloudProviderId.pikpak;

  static bool isDebrid(String provider) =>
      CloudProviderId.fromPlaybackId(provider) == CloudProviderId.debrid;

  static bool isTorbox(String provider) =>
      CloudProviderId.fromPlaybackId(provider) == CloudProviderId.torbox;

  static bool isPremiumize(String provider) =>
      CloudProviderId.fromPlaybackId(provider) == CloudProviderId.premiumize;

  /// Probe budget / one-probe safety / pack-top PikPak hoist / pack-first
  /// silent skip / series auto-pin and rebind torrent exclusion.
  static bool oneProbeSafety(String provider) => isPikPak(provider);

  /// Skip-orphan: RD `addMagnet` / PikPak `addOfflineDownload` create a
  /// fresh account entry. TorBox/AllDebrid dedup; Premiumize adds nothing.
  static bool deletesRdOrphan(String provider) => isDebrid(provider);

  static bool deletesPikPakOrphan(String provider) => isPikPak(provider);

  static bool skipSeriesTorrentPin(String provider) => isPikPak(provider);

  /// Bound replay: the five debrid [CloudProviderId.storedId]s plus on-device
  /// `local` and addon-direct. A stored `debrid` is not RD ([fromStoredId]
  /// would miss; [tryParse] would wrongly accept it).
  static bool boundProviderSupported(String stored) {
    if (stored == SeriesSource.localService) return true;
    if (stored == SeriesSource.addonDirectService) return true;
    return CloudProviderId.fromStoredId(stored) != null;
  }

  static String providerFromStored(String stored) =>
      CloudProviderId.playbackIdFromStored(stored);

  static String storedProviderKey(String provider) =>
      CloudProviderId.storedIdFromPlayback(provider);

  /// TorBox whole-torrent ZIP tiles. Needs [CloudPlaybackResult.torboxTorrentId]
  /// at the call site. Not Premiumize transfer ZIP.
  static bool showTorboxPowerActions(String provider) => isTorbox(provider);

  /// Premiumize cloud-transfer / ZIP tiles. Needs a magnet at the call site.
  /// Not TorBox ZIP permalink.
  static bool showPremiumizePowerActions(String provider) =>
      isPremiumize(provider);
}
