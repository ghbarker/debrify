import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/cloud/cloud_provider_id.dart';
import '../../../services/pikpak_tv_service.dart';
import '../../../services/torrent_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../video_player_screen.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;

import 'provider_watch_flow.dart';

class PikpakWatchFlow {
  const PikpakWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithPikPak(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'Please login to PikPak in Settings first!';
        host.isBusy = false;
      });
      host.showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    log('🌐 PikPak: searching for torrents...');
    final search = QuickWatchSearchAccumulator(
      host,
      providerLabel: 'PikPak',
      queueStatus: 'Preparing PikPak stream...',
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
      host.queue
        ..clear()
        ..addAll(combinedList);
      host.lastQueueSize = host.queue.length;
      host.lastSearchAt = DateTime.now();

      if (host.mounted) {
        host.setState(() {
          host.status = 'Preparing PikPak stream...';
        });
      }

      Future<Map<String, String>?> requestPikPakNext() async {
        if (host.watchCancelled) {
          return null;
        }
        while (host.queue.isNotEmpty && !host.watchCancelled) {
          final item = host.queue.removeAt(0);
          if (host.watchCancelled) {
            break;
          }
          if (item is! Torrent) {
            continue;
          }

          log('Trying torrent: ${item.name}');
          final prepared = await host.preparePikPakTorrent(
            candidate: item,
            log: (msg) => debugPrint('DebrifyTV/PikPak: $msg'),
          );

          if (host.watchCancelled) {
            return null;
          }

          if (prepared == null) {
            log('Torrent not ready, trying next...');
            continue;
          }

          // Add back to queue if there are more files in this torrent
          if (prepared.hasMore) {
            host.queue.add(item);
            log(
              'Multi-file torrent: added back to queue (${host.queue.length} remaining)',
            );
          }

          if (host.mounted && !host.watchCancelled) {
            host.setState(() {
              host.status = host.queue.isEmpty
                  ? ''
                  : 'Queue has ${host.queue.length} remaining';
            });
          }

          return {
            'url': prepared.streamUrl,
            'title': prepared.title,
            'provider': CloudProviderId.pikpak.magicTvId,
            'pikpakFileId': '',
          };
        }
        if (host.mounted && !host.watchCancelled) {
          host.setState(() {
            host.status = 'No more PikPak streams available.';
          });
        }
        return null;
      }

      final first = await requestPikPakNext();
      if (host.watchCancelled) {
        return;
      }
      if (first == null) {
        host.closeProgressDialog();
        if (host.mounted && !host.watchCancelled) {
          host.setState(() {
            host.status =
                'No playable PikPak streams found. Try different keywords.';
          });
          MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
          host.showSnack(
            'No playable PikPak streams found. Try different keywords.',
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

      // Try Android TV native player first
      final launchedOnTv = await host.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
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
              startFromRandom: host.quickStartRandom,
              randomStartMaxPercent: host.quickRandomStartPercent,
              hideSeekbar: host.quickHideSeekbar,
              showChannelName: host.quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: host.quickShowVideoTitle,
              hideOptions: host.quickHideOptions,
              requestMagicNext: requestPikPakNext,
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

  Future<void> watchPikPakWithCachedTorrents(
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
      debugPrint('DebrifyTV/PikPak: $message');
    }

    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      host.showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    host.showCachedPlaybackDialog();

    host.pikpakCandidatePool = List<Torrent>.from(cachedTorrents);
    host.pikpakCandidatePool!.shuffle(Random());

    if (host.mounted) {
      host.setState(() {
        host.status = 'Preparing PikPak stream...';
        host.isBusy = true;
        host.queue
          ..clear()
          ..addAll(host.pikpakCandidatePool!);
      });
    }

    Future<Map<String, String>?> requestPikPakNext() async {
      if (host.watchCancelled) return null;

      while (host.queue.isNotEmpty && !host.watchCancelled) {
        final next = host.queue.removeAt(0);
        if (host.watchCancelled) break;

        if (next is! Torrent) {
          continue;
        }

        final prepared = await host.preparePikPakTorrent(
          candidate: next,
          log: log,
        );

        if (host.watchCancelled) return null;

        if (prepared == null) {
          continue;
        }

        if (prepared.hasMore) {
          host.queue.add(next);
        }

        return {
          'url': prepared.streamUrl,
          'title': prepared.title,
          'provider': CloudProviderId.pikpak.magicTvId,
        };
      }
      return null;
    }

    try {
      final first = await requestPikPakNext();
      if (first == null) {
        host.closeProgressDialog();
        if (!host.mounted) return;
        host.setState(() {
          host.status = 'No playable PikPak streams found. Try refreshing.';
          host.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
        host.showSnack(
          'No PikPak streams are playable. Try refreshing the channel.',
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

      // Try Android TV native player first
      final launchedOnTv = await host.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) {
        return;
      }

      // Fall back to Flutter video player (MediaKit)
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
            requestMagicNext: requestPikPakNext,
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
