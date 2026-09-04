import '../../models/tracking_source.dart';
import 'tracker_calendar.dart';
import 'tracker_continue_watching.dart';
import 'tracker_item_transformer.dart';
import 'tracker_list_source.dart';

/// One tracker (or the local device) as registered in [TrackerRegistry].
class TrackerSpec {
  const TrackerSpec({
    required this.source,
    required this.progressSource,
    required this.label,
    required this.hasCredential,
    this.isDedicatedProgress = true,
    this.listSource,
    this.calendar,
    this.continueWatching,
    this.transformer,
  });

  final TrackingSource source;
  final WatchProgressSource progressSource;
  final String label;

  /// Credential probe used by [TrackingSourcePolicy.load] for dedicated
  /// progress fallback. Local is always `true`.
  final Future<bool> Function() hasCredential;

  /// When false (local), [TrackingSourcePolicy.load] never credential-falls
  /// back. Today's switch used `_ => null` for both Smart and local.
  final bool isDedicatedProgress;

  final TrackerListSource? listSource;
  final TrackerCalendar? calendar;
  final TrackerContinueWatching? continueWatching;
  final TrackerItemTransformer? transformer;
}
