import '../../models/torrent.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../series_source_service.dart';
import 'cloud_playback_result.dart';
import 'cloud_provider_id.dart';

/// Narrow playback port: add a magnet and resolve a playable result.
///
/// HTTP clients stay in the existing `*_service.dart` files. This port is the
/// switch that [TorrentPlaybackService._add], hashless bound replay, and the
/// download-picker lazy URL used to inline.
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

  /// Download-picker lazy URL. Launcher/TV lazy resolve is
  /// [CloudProviderRegistry.unlockPlaybackEntry]. The in-app player uses
  /// [CloudProviderRegistry.unlockPlayerScreenEntry] (same adapters, different
  /// wrap / Premiumize / empty-restrictedLink dialect).
  Future<String?> resolvePlaylistEntry(PlaylistEntry entry);

  /// HTTP unlock after the registry has chosen this adapter. Throws on missing
  /// metadata or empty URL. Do not wrap errors here — the player-screen path
  /// wraps HTTP failures as `$brand link failed`.
  Future<String> unlockPlaybackEntry(PlaylistEntry entry);
}
