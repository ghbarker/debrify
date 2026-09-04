import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import 'cloud_credentials.dart';
import 'cloud_provider_id.dart';
import 'cloud_provider_registry.dart';

/// Stremio TV *auto* TorBox cache membership.
///
/// Missing key, cancel, and empty hashes become `{}` so auto-play skips
/// TorBox. Explicit `torbox` provider filtering is different: no key means
/// skip the filter (keep uncached torrents). Chunk HTTP does not throw;
/// the try/catch is for unexpected adapter errors (e.g. missing key).
class StremioTvTorboxCache {
  StremioTvTorboxCache._();

  static Future<Set<String>> load(
    Iterable<Torrent> torrents, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return const <String>{};

    if (!await CloudCredentials.isPlaybackConfigured(CloudProviderId.torbox)) {
      return const <String>{};
    }
    if (isCancelled?.call() ?? false) return const <String>{};

    final infoHashes = torrents
        .map((torrent) => torrent.infohash.trim().toLowerCase())
        .where((hash) => hash.isNotEmpty)
        .toSet()
        .toList();
    if (infoHashes.isEmpty) return const <String>{};

    try {
      final cached = await CloudProviderRegistry.instance.checkCachedHashes(
        infoHashes,
      );
      if (isCancelled?.call() ?? false) return const <String>{};

      debugPrint(
        'StremioTV: Auto TorBox cache check found ${cached.length} '
        'of ${infoHashes.length} candidate(s)',
      );
      return cached;
    } catch (e) {
      debugPrint('StremioTV: TorBox cache check failed: $e');
      return const <String>{};
    }
  }
}
