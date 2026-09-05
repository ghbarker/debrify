import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/debrify_tv/channel.dart';
import '../../models/debrify_tv/cache_results.dart';
import '../../models/torrent.dart';
import '../../services/android_tv_player_bridge.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/debrid_service.dart';
import '../../services/alldebrid_service.dart';
import '../../services/cloud/cloud_provider_id.dart';
import '../../services/cloud/magic_tv_prepare_args.dart';
import '../../services/pikpak_tv_service.dart';
import '../../utils/rd_blocked_filter.dart';
import '../magic_tv_screen.dart' show MagicTvDispatch;
import 'watch/provider_watch_flow.dart';

/// Channel routing and native handoff; live host bindings retain origin timing.
/// Positive Android launch/onFinished still requires device-runtime proof.
class ChannelSwitchFlow {
  ChannelSwitchFlow(this.host);

  final WatchFlowBindings host;

  Future<bool> launchTorboxOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!host.isAndroidTv) {
      return false;
    }
    final initialUrl = firstStream['url'] ?? '';
    if (initialUrl.isEmpty) {
      return false;
    }
    // Torbox native player already receives a prepared stream URL, so skip sending magnet
    // bundles—the binder payload stays small and launch succeeds.
    const List<Map<String, dynamic>> magnets = [];

    final title = (firstStream['title'] ?? '').trim();

    try {
      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchTorboxPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        magnets: magnets,
        requestNext: requestNext,
        requestChannelSwitch: host.channels.length > 1
            ? requestNextChannel
            : null,
        requestChannelById: host.channels.length > 1
            ? requestChannelById
            : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!host.mounted) {
            return;
          }
          host.setState(() {
            host.status = host.queue.isEmpty
                ? ''
                : 'Queue has ${host.queue.length} remaining';
          });
        },
        startFromRandom: host.startRandom,
        randomStartMaxPercent: host.randomStartPercent,
        hideSeekbar: host.hideSeekbar,
        hideOptions: host.hideOptions,
        showVideoTitle: host.showVideoTitle,
        showChannelName: showChannelNameOverride ?? host.showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? host.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (host.mounted) {
          host.setState(() {
            host.status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed: $e');
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }

  Future<Map<String, dynamic>?> requestNextChannel() async {
    debugPrint('DebrifyTV: _requestNextChannel() called');

    if (host.channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available');
      return null;
    }

    int currentIndex = -1;
    if (host.currentWatchingChannelId != null) {
      currentIndex = host.channels.indexWhere(
        (c) => c.id == host.currentWatchingChannelId,
      );
    }

    final int nextIndex = (currentIndex + 1) % host.channels.length;
    final DebrifyTvChannel targetChannel = host.channels[nextIndex];

    debugPrint(
      'DebrifyTV: Switching from channel ${currentIndex + 1} to ${nextIndex + 1} (${targetChannel.name})',
    );

    return switchToChannel(
      targetChannel,
      fallbackIndex: nextIndex,
      reason: 'next',
    );
  }

  Future<Map<String, dynamic>?> requestChannelById(String channelId) async {
    debugPrint('DebrifyTV: _requestChannelById($channelId) called');

    if (host.channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available for direct selection');
      return null;
    }

    DebrifyTvChannel? targetChannel;
    int discoveredIndex = -1;
    for (var i = 0; i < host.channels.length; i++) {
      final channel = host.channels[i];
      if (channel.id == channelId) {
        targetChannel = channel;
        discoveredIndex = i;
        break;
      }
    }

    if (targetChannel == null) {
      debugPrint('DebrifyTV: Channel id $channelId not found');
      return null;
    }

    if (host.currentWatchingChannelId == targetChannel.id) {
      debugPrint(
        'DebrifyTV: Selected channel is already active; refreshing playback',
      );
    } else {
      debugPrint(
        'DebrifyTV: Switching directly to channel ${targetChannel.name}',
      );
    }

    return switchToChannel(
      targetChannel,
      fallbackIndex: discoveredIndex >= 0 ? discoveredIndex : null,
      reason: 'direct',
    );
  }

  Future<Map<String, dynamic>?> switchToChannel(
    DebrifyTvChannel targetChannel, {
    int? fallbackIndex,
    String reason = 'direct',
  }) async {
    debugPrint(
      'DebrifyTV: _switchToChannel(${targetChannel.name}) reason=$reason',
    );

    final int computedIndex =
        fallbackIndex ??
        host.channels.indexWhere((channel) => channel.id == targetChannel.id);
    final int targetChannelNumber = targetChannel.channelNumber > 0
        ? targetChannel.channelNumber
        : (computedIndex >= 0 ? computedIndex + 1 : 0);

    final cacheEntry = await host.cacheWarmer.ensureCacheEntry(
      targetChannel.id,
    );
    if (cacheEntry == null) {
      debugPrint(
        'DebrifyTV: Channel "${targetChannel.name}" has no cache entry',
      );
      return null;
    }
    if (!cacheEntry.isReady) {
      debugPrint(
        'DebrifyTV: Channel "${targetChannel.name}" cache not ready. Error: ${cacheEntry.errorMessage}',
      );
      return null;
    }
    if (cacheEntry.torrents.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no torrents');
      return null;
    }

    debugPrint('DebrifyTV: Stopping old channel prefetcher...');
    await host.stopPrefetch();
    debugPrint('DebrifyTV: Prefetcher stopped. Waiting for RD cooldown...');
    await Future.delayed(const Duration(seconds: 5));
    debugPrint('DebrifyTV: Cooldown complete. Proceeding with channel switch.');

    final previousChannelId = host.currentWatchingChannelId;
    if (previousChannelId != null) {
      host.cacheWarmer.channelCache.remove(previousChannelId);
      debugPrint(
        'DebrifyTV: Evicted cache entry for previous channel $previousChannelId',
      );
    }

    host.seenRestrictedLinks.clear();
    host.seenLinkWithTorrentId.clear();
    // New channel, new filter verdict — let it warn again if this one has
    // nothing at the requested quality/size.
    host.qualityFallbackNotified = false;
    host.cacheWarmer.resetSizeFilterSession();
    debugPrint('DebrifyTV: Cleared prefetch state');

    final keywords = await host.getChannelKeywords(targetChannel.id);
    if (keywords.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no keywords');
      if (MagicTvDispatch.usesLockedLinks(host.provider)) {
        unawaited(host.startPrefetch());
      }
      return null;
    }

    final normalizedKeywords = host.cacheWarmer.normalizedKeywords(keywords);
    final playbackSelection = host.cacheWarmer.selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );

    if (playbackSelection.isEmpty) {
      debugPrint('DebrifyTV: No torrents matched in selected channel');
      if (MagicTvDispatch.usesLockedLinks(host.provider)) {
        unawaited(host.startPrefetch());
      }
      return null;
    }

    final List<Torrent> allTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    if (allTorrents.isEmpty) {
      debugPrint('DebrifyTV: No playable torrents resolved for channel');
      if (MagicTvDispatch.usesLockedLinks(host.provider)) {
        unawaited(host.startPrefetch());
      }
      return null;
    }

    List<Torrent> filteredTorrents = allTorrents;
    if (MagicTvDispatch.usesCachedHashes(host.provider)) {
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('DebrifyTV: ❌ No Torbox API key configured');
        return null;
      }

      final List<Torrent> torboxCandidates = List<Torrent>.from(
        filteredTorrents,
      );
      torboxCandidates.shuffle(Random());

      int candidateCursor = 0;
      List<Torrent> cachedCandidates = <Torrent>[];
      try {
        while (candidateCursor < torboxCandidates.length &&
            cachedCandidates.isEmpty) {
          final TorboxCacheWindowResult window = await host.cacheWarmer
              .fetchTorboxCacheWindow(
                candidates: torboxCandidates,
                startIndex: candidateCursor,
                apiKey: apiKey,
              );
          candidateCursor = window.nextCursor;
          if (window.cachedTorrents.isNotEmpty) {
            cachedCandidates = window.cachedTorrents;
            break;
          }
          if (window.exhausted) {
            break;
          }
        }
      } catch (e) {
        debugPrint(
          'DebrifyTV: Torbox cache check failed during channel switch: $e',
        );
        return null;
      }

      if (cachedCandidates.isEmpty) {
        debugPrint(
          'DebrifyTV: Torbox channel has no cached torrents available',
        );
        return null;
      }

      filteredTorrents = cachedCandidates;
    }

    try {
      if (MagicTvDispatch.watchId(host.provider) == CloudProviderId.debrid) {
        debugPrint('DebrifyTV: Selected channel uses Real-Debrid provider');
        final apiKey = await StorageService.getApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Real-Debrid API key configured');
          return null;
        }

        if (host.rdSkipBlockedTorrents) {
          filteredTorrents = filteredTorrents
              .where((t) => !isRdBlockedTorrent(t.name))
              .toList();
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          MagicTvLockedBatch? batch;
          try {
            batch = await host.resolveRdLockedLinks(
              candidate,
              seenKeys: <String>{},
            );
          } catch (error) {
            debugPrint(
              'DebrifyTV: Real-Debrid rejected candidate ${candidate.infohash}: $error',
            );
            continue;
          }

          final rdLinks = batch?.lockedLinks ?? const <String>[];

          if (rdLinks.isEmpty) {
            debugPrint(
              'DebrifyTV: Real-Debrid returned no usable links for candidate ${candidate.infohash}',
            );
            continue;
          }

          final torrentId = batch?.remoteId ?? '';
          List<String> newLinks = rdLinks
              .where((link) => !host.seenRestrictedLinks.contains(link))
              .toList();
          if (newLinks.isEmpty) {
            newLinks = List<String>.from(rdLinks);
          }
          newLinks.shuffle(Random());
          // Exhaust THIS candidate's links before moving on. Advancing to the
          // next candidate costs a whole add+info round trip, so a sample as
          // the first pick must not throw away a torrent that has a real
          // episode sitting right behind it.
          String? videoUrl;
          for (final selectedLink in newLinks) {
            host.seenRestrictedLinks.add(selectedLink);
            if (torrentId.isNotEmpty) {
              host.seenLinkWithTorrentId.add('$torrentId|$selectedLink');
            }

            Map<String, dynamic> unrestrict;
            try {
              unrestrict = await DebridService.unrestrictLink(
                apiKey,
                selectedLink,
              );
            } catch (error) {
              debugPrint(
                'DebrifyTV: Real-Debrid unrestrict failed for candidate ${candidate.infohash}: $error',
              );
              continue;
            }

            if (!host.cacheWarmer.rdLinkPassesSizeRules(unrestrict)) continue;

            final String? resolved = unrestrict['download'] as String?;
            if (resolved == null || resolved.isEmpty) {
              debugPrint(
                'DebrifyTV: Real-Debrid unrestrict returned empty URL for candidate ${candidate.infohash}',
              );
              continue;
            }
            videoUrl = resolved;
            break;
          }

          if (videoUrl == null) continue;

          String title = candidate.name;
          final uri = Uri.tryParse(videoUrl);
          if (uri != null && uri.pathSegments.isNotEmpty) {
            final inferred = Uri.decodeComponent(uri.pathSegments.last);
            if (inferred.isNotEmpty) {
              title = inferred;
            }
          }

          if (host.mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            host.setState(() {
              host.currentWatchingChannelId = targetChannel.id;
              host.queue
                ..clear()
                ..addAll(remaining);
            });
            host.keywordsController.text = keywords.join(', ');
          }

          host.activeApiKey = apiKey;
          host.activeProvider = CloudProviderId.debrid.magicTvId;
          unawaited(host.startPrefetch());
          debugPrint(
            'DebrifyTV: Started Real-Debrid prefetcher for new channel',
          );
          debugPrint('DebrifyTV: Successfully got stream from channel: $title');

          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': videoUrl,
            'firstTitle': title,
          };
        }

        debugPrint('DebrifyTV: All Real-Debrid candidates failed for channel');
        return null;
      }

      if (MagicTvDispatch.watchId(host.provider) == CloudProviderId.alldebrid) {
        debugPrint('DebrifyTV: Selected channel uses AllDebrid provider');
        final apiKey = await StorageService.getAllDebridApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No AllDebrid API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await host.resolveAllDebridLinks(candidate);
          if (prepared == null || prepared.lockedLinks.isEmpty) {
            // Not cached/ready or no usable video; try the next candidate.
            continue;
          }

          final links = List<String>.from(prepared.lockedLinks);
          final String headLink = links.removeAt(0);

          String videoUrl;
          try {
            videoUrl = await AllDebridService.unlockLink(apiKey, headLink);
          } catch (error) {
            debugPrint(
              'DebrifyTV: AllDebrid unlock failed for candidate ${candidate.infohash}: $error',
            );
            continue;
          }
          if (videoUrl.isEmpty) {
            continue;
          }

          String title = candidate.name;
          final uri = Uri.tryParse(videoUrl);
          if (uri != null && uri.pathSegments.isNotEmpty) {
            final inferred = Uri.decodeComponent(uri.pathSegments.last);
            if (inferred.isNotEmpty) {
              title = inferred;
            }
          }

          if (host.mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            host.setState(() {
              host.currentWatchingChannelId = targetChannel.id;
              host.queue
                ..clear()
                // Remaining video files of this torrent first (already
                // resolved, still locked), then the other candidates.
                ..addAll(
                  links.map(
                    (link) => {
                      'type': 'ad_locked',
                      'allDebridLink': link,
                      'magnetId': prepared.magnetId,
                      'displayName': candidate.name,
                    },
                  ),
                )
                ..addAll(remaining);
            });
            host.keywordsController.text = keywords.join(', ');
          }

          host.activeApiKey = apiKey;
          host.activeProvider = CloudProviderId.alldebrid.magicTvId;
          unawaited(host.startPrefetch());
          debugPrint('DebrifyTV: Started AllDebrid prefetcher for new channel');
          debugPrint('DebrifyTV: Successfully got stream from channel: $title');

          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': videoUrl,
            'firstTitle': title,
          };
        }

        debugPrint('DebrifyTV: All AllDebrid candidates failed for channel');
        return null;
      }

      if (MagicTvDispatch.watchId(host.provider) == CloudProviderId.torbox) {
        final apiKey = await StorageService.getTorboxApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Torbox API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await host.prepareTorboxTorrent(
            candidate: candidate,
            apiKey: apiKey,
            log: (message) => debugPrint(message),
          );

          if (prepared == null || prepared.streamUrl.isEmpty) {
            debugPrint(
              'DebrifyTV: Torbox preparation failed for candidate ${candidate.infohash}',
            );
            continue;
          }

          if (host.mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            host.setState(() {
              host.currentWatchingChannelId = targetChannel.id;
              host.queue
                ..clear()
                ..addAll(remaining);
              if (prepared.hasMore) {
                host.queue.add(candidate);
              }
            });
            host.keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: Torbox channel switch ready with stream ${prepared.title}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared.streamUrl,
            'firstTitle': prepared.title,
          };
        }

        debugPrint('DebrifyTV: All Torbox candidates failed for channel');
        return null;
      }

      if (MagicTvDispatch.watchId(host.provider) == CloudProviderId.pikpak) {
        final pikpakAvailable = await PikPakTvService.instance.isAvailable();
        if (!pikpakAvailable) {
          debugPrint('DebrifyTV: PikPak not authenticated');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await host.preparePikPakTorrent(
            candidate: candidate,
            log: (message) => debugPrint('DebrifyTV/PikPak: $message'),
          );

          if (prepared == null) {
            debugPrint(
              'DebrifyTV: PikPak preparation failed for candidate ${candidate.infohash}',
            );
            continue;
          }

          if (host.mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            host.setState(() {
              host.currentWatchingChannelId = targetChannel.id;
              host.queue
                ..clear()
                ..addAll(remaining);
              // Add back to queue if there are more files in this torrent
              if (prepared.hasMore) {
                host.queue.add(candidate);
              }
            });
            host.keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: PikPak channel switch ready with stream ${prepared.title}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared.streamUrl,
            'firstTitle': prepared.title,
          };
        }

        debugPrint('DebrifyTV: All PikPak candidates failed for channel');
        return null;
      }

      debugPrint(
        'DebrifyTV: Unsupported provider for channel switching: ${host.provider}',
      );
      return null;
    } catch (e) {
      debugPrint('DebrifyTV: Error getting stream from channel: $e');
    }

    debugPrint('DebrifyTV: Channel switch failed');
    if (MagicTvDispatch.usesLockedLinks(host.provider)) {
      unawaited(host.startPrefetch());
      debugPrint('DebrifyTV: Restarted prefetcher for current channel');
    }
    return null;
  }

  int resolveChannelNumber(DebrifyTvChannel channel) {
    if (channel.channelNumber > 0) {
      return channel.channelNumber;
    }
    final int index = host.channels.indexWhere(
      (element) => element.id == channel.id,
    );
    if (index >= 0) {
      return index + 1;
    }
    final int fallback = host.channels.indexOf(channel);
    return fallback >= 0 ? fallback + 1 : 0;
  }

  List<Map<String, dynamic>> androidTvChannelMetadata({
    String? activeChannelId,
  }) {
    if (host.channels.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final String? highlightId =
        activeChannelId ?? host.currentWatchingChannelId;
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
    for (var i = 0; i < host.channels.length; i++) {
      final channel = host.channels[i];
      payload.add({
        'id': channel.id,
        'name': channel.name,
        'channelNumber': channel.channelNumber > 0
            ? channel.channelNumber
            : i + 1,
        'isCurrent': highlightId != null && channel.id == highlightId,
      });
    }
    return payload;
  }

  Future<bool> launchRealDebridOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    debugPrint('DebrifyTV: _launchRealDebridOnAndroidTv() called');
    debugPrint('DebrifyTV: _isAndroidTv=${host.isAndroidTv}');

    if (!host.isAndroidTv) {
      debugPrint('DebrifyTV: Not Android TV, skipping native launch');
      return false;
    }

    final initialUrl = firstStream['url'] ?? '';
    debugPrint(
      'DebrifyTV: initialUrl=${initialUrl.substring(0, initialUrl.length > 50 ? 50 : initialUrl.length)}...',
    );

    if (initialUrl.isEmpty) {
      debugPrint('DebrifyTV: Initial URL is empty, cannot launch');
      return false;
    }

    final title = (firstStream['title'] ?? '').trim();
    debugPrint('DebrifyTV: title="$title"');
    debugPrint(
      'DebrifyTV: Calling AndroidTvPlayerBridge.launchRealDebridPlayback()...',
    );

    try {
      final bool canSwitchChannels =
          host.currentWatchingChannelId != null &&
          host.channels.length > 1 &&
          MagicTvDispatch.usesLockedLinks(host.provider);

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchRealDebridPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        channelName: channelName,
        requestNext: requestNext,
        requestChannelSwitch: canSwitchChannels ? requestNextChannel : null,
        requestChannelById: canSwitchChannels ? requestChannelById : null,
        onFinished: () async {
          debugPrint('DebrifyTV: Android TV playback finished callback');

          // Stop prefetcher when exiting player
          await host.stopPrefetch();
          debugPrint('DebrifyTV: Stopped prefetcher on player exit');

          AndroidTvPlayerBridge.clearStreamProvider();
          host.currentWatchingChannelId = null; // Clear channel tracking
          if (!host.mounted) return;
          host.setState(() {
            host.status = host.queue.isEmpty
                ? ''
                : 'Queue has ${host.queue.length} remaining';
          });
        },
        startFromRandom: host.startRandom,
        randomStartMaxPercent: host.randomStartPercent,
        hideSeekbar: host.hideSeekbar,
        hideOptions: host.hideOptions,
        showVideoTitle: host.showVideoTitle,
        showChannelName: showChannelNameOverride ?? host.showChannelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? host.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );

      debugPrint(
        'DebrifyTV: AndroidTvPlayerBridge.launchRealDebridPlayback() returned: $launched',
      );

      if (launched) {
        if (host.mounted) {
          host.setState(() {
            host.status = 'Playing via Android TV';
          });
        }
        debugPrint(
          'DebrifyTV: ✅ Successfully launched Real-Debrid on Android TV',
        );
        return true;
      } else {
        debugPrint(
          'DebrifyTV: ❌ AndroidTvPlayerBridge returned false - launch failed',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DebrifyTV: ❌ Exception during Android TV launch: $e');
      debugPrint('DebrifyTV: Stack trace: $stackTrace');
    }

    AndroidTvPlayerBridge.clearStreamProvider();
    debugPrint('DebrifyTV: Falling back to Flutter player');
    return false;
  }

  Future<bool> launchPikPakOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!host.isAndroidTv) {
      return false;
    }
    final initialUrl = firstStream['url'] ?? '';
    if (initialUrl.isEmpty) {
      return false;
    }

    final title = (firstStream['title'] ?? '').trim();

    try {
      MainPageBridge.notifyPlayerLaunching();

      // Reuse Torbox bridge method - it works for any stream URL
      final launched = await AndroidTvPlayerBridge.launchTorboxPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        magnets: const [],
        requestNext: requestNext,
        requestChannelSwitch: host.channels.length > 1
            ? requestNextChannel
            : null,
        requestChannelById: host.channels.length > 1
            ? requestChannelById
            : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!host.mounted) {
            return;
          }
          host.setState(() {
            host.status = host.queue.isEmpty
                ? ''
                : 'Queue has ${host.queue.length} remaining';
          });
        },
        startFromRandom: host.startRandom,
        randomStartMaxPercent: host.randomStartPercent,
        hideSeekbar: host.hideSeekbar,
        hideOptions: host.hideOptions,
        showVideoTitle: host.showVideoTitle,
        showChannelName: showChannelNameOverride ?? host.showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? host.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (host.mounted) {
          host.setState(() {
            host.status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed for PikPak: $e');
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }
}
