import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/torrent.dart';
import '../alldebrid_service.dart';
import '../cloud/cloud_provider_id.dart';
import '../cloud/cloud_provider_registry.dart';
import '../cloud/magic_tv_prepare_args.dart';
import '../engine/settings_manager.dart';

abstract interface class WatchAllDebridPrepared {
  String get magnetId;
  String get name;
  List<String> get lockedLinks;
}

class QueuePrefetcher {
  QueuePrefetcher({
    required List<dynamic> queue,
    required Set<String> seenRestrictedLinks,
    required Set<String> seenLinkWithTorrentId,
    required SettingsManager settingsManager,
    required bool Function() isMounted,
    required MagicTvPrepareRequest Function(Torrent) buildLockedRequest,
  }) : _queue = queue,
       _seenRestrictedLinks = seenRestrictedLinks,
       _seenLinkWithTorrentId = seenLinkWithTorrentId,
       _settingsManager = settingsManager,
       _isMounted = isMounted,
       _buildLockedRequest = buildLockedRequest;

  final List<dynamic> _queue;
  final Set<String> _seenRestrictedLinks;
  final Set<String> _seenLinkWithTorrentId;
  final SettingsManager _settingsManager;
  final bool Function() _isMounted;
  final MagicTvPrepareRequest Function(Torrent) _buildLockedRequest;

  // Prefetch state
  static const int _minPrepared = 6; // maintain at least 6 prepared items
  static const int _lookaheadWindow = 10; // window near head to keep prepared
  bool _prefetchRunning = false;
  bool stopRequested = false;
  Future<void>? _prefetchTask;
  // Invalidates an async start when playback exits while the preference is
  // still being read. Without this, a stopped player could start a late
  // prefetch loop after stopPrefetch returned.
  int _prefetchEpoch = 0;
  String? activeApiKey;
  // Which provider the active prefetch run resolves through. RD and AllDebrid
  // are the two cache-check-less providers that use the background prefetcher;
  // this tells _prefetchOneAtIndex / requestMagicNext which add+resolve path to
  // use against activeApiKey.
  String activeProvider = CloudProviderId.debrid.magicTvId;
  final Set<String> _inflightInfohashes = {};

  Future<void> startPrefetch() async {
    if (_prefetchRunning || activeApiKey == null || activeApiKey!.isEmpty) {
      return;
    }

    final startEpoch = _prefetchEpoch;
    final enabled = await _settingsManager.getGlobalBackgroundPrefetchEnabled();

    // Re-check mutable state after the preference read. Multiple playback
    // paths can request a start at nearly the same time, and playback may
    // have stopped while this method was awaiting SharedPreferences.
    if (!_isMounted() ||
        startEpoch != _prefetchEpoch ||
        _prefetchRunning ||
        activeApiKey == null ||
        activeApiKey!.isEmpty) {
      return;
    }
    if (!enabled) {
      debugPrint('MagicTV: Background torrent prefetch is disabled.');
      return;
    }

    _prefetchRunning = true;
    stopRequested = false;
    debugPrint('MagicTV: Prefetch started.');
    _prefetchTask = _runPrefetchLoop();
  }

  Future<void> stopPrefetch() async {
    _prefetchEpoch++;
    if (!_prefetchRunning) return;
    stopRequested = true;
    try {
      await _prefetchTask;
    } catch (_) {}
    _prefetchRunning = false;
    _prefetchTask = null;
    _inflightInfohashes.clear();
    debugPrint('MagicTV: Prefetch stopped.');
  }

  Future<void> _runPrefetchLoop() async {
    while (_isMounted() && !stopRequested) {
      try {
        final prepared = _countPreparedInLookahead();
        if (prepared >= _minPrepared) {
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        // Find first unprepared torrent within lookahead window and prefetch it
        final idx = _findUnpreparedTorrentIndexInLookahead();
        if (idx == -1) {
          // nothing to prefetch near head; small idle
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        await _prefetchOneAtIndex(idx);
        // brief yield (faster when under target prepared)
        await Future.delayed(Duration(milliseconds: prepared <= 2 ? 75 : 150));
      } catch (e) {
        debugPrint('MagicTV: Prefetch loop error: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  int _countPreparedInLookahead() {
    final end = _queue.length < _lookaheadWindow
        ? _queue.length
        : _lookaheadWindow;
    int count = 0;
    for (int i = 0; i < end; i++) {
      final item = _queue[i];
      if (item is Map &&
          (item['type'] == 'rd_restricted' || item['type'] == 'ad_locked')) {
        count++;
      }
    }
    return count;
  }

  int _findUnpreparedTorrentIndexInLookahead() {
    final end = _queue.length < _lookaheadWindow
        ? _queue.length
        : _lookaheadWindow;
    for (int i = 0; i < end; i++) {
      final item = _queue[i];
      if (item is Torrent && !_inflightInfohashes.contains(item.infohash)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _prefetchOneAtIndex(int idx) async {
    if (activeApiKey == null || activeApiKey!.isEmpty) return;
    if (idx < 0 || idx >= _queue.length) return;
    final item = _queue[idx];
    if (item is! Torrent) return;
    if ((CloudProviderId.fromMagicTvId(activeProvider) ??
            CloudProviderId.debrid) ==
        CloudProviderId.alldebrid) {
      await _prefetchOneAllDebrid(idx, item);
      return;
    }
    final infohash = item.infohash;
    _inflightInfohashes.add(infohash);
    debugPrint('MagicTV: Prefetching torrent at idx=$idx name="${item.name}"');
    try {
      final batch = await CloudProviderRegistry.instance
          .prepareMagicTvLockedLinks(
            provider: CloudProviderId.debrid.magicTvId,
            request: _buildLockedRequest(item),
          );
      if (batch == null || batch.lockedLinks.isEmpty) {
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
          _queue.add(item);
        }
        debugPrint(
          'MagicTV: Prefetch: no links; moved torrent to tail idx=$idx',
        );
        return;
      }

      final headLinkCandidates = List<String>.from(batch.lockedLinks);
      headLinkCandidates.shuffle(Random());
      final headLink = headLinkCandidates.removeAt(0);
      _seenRestrictedLinks.add(headLink);
      _seenLinkWithTorrentId.add('${batch.remoteId}|$headLink');

      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue[idx] = {
          'type': 'rd_restricted',
          'restrictedLink': headLink,
          'torrentId': batch.remoteId,
          'displayName': item.name,
        };
      }

      if (headLinkCandidates.isNotEmpty) {
        _queue.add(item);
      }
    } catch (e) {
      // On failure, move to tail for retry later
      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue.removeAt(idx);
        _queue.add(item);
      }
      debugPrint('MagicTV: Prefetch failed for $infohash: $e (moved to tail)');
    } finally {
      _inflightInfohashes.remove(infohash);
    }
  }

  /// Adds [candidate] to AllDebrid (trusting the upload `ready` flag — no
  /// polling) and returns its fresh (unseen) locked video-file links, marking
  /// them seen. Returns null when the torrent is not cached/ready (the magnet
  /// is deleted in that case) or has no usable video files. Each returned link
  /// is still locked and must be unlocked via [AllDebridService.unlockLink]
  /// before playback — the lazy model mirrors Real-Debrid's restricted links.
  Future<WatchAllDebridPrepared?> resolveAllDebridLinks(
    Torrent candidate,
  ) async {
    final batch = await CloudProviderRegistry.instance
        .prepareMagicTvLockedLinks(
          provider: CloudProviderId.alldebrid.magicTvId,
          request: _buildLockedRequest(candidate),
        );
    if (batch == null || batch.lockedLinks.isEmpty) return null;
    for (final link in batch.lockedLinks) {
      _seenRestrictedLinks.add(link);
    }
    return _AllDebridPrepared(
      magnetId: batch.remoteId,
      name: batch.name,
      lockedLinks: batch.lockedLinks,
    );
  }

  /// AllDebrid analog of the Real-Debrid prefetch path. Converts the [item]
  /// queue slot into a prepared `ad_locked` entry (a still-locked link), and
  /// since AllDebrid returns every file at once, enqueues the remaining video
  /// files immediately rather than re-adding the torrent.
  Future<void> _prefetchOneAllDebrid(int idx, Torrent item) async {
    final infohash = item.infohash;
    _inflightInfohashes.add(infohash);
    debugPrint(
      'MagicTV: Prefetching AllDebrid torrent at idx=$idx name="${item.name}"',
    );
    try {
      final prepared = await resolveAllDebridLinks(item);
      if (prepared == null || prepared.lockedLinks.isEmpty) {
        // Not ready / no usable video; move to tail to retry later.
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
          _queue.add(item);
        }
        debugPrint(
          'MagicTV: AllDebrid prefetch: not ready/no links; moved to tail idx=$idx',
        );
        return;
      }

      final links = List<String>.from(prepared.lockedLinks);
      final headLink = links.removeAt(0);
      Map<String, dynamic> lockedEntry(String link) => {
        'type': 'ad_locked',
        'allDebridLink': link,
        'magnetId': prepared.magnetId,
        'displayName': item.name,
      };

      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue[idx] = lockedEntry(headLink);
      } else {
        // Slot shifted out from under us; don't lose the resolved head link.
        _queue.add(lockedEntry(headLink));
      }
      for (final link in links) {
        _queue.add(lockedEntry(link));
      }
    } catch (e) {
      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue.removeAt(idx);
        _queue.add(item);
      }
      debugPrint(
        'MagicTV: AllDebrid prefetch failed for $infohash: $e (moved to tail)',
      );
    } finally {
      _inflightInfohashes.remove(infohash);
    }
  }
}

/// Result of adding an AllDebrid magnet for Debrify TV: the resolved (still
/// locked) video-file links plus identifiers for the created magnet.
class _AllDebridPrepared implements WatchAllDebridPrepared {
  @override
  final String magnetId;
  @override
  final String name;
  @override
  final List<String> lockedLinks;
  _AllDebridPrepared({
    required this.magnetId,
    required this.name,
    required this.lockedLinks,
  });
}
