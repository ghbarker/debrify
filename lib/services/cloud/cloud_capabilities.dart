import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'cloud_playback_result.dart';
import 'cloud_playlist_result.dart';
import 'magic_tv_prepare_args.dart';
import 'stremio_torrent_resolve_args.dart';

export 'cloud_playlist_result.dart';

/// HTTP unlock / bound replay / Stremio torrent resolve.
abstract class CloudUnlock {
  Future<String> unlockPlaybackEntry(PlaylistEntry entry);

  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  });

  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args);
}

/// Playback-pipeline magnet add (cached-only where the provider distinguishes).
abstract class CloudMagnetAdd {
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent);
}

/// Download-picker lazy URL. Null-on-miss is [CloudPlaylistMiss]; adapters
/// that do not implement this type are unsupported.
abstract class CloudPlaylist {
  Future<CloudPlaylistResolve> resolvePlaylist(PlaylistEntry entry);
}

/// Debrify TV. Adapters implement [CloudMagicTvPrepare] and/or
/// [CloudMagicTvLockedLinks] — not both prepare methods on one type.
/// Live RD/AD unlock is a separate capability file (not this one).
abstract class CloudMagicTv {}

abstract class CloudMagicTvPrepare implements CloudMagicTv {
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request);
}

abstract class CloudMagicTvLockedLinks implements CloudMagicTv {
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  );
}

/// TorBox `checkcached` hashes. Not Premiumize [CloudCheckCache].
abstract class CloudCachedHashes {
  Future<Set<String>> checkCachedHashes(List<String> infoHashes);
}

/// Premiumize `cache/check` positional bools. Not [CloudCachedHashes].
abstract class CloudCheckCache {
  Future<List<bool>> checkCache(List<String> items);
}

abstract class CloudZipPermalink {
  Future<String> zipPermalink(int torrentId);
}

abstract class CloudFileDownloadLink {
  Future<String> fileDownloadLink(int torrentId, int fileId);
}

abstract class CloudWebZipPermalink {
  Future<String> webZipPermalink(int webId);
}

abstract class CloudTransfer {
  Future<void> createCloudTransfer(String magnet);
}

abstract class CloudTransferZip {
  Future<String> createTransferZip(String magnet);
}

abstract class CloudQueueUncached {
  Future<void> queueUncachedMagnet(String magnet);
}

abstract class CloudMagnetTorrent {
  Future<Map<String, dynamic>> createMagnetTorrent(
    String magnet, {
    required bool addOnlyIfCached,
  });
}
