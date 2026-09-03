import '../../models/torrent.dart';

/// Inputs for Stremio TV torrent → URL resolve. Episode matching stays on the
/// adapters; [contentType] is `StremioMeta.type` (`series` / `movie`).
class StremioTorrentResolveArgs {
  const StremioTorrentResolveArgs({
    required this.torrent,
    required this.contentType,
    this.season,
    this.episode,
    this.isCancelled,
  });

  final Torrent torrent;
  final String contentType;
  final int? season;
  final int? episode;
  final bool Function()? isCancelled;

  bool get isSeries => contentType.toLowerCase() == 'series';
  bool get isMovie => contentType.toLowerCase() == 'movie';

  String get magnet =>
      'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
}
