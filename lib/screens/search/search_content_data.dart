import 'dart:async';

import '../../models/stremio_addon.dart';
import '../../services/series_source_service.dart';

/// Bound-source data shared by screen owners; UI commits remain with the host.
class SearchContentData {
  final Map<String, int> boundCounts = {};

  String? imdbOf(StremioMeta item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool isBound(StremioMeta item) {
    final id = imdbOf(item);
    return id != null && (boundCounts[id] ?? 0) > 0;
  }

  int boundCountFor(StremioMeta item) {
    final id = imdbOf(item);
    return id == null ? 0 : (boundCounts[id] ?? 0);
  }

  FutureOr<Map<String, int>> readBoundCounts(List<StremioMeta> items) {
    final ids = _eligibleIds(items).iterator;
    // The origin host reached its commit without awaiting when every item was
    // ineligible. Preserve that synchronous path, including an empty snapshot.
    if (!ids.moveNext()) return <String, int>{};
    return _readEligibleCounts(ids);
  }

  Iterable<String> _eligibleIds(List<StremioMeta> items) sync* {
    final seen = <String>{};
    for (final item in items) {
      final imdb = imdbOf(item);
      if (imdb == null || !seen.add(imdb)) continue;
      yield imdb;
    }
  }

  Future<Map<String, int>> _readEligibleCounts(Iterator<String> ids) async {
    final counts = <String, int>{};
    do {
      final imdb = ids.current;
      final n = (await SeriesSourceService.getSources(imdb)).length;
      if (n > 0) counts[imdb] = n;
    } while (ids.moveNext());
    return counts;
  }
}
