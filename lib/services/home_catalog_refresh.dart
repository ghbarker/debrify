import 'package:collection/collection.dart';
import '../models/stremio_addon.dart';

/// Reuses unchanged rows, including their paging state and any in-flight page.
/// Changed definitions reload the old raw paging extent before replacing a row.
Future<CatalogSection?> loadHomeCatalogSection({
  required StremioAddon addon,
  required StremioAddonCatalog catalog,
  CatalogSection? previous,
  required Future<List<StremioMeta>> Function(
    int skip,
    void Function(int) onRawCount,
  )
  fetch,
  required bool Function() isCurrent,
}) async {
  final sameIdentity =
      previous != null &&
      previous.addon.id == addon.id &&
      previous.catalog.id == catalog.id &&
      previous.catalog.type == catalog.type;
  if (sameIdentity &&
      const DeepCollectionEquality().equals(
        previous.addon.toJson(),
        addon.toJson(),
      ) &&
      const DeepCollectionEquality().equals(
        previous.catalog.toJson(),
        catalog.toJson(),
      )) {
    return previous;
  }
  final targetSkip = sameIdentity ? previous.nextSkip : 0;
  final items = <StremioMeta>[];
  final seen = <String>{};
  var skip = 0;
  var exhausted = false;
  do {
    if (!isCurrent()) return null;
    var rawCount = 0;
    final page = await fetch(skip, (count) => rawCount = count);
    if (!isCurrent()) return null;
    if (page.isEmpty) {
      exhausted = true;
      break;
    }
    skip += rawCount > 0 ? rawCount : page.length;
    final fresh = page.where((item) => seen.add(item.id)).toList();
    items.addAll(fresh);
    if (fresh.isEmpty) {
      exhausted = true;
      break;
    }
  } while (skip < targetSkip);
  if (items.isEmpty) return null;
  return CatalogSection(
    title: CatalogSection.rowTitle(catalog),
    addon: addon,
    catalog: catalog,
    items: items,
    nextSkip: skip,
    exhausted: exhausted,
  );
}
