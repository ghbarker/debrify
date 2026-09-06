import 'dart:convert';

import 'home_collection.dart';

/// Atomic local inventory. Null records are durable, per-collection deletions:
/// an absent record on an offline peer must never resurrect a deleted folder.
/// Legacy list preferences are accepted and upgraded on the next mutation.
class HomeCollectionInventory {
  static const String prefsKey = 'home_collections_v1';
  static const int maxStoredBytes = 128 * 1024;
  static const int maxRecords = 1024;

  final Map<String, HomeCollection?> records;
  final List<String> order;

  HomeCollectionInventory({
    Map<String, HomeCollection?>? records,
    List<String>? order,
  }) : records = records ?? {},
       order = order ?? [];

  factory HomeCollectionInventory.decode(Object? encoded) {
    if (encoded == null || encoded == '') return HomeCollectionInventory();
    final raw = encoded is String ? jsonDecode(encoded) : encoded;
    final out = HomeCollectionInventory();
    if (raw is List) {
      for (final item in raw) {
        final c = HomeCollection.fromJson(item);
        if (c == null) throw const FormatException('Invalid saved collection.');
        out.put(c);
      }
      return out;
    }
    if (raw is! Map ||
        raw['version'] != 2 ||
        raw['records'] is! Map ||
        raw['order'] is! List) {
      throw const FormatException(
        'Invalid saved collections. Restore a backup or remove them before importing.',
      );
    }
    for (final entry in (raw['records'] as Map).entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw const FormatException('Invalid collection identity.');
      }
      final value = entry.value;
      final c = value == null ? null : HomeCollection.fromJson(value);
      if (value != null && (c == null || c.id != entry.key)) {
        throw const FormatException('Invalid saved collection.');
      }
      out.records[entry.key as String] = c;
    }
    for (final id in raw['order'] as List) {
      if (id is! String) {
        throw const FormatException('Invalid collection order.');
      }
      if (out.records.containsKey(id) && !out.order.contains(id)) {
        out.order.add(id);
      }
    }
    for (final id in out.records.keys) {
      if (!out.order.contains(id)) out.order.add(id);
    }
    return out;
  }

  List<HomeCollection> get collections => [
    for (final id in order)
      if (records[id] case final c?) c,
  ];

  void put(HomeCollection c) {
    records[c.id] = c;
    if (!order.contains(c.id)) order.add(c.id);
  }

  void remove(String id) {
    if (records.containsKey(id)) records[id] = null;
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    'records': {for (final e in records.entries) e.key: e.value?.toJson()},
    'order': order,
  };

  /// IDs become WebDAV record keys and Home row identities. Reject oversized
  /// identities before they can create an inventory that cannot be synced.
  void validate() {
    void bounded(String value, int limit, String label) {
      if (value.contains('\u0000')) {
        throw FormatException('$label contains an invalid character.');
      }
      if (utf8.encode(value).length > limit) {
        throw FormatException(
          '$label is too long. Import a smaller collection file.',
        );
      }
    }

    for (final entry in records.entries) {
      if (entry.key.isEmpty) {
        throw const FormatException('Collection ID must not be empty.');
      }
      bounded(entry.key, 256, 'Collection ID');
      final c = entry.value;
      if (c == null) continue;
      for (final f in c.folders) {
        bounded(f.id, 256, 'Folder ID');
        for (final source in f.sources) {
          bounded(source.addonId, 256, 'Addon ID');
          bounded(source.catalogId, 256, 'Catalog ID');
          bounded(source.type, 64, 'Catalog type');
          bounded(source.genre ?? '', 256, 'Genre');
        }
      }
    }
  }

  String encode() => jsonEncode(toJson());
}
