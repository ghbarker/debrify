import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/stremio_addon.dart';
import 'browsing_cache_preferences.dart';
import 'profiles/profile_runtime.dart';

/// A detail route owns speculation, never a user's pending Play request.
class MovieStreamPrefetchLease {
  MovieStreamPrefetchLease._(this._owner, this.contentId, this._generation);

  final MovieStreamPrefetch _owner;
  final String contentId;
  final int _generation;
  bool _closed = false;
  bool _chosen = false;
  _MovieDiscovery? _movie;

  bool get isActive => !_closed && _generation == _owner._generation;

  /// Stops unstarted addon requests and discards unclaimed cached results.
  /// Already-issued GETs and any Play that joined them finish normally.
  void close() {
    if (_closed) return;
    _closed = true;
    final movie = _movie;
    if (movie == null) return;
    movie.owners--;
    if (movie.owners == 0 &&
        !movie.claimed &&
        identical(_owner._movies[contentId], movie)) {
      _owner._movies.remove(contentId);
    }
  }

  /// Called synchronously by Play/Sources, before their async route/resume
  /// work can cover or dismiss the detail. Closing must preserve that choice.
  void claim() {
    _chosen = true;
    _movie?.claimed = true;
  }
}

class _MovieDiscovery {
  final entries = <String, _Discovery>{};
  int owners = 0;
  bool claimed = false;
}

class _Discovery {
  _Discovery(this.timeout);
  final Duration timeout;
  late final Future<List<StremioStream>> future;
  List<StremioStream>? streams;
  DateTime? expiresAt;
}

/// Memory-only discovery cache, admitted exclusively by opening movie details.
/// No resolver, player, debrid operation, watch-history write, or media GET is
/// reachable here. Only the supplied addon /stream discovery loader can run.
class MovieStreamPrefetch {
  MovieStreamPrefetch._() {
    ProfileRuntime.scope.addListener(invalidate);
    BrowsingCachePreferences.notifier.addListener(_preferencesChanged);
  }

  static final instance = MovieStreamPrefetch._();
  static const ttl = Duration(seconds: 60);
  static const directTtl = Duration(seconds: 20);
  static const maxMovies = 3;
  static const maxActiveMovies = 2;
  static const maxAddonsPerMovie = 16;
  static const maxCachedStreamsPerAddon = 500;

  final _movies = <String, _MovieDiscovery>{};
  final _running = <MovieStreamPrefetchLease>{};
  int _generation = 0;
  bool _enabled = BrowsingCachePreferences.current.prefetchMovieStreams;
  DateTime Function() _now = DateTime.now;

  /// Same identity as the catalog Play selection. Native IDs remain native;
  /// a TMDB number must never be fabricated into an IMDb ID.
  static String? contentIdFor(StremioMeta item) {
    if (item.type != 'movie') return null;
    final id = item.effectiveImdbId ?? item.id;
    return id.trim().isEmpty ? null : id;
  }

  /// These are discovery responses, not resolved media or durable bindings.
  /// Preserve the entire ordered response, including mixed transports, for a
  /// short window. Normal direct Play still performs its existing validation
  /// and startup failover; pinned direct resolution and manual retry bypass us.
  DateTime _expiresAt(List<StremioStream> streams, DateTime startedAt) {
    final hasUrls = streams.any(
      (stream) => stream.url != null || stream.externalUrl != null,
    );
    var expiry = hasUrls ? startedAt.add(directTtl) : _now().add(ttl);
    for (final stream in streams) {
      for (final raw in [stream.url, stream.externalUrl]) {
        if (raw == null) continue;
        final url = Uri.tryParse(raw);
        if (url == null) continue;
        // Recognize explicit absolute Unix expiry in URL query parameters.
        // Opaque signatures and other provider-specific formats are not
        // decoded or probed; those retain the conservative 20-second limit.
        Map<String, List<String>> parameters;
        try {
          parameters = url.queryParametersAll;
        } on FormatException {
          continue; // An opaque query must never make discovery itself fail.
        }
        for (final parameter in parameters.entries) {
          final key = parameter.key.toLowerCase();
          if (key != 'exp' && key != 'expires') continue;
          for (final value in parameter.value) {
            final epoch = int.tryParse(value);
            if (epoch == null || epoch < 0 || epoch > 99999999999999) continue;
            final explicit = DateTime.fromMillisecondsSinceEpoch(
              epoch < 1000000000000 ? epoch * 1000 : epoch,
              isUtc: true,
            ).subtract(const Duration(seconds: 2));
            if (explicit.isBefore(expiry)) expiry = explicit;
          }
        }
      }
    }
    return expiry;
  }

  void _preferencesChanged() {
    final enabled = BrowsingCachePreferences.current.prefetchMovieStreams;
    if (_enabled == enabled) return;
    _enabled = enabled;
    // This is a resource-policy change, not a profile/authorization revocation.
    // Explicit Play consumers already waiting on a GET may still use its
    // result; only speculative publication and unstarted work are discarded.
    _discardSpeculation();
  }

  /// Also called by Stremio's addon-change notification, including reorder,
  /// enable/disable, reconfiguration, and external profile-resource changes.
  void invalidate() {
    _generation++;
    _discardSpeculation();
  }

  void _discardSpeculation() {
    _movies.clear();
    for (final lease in _running) {
      lease.close();
    }
    // Keep occupied slots until their actual GETs finish, even after closing.
  }

  MovieStreamPrefetchLease open(
    String contentId,
    Future<void> Function(MovieStreamPrefetchLease lease) discover,
  ) {
    final lease = MovieStreamPrefetchLease._(this, contentId, _generation);
    if (_running.length >= maxActiveMovies) {
      lease.close();
      return lease;
    }
    _running.add(lease);
    unawaited(() async {
      try {
        await BrowsingCachePreferences.initialize();
        if (!lease.isActive ||
            !BrowsingCachePreferences.current.prefetchMovieStreams) {
          return;
        }
        // LRU admission is bounded even while users open many detail routes.
        final movie = _movies.remove(contentId) ?? _MovieDiscovery();
        lease._movie = movie;
        movie.owners++;
        if (lease._chosen) movie.claimed = true;
        _movies[contentId] = movie;
        while (_movies.length > maxMovies) {
          _movies.remove(_movies.keys.first);
        }
        await discover(lease);
      } catch (_) {
        // Speculation is best effort. A failed GET is never a negative cache.
      } finally {
        _running.remove(lease);
      }
    }());
    return lease;
  }

  /// Called only at the stream-discovery boundary. Ranking and conversion
  /// still run for every consumer using that consumer's current preferences.
  Future<List<StremioStream>> lookup({
    required String contentId,
    required String addonConfiguration,
    required Duration timeout,
    required Future<List<StremioStream>> Function() load,
    MovieStreamPrefetchLease? speculation,
    bool claimForPlay = true,
  }) async {
    await BrowsingCachePreferences.initialize();
    if (speculation != null && !speculation.isActive) return const [];
    final movie = _movies.remove(contentId);
    if (movie != null) _movies[contentId] = movie;
    if (!BrowsingCachePreferences.current.prefetchMovieStreams ||
        movie == null) {
      return speculation == null ? load() : const [];
    }
    // A consumer already inside discovery also owns its result independently
    // of the detail route (e.g. a sources page that has replaced the detail).
    if (speculation == null && claimForPlay) movie.claimed = true;
    final entries = movie.entries;
    final previous = entries[addonConfiguration];
    if (previous != null) {
      final expiresAt = previous.expiresAt;
      if (expiresAt != null && _now().isBefore(expiresAt)) {
        return List.of(previous.streams!);
      }
      if (expiresAt == null) {
        final generation = _generation;
        Future<List<StremioStream>> join() async {
          try {
            return await previous.future;
          } catch (_) {
            // A shorter speculative/recommendation budget must not turn a
            // longer explicit lookup into an early failure. Its retry is still
            // bounded by this caller's timeout below.
            if (speculation == null &&
                previous.timeout < timeout &&
                generation == _generation) {
              return load();
            }
            rethrow;
          }
        }

        final streams = await join().timeout(timeout);
        if (generation != _generation) {
          throw StateError('Movie discovery configuration changed');
        }
        return List.of(streams);
      }
      // User retry and pinned signed-URL resolution bypass this API entirely.
      entries.remove(addonConfiguration);
    }
    if (entries.length >= maxAddonsPerMovie) {
      return speculation == null ? load() : const [];
    }
    final generation = _generation;
    final startedAt = _now();
    final entry = _Discovery(timeout);
    entries[addonConfiguration] = entry;
    entry.future = () async {
      try {
        final streams = await load();
        if (generation != _generation) {
          throw StateError('Movie discovery configuration changed');
        }
        final expiresAt = _expiresAt(streams, startedAt);
        final reusable =
            streams.isNotEmpty &&
            streams.length <= maxCachedStreamsPerAddon &&
            _now().isBefore(expiresAt);
        if (reusable) {
          entry.streams = List.unmodifiable(streams);
          entry.expiresAt = expiresAt;
        } else if (identical(entries[addonConfiguration], entry)) {
          entries.remove(addonConfiguration);
        }
        return streams;
      } catch (_) {
        if (identical(entries[addonConfiguration], entry)) {
          entries.remove(addonConfiguration);
        }
        rethrow;
      }
    }();
    return List.of(await entry.future);
  }

  @visibleForTesting
  void resetForTesting({DateTime Function()? now}) {
    invalidate();
    _running.clear();
    _now = now ?? DateTime.now;
    _enabled = BrowsingCachePreferences.current.prefetchMovieStreams;
  }
}
