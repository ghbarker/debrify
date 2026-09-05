import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/storage_service.dart';
import '../../../services/torrent_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../video_player_screen.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;

import 'provider_watch_flow.dart';

class TorboxWatchFlow {
  const TorboxWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithTorbox(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'Enable Torbox in Settings to use this provider.';
        host.isBusy = false;
      });
      host.showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status =
            'Add your Torbox API key in Settings to use this provider.';
        host.isBusy = false;
      });
      host.showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Torbox: searching for cached torrents...');
    final search = QuickWatchSearchAccumulator(
      host,
      providerLabel: 'Torbox',
      queueStatus: 'Checking Torbox cache...',
    );
    final engineStates = await host.cacheWarmer.tvEngineSearchStates();
    final maxResultsOverrides = host.cacheWarmer.quickPlayMaxResultsOverrides();

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: engineStates,
              maxResultsOverrides: maxResultsOverrides,
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        search.accept(result);
      }

      final combinedList = host.cacheWarmer.applyQualityFilterToTorrents(
        search.snapshot(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        host.closeProgressDialog();
        if (host.mounted) {
          host.setState(() {
            host.status = 'No results found. Try different keywords.';
          });
          host.showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      if (host.mounted) {
        host.setState(() {
          host.status = 'Checking Torbox cache...';
        });
      }

      final populateQueue = CachedWatchQueueCursor(
        host: host,
        candidates: combinedList,
        fetchWindow: (startIndex) => host.cacheWarmer.fetchTorboxCacheWindow(
          candidates: combinedList,
          startIndex: startIndex,
          apiKey: apiKey,
        ),
        batchReady: (count) => log('✅ Found $count cached Torbox torrent(s)'),
      ).populate;

      bool seeded;
      try {
        seeded = await populateQueue();
      } catch (e) {
        log('❌ Torbox cache check failed: $e');
        host.closeProgressDialog();
        if (host.mounted) {
          host.setState(() {
            host.status = 'Torbox cache check failed. Try again.';
          });
          host.showSnack(
            'Torbox cache check failed: ${host.formatTorboxError(e)}',
            color: Colors.red,
          );
        }
        return;
      }

      if (!seeded) {
        host.closeProgressDialog();
        if (host.mounted) {
          host.setState(() {
            host.status = 'Torbox has no cached results for these keywords.';
          });
          host.showSnack(
            'Torbox has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      Future<Map<String, String>?> requestTorboxNext() async {
        if (host.watchCancelled) {
          return null;
        }
        while (!host.watchCancelled) {
          if (host.queue.isEmpty) {
            bool replenished;
            try {
              replenished = await populateQueue();
            } catch (e) {
              log('❌ Torbox cache check failed: $e');
              host.closeProgressDialog();
              if (host.mounted && !host.watchCancelled) {
                host.setState(() {
                  host.status = 'Torbox cache check failed. Try again.';
                });
                host.showSnack(
                  'Torbox cache check failed: ${host.formatTorboxError(e)}',
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
          if (item is Map && item['type'] == host.torboxFileEntryType) {
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
            final result = await host.prepareTorboxTorrent(
              candidate: item,
              apiKey: apiKey,
              log: log,
            );
            if (host.watchCancelled) {
              return null;
            }
            if (result != null) {
              if (result.hasMore && !host.watchCancelled) {
                combinedList.add(item);
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
            host.status = 'No more cached Torbox streams available.';
          });
        }
        return null;
      }

      final first = await requestTorboxNext();
      if (host.watchCancelled) {
        return;
      }
      if (first == null) {
        host.closeProgressDialog();
        if (host.mounted && !host.watchCancelled) {
          host.setState(() {
            host.status =
                'No playable Torbox streams found. Try different keywords.';
          });
          host.showSnack(
            'No playable Torbox streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      host.closeProgressDialog();
      if (!host.mounted) return;

      if (await host.handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await host.launchTorboxOnAndroidTv(
        firstStream: first,
        requestNext: requestTorboxNext,
        showChannelNameOverride: host.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (host.watchCancelled) {
        return;
      }
      if (launchedOnTv) {
        return;
      }

      if (!host.watchCancelled) {
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();

        await host.navigator().push(
          FrozenLegacyPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: host.startRandom,
              randomStartMaxPercent: host.randomStartPercent,
              hideSeekbar: host.hideSeekbar,
              showChannelName: host.showChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: host.showVideoTitle,
              hideOptions: host.hideOptions,
              requestMagicNext: requestTorboxNext,
              requestNextChannel:
                  host.channels.length > 1 &&
                      MagicTvDispatch.allowsNextChannel(
                        host.quickProvider,
                        MagicTvNextChannelQuirk.rdTorboxPikPak,
                      )
                  ? host.requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (host.mounted && !host.watchCancelled) {
        host.setState(() {
          host.status = host.queue.isEmpty
              ? ''
              : 'Queue has ${host.queue.length} remaining';
        });
      }
    } finally {
      host.closeProgressDialog();
      if (host.mounted) {
        host.setState(() {
          host.isBusy = false;
        });
      }
    }
  }

  Future<void> watchTorboxWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      host.showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        host.channels.isNotEmpty
        ? host.androidTvChannelMetadata(
            activeChannelId: channelId ?? host.currentWatchingChannelId,
          )
        : null;

    void log(String message) {
      debugPrint('DebrifyTV: $message');
    }

    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      host.showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No Torbox API key');
      host.showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    host.showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (host.mounted) {
      host.setState(() {
        host.status = 'Checking Torbox cache...';
        host.isBusy = true;
      });
    }

    final populateQueue = CachedWatchQueueCursor(
      host: host,
      candidates: candidatePool,
      fetchWindow: (startIndex) => host.cacheWarmer.fetchTorboxCacheWindow(
        candidates: candidatePool,
        startIndex: startIndex,
        apiKey: apiKey,
      ),
      batchReady: (count) =>
          log('✅ Cached Torbox batch ready with $count item(s)'),
    ).populate;

    bool seeded;
    try {
      seeded = await populateQueue();
    } catch (e) {
      host.closeProgressDialog();
      host.showSnack(
        'Torbox cache check failed: ${host.formatTorboxError(e)}',
        color: Colors.orange,
      );
      if (host.mounted) {
        host.setState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    if (!seeded) {
      host.closeProgressDialog();
      host.showSnack(
        'Cached torrents are no longer available on Torbox. Please refresh the channel.',
        color: Colors.orange,
      );
      if (host.mounted) {
        host.setState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    Future<Map<String, String>?> requestTorboxNext() async {
      while (true) {
        if (host.queue.isEmpty) {
          bool replenished;
          try {
            replenished = await populateQueue();
          } catch (e) {
            host.closeProgressDialog();
            host.showSnack(
              'Torbox cache check failed: ${host.formatTorboxError(e)}',
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
        if (next is Map && next['type'] == host.torboxFileEntryType) {
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

        final prepared = await host.prepareTorboxTorrent(
          candidate: next,
          apiKey: apiKey,
          log: log,
        );
        if (prepared == null) {
          continue;
        }

        if (prepared.hasMore) {
          candidatePool.add(next);
        }
        return {'url': prepared.streamUrl, 'title': prepared.title};
      }
      return null;
    }

    try {
      final first = await requestTorboxNext();
      if (first == null) {
        host.closeProgressDialog();
        if (!host.mounted) return;
        host.setState(() {
          host.status = 'No playable Torbox streams found. Try refreshing.';
          host.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed(
          'No cached Torbox streams available',
        );
        host.showSnack(
          'No cached Torbox streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!host.mounted) return;
      host.closeProgressDialog();

      if (await host.handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await host.launchTorboxOnAndroidTv(
        firstStream: first,
        requestNext: requestTorboxNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) {
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      await host.navigator().push(
        FrozenLegacyPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: host.startRandom,
            randomStartMaxPercent: host.randomStartPercent,
            hideSeekbar: host.hideSeekbar,
            showChannelName: host.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: host.showVideoTitle,
            hideOptions: host.hideOptions,
            requestMagicNext: requestTorboxNext,
            requestNextChannel:
                host.channels.length > 1 &&
                    MagicTvDispatch.allowsNextChannel(
                      host.provider,
                      MagicTvNextChannelQuirk.exceptAllDebrid,
                    )
                ? host.requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: host.channels.length > 1
                ? host.requestChannelById
                : null,
          ),
        ),
      );
      if (host.mounted) {
        host.setState(() {
          host.status = host.queue.isEmpty
              ? ''
              : 'Queue has ${host.queue.length} remaining';
        });
      }
    } finally {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.isBusy = false;
      });
    }
  }
}
