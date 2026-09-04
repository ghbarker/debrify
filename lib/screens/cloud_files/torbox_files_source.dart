import 'package:flutter/material.dart';

import '../../models/torbox_torrent.dart';
import '../../services/series_source_service.dart';
import 'cloud_files_source.dart';

/// TorBox [CloudFilesSource]. Web downloads are a source-provided section
/// on the same screen, not a second route.
class TorBoxFilesSource extends CloudFilesSource {
  const TorBoxFilesSource({
    this.initialTorrentToOpen,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  final TorboxTorrent? initialTorrentToOpen;

  @override
  final bool isPushedRoute;

  @override
  final String? initialSearchQuery;

  @override
  final bool selectSourceMode;

  @override
  final void Function(SeriesSource)? onSourceSelected;

  /// Frozen sidebar / tab-back destination id (was a `'torbox'` literal).
  static const destinationIdValue = 'torbox';

  static const selectSourceTitleValue = 'Select Source from TorBox';

  static const torrentsSection = CloudFilesSection(
    id: 'torrents',
    label: 'Torrents',
    icon: Icons.folder_rounded,
  );

  static const webDownloadsSection = CloudFilesSection(
    id: 'webDownloads',
    label: 'Web Downloads',
    icon: Icons.link_rounded,
  );

  @override
  String get destinationId => destinationIdValue;

  @override
  String get displayName => 'TorBox';

  @override
  String get selectSourceTitle => selectSourceTitleValue;

  @override
  List<CloudFilesSection> get sections => const [
    torrentsSection,
    webDownloadsSection,
  ];
}
