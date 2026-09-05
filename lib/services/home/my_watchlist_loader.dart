import '../../models/stremio_addon.dart';
import '../storage_service.dart';

/// Reads the local watchlist without owning UI, refresh policy, or cached data.
class MyWatchlistLoader {
  MyWatchlistLoader._();

  static Future<({List<StremioMeta> movies, List<StremioMeta> series})> load() async {
    final items = await StorageService.getMyWatchlistItems();
    return (
      movies: [
        for (final item in items)
          if (item.type.toLowerCase() != 'series') item,
      ],
      series: [
        for (final item in items)
          if (item.type.toLowerCase() == 'series') item,
      ],
    );
  }
}
