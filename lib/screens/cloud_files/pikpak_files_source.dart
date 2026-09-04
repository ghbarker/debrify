import '../../services/series_source_service.dart';
import 'cloud_files_source.dart';

/// PikPak [CloudFilesSource]. Folder browse stays a host quirk — no
/// segmented root sections (unlike RD/TorBox/PM/AD).
class PikPakFilesSource extends CloudFilesSource {
  const PikPakFilesSource({
    this.initialFolderId,
    this.initialFolderName,
    this.isPushedRoute = false,
    this.selectSourceMode = false,
    this.onSourceSelectedAsync,
  });

  final String? initialFolderId;
  final String? initialFolderName;

  @override
  final bool isPushedRoute;

  @override
  String? get initialSearchQuery => null;

  @override
  final bool selectSourceMode;

  /// Origin bind is `Future<void> Function(SeriesSource)?` (async).
  final Future<void> Function(SeriesSource)? onSourceSelectedAsync;

  /// Frozen sidebar / tab-back destination id (was a `'pikpak'` literal).
  static const destinationIdValue = 'pikpak';

  static const selectSourceTitleValue = 'Select PikPak Source';

  @override
  String get destinationId => destinationIdValue;

  @override
  String get displayName => 'PikPak';

  @override
  String get selectSourceTitle => selectSourceTitleValue;

  @override
  String get openingTitle => 'Opening folder...';

  @override
  String get openingBody => 'Loading folder contents...';

  @override
  String get openFailedMessage => 'Failed to open folder. Please try again.';

  @override
  List<CloudFilesSection> get sections => const [];
}
