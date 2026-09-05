import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../models/debrify_tv/cache_results.dart';
import '../../../models/debrify_tv/prepared_torrents.dart';
import 'provider_watch_flow.dart';

enum WindowedProvider { torbox, premiumize }

/// TB/PM window cursor and two distinct next programmes, using the live host queue.
/// No in-flight lock/epoch; overlapping calls retain original completion behavior.
class WindowedWatchRun {
  WindowedWatchRun({
    required this.host,
    required this.candidates,
    required this.fetchWindow,
    required this.batchReady,
    required this.prepare,
    required this.provider,
    required this.log,
  });

  final WatchFlowBindings host;
  final List<Torrent> candidates;
  final Future<TorboxCacheWindowResult> Function(int startIndex) fetchWindow;
  final void Function(int count) batchReady;
  final Future<WindowedPreparedTorrent?> Function(Torrent candidate) prepare;
  final WindowedProvider provider;
  final void Function(String message) log;
  int _cursor = 0;

  String get _label =>
      provider == WindowedProvider.torbox ? 'Torbox' : 'Premiumize';
  String _formatError(Object error) => provider == WindowedProvider.torbox
      ? host.formatTorboxError(error)
      : '$error';

  Future<bool> populate() async {
    while (true) {
      if (_cursor >= candidates.length) {
        return false;
      }
      final TorboxCacheWindowResult window = await fetchWindow(_cursor);
      _cursor = window.nextCursor;
      if (window.cachedTorrents.isEmpty) {
        if (window.exhausted) {
          return false;
        }
        continue;
      }
      host.queue
        ..clear()
        ..addAll(window.cachedTorrents);
      host.lastQueueSize = host.queue.length;
      host.lastSearchAt = DateTime.now();
      if (host.mounted) {
        host.setState(() {
          host.status = host.queue.isEmpty
              ? ''
              : 'Queue has ${host.queue.length} remaining';
        });
      }
      batchReady(host.queue.length);
      return true;
    }
  }

  Future<Map<String, String>?> nextQuick() async {
    if (host.watchCancelled) {
      return null;
    }
    while (!host.watchCancelled) {
      if (host.queue.isEmpty) {
        bool replenished;
        try {
          replenished = await populate();
        } catch (e) {
          log('❌ $_label cache check failed: $e');
          host.closeProgressDialog();
          if (host.mounted && !host.watchCancelled) {
            host.setState(() {
              host.status = '$_label cache check failed. Try again.';
            });
            host.showSnack(
              '$_label cache check failed: ${_formatError(e)}',
              color: Colors.red,
            );
          }
          return null;
        }
        if (!replenished) {
          break;
        }
      }
      if (host.queue.isEmpty) {
        break;
      }
      final item = host.queue.removeAt(0);
      if (host.watchCancelled) {
        break;
      }
      if (provider == WindowedProvider.torbox &&
          item is Map &&
          item['type'] == host.torboxFileEntryType) {
        final resolved = await host.resolveTorboxQueuedFile(
          entry: item as Map<String, dynamic>,
          log: log,
        );
        if (host.watchCancelled) {
          return null;
        }
        if (resolved != null) {
          if (host.mounted && !host.watchCancelled) {
            host.setState(() {
              host.status = host.queue.isEmpty
                  ? ''
                  : 'Queue has ${host.queue.length} remaining';
            });
          }
          if (host.watchCancelled) {
            return null;
          }
          return resolved;
        }
        continue;
      }

      if (item is Torrent) {
        final result = await prepare(item);
        if (host.watchCancelled) {
          return null;
        }
        if (result != null) {
          if (result.hasMore && !host.watchCancelled) {
            candidates.add(item);
          }
          if (host.mounted && !host.watchCancelled) {
            host.setState(() {
              host.status = host.queue.isEmpty
                  ? ''
                  : 'Queue has ${host.queue.length} remaining';
            });
          }
          if (host.watchCancelled) {
            return null;
          }
          return {'url': result.streamUrl, 'title': result.title};
        }
      }
    }
    if (host.mounted && !host.watchCancelled) {
      host.setState(() {
        host.status = provider == WindowedProvider.torbox
            ? 'No more cached Torbox streams available.'
            : 'No more cached Premiumize streams.';
      });
    }
    return null;
  }

  Future<Map<String, String>?> nextCached() async {
    while (true) {
      if (host.queue.isEmpty) {
        bool replenished;
        try {
          replenished = await populate();
        } catch (e) {
          host.closeProgressDialog();
          host.showSnack(
            '$_label cache check failed: ${_formatError(e)}',
            color: Colors.orange,
          );
          if (host.mounted) {
            host.setState(() {
              host.isBusy = false;
            });
          }
          return null;
        }
        if (!replenished) {
          break;
        }
      }
      if (host.queue.isEmpty) {
        break;
      }

      final next = host.queue.removeAt(0);
      if (provider == WindowedProvider.torbox &&
          next is Map &&
          next['type'] == host.torboxFileEntryType) {
        final resolved = await host.resolveTorboxQueuedFile(
          entry: Map<String, dynamic>.from(next as Map),
          log: log,
        );
        if (resolved != null) {
          return resolved;
        }
        continue;
      }

      if (next is! Torrent) {
        continue;
      }

      final prepared = await prepare(next);
      if (prepared == null) {
        continue;
      }

      if (prepared.hasMore) {
        candidates.add(next);
      }
      return {'url': prepared.streamUrl, 'title': prepared.title};
    }
    return null;
  }
}
