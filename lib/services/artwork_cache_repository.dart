import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The manager and byte controller share one open public repository connection.
class ArtworkCacheRepository extends CacheInfoRepository {
  ArtworkCacheRepository(this.delegate, {this.memoryCapacity = 256})
    : assert(memoryCapacity > 0);
  final CacheInfoRepository delegate;
  final int memoryCapacity;
  final _cached = <String, CacheObject>{};
  int _revision = 0;
  Future<bool>? _opening;
  @override
  Future<bool> open() => _opening ??= delegate.open();
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<bool> close() async {
    return _mutate(_forgetAll, delegate.close);
  }

  @override
  Future<void> deleteDataFile() async {
    _forgetAll();
    try {
      await delegate.deleteDataFile();
    } finally {
      _forgetAll();
    }
  }

  // Writer/304 authority checks continue to use get(), which always reads the
  // repository. Only ordinary file lookups opt into the bounded metadata cache.
  Future<CacheObject?> getCached(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    if (ignoreMemCache) {
      _forget(key: key);
    } else {
      final cached = _cached.remove(key);
      if (cached != null) {
        _cached[key] = cached;
        return cached;
      }
    }
    final revision = _revision;
    final object = await get(key);
    // A lookup completing after a mutation must not restore stale metadata.
    if (object != null && revision == _revision) {
      _cached.remove(key);
      _cached[key] = object;
      if (_cached.length > memoryCapacity) _cached.remove(_cached.keys.first);
    }
    return object;
  }

  void _forgetAll() {
    _revision++;
    _cached.clear();
  }

  void _forget({String? key, int? id, Set<int>? ids}) {
    _revision++;
    _cached.removeWhere(
      (cachedKey, object) =>
          cachedKey == key ||
          (id != null && object.id == id) ||
          (ids != null && ids.contains(object.id)),
    );
  }

  Future<T> _mutate<T>(
    void Function() invalidate,
    Future<T> Function() action,
  ) async {
    await open();
    invalidate();
    try {
      return await action();
    } finally {
      // Also remove reads started during the mutation, including failed writes.
      invalidate();
    }
  }

  @override
  Future<CacheObject?> get(String key) async {
    await open();
    return delegate.get(key);
  }

  @override
  Future<List<CacheObject>> getAllObjects() async {
    await open();
    return delegate.getAllObjects();
  }

  @override
  Future<dynamic> updateOrInsert(CacheObject object) async {
    return _mutate(
      () => _forget(key: object.key, id: object.id),
      () => delegate.updateOrInsert(object),
    );
  }

  @override
  Future<CacheObject> insert(
    CacheObject object, {
    bool setTouchedToNow = true,
  }) async {
    return _mutate(
      () => _forget(key: object.key, id: object.id),
      () => delegate.insert(object, setTouchedToNow: setTouchedToNow),
    );
  }

  @override
  Future<int> update(CacheObject object, {bool setTouchedToNow = true}) async {
    return _mutate(
      () => _forget(key: object.key, id: object.id),
      () => delegate.update(object, setTouchedToNow: setTouchedToNow),
    );
  }

  @override
  Future<int> delete(int id) async {
    return _mutate(() => _forget(id: id), () => delegate.delete(id));
  }

  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    final selected = ids.toSet();
    return _mutate(
      () => _forget(ids: selected),
      () => delegate.deleteAll(selected),
    );
  }

  // Byte-controller cleanup owns deletion, including open-reader protection.
  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async => [];
  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async => [];
}
