import '../../models/stremio_addon.dart';

/// Shared raw-row → [StremioMeta] shape. Families keep their static helpers;
/// the registry holds an instance adapter so callers can iterate.
abstract class TrackerItemTransformer {
  StremioMeta? transformItem(Map<String, dynamic> raw, {String? inferredType});

  List<StremioMeta> transformList(List<dynamic> items, {String? inferredType});
}
