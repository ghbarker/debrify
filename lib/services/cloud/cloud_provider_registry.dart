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
  ) {
    final port = require(provider);
    if (port is CloudMagnetAdd) return port.addMagnet(magnet, torrent);
    return port.addMagnet(magnet, torrent);
  }

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
    if (port is CloudUnlock) {
      return port.resolveNativeBound(source, contentType: contentType);
    }
    return port.resolveNativeBound(source, contentType: contentType);
  }

  /// Field presence, not [PlaylistEntry.provider]. Restricted-link wins over
  /// TorBox; TorBox web-download ids are ignored here. Errors become null.
  Future<String?> resolveEntryUrl(PlaylistEntry entry) async {
    if (entry.url.isNotEmpty) return entry.url;
    try {
      if (entry.restrictedLink != null && entry.restrictedLink!.isNotEmpty) {
        return await _resolvePlaylist(_byId[CloudProviderId.debrid], entry);
      }
      if (entry.torboxTorrentId != null && entry.torboxFileId != null) {
        return await _resolvePlaylist(_byId[CloudProviderId.torbox], entry);
      }
      if (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty) {
        return await _resolvePlaylist(_byId[CloudProviderId.alldebrid], entry);
      }
    } catch (_) {}
    return null;
  }

  /// Production [CloudPlaylist] returns a sealed miss/url. Fat-port fakes
  /// keep [CloudProviderPort.resolvePlaylistEntry] (`String?`).
  Future<String?> _resolvePlaylist(
    CloudProviderPort? port,
    PlaylistEntry entry,
  ) async {
    final playlist = _as<CloudPlaylist>(port);
    if (playlist != null) {
      return (await playlist.resolvePlaylist(entry)).urlOrNull;
    }
    if (port != null && port.supports(CloudPortFeature.playlistEntry)) {
      return port.resolvePlaylistEntry(entry);
    }
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
    return _unlock(requireId(provider), entry);
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

  Future<String> _unlock(CloudProviderPort port, PlaylistEntry entry) {
    if (port is CloudUnlock) return port.unlockPlaybackEntry(entry);
    return port.unlockPlaybackEntry(entry);
  }

  Future<String> _playerWrappedUnlock(
    CloudProviderId provider,
    PlaylistEntry entry,
  ) async {
    try {
      return await _unlock(requireId(provider), entry);
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
        if (port is CloudUnlock) return port.resolveStremioTorrent(args);
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
    final prepare = _as<CloudMagicTvPrepare>(port);
    if (prepare != null) return prepare.prepareMagicTv(request);
    if (!port.supports(CloudPortFeature.magicTvPrepare)) return null;
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
    final locked = _as<CloudMagicTvLockedLinks>(port);
    if (locked != null) return locked.prepareMagicTvLockedLinks(request);
    if (!port.supports(CloudPortFeature.magicTvLockedLinks)) return null;
    return port.prepareMagicTvLockedLinks(request);
  }

  /// TorBox cache-check only. Missing adapter / unsupported → empty set.
  /// Missing key throws [CloudMissingApiKey]. Chunk HTTP does not throw
  /// ([TorboxService.checkCachedTorrents] swallows per-chunk failures).
  Future<Set<String>> checkCachedHashes(List<String> infoHashes) async {
    final port = _byId[CloudProviderId.torbox];
    final hashes = _as<CloudCachedHashes>(port);
    if (hashes != null) return hashes.checkCachedHashes(infoHashes);
    if (port != null && port.supports(CloudPortFeature.cachedHashes)) {
      return port.checkCachedHashes(infoHashes);
    }
    return const <String>{};
  }

  /// Premiumize cache/check only. Missing adapter / unsupported → `[]`.
  /// Missing key throws [CloudMissingApiKey]. Chunk HTTP does not throw
  /// ([PremiumizeService.checkCache] leaves those slots `false`).
  /// Positional bools, not a hash set.
  Future<List<bool>> checkCache(List<String> items) async {
    final port = _byId[CloudProviderId.premiumize];
    final cache = _as<CloudCheckCache>(port);
    if (cache != null) return cache.checkCache(items);
    if (port != null && port.supports(CloudPortFeature.checkCache)) {
      return port.checkCache(items);
    }
    return const <bool>[];
  }

  /// TorBox torrent ZIP permalink only. Missing adapter / unsupported throws
  /// [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  /// Not web-download ZIP.
  Future<String> zipPermalink(int torrentId) async {
    final port = _byId[CloudProviderId.torbox];
    final zip = _as<CloudZipPermalink>(port);
    if (zip != null) return zip.zipPermalink(torrentId);
    if (port != null && port.supports(CloudPortFeature.zipPermalink)) {
      return port.zipPermalink(torrentId);
    }
    throw const CloudUnsupported(
      CloudProviderId.torbox,
      CloudPortFeature.zipPermalink,
    );
  }

  /// TorBox torrent file download link only. Missing adapter / unsupported
  /// throws [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  /// Not web-download file link. Not [zipPermalink].
  Future<String> fileDownloadLink(int torrentId, int fileId) async {
    final port = _byId[CloudProviderId.torbox];
    final files = _as<CloudFileDownloadLink>(port);
    if (files != null) return files.fileDownloadLink(torrentId, fileId);
    if (port != null && port.supports(CloudPortFeature.fileDownloadLink)) {
      return port.fileDownloadLink(torrentId, fileId);
    }
    throw const CloudUnsupported(
      CloudProviderId.torbox,
      CloudPortFeature.fileDownloadLink,
    );
  }

  /// TorBox web-download ZIP permalink only. Missing adapter / unsupported
  /// throws [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  /// Not torrent [zipPermalink].
  Future<String> webZipPermalink(int webId) async {
    final port = _byId[CloudProviderId.torbox];
    final web = _as<CloudWebZipPermalink>(port);
    if (web != null) return web.webZipPermalink(webId);
    if (port != null && port.supports(CloudPortFeature.webZipPermalink)) {
      return port.webZipPermalink(webId);
    }
    throw const CloudUnsupported(
      CloudProviderId.torbox,
      CloudPortFeature.webZipPermalink,
    );
  }

  /// Premiumize cloud transfer only. Missing adapter / unsupported throws
  /// [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  Future<void> createCloudTransfer(String magnet) async {
    final port = _byId[CloudProviderId.premiumize];
    final transfer = _as<CloudTransfer>(port);
    if (transfer != null) return transfer.createCloudTransfer(magnet);
    if (port != null && port.supports(CloudPortFeature.cloudTransfer)) {
      return port.createCloudTransfer(magnet);
    }
    throw const CloudUnsupported(
      CloudProviderId.premiumize,
      CloudPortFeature.cloudTransfer,
    );
  }

  /// Premiumize transfer+zip only. Missing adapter / unsupported throws
  /// [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  Future<String> createTransferZip(String magnet) async {
    final port = _byId[CloudProviderId.premiumize];
    final zip = _as<CloudTransferZip>(port);
    if (zip != null) return zip.createTransferZip(magnet);
    if (port != null && port.supports(CloudPortFeature.transferZip)) {
      return port.createTransferZip(magnet);
    }
    throw const CloudUnsupported(
      CloudProviderId.premiumize,
      CloudPortFeature.transferZip,
    );
  }

  /// Not-cached keep-downloading. Unknown / unsupported provider is a no-op
  /// (RD/AD already added while resolving).
  Future<void> queueUncachedMagnet(String provider, String magnet) async {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return;
    final port = _byId[id];
    final queue = _as<CloudQueueUncached>(port);
    if (queue != null) {
      await queue.queueUncachedMagnet(magnet);
      return;
    }
    if (port != null && port.supports(CloudPortFeature.queueUncached)) {
      await port.queueUncachedMagnet(magnet);
    }
  }

  /// Magnet share-sheet createtorrent only. Missing adapter / unsupported
  /// throws [CloudUnsupported]. Missing key throws [CloudMissingApiKey].
  /// Not playback [CloudProviderPort.addMagnet]. Not [queueUncachedMagnet].
  Future<Map<String, dynamic>> createMagnetTorrent(
    String magnet, {
    required bool addOnlyIfCached,
  }) async {
    final port = _byId[CloudProviderId.torbox];
    final torrent = _as<CloudMagnetTorrent>(port);
    if (torrent != null) {
      return torrent.createMagnetTorrent(
        magnet,
        addOnlyIfCached: addOnlyIfCached,
      );
    }
    if (port != null && port.supports(CloudPortFeature.magnetTorrent)) {
      return port.createMagnetTorrent(magnet, addOnlyIfCached: addOnlyIfCached);
    }
    throw const CloudUnsupported(
      CloudProviderId.torbox,
      CloudPortFeature.magnetTorrent,
    );
  }

  /// Magic TV live RD unrestrict. Same Map as DebridService.unrestrictLink.
  /// Looks up the API key; Magic TV currently passes it. Not
  /// [unlockPlaybackEntry] (String URL). Missing adapter throws
  /// [CloudUnsupported] — no fat-port stub.
  Future<Map<String, dynamic>> unrestrictLink(String link) async {
    final port = _byId[CloudProviderId.debrid];
    final unlock = _as<CloudMagicTvRdUnlock>(port);
    if (unlock != null) return unlock.unrestrictLink(link);
    throw const CloudUnsupported(
      CloudProviderId.debrid,
      CloudPortFeature.magicTvRdUnlock,
    );
  }

  /// Magic TV live RD PreferVideos add. Same Map as
  /// DebridService.addTorrentToDebridPreferVideos. Looks up the API key;
  /// Magic TV currently passes it. Not [addMagnet] (playback result).
  Future<Map<String, dynamic>> addTorrentPreferVideos(String magnet) async {
    final port = _byId[CloudProviderId.debrid];
    final unlock = _as<CloudMagicTvRdUnlock>(port);
    if (unlock != null) return unlock.addTorrentPreferVideos(magnet);
    throw const CloudUnsupported(
      CloudProviderId.debrid,
      CloudPortFeature.magicTvRdUnlock,
    );
  }

  /// Magic TV live AllDebrid unlock. Same String as
  /// AllDebridService.unlockLink. Looks up the API key; Magic TV currently
  /// passes it. Not [unlockPlaybackEntry] (PlaylistEntry).
  Future<String> unlockLink(String lockedLink) async {
    final port = _byId[CloudProviderId.alldebrid];
    final unlock = _as<CloudMagicTvAdUnlock>(port);
    if (unlock != null) return unlock.unlockLink(lockedLink);
    throw const CloudUnsupported(
      CloudProviderId.alldebrid,
      CloudPortFeature.magicTvAdUnlock,
    );
  }

  static T? _as<T>(CloudProviderPort? port) => port is T ? port as T : null;

  static String? credentialKeyFor(String provider) =>
      CloudProviderId.tryParse(provider)?.credentialKey;
}
