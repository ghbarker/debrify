import 'package:flutter/foundation.dart';

import 'home_row_families.dart';
import 'home_row_family.dart';
import 'home_row_ids.dart';

/// Lookup table for Home row families.
///
/// The Home Rows manager and the board's canonical rail assembly both iterate
/// this registry. Tests replace [instance] with extra families; adding a
/// family is enough for it to appear in both surfaces.
class HomeRowRegistry {
  HomeRowRegistry(List<HomeRowFamily> families)
    : families = List.unmodifiable(families);

  factory HomeRowRegistry.production() =>
      HomeRowRegistry(productionHomeRowFamilies());

  static HomeRowRegistry instance = HomeRowRegistry.production();

  final List<HomeRowFamily> families;

  @visibleForTesting
  static void debugReset() {
    instance = HomeRowRegistry.production();
  }

  List<HomeRowFamily> get familiesInCanonicalOrder {
    final out = [...families];
    out.sort((a, b) => a.canonicalIndex.compareTo(b.canonicalIndex));
    return out;
  }

  /// Prefix families first (catalog is last and matches leftover triples).
  HomeRowFamily? familyFor(String id) {
    HomeRowFamily? catalog;
    for (final family in families) {
      if (family.id == 'catalog') {
        catalog = family;
        continue;
      }
      if (family.owns(id)) return family;
    }
    if (catalog != null && catalog.owns(id)) return catalog;
    return null;
  }

  /// Manager groups: iterate families in registration order, merging leaves
  /// that share a [HomeRowFamily.groupName]. Empty groups are omitted.
  ///
  /// Enabled opt-in extras no family resolved (outage / vanished list) are
  /// materialized as unavailable leaves so a save cannot silently drop them.
  List<HomeManagerGroup> buildManagerModel(HomeRowResolveContext ctx) {
    final groups = <HomeManagerGroup>[];
    final byName = <String, HomeManagerGroup>{};

    void addLeaf(HomeRowLeaf leaf) {
      final existing = byName[leaf.groupName];
      if (existing != null) {
        existing.items.add(leaf);
        return;
      }
      final group = HomeManagerGroup(leaf.groupName, [leaf]);
      byName[leaf.groupName] = group;
      groups.add(group);
    }

    for (final family in families) {
      for (final leaf in family.resolve(ctx)) {
        addLeaf(leaf);
      }
    }

    final represented = <String>{
      for (final g in groups)
        for (final it in g.items) it.id,
    };
    for (final r in ctx.extraRows) {
      if (represented.contains(r.id)) continue;
      final family = familyFor(r.id);
      if (family == null || family.id == 'catalog') continue;
      addLeaf(
        HomeRowLeaf(
          id: r.id,
          label: r.title.isNotEmpty ? r.title : r.id,
          groupName: family.groupName,
          on: true,
          defaultOn: false,
          extraTitle: r.title,
          unavailable: true,
        ),
      );
    }
    return groups;
  }

  /// The board's pre-customization order. Keep this aligned with Home's row
  /// assembly: Continue Watching, favourites/IPTV lists, tracker list rows,
  /// then addon catalogs. The settings page groups rows by provider for
  /// toggling, so simply flattening manager groups would produce a different
  /// order.
  List<String> canonicalOrderIds(List<HomeManagerGroup> groups) {
    final items = <String, HomeRowLeaf>{
      for (final group in groups)
        for (final item in group.items) item.id: item,
    };
    final out = <String>[];
    final seen = <String>{};
    void add(String id) {
      final item = items[id];
      if (item != null && item.arrangeable && seen.add(id)) out.add(id);
    }

    for (final family in familiesInCanonicalOrder) {
      for (final group in groups) {
        for (final item in group.items) {
          if (family.owns(item.id)) add(item.id);
        }
      }
    }
    for (final group in groups) {
      for (final item in group.items) {
        if (item.arrangeable) add(item.id);
      }
    }
    return out;
  }

  /// Canonical board rail ids: live [visibleIds] partitioned by family
  /// board-slot / canonicalIndex, then any [HomeRowFamily.boardIds] extras
  /// (fake families in tests). Unknown live ids append in input order.
  List<String> canonicalBoardRailIds({
    Iterable<String> visibleIds = const [],
    HomeRowResolveContext? ctx,
  }) {
    final visible = [
      for (final id in visibleIds)
        if (id.isNotEmpty) id,
    ];
    final out = <String>[];
    final seen = <String>{};
    for (final family in familiesInCanonicalOrder) {
      for (final id in visible) {
        if (family.owns(id) && seen.add(id)) out.add(id);
      }
      if (ctx == null || family.boardIds == null) continue;
      for (final id in family.boardIds!(ctx)) {
        if (id.isNotEmpty && seen.add(id)) out.add(id);
      }
    }
    for (final id in visible) {
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  /// `addonId:type:catalogId` / list / collection row id. Same grammar as
  /// search_screen `_sectionRowId`.
  static String sectionRowId({
    String? listRowId,
    String? collectionRowId,
    required String addonId,
    required String catalogType,
    required String catalogId,
  }) => HomeRowIds.sectionRowId(
    listRowId: listRowId,
    collectionRowId: collectionRowId,
    addonId: addonId,
    catalogType: catalogType,
    catalogId: catalogId,
  );
}
