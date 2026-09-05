/// Immediate common consumer of TB/PM prepared results; objects stay unchanged.
abstract interface class WindowedPreparedTorrent {
  String get streamUrl;
  String get title;
  bool get hasMore;
}

/// Represents a Torbox torrent that has been prepared for streaming.
///
/// Contains the stream URL, title, and whether there are more files
/// available in the torrent.
class TorboxPreparedTorrent implements WindowedPreparedTorrent {
  @override
  final String streamUrl;
  @override
  final String title;
  @override
  final bool hasMore;

  TorboxPreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}

/// Represents a PikPak torrent that has been prepared for streaming.
///
/// Contains the stream URL, title, and whether there are more files
/// available in the torrent.
class PikPakPreparedTorrent {
  final String streamUrl;
  final String title;
  final bool hasMore;

  PikPakPreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}

/// Represents a Premiumize torrent that has been prepared for streaming.
///
/// Premiumize returns ready-to-use direct links from directdl in one call,
/// so no separate unrestrict step is needed.
class PremiumizePreparedTorrent implements WindowedPreparedTorrent {
  @override
  final String streamUrl;
  @override
  final String title;
  @override
  final bool hasMore;

  PremiumizePreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}
