import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_result.dart';
import 'cloud_port_feature.dart';
import 'cloud_provider_id.dart';
import 'stremio_torrent_resolve_args.dart';
import 'magic_tv_prepare_args.dart';

export 'cloud_port_feature.dart';

/// Narrow playback port: add a magnet and resolve a playable result.
///
/// HTTP clients stay in the existing `*_service.dart` files. This port is the
/// switch that [TorrentPlaybackService._add], hashless bound replay, and the
/// download-picker lazy URL used to inline.
abstract class CloudProviderPort {
  CloudProviderId get id;

  /// Whether this adapter implements [feature]. False means do not call the
  /// method; a supported method may still return null on a miss.
  ///
  /// Classes that `implement` this port (test fakes) must declare this.
  /// Production adapters `extend` [CloudProviderAdapter] and inherit it.
  bool supports(CloudPortFeature feature);

  /// Playback-pipeline "has credentials" check (API key present / PikPak
  /// enabled). Magnet deep-links also require the integration-enabled flags;
  /// those stay on [CloudCredentials.isMagnetConfigured].
  Future<bool> isConfigured();

  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent);

  /// Hashless bound-source replay. Direct URLs refresh every play.
  /// Returns null when this provider cannot resolve [source] (wrong kind,
  /// missing credentials, missing remote item).
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  });

  /// Download-picker lazy URL. Launcher/TV lazy resolve is
  /// [CloudProviderRegistry.unlockPlaybackEntry]. The in-app player uses
  /// [CloudProviderRegistry.unlockPlayerScreenEntry] (same adapters, different
  /// wrap / Premiumize / empty-restrictedLink dialect).
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry);

  /// HTTP unlock after the registry has chosen this adapter. Throws on missing
  /// metadata or empty URL. Do not wrap errors here — the player-screen path
  /// wraps HTTP failures as `$brand link failed`.
  Future<String> unlockPlaybackEntry(PlaylistEntry entry);

  /// Stremio TV torrent resolve. Returns null on miss / error (no throw).
  /// Distinct from [addMagnet] (playback pipeline) and playlist unlock.
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args);

  /// Debrify TV file prepare. Random unseen file; infohash-only magnet.
  /// Unsupported adapters throw [CloudUnsupported]; the registry maps that
  /// to null for screen callers.
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request);

  /// Debrify TV locked-link queue fill. Still-locked URLs, not a stream.
  /// Unsupported adapters throw [CloudUnsupported]; the registry maps that
  /// to null for screen callers.
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  );

  /// TorBox `checkcached` hashes. Missing key throws [CloudMissingApiKey].
  /// Per-chunk HTTP failures are swallowed by [TorboxService.checkCachedTorrents]
  /// (partial or empty set). Explicit Stremio filter skips the call when there
  /// is no key. Not Premiumize [checkCache] (positional bools).
  /// Unsupported adapters throw [CloudUnsupported].
  Future<Set<String>> checkCachedHashes(List<String> infoHashes);

  /// Premiumize `cache/check`. Returns positional bools aligned with [items],
  /// not a hash set. Chunk HTTP misses stay `false` (service dialect).
  /// Missing key throws [CloudMissingApiKey]. Not [checkCachedHashes].
  /// Unsupported adapters throw [CloudUnsupported].
  Future<List<bool>> checkCache(List<String> items);

  /// TorBox whole-torrent ZIP permalink (`zip_link=true`). Sync URL builder
  /// behind a Future. Missing key throws [CloudMissingApiKey]. Not the
  /// web-download ZIP permalink. Not Premiumize transfer+zip.
  /// Unsupported adapters throw [CloudUnsupported].
  Future<String> zipPermalink(int torrentId);

  /// Premiumize `transfer/create`. Missing key throws [CloudMissingApiKey].
  /// Not [createTransferZip] (wait + zip URL). Not TorBox `createTorrent`.
  /// Unsupported adapters throw [CloudUnsupported].
  Future<void> createCloudTransfer(String magnet);

  /// Premiumize transfer + poll + zip URL. Missing key throws
  /// [CloudMissingApiKey]. Not [createCloudTransfer] (no wait). Not TorBox
  /// [zipPermalink]. Unsupported adapters throw [CloudUnsupported].
  Future<String> createTransferZip(String magnet);
}

/// Shared [supports] for production adapters (`implements` would re-require it).
abstract class CloudProviderAdapter implements CloudProviderPort {
  const CloudProviderAdapter();

  @override
  bool supports(CloudPortFeature feature) =>
      CloudPortFeature.forProvider(id).contains(feature);

  @override
  Future<Set<String>> checkCachedHashes(List<String> infoHashes) {
    throw CloudUnsupported(id, CloudPortFeature.cachedHashes);
  }

  @override
  Future<List<bool>> checkCache(List<String> items) {
    throw CloudUnsupported(id, CloudPortFeature.checkCache);
  }

  @override
  Future<String> zipPermalink(int torrentId) {
    throw CloudUnsupported(id, CloudPortFeature.zipPermalink);
  }

  @override
  Future<void> createCloudTransfer(String magnet) {
    throw CloudUnsupported(id, CloudPortFeature.cloudTransfer);
  }

  @override
  Future<String> createTransferZip(String magnet) {
    throw CloudUnsupported(id, CloudPortFeature.transferZip);
  }
}
