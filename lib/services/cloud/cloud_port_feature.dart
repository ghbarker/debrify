import 'cloud_capabilities.dart';
import 'cloud_provider_id.dart';

/// Features a production adapter actually implements.
///
/// Returning null from an optional method used to mean both "this adapter
/// does not do that" and "it tried and missed". [of] / `is` checks are the
/// former; a miss result from a supported method is the latter.
///
/// [forProvider] stays for [FakeCloudProvider] (fat port, not `is` checks).
/// It must equal [of] on the production adapter (see cloud_port_feature_test).
enum CloudPortFeature {
  playlistEntry,
  magicTvPrepare,
  magicTvLockedLinks,
  cachedHashes,
  checkCache,
  zipPermalink,
  fileDownloadLink,
  webZipPermalink,
  cloudTransfer,
  transferZip,
  queueUncached,
  magnetTorrent;

  /// Derived from which capability interfaces [adapter] implements.
  static Set<CloudPortFeature> of(Object adapter) => {
    if (adapter is CloudPlaylist) playlistEntry,
    if (adapter is CloudMagicTvPrepare) magicTvPrepare,
    if (adapter is CloudMagicTvLockedLinks) magicTvLockedLinks,
    if (adapter is CloudCachedHashes) cachedHashes,
    if (adapter is CloudCheckCache) checkCache,
    if (adapter is CloudZipPermalink) zipPermalink,
    if (adapter is CloudFileDownloadLink) fileDownloadLink,
    if (adapter is CloudWebZipPermalink) webZipPermalink,
    if (adapter is CloudTransfer) cloudTransfer,
    if (adapter is CloudTransferZip) transferZip,
    if (adapter is CloudQueueUncached) queueUncached,
    if (adapter is CloudMagnetTorrent) magnetTorrent,
  };

  /// Feature set keyed by provider id. Used by [FakeCloudProvider.supports]
  /// because the fake implements the fat port, not the capability types.
  /// Production adapters use [of] / `is` checks.
  static Set<CloudPortFeature> forProvider(CloudProviderId id) => switch (id) {
    CloudProviderId.debrid => {playlistEntry, magicTvLockedLinks},
    CloudProviderId.torbox => {
      playlistEntry,
      magicTvPrepare,
      cachedHashes,
      zipPermalink,
      fileDownloadLink,
      webZipPermalink,
      queueUncached,
      magnetTorrent,
    },
    CloudProviderId.premiumize => {
      magicTvPrepare,
      checkCache,
      cloudTransfer,
      transferZip,
      queueUncached,
    },
    CloudProviderId.alldebrid => {playlistEntry, magicTvLockedLinks},
    CloudProviderId.pikpak => {magicTvPrepare},
  };
}
