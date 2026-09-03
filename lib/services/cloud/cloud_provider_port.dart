import '../../models/torrent.dart';
import '../series_source_service.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';

/// Narrow playback port: add a magnet and resolve a playable result.
///
/// HTTP clients stay in the existing `*_service.dart` files. This port is the
/// switch that [TorrentPlaybackService._add] and hashless bound replay used
/// to inline.
abstract class CloudProviderPort {
  CloudProviderId get id;

  /// Playback-pipeline "has credentials" check (API key present / PikPak
  /// enabled). Magnet deep-links also require the integration-enabled flags;
  /// those stay on [CloudCredentials.isMagnetConfigured].
  Future<bool> isConfigured();

  Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent);

  /// Hashless bound-source replay. Direct URLs refresh every play.
  /// Returns null when this provider cannot resolve [source] (wrong kind,
  /// missing credentials, missing remote item).
  Future<CloudPlaybackResult?> resolveNativeBound(
    SeriesSource source, {
    required String? contentType,
  });
}
