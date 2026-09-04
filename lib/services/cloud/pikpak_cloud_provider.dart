import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../../utils/series_parser.dart';
import '../../utils/stremio_episode_selector.dart';
import '../../utils/stremio_tv_debrid_fallback.dart';
import '../main_page_bridge.dart';
import '../pikpak_api_service.dart';
import '../pikpak_tv_service.dart';
import '../series_source_service.dart';
import 'cloud_credentials.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_helpers.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';
import 'magic_tv_prepare_args.dart';
import 'stremio_torrent_resolve_args.dart';

class PikPakCloudProvider extends CloudProviderAdapter
    implements CloudUnlock, CloudMagnetAdd, CloudMagicTvPrepare {
  const PikPakCloudProvider();

  @override
  CloudProviderId get id => CloudProviderId.pikpak;

  @override
  Future<bool> isConfigured() =>
      CloudCredentials.configured(id, CloudSurface.playback);

  @override
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent) async {
    final title = torrent.displayTitle;
    final pikpak = PikPakApiService.instance;
    final add = await pikpak.addOfflineDownload(magnet);
    String? fileId;
    String? taskId;
    if (add['file'] != null) {
      fileId = add['file']['id']?.toString();
    } else if (add['task'] != null) {
      fileId = add['task']['file_id']?.toString();
      taskId = add['task']['id']?.toString();
    } else if (add['id'] != null) {
      fileId = add['id']?.toString();
    }
    if (fileId == null) throw Exception('PikPak: no file id returned');

    const pollInterval = Duration(seconds: 2);
    var phase1 = false;
    if (taskId != null) {
      for (var a = 0; a < 7; a++) {
        if (a > 0) await Future.delayed(pollInterval);
        try {
          final t = await pikpak.getTaskStatus(taskId);
          final phase = t['phase'];
          if (phase == 'PHASE_TYPE_COMPLETE') {
            phase1 = true;
            break;
          }
          if (phase == 'PHASE_TYPE_ERROR') {
            throw const PikPakFailed();
          }
          final rp = t['progress'];
          if (rp != null) {
            final p = rp is int ? rp : int.tryParse(rp.toString()) ?? 0;
            if (p >= 90) {
              phase1 = true;
              break;
            }
          }
        } on PikPakFailed {
          rethrow;
        } catch (_) {
          break;
        }
      }
    }

    List<Map<String, dynamic>> videoFiles = const [];
    for (var a = 0; a < 5; a++) {
      if (a > 0 || !phase1) await Future.delayed(pollInterval);
      try {
        final fd = await pikpak.getFileDetails(fileId);
        if (fd['phase'] == 'PHASE_TYPE_COMPLETE') {
          if (fd['kind'] == 'drive#folder') {
            videoFiles = await extractPikPakVideos(pikpak, fileId);
          } else {
            final mt = (fd['mime_type'] ?? '').toString();
            if (mt.startsWith('video/')) videoFiles = [fd];
          }
          break;
        }
        if (fd['phase'] == 'PHASE_TYPE_ERROR') {
          throw const PikPakFailed();
        }
      } on PikPakFailed {
        rethrow;
      } catch (_) {}
    }
    if (videoFiles.isEmpty) {
      throw const PikPakStillProcessing();
    }

    final playlist = await buildPikPakPlaylist(
      torrent.name,
      videoFiles,
      pikpak,
    );
    if (playlist == null || playlist.isEmpty) {
      throw Exception('PikPak: could not resolve a playable stream.');
    }
    var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
    if (startIndex < 0) startIndex = 0;
    final capturedFileId = fileId;
    return CloudPlaybackResult(
      title: title,
      playUrl: playlist[startIndex].url,
      downloadUrls: playlist[startIndex].url.isNotEmpty
          ? [playlist[startIndex].url]
          : const [],
      openInTab: () =>
          MainPageBridge.openPikPakFolder?.call(capturedFileId, title),
      playlist: playlist.length > 1 ? playlist : null,
      startIndex: startIndex,
      fileName: playlist.length == 1 ? playlist.first.title : null,
      pikpakFileId: capturedFileId,
      pikpakVideoFileId: playlist.length == 1
          ? playlist.first.pikpakFileId
          : null,
    );
  }

  @override
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  }) async {
    final sourceId = source.debridTorrentId.trim();
    final pikpak = PikPakApiService.instance;
    if (source.cloudSourceKind == SeriesSource.cloudKindFile) {
      final data = await pikpak.getFileDetails(sourceId);
      if (data['phase'] != 'PHASE_TYPE_COMPLETE') return null;
      final url = pikpak.getStreamingUrl(data);
      if (url == null || url.isEmpty) return null;
      final name = (data['name'] ?? source.torrentName).toString();
      return CloudPlaybackResult(
        title: source.torrentName,
        playUrl: url,
        downloadUrls: [url],
        fileName: name,
        pikpakFileId: sourceId,
        pikpakVideoFileId: sourceId,
      );
    }

    final all = await pikpak.listFilesRecursive(
      folderId: sourceId,
      includePaths: true,
    );
    final videos = all.where((file) {
      final name = file['name']?.toString() ?? '';
      final mime = file['mime_type']?.toString() ?? '';
      return mime.startsWith('video/') || FileUtils.isVideoFile(name);
    }).toList();
    if (videos.isEmpty) return null;
    if (contentType != 'series') {
      int sizeOf(Map<String, dynamic> file) =>
          int.tryParse(file['size']?.toString() ?? '') ?? 0;
      final video = videos.reduce((a, b) => sizeOf(a) >= sizeOf(b) ? a : b);
      final videoId = video['id']?.toString() ?? '';
      if (videoId.isEmpty) return null;
      final data = await pikpak.getFileDetails(videoId);
      if (data['phase'] != 'PHASE_TYPE_COMPLETE') return null;
      final url = pikpak.getStreamingUrl(data);
      if (url == null || url.isEmpty) return null;
      return CloudPlaybackResult(
        title: source.torrentName,
        playUrl: url,
        downloadUrls: [url],
        fileName:
            video['_fullPath']?.toString() ??
            video['name']?.toString() ??
            source.torrentName,
        pikpakFileId: sourceId,
        pikpakVideoFileId: videoId,
      );
    }
    final playlist = await PikPakCloudProvider.buildPikPakPlaylist(
      source.torrentName,
      videos,
      pikpak,
    );
    if (playlist == null || playlist.isEmpty) return null;
    var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
    if (startIndex < 0) startIndex = 0;
    final playUrl = playlist[startIndex].url;
    if (playUrl.isEmpty) return null;
    return CloudPlaybackResult(
      title: source.torrentName,
      playUrl: playUrl,
      downloadUrls: [playUrl],
      playlist: playlist.length > 1 ? playlist : null,
      startIndex: startIndex,
      fileName: playlist.length == 1 ? playlist.first.title : null,
      pikpakFileId: sourceId,
      pikpakVideoFileId: playlist.length == 1
          ? playlist.first.pikpakFileId
          : null,
    );
  }

  @override
  Future<String> unlockPlaybackEntry(PlaylistEntry entry) async {
    final fileId = entry.pikpakFileId;
    if (fileId == null) {
      throw const CloudMetadataMissing('PikPak file metadata missing');
    }
    final pikpak = PikPakApiService.instance;
    final fileData = await pikpak.getFileDetails(fileId);
    final url = pikpak.getStreamingUrl(fileData);
    if (url == null || url.isEmpty) {
      throw Exception('PikPak returned an empty stream URL');
    }
    return url;
  }

  @override
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args) async {
    if (!await CloudCredentials.configured(id, CloudSurface.playback)) {
      return null;
    }
    Map<String, dynamic>? preparedForCleanup;
    var keepPreparedItem = false;
    try {
      final prepared = await PikPakTvService.instance.prepareTorrent(
        infohash: args.torrent.infohash.trim().toLowerCase(),
        torrentName: args.torrent.name,
      );

      if (prepared == null) return null;
      preparedForCleanup = prepared;
      if (args.isCancelled?.call() ?? false) return null;

      String? streamUrl = prepared['url'] as String?;

      final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;
      if (args.isSeries &&
          args.season != null &&
          args.episode != null &&
          (allVideoFiles == null || allVideoFiles.isEmpty)) {
        final directNames = <String>[
          if ((prepared['title'] as String?)?.trim().isNotEmpty == true)
            (prepared['title'] as String).trim(),
          args.torrent.name,
        ];
        final directMatch = StremioEpisodeSelector.namesContainEpisode(
          directNames,
          season: args.season!,
          episode: args.episode!,
        );
        if (!directMatch) {
          debugPrint(
            'StremioTV: PikPak single file could not verify '
            'S${args.season}E${args.episode} in ${args.torrent.name}, rejecting source',
          );
          return null;
        }
      }
      if (allVideoFiles != null && allVideoFiles.isNotEmpty) {
        Map<String, dynamic>? targetFile;
        if (args.isSeries && args.season != null && args.episode != null) {
          final candidateNames = allVideoFiles.map((file) {
            if (file is! Map<String, dynamic>) return '';
            return (file['_fullPath'] as String?) ??
                (file['name'] as String?) ??
                '';
          }).toList();
          final targetIndex =
              StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
                candidateNames,
                sourceName: args.torrent.name,
                season: args.season!,
                episode: args.episode!,
              );
          if (targetIndex == null || targetIndex >= allVideoFiles.length) {
            debugPrint(
              'StremioTV: PikPak could not match S${args.season}E${args.episode} in ${args.torrent.name}, '
              'rejecting source',
            );
            return null;
          } else {
            final file = allVideoFiles[targetIndex];
            if (file is Map<String, dynamic>) {
              targetFile = file;
            }
          }
        } else if (args.isMovie) {
          final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
            allVideoFiles.map((file) {
              if (file is! Map<String, dynamic>) return null;
              return file['size'] as int?;
            }).toList(),
          );
          final file = allVideoFiles[targetIndex];
          if (file is Map<String, dynamic>) {
            targetFile = file;
          }
        }

        if (targetFile != null) {
          final targetFileId = targetFile['id'] as String?;
          if (targetFileId == null || targetFileId.isEmpty) return null;

          final api = PikPakApiService.instance;
          final fileData = await api.getFileDetails(targetFileId);
          final url = api.getStreamingUrl(fileData);
          if (url == null || url.isEmpty) return null;
          streamUrl = url;
        } else if (args.isSeries &&
            args.season != null &&
            args.episode != null) {
          return null;
        }
      }

      if (streamUrl == null ||
          streamUrl.isEmpty ||
          (args.isCancelled?.call() ?? false)) {
        return null;
      }

      keepPreparedItem = true;
      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: PikPak resolve error: $e');
      return null;
    } finally {
      if (preparedForCleanup != null && !keepPreparedItem) {
        await _trashRejectedPikPakItem(preparedForCleanup);
      }
    }
  }

  Future<void> _trashRejectedPikPakItem(Map<String, dynamic> prepared) async {
    final rootId = StremioTvDebridFallback.pikPakCleanupRootId(prepared);
    if (rootId == null) return;

    try {
      await PikPakApiService.instance
          .batchTrashFiles(<String>[rootId])
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('StremioTV: Failed to trash rejected PikPak item $rootId: $e');
    }
  }

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    if (request.infohash.isEmpty) return null;

    request.log('⏳ PikPak: preparing ${request.torrent.name}');

    final prepared = await PikPakTvService.instance.prepareTorrent(
      infohash: request.infohash,
      torrentName: request.torrent.name,
      onLog: request.log,
    );

    if (prepared == null) {
      request.log('⚠️ PikPak torrent not ready ${request.torrent.name}');
      return null;
    }

    final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;

    if (allVideoFiles == null || allVideoFiles.isEmpty) {
      request.log('🎬 PikPak: streaming ${prepared['title']}');
      return MagicTvPrepared(
        streamUrl: prepared['url'] as String,
        title: prepared['title'] as String,
        hasMore: false,
      );
    }

    final pikpakFolderId = prepared['pikpakFolderId'] as String?;
    if (pikpakFolderId == null) {
      request.log('⚠️ PikPak multi-file torrent missing folder ID');
      return null;
    }

    List<dynamic> filterUnseen({required bool applySizeFilter}) {
      return allVideoFiles.where((file) {
        final fileId = file['id'] as String?;
        if (fileId == null || fileId.isEmpty) return false;
        final trackingKey = '${request.infohash}|$fileId';
        if (request.seenKeys.contains(trackingKey)) return false;
        final size = (file['size'] as num?)?.toInt() ?? 0;
        if (size > 0 && size < request.minVideoSizeBytes) return false;
        if (applySizeFilter && !request.sizeMatchesBytes(size)) return false;
        return true;
      }).toList();
    }

    var unseenFiles = filterUnseen(applySizeFilter: true);
    if (unseenFiles.isEmpty && request.hasSizeFilter) {
      request.log(
        '⚠️ PikPak: no file matched the size filter — using unfiltered',
      );
      unseenFiles = filterUnseen(applySizeFilter: false);
    }

    if (unseenFiles.isEmpty) {
      request.log(
        '⚠️ PikPak torrent has no unseen files ${request.torrent.name}',
      );
      return null;
    }

    unseenFiles.shuffle(Random());
    final selectedFile = unseenFiles.removeAt(0);
    final selectedFileId = selectedFile['id'] as String?;
    final selectedFileName = selectedFile['name'] as String?;

    if (selectedFileId == null ||
        selectedFileId.isEmpty ||
        selectedFileName == null ||
        selectedFileName.isEmpty) {
      request.log('⚠️ Selected file has invalid ID or name');
      return null;
    }

    request.log(
      '🎬 PikPak: selected $selectedFileName (${unseenFiles.length} unseen files)',
    );

    String streamUrl;
    try {
      final api = PikPakApiService.instance;
      final fullFileData = await api.getFileDetails(selectedFileId);
      final url = api.getStreamingUrl(fullFileData);
      if (url == null || url.isEmpty) {
        request.log('⚠️ No streaming URL for selected file');
        return null;
      }
      streamUrl = url;
    } catch (e) {
      request.log('❌ Failed to get streaming URL: $e');
      return null;
    }

    request.seenKeys.add('${request.infohash}|$selectedFileId');

    return MagicTvPrepared(
      streamUrl: streamUrl,
      title: selectedFileName,
      hasMore: unseenFiles.isNotEmpty,
    );
  }

  static Future<List<Map<String, dynamic>>> extractPikPakVideos(
    PikPakApiService pikpak,
    String folderId, {
    int maxDepth = 5,
    int currentDepth = 0,
    String currentPath = '',
  }) async {
    if (currentDepth >= maxDepth) return [];
    final videos = <Map<String, dynamic>>[];
    try {
      final result = await pikpak.listFiles(parentId: folderId);
      for (final file in result.files) {
        final kind = file['kind'] ?? '';
        final mimeType = (file['mime_type'] ?? '').toString();
        final itemName = (file['name'] ?? 'unknown').toString();
        if (kind == 'drive#folder') {
          final subPath = currentPath.isEmpty
              ? itemName
              : '$currentPath/$itemName';
          videos.addAll(
            await extractPikPakVideos(
              pikpak,
              file['id'].toString(),
              maxDepth: maxDepth,
              currentDepth: currentDepth + 1,
              currentPath: subPath,
            ),
          );
        } else if (mimeType.startsWith('video/')) {
          final videoWithPath = Map<String, dynamic>.from(file);
          if (currentPath.isNotEmpty) {
            videoWithPath['name'] = '$currentPath/$itemName';
          }
          videos.add(videoWithPath);
        }
      }
    } catch (_) {}
    videos.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );
    return videos;
  }

  static Future<List<PlaylistEntry>?> buildPikPakPlaylist(
    String torrentName,
    List<Map<String, dynamic>> videoFiles,
    PikPakApiService pikpak,
  ) async {
    if (videoFiles.isEmpty) return null;
    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final fullData = await pikpak.getFileDetails(file['id'].toString());
        final url = pikpak.getStreamingUrl(fullData);
        if (url == null) return null;
        return [
          PlaylistEntry(
            url: url,
            title: (file['name'] ?? torrentName).toString(),
            relativePath: file['_fullPath'] as String?,
            provider: 'pikpak',
            pikpakFileId: file['id']?.toString(),
            sizeBytes: int.tryParse(file['size']?.toString() ?? '0') ?? 0,
          ),
        ];
      } catch (_) {
        return null;
      }
    }

    final items = <_PikPakItem>[
      for (final file in videoFiles)
        _PikPakItem(
          file: file,
          seriesInfo: SeriesParser.parseFilename(_pikpakDisplayName(file)),
          displayName: _pikpakDisplayName(file),
        ),
    ];
    final fnames = items.map((e) => e.displayName).toList();
    final isSeriesCollection =
        items.length > 1 && SeriesParser.isSeriesPlaylist(fnames);

    final sorted = [...items];
    if (isSeriesCollection) {
      sorted.sort((a, b) {
        final sc = (a.seriesInfo.season ?? 0).compareTo(
          b.seriesInfo.season ?? 0,
        );
        if (sc != 0) return sc;
        final ec = (a.seriesInfo.episode ?? 0).compareTo(
          b.seriesInfo.episode ?? 0,
        );
        if (ec != 0) return ec;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    } else {
      sorted.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }

    final seriesInfos = sorted.map((e) => e.seriesInfo).toList();
    var startIndex = isSeriesCollection
        ? CloudPlaybackHelpers.firstEpisodeIndex(seriesInfos)
        : 0;
    if (startIndex < 0 || startIndex >= sorted.length) startIndex = 0;

    String initialUrl = '';
    try {
      final fullData = await pikpak.getFileDetails(
        sorted[startIndex].file['id'].toString(),
      );
      initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
    } catch (_) {
      return null;
    }
    if (initialUrl.isEmpty) return null;

    final entries = <PlaylistEntry>[];
    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final episodeLabel = _formatPikPakTitle(
        info: entry.seriesInfo,
        fallback: entry.displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _combineTitle(
        seriesTitle: entry.seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: entry.displayName,
      );
      entries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath: entry.file['_fullPath'] as String?,
          provider: 'pikpak',
          pikpakFileId: entry.file['id']?.toString(),
          sizeBytes: int.tryParse(entry.file['size']?.toString() ?? '0'),
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }

  static String _pikpakDisplayName(Map<String, dynamic> file) {
    final name = file['name']?.toString() ?? '';
    if (name.isNotEmpty) return FileUtils.getFileName(name);
    return 'File ${file['id']}';
  }

  static String _formatPikPakTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      final desc = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : (info.title?.trim().isNotEmpty == true
                ? info.title!.trim()
                : fallback);
      return 'S${s}E$e · $desc';
    }
    return fallback;
  }

  static String _combineTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final clean = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (clean != null && clean.isNotEmpty) return '$clean $episodeLabel';
    return fallback;
  }
}

class _PikPakItem {
  final Map<String, dynamic> file;
  final SeriesInfo seriesInfo;
  final String displayName;
  const _PikPakItem({
    required this.file,
    required this.seriesInfo,
    required this.displayName,
  });
}
