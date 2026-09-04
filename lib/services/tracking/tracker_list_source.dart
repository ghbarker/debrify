import '../../models/stremio_addon.dart';

/// Shared See-All / Discover list page: items plus the empty-vs-failed signal.
///
/// [complete] is true for Trakt/Simkl (they have no partial-page flag) and
/// mirrors MDBList's `loadListItems.complete`.
class TrackerListPage {
  const TrackerListPage({
    required this.items,
    required this.failed,
    this.complete = true,
  });

  final List<StremioMeta> items;
  final bool failed;
  final bool complete;
}

/// Shared list-source shape. Each family keeps its own choice type; [loadPage]
/// is a thin adapter over the existing load method (HTTP unchanged).
abstract class TrackerListSource {
  Future<TrackerListPage> loadPage(
    Object choice, {
    List<StremioMeta> cwItems = const [],
  });
}
