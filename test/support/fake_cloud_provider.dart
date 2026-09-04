import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_playback_result.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_port.dart';
import 'package:debrify/services/cloud/stremio_torrent_resolve_args.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
import 'package:debrify/services/series_source_service.dart';

/// In-memory cloud provider for matrix tests. Never talks to a network.
class FakeCloudProvider implements CloudProviderPort {
  FakeCloudProvider({
    required this.id,
    this.configured = true,
    this.result,
    this.boundResult,
    this.playlistUrl,
    this.playbackUnlockUrl,
    this.stremioUrl,
    this.magicTvResult,
    this.lockedLinksResult,
    this.cachedHashes = const <String>{},
    this.cacheFlags = const <bool>[],
    this.zipPermalinkUrl,
    this.fileDownloadUrl,
    this.transferZipUrl,
    this.error,
  });

  @override
  final CloudProviderId id;

  @override
  bool supports(CloudPortFeature feature) =>
      CloudPortFeature.forProvider(id).contains(feature);
  bool configured;
  CloudPlaybackResult? result;
  CloudPlaybackResult? boundResult;
  String? playlistUrl;
  String? playbackUnlockUrl;
  String? stremioUrl;
  MagicTvPrepared? magicTvResult;
  MagicTvLockedBatch? lockedLinksResult;
  Set<String> cachedHashes;
  List<bool> cacheFlags;
  String? zipPermalinkUrl;
  String? fileDownloadUrl;
  Object? error;

  int addCount = 0;
  int boundCount = 0;
  int playlistCount = 0;
  int unlockCount = 0;
  int stremioCount = 0;
  int magicTvCount = 0;
  int lockedLinksCount = 0;
  int cachedHashesCount = 0;
  int checkCacheCount = 0;
  int zipPermalinkCount = 0;
  int fileDownloadLinkCount = 0;
  int? lastFileDownloadTorrentId;
  int? lastFileDownloadFileId;
  String? lastMagnet;
  SeriesSource? lastBoundSource;
  PlaylistEntry? lastPlaylistEntry;
  Torrent? lastStremioTorrent;
  MagicTvPrepareRequest? lastMagicTvRequest;
  List<String>? lastCachedHashQuery;
  List<String>? lastCacheQuery;

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent) async {
    addCount++;
    lastMagnet = magnet;
    if (error != null) throw error!;
    return result ??
        CloudPlaybackResult(
          title: torrent.displayTitle,
          playUrl: 'https://fake.example/${id.playbackId}',
          downloadUrls: ['https://fake.example/${id.playbackId}'],
          fileName: torrent.name,
        );
  }

  @override
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  }) async {
    boundCount++;
    lastBoundSource = source;
    if (error != null) throw error!;
    return boundResult;
  }

  @override
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry) async {
    playlistCount++;
    lastPlaylistEntry = entry;
    if (error != null) throw error!;
    return playlistUrl;
  }

  @override
  Future<String> unlockPlaybackEntry(PlaylistEntry entry) async {
    unlockCount++;
    if (error != null) throw error!;
    if (playbackUnlockUrl != null) return playbackUnlockUrl!;
    throw Exception('No URL metadata available for this entry');
  }

  @override
  Future<String?> resolveStremioTorrent(StremioTorrentResolveArgs args) async {
    stremioCount++;
    lastStremioTorrent = args.torrent;
    if (error != null) throw error!;
    return stremioUrl;
  }

  @override
  Future<MagicTvPrepared?> prepareMagicTv(MagicTvPrepareRequest request) async {
    magicTvCount++;
    lastMagicTvRequest = request;
    if (error != null) throw error!;
    return magicTvResult;
  }

  @override
  Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(
    MagicTvPrepareRequest request,
  ) async {
    lockedLinksCount++;
    lastMagicTvRequest = request;
    if (error != null) throw error!;
    return lockedLinksResult;
  }

  @override
  Future<Set<String>> checkCachedHashes(List<String> infoHashes) async {
    cachedHashesCount++;
    lastCachedHashQuery = infoHashes;
    if (error != null) throw error!;
    return cachedHashes;
  }

  @override
  Future<List<bool>> checkCache(List<String> items) async {
    checkCacheCount++;
    lastCacheQuery = items;
    if (error != null) throw error!;
    return cacheFlags;
  }

  @override
  Future<String> zipPermalink(int torrentId) async {
    zipPermalinkCount++;
    if (error != null) throw error!;
    if (zipPermalinkUrl != null) return zipPermalinkUrl!;
    throw CloudUnsupported(id, CloudPortFeature.zipPermalink);
  }

  @override
  Future<String> fileDownloadLink(int torrentId, int fileId) async {
    fileDownloadLinkCount++;
    lastFileDownloadTorrentId = torrentId;
    lastFileDownloadFileId = fileId;
    if (error != null) throw error!;
    if (fileDownloadUrl != null) return fileDownloadUrl!;
    throw CloudUnsupported(id, CloudPortFeature.fileDownloadLink);
  }

  int createCloudTransferCount = 0;
  String? lastTransferMagnet;

  @override
  Future<void> createCloudTransfer(String magnet) async {
    createCloudTransferCount++;
    lastTransferMagnet = magnet;
    if (error != null) throw error!;
    if (!supports(CloudPortFeature.cloudTransfer)) {
      throw CloudUnsupported(id, CloudPortFeature.cloudTransfer);
    }
  }

  String? transferZipUrl;
  int createTransferZipCount = 0;

  @override
  Future<String> createTransferZip(String magnet) async {
    createTransferZipCount++;
    lastTransferMagnet = magnet;
    if (error != null) throw error!;
    if (transferZipUrl != null) return transferZipUrl!;
    throw CloudUnsupported(id, CloudPortFeature.transferZip);
  }

  int queueUncachedCount = 0;

  @override
  Future<void> queueUncachedMagnet(String magnet) async {
    queueUncachedCount++;
    lastTransferMagnet = magnet;
    if (error != null) throw error!;
    if (!supports(CloudPortFeature.queueUncached)) {
      throw CloudUnsupported(id, CloudPortFeature.queueUncached);
    }
  }
}
