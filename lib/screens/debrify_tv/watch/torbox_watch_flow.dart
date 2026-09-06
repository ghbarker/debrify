import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/storage_service.dart';
import '../../../services/main_page_bridge.dart';

import 'provider_watch_flow.dart';
import 'quick_windowed_watch_programme.dart';
import 'windowed_watch_queue.dart';

class TorboxWatchFlow {
  const TorboxWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithTorbox(
    List<String> keywords,
    void Function(String message) log,
  ) => runQuickWatchSearch(
    host,
    provider: QuickWatchProvider.torbox,
    keywords: keywords,
    log: log,
    continueWith: (combinedList, apiKey) => runQuickWindowedWatch(
      host,
      provider: WindowedProvider.torbox,
      candidates: combinedList,
      apiKey: apiKey,
      log: log,
    ),
  );

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
        await ProviderCredentialPrefs.getTorboxIntegrationEnabled();
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

    final run = WindowedWatchRun(
      host: host,
      candidates: candidatePool,
      fetchWindow: (startIndex) => host.cacheWarmer.fetchTorboxCacheWindow(
        candidates: candidatePool,
        startIndex: startIndex,
        apiKey: apiKey,
      ),
      batchReady: (count) =>
          log('✅ Cached Torbox batch ready with $count item(s)'),
      prepare: (candidate) => host.prepareTorboxTorrent(
        candidate: candidate,
        apiKey: apiKey,
        log: log,
      ),
      provider: WindowedProvider.torbox,
      log: log,
    );
    final populateQueue = run.populate;

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

    final requestTorboxNext = run.nextCached;

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
      await pushCachedWatchPlayer(
        host,
        first,
        requestTorboxNext,
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
      host.setState(() {
        host.isBusy = false;
      });
    }
  }
}
