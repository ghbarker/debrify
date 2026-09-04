import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'alldebrid_cloud_provider.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_unlock_plan.dart';
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

  CloudProviderPort requireId(CloudProviderId id) {
    final port = _byId[id];
    if (port == null) {
      throw Exception('Unknown provider: ${id.playbackId}');
    }
    return port;
  }

  /// Magnets / TPS picker strings. [tryParse] so `realdebrid` still hits RD.
  /// Playlist unlock must use [requireId] with [CloudUnlockPlan.provider].
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
    final plan = CloudUnlockPlan.choose(entry, playerScreen: false);
    final provider = plan.provider;
    if (provider == null) {
      if (fallbackUrl.isNotEmpty) return fallbackUrl;
      throw Exception('No URL metadata available for this entry');
    }
    return requireId(provider).unlockPlaybackEntry(entry);
  }

  /// In-app player (`video_player_screen._resolvePlaylistEntryUrl`). Same
  /// adapter HTTP as [unlockPlaybackEntry], but: incomplete Premiumize hash
  /// throws (no RD fallthrough); empty `restrictedLink` still hits RD;
  /// HTTP/empty-URL errors wrap as `$brand link failed`; no [fallbackUrl].
  Future<String> unlockPlayerScreenEntry(PlaylistEntry entry) async {
    final plan = CloudUnlockPlan.choose(entry, playerScreen: true);
    if (plan.incompletePremiumize) {
      throw const CloudMetadataMissing('Premiumize file metadata missing');
    }
    final provider = plan.provider;
    if (provider == null) {
      throw Exception('No URL metadata available for this entry');
    }
    return _playerWrappedUnlock(provider, entry);
  }

  Future<String> _playerWrappedUnlock(
    CloudProviderId provider,
    PlaylistEntry entry,
  ) async {
    try {
      return await requireId(provider).unlockPlaybackEntry(entry);
    } on CloudMetadataMissing {
      rethrow;
    } on CloudMissingApiKey {
      rethrow;
    } catch (e) {
      throw Exception('${provider.playerWrapBrand} link failed: $e');
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
    if (!port.supports(CloudPortFeature.magicTvPrepare)) return null;
    try {
      return await port.prepareMagicTv(request);
    } on CloudUnsupported {
      return null;
    }
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
    if (!port.supports(CloudPortFeature.magicTvLockedLinks)) return null;
    try {
      return await port.prepareMagicTvLockedLinks(request);
    } on CloudUnsupported {
      return null;
    }
  }

  /// TorBox cache-check only. Missing adapter / unsupported → empty set.
  /// Missing key throws [CloudMissingApiKey]. Chunk HTTP does not throw
  /// ([TorboxService.checkCachedTorrents] swallows per-chunk failures).
  Future<Set<String>> checkCachedHashes(List<String> infoHashes) async {
    final port = _byId[CloudProviderId.torbox];
    if (port == null || !port.supports(CloudPortFeature.cachedHashes)) {
      return const <String>{};
    }
    return port.checkCachedHashes(infoHashes);
  }

  /// Premiumize cache/check only. Missing adapter / unsupported → `[]`.
  /// Missing key throws [CloudMissingApiKey]. Chunk HTTP does not throw
  /// ([PremiumizeService.checkCache] leaves those slots `false`).
  /// Positional bools, not a hash set.
  Future<List<bool>> checkCache(List<String> items) async {
    final port = _byId[CloudProviderId.premiumize];
    if (port == null || !port.supports(CloudPortFeature.checkCache)) {
      return const <bool>[];
    }
    return port.checkCache(items);
  }

  /// TorBox torrent ZIP permalink only. Missing adapter / unsupported throws
  /// [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  /// Not web-download ZIP.
  Future<String> zipPermalink(int torrentId) async {
    final port = _byId[CloudProviderId.torbox];
    if (port == null || !port.supports(CloudPortFeature.zipPermalink)) {
      throw const CloudUnsupported(
        CloudProviderId.torbox,
        CloudPortFeature.zipPermalink,
      );
    }
    return port.zipPermalink(torrentId);
  }

  /// Premiumize cloud transfer only. Missing adapter / unsupported throws
  /// [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  Future<void> createCloudTransfer(String magnet) async {
    final port = _byId[CloudProviderId.premiumize];
    if (port == null || !port.supports(CloudPortFeature.cloudTransfer)) {
      throw const CloudUnsupported(
        CloudProviderId.premiumize,
        CloudPortFeature.cloudTransfer,
      );
    }
    return port.createCloudTransfer(magnet);
  }

  /// Premiumize transfer+zip only. Missing adapter / unsupported throws
  /// [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  Future<String> createTransferZip(String magnet) async {
    final port = _byId[CloudProviderId.premiumize];
    if (port == null || !port.supports(CloudPortFeature.transferZip)) {
      throw const CloudUnsupported(
        CloudProviderId.premiumize,
        CloudPortFeature.transferZip,
      );
    }
    return port.createTransferZip(magnet);
  }

  /// Not-cached keep-downloading. Unknown / unsupported provider is a no-op
  /// (RD/AD already added while resolving).
  Future<void> queueUncachedMagnet(String provider, String magnet) async {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return;
    final port = _byId[id];
    if (port == null || !port.supports(CloudPortFeature.queueUncached)) {
      return;
    }
    await port.queueUncachedMagnet(magnet);
  }

  static String? credentialKeyFor(String provider) =>
      CloudProviderId.tryParse(provider)?.credentialKey;
}
