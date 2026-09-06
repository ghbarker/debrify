import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/cloud/cloud_provider_id.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../video_player_screen.dart';
import '../../magic_tv_screen.dart'
    show MagicTvDispatch, MagicTvNextChannelQuirk;

import 'provider_watch_flow.dart';

class AlldebridWatchFlow {
  const AlldebridWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithAllDebrid(
    List<String> keywords,
    void Function(String message) log,
  ) => runQuickWatchSearch(
    host,
    provider: QuickWatchProvider.allDebrid,
    keywords: keywords,
    log: log,
    continueWith: (combinedList, apiKey) async {
    try {

      // Seed the queue with raw torrents — sequential add-and-probe, no cache
      // check (mirrors Real-Debrid). The prefetcher prepares the rest.
      host.queue
        ..clear()
        ..addAll(combinedList);
      host.lastQueueSize = host.queue.length;
      host.lastSearchAt = DateTime.now();
      host.seenRestrictedLinks.clear();
      host.seenLinkWithTorrentId.clear();

      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        if (host.watchCancelled) return null;
        debugPrint(
          'MagicTV/AD: requestMagicNext() queueSize=${host.queue.length}',
        );
        while (host.queue.isNotEmpty && !host.watchCancelled) {
          final item = host.queue.removeAt(0);
          if (item is Map && item['type'] == 'ad_locked') {
            final String link = item['allDebridLink'] as String? ?? '';
            if (link.isEmpty) continue;
            try {
              final videoUrl = await host.unlockLink(apiKey, link);
              if (host.watchCancelled) return null;
              if (videoUrl.isNotEmpty) {
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('MagicTV/AD: unlock failed: $e');
              continue;
            }
          }

          if (item is Torrent) {
            final prepared = await host.resolveAllDebridLinks(item);
            if (host.watchCancelled) return null;
            if (prepared == null || prepared.lockedLinks.isEmpty) {
              continue;
            }
            final links = List<String>.from(prepared.lockedLinks);
            final String headLink = links.removeAt(0);
            for (final link in links) {
              host.queue.add({
                'type': 'ad_locked',
                'allDebridLink': link,
                'magnetId': prepared.magnetId,
                'displayName': item.name,
              });
            }
            try {
              final videoUrl = await host.unlockLink(apiKey, headLink);
              if (host.watchCancelled) return null;
              if (videoUrl.isNotEmpty) {
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('MagicTV/AD: add/unlock failed: $e');
              continue;
            }
          }
        }
        debugPrint('MagicTV/AD: requestMagicNext() queue exhausted.');
        return null;
      }

      final first = await requestMagicNext();
      if (host.watchCancelled) return;
      if (first == null) {
        host.closeProgressDialog();
        if (host.mounted && !host.watchCancelled) {
          host.setState(() {
            host.status =
                'No playable AllDebrid streams found. Try different keywords.';
          });
          host.showSnack(
            'No playable AllDebrid streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      host.closeProgressDialog();
      if (!host.mounted) return;

      host.activeApiKey = apiKey;
      host.activeProvider = CloudProviderId.alldebrid.magicTvId;
      unawaited(host.startPrefetch());

      if (await host.handOffToExternalPlayer(first['url'] ?? '', firstTitle)) {
        return;
      }

      final launchedOnTv = await host.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: host.quickShowChannelName,
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
              title: firstTitle,
              startFromRandom: host.quickStartRandom,
              randomStartMaxPercent: host.quickRandomStartPercent,
              hideSeekbar: host.quickHideSeekbar,
              showChannelName: host.quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: host.quickShowVideoTitle,
              hideOptions: host.quickHideOptions,
              requestMagicNext: requestMagicNext,
              requestNextChannel:
                  host.channels.length > 1 &&
                      MagicTvDispatch.allowsNextChannel(
                        host.quickProvider,
                        MagicTvNextChannelQuirk.allKnown,
                      )
                  ? host.requestNextChannel
                  : null,
            ),
          ),
        );
        await host.stopPrefetch();
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
  });

}
