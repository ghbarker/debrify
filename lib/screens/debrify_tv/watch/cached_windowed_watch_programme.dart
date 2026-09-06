import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/storage/provider_credential_prefs.dart';
import '../../../services/storage_service.dart';
import '../../../services/main_page_bridge.dart';
import 'provider_watch_flow.dart';
import 'windowed_watch_queue.dart';

/// Whole cached TB/PM entry. Early credentials stay outside both cleanup scopes.
/// The unmounted return in finally deliberately retains origin error suppression.
Future<void> runCachedWindowedWatch(
  WatchFlowBindings host,
  List<Torrent> cachedTorrents, {
  required WindowedProvider provider,
  String? channelName,
  String? channelId,
  int? channelNumber,
}) async {
  final label = provider == WindowedProvider.torbox ? 'Torbox' : 'Premiumize';

  if (cachedTorrents.isEmpty) {
    MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
    host.showSnack(
      'Cached channel has no torrents yet. Please wait a moment.',
      color: Colors.orange,
    );
    return;
  }

  final List<Map<String, dynamic>>? channelDirectory = host.channels.isNotEmpty
      ? host.androidTvChannelMetadata(
          activeChannelId: channelId ?? host.currentWatchingChannelId,
        )
      : null;

  void log(String message) {
    debugPrint(
      provider == WindowedProvider.torbox
          ? 'DebrifyTV: $message'
          : 'DebrifyTV/PM: $message',
    );
  }

  final integrationEnabled = await (provider == WindowedProvider.torbox
      ? ProviderCredentialPrefs.getTorboxIntegrationEnabled
      : ProviderCredentialPrefs.getPremiumizeIntegrationEnabled)();
  if (!integrationEnabled) {
    host.showSnack(
      'Enable $label in Settings to use this provider.',
      color: Colors.orange,
    );
    return;
  }

  final apiKey = await (provider == WindowedProvider.torbox
      ? StorageService.getTorboxApiKey
      : StorageService.getPremiumizeApiKey)();
  if (apiKey == null || apiKey.isEmpty) {
    MainPageBridge.notifyAutoLaunchFailed('No $label API key');
    host.showSnack(
      'Please add your $label API key in Settings first!',
      color: Colors.orange,
    );
    return;
  }

  host.showCachedPlaybackDialog();

  final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
  candidatePool.shuffle(Random());

  if (host.mounted) {
    host.setState(() {
      host.status = 'Checking $label cache...';
      host.isBusy = true;
    });
  }

  final run = WindowedWatchRun(
    host: host,
    candidates: candidatePool,
    fetchWindow: (startIndex) =>
        (provider == WindowedProvider.torbox
        ? host.cacheWarmer.fetchTorboxCacheWindow
        : host.fetchPremiumizeCacheWindow)(
          candidates: candidatePool,
          startIndex: startIndex,
          apiKey: apiKey,
        ),
    batchReady: (count) =>
        log('✅ Cached $label batch ready with $count item(s)'),
    prepare: (candidate) =>
        (provider == WindowedProvider.torbox
        ? host.prepareTorboxTorrent
        : host.preparePremiumizeTorrent)(
          candidate: candidate,
          apiKey: apiKey,
          log: log,
        ),
    provider: provider,
    log: log,
  );
  final populateQueue = run.populate;

  bool seeded;
  try {
    seeded = await populateQueue();
  } catch (e) {
    host.closeProgressDialog();
    host.showSnack(
      '$label cache check failed: ${provider == WindowedProvider.torbox ? host.formatTorboxError(e) : e}',
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
      provider == WindowedProvider.torbox
          ? 'Cached torrents are no longer available on Torbox. Please refresh the channel.'
          : 'No cached torrents found on Premiumize. Please refresh the channel.',
      color: Colors.orange,
    );
    if (host.mounted) {
      host.setState(() {
        host.isBusy = false;
      });
    }
    return;
  }

  final requestNext = run.nextCached;

  try {
    final first = await requestNext();
    if (first == null) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'No playable $label streams found. Try refreshing.';
        host.isBusy = false;
      });
      MainPageBridge.notifyAutoLaunchFailed(
        'No cached $label streams available',
      );
      host.showSnack(
        'No cached $label streams are playable. Try refreshing the channel.',
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

    final launchedOnTv =
        await (provider == WindowedProvider.torbox
            ? host.launchTorboxOnAndroidTv
            : host.launchPikPakOnAndroidTv)(
          firstStream: first,
          requestNext: requestNext,
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
      requestNext,
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
