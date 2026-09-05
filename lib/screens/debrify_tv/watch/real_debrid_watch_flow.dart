import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/cloud/cloud_provider_id.dart';
import '../../../services/storage_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../../utils/nsfw_filter.dart';
import '../../../utils/rd_blocked_filter.dart';
import '../../video_player_screen.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;

import 'provider_watch_flow.dart';

class RealDebridWatchFlow {
  const RealDebridWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    required bool applyNsfwFilter,
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

    host.launchedPlayer = false;
    await host.stopPrefetch();
    host.prefetchStopRequested = false;
    host.originalMaxCap = null;
    host.seenRestrictedLinks.clear();
    host.seenLinkWithTorrentId.clear();

    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!host.mounted) return;
      MainPageBridge.notifyAutoLaunchFailed('No Real Debrid API key');
      host.showSnack(
        'Please add your Real Debrid API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    host.showCachedPlaybackDialog();

    // Apply NSFW filter to cached torrents if enabled
    List<Torrent> torrentsToUse = cachedTorrents;
    if (applyNsfwFilter) {
      final beforeCount = cachedTorrents.length;
      torrentsToUse = cachedTorrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          debugPrint(
            'DebrifyTV: Filtered cached NSFW torrent: ${torrent.name}',
          );
          return false;
        }
        return true;
      }).toList();
      if (beforeCount != torrentsToUse.length) {
        debugPrint(
          'DebrifyTV: NSFW filter on cached: $beforeCount → ${torrentsToUse.length} torrents',
        );
      }
    }

    // Filter out RD-blocked torrents
    if (host.rdSkipBlockedTorrents) {
      final beforeCount = torrentsToUse.length;
      torrentsToUse = torrentsToUse
          .where((t) => !isRdBlockedTorrent(t.name))
          .toList();
      if (beforeCount != torrentsToUse.length) {
        debugPrint(
          'DebrifyTV: RD-blocked filter on cached: $beforeCount → ${torrentsToUse.length} torrents',
        );
      }
    }

    host.queue
      ..clear()
      ..addAll(List<Torrent>.from(torrentsToUse)..shuffle(Random()));
    host.lastQueueSize = host.queue.length;
    host.lastSearchAt = DateTime.now();

    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint(
        'DebrifyTV: Cached requestMagicNext() queueSize=${host.queue.length}',
      );
      while (host.queue.isNotEmpty) {
        final item = host.queue.removeAt(0);
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('DebrifyTV: Cached path trying RD link: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await host.unrestrictLink(apiKey, link);
            if (!host.cacheWarmer.rdLinkPassesSizeRules(unrestrict)) continue;
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('DebrifyTV: Cached success (RD link) in ${elapsed}s');
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV: Cached RD link failed: $e');
            continue;
          }
        }

        if (item is Torrent) {
          debugPrint(
            'DebrifyTV: Cached trying torrent name="${item.name}" hash=${item.infohash}',
          );
          try {
            final started = DateTime.now();
            final batch = await host.resolveRdLockedLinks(item);
            final elapsed = DateTime.now().difference(started).inSeconds;
            if (batch == null || batch.lockedLinks.isEmpty) {
              continue;
            }

            final torrentId = batch.remoteId;
            final newLinks = List<String>.from(batch.lockedLinks);

            newLinks.shuffle(Random());
            // Walk THIS torrent's own links until one is playable. Bailing
            // after a single reject and re-queuing the torrent would pay
            // another add+info round trip just to reach a sibling file, so a
            // pack full of samples could burn one RD add per sample and play
            // nothing. Unrestrict calls are the cheap half — spend those.
            while (newLinks.isNotEmpty) {
              final selectedLink = newLinks.removeAt(0);
              host.seenRestrictedLinks.add(selectedLink);
              host.seenLinkWithTorrentId.add('$torrentId|$selectedLink');

              final unrestrict = await host.unrestrictLink(
                apiKey,
                selectedLink,
              );
              if (!host.cacheWarmer.rdLinkPassesSizeRules(unrestrict)) continue;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl == null || videoUrl.isEmpty) continue;

              debugPrint(
                'DebrifyTV: Cached success: unrestricted in ${elapsed}s',
              );
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;

              if (newLinks.isNotEmpty) {
                host.queue.add(item);
              }

              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV: Cached Debrid add failed: $e');
          }
        }
      }
      debugPrint('DebrifyTV: Cached queue exhausted.');
      return null;
    }

    host.setState(() {
      host.status = 'Finding a playable stream...';
      host.isBusy = true;
    });

    try {
      final first = await requestMagicNext();
      if (first == null) {
        host.closeProgressDialog();
        if (!host.mounted) return;
        host.setState(() {
          host.isBusy = false;
          host.status =
              'No cached torrents played successfully. Try refreshing the channel.';
        });
        MainPageBridge.notifyAutoLaunchFailed('No cached streams available');
        host.showSnack(
          'No cached torrents played successfully. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      if (!host.mounted) return;
      host.activeApiKey = apiKey;
      host.activeProvider = CloudProviderId.debrid.magicTvId;
      unawaited(host.startPrefetch());
      host.closeProgressDialog();

      if (await host.handOffToExternalPlayer(firstUrl, firstTitle)) {
        return;
      }

      // Try to launch on Android TV first (for cached flow)
      final launchedOnTv = await host.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );

      if (launchedOnTv) {
        // Successfully launched on Android TV
        debugPrint(
          'DebrifyTV: Cached flow - Real-Debrid playback started on Android TV',
        );
        // Prefetch will continue in background while TV player is active
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      // Fall back to Flutter video player
      await host.navigator().push(
        FrozenLegacyPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: host.startRandom,
            randomStartMaxPercent: host.randomStartPercent,
            hideSeekbar: host.hideSeekbar,
            showChannelName: host.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: host.showVideoTitle,
            hideOptions: host.hideOptions,
            requestMagicNext: requestMagicNext,
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
      await host.stopPrefetch();
    } finally {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.isBusy = false;
        host.status = '';
      });
      debugPrint('DebrifyTV: Cached watch flow finished.');
    }
  }
}
