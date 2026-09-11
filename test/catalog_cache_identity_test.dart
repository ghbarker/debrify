import 'dart:collection';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/catalog_disk_cache.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Count traversal of the complete configuration without a production test hook
// or a machine-dependent wall-clock assertion. Reading fields for comparison
// does not enumerate this map; canonicalizing the full manifest does.
class ObservedMap extends MapBase<String, dynamic> {
  ObservedMap(this.valuesMap, this.onKeys);
  final Map<String, dynamic> valuesMap;
  final void Function() onKeys;
  @override
  Iterable<String> get keys {
    onKeys();
    return valuesMap.keys;
  }

  @override
  int get length => valuesMap.length;
  @override
  bool containsKey(Object? key) => valuesMap.containsKey(key);
  @override
  dynamic operator [](Object? key) => valuesMap[key];
  @override
  void operator []=(String key, dynamic value) => valuesMap[key] = value;
  @override
  void clear() => valuesMap.clear();
  @override
  dynamic remove(Object? key) => valuesMap.remove(key);
}

class ObservedAddon extends StremioAddon {
  ObservedAddon(String id, List<StremioAddonCatalog> catalogs)
    : super(
        id: id,
        name: 'Synthetic',
        baseUrl: 'https://example.invalid/$id',
        manifestUrl: 'https://example.invalid/$id/manifest.json',
        catalogs: catalogs,
        types: ['movie'],
        resources: ['catalog'],
        idPrefixes: ['tt'],
      );
  int fullTraversals = 0;
  @override
  Map<String, dynamic> toJson() =>
      ObservedMap(super.toJson(), () => fullTraversals++);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const catalog = StremioAddonCatalog(id: 'one', type: 'movie', name: 'One');
  final cache = CatalogDiskCache.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BrowsingCachePreferences.resetForTesting();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'synthetic', dataGeneration: 1, sessionEpoch: 1),
    );
    cache.invalidateRequests();
    await BrowsingCachePreferences.initialize();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    cache.invalidateRequests();
    BrowsingCachePreferences.resetForTesting();
  });

  Future<CatalogCacheRequest> request(
    StremioAddon addon, {
    String url = 'https://example.invalid/catalog/movie/one.json',
    StremioAddonCatalog selected = catalog,
  }) => cache.request(url, addon, selected);

  test(
    '2250-catalog snapshot is canonicalized once across distinct pages',
    () async {
      final addon = ObservedAddon(
        'large',
        List.generate(
          2250,
          (i) =>
              StremioAddonCatalog(id: 'row-$i', type: 'movie', name: 'Row $i'),
        ),
      );
      final keys = <String>{};
      for (var i = 0; i < 30; i++) {
        final result = await request(
          addon,
          url: 'https://example.invalid/page-$i',
        );
        expect(result.enabled, isFalse);
        expect(cache.isCurrent(result), isTrue);
        keys.add(result.key);
      }
      expect(keys, hasLength(30));
      expect(addon.fullTraversals, 1);
      final first = await request(addon, url: 'https://example.invalid/page-0');
      expect(first.key, keys.first);
      expect(addon.fullTraversals, 1);
    },
  );

  test(
    'nested mutations and copyWith aliases change identity even with titles off',
    () async {
      final options = ['Drama', 'Comedy'];
      final supported = ['genre'];
      final extras = [StremioExtraParam(name: 'genre', options: options)];
      final catalogs = [
        StremioAddonCatalog(
          id: 'one',
          type: 'movie',
          name: 'One',
          extraSupported: supported,
          extras: extras,
        ),
      ];
      final addon = ObservedAddon('mutable', catalogs);
      var before = await request(addon);
      for (final mutate in <void Function()>[
        () => options[0] = 'Action',
        () => supported.add('skip'),
        () => extras.add(
          const StremioExtraParam(name: 'search', isRequired: true),
        ),
        () => catalogs.add(
          const StremioAddonCatalog(id: 'two', type: 'series', name: 'Two'),
        ),
        () => catalogs[0] = const StremioAddonCatalog(
          id: 'one',
          type: 'movie',
          name: 'Renamed',
        ),
        () => addon.types.add('series'),
        () => addon.resources.add('meta'),
        () => addon.idPrefixes!.add('tmdb:'),
      ]) {
        mutate();
        final after = await request(addon);
        expect(after.key, isNot(before.key));
        expect((await request(addon)).key, after.key);
        before = after;
      }
      final alias = addon.copyWith();
      expect((await request(alias)).key, before.key);
      alias.catalogs.removeLast();
      expect((await request(addon)).key, isNot(before.key));
    },
  );

  test(
    'all stored scalar configuration remains part of the identity',
    () async {
      final addon = ObservedAddon('config', [catalog]);
      final original = (await request(addon)).key;
      for (final changed in [
        addon.copyWith(name: 'Renamed'),
        addon.copyWith(manifestId: 'new-manifest'),
        addon.copyWith(
          manifestUrl: 'https://example.invalid/new/manifest.json',
        ),
        addon.copyWith(baseUrl: 'https://example.invalid/new-config'),
        addon.copyWith(connectionResourceId: 'resource'),
        addon.copyWith(connectionResourceRevision: 2),
        addon.copyWith(connectionResourceReadOnly: true),
        addon.copyWith(connectionResourceCredentialsRedacted: true),
        addon.copyWith(description: 'Changed'),
        addon.copyWith(version: '2'),
        addon.copyWith(enabled: false),
      ]) {
        expect((await request(changed)).key, isNot(original));
      }
      expect(
        (await request(
          addon.copyWith(addedAt: DateTime(2000), lastChecked: DateTime(2026)),
        )).key,
        original,
      );
      expect(
        (await request(
          addon,
          selected: const StremioAddonCatalog(
            id: 'one',
            type: 'movie',
            name: 'Different selection',
          ),
        )).key,
        isNot(original),
      );
    },
  );

  test(
    'memo is bounded and eviction does not change stable identity',
    () async {
      final first = ObservedAddon('first', [catalog]);
      final key = (await request(first)).key;
      for (var i = 0; i < 9; i++) {
        await request(ObservedAddon('other-$i', [catalog]));
      }
      expect((await request(first)).key, key);
      expect(first.fullTraversals, 2);
    },
  );

  test(
    'authority changes invalidate pending requests and cached snapshots',
    () async {
      final addon = ObservedAddon('scope', [catalog]);
      final old = await request(addon);
      cache.invalidateRequests();
      expect(cache.isCurrent(old), isFalse);
      final refreshed = await request(addon);
      expect(refreshed.key, old.key);
      expect(refreshed.memoryKey, isNot(old.memoryKey));
      expect(addon.fullTraversals, 2);
      MetadataPreferencesService.revision.value++;
      expect(cache.isCurrent(refreshed), isFalse);
      final metadata = await request(addon);
      expect(metadata.memoryKey, isNot(refreshed.memoryKey));
      expect(addon.fullTraversals, 3);
      ProfileRuntime.publish(
        ProfileScope(
          profileId: 'synthetic',
          dataGeneration: 1,
          sessionEpoch: 2,
        ),
      );
      final session = await request(addon);
      expect(session.key, old.key);
      expect(session.memoryKey, isNot(old.memoryKey));
      ProfileRuntime.publish(
        ProfileScope(
          profileId: 'synthetic',
          dataGeneration: 2,
          sessionEpoch: 3,
        ),
      );
      final generation = await request(addon);
      expect(generation.key, isNot(old.key));
      ProfileRuntime.publish(
        ProfileScope(profileId: 'other', dataGeneration: 1, sessionEpoch: 4),
      );
      expect((await request(addon)).key, isNot(old.key));
    },
  );

  test(
    'enabled persistence keeps metadata and nested configuration in identity',
    () async {
      await BrowsingCachePreferences.update(
        const BrowsingCacheOptions(rememberTitles: true),
      );
      final options = ['Drama'];
      final addon = ObservedAddon('enabled', [
        StremioAddonCatalog(
          id: 'one',
          type: 'movie',
          name: 'One',
          extras: [StremioExtraParam(name: 'genre', options: options)],
        ),
      ]);
      final before = await request(addon);
      expect(before.enabled, isTrue);
      options[0] = 'Action';
      final edited = await request(addon);
      expect(edited.key, isNot(before.key));
      await MetadataPreferencesService.save(
        MetadataPreferences(language: 'fr-FR'),
      );
      final translated = await request(addon);
      expect(translated.key, isNot(edited.key));
      expect(cache.isCurrent(edited), isFalse);
      expect((await request(addon)).key, translated.key);
    },
  );

  test(
    'uninitialized profile keeps a disabled request without opening profile preferences',
    () async {
      ProfileRuntime.debugReset();
      final result = await request(ObservedAddon('no-profile', [catalog]));
      expect(result.scope, isNull);
      expect(result.enabled, isFalse);
    },
  );

  test(
    'profile switch while preferences initialize cannot authorize the old request',
    () async {
      final addon = ObservedAddon('race', [catalog]);
      BrowsingCachePreferences.resetForTesting();
      final pending = request(addon);
      ProfileRuntime.publish(
        ProfileScope(profileId: 'other', dataGeneration: 1, sessionEpoch: 2),
      );
      final stale = await pending;
      expect(cache.isCurrent(stale), isFalse);
      expect(stale.scope!.profileId, 'synthetic');
      final current = await request(addon);
      expect(current.key, isNot(stale.key));
      expect(cache.isCurrent(current), isTrue);
    },
  );
}
