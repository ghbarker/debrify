import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/torbox_file.dart';
import '../../models/torbox_torrent.dart';
import '../../models/torbox_web_download.dart';
import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../../utils/stremio_episode_selector.dart';
import '../main_page_bridge.dart';
import '../series_source_service.dart';
import '../torbox_service.dart';
import '../torbox_torrent_control_service.dart';
import 'cloud_credentials.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_helpers.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';
import 'magic_tv_playable.dart';
import 'magic_tv_prepare_args.dart';
import 'stremio_torrent_resolve_args.dart';

class TorboxCloudProvider extends CloudProviderAdapter {
  const TorboxCloudProvider();

  @override
  CloudProviderId get id => CloudProviderId.torbox;

  @override
  Future<bool> isConfigured() => CloudCredentials.isPlaybackConfigured(id);

  @override
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent) async {
    final title = torrent.displayTitle;
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    final resp = await TorboxService.createTorrent(
      apiKey: apiKey,
      magnet: magnet,
      addOnlyIfCached: true,
    );
    final ok =
        resp['success'] == true ||
        resp['error'].toString().contains('ALREADY_ADDED');
    if (!ok) {
      if (resp['error'].toString().contains('NOT_CACHED')) {
        throw const TorboxNotCached();
      }
      throw Exception(resp['error']?.toString() ?? 'TorBox add failed');
    }
    final data = resp['data'];
    final torrentId = data is Map
        ? (data['torrent_id'] as num?)?.toInt()
        : null;
    if (torrentId == null) throw Exception('TorBox: no torrent id');
    final tt = await TorboxService.getTorrentById(apiKey, torrentId);
    final open = tt == null
        ? null
        : () => MainPageBridge.openTorboxFolder?.call(tt);
    final videos = (tt?.files ?? const <TorboxFile>[])
        .where((f) => FileUtils.isVideoFile(f.name))
        .toList();
    if (videos.length <= 1) {
      final file = videos.isNotEmpty
          ? videos.first
          : CloudPlaybackHelpers.pickLargest(
              tt?.files ?? const <TorboxFile>[],
              (f) => f.name,
              (f) => f.size,
            );
      final playUrl = file == null
          ? null
          : await TorboxService.requestFileDownloadLink(
              apiKey: apiKey,
              torrentId: torrentId,
              fileId: file.id,
            );
      return CloudPlaybackResult(
        title: title,
        playUrl: playUrl,
        downloadUrls: playUrl != null ? [playUrl] : const [],
        openInTab: open,
        fileName: file == null
            ? null
            : CloudPlaybackHelpers.fileName(file.name),
        torboxTorrentId: torrentId,
        torboxFileId: file?.id,
      );
    }
    final (sorted, startIndex) = CloudPlaybackHelpers.orderBySeries(
      videos,
      (f) => f.name,
    );
    final startUrl = await TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrentId,
      fileId: sorted[startIndex].id,
    );
    final entries = [
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: CloudPlaybackHelpers.fileName(sorted[i].name),
          provider: 'torbox',
          torboxTorrentId: torrentId,
          torboxFileId: sorted[i].id,
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
      torboxTorrentId: torrentId,
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
    final webId = int.tryParse(sourceId);
    if (apiKey.isEmpty || webId == null) return null;
    final result = await TorboxService.getWebDownloads(apiKey, webId: webId);
    final downloads = (result['webDownloads'] as List)
        .cast<TorboxWebDownload>();
    if (downloads.isEmpty) return null;
    final download = downloads.firstWhere(
      (candidate) => candidate.id == webId,
      orElse: () => downloads.first,
    );
    final videos = download.files.where((file) {
      if (file.zipped) return false;
      final name = file.shortName.isNotEmpty
          ? file.shortName
          : FileUtils.getFileName(file.name);
      return (file.mimetype?.startsWith('video/') ?? false) ||
          FileUtils.isVideoFile(name);
    }).toList();
    if (videos.isEmpty) return null;

    String displayName(TorboxFile file) => file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    String relativePath(TorboxFile file) =>
        (file.absolutePath?.isNotEmpty ?? false)
        ? file.absolutePath!
        : file.name;

    if (contentType != 'series') {
      final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
      final url = await TorboxService.requestWebDownloadFileLink(
        apiKey: apiKey,
        webId: webId,
        fileId: video.id,
      );
      if (url.isEmpty) return null;
      return CloudPlaybackResult(
        title: source.torrentName,
        playUrl: url,
        downloadUrls: [url],
        fileName: displayName(video),
      );
    }

    final (sorted, startIndex) = CloudPlaybackHelpers.orderBySeries(
      videos,
      relativePath,
    );
    final entries = <PlaylistEntry>[
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: '',
          title: relativePath(sorted[i]),
          relativePath: relativePath(sorted[i]),
          provider: 'torbox',
          torboxWebDownloadId: webId,
          torboxFileId: sorted[i].id,
          sizeBytes: sorted[i].size > 0 ? sorted[i].size : null,
        ),
    ];
    final playUrl = await TorboxService.requestWebDownloadFileLink(
      apiKey: apiKey,
      webId: webId,
      fileId: sorted[startIndex].id,
    );
    if (playUrl.isEmpty) return null;
    entries[startIndex] = PlaylistEntry(
      url: playUrl,
      title: entries[startIndex].title,
      relativePath: entries[startIndex].relativePath,
      provider: entries[startIndex].provider,
      torboxWebDownloadId: webId,
      torboxFileId: sorted[startIndex].id,
      sizeBytes: entries[startIndex].sizeBytes,
    );
    return CloudPlaybackResult(
      title: source.torrentName,
      playUrl: playUrl,
      downloadUrls: [playUrl],
      playlist: entries.length > 1 ? entries : null,
      startIndex: startIndex,
      fileName: entries.length == 1 ? entries.first.title : null,
    );
  }

  @override
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry) async {
    final torrentId = entry.torboxTorrentId;
    final fileId = entry.torboxFileId;
    if (torrentId == null || fileId == null) return null;
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    return TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrentId,
      fileId: fileId,
    );
  }

  @override
  Future<String> unlockPlaybackEntry(PlaylistEntry entry) async {
    final torrentId = entry.torboxTorrentId;
    final webDownloadId = entry.torboxWebDownloadId;
    final fileId = entry.torboxFileId;
    if (fileId == null || (torrentId == null && webDownloadId == null)) {
      throw const CloudMetadataMissing('Torbox file metadata missing');
    }
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) {
      throw const CloudMissingApiKey('Missing Torbox API key');
    }
    final String url;
    if (webDownloadId != null) {
      url = await TorboxService.requestWebDownloadFileLink(
        apiKey: apiKey,
        webId: webDownloadId,
        fileId: fileId,
      );
    } else {
      url = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torrentId!,
        fileId: fileId,
      );
    }
    if (url.isEmpty) {
      throw Exception('Torbox returned an empty stream URL');
    }
    return url;
  }

  @override
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;
    int? createdTorrentId;
    var keepTorrent = false;
    try {
      final result = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: args.magnet,
      );
      final data = result['data'];
      final rawTorrentId = data is Map
          ? (data['torrent_id'] ?? data['id'])
          : (result['torrent_id'] ?? result['id']);

      createdTorrentId = rawTorrentId is int
          ? rawTorrentId
          : int.tryParse(rawTorrentId?.toString() ?? '');
      if (createdTorrentId == null) return null;

      await Future.delayed(const Duration(seconds: 3));
      if (args.isCancelled?.call() ?? false) return null;

      final torrentInfo = await TorboxService.getTorrentById(
        apiKey,
        createdTorrentId,
      );

      if (torrentInfo == null || (args.isCancelled?.call() ?? false)) {
        return null;
      }

      final allFiles = torrentInfo.files;
      final videoFiles = allFiles
          .where((f) => FileUtils.isVideoFile(f.name))
          .toList();
      final files = videoFiles.isNotEmpty ? videoFiles : allFiles;
      if (files.isEmpty) return null;

      var targetFile = files.first;
      if (args.isSeries && args.season != null && args.episode != null) {
        if (files.length > 1) {
          final fallbackIndex = StremioEpisodeSelector.findLargestFileIndex(
            files.map((f) => f.size).toList(),
          );
          targetFile = files[fallbackIndex];
        }
        final candidateNames = files
            .map((f) => f.absolutePath ?? f.name)
            .toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: args.torrent.name,
              season: args.season!,
              episode: args.episode!,
            );
        if (targetIndex == null || targetIndex >= files.length) {
          debugPrint(
            'StremioTV: Torbox could not match S${args.season}E${args.episode} in ${args.torrent.name}, '
            'rejecting source',
          );
          return null;
        } else {
          targetFile = files[targetIndex];
        }
      } else if (args.isMovie && files.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          files.map((f) => f.size).toList(),
        );
        targetFile = files[targetIndex];
      } else if (files.length > 1) {
        for (final f in files) {
          if (f.size > targetFile.size) {
            targetFile = f;
          }
        }
      }

      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: createdTorrentId,
        fileId: targetFile.id,
      );
      if (streamUrl.isEmpty || (args.isCancelled?.call() ?? false)) return null;

      keepTorrent = true;
      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: Torbox resolve error: $e');
      return null;
    } finally {
      if (createdTorrentId != null && !keepTorrent) {
        try {
          await TorboxTorrentControlService.deleteTorrent(
            apiKey: apiKey,
            torrentId: createdTorrentId,
          ).timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint(
            'StremioTV: Failed to delete rejected TorBox torrent '
            '$createdTorrentId: $e',
          );
        }
      }
    }
  }

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    if (request.infohash.isEmpty) return null;
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;

    request.log('⏳ Torbox: preparing ${request.torrent.name}');

    Map<String, dynamic> response;
    try {
      response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: request.magnet,
        seed: true,
        allowZip: false,
        addOnlyIfCached: true,
      );
    } catch (e) {
      request.log('❌ Torbox createtorrent failed: $e');
      return null;
    }

    final success = response['success'] as bool? ?? false;
    if (!success) {
      final error = (response['error'] ?? '').toString();
      request.log('⚠️ Torbox createtorrent error: $error');
      return null;
    }

    final data = response['data'];
    final torrentId = _asIntMapValue(data, 'torrent_id');
    if (torrentId == null) {
      request.log('⚠️ Torbox createtorrent missing torrent_id');
      return null;
    }

    TorboxTorrent? torboxTorrent;
    for (int attempt = 0; attempt < 6; attempt++) {
      torboxTorrent = await TorboxService.getTorrentById(
        apiKey,
        torrentId,
        attempts: 1,
      );
      if (torboxTorrent != null && torboxTorrent.files.isNotEmpty) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (torboxTorrent == null || torboxTorrent.files.isEmpty) {
      request.log(
        '⚠️ Torbox torrent details not ready for ${request.torrent.name}',
      );
      return null;
    }

    final currentTorrent = torboxTorrent;

    final playableEntries = MagicTvPlayable.buildTorboxEntries(
      currentTorrent,
      request.torrent.name,
      request,
    );
    if (playableEntries.isEmpty) {
      request.log(
        '⚠️ Torbox torrent has no playable files ${request.torrent.name}',
      );
      return null;
    }

    final filteredEntries = playableEntries
        .where(
          (entry) => !request.seenKeys.contains(
            '${currentTorrent.id}|${entry.file.id}',
          ),
        )
        .toList();
    if (filteredEntries.isEmpty) {
      request.log(
        '⚠️ Torbox torrent has no unseen playable files ${request.torrent.name}',
      );
      return null;
    }

    filteredEntries.shuffle(Random());
    final next = filteredEntries.removeAt(0);
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: currentTorrent.id,
        fileId: next.file.id,
      );
      request.log('🎬 Torbox: streaming ${next.title}');
      request.seenKeys.add('${currentTorrent.id}|${next.file.id}');
      return MagicTvPrepared(
        streamUrl: streamUrl,
        title: next.title,
        hasMore: filteredEntries.isNotEmpty,
      );
    } catch (e) {
      request.log('❌ Torbox requestdl failed: $e');
      return null;
    }
  }

  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) {
    throw const CloudUnsupported(
      CloudProviderId.torbox,
      CloudPortFeature.magicTvLockedLinks,
    );
  }

  static int? _asIntMapValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final value = data[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
    }
    return null;
  }
}
