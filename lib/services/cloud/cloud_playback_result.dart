import 'package:flutter/foundation.dart';

import '../../screens/video_player/models/playlist_entry.dart';

/// Resolved add result carrying what each post-action branch needs.
class CloudPlaybackResult {
  final String title;
  final String? playUrl;
  final List<String> downloadUrls;
  final VoidCallback? openInTab;

  /// Multi-file playlist (season packs); the launcher lazily resolves each
  /// entry's URL from its provider metadata (torboxFileId / allDebridLink /
  /// restrictedLink / premiumizePath / pikpakFileId). [startIndex] is the
  /// first-episode entry to begin playback at.
  final List<PlaylistEntry>? playlist;
  final int startIndex;

  /// The single resolved file's name (with extension) for download naming.
  final String? fileName;

  /// RD only: an unextracted RAR archive (multiple files, one link). The
  /// provider "open" view isn't useful for these, so it's disabled.
  final bool isRarArchive;

  /// TorBox only: the torrent id, for the "Copy Download Link (Zip)" action.
  final int? torboxTorrentId;

  /// RD only: the account entry this add created (RD's addMagnet always makes
  /// a fresh entry), so a rejected bound-source attempt can delete it again.
  final String? rdTorrentId;

  /// PikPak only: the drive entry (file/folder) this add created (PikPak's
  /// addOfflineDownload always makes a fresh entry), so a rejected
  /// bound-source attempt can delete it again.
  final String? pikpakFileId;

  // Single-file provider-native identifiers, captured so an "Add to playlist"
  // item can be RE-RESOLVED after the direct URL expires.
  final String? restrictedLink;
  final int? torboxFileId;
  final String? premiumizePath;
  final String? allDebridLink;
  final String? pikpakVideoFileId;

  const CloudPlaybackResult({
    required this.title,
    this.playUrl,
    this.downloadUrls = const [],
    this.openInTab,
    this.playlist,
    this.startIndex = 0,
    this.fileName,
    this.isRarArchive = false,
    this.torboxTorrentId,
    this.rdTorrentId,
    this.pikpakFileId,
    this.restrictedLink,
    this.torboxFileId,
    this.premiumizePath,
    this.allDebridLink,
    this.pikpakVideoFileId,
  });

  bool get hasPlaylist => playlist != null && playlist!.length > 1;
}
