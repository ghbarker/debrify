import 'package:flutter/material.dart';

import '../../services/series_source_service.dart';
import 'cloud_files_source.dart';

/// Premiumize [CloudFilesSource]. Folder browse and Transfers are
/// source-provided sections — not a second screen.
class PremiumizeFilesSource extends CloudFilesSource {
  const PremiumizeFilesSource({
    this.initialFolderId,
    this.initialFolderName,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelectedAsync,
  });

  final String? initialFolderId;
  final String? initialFolderName;

  @override
  final bool isPushedRoute;

  @override
  final String? initialSearchQuery;

  @override
  final bool selectSourceMode;

  /// Origin bind is `Future<void> Function(SeriesSource)?` (async).
  final Future<void> Function(SeriesSource)? onSourceSelectedAsync;

  /// Frozen sidebar / tab-back destination id (was a `'premiumize'` literal).
  static const destinationIdValue = 'premiumize';

  static const selectSourceTitleValue = 'Select Premiumize Source';

  static const filesSection = CloudFilesSection(
    id: 'files',
    label: 'My Files',
    icon: Icons.folder_rounded,
  );

  static const transfersSection = CloudFilesSection(
    id: 'transfers',
    label: 'Transfers',
    icon: Icons.swap_vert_rounded,
  );

  @override
  String get destinationId => destinationIdValue;

  @override
  String get displayName => 'Premiumize';

  @override
  String get selectSourceTitle => selectSourceTitleValue;

  @override
  String get openingTitle => 'Opening folder...';

  @override
  List<CloudFilesSection> get sections => const [
    filesSection,
    transfersSection,
  ];
}
