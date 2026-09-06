import '../../../models/torrent.dart';

import 'provider_watch_flow.dart';
import 'cached_windowed_watch_programme.dart';
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
  }) => runCachedWindowedWatch(
    host,
    cachedTorrents,
    provider: WindowedProvider.premiumize,
    channelName: channelName,
    channelId: channelId,
    channelNumber: channelNumber,
  );
}
