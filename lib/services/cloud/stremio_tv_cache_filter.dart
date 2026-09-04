import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import 'cloud_credentials.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_registry.dart';

/// Stremio TV *explicit* `torbox` / `premiumize` cache filter.
///
/// No key means skip the filter (keep uncached torrents). Empty torrent hashes
/// skip HTTP. Direct streams stay. Auto-play uses [StremioTvTorboxCache.load],
/// not this. Not TPS cache-first (reorder + catch-all).
class StremioTvCacheFilter {
  StremioTvCacheFilter._();

  /// Returns null if [isCancelled] fires immediately before HTTP (overlay
  /// play abort). Silent paths omit [isCancelled] and never abort.
  static Future<List<Torrent>?> apply({
    required String provider,
    required List<Torrent> sources,
    bool Function()? isCancelled,
    VoidCallback? onStart,
    void Function(int cachedCount, int torrentCount)? onChecked,
  }) async {
    if (provider == 'torbox') {
      return _filterTorbox(
        sources: sources,
        isCancelled: isCancelled,
        onStart: onStart,
        onChecked: onChecked,
      );
    }
    if (provider == 'premiumize') {
      return _filterPremiumize(
        sources: sources,
        isCancelled: isCancelled,
        onStart: onStart,
        onChecked: onChecked,
      );
    }
    return sources;
  }

  static List<String> _torrentHashes(List<Torrent> sources) => sources
      .where((torrent) => torrent.streamType == StreamType.torrent)
      .map((torrent) => torrent.infohash.trim().toLowerCase())
      .where((hash) => hash.isNotEmpty)
      .toList();

  static List<Torrent> _keepDirectsAndCached(
    List<Torrent> sources,
    Set<String> cached,
  ) =>
      sources
          .where(
            (torrent) =>
                torrent.streamType != StreamType.torrent ||
                cached.contains(torrent.infohash.trim().toLowerCase()),
          )
          .toList();

  static Future<List<Torrent>?> _filterTorbox({
    required List<Torrent> sources,
    bool Function()? isCancelled,
    VoidCallback? onStart,
    void Function(int cachedCount, int torrentCount)? onChecked,
  }) async {
    if (!await CloudCredentials.isPlaybackConfigured(CloudProviderId.torbox)) {
      return sources;
    }
    final hashes = _torrentHashes(sources);
    if (hashes.isEmpty) return sources;
    if (isCancelled?.call() ?? false) return null;

    onStart?.call();
    final cached = await CloudProviderRegistry.instance.checkCachedHashes(
      hashes,
    );
    onChecked?.call(cached.length, hashes.length);
    return _keepDirectsAndCached(sources, cached);
  }

  static Future<List<Torrent>?> _filterPremiumize({
    required List<Torrent> sources,
    bool Function()? isCancelled,
    VoidCallback? onStart,
    void Function(int cachedCount, int torrentCount)? onChecked,
  }) async {
    if (!await CloudCredentials.isPlaybackConfigured(
      CloudProviderId.premiumize,
    )) {
      return sources;
    }
    final hashes = _torrentHashes(sources);
    if (hashes.isEmpty) return sources;
    if (isCancelled?.call() ?? false) return null;

    onStart?.call();
    final flags = await CloudProviderRegistry.instance.checkCache(hashes);
    final cached = <String>{};
    for (var i = 0; i < hashes.length; i++) {
      if (i < flags.length && flags[i]) {
        cached.add(hashes[i]);
      }
    }
    onChecked?.call(cached.length, hashes.length);
    return _keepDirectsAndCached(sources, cached);
  }
}
