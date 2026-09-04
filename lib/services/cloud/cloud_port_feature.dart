import 'cloud_provider_id.dart';

/// Features a [CloudProviderPort] actually implements.
///
/// Returning null from an optional method used to mean both "this adapter
/// does not do that" and "it tried and missed". [CloudProviderPort.supports]
/// is the former; a null return from a supported method is the latter.
enum CloudPortFeature {
  playlistEntry,
  magicTvPrepare,
  magicTvLockedLinks,
  cachedHashes,
  checkCache,
  zipPermalink,
  fileDownloadLink,
  cloudTransfer,
  transferZip,
  queueUncached,
  magnetTorrent;

  static Set<CloudPortFeature> forProvider(CloudProviderId id) => switch (id) {
    CloudProviderId.debrid => {
      playlistEntry,
      magicTvLockedLinks,
    },
    CloudProviderId.torbox => {
      playlistEntry,
      magicTvPrepare,
      cachedHashes,
      zipPermalink,
      fileDownloadLink,
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
