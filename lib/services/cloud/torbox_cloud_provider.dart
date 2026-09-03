import '../../models/torbox_file.dart';
import '../../models/torbox_web_download.dart';
import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../main_page_bridge.dart';
import '../series_source_service.dart';
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
}
