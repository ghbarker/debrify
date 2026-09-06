import '../../../models/torrent.dart';
import 'provider_watch_flow.dart';
import 'cached_locked_watch_programme.dart';

class RealDebridWatchFlow {
  const RealDebridWatchFlow(this.host);
  final WatchFlowBindings host;

  Future<void> watchWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    required bool applyNsfwFilter,
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) => runCachedLockedWatch(
    host,
    cachedTorrents,
    provider: CachedLockedProvider.realDebrid,
    applyNsfwFilter: applyNsfwFilter,
    channelName: channelName,
    channelId: channelId,
    channelNumber: channelNumber,
  );
}
