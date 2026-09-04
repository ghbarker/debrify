/// Result of a download-picker playlist unlock.
///
/// [CloudPlaylistMiss] is "this adapter handles playlist entries but this
/// one had no usable link". Unsupported adapters do not implement
/// [CloudPlaylist] — they do not return a miss.
sealed class CloudPlaylistResolve {
  const CloudPlaylistResolve();

  String? get urlOrNull => switch (this) {
    CloudPlaylistResolved(:final url) => url,
    CloudPlaylistMiss() => null,
  };
}

/// Unlocked HTTP URL.
final class CloudPlaylistResolved extends CloudPlaylistResolve {
  const CloudPlaylistResolved(this.url);
  final String url;
}

/// Supported adapter, no playable URL (empty/missing metadata).
final class CloudPlaylistMiss extends CloudPlaylistResolve {
  const CloudPlaylistMiss();
}
