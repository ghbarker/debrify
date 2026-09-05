import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../services/cloud/cloud_provider_id.dart';
import '../../../services/storage_service.dart';
import '../../../services/torrent_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_surfaces.dart';
import '../../../utils/nsfw_filter.dart';
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
  ) async {
    final integrationEnabled =
        await ProviderCredentialPrefs.getAllDebridIntegrationEnabled();
    if (!integrationEnabled) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status = 'Enable AllDebrid in Settings to use this provider.';
        host.isBusy = false;
      });
      host.showSnack(
        'Enable AllDebrid in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      host.closeProgressDialog();
      if (!host.mounted) return;
      host.setState(() {
        host.status =
            'Add your AllDebrid API key in Settings to use this provider.';
        host.isBusy = false;
      });
      host.showSnack(
        'Please add your AllDebrid API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 AllDebrid: searching for torrents...');
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
        if (host.watchCancelled) return;
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
          host.setState(() => host.status = 'Finding a playable stream...');
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
  }

  Future<void> watchAllDebridWithCachedTorrents(
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

    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!host.mounted) return;
      MainPageBridge.notifyAutoLaunchFailed('No AllDebrid API key');
      host.showSnack(
        'Please add your AllDebrid API key in Settings first!',
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
        'DebrifyTV/AD: requestMagicNext() queueSize=${host.queue.length}',
      );
      while (host.queue.isNotEmpty) {
        final item = host.queue.removeAt(0);
        if (item is Map && item['type'] == 'ad_locked') {
          final String link = item['allDebridLink'] as String? ?? '';
          if (link.isEmpty) continue;
          try {
            final videoUrl = await host.unlockLink(apiKey, link);
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
            debugPrint('DebrifyTV/AD: Cached unlock failed: $e');
            continue;
          }
        }

        if (item is Torrent) {
          debugPrint(
            'DebrifyTV/AD: Cached trying torrent name="${item.name}" hash=${item.infohash}',
          );
          final prepared = await host.resolveAllDebridLinks(item);
          if (prepared == null || prepared.lockedLinks.isEmpty) {
            continue;
          }
          final links = List<String>.from(prepared.lockedLinks);
          final String headLink = links.removeAt(0);
          // AllDebrid returns every file at once: enqueue the remaining video
          // files (still locked) so siblings aren't lost if the head fails.
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
            if (videoUrl.isNotEmpty) {
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV/AD: Cached add/unlock failed: $e');
            continue;
          }
        }
      }
      debugPrint('DebrifyTV/AD: Cached queue exhausted.');
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
      host.activeProvider = CloudProviderId.alldebrid.magicTvId;
      unawaited(host.startPrefetch());
      host.closeProgressDialog();

      if (await host.handOffToExternalPlayer(firstUrl, firstTitle)) {
        return;
      }

      // Try to launch on Android TV first (reuses the generic direct-URL
      // launcher; AllDebrid streams are ready URLs just like Real-Debrid's).
      final launchedOnTv = await host.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );

      if (launchedOnTv) {
        debugPrint(
          'DebrifyTV: Cached flow - AllDebrid playback started on Android TV',
        );
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
                      MagicTvNextChannelQuirk.allKnown,
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
      debugPrint('DebrifyTV: AllDebrid cached watch flow finished.');
    }
  }
}
