import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../main_page_bridge.dart';
import '../premiumize_service.dart';
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
        fileName: file == null ? null : CloudPlaybackHelpers.fileName(file.path),
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
}
