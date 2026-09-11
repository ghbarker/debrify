import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import '../models/stremio_addon.dart';
import 'browsing_cache_preferences.dart';
import 'metadata_preferences_service.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';

/// A request's persistent identity excludes session epoch; its publication
/// authority includes it. Neither URLs nor addon credentials become filenames.
class CatalogCacheRequest {
  CatalogCacheRequest._(this.key, this.scope, this.revision, this.enabled);
  final String key;
  final ProfileScope? scope;
  final int revision;
  final bool enabled;
  String get memoryKey => '$key:${scope?.sessionEpoch}:$revision';
}

class CatalogDiskPage {
  const CatalogDiskPage(this.items, this.rawCount, this.fetchedAt);
  final List<StremioMeta> items;
  final int rawCount;
  final DateTime fetchedAt;
}

/// Rebuildable, profile-generation-scoped catalog pages, with one installation
/// budget. Only this directory is enumerated/evicted, never other app caches.
class CatalogDiskCache {
  CatalogDiskCache._() {
    ProfileRuntime.scope.addListener(invalidateRequests);
    MetadataPreferencesService.revision.addListener(invalidateRequests);
    BrowsingCachePreferences.notifier.addListener(_optionsChanged);
  }
  static final instance = CatalogDiskCache._();
  static const maxAge = Duration(hours: 24);
  static const _maxPageBytes = 4 * 1024 * 1024;
  final _lock = Lock();
  int _revision = 0;
  int _authority = 0;
  int _serial = 0;
  bool _rememberTitles = BrowsingCachePreferences.current.rememberTitles;
  int _budgetBytes = BrowsingCachePreferences.current.titleBudgetBytes;

  @visibleForTesting
  Future<void> Function(File file, List<int> bytes)? debugWriteTemporary;
  @visibleForTesting
  Future<String> Function(File file)? debugRead;
  @visibleForTesting
  Directory? debugTemporaryDirectory;

  void _optionsChanged() {
    final options = BrowsingCachePreferences.current;
    if (_rememberTitles == options.rememberTitles &&
        _budgetBytes == options.titleBudgetBytes) {
      return;
    }
    _rememberTitles = options.rememberTitles;
    _budgetBytes = options.titleBudgetBytes;
    _revision++;
    unawaited(
      _lock.synchronized(() async {
        try {
          final entries = <({File file, FileStat stat})>[];
          var bytes = 0;
          for (final file in await _files(await _root())) {
            // A .part outside a write's lock is an interrupted prior write.
            if (file.path.endsWith('.part')) {
              await file.delete();
              continue;
            }
            final stat = await file.stat();
            entries.add((file: file, stat: stat));
            bytes += stat.size;
          }
          entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
          for (final entry in entries) {
            if (bytes <= BrowsingCachePreferences.current.titleBudgetBytes) {
              break;
            }
            await entry.file.delete();
            bytes -= entry.stat.size;
          }
        } catch (_) {
          /* Storage maintenance never blocks browsing. */
        }
      }),
    );
  }

  /// Also called by the catalog owner when installed addon configuration changes.
  void invalidateRequests() {
    _revision++;
    _authority++;
  }

  bool isCurrent(CatalogCacheRequest request) =>
      request.revision == _revision &&
      request.scope == ProfileRuntime.scope.value &&
      !ProfileRuntime.isInMaintenance;

  bool _enabled(CatalogCacheRequest request) =>
      request.enabled &&
      request.scope != null &&
      isCurrent(request) &&
      BrowsingCachePreferences.current.rememberTitles;

  Future<CatalogCacheRequest> request(
    String url,
    StremioAddon addon,
    StremioAddonCatalog catalog,
  ) async {
    final scope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    // Preference initialization itself publishes a revision. Capture it after
    // initialization, but never adopt a different profile after that await.
    final before = _authority;
    await BrowsingCachePreferences.initialize();
    final revision = _revision;
    var enabled = BrowsingCachePreferences.current.rememberTitles;
    Object? policy;
    if (enabled && scope != null && scope == ProfileRuntime.scope.value) {
      try {
        policy = (await MetadataPreferencesService.load()).toJson();
      } catch (_) {
        // A cache-policy read failure must not block the ordinary network path.
        enabled = false;
      }
    }
    final config = addon.toJson()
      ..remove('added_at')
      ..remove('last_checked');
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              _canonical({
                'url': url,
                'addon': config,
                'catalog': catalog.toJson(),
                'profile': scope?.profileId,
                'generation': scope?.dataGeneration,
                'metadata': policy,
              }),
            ),
          ),
        )
        .toString();
    return CatalogCacheRequest._(
      key,
      scope,
      before == _authority ? revision : -1,
      enabled,
    );
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  // Outside profile generation trees: restore staging and durable manifests
  // must never copy these disposable pages, even when temp and cache coincide.
  Future<Directory> _root() async => Directory(
    p.join(
      (debugTemporaryDirectory ?? await getTemporaryDirectory()).path,
      'catalog-titles-v1',
    ),
  );

  File _file(Directory root, CatalogCacheRequest request) => File(
    p.join(
      root.path,
      sha256.convert(utf8.encode(request.scope!.profileId)).toString(),
      '${request.scope!.dataGeneration}',
      '${request.key}.json',
    ),
  );

  Future<List<File>> _files(Directory root) async {
    if (!await root.exists()) return [];
    return root
        .list(recursive: true, followLinks: false)
        .where((entry) => entry is File && p.isWithin(root.path, entry.path))
        .cast<File>()
        .toList();
  }

  Future<CatalogDiskPage?> read(
    CatalogCacheRequest request,
    StremioAddon addon,
  ) async {
    if (!_enabled(request)) return null;
    try {
      return await _lock.synchronized(() async {
        if (!_enabled(request)) return null;
        final file = _file(await _root(), request);
        if (!await file.exists()) return null;
        try {
          if (await file.length() > _maxPageBytes) {
            throw const FormatException();
          }
          final json =
              jsonDecode(await (debugRead?.call(file) ?? file.readAsString()))
                  as Map<String, dynamic>;
          final at = DateTime.fromMillisecondsSinceEpoch(
            json['fetchedAt'] as int,
          );
          final age = DateTime.now().difference(at);
          if (json['version'] != 1 ||
              json['key'] != request.key ||
              age.isNegative ||
              age > maxAge) {
            throw const FormatException();
          }
          final raw = json['rawCount'] as int;
          final rows = json['items'] as List;
          if (raw < rows.length || raw < 0) throw const FormatException();
          final items = <StremioMeta>[];
          for (final row in rows) {
            final data = row as Map<String, dynamic>;
            if (data.keys.any((key) => !_fields.contains(key)) ||
                data['id'] is! String ||
                data['type'] is! String ||
                data['name'] is! String) {
              throw const FormatException();
            }
            final parsed = StremioMeta.fromJson(data);
            final item = StremioMeta(
              id: parsed.id,
              imdbId: parsed.imdbId,
              type: parsed.type,
              name: parsed.name,
              poster: parsed.poster,
              background: parsed.background,
              description: parsed.description,
              year: parsed.year,
              imdbRating: parsed.imdbRating,
              genres: parsed.genres,
              runtime: parsed.runtime,
              logo: parsed.logo,
              trailerYtId: parsed.trailerYtId,
              addedAtMs: data['addedAtMs'] as int?,
            );
            if (!item.hasValidId) throw const FormatException();
            items.add(item.withSourceAddon(addon));
          }
          if (!_enabled(request)) return null;
          await file.setLastModified(DateTime.now());
          return _enabled(request) ? CatalogDiskPage(items, raw, at) : null;
        } catch (_) {
          if (await file.exists()) await file.delete();
          return null;
        }
      });
    } catch (_) {
      return null;
    }
  }

  static const _fields = {
    'id',
    'imdb_id',
    'type',
    'name',
    'poster',
    'background',
    'description',
    'year',
    'rating',
    'genres',
    'runtime',
    'logo',
    'trailer_yt_id',
    'addedAtMs',
  };

  static Map<String, dynamic> _encode(StremioMeta item) => {
    'id': item.id,
    'type': item.type,
    'name': item.name,
    if (item.imdbId != null) 'imdb_id': item.imdbId,
    if (item.poster != null) 'poster': item.poster,
    if (item.background != null) 'background': item.background,
    if (item.description != null) 'description': item.description,
    if (item.year != null) 'year': item.year,
    if (item.imdbRating != null) 'rating': item.imdbRating,
    if (item.genres != null) 'genres': item.genres,
    if (item.runtime != null) 'runtime': item.runtime,
    if (item.logo != null) 'logo': item.logo,
    if (item.trailerYtId != null) 'trailer_yt_id': item.trailerYtId,
    if (item.addedAtMs != null) 'addedAtMs': item.addedAtMs,
  };

  Future<void> write(
    CatalogCacheRequest request,
    StremioAddon addon,
    List<StremioMeta> items,
    int rawCount, {
    bool Function()? stillCurrent,
  }) async {
    bool allowed() => _enabled(request) && (stillCurrent?.call() ?? true);
    if (!allowed()) return;
    // Foreign embedded source manifests cannot safely be reconstructed from
    // the request's addon. Skip that page instead of changing playback routing.
    if (items.any(
      (m) =>
          m.sourceAddon != null &&
          m.sourceAddon!.manifestUrl != addon.manifestUrl,
    )) {
      return;
    }
    try {
      final bytes = utf8.encode(
        jsonEncode({
          'version': 1,
          'key': request.key,
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
          'rawCount': rawCount,
          'items': items.map(_encode).toList(),
        }),
      );
      if (bytes.length > _maxPageBytes) return;
      await _lock.synchronized(() async {
        if (!allowed()) return;
        final root = await _root();
        final target = _file(root, request);
        final budget = BrowsingCachePreferences.current.titleBudgetBytes;
        // Reserve actual temporary-file bytes too; never double the disk budget
        // while atomically replacing an existing page.
        final files = await _files(root);
        final entries = <({File file, FileStat stat})>[];
        var size = 0;
        for (final file in files) {
          final stat = await file.stat();
          size += stat.size;
          entries.add((file: file, stat: stat));
        }
        entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
        for (final entry in entries) {
          if (size + bytes.length <= budget) break;
          if (p.equals(entry.file.path, target.path)) continue;
          if (!allowed()) return;
          await entry.file.delete();
          size -= entry.stat.size;
        }
        if (size + bytes.length > budget || !allowed()) return;
        await target.parent.create(recursive: true);
        final temporary = File('${target.path}.${_serial++}.part');
        try {
          if (debugWriteTemporary != null) {
            await debugWriteTemporary!(temporary, bytes);
          } else {
            await temporary.writeAsBytes(bytes, flush: true);
          }
          if (!allowed()) return;
          await temporary.rename(target.path);
          // Clear/profile changes can run during the rename's await.
          if (!allowed() && await target.exists()) await target.delete();
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      });
    } catch (_) {
      // Corruption, permissions, OS eviction and ENOSPC are cache misses, not
      // catalog failures. No request URL, credentials or title data is logged.
    }
  }

  /// Retires in-flight readers/writers synchronously, then removes only our store.
  Future<void> clear() {
    invalidateRequests();
    return _lock.synchronized(() async {
      try {
        final root = await _root();
        for (final file in await _files(root)) {
          await file.delete();
        }
      } catch (_) {
        /* Best effort when storage is unavailable. */
      }
    });
  }

  /// Measured bytes across all cached profile generations, including temp files.
  Future<int> sizeBytes() => _lock.synchronized(() async {
    try {
      var size = 0;
      for (final file in await _files(await _root())) {
        size += await file.length();
      }
      return size;
    } catch (_) {
      return 0;
    }
  });
}
