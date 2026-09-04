import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_result.dart';
import 'cloud_port_feature.dart';
import 'cloud_provider_id.dart';
import 'stremio_torrent_resolve_args.dart';
import 'magic_tv_prepare_args.dart';

export 'cloud_capabilities.dart';
export 'cloud_port_feature.dart';

/// Fat playback port kept so [FakeCloudProvider] still compiles.
///
/// Production adapters `extend` [CloudProviderAdapter] and `implement` only
/// the capability interfaces they support ([CloudUnlock], [CloudMagnetAdd],
/// [CloudPlaylist], [CloudMagicTvPrepare] / [CloudMagicTvLockedLinks],
/// [CloudCachedHashes], …). [supports] on production is `is`-checks via
/// [CloudPortFeature.of].
abstract class CloudProviderPort {
  CloudProviderId get id;

  /// Whether this adapter implements [feature]. False means do not call the
  /// method; a supported method may still miss.
  ///
  /// Classes that `implement` this port (test fakes) must declare this.
  /// Production adapters `extend` [CloudProviderAdapter] and inherit it.
  bool supports(CloudPortFeature feature);

  /// Playback-pipeline "has credentials" check (API key present / PikPak
  /// enabled). Magnet deep-links also require the integration-enabled flags;
  /// those stay on [CloudCredentials.configured] / [CloudSurface.magnet].
  Future<bool> isConfigured();

  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent);

  /// Hashless bound-source replay. Direct URLs refresh every play.
  /// Returns null when this provider cannot resolve [source] (wrong kind,
  /// missing credentials, missing remote item).
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  });

  /// Download-picker lazy URL. Production playlist adapters implement
  /// [CloudPlaylist.resolvePlaylist] (sealed result) and map it here.
  /// Launcher/TV lazy resolve is [CloudProviderRegistry.unlockPlaybackEntry].
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry);

  /// HTTP unlock after the registry has chosen this adapter. Throws on missing
  /// metadata or empty URL. Do not wrap errors here — the player-screen path
  /// wraps HTTP failures as `$brand link failed`.
  Future<String> unlockPlaybackEntry(PlaylistEntry entry);

  /// Stremio TV torrent resolve. Returns null on miss / error (no throw).
  /// Distinct from [addMagnet] (playback pipeline) and playlist unlock.
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args);

  /// Debrify TV file prepare. Random unseen file; infohash-only magnet.
  /// Unsupported adapters do not implement [CloudMagicTvPrepare].
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request);

  /// Debrify TV locked-link queue fill. Still-locked URLs, not a stream.
  /// Unsupported adapters do not implement [CloudMagicTvLockedLinks].
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  );

  /// TorBox `checkcached` hashes. Missing key throws [CloudMissingApiKey].
  /// Per-chunk HTTP failures are swallowed by [TorboxService.checkCachedTorrents]
  /// (partial or empty set). Explicit Stremio filter skips the call when there
  /// is no key. Not Premiumize [checkCache] (positional bools).
  Future<Set<String>> checkCachedHashes(List<String> infoHashes);

  /// Premiumize `cache/check`. Returns positional bools aligned with [items],
  /// not a hash set. Chunk HTTP misses stay `false` (service dialect).
  /// Missing key throws [CloudMissingApiKey]. Not [checkCachedHashes].
  Future<List<bool>> checkCache(List<String> items);

  /// TorBox whole-torrent ZIP permalink (`zip_link=true`). Sync URL builder
  /// behind a Future. Missing key throws [CloudMissingApiKey]. Not the
  /// web-download ZIP permalink. Not Premiumize transfer+zip.
  Future<String> zipPermalink(int torrentId);

  /// TorBox torrent file `requestdl` (`zip_link=false`). Missing key throws
  /// [CloudMissingApiKey]. Not [zipPermalink]. Not web-download file link.
  /// Not playlist [resolvePlaylistEntry] / player [unlockPlaybackEntry]
  /// (those keep their empty-URL / metadata dialects).
  Future<String> fileDownloadLink(int torrentId, int fileId);

  /// TorBox web-download ZIP permalink (`webdl/requestdl`, `zip_link=true`).
  /// Sync URL builder behind a Future. Missing key throws [CloudMissingApiKey].
  /// Not torrent [zipPermalink]. Not web-download file link.
  Future<String> webZipPermalink(int webId);

  /// Premiumize `transfer/create`. Missing key throws [CloudMissingApiKey].
  /// Not [createTransferZip] (wait + zip URL). Not TorBox `createTorrent`.
  Future<void> createCloudTransfer(String magnet);

  /// Premiumize transfer + poll + zip URL. Missing key throws
  /// [CloudMissingApiKey]. Not [createCloudTransfer] (no wait). Not TorBox
  /// [zipPermalink].
  Future<String> createTransferZip(String magnet);

  /// Not-cached "add anyway". TorBox `createTorrent` with
  /// `addOnlyIfCached: false`. Premiumize [createCloudTransfer].
  /// Not playback [addMagnet] (cached-only).
  Future<void> queueUncachedMagnet(String magnet);

  /// Magnet share-sheet `createtorrent`. Returns the raw payload so the
  /// sheet can keep DOWNLOAD_NOT_CACHED / error-string dialect.
  /// Not playback [addMagnet]. Not TPS [queueUncachedMagnet] (void).
  /// Missing key throws [CloudMissingApiKey].
  Future<Map<String, dynamic>> createMagnetTorrent(
    String magnet, {
    required bool addOnlyIfCached,
  });
}

/// Shared [supports] for production adapters (`implements` would re-require it).
///
/// Optional fat-port methods default to [CloudUnsupported] so
/// [FakeCloudProvider] and frozen `cloud_stremio_*` pins that call
/// `RealDebridCloudProvider.checkCachedHashes` keep compiling. Production
/// registry paths use `is` / [supports] and do not call these stubs.
abstract class CloudProviderAdapter implements CloudProviderPort {
  const CloudProviderAdapter();

  @override
  bool supports(CloudPortFeature feature) =>
      CloudPortFeature.of(this).contains(feature);

  @override
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry) {
    throw CloudUnsupported(id, CloudPortFeature.playlistEntry);
  }

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) {
    throw CloudUnsupported(id, CloudPortFeature.magicTvPrepare);
  }

  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) {
    throw CloudUnsupported(id, CloudPortFeature.magicTvLockedLinks);
  }

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
  Future<String> fileDownloadLink(int torrentId, int fileId) {
    throw CloudUnsupported(id, CloudPortFeature.fileDownloadLink);
  }

  @override
  Future<String> webZipPermalink(int webId) {
    throw CloudUnsupported(id, CloudPortFeature.webZipPermalink);
  }

  @override
  Future<void> createCloudTransfer(String magnet) {
    throw CloudUnsupported(id, CloudPortFeature.cloudTransfer);
  }

  @override
  Future<String> createTransferZip(String magnet) {
    throw CloudUnsupported(id, CloudPortFeature.transferZip);
  }

  @override
  Future<void> queueUncachedMagnet(String magnet) {
    throw CloudUnsupported(id, CloudPortFeature.queueUncached);
  }

  @override
  Future<Map<String, dynamic>> createMagnetTorrent(
    String magnet, {
    required bool addOnlyIfCached,
  }) {
    throw CloudUnsupported(id, CloudPortFeature.magnetTorrent);
  }
}
