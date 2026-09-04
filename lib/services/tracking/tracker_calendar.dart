import '../../models/trakt/trakt_calendar_entry.dart';

/// Shared calendar shape. Every family already exposes this [getRange].
abstract class TrackerCalendar {
  /// Inclusive local-date range `[start, end]`, grouped by local midnight.
  /// Empty buckets are omitted. Inverted ranges return `{}` without HTTP.
  Future<Map<DateTime, List<TraktCalendarEntry>>> getRange(
    DateTime start,
    DateTime end,
  );
}
