import '../../models/playlist_entry.dart';
import 'cloud_provider_id.dart';

/// Which adapter the playlist-unlock ladders should call.
///
/// Launcher and in-app player share this order. They differ only at:
/// incomplete Premiumize hash/path (player throws, launcher falls through)
/// and empty `restrictedLink` (player hits RD, launcher does not).
///
/// [provider] is a [CloudProviderId], not a playback-id string. Registry
/// lookup must [CloudProviderRegistry.requireId], not `tryParse(playbackId)`.
class CloudUnlockPlan {
  const CloudUnlockPlan._(this.provider, {this.incompletePremiumize = false});

  const CloudUnlockPlan.forProvider(CloudProviderId provider)
    : this._(provider);

  const CloudUnlockPlan.incompletePremiumize()
    : this._(CloudProviderId.premiumize, incompletePremiumize: true);

  final CloudProviderId? provider;
  final bool incompletePremiumize;

  static const none = CloudUnlockPlan._(null);

  static CloudUnlockPlan choose(
    PlaylistEntry entry, {
    required bool playerScreen,
  }) {
    // Playback ids only (`debrid` / `torbox` / …). [CloudProviderId.tryParse]
    // would treat playlist JSON `realdebrid` as RD; RD is restrictedLink.
    final playback = CloudProviderId.fromPlaybackId(
      entry.provider?.toLowerCase() ?? '',
    );
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (playback == CloudProviderId.torbox ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      return const CloudUnlockPlan.forProvider(CloudProviderId.torbox);
    }

    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (playback == CloudProviderId.pikpak || hasPikPakMetadata) {
      return const CloudUnlockPlan.forProvider(CloudProviderId.pikpak);
    }

    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      return const CloudUnlockPlan.forProvider(CloudProviderId.premiumize);
    }

    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (playback == CloudProviderId.premiumize || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      final complete =
          hash != null &&
          hash.isNotEmpty &&
          path != null &&
          path.isNotEmpty;
      if (complete) {
        return const CloudUnlockPlan.forProvider(CloudProviderId.premiumize);
      }
      if (playerScreen) {
        return const CloudUnlockPlan.incompletePremiumize();
      }
    }

    if (playerScreen) {
      if (entry.restrictedLink != null) {
        return const CloudUnlockPlan.forProvider(CloudProviderId.debrid);
      }
    } else if (entry.restrictedLink != null &&
        entry.restrictedLink!.isNotEmpty) {
      return const CloudUnlockPlan.forProvider(CloudProviderId.debrid);
    }

    if (playback == CloudProviderId.alldebrid ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      return const CloudUnlockPlan.forProvider(CloudProviderId.alldebrid);
    }

    return CloudUnlockPlan.none;
  }
}
