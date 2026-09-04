import '../../screens/video_player/models/playlist_entry.dart';

/// Which adapter the playlist-unlock ladders should call.
///
/// Launcher and in-app player share this order. They differ only at:
/// incomplete Premiumize hash/path (player throws, launcher falls through)
/// and empty `restrictedLink` (player hits RD, launcher does not).
enum CloudUnlockLane { torbox, pikpak, premiumize, debrid, alldebrid }

class CloudUnlockPlan {
  const CloudUnlockPlan._(this.lane, {this.incompletePremiumize = false});

  const CloudUnlockPlan.lane(CloudUnlockLane lane) : this._(lane);

  const CloudUnlockPlan.incompletePremiumize()
    : this._(CloudUnlockLane.premiumize, incompletePremiumize: true);

  final CloudUnlockLane? lane;
  final bool incompletePremiumize;

  static const none = CloudUnlockPlan._(null);

  String get playbackId => switch (lane!) {
    CloudUnlockLane.torbox => 'torbox',
    CloudUnlockLane.pikpak => 'pikpak',
    CloudUnlockLane.premiumize => 'premiumize',
    CloudUnlockLane.debrid => 'debrid',
    CloudUnlockLane.alldebrid => 'alldebrid',
  };

  /// Player-screen wrap brand. TorBox is `Torbox`, RD is `Real Debrid`.
  String get playerBrand => switch (lane!) {
    CloudUnlockLane.torbox => 'Torbox',
    CloudUnlockLane.pikpak => 'PikPak',
    CloudUnlockLane.premiumize => 'Premiumize',
    CloudUnlockLane.debrid => 'Real Debrid',
    CloudUnlockLane.alldebrid => 'AllDebrid',
  };

  static CloudUnlockPlan choose(
    PlaylistEntry entry, {
    required bool playerScreen,
  }) {
    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      return const CloudUnlockPlan.lane(CloudUnlockLane.torbox);
    }

    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      return const CloudUnlockPlan.lane(CloudUnlockLane.pikpak);
    }

    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      return const CloudUnlockPlan.lane(CloudUnlockLane.premiumize);
    }

    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      final complete =
          hash != null &&
          hash.isNotEmpty &&
          path != null &&
          path.isNotEmpty;
      if (complete) {
        return const CloudUnlockPlan.lane(CloudUnlockLane.premiumize);
      }
      if (playerScreen) {
        return const CloudUnlockPlan.incompletePremiumize();
      }
    }

    if (playerScreen) {
      if (entry.restrictedLink != null) {
        return const CloudUnlockPlan.lane(CloudUnlockLane.debrid);
      }
    } else if (entry.restrictedLink != null &&
        entry.restrictedLink!.isNotEmpty) {
      return const CloudUnlockPlan.lane(CloudUnlockLane.debrid);
    }

    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      return const CloudUnlockPlan.lane(CloudUnlockLane.alldebrid);
    }

    return CloudUnlockPlan.none;
  }
}
