import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:debrify/services/artwork_cache_budget.dart';
import 'package:debrify/services/artwork_cache_file.dart';
import 'package:debrify/services/artwork_cache_manager.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'artwork_cache_test.dart' show Response, Service;

class _PausedReadRepository extends JsonCacheInfoRepository {
  _PausedReadRepository({required super.path});

  bool pauseNextRead = false;
  final entered = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<CacheObject?> get(String key) async {
    final value = await super.get(key);
    if (pauseNextRead) {
      pauseNextRead = false;
      entered.complete();
      await resume.future;
    }
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory root;
  late ArtworkCacheBudget budget;
  late ArtworkCacheManager manager;
  late _PausedReadRepository repo;
  final held = <ArtworkCacheFile>[];

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp('artwork-authority-');
    budget = ArtworkCacheBudget(handoffGrace: Duration.zero);
    repo = _PausedReadRepository(path: p.join(root.path, 'index.json'));
  });
  tearDown(() async {
    if (!repo.resume.isCompleted) repo.resume.complete();
    for (final file in held) {
      file.release();
    }
    held.clear();
    await budget.dispose();
    await manager.dispose();
    await root.delete(recursive: true);
  });

  void setup(Future<FileServiceResponse> Function(String) respond) {
    manager = ArtworkCacheManager(
      cacheKey: 'authority',
      budget: budget,
      standardCapacity: 1000,
      directory: io.Directory(p.join(root.path, 'payload')),
      repository: repo,
      fileService: Service(respond),
    );
  }

  Future<Object> observe(Future<FileInfo> future) =>
      future.then<Object>((value) {
        held.add(value.file as ArtworkCacheFile);
        return value;
      }, onError: (Object error) => error);

  Future<void> seed() async {
    final file = await manager.putFile('same', Uint8List.fromList([1, 1]));
    (file as ArtworkCacheFile).release();
  }

  for (final clear in [true, false]) {
    test(
      '304 read rejects ${clear ? 'clear' : 'policy change'} during repository await',
      () async {
        final response = Completer<FileServiceResponse>();
        final requested = Completer<void>();
        setup((_) {
          requested.complete();
          return response.future;
        });
        await seed();
        final outcome = observe(manager.downloadFile('same'));
        await requested.future;
        repo.pauseNextRead = true;
        response.complete(Response(const Stream.empty(), statusCode: 304));
        await repo.entered.future;
        final applying = clear
            ? budget.clear()
            : budget.apply(expanded: true, bytes: 1024);
        repo.resume.complete();
        final result = await outcome;
        await applying;
        expect(result, isA<ArtworkCacheCancelled>());
      },
    );
  }

  test(
    'superseded 304 returns the newer forced payload after repository await',
    () async {
      final first = Completer<FileServiceResponse>();
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();
      var calls = 0;
      setup((_) {
        if (++calls == 1) {
          firstEntered.complete();
          return first.future;
        }
        secondEntered.complete();
        return Future.value(Response(Stream.value([9, 9]), contentLength: 2));
      });
      await seed();
      final old = observe(manager.downloadFile('same', force: true));
      await firstEntered.future;
      repo.pauseNextRead = true;
      first.complete(Response(const Stream.empty(), statusCode: 304));
      await repo.entered.future;
      final fresh = observe(manager.downloadFile('same', force: true));
      await secondEntered.future;
      repo.resume.complete();
      final oldResult = await old;
      final freshResult = await fresh;
      expect(freshResult, isA<FileInfo>());
      expect(oldResult, isA<FileInfo>());
      expect(await (oldResult as FileInfo).file.readAsBytes(), [9, 9]);
    },
  );

  test('existing joined download follows the newer forced writer too', () async {
    final first = Completer<FileServiceResponse>();
    final firstEntered = Completer<void>();
    final secondEntered = Completer<void>();
    var calls = 0;
    setup((_) {
      if (++calls == 1) {
        firstEntered.complete();
        return first.future;
      }
      secondEntered.complete();
      return Future.value(Response(Stream.value([9, 9]), contentLength: 2));
    });
    final old = observe(manager.downloadFile('same'));
    await firstEntered.future;
    final joined = observe(manager.downloadFile('same'));
    // Drain the ready-policy continuation so this consumer joins the held HTTP.
    await Future<void>(() {});
    expect(calls, 1);
    final fresh = observe(manager.downloadFile('same', force: true));
    await secondEntered.future;
    await fresh;
    first.complete(Response(Stream.value([1, 1]), contentLength: 2));
    final oldResult = await old;
    final joinedResult = await joined;
    expect(oldResult, isA<FileInfo>());
    expect(await (oldResult as FileInfo).file.readAsBytes(), [9, 9]);
    expect(joinedResult, isA<FileInfo>());
    expect(await (joinedResult as FileInfo).file.readAsBytes(), [9, 9]);
  });

  test('remove retires an earlier download for that same cache key', () async {
    final response = Completer<FileServiceResponse>();
    final entered = Completer<void>();
    setup((_) {
      entered.complete();
      return response.future;
    });
    await seed();
    final outcome = observe(manager.downloadFile('same', force: true));
    await entered.future;
    await manager.removeFile('same');
    response.complete(Response(Stream.value([9, 9]), contentLength: 2));
    final result = await outcome;
    final cached = await manager.getFileFromCache('same');
    if (cached != null) held.add(cached.file as ArtworkCacheFile);
    expect(result, isA<ArtworkCacheCancelled>());
    expect(cached, isNull);
    expect(await budget.sizeBytes(), 0);
  });
}
