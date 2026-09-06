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

class PremiumizeWatchFlow {
  const PremiumizeWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithPremiumize(
    List<String> keywords,
    void Function(String message) log,
  ) => runQuickWatchSearch(
    host,
    provider: QuickWatchProvider.premiumize,
    keywords: keywords,
    log: log,
    continueWith: (combinedList, apiKey) => runQuickWindowedWatch(
      host,
      provider: WindowedProvider.premiumize,
      candidates: combinedList,
      apiKey: apiKey,
      log: log,
    ),
  );

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
        await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled();
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
