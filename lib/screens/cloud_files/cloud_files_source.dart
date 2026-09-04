import 'package:flutter/material.dart';

import '../../services/series_source_service.dart';

/// One root section of a [CloudFilesSource] (torrent library, DDL, web
/// downloads, …). Per-provider quirks such as the Real-Debrid folder tree
/// and TorBox web downloads are source-provided sections, not extra screens.
class CloudFilesSection {
  const CloudFilesSection({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Screen-local files capability used by [CloudFilesScreen].
///
/// This is **not** the P1 adapter port. It wraps current screen constructor
/// data (route flags, bind callbacks, section tables). Do not add this to
/// `lib/services/cloud/**` adapters from this lane.
abstract class CloudFilesSource {
  const CloudFilesSource();

  /// Sidebar / [MainPageBridge] tab-back key. Frozen destination ids.
  String get destinationId;

  String get displayName;

  /// AppBar title in select-source / bind mode.
  String get selectSourceTitle;

  /// Deep-link splash while a folder tree is still loading.
  String get openingTitle => 'Opening torrent...';

  String get openingBody => 'Loading torrent files...';

  /// 10s deep-link timeout snack (identical on RD and TorBox today).
  String get openFailedMessage => 'Failed to open torrent. Please try again.';

  List<CloudFilesSection> get sections;

  bool get isPushedRoute;
  bool get selectSourceMode;
  String? get initialSearchQuery;

  /// RD/TorBox bind is sync. PM/AD/PikPak bind is async and stays on the host.
  void Function(SeriesSource)? get onSourceSelected => null;
}
