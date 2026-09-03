import '../../models/torrent.dart';

/// Inputs for Debrify TV (Magic TV) torrent prepare.
///
/// Magnet is infohash-only (`magnet:?xt=urn:btih:…`) — Stremio adds `&dn=`.
/// File pick is random unseen, not Stremio episode matching.
class MagicTvPrepareRequest {
  const MagicTvPrepareRequest({
    required this.torrent,
    required this.log,
    required this.seenKeys,
    required this.sizeMatchesBytes,
    required this.hasSizeFilter,
    required this.minVideoSizeBytes,
  });

  final Torrent torrent;
  final void Function(String message) log;
  final Set<String> seenKeys;
  final bool Function(int bytes) sizeMatchesBytes;
  final bool hasSizeFilter;
  final int minVideoSizeBytes;

  String get infohash => torrent.infohash.trim().toLowerCase();

  /// Debrify TV magnet. Do not add `dn=` — Stremio's resolver does.
  String get magnet => 'magnet:?xt=urn:btih:${torrent.infohash}';
}

class MagicTvPrepared {
  const MagicTvPrepared({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });

  final String streamUrl;
  final String title;
  final bool hasMore;
}
