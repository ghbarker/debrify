import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

import '../models/home_collection.dart';
import '../models/home_collection_inventory.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import '../models/stremio_addon.dart';
import 'profiles/profile_preferences.dart';

/// Outcome of an import, for the settings page's result dialog.
class HomeCollectionImportResult {
  /// Collections new to this profile.
  final List<HomeCollection> added;

  /// Collections whose id already existed and were replaced in place
  /// (keeping their enabled state).
  final List<HomeCollection> replaced;

  /// Addon ids no installed addon can serve (see
  /// [HomeCollectionsStore.resolveAddon]). Their folders still import; they
  /// browse empty until such an addon is installed.
  final Set<String> unresolvedAddonIds;

  const HomeCollectionImportResult({
    required this.added,
    required this.replaced,
    required this.unresolvedAddonIds,
  });

  int get collectionCount => added.length + replaced.length;
  int get folderCount =>
      [...added, ...replaced].fold(0, (sum, c) => sum + c.folders.length);
}

/// Profile-scoped store for imported Home collections, plus the import
/// pipeline (file / URL / paste) and the addon-resolution helpers the board,
/// the folder browser and the settings pages share.
///
/// Persists an atomic inventory under `home_collections_v1`. Deleted IDs
/// remain as null records for sync; corrupt inventories surface an error
/// instead of being silently replaced. Legacy JSON arrays remain readable.
class HomeCollectionsStore {
  HomeCollectionsStore({http.Client Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  static final HomeCollectionsStore instance = HomeCollectionsStore();

  static const String prefsKey = HomeCollectionInventory.prefsKey;

  /// Folder layout preference (`rows` | `tabs`), profile-scoped.
  static const String folderLayoutKey = 'home_collections_folder_layout';
  static const Duration _fetchTimeout = Duration(seconds: 20);

  /// Documents past this are refused before decoding: a collections file is
  /// a few hundred KB at most, so anything larger is a wrong pick.
  static const int maxImportBytes = 8 * 1024 * 1024;

  final http.Client Function() _httpClientFactory;

  // ── Read / write ───────────────────────────────────────────────────────

  /// Call before opening a picker/downloading, so completion cannot change
  /// the profile which owns an import. Also captures legacy -> profile changes.
  static ({ProfileScope? scope, ProfileScope? active, bool committed})
  captureSession() => (
    scope: ProfileRuntime.isProfileCommitted ? ProfileRuntime.capture() : null,
    active: ProfileRuntime.scope.value,
    committed: ProfileRuntime.isProfileCommitted,
  );

  static void checkSession(
    ({ProfileScope? scope, ProfileScope? active, bool committed}) session,
  ) {
    if (session != captureSession()) {
      throw StateError('The profile changed. Import the collections again.');
    }
  }

  Future<List<HomeCollection>> getCollections() async {
    final prefs = await ProfilePreferences.instance();
    return HomeCollectionInventory.decode(
      prefs.getString(prefsKey),
    ).collections;
  }

  Future<List<HomeCollection>> getEnabledCollections() async => [
    for (final c in await getCollections())
      if (c.enabled && c.folders.isNotEmpty) c,
  ];

  Future<T> _mutate<T>(
    ({ProfileScope? scope, ProfileScope? active, bool committed}) session,
    T Function(HomeCollectionInventory current) update,
  ) async {
    checkSession(session);
    final prefs = await ProfilePreferences.instance();
    checkSession(session);
    late T result;
    final saved = await prefs.mutateStringAtomically(prefsKey, (old) {
      checkSession(session);
      final current = HomeCollectionInventory.decode(old);
      final previousSize = utf8.encode(current.encode()).length;
      final previousCount = current.records.length;
      result = update(current);
      current.validate();
      final encoded = current.encode();
      final size = utf8.encode(encoded).length;
      // Permit reduction of an older/merged oversized inventory, but never
      // increase one. Deletions remain records to survive offline peers.
      if ((size > HomeCollectionInventory.maxStoredBytes &&
              size > previousSize) ||
          (current.records.length > HomeCollectionInventory.maxRecords &&
              current.records.length > previousCount)) {
        throw const FormatException(
          'Collections exceed the profile storage limit (128 KiB). Remove a collection or import a smaller file.',
        );
      }
      return encoded;
    });
    if (!saved) {
      throw StateError(
        'Could not save collections: device storage limit reached.',
      );
    }
    return result;
  }

  Future<void> saveCollections(List<HomeCollection> collections) =>
      _mutate<void>(captureSession(), (current) {
        final ids = collections.map((c) => c.id).toSet();
        for (final id in current.records.keys.toList()) {
          if (!ids.contains(id)) current.remove(id);
        }
        for (final c in collections) {
          current.put(c);
        }
        final deletedIds = current.order
            .where((id) => !ids.contains(id))
            .toList();
        current.order
          ..clear()
          ..addAll(ids)
          ..addAll(deletedIds);
      });

  static String signatureOf(List<HomeCollection> collections) => sha256
      .convert(
        utf8.encode(jsonEncode([for (final c in collections) c.toJson()])),
      )
      .toString();

  Future<void> remove(String id) =>
      _mutate<void>(captureSession(), (current) => current.remove(id));

  Future<void> setEnabled(String id, bool enabled) =>
      _mutate<void>(captureSession(), (current) {
        final c = current.records[id];
        if (c != null) current.put(c.copyWith(enabled: enabled));
      });

  Future<void> clear() => _mutate<void>(captureSession(), (current) {
    for (final id in current.records.keys.toList()) {
      current.remove(id);
    }
  });

  Future<CollectionFolderLayout> getFolderLayout() async {
    final prefs = await ProfilePreferences.instance();
    return CollectionFolderLayout.parse(prefs.getString(folderLayoutKey));
  }

  Future<void> setFolderLayout(CollectionFolderLayout layout) async {
    final session = captureSession();
    final prefs = await ProfilePreferences.instance();
    checkSession(session);
    if (!await prefs.setString(folderLayoutKey, layout.storageValue)) {
      throw StateError(
        'Could not save folder layout: device storage limit reached.',
      );
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────

  /// Merge parsed collections into the store: a known id is replaced in place
  /// (keeping the user's enabled toggle), a new id is appended. With
  /// [replaceExisting] every stored collection is dropped first.
  Future<HomeCollectionImportResult> importCollections(
    List<HomeCollection> incoming, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) async {
    final session = captureSession();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _mutate(session, (current) {
      final added = <HomeCollection>[];
      final replaced = <HomeCollection>[];
      if (replaceExisting) {
        for (final id in current.records.keys.toList()) {
          current.remove(id);
        }
      }
      for (final c in incoming) {
        final existing = current.records[c.id];
        final stamped = c.copyWith(
          importedAtMs: now,
          enabled: existing?.enabled ?? c.enabled,
        );
        current.put(stamped);
        (existing == null ? added : replaced).add(stamped);
      }
      return HomeCollectionImportResult(
        added: added,
        replaced: replaced,
        unresolvedAddonIds: unresolvedAddonIds(incoming, installedAddons),
      );
    });
  }

  /// Parse and import a JSON document (file contents, pasted text, or a
  /// fetched URL body). Throws [FormatException] for a bad document.
  Future<HomeCollectionImportResult> importJson(
    String jsonText, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) {
    if (utf8.encode(jsonText).length > maxImportBytes) {
      throw const FormatException('That file is too large to be a collection.');
    }
    final parsed = HomeCollectionParser.parse(jsonText);
    return importCollections(
      parsed,
      replaceExisting: replaceExisting,
      installedAddons: installedAddons,
    );
  }

  /// Download a collections JSON from [url] and import it. Throws
  /// [FormatException] for a bad URL / response / document.
  Future<HomeCollectionImportResult> importFromUrl(
    String url, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) async {
    final session = captureSession();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('Enter an http(s) link to a JSON file.');
    }
    final client = _httpClientFactory();
    try {
      final bytes = await (() async {
        final response = await client.send(http.Request('GET', uri));
        if (response.statusCode != 200) {
          throw FormatException(
            'The server answered ${response.statusCode} for that link.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxImportBytes) {
            throw const FormatException(
              'That file is too large to be a collection.',
            );
          }
          bytes.addAll(chunk);
        }
        return bytes;
      })().timeout(_fetchTimeout);
      checkSession(session);
      return await importJson(
        utf8.decode(bytes),
        replaceExisting: replaceExisting,
        installedAddons: installedAddons,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Could not download that link: $e');
    } finally {
      client.close();
    }
  }

  // ── Backup / restore ───────────────────────────────────────────────────

  /// The store as a JSON-ready list (the backup payload's `homeCollections`).
  Future<List<Map<String, dynamic>>> exportJson() async => [
    for (final c in await getCollections()) c.toJson(),
  ];

  /// Restore a backup's `homeCollections` list, merging by id so a device
  /// that already holds some of them keeps the rest.
  Future<({int imported, int alreadyPresent, int failed})> applyBackup(
    List<dynamic> list,
  ) async {
    var failed = 0;
    final parsed = <HomeCollection>[];
    for (final raw in list) {
      final c = HomeCollection.fromJson(raw);
      if (c == null) {
        failed++;
      } else {
        parsed.add(c);
      }
    }
    if (parsed.isEmpty) return (imported: 0, alreadyPresent: 0, failed: failed);
    final result = await importCollections(parsed);
    return (
      imported: result.added.length,
      alreadyPresent: result.replaced.length,
      failed: failed,
    );
  }

  // ── Addon resolution ───────────────────────────────────────────────────

  /// The installed addon a source refers to: an exact manifest-id match, else
  /// any installed addon serving a catalog with the same `type` + `catalogId`.
  /// The fallback matters because the file was made against someone else's
  /// install, and the same addon deployed elsewhere can carry another id.
  static StremioAddon? resolveAddon(
    CollectionCatalogSource source,
    List<StremioAddon> installed,
  ) {
    for (final a in installed) {
      if (a.id == source.addonId && resolveCatalog(source, a) != null) return a;
    }
    for (final a in installed) {
      if (resolveCatalog(source, a) != null) {
        return a;
      }
    }
    return null;
  }

  /// The catalog of [addon] a source points at (type + id), or null.
  static StremioAddonCatalog? resolveCatalog(
    CollectionCatalogSource source,
    StremioAddon addon,
  ) {
    for (final c in addon.catalogs) {
      if (c.id == source.catalogId && c.type == source.type && c.isBrowsable) {
        return c;
      }
    }
    return null;
  }

  /// Home-row keys (`addonId:type:catalogId`) of every catalog an enabled
  /// collection folder resolves to. As in Nuvio, a list lives in its folder
  /// rather than in both places, so these are left off the Home board and
  /// out of the addon groups in the Home Rows manager.
  static Set<String> claimedCatalogKeys(
    List<HomeCollection> collections,
    List<StremioAddon> installed,
  ) {
    final out = <String>{};
    for (final c in collections) {
      if (!c.enabled) continue;
      for (final f in c.folders) {
        for (final s in f.sources) {
          final addon = resolveAddon(s, installed);
          if (addon == null) continue;
          final catalog = resolveCatalog(s, addon);
          if (catalog == null) continue;
          out.add('${addon.id}:${catalog.type}:${catalog.id}');
        }
      }
    }
    return out;
  }

  /// Addon ids referenced by [collections] that nothing in [installed] can
  /// serve, by id or by catalog match.
  static Set<String> unresolvedAddonIds(
    List<HomeCollection> collections,
    List<StremioAddon> installed,
  ) {
    final out = <String>{};
    for (final c in collections) {
      for (final f in c.folders) {
        for (final s in f.sources) {
          if (resolveAddon(s, installed) == null) out.add(s.addonId);
        }
      }
    }
    return out;
  }
}
