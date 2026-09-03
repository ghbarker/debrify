import 'package:flutter/foundation.dart';

import '../../models/quick_play_rules.dart';

/// Series-auto-pin negative cache: skip repeating an expensive whole-series
/// pack search for a season after a miss.
///
/// In-memory + TTL. A settings/provider change is part of the key so it takes
/// effect immediately. Extracted from [TorrentPlaybackService] so tests can
/// lock the TTL / "do not remember" / cap behaviour.
class PackNegativeCache {
  PackNegativeCache({DateTime Function()? now, this.cap = 200})
    : _now = now ?? DateTime.now;

  static PackNegativeCache instance = PackNegativeCache();

  final DateTime Function() _now;
  final int cap;
  final Map<String, DateTime> _until = {};

  @visibleForTesting
  Map<String, DateTime> get debugEntries => Map.unmodifiable(_until);

  @visibleForTesting
  static void debugReset() {
    instance = PackNegativeCache();
  }

  String key(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) => '$imdbId:$season:$provider:${rules.hashCode}';

  bool recentlyNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) {
    // "Do not remember" must take effect immediately, including for entries
    // recorded before the user changed this setting.
    if (rules.failedPackCacheHours <= 0) return false;
    final k = key(imdbId, season, provider, rules);
    final until = _until[k];
    if (until == null) return false;
    if (!_now().isBefore(until)) {
      _until.remove(k);
      return false;
    }
    return true;
  }

  void markNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
    Duration ttl,
  ) {
    if (ttl <= Duration.zero) return;
    final now = _now();
    _until.removeWhere((_, until) => !now.isBefore(until));
    if (_until.length >= cap) {
      final oldest = _until.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _until.remove(oldest);
    }
    _until[key(imdbId, season, provider, rules)] = now.add(ttl);
  }
}
