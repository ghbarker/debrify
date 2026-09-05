import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/storage_service.dart';
import '../../../services/torrent_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../../utils/nsfw_filter.dart';
import '../../video_player_screen.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;

import 'provider_watch_flow.dart';
import 'windowed_watch_queue.dart';

class PremiumizeWatchFlow {
  const PremiumizeWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithPremiumize(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await StorageService.getPremiumizeIntegrationEnabled();
    if (!integrationEnabled) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'Enable Premiumize in Settings to use this provider.';
        host.isBusy = false;
      });
      host.showSnack(
        'Enable Premiumize in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status =
            'Add your Premiumize API key in Settings to use this provider.';
        host.isBusy = false;
      });
      host.showSnack(
        'Please add your Premiumize API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Premiumize: searching for cached torrents...');
    final Map<String, Torrent> dedup = {};
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
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);

        List<Torrent> torrentsToProcess = torrents;
        if (host.quickAvoidNsfw || host.viewerForcesNsfw) {
          torrentsToProcess = torrents.where((t) {
            return !NsfwFilter.shouldFilter(t.category, t.name);
          }).toList();
        }

        for (final torrent in torrentsToProcess) {
          final normalizedHash = host.normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          dedup.putIfAbsent(normalizedHash, () => torrent);
        }

        if (dedup.isNotEmpty && host.mounted) {
          host.setState(() => host.status = 'Checking Premiumize cache...');
        }
      }

      final combinedList = host.cacheWarmer.applyQualityFilterToTorrents(
        dedup.values.toList(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        host.closeProgressDialog();
        if (host.mounted) {
          host.setState(
            () => host.status = 'No results found. Try different keywords.',
          );
          host.showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      if (host.mounted) {
        host.setState(() => host.status = 'Checking Premiumize cache...');
      }

      final run = WindowedWatchRun(
        host: host,
        candidates: combinedList,
        fetchWindow: (startIndex) => host.fetchPremiumizeCacheWindow(
          candidates: combinedList,
          startIndex: startIndex,
          apiKey: apiKey,
        ),
        batchReady: (count) =>
            log('✅ Found $count cached Premiumize torrent(s)'),
        prepare: (candidate) => host.preparePremiumizeTorrent(
          candidate: candidate,
          apiKey: apiKey,
          log: log,
        ),
        provider: WindowedProvider.premiumize,
        log: log,
      );
      final populateQueue = run.populate;

      bool seeded;
      try {
        seeded = await populateQueue();
      } catch (e) {
        log('❌ Premiumize cache check failed: $e');
        host.closeProgressDialog();
        if (host.mounted) {
          host.setState(
            () => host.status = 'Premiumize cache check failed. Try again.',
          );
          host.showSnack(
            'Premiumize cache check failed: $e',
            color: Colors.red,
          );
        }
        return;
      }

      if (!seeded) {
        host.closeProgressDialog();
        if (host.mounted) {
          host.setState(
            () => host.status =
                'Premiumize has no cached results for these keywords.',
          );
          host.showSnack(
            'Premiumize has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      final requestPremiumizeNext = run.nextQuick;

      final first = await requestPremiumizeNext();
      if (host.watchCancelled) return;
      if (first == null) {
        host.closeProgressDialog();
        if (host.mounted && !host.watchCancelled) {
          host.setState(() {
            host.status =
                'No playable Premiumize streams found. Try different keywords.';
          });
          host.showSnack(
            'No playable Premiumize streams found. Try different keywords.',
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

      final launchedOnTv = await host.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPremiumizeNext,
        showChannelNameOverride: host.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (host.watchCancelled) return;
      if (launchedOnTv) return;

      if (!host.watchCancelled) {
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
              requestMagicNext: requestPremiumizeNext,
              requestNextChannel:
                  host.channels.length > 1 &&
                      MagicTvDispatch.allowsNextChannel(
                        host.quickProvider,
                        MagicTvNextChannelQuirk.exceptAllDebrid,
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
      if (host.mounted) host.setState(() => host.isBusy = false);
    }
  }

  Future<void> watchPremiumizeWithCachedTorrents(
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

    void log(String message) => debugPrint('DebrifyTV/PM: $message');

    final integrationEnabled =
        await StorageService.getPremiumizeIntegrationEnabled();
    if (!integrationEnabled) {
      host.showSnack(
        'Enable Premiumize in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No Premiumize API key');
      host.showSnack(
        'Please add your Premiumize API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    host.showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (host.mounted) {
      host.setState(() {
        host.status = 'Checking Premiumize cache...';
        host.isBusy = true;
      });
    }

    final run = WindowedWatchRun(
      host: host,
      candidates: candidatePool,
      fetchWindow: (startIndex) => host.fetchPremiumizeCacheWindow(
        candidates: candidatePool,
        startIndex: startIndex,
        apiKey: apiKey,
      ),
      batchReady: (count) =>
          log('✅ Cached Premiumize batch ready with $count item(s)'),
      prepare: (candidate) => host.preparePremiumizeTorrent(
        candidate: candidate,
        apiKey: apiKey,
        log: log,
      ),
      provider: WindowedProvider.premiumize,
      log: log,
    );
    final populateQueue = run.populate;

    bool seeded;
    try {
      seeded = await populateQueue();
    } catch (e) {
      host.closeProgressDialog();
      host.showSnack('Premiumize cache check failed: $e', color: Colors.orange);
      if (host.mounted) host.setState(() => host.isBusy = false);
      return;
    }

    if (!seeded) {
      host.closeProgressDialog();
      host.showSnack(
        'No cached torrents found on Premiumize. Please refresh the channel.',
        color: Colors.orange,
      );
      if (host.mounted) host.setState(() => host.isBusy = false);
      return;
    }

    final requestPremiumizeNext = run.nextCached;

    try {
      final first = await requestPremiumizeNext();
      if (first == null) {
        host.closeProgressDialog();
        if (!host.mounted) return;
        host.setState(() {
          host.status = 'No playable Premiumize streams found. Try refreshing.';
          host.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed(
          'No cached Premiumize streams available',
        );
        host.showSnack(
          'No cached Premiumize streams are playable. Try refreshing the channel.',
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

      final launchedOnTv = await host.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPremiumizeNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) return;

      await pushCachedWatchPlayer(
        host,
        first,
        requestPremiumizeNext,
        channelName: channelName,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
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
      host.setState(() => host.isBusy = false);
    }
  }
}
