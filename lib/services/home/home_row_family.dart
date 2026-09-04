import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../iptv_media_store.dart' show IptvListMeta;
import '../mdblist/mdblist_list_source.dart';
import '../storage_service.dart';
import '../trakt/trakt_list_source.dart';

/// Which Home board rail family a row belongs to. `_canonicalCanvasRails`
/// groups rails by this slot (CW, then favourites, then sections).
enum HomeBoardSlot { continueWatching, favourites, section }

/// One toggleable Home row leaf, as shown in the Home Rows manager.
class HomeRowLeaf {
  final String id;
  final String label;
  final String groupName;
  final bool defaultOn;
  final bool arrangeable;
  final String? badge;
  final String? extraTitle;
  final bool unavailable;
  final bool on;

  const HomeRowLeaf({
    required this.id,
    required this.label,
    required this.groupName,
    required this.on,
    this.defaultOn = true,
    this.arrangeable = true,
    this.badge,
    this.extraTitle,
    this.unavailable = false,
  });
}

/// A manager rail group whose items are the rows shown under it.
class HomeManagerGroup {
  final String name;
  final List<HomeRowLeaf> items;
  HomeManagerGroup(this.name, this.items);
}

/// Inputs the manager (and fake-family tests) pass to family resolvers.
class HomeRowResolveContext {
  final Set<String> disabled;
  final List<HomeExtraRow> extraRows;
  final List<TraktListChoice> traktUserLists;
  final List<MdblistListChoice> mdblistMine;
  final List<MdblistListChoice> mdblistLiked;
  final List<MdblistListChoice> mdblistTop;
  final List<IptvListMeta> iptvLists;
  final List<HomeCollection> collections;
  final List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>
  catalogTree;
  final bool mdblistEnabled;

  const HomeRowResolveContext({
    this.disabled = const {},
    this.extraRows = const [],
    this.traktUserLists = const [],
    this.mdblistMine = const [],
    this.mdblistLiked = const [],
    this.mdblistTop = const [],
    this.iptvLists = const [],
    this.collections = const [],
    this.catalogTree = const [],
    this.mdblistEnabled = true,
  });

  Map<String, HomeExtraRow> get extraById => {
    for (final r in extraRows) r.id: r,
  };

  bool isOn(String id, {required bool defaultOn}) =>
      defaultOn ? !disabled.contains(id) : extraById.containsKey(id);

  HomeRowLeaf defaultOnLeaf(
    String id,
    String label, {
    required String groupName,
    String? badge,
    bool arrangeable = true,
  }) => HomeRowLeaf(
    id: id,
    label: label,
    groupName: groupName,
    on: isOn(id, defaultOn: true),
    badge: badge,
    arrangeable: arrangeable,
  );

  HomeRowLeaf optInLeaf(
    String id,
    String label, {
    required String groupName,
    String? badge,
  }) => HomeRowLeaf(
    id: id,
    label: label,
    groupName: groupName,
    on: isOn(id, defaultOn: false),
    defaultOn: false,
    badge: badge,
    extraTitle: label,
  );
}

/// One Home row family, keyed by a persisted id prefix.
///
/// Adding a family to [HomeRowRegistry] is enough for it to appear in the
/// Home Rows manager and in canonical board-rail assembly.
class HomeRowFamily {
  /// Stable family id (`cw`, `traktlist`, `catalog`, …).
  final String id;

  /// Persisted prefix this family owns (`cw:`, `traktlist:`, …). Empty for
  /// the addon-catalog family, which matches `addonId:type:catalogId`.
  final String prefix;

  /// Manager rail label. Families that share a name merge into one group
  /// (Trakt CW + Trakt lists).
  final String groupName;

  /// Default-ON rows persist to the disabled set when off; default-OFF
  /// (opt-in) rows persist to the extras store when on.
  final bool defaultOn;

  /// False for folder-list leaves that are toggled here but never arranged.
  final bool arrangeable;

  final HomeBoardSlot boardSlot;

  /// Canonical / board order among families. Lower comes first. Independent
  /// of manager-group order (registration order in the registry).
  final int canonicalIndex;

  final List<HomeRowLeaf> Function(HomeRowResolveContext ctx) resolve;

  /// Override prefix matching (collection owns `collection:` and
  /// `collectionlist:`; catalog matches leftover triples).
  final bool Function(String id)? ownsId;

  /// Extra board row ids this family contributes even when they are not in
  /// the live visible-id set. Production families leave this null; tests
  /// register a fake family that returns its ids here.
  final List<String> Function(HomeRowResolveContext ctx)? boardIds;

  const HomeRowFamily({
    required this.id,
    required this.prefix,
    required this.groupName,
    required this.boardSlot,
    required this.canonicalIndex,
    required this.resolve,
    this.defaultOn = true,
    this.arrangeable = true,
    this.ownsId,
    this.boardIds,
  });

  bool owns(String rowId) => ownsId?.call(rowId) ?? rowId.startsWith(prefix);
}
