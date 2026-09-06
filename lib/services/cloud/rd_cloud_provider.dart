import 'package:flutter/foundation.dart';

import '../../models/rd_torrent.dart';
import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../../utils/rd_folder_tree_builder.dart';
import '../../utils/series_parser.dart';
import '../../utils/stremio_episode_selector.dart';
import '../debrid_service.dart';
import '../main_page_bridge.dart';
import '../series_source_service.dart';
import 'cloud_credentials.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';
import 'magic_tv_prepare_args.dart';
import 'stremio_torrent_resolve_args.dart';

class RealDebridCloudProvider extends CloudProviderAdapter
    implements
        CloudUnlock,
        CloudMagnetAdd,
        CloudPlaylist,
        CloudMagicTvLockedLinks,
        CloudMagicTvRdUnlock,
        CloudMagicTvCapturedRdUnlock {
  const RealDebridCloudProvider();

  @override
  CloudProviderId get id => CloudProviderId.debrid;

  @override
  Future<bool> isConfigured() =>
      CloudCredentials.configured(id, CloudSurface.playback);

  @override
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent) async {
    final title = torrent.displayTitle;
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    final result = await DebridService.addTorrentToDebrid(apiKey, magnet);
    final playUrl = result['downloadLink'] as String?;
    final linksRaw = (result['links'] as List?) ?? const [];
    final filesRaw = (result['files'] as List?) ?? const [];
    final links = linksRaw.map((e) => e.toString()).toList();
    final isRar = filesRaw.isNotEmpty
        ? RDFolderTreeBuilder.isRarArchive(
            filesRaw.map((f) => f as Map<String, dynamic>).toList(),
            linksRaw,
          )
        : false;
    final rd = RDTorrent(
      id: result['torrentId']?.toString() ?? '',
      filename: title,
      hash: torrent.infohash,
      bytes: torrent.sizeBytes,
      host: '',
      split: 0,
      progress: 100,
      status: 'downloaded',
      added: DateTime.now().toIso8601String(),
      links: links,
    );
    void open() => MainPageBridge.openDebridOptions?.call(rd);
    final playlist = await buildRdPlaylist(linksRaw, filesRaw, apiKey);
    if (playlist != null && playlist.length > 1) {
      var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
      if (startIndex < 0) startIndex = 0;
      final start = playlist[startIndex].url.isNotEmpty
          ? playlist[startIndex].url
          : playUrl;
      return CloudPlaybackResult(
        title: title,
        playUrl: start,
        downloadUrls: playUrl != null ? [playUrl] : const [],
        openInTab: open,
        playlist: playlist,
        startIndex: startIndex,
        isRarArchive: isRar,
        rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
      );
    }
    return CloudPlaybackResult(
      title: title,
      playUrl: playUrl,
      downloadUrls: playUrl != null ? [playUrl] : const [],
      openInTab: open,
      fileName: (playlist != null && playlist.length == 1)
          ? playlist.first.title
          : null,
      isRarArchive: isRar,
      rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
      restrictedLink: links.isNotEmpty ? links.first : null,
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
    final download = await DebridService.getDownloadById(apiKey, sourceId);
    if (download == null) return null;
    var url = download.download;
    if (download.link.isNotEmpty) {
      try {
        final refreshed = await DebridService.unrestrictLink(
          apiKey,
          download.link,
        );
        final refreshedUrl = refreshed['download']?.toString() ?? '';
        if (refreshedUrl.isNotEmpty) url = refreshedUrl;
      } catch (_) {
        // The freshly listed download URL is still a useful fallback when
        // a host temporarily refuses to unrestrict the original link.
      }
    }
    if (url.isEmpty) return null;
    return CloudPlaybackResult(
      title: source.torrentName,
      playUrl: url,
      downloadUrls: [url],
      fileName: download.filename.isNotEmpty
          ? download.filename
          : source.torrentName,
    );
  }

  @override
  Future<CloudPlaylistResolve> resolvePlaylist(PlaylistEntry entry) async {
    final link = entry.restrictedLink;
    if (link == null || link.isEmpty) return const CloudPlaylistMiss();
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    final r = await DebridService.unrestrictLink(apiKey, link);
    final url = r['download']?.toString();
    if (url == null || url.isEmpty) return const CloudPlaylistMiss();
    return CloudPlaylistResolved(url);
  }

  @override
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry) async =>
      (await resolvePlaylist(entry)).urlOrNull;

  @override
  Future<String> unlockPlaybackEntry(PlaylistEntry entry) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) {
      throw const CloudMissingApiKey('Missing Real Debrid API key');
    }
    final unrestrictResult = await DebridService.unrestrictLink(
      apiKey,
      entry.restrictedLink!,
    );
    final url = unrestrictResult['download']?.toString() ?? '';
    if (url.isEmpty) {
      throw Exception('Real Debrid returned an empty stream URL');
    }
    return url;
  }

  /// Video-file filtering aligned to the `links` array, archive guard,
  /// [SeriesParser] first-episode detection, start entry unrestricted.
  static Future<List<PlaylistEntry>?> buildRdPlaylist(
    List<dynamic> links,
    List<dynamic> files,
    String apiKey,
  ) async {
    final selectedFiles = files.where((file) => file['selected'] == 1).toList();
    final allFilesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;

    final filesToUse = allFilesToUse.where((file) {
      String? filename =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      return filename != null && FileUtils.isVideoFile(filename);
    }).toList();

    if (filesToUse.length > 1 && links.length == 1) return null;
    if (filesToUse.isEmpty) return null;

    final filenames = filesToUse.map((file) {
      String? name =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (name != null && name.startsWith('/')) name = name.split('/').last;
      return name ?? 'Unknown File';
    }).toList();

    final isSeries = SeriesParser.isSeriesPlaylist(filenames);
    final seriesInfos = isSeries ? SeriesParser.parsePlaylist(filenames) : null;

    int firstIndex = 0;
    if (isSeries && seriesInfos != null) {
      int lowestSeason = 999, lowestEpisode = 999;
      for (int i = 0; i < seriesInfos.length; i++) {
        final info = seriesInfos[i];
        if (info.isSeries && info.season != null && info.episode != null) {
          if (info.season! < lowestSeason ||
              (info.season! == lowestSeason && info.episode! < lowestEpisode)) {
            lowestSeason = info.season!;
            lowestEpisode = info.episode!;
            firstIndex = i;
          }
        }
      }
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < filesToUse.length; i++) {
      final file = filesToUse[i];
      String? filename =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      String? relativePath = filename;
      if (relativePath != null && relativePath.startsWith('/')) {
        relativePath = relativePath.substring(1);
      }
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      final finalFilename = filename ?? 'Unknown File';
      final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;
      if (i >= links.length) continue;

      String url = '';
      if (i == firstIndex) {
        try {
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            links[i],
          );
          url = unrestrictResult['download']?.toString() ?? '';
        } catch (_) {
          url = '';
        }
      }
      entries.add(
        PlaylistEntry(
          url: url,
          title: finalFilename,
          relativePath: relativePath,
          restrictedLink: url.isEmpty ? links[i].toString() : null,
          sizeBytes: sizeBytes,
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }

  @override
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;
    try {
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        args.magnet,
      );

      final links = result['links'] as List<dynamic>? ?? [];
      final updatedInfo = result['updatedInfo'] as Map<String, dynamic>? ?? {};
      final files = updatedInfo['files'] as List<dynamic>? ?? [];

      if (links.isEmpty) return null;

      String linkToUnrestrict = links.first.toString();
      final selectedVideoFiles = <Map<String, dynamic>>[];
      final selectedVideoLinks = <String>[];
      int linkIndex = 0;
      for (final file in files) {
        if (file is! Map<String, dynamic>) continue;
        final selected = file['selected'] == 1 || file['selected'] == true;
        if (!selected) continue;
        final rawName =
            (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        if (FileUtils.isVideoFile(FileUtils.getFileName(rawName)) &&
            linkIndex < links.length) {
          selectedVideoFiles.add(file);
          selectedVideoLinks.add(links[linkIndex].toString());
        }
        linkIndex++;
      }

      if (args.isSeries && args.season != null && args.episode != null) {
        final candidateNames = selectedVideoFiles.map((file) {
          return (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        }).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: args.torrent.name,
              season: args.season!,
              episode: args.episode!,
            );
        if (targetIndex == null || targetIndex >= selectedVideoLinks.length) {
          debugPrint(
            'StremioTV: RD could not match S${args.season}E${args.episode} in ${args.torrent.name}, '
            'rejecting source',
          );
          final torrentId = result['torrentId']?.toString();
          if (torrentId != null && torrentId.isNotEmpty) {
            try {
              await DebridService.deleteTorrent(apiKey, torrentId);
            } catch (_) {}
          }
          return null;
        } else {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
        }
      } else if (args.isMovie && selectedVideoLinks.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          selectedVideoFiles.map((file) => file['bytes'] as int?).toList(),
        );
        if (targetIndex < selectedVideoLinks.length) {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
        }
      }

      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        linkToUnrestrict,
      );
      return unrestrictResult['download'] as String?;
    } catch (e) {
      debugPrint('StremioTV: RD resolve error: $e');
      return null;
    }
  }

  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;
    final result = await DebridService.addTorrentToDebridPreferVideos(
      apiKey,
      request.magnet,
    );
    final torrentId = result['torrentId'] as String? ?? '';
    final links = (result['links'] as List<dynamic>? ?? const [])
        .map((link) => link?.toString() ?? '')
        .where((link) => link.isNotEmpty && !request.seenKeys.contains(link))
        .toList();
    if (links.isEmpty) return null;
    return MagicTvLockedBatch(
      remoteId: torrentId,
      name: request.torrent.name,
      lockedLinks: links,
    );
  }

  /// Same Map as [DebridService.unrestrictLink]. Looks up the API key;
  /// Magic TV currently passes it.
  @override
  Future<Map<String, dynamic>> unrestrictLink(String link) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) {
      throw const CloudMissingApiKey('Missing Real Debrid API key');
    }
    return DebridService.unrestrictLink(apiKey, link);
  }

  /// Same Map as [DebridService.addTorrentToDebridPreferVideos]. Looks up
  /// the API key; Magic TV currently passes it.
  @override
  Future<Map<String, dynamic>> addTorrentPreferVideos(String magnet) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) {
      throw const CloudMissingApiKey('Missing Real Debrid API key');
    }
    return DebridService.addTorrentToDebridPreferVideos(apiKey, magnet);
  }

  @override
  Future<Map<String, dynamic>> unrestrictLinkWithKey(String apiKey, String link) =>
      DebridService.unrestrictLink(apiKey, link);

  @override
  Future<Map<String, dynamic>> addTorrentPreferVideosWithKey(
    String apiKey,
    String magnet,
  ) => DebridService.addTorrentToDebridPreferVideos(apiKey, magnet);
}
