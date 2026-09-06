import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../video_player_screen.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;
import 'provider_watch_flow.dart';
import 'windowed_watch_queue.dart';

/// Shared TB/PM quick cache-to-player programme; cached flows remain distinct.
/// The caller returns this future directly in place of its original async body.
Future<void> runQuickWindowedWatch(
  WatchFlowBindings host, {
  required WindowedProvider provider,
  required List<Torrent> candidates,
  required String apiKey,
  required void Function(String message) log,
}) async {
  final label = provider == WindowedProvider.torbox ? 'Torbox' : 'Premiumize';
  try {
    if (host.mounted) {
      host.setState(() {
        host.status = 'Checking $label cache...';
      });
    }

    final run = WindowedWatchRun(
      host: host,
      candidates: candidates,
      fetchWindow: (startIndex) =>
          (provider == WindowedProvider.torbox
          ? host.cacheWarmer.fetchTorboxCacheWindow
          : host.fetchPremiumizeCacheWindow)(
            candidates: candidates,
            startIndex: startIndex,
            apiKey: apiKey,
          ),
      batchReady: (count) => log('✅ Found $count cached $label torrent(s)'),
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
      log('❌ $label cache check failed: $e');
      host.closeProgressDialog();
      if (host.mounted) {
        host.setState(() {
          host.status = '$label cache check failed. Try again.';
        });
        host.showSnack(
          '$label cache check failed: ${provider == WindowedProvider.torbox ? host.formatTorboxError(e) : e}',
          color: Colors.red,
        );
      }
      return;
    }

    if (!seeded) {
      host.closeProgressDialog();
      if (host.mounted) {
        host.setState(() {
          host.status = '$label has no cached results for these keywords.';
        });
        host.showSnack(
          '$label has no cached results for these keywords.',
          color: Colors.orange,
        );
      }
      return;
    }

    final requestNext = run.nextQuick;

    final first = await requestNext();
    if (host.watchCancelled) {
      return;
    }
    if (first == null) {
      host.closeProgressDialog();
      if (host.mounted && !host.watchCancelled) {
        host.setState(() {
          host.status =
              'No playable $label streams found. Try different keywords.';
        });
        host.showSnack(
          'No playable $label streams found. Try different keywords.',
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

    final launchedOnTv =
        await (provider == WindowedProvider.torbox
            ? host.launchTorboxOnAndroidTv
            : host.launchPikPakOnAndroidTv)(
          firstStream: first,
          requestNext: requestNext,
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
            requestMagicNext: requestNext,
            requestNextChannel:
                host.channels.length > 1 &&
                    MagicTvDispatch.allowsNextChannel(
                      host.quickProvider,
                      provider == WindowedProvider.torbox
                          ? MagicTvNextChannelQuirk.rdTorboxPikPak
                          : MagicTvNextChannelQuirk.exceptAllDebrid,
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
