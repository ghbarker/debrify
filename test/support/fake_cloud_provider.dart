import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
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
}
