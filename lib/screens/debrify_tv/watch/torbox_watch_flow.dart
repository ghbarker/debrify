import '../../../models/torrent.dart';

import 'provider_watch_flow.dart';
import 'cached_windowed_watch_programme.dart';
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
  }) => runCachedWindowedWatch(
    host,
    cachedTorrents,
    provider: WindowedProvider.torbox,
    channelName: channelName,
    channelId: channelId,
    channelNumber: channelNumber,
  );
}
