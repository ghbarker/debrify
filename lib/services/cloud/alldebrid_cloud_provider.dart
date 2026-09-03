import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../../utils/stremio_episode_selector.dart';
import '../alldebrid_service.dart';
import '../main_page_bridge.dart';
import '../series_source_service.dart';
import 'cloud_credentials.dart';
import 'cloud_playback_helpers.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';
import 'stremio_torrent_resolve_args.dart';

class AllDebridCloudProvider implements CloudProviderPort {
  const AllDebridCloudProvider();

  @override
  CloudProviderId get id => CloudProviderId.alldebrid;

  @override
  Future<bool> isConfigured() => CloudCredentials.isPlaybackConfigured(id);

  @override
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent) async {
    final title = torrent.displayTitle;
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    final result = await AllDebridService.addMagnetAndResolveFiles(
      apiKey,
      magnet,
    );
    void open() => MainPageBridge.openAllDebridFolder?.call();
    final videos = result.files
        .where((f) => FileUtils.isVideoFile(f.path))
        .toList();
    if (videos.length <= 1) {
      final file = videos.isNotEmpty
          ? videos.first
          : CloudPlaybackHelpers.pickLargest(
              result.files,
              (f) => f.path,
              (f) => f.size,
            );
      final playUrl = file == null
          ? null
          : await AllDebridService.unlockLink(apiKey, file.link);
      return CloudPlaybackResult(
        title: title,
        playUrl: playUrl,
        downloadUrls: playUrl != null ? [playUrl] : const [],
        openInTab: open,
        fileName: file == null
            ? null
            : CloudPlaybackHelpers.fileName(file.path),
        allDebridLink: file?.link,
      );
    }
    final (sorted, startIndex) = CloudPlaybackHelpers.orderBySeries(
      videos,
      (f) => f.path,
    );
    final startUrl = await AllDebridService.unlockLink(
      apiKey,
      sorted[startIndex].link,
    );
    final entries = [
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: CloudPlaybackHelpers.fileName(sorted[i].path),
          provider: 'alldebrid',
          allDebridLink: sorted[i].link,
          sizeBytes: sorted[i].size,
          torrentHash: torrent.infohash,
        ),
    ];
    return CloudPlaybackResult(
      title: title,
      playUrl: startUrl,
      downloadUrls: [startUrl],
      openInTab: open,
      playlist: entries,
      startIndex: startIndex,
    );
  }

  @override
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  }) async {
    if (source.cloudSourceKind != SeriesSource.cloudKindWebDownload) {
      return null;
    }
    final sourceId = source.debridTorrentId.trim();
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    if (apiKey.isEmpty) return null;
    final links = await AllDebridService.listSavedLinks(apiKey);
    final matching = links.where(
      (link) => SeriesSource.opaqueCloudReference(link.link) == sourceId,
    );
    if (matching.isEmpty) return null;
    final link = matching.first;
    final url = await AllDebridService.unlockLink(apiKey, link.link);
    if (url.isEmpty) return null;
    return CloudPlaybackResult(
      title: source.torrentName,
      playUrl: url,
      downloadUrls: [url],
      fileName: link.fileName,
    );
  }

  @override
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry) async {
    final link = entry.allDebridLink;
    if (link == null || link.isEmpty) return null;
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    return AllDebridService.unlockLink(apiKey, link);
  }

  @override
  Future<String> unlockPlaybackEntry(PlaylistEntry entry) async {
    final lockedLink = entry.allDebridLink;
    if (lockedLink == null || lockedLink.isEmpty) {
      throw Exception('AllDebrid link metadata missing');
    }
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Missing AllDebrid API key');
    }
    final url = await AllDebridService.unlockLink(apiKey, lockedLink);
    if (url.isEmpty) {
      throw Exception('AllDebrid returned an empty stream URL');
    }
    return url;
  }

  @override
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;
    try {
      AllDebridAddResult result;
      try {
        result = await AllDebridService.addMagnetAndResolveFiles(
          apiKey,
          args.magnet,
        );
      } on AllDebridTorrentNotReadyException catch (e) {
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        return null;
      }

      final videoFiles = result.files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      if (videoFiles.isEmpty) return null;

      String targetLink = videoFiles.first.link;

      if (args.isSeries && args.season != null && args.episode != null) {
        final candidateNames = videoFiles.map((f) => f.path).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: args.torrent.name,
              season: args.season!,
              episode: args.episode!,
            );
        if (targetIndex == null || targetIndex >= videoFiles.length) {
          debugPrint(
            'StremioTV: AllDebrid could not match S${args.season}E${args.episode} in '
            '${args.torrent.name}, rejecting source',
          );
          try {
            await AllDebridService.deleteMagnet(apiKey, result.magnetId);
          } catch (_) {}
          return null;
        } else {
          targetLink = videoFiles[targetIndex].link;
        }
      } else if (args.isMovie && videoFiles.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          videoFiles.map<int?>((f) => f.size).toList(),
        );
        if (targetIndex < videoFiles.length) {
          targetLink = videoFiles[targetIndex].link;
        }
      }

      if (targetLink.isEmpty) return null;
      final url = await AllDebridService.unlockLink(apiKey, targetLink);
      return url.isEmpty ? null : url;
    } catch (e) {
      debugPrint('StremioTV: AllDebrid resolve error: $e');
      return null;
    }
  }
}
