import 'package:flutter/material.dart';

import '../../models/rd_torrent.dart';
import '../../services/series_source_service.dart';
import 'cloud_files_source.dart';

/// Real-Debrid [CloudFilesSource]. Folder-tree browse stays a host quirk
/// of the torrents section — not a second screen.
class RealDebridFilesSource extends CloudFilesSource {
  const RealDebridFilesSource({
    this.initialTorrentForOptions,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  final RDTorrent? initialTorrentForOptions;

  @override
  final bool isPushedRoute;

  @override
  final String? initialSearchQuery;

  @override
  final bool selectSourceMode;

  @override
  final void Function(SeriesSource)? onSourceSelected;

  /// Frozen sidebar / tab-back destination id (was a `'realdebrid'` literal).
  static const destinationIdValue = 'realdebrid';

  static const selectSourceTitleValue = 'Select Source from Real-Debrid';

  static const torrentsSection = CloudFilesSection(
    id: 'torrents',
    label: 'Torrent Downloads',
    icon: Icons.folder_rounded,
  );

  static const ddlSection = CloudFilesSection(
    id: 'ddl',
    label: 'DDL Downloads',
    icon: Icons.download_rounded,
  );

  @override
  String get destinationId => destinationIdValue;

  @override
  String get displayName => 'Real-Debrid';

  @override
  String get selectSourceTitle => selectSourceTitleValue;

  @override
  List<CloudFilesSection> get sections => const [torrentsSection, ddlSection];
}
