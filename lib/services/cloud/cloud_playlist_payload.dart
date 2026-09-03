import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';

/// Playlist JSON written by [TorrentPlaybackService._addToPlaylist].
///
/// Real-Debrid is stored as `realdebrid` (not `debrid` / `rd`) so the playlist
/// player can re-resolve after the direct URL expires.
class CloudPlaylistPayload {
  CloudPlaylistPayload._();

  static Map<String, dynamic> build({
    required String provider,
    required CloudPlaybackResult result,
    required String torrentHash,
    required String title,
    int sizeBytes = 0,
    String? imdbId,
    String? contentType,
    String? posterUrl,
  }) {
    final isPack = result.hasPlaylist;
    final item = <String, dynamic>{
      'provider': provider == CloudProviderId.debrid.playbackId
          ? CloudProviderId.debrid.playlistStoredProvider
          : provider,
      'title': title,
      'kind': isPack ? 'collection' : 'single',
      'torrent_hash': torrentHash,
      if (isPack) 'count': result.playlist!.length,
      if (sizeBytes > 0) 'sizeBytes': sizeBytes,
      if (imdbId != null && imdbId.isNotEmpty) 'imdbId': imdbId,
      if (contentType != null) 'contentType': contentType,
      if (posterUrl != null && posterUrl.isNotEmpty) 'posterUrl': posterUrl,
    };
    _attachProviderIds(item, provider, result, isPack);
    return item;
  }

  static void _attachProviderIds(
    Map<String, dynamic> item,
    String provider,
    CloudPlaybackResult r,
    bool isPack,
  ) {
    switch (CloudProviderId.fromPlaybackId(provider)) {
      case CloudProviderId.debrid:
        if (r.rdTorrentId != null) item['rdTorrentId'] = r.rdTorrentId;
        if (!isPack) {
          item['url'] = '';
          if (r.restrictedLink != null) {
            item['restrictedLink'] = r.restrictedLink;
          }
        }
      case CloudProviderId.torbox:
        item['torboxTorrentId'] = r.torboxTorrentId;
        if (isPack) {
          item['torboxFileIds'] = [
            for (final e in r.playlist!)
              if (e.torboxFileId != null) e.torboxFileId,
          ];
        } else if (r.torboxFileId != null) {
          item['torboxFileId'] = r.torboxFileId;
        }
      case CloudProviderId.premiumize:
        if (!isPack && r.premiumizePath != null) {
          item['premiumizePath'] = r.premiumizePath;
        }
      case CloudProviderId.alldebrid:
        if (!isPack && r.allDebridLink != null) {
          item['allDebridLink'] = r.allDebridLink;
        }
      case CloudProviderId.pikpak:
        if (isPack) {
          item['pikpakFileId'] = r.pikpakFileId;
          item['pikpakFileIds'] = [
            for (final e in r.playlist!)
              if (e.pikpakFileId != null) e.pikpakFileId,
          ];
        } else {
          item['pikpakFileId'] = r.pikpakVideoFileId ?? r.pikpakFileId;
        }
      case null:
        break;
    }
  }
}
