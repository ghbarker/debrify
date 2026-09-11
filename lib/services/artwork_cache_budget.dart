import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

/// A cancelled cache operation must never publish into a newer policy/clear.
class ArtworkCacheCancelled implements Exception {}

class ArtworkCacheLimit implements Exception {
  const ArtworkCacheLimit();
  @override
  String toString() => 'Artwork cache has no safe space for this file';
}

class ArtworkCacheToken {
  ArtworkCacheToken(this.generation, this.cancelled);
  final int generation;
  final Stream<int> cancelled;
}

class ArtworkCacheStore {
  ArtworkCacheStore(
    this.name,
    this.directory,
    this.repo,
    this.standardCapacity,
  );
  final String name;
  final Future<Directory> directory;
  final CacheInfoRepository repo;
  final int standardCapacity;
}

class _Entry {
  _Entry(this.path, this.store, this.bytes, this.touched);
  String path;
  final ArtworkCacheStore store;
  int bytes;
  DateTime touched;
  int readers = 0;
  bool writing = false;
  bool removed = false;
  String? key;
}

/// One payload-byte ledger for both stores, including unindexed/partial files.
/// Disk modification times persist LRU order without a second database.
class ArtworkCacheBudget {
  ArtworkCacheBudget({
    this.maxFileBytes = 32 * 1024 * 1024,
    this.handoffGrace = const Duration(seconds: 5),
    this.now = DateTime.now,
    this.beforeInventory,
  });

  final Future<void> Function()? beforeInventory;
  final int maxFileBytes;
  final Duration handoffGrace;
  final DateTime Function() now;
  final _lock = Lock();
  final _stores = <ArtworkCacheStore>[];
  final _entries = <String, _Entry>{};
  final _graces = <String, Timer>{};
  Future<void>? _initialization;
  bool _expanded = false;
  int _budget = 512 * 1024 * 1024;
  int _generation = 0;
  int _clearGeneration = 0;
  int get clearGeneration => _clearGeneration;
  final _cancelled = StreamController<int>.broadcast(sync: true);
  int _downloads = 0;
  final _waiters = <Completer<void>>[];

  bool get expanded => _expanded;
  int get budgetBytes => _budget;
  int get fileLimit =>
      _expanded && _budget < maxFileBytes ? _budget : maxFileBytes;
  ArtworkCacheToken token() =>
      ArtworkCacheToken(_generation, _cancelled.stream);
  void check(ArtworkCacheToken token) {
    if (token.generation != _generation) throw ArtworkCacheCancelled();
  }

  void register(ArtworkCacheStore store) {
    if (_initialization != null) throw StateError('Register stores before use');
    _stores.add(store);
  }

  Future<void> initialize() => _initialization ??= _inventory().catchError((
    Object error,
    StackTrace stack,
  ) {
    _initialization = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _inventory() async {
    await beforeInventory?.call();
    for (final store in _stores) {
      final dir = await store.directory;
      await dir.create(recursive: true);
      await store.repo.open();
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        final entry = _Entry(entity.path, store, stat.size, stat.modified);
        entry.removed = entity.path.endsWith('.part');
        _entries.putIfAbsent(entity.path, () => entry);
      }
      for (final object in await store.repo.getAllObjects()) {
        _entries[p.join(dir.path, object.relativePath)]?.key = object.key;
      }
    }
    await _lock.synchronized(_trim);
  }

  Future<bool> adopt(String path, ArtworkCacheStore store, String key) async {
    if (_entries.containsKey(path)) return available(path);
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) return false;
    _entries[path] = _Entry(path, store, stat.size, stat.modified)..key = key;
    return true;
  }

  void _invalidate() {
    _generation++;
    _cancelled.add(_generation);
  }

  void configure({required bool expanded, required int bytes}) {
    if (bytes <= 0) throw ArgumentError.value(bytes, 'bytes');
    if (_expanded != expanded || _budget != bytes) {
      _invalidate();
      _expanded = expanded;
      _budget = bytes;
    }
  }

  Future<void> apply({required bool expanded, required int bytes}) async {
    configure(expanded: expanded, bytes: bytes);
    await initialize();
    await _lock.synchronized(_trim);
  }

  /// Known payload bytes for frequent speculative-admission checks. Initial
  /// inventory is required; subsequent reads use the same ledger as write
  /// enforcement, including partial writes and files retained by live readers.
  /// This is not a reservation. External filesystem changes are reconciled by
  /// [sizeBytes]; a missing file can conservatively overcount until then.
  Future<int> admissionSizeBytes() async {
    await initialize();
    return _lock.synchronized(() => _total);
  }

  Future<int> sizeBytes() async {
    await initialize();
    return _lock.synchronized(() async {
      // Measure actual files, not HTTP Content-Length or database estimates.
      for (final entry in _entries.values.toList()) {
        final stat = await File(entry.path).stat();
        if (stat.type == FileSystemEntityType.notFound && !entry.writing) {
          _entries.remove(entry.path);
        } else {
          if (stat.type != FileSystemEntityType.notFound) {
            entry.bytes = stat.size;
          }
        }
      }
      return _total;
    });
  }

  int get _total => _entries.values.fold(0, (sum, entry) => sum + entry.bytes);
  bool _protected(_Entry entry) =>
      entry.writing || entry.readers > 0 || _graces.containsKey(entry.path);

  Future<void> clear([ArtworkCacheStore? only]) async {
    _clearGeneration++;
    _invalidate();
    await initialize();
    await _lock.synchronized(() async {
      for (final entry in _entries.values) {
        if (only == null || entry.store == only) entry.removed = true;
      }
      // Drop lookups now; active readers retain their immutable file until done.
      for (final store in _stores) {
        if (only != null && only != store) continue;
        final objects = await store.repo.getAllObjects();
        await store.repo.deleteAll(objects.map((e) => e.id).whereType<int>());
      }
      await _trim();
    });
  }

  Future<T> transaction<T>(Future<T> Function() action) =>
      _lock.synchronized(action);

  Future<void> begin(
    String path,
    String key,
    ArtworkCacheStore store,
    ArtworkCacheToken token,
  ) => _lock.synchronized(() async {
    check(token);
    final entry = _Entry(path, store, 0, now())
      ..writing = true
      ..key = key;
    _entries[path] = entry;
  });

  Future<void> write(
    String path,
    RandomAccessFile file,
    List<int> chunk,
    ArtworkCacheToken token,
  ) => _lock.synchronized(() async {
    check(token);
    final entry = _entries[path]!;
    if (entry.bytes + chunk.length > fileLimit) throw const ArtworkCacheLimit();
    await _trim(requiredBytes: chunk.length);
    check(token);
    if (_expanded && _total + chunk.length > _budget) {
      throw const ArtworkCacheLimit();
    }
    try {
      await file.writeFrom(chunk);
      entry.bytes += chunk.length;
    } catch (_) {
      // A failed OS write may have persisted a prefix before reporting ENOSPC.
      entry.bytes = await file.length();
      rethrow;
    }
  });

  /// Called inside transaction after closing the write handle.
  Future<void> publish(
    String temporary,
    String path,
    ArtworkCacheToken token,
    Future<void> Function() saveMetadata,
  ) async {
    check(token);
    final entry = _entries[temporary]!;
    await File(temporary).rename(path);
    _entries.remove(temporary);
    entry.path = path;
    _entries[path] = entry;
    try {
      await saveMetadata();
      check(token);
      entry.writing = false;
      await touch(path);
      handoff(path);
      await _trim();
    } catch (_) {
      entry.writing = false;
      entry.removed = true;
      await _trim();
      rethrow;
    }
  }

  Future<void> abandon(String path) => _lock.synchronized(() async {
    final entry = _entries[path];
    if (entry == null) return;
    entry.writing = false;
    entry.removed = true;
    await _trim();
  });

  /// Called under transaction before returning an image file to its decoder.
  bool available(String path) => _entries[path]?.removed == false;
  void retire(String path) {
    _entries[path]?.removed = true;
  }

  Future<void> touch(String path) async {
    final entry = _entries[path];
    if (entry == null) return;
    entry.touched = now();
    await File(path).setLastModified(entry.touched);
  }

  void handoff(String path) {
    _graces.remove(path)?.cancel();
    _graces[path] = Timer(handoffGrace, () {
      _graces.remove(path);
      unawaited(_lock.synchronized(_trim).catchError((Object _) {}));
    });
  }

  void finishHandoff(String path) {
    _graces.remove(path)?.cancel();
  }

  /// Synchronous pin precedes any asynchronous file read/open.
  void Function() pin(String path) {
    final entry = _entries[path];
    if (entry == null) throw FileSystemException('Artwork was evicted', path);
    entry.readers++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      entry.readers--;
      unawaited(_lock.synchronized(_trim).catchError((Object _) {}));
    };
  }

  Future<void> remove(String path) => _lock.synchronized(() async {
    final entry = _entries[path];
    if (entry != null) entry.removed = true;
    await _trim();
  });

  Future<void> _delete(_Entry entry) async {
    try {
      await File(entry.path).delete();
    } on PathNotFoundException {
      /* Already reclaimed by the OS. */
    }
    _entries.remove(entry.path);
    final dir = await entry.store.directory;
    final object = entry.key == null
        ? null
        : await entry.store.repo.get(entry.key!);
    if (object != null &&
        p.join(dir.path, object.relativePath) == entry.path &&
        object.id != null) {
      await entry.store.repo.delete(object.id!);
    }
  }

  Future<void> _trim({int requiredBytes = 0}) async {
    var total = _total;
    if (requiredBytes > 0 && (!_expanded || total + requiredBytes <= _budget)) {
      return;
    }
    final ordered = _entries.values.toList()
      ..sort((a, b) => a.touched.compareTo(b.touched));
    final counts = <ArtworkCacheStore, int>{};
    for (final e in ordered) {
      counts.update(e.store, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final entry in ordered) {
      final capacity = _expanded ? 20000 : entry.store.standardCapacity;
      final expired =
          now().difference(entry.touched) > const Duration(days: 30);
      if (!entry.removed &&
          !expired &&
          counts[entry.store]! <= capacity &&
          (!_expanded || total + requiredBytes <= _budget)) {
        continue;
      }
      if (_protected(entry)) continue;
      await _delete(entry);
      total -= entry.bytes;
      counts[entry.store] = counts[entry.store]! - 1;
    }
  }

  Future<T> downloadSlot<T>(
    ArtworkCacheToken token,
    Future<T> Function() run,
  ) async {
    while (_downloads >= 4) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await untilCancelled(waiter.future, token, const Duration(minutes: 1));
      } finally {
        _waiters.remove(waiter);
      }
      check(token);
    }
    check(token);
    _downloads++;
    try {
      return await run();
    } finally {
      _downloads--;
      for (final waiter in _waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  Future<T> untilCancelled<T>(
    Future<T> action,
    ArtworkCacheToken token,
    Duration timeout,
  ) async {
    final cancelled = Completer<T>();
    final subscription = token.cancelled.listen((_) {
      if (!cancelled.isCompleted) {
        cancelled.completeError(ArtworkCacheCancelled());
      }
    });
    if (token.generation != _generation) {
      cancelled.completeError(ArtworkCacheCancelled());
    }
    try {
      return await Future.any([action.timeout(timeout), cancelled.future]);
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> dispose() async {
    _invalidate();
    for (final timer in _graces.values) {
      timer.cancel();
    }
    _graces.clear();
  }
}
