import '../../models/rd_torrent.dart';
import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../utils/file_utils.dart';
import '../../utils/rd_folder_tree_builder.dart';
import '../../utils/series_parser.dart';
import '../debrid_service.dart';
import '../main_page_bridge.dart';
import '../series_source_service.dart';
import 'cloud_credentials.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_port.dart';

class RealDebridCloudProvider implements CloudProviderPort {
  const RealDebridCloudProvider();

  @override
  CloudProviderId get id => CloudProviderId.debrid;

  @override
  Future<bool> isConfigured() => CloudCredentials.isPlaybackConfigured(id);

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
}
