import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'alldebrid_cloud_provider.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'stremio_torrent_resolve_args.dart';
import 'magic_tv_prepare_args.dart';
import 'cloud_provider_port.dart';
import 'pikpak_cloud_provider.dart';
import 'premiumize_cloud_provider.dart';
import 'rd_cloud_provider.dart';
import 'torbox_cloud_provider.dart';
import '../../utils/stremio_tv_debrid_fallback.dart';

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

  /// In-app player (`video_player_screen._resolvePlaylistEntryUrl`). Same
  /// adapter HTTP as [unlockPlaybackEntry], but: incomplete Premiumize hash
  /// throws (no RD fallthrough); empty `restrictedLink` still hits RD;
  /// HTTP/empty-URL errors wrap as `$brand link failed`; no [fallbackUrl].
  Future<String> unlockPlayerScreenEntry(PlaylistEntry entry) async {
    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      return _playerWrappedUnlock('Torbox', 'torbox', entry);
    }

    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      return _playerWrappedUnlock('PikPak', 'pikpak', entry);
    }

    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      return _playerWrappedUnlock('Premiumize', 'premiumize', entry);
    }

    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      if (hash == null || hash.isEmpty || path == null || path.isEmpty) {
        throw Exception('Premiumize file metadata missing');
      }
      return _playerWrappedUnlock('Premiumize', 'premiumize', entry);
    }

    if (entry.restrictedLink != null) {
      return _playerWrappedUnlock('Real Debrid', 'debrid', entry);
    }

    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      return _playerWrappedUnlock('AllDebrid', 'alldebrid', entry);
    }

    throw Exception('No URL metadata available for this entry');
  }

  Future<String> _playerWrappedUnlock(
    String brand,
    String provider,
    PlaylistEntry entry,
  ) async {
    try {
      return await require(provider).unlockPlaybackEntry(entry);
    } catch (e) {
      final text = e.toString();
      if (text.contains('metadata missing') ||
          text.contains('Missing Torbox API key') ||
          text.contains('Missing Premiumize API key') ||
          text.contains('Missing Real Debrid API key') ||
          text.contains('Missing AllDebrid API key')) {
        rethrow;
      }
      throw Exception('$brand link failed: $e');
    }
  }

  /// Stremio TV torrent → URL. Uses [StremioTvDebridFallback.autoOrder]
  /// (`realdebrid` before TorBox before PikPak before Premiumize) — not
  /// [CloudProviderId.playbackPrecedence]. Lookup is [CloudProviderId.tryParse]
  /// so `realdebrid` hits the RD adapter; [fromPlaybackId] would miss.
  Future<String?> resolveStremioTorrent({
    required Torrent torrent,
    required String contentType,
    required String selected,
    int? season,
    int? episode,
    bool Function()? isCancelled,
    Future<bool> Function(String provider)? canAttempt,
  }) {
    final args = StremioTorrentResolveArgs(
      torrent: torrent,
      contentType: contentType,
      season: season,
      episode: episode,
      isCancelled: isCancelled,
    );
    return StremioTvDebridFallback.resolve<String>(
      selected: selected,
      isCancelled: isCancelled,
      canAttempt: canAttempt,
      attempt: (provider) async {
        final id = CloudProviderId.tryParse(provider);
        final port = id == null ? null : _byId[id];
        if (port == null) return null;
        return port.resolveStremioTorrent(args);
      },
    );
  }

  /// Debrify TV prepare. Lookup is [CloudProviderId.tryParse] so
  /// `real_debrid` hits RD; [fromPlaybackId] would miss. Not Stremio auto
  /// order and not [CloudProviderId.playbackPrecedence].
  Future<MagicTvPrepared?> prepareMagicTv({
    required String provider,
    required MagicTvPrepareRequest request,
  }) async {
    final id = CloudProviderId.tryParse(provider);
    final port = id == null ? null : _byId[id];
    if (port == null) return null;
    return port.prepareMagicTv(request);
  }

  /// Locked-link queue fill. Same [CloudProviderId.tryParse] as
  /// [prepareMagicTv] (`real_debrid` hits RD). Not playback unlock.
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks({
    required String provider,
    required MagicTvPrepareRequest request,
  }) async {
    final id = CloudProviderId.tryParse(provider);
    final port = id == null ? null : _byId[id];
    if (port == null) return null;
    return port.prepareMagicTvLockedLinks(request);
  }

  static String? credentialKeyFor(String provider) =>
      CloudProviderId.tryParse(provider)?.credentialKey;
}
