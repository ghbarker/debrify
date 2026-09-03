import '../../models/torbox_file.dart';
import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../main_page_bridge.dart';
import '../torbox_service.dart';
import 'cloud_credentials.dart';
import 'cloud_exceptions.dart';
import 'cloud_playback_helpers.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';

class TorboxCloudProvider implements CloudProviderPort {
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
    final torrentId = data is Map ? (data['torrent_id'] as num?)?.toInt() : null;
    if (torrentId == null) throw Exception('TorBox: no torrent id');
    final tt = await TorboxService.getTorrentById(apiKey, torrentId);
    final open = tt == null ? null : () => MainPageBridge.openTorboxFolder?.call(tt);
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
        fileName: file == null ? null : CloudPlaybackHelpers.fileName(file.name),
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
}
