import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/premiumize_file.dart';
import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../../utils/stremio_episode_selector.dart';
import '../main_page_bridge.dart';
import '../premiumize_service.dart';
import '../series_source_service.dart';
import 'cloud_credentials.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_helpers.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';
import 'magic_tv_playable.dart';
import 'magic_tv_prepare_args.dart';
import 'stremio_torrent_resolve_args.dart';

class PremiumizeCloudProvider implements CloudProviderPort {
  const PremiumizeCloudProvider();

  @override
  CloudProviderId get id => CloudProviderId.premiumize;

  @override
  Future<bool> isConfigured() => CloudCredentials.isPlaybackConfigured(id);

  @override
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent) async {
    final title = torrent.displayTitle;
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    if (!await PremiumizeService.isCached(apiKey, magnet)) {
      throw const PremiumizeNotCached();
    }
    final files = await PremiumizeService.directDownload(apiKey, magnet);
    void open() => MainPageBridge.openPremiumizeFolder?.call();
    final videos = files.where((f) => FileUtils.isVideoFile(f.path)).toList();
    if (videos.length <= 1) {
      final file = videos.isNotEmpty
          ? videos.first
          : CloudPlaybackHelpers.pickLargest(
              files,
              (f) => f.path,
              (f) => f.size,
            );
      return CloudPlaybackResult(
        title: title,
        playUrl: file?.link,
        downloadUrls: file?.link != null ? [file!.link] : const [],
        openInTab: open,
        fileName: file == null
            ? null
            : CloudPlaybackHelpers.fileName(file.path),
        premiumizePath: file?.path,
      );
    }
    final (sorted, startIndex) = CloudPlaybackHelpers.orderBySeries(
      videos,
      (f) => f.path,
    );
    final entries = [
      for (final f in sorted)
        PlaylistEntry(
          url: f.link,
          title: CloudPlaybackHelpers.fileName(f.path),
          provider: 'premiumize',
          premiumizeHash: torrent.infohash,
          premiumizePath: f.path,
          sizeBytes: f.size,
          torrentHash: torrent.infohash,
        ),
    ];
    return CloudPlaybackResult(
      title: title,
      playUrl: sorted[startIndex].link,
      downloadUrls: [sorted[startIndex].link],
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
    final sourceId = source.debridTorrentId.trim();
    final apiKey = (await CloudCredentials.apiKey(id)) ?? '';
    if (apiKey.isEmpty) return null;
    if (source.cloudSourceKind == SeriesSource.cloudKindFile) {
      final file = await PremiumizeService.resolveItemById(apiKey, sourceId);
      if (file == null || file.link.isEmpty) return null;
      return CloudPlaybackResult(
        title: source.torrentName,
        playUrl: file.link,
        downloadUrls: [file.link],
        fileName: file.path.isNotEmpty ? file.path : source.torrentName,
      );
    }

    final all = await PremiumizeService.listFolderRecursive(apiKey, sourceId);
    final videos = all.where((f) => f.isVideo).toList();
    if (videos.isEmpty) return null;
    if (contentType != 'series') {
      final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
      var url = video.playableUrl ?? '';
      if (url.isEmpty) {
        final resolved = await PremiumizeService.resolveItemById(
          apiKey,
          video.id,
        );
        url = resolved?.link ?? '';
      }
      if (url.isEmpty) return null;
      return CloudPlaybackResult(
        title: source.torrentName,
        playUrl: url,
        downloadUrls: [url],
        fileName: video.relativePath ?? video.name,
      );
    }
    final (sorted, startIndex) = CloudPlaybackHelpers.orderBySeries(
      videos,
      (f) => f.relativePath ?? f.name,
    );
    final entries = <PlaylistEntry>[
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: i == startIndex ? (sorted[i].playableUrl ?? '') : '',
          title: sorted[i].relativePath ?? sorted[i].name,
          relativePath: sorted[i].relativePath ?? sorted[i].name,
          provider: 'premiumize',
          premiumizeItemId: sorted[i].id,
          sizeBytes: sorted[i].size > 0 ? sorted[i].size : null,
        ),
    ];
    var playUrl = entries[startIndex].url;
    if (playUrl.isEmpty) {
      final resolved = await PremiumizeService.resolveItemById(
        apiKey,
        entries[startIndex].premiumizeItemId!,
      );
      playUrl = resolved?.link ?? '';
    }
    if (playUrl.isEmpty) return null;
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
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry) async => null;

  @override
  Future<String> unlockPlaybackEntry(PlaylistEntry entry) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Missing Premiumize API key');
    }
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final file = await PremiumizeService.resolveItemById(
        apiKey,
        entry.premiumizeItemId!,
      );
      if (file == null || file.link.isEmpty) {
        throw Exception('File not found in Premiumize cloud');
      }
      return file.link;
    }
    final hash = entry.premiumizeHash;
    final path = entry.premiumizePath;
    final files = await PremiumizeService.resolveFilesByHash(apiKey, hash!);
    final match = files.firstWhere(
      (f) => f.path == path,
      orElse: () => throw Exception('File not found in Premiumize cloud'),
    );
    if (match.link.isEmpty) {
      throw Exception('Premiumize returned an empty stream URL');
    }
    return match.link;
  }

  @override
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args) async {
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;
    try {
      final files = await PremiumizeService.directDownload(apiKey, args.magnet);

      if (files.isEmpty) return null;

      final videoFiles = files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      final candidates = videoFiles.isNotEmpty ? videoFiles : files;

      PremiumizeFile? targetFile;
      if (args.isSeries && args.season != null && args.episode != null) {
        final candidateNames = candidates.map((f) => f.path).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: args.torrent.name,
              season: args.season!,
              episode: args.episode!,
            );
        if (targetIndex != null && targetIndex < candidates.length) {
          targetFile = candidates[targetIndex];
        } else {
          debugPrint(
            'StremioTV: Premiumize could not match S${args.season}E${args.episode} in '
            '${args.torrent.name}, rejecting source',
          );
          return null;
        }
      }
      targetFile ??= candidates.length > 1
          ? candidates.reduce((a, b) => a.size >= b.size ? a : b)
          : candidates.first;

      return targetFile.streamLink ?? targetFile.link;
    } catch (e) {
      debugPrint('StremioTV: Premiumize resolve error: $e');
      return null;
    }
  }

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    if (request.infohash.isEmpty) return null;
    final apiKey = await CloudCredentials.apiKey(id);
    if (apiKey == null || apiKey.isEmpty) return null;

    request.log('⏳ Premiumize: preparing ${request.torrent.name}');

    List<PremiumizeFile> files;
    try {
      files = await PremiumizeService.directDownload(apiKey, request.magnet);
    } catch (e) {
      request.log('❌ Premiumize directdl failed: $e');
      return null;
    }

    if (files.isEmpty) {
      request.log('⚠️ Premiumize: no files for ${request.torrent.name}');
      return null;
    }

    final playableEntries = MagicTvPlayable.buildPremiumizeEntries(
      files,
      request.torrent.name,
      request,
    );
    if (playableEntries.isEmpty) {
      request.log(
        '⚠️ Premiumize: no playable files for ${request.torrent.name}',
      );
      return null;
    }

    final filteredEntries = playableEntries
        .where(
          (e) =>
              !request.seenKeys.contains('${request.infohash}|${e.file.path}'),
        )
        .toList();
    if (filteredEntries.isEmpty) {
      request.log(
        '⚠️ Premiumize: no unseen playable files for ${request.torrent.name}',
      );
      return null;
    }

    filteredEntries.shuffle(Random());
    final next = filteredEntries.removeAt(0);
    final streamUrl = next.file.streamLink ?? next.file.link;
    request.seenKeys.add('${request.infohash}|${next.file.path}');
    request.log('🎬 Premiumize: streaming ${next.title}');
    return MagicTvPrepared(
      streamUrl: streamUrl,
      title: next.title,
      hasMore: filteredEntries.isNotEmpty,
    );
  }

  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) async => null;
}
