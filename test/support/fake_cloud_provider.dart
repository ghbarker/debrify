import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_playback_result.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_port.dart';
import 'package:debrify/services/series_source_service.dart';

/// In-memory cloud provider for matrix tests. Never talks to a network.
class FakeCloudProvider implements CloudProviderPort {
  FakeCloudProvider({
    required this.id,
    this.configured = true,
    this.result,
    this.boundResult,
    this.error,
  });

  @override
  final CloudProviderId id;
  bool configured;
  CloudPlaybackResult? result;
  CloudPlaybackResult? boundResult;
  Object? error;

  int addCount = 0;
  int boundCount = 0;
  String? lastMagnet;
  SeriesSource? lastBoundSource;

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
}
