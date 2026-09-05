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

  Future<Map<String, int>> readBoundCounts(List<StremioMeta> items) async {
    final counts = <String, int>{};
    final seen = <String>{};
    for (final item in items) {
      final imdb = imdbOf(item);
      if (imdb == null || !seen.add(imdb)) continue;
      final n = (await SeriesSourceService.getSources(imdb)).length;
      if (n > 0) counts[imdb] = n;
    }
    return counts;
  }
}
