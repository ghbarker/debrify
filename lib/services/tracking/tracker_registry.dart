import 'package:flutter/foundation.dart';

import '../../models/tracking_source.dart';
import '../mdblist/mdblist_calendar_service.dart';
import '../mdblist/mdblist_continue_watching_service.dart';
import '../mdblist/mdblist_item_transformer.dart';
import '../mdblist/mdblist_list_source.dart';
import '../simkl/simkl_calendar_service.dart';
import '../simkl/simkl_continue_watching_service.dart';
import '../simkl/simkl_item_transformer.dart';
import '../simkl/simkl_list_source.dart';
import '../storage_service.dart';
import '../trakt/trakt_calendar_service.dart';
import '../trakt/trakt_continue_watching_service.dart';
import '../trakt/trakt_item_transformer.dart';
import '../trakt/trakt_list_source.dart';
import 'tracker_spec.dart';

export 'tracker_calendar.dart';
export 'tracker_continue_watching.dart';
export 'tracker_item_transformer.dart';
export 'tracker_list_source.dart';
export 'tracker_spec.dart';

/// Lookup table keyed by [TrackingSource].
///
/// [TrackingSourcePolicy] iterates this instead of switching on source.
/// Home CW rows and the calendar screen still call family singletons
/// directly (those files are other lanes).
class TrackerRegistry {
  TrackerRegistry(List<TrackerSpec> trackers)
    : _trackers = List<TrackerSpec>.of(trackers);

  factory TrackerRegistry.production() =>
      TrackerRegistry(productionTrackerSpecs());

  static TrackerRegistry instance = TrackerRegistry.production();

  final List<TrackerSpec> _trackers;

  List<TrackerSpec> get all => List<TrackerSpec>.unmodifiable(_trackers);

  /// Remote trackers in registration order (Trakt, Simkl, MDBList).
  List<TrackerSpec> get remotes => [
    for (final spec in _trackers)
      if (spec.source != TrackingSource.local) spec,
  ];

  void register(TrackerSpec spec) => _trackers.add(spec);

  @visibleForTesting
  static void debugReset() {
    instance = TrackerRegistry.production();
  }

  TrackerSpec? of(TrackingSource source) {
    for (final spec in _trackers) {
      if (spec.source == source) return spec;
    }
    return null;
  }

  /// Smart is not a tracker. Local is a spec but not dedicated.
  TrackerSpec? forProgress(WatchProgressSource source) {
    if (source == WatchProgressSource.smart) return null;
    for (final spec in _trackers) {
      if (spec.progressSource == source) return spec;
    }
    return null;
  }

  /// Today's `load()` dedicated mapping: only trakt / simkl / mdblist.
  TrackerSpec? dedicatedProgress(WatchProgressSource source) {
    final spec = forProgress(source);
    if (spec == null || !spec.isDedicatedProgress) return null;
    return spec;
  }
}

/// Production table. Order matches [TrackingSource.values]: local, trakt,
/// simkl, mdblist. Credential probes are the same StorageService methods
/// the policy switch called.
List<TrackerSpec> productionTrackerSpecs() => [
  TrackerSpec(
    source: TrackingSource.local,
    progressSource: WatchProgressSource.local,
    label: 'This device',
    hasCredential: () async => true,
    isDedicatedProgress: false,
  ),
  TrackerSpec(
    source: TrackingSource.trakt,
    progressSource: WatchProgressSource.trakt,
    label: 'Trakt',
    hasCredential: StorageService.hasTraktCredential,
    listSource: TraktListSource.instance,
    calendar: TraktCalendarService.instance,
    continueWatching: TraktContinueWatchingService.instance,
    transformer: const TraktTrackerItemTransformer(),
  ),
  TrackerSpec(
    source: TrackingSource.simkl,
    progressSource: WatchProgressSource.simkl,
    label: 'Simkl',
    hasCredential: StorageService.hasSimklCredential,
    listSource: SimklListSource.instance,
    calendar: SimklCalendarService.instance,
    continueWatching: SimklContinueWatchingService.instance,
    transformer: const SimklTrackerItemTransformer(),
  ),
  TrackerSpec(
    source: TrackingSource.mdblist,
    progressSource: WatchProgressSource.mdblist,
    label: 'MDBList',
    hasCredential: StorageService.hasMdblistCredential,
    listSource: MdblistListSource.instance,
    calendar: MdblistCalendarService.instance,
    continueWatching: MdblistContinueWatchingService.instance,
    transformer: const MdblistTrackerItemTransformer(),
  ),
];
