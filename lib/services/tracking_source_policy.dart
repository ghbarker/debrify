import '../models/tracking_source.dart';
import 'storage_service.dart';
import 'tracking/tracker_registry.dart';

export '../models/tracking_source.dart';

/// One immutable snapshot of the user's Tracking preferences.
///
/// Keeping all three decisions here prevents individual playback and Home
/// surfaces from growing subtly different interpretations of the settings.
class TrackingSourcePolicy {
  const TrackingSourcePolicy({
    required this.scrobbleTargets,
    required this.progressSource,
    required this.homeTickSources,
  });

  final Set<TrackingSource> scrobbleTargets;
  final WatchProgressSource progressSource;
  final Set<TrackingSource> homeTickSources;

  static Future<TrackingSourcePolicy> load() async {
    final scrobbleTargets = await StorageService.getTrackingScrobbleTargets();
    var progressSource = await StorageService.getWatchProgressSource();
    final dedicated = TrackerRegistry.instance.dedicatedProgress(
      progressSource,
    );
    if (dedicated != null) {
      if (!await dedicated.hasCredential()) {
        await StorageService.fallbackDisconnectedProgressSource(
          dedicated.source,
        );
        progressSource = WatchProgressSource.smart;
      }
    }
    return TrackingSourcePolicy(
      scrobbleTargets: scrobbleTargets,
      progressSource: progressSource,
      homeTickSources: await StorageService.getHomeTickSources(),
    );
  }

  bool scrobbles(TrackingSource source) =>
      source == TrackingSource.local || scrobbleTargets.contains(source);

  /// Smart preserves the legacy merged/recency behavior. A dedicated source
  /// admits only itself; local means data written by this Debrify profile.
  bool progressFrom(TrackingSource source) {
    if (progressSource == WatchProgressSource.smart) return true;
    final spec = TrackerRegistry.instance.forProgress(progressSource);
    return spec != null && spec.source == source;
  }

  bool homeTicksFrom(TrackingSource source) => homeTickSources.contains(source);

  /// Episode-guide supplier mask: ticks AND partial bars both follow
  /// [progressSource] (Varun, 2026-08-27 — supersedes the earlier
  /// ticks-always-merged decision). Also used by the native TV payload so
  /// late metadata cannot reintroduce a foreign entry.
  double? guideProgressFrom(TrackingSource source, double? percent) {
    if (percent == null || !percent.isFinite) return null;
    if (!progressFrom(source)) return null;
    return percent.clamp(0.0, 100.0).toDouble();
  }

  bool get forcesLocalCompletion => progressSource == WatchProgressSource.local;

  bool get isSmart => progressSource == WatchProgressSource.smart;
}
