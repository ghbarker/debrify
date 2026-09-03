import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'alldebrid_cloud_provider.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';
import 'pikpak_cloud_provider.dart';
import 'premiumize_cloud_provider.dart';
import 'rd_cloud_provider.dart';
import 'torbox_cloud_provider.dart';

/// Lookup table for cloud playback adapters.
///
/// Tests replace [instance] with a registry of [FakeCloudProvider]s.
class CloudProviderRegistry {
  CloudProviderRegistry(List<CloudProviderPort> providers)
    : _byId = {for (final p in providers) p.id: p};

  factory CloudProviderRegistry.production() => CloudProviderRegistry(const [
    RealDebridCloudProvider(),
    TorboxCloudProvider(),
    PremiumizeCloudProvider(),
    AllDebridCloudProvider(),
    PikPakCloudProvider(),
  ]);

  static CloudProviderRegistry instance = CloudProviderRegistry.production();

  final Map<CloudProviderId, CloudProviderPort> _byId;

  @visibleForTesting
  static void debugReset() {
    instance = CloudProviderRegistry.production();
  }

  CloudProviderPort? operator [](CloudProviderId id) => _byId[id];

  CloudProviderPort require(String provider) {
    final id = CloudProviderId.tryParse(provider);
    final port = id == null ? null : _byId[id];
    if (port == null) {
      throw Exception('Unknown provider: $provider');
    }
    return port;
  }

  Future<bool> isConfigured(String provider) async {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return false;
    final port = _byId[id];
    if (port == null) return false;
    return port.isConfigured();
  }

  Future<CloudPlaybackResult> addMagnet(
    String provider,
    String magnet,
    Torrent torrent,
  ) => require(provider).addMagnet(magnet, torrent);

  /// Bound replay looks up [SeriesSource.debridService] as a stored id
  /// (`rd`, not `debrid`). Unknown ids return null; they do not throw.
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  }) async {
    if (!source.isProviderNativeCloud) return null;
    if (source.debridTorrentId.trim().isEmpty) return null;
    final id = CloudProviderId.fromStoredId(source.debridService);
    final port = id == null ? null : _byId[id];
    if (port == null) return null;
    return port.resolveNativeBound(source, contentType: contentType);
  }

  /// Field presence, not [PlaylistEntry.provider]. Restricted-link wins over
  /// TorBox; TorBox web-download ids are ignored here. Errors become null.
  Future<String?> resolveEntryUrl(PlaylistEntry entry) async {
    if (entry.url.isNotEmpty) return entry.url;
    try {
      if (entry.restrictedLink != null && entry.restrictedLink!.isNotEmpty) {
        return await _byId[CloudProviderId.debrid]?.resolvePlaylistEntry(entry);
      }
      if (entry.torboxTorrentId != null && entry.torboxFileId != null) {
        return await _byId[CloudProviderId.torbox]?.resolvePlaylistEntry(entry);
      }
      if (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty) {
        return await _byId[CloudProviderId.alldebrid]?.resolvePlaylistEntry(
          entry,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Launcher / TV order: TorBox (incl. web-download) before PikPak before
  /// Premiumize before RD. Throws. [fallbackUrl] is [VideoPlayerLaunchArgs.videoUrl].
  Future<String> unlockPlaybackEntry(
    PlaylistEntry entry, {
    String fallbackUrl = '',
  }) async {
    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      return require('torbox').unlockPlaybackEntry(entry);
    }

    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      return require('pikpak').unlockPlaybackEntry(entry);
    }

    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      return require('premiumize').unlockPlaybackEntry(entry);
    }

    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      if (hash != null && hash.isNotEmpty && path != null && path.isNotEmpty) {
        return require('premiumize').unlockPlaybackEntry(entry);
      }
    }

    if (entry.restrictedLink != null && entry.restrictedLink!.isNotEmpty) {
      return require('debrid').unlockPlaybackEntry(entry);
    }

    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      return require('alldebrid').unlockPlaybackEntry(entry);
    }

    if (fallbackUrl.isNotEmpty) return fallbackUrl;

    throw Exception('No URL metadata available for this entry');
  }

  static String? credentialKeyFor(String provider) =>
      CloudProviderId.tryParse(provider)?.credentialKey;
}
