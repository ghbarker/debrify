import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:debrify/services/artwork_cache_budget.dart';
import 'package:debrify/services/artwork_cache_file.dart';
import 'package:debrify/services/artwork_cache_manager.dart';
import 'package:debrify/services/artwork_cache_repository.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class MeasuredRepository extends JsonCacheInfoRepository {
  MeasuredRepository({required super.path});
  int reads = 0;
  Future<void> Function()? afterRead;
  Future<void> Function()? beforeUpdate;
  bool failAfterUpdate = false;

  @override
  Future<CacheObject?> get(String key) async {
    reads++;
    final object = await super.get(key);
    await afterRead?.call();
    return object;
  }

  @override
  Future<int> update(CacheObject object, {bool setTouchedToNow = true}) async {
    await beforeUpdate?.call();
    final result = await super.update(object, setTouchedToNow: setTouchedToNow);
    if (failAfterUpdate) throw StateError('synthetic committed write failure');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory root;
  late ArtworkCacheBudget budget;
  late ArtworkCacheManager manager;
  late MeasuredRepository delegate;
  final held = <ArtworkCacheFile>[];
  var now = DateTime(2026);
  ArtworkCacheRepository getRepository() =>
      manager.config.repo as ArtworkCacheRepository;

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp('artwork-warm-test-');
    budget = ArtworkCacheBudget(handoffGrace: Duration.zero, now: () => now);
    delegate = MeasuredRepository(path: p.join(root.path, 'index.json'));
    manager = ArtworkCacheManager(
      cacheKey: 'warm',
      budget: budget,
      standardCapacity: 1000,
      directory: io.Directory(p.join(root.path, 'payload')),
      repository: delegate,
    );
  });
  tearDown(() async {
    for (final file in held) {
      file.release();
    }
    held.clear();
    await budget.dispose();
    await manager.dispose();
    await root.delete(recursive: true);
  });

  Future<ArtworkCacheFile> put(String key, [int value = 1]) async {
    now = now.add(const Duration(seconds: 1));
    final file = await manager.putFile(key, Uint8List.fromList([value, value]));
    held.add(file as ArtworkCacheFile);
    return file;
  }

  Future<FileInfo?> lookup(String key, {bool fresh = false}) async {
    final info = await manager.getFileFromCache(key, ignoreMemCache: fresh);
    if (info != null) held.add(info.file as ArtworkCacheFile);
    return info;
  }

  test(
    '40 warm lookups finish while all repository reads are blocked',
    () async {
      await put('poster');
      await lookup('poster');
      delegate.reads = 0;
      final resume = Completer<void>();
      delegate.afterRead = () => resume.future;
      final pending = Future.wait(List.generate(40, (_) => lookup('poster')));
      try {
        final result = await pending.timeout(const Duration(seconds: 3));
        expect(result.every((info) => info != null), isTrue);
        expect(delegate.reads, 0);
        expect(identical(result.first!.file, result.last!.file), isFalse);
      } finally {
        resume.complete();
        await pending;
      }
    },
  );

  test(
    'concurrent first lookups read metadata once and retain separate leases',
    () async {
      await put('poster');
      delegate.reads = 0;
      final results = await Future.wait(
        List.generate(20, (_) => lookup('poster')),
      );
      expect(delegate.reads, 1);
      expect(await results.first!.file.readAsBytes(), [1, 1]);
      await manager.emptyCache();
      expect(await lookup('poster'), isNull);
      expect(await results.last!.file.readAsBytes(), [1, 1]);
      for (final file in held) {
        file.release();
      }
      await budget.apply(expanded: false, bytes: budget.budgetBytes);
      expect(await budget.sizeBytes(), 0);
    },
  );

  test(
    'memory API avoids storage and ignoreMemCache forces an authoritative read',
    () async {
      await put('poster');
      await lookup('poster');
      delegate.reads = 0;
      final memory = await manager.getFileFromMemory('poster');
      held.add(memory!.file as ArtworkCacheFile);
      expect(delegate.reads, 0);
      expect(await lookup('poster', fresh: true), isNotNull);
      expect(delegate.reads, 1);
      await lookup('poster');
      expect(delegate.reads, 1);
    },
  );

  for (final truncate in [true, false]) {
    test(
      'warm metadata still rejects a ${truncate ? 'truncated' : 'deleted'} file',
      () async {
        final file = await put('poster');
        await lookup('poster');
        if (truncate) {
          await io.File(file.path).writeAsBytes([1]);
        } else {
          await io.File(file.path).delete();
        }
        expect(await lookup('poster'), isNull);
        expect(await getRepository().get('poster'), isNull);
      },
    );
  }

  test(
    'replacement invalidates its key while unrelated warm metadata stays hot',
    () async {
      final original = await put('poster');
      await put('other');
      await lookup('poster');
      await lookup('other');
      await put('poster', 9);
      delegate.reads = 0;
      expect(await (await lookup('poster'))!.file.readAsBytes(), [9, 9]);
      expect(delegate.reads, 1);
      await lookup('other');
      expect(delegate.reads, 1);
      expect(await original.readAsBytes(), [1, 1]);
    },
  );

  test(
    'budget shrink evicts warm metadata together with its physical payload',
    () async {
      (await put('older')).release();
      await lookup('older');
      for (final file in held) {
        file.release();
      }
      (await put('newer')).release();
      await lookup('newer');
      for (final file in held) {
        file.release();
      }
      await budget.apply(expanded: true, bytes: 2);
      expect(await lookup('older'), isNull);
      expect(await (await lookup('newer'))!.file.readAsBytes(), [1, 1]);
      expect(await budget.sizeBytes(), 2);
    },
  );

  test(
    'late metadata read cannot repopulate the cache after a replacement',
    () async {
      await put('poster');
      final repo = getRepository();
      final object = (await repo.get('poster'))!;
      final entered = Completer<void>();
      final resume = Completer<void>();
      delegate.afterRead = () {
        if (!entered.isCompleted) entered.complete();
        return resume.future;
      };
      final old = repo.getCached('poster');
      try {
        await entered.future;
        await repo.update(object.copyWith(relativePath: 'new-path'));
      } finally {
        delegate.afterRead = null;
        resume.complete();
      }
      expect((await old)!.relativePath, object.relativePath);
      expect((await repo.getCached('poster'))!.relativePath, 'new-path');
    },
  );

  test(
    'a read during a failed write cannot leave pre-write metadata cached',
    () async {
      await put('poster');
      await lookup('poster');
      final repo = getRepository();
      final object = (await repo.get('poster'))!;
      final entered = Completer<void>();
      final resume = Completer<void>();
      delegate.beforeUpdate = () {
        entered.complete();
        return resume.future;
      };
      delegate.failAfterUpdate = true;
      final writing = repo
          .update(object.copyWith(relativePath: 'committed-path'))
          .then<Object>((value) => value, onError: (Object error) => error);
      try {
        await entered.future;
        expect(
          (await repo.getCached('poster'))!.relativePath,
          object.relativePath,
        );
      } finally {
        resume.complete();
      }
      expect(await writing, isA<StateError>());
      expect((await repo.getCached('poster'))!.relativePath, 'committed-path');
    },
  );

  test('metadata LRU is bounded and misses are not remembered', () async {
    final raw = MeasuredRepository(path: p.join(root.path, 'bounded.json'));
    final repo = ArtworkCacheRepository(raw, memoryCapacity: 2);
    try {
      for (final key in ['one', 'two', 'three']) {
        await repo.insert(
          CacheObject(
            key,
            relativePath: key,
            validTill: DateTime.now().add(const Duration(days: 1)),
          ),
        );
      }
      await repo.getCached('one');
      await repo.getCached('two');
      await repo.getCached('one');
      await repo.getCached('three');
      raw.reads = 0;
      await repo.getCached('one');
      expect(raw.reads, 0);
      await repo.getCached('two');
      expect(raw.reads, 1);
      await repo.getCached('missing');
      await repo.getCached('missing');
      expect(raw.reads, 3);
    } finally {
      await repo.close();
    }
  });
}
