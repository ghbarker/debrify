import '../../models/torrent.dart';
import 'cloud_provider_registry.dart';

/// Playback-pipeline cache-first reorder.
///
/// Playback ids (`torbox` / `premiumize`). Hits move to the front; misses stay.
/// Catch-all (including missing key). Empty key still reaches the adapter.
/// Not [StremioTvCacheFilter] (drop uncached) and not Magic TV windows.
class PlaybackCacheFirst {
  PlaybackCacheFirst._();

  static Future<List<Torrent>> reorder(
    String provider,
    List<Torrent> candidates,
  ) async {
    final hashes = candidates
        .map((torrent) => torrent.infohash.toLowerCase())
        .where((hash) => hash.isNotEmpty)
        .toList();
    final cached = <String>{};
    try {
      if (provider == 'torbox') {
        cached.addAll(
          await CloudProviderRegistry.instance.checkCachedHashes(hashes),
        );
      } else if (provider == 'premiumize') {
        final flags = await CloudProviderRegistry.instance.checkCache(hashes);
        for (var i = 0; i < hashes.length && i < flags.length; i++) {
          if (flags[i]) cached.add(hashes[i]);
        }
      }
    } catch (_) {}
    if (cached.isEmpty) return candidates;
    final hit = candidates
        .where((torrent) => cached.contains(torrent.infohash.toLowerCase()))
        .toList();
    final miss = candidates
        .where((torrent) => !cached.contains(torrent.infohash.toLowerCase()))
        .toList();
    return [...hit, ...miss];
  }
}
