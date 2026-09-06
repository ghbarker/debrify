import 'package:debrify/services/storage/my_watchlist_store.dart';
import '../../models/stremio_addon.dart';

/// Reads the local watchlist without owning UI, refresh policy, or cached data.
class MyWatchlistLoader {
  MyWatchlistLoader._();

  static Future<({List<StremioMeta> movies, List<StremioMeta> series})> load() async {
    final items = await MyWatchlistStore.getMyWatchlistItems();
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
