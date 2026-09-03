import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../main_page_bridge.dart';
import '../premiumize_service.dart';
import '../series_source_service.dart';
import 'cloud_credentials.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_helpers.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';

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
}
