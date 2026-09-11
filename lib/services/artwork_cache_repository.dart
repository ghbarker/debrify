import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The manager and byte controller share one open public repository connection.
class ArtworkCacheRepository extends CacheInfoRepository {
  ArtworkCacheRepository(this.delegate);
  final CacheInfoRepository delegate;
  Future<bool>? _opening;
  @override
  Future<bool> open() => _opening ??= delegate.open();
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<bool> close() async {
    await open();
    return delegate.close();
  }

  @override
  Future<void> deleteDataFile() => delegate.deleteDataFile();
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
    await open();
    return delegate.updateOrInsert(object);
  }

  @override
  Future<CacheObject> insert(
    CacheObject object, {
    bool setTouchedToNow = true,
  }) async {
    await open();
    return delegate.insert(object, setTouchedToNow: setTouchedToNow);
  }

  @override
  Future<int> update(CacheObject object, {bool setTouchedToNow = true}) async {
    await open();
    return delegate.update(object, setTouchedToNow: setTouchedToNow);
  }

  @override
  Future<int> delete(int id) async {
    await open();
    return delegate.delete(id);
  }

  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    await open();
    return delegate.deleteAll(ids);
  }

  // Byte-controller cleanup owns deletion, including open-reader protection.
  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async => [];
  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async => [];
}
