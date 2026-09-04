import 'package:flutter/material.dart';

import '../../services/series_source_service.dart';
import 'cloud_files_source.dart';

/// AllDebrid [CloudFilesSource]. Magnet library and saved links are
/// source-provided sections on the same screen.
class AllDebridFilesSource extends CloudFilesSource {
  const AllDebridFilesSource({
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelectedAsync,
  });

  @override
  final bool isPushedRoute;

  @override
  final String? initialSearchQuery;

  @override
  final bool selectSourceMode;

  /// Origin bind is `Future<void> Function(SeriesSource)?` (async).
  final Future<void> Function(SeriesSource)? onSourceSelectedAsync;

  /// Frozen sidebar / tab-back destination id (was a `'alldebrid'` literal).
  static const destinationIdValue = 'alldebrid';

  static const selectSourceTitleValue = 'Select AllDebrid Source';

  static const torrentsSection = CloudFilesSection(
    id: 'torrents',
    label: 'Torrent Downloads',
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
  String get displayName => 'AllDebrid';

  @override
  String get selectSourceTitle => selectSourceTitleValue;

  @override
  List<CloudFilesSection> get sections => const [
    torrentsSection,
    webDownloadsSection,
  ];
}
