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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory root;
  late ArtworkCacheBudget budget;
  late ArtworkCacheManager manager;
  final held = <ArtworkCacheFile>[];

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp('artwork-review-');
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
  void setup({Future<void> Function()? inventory, FileService? service}) {
    budget = ArtworkCacheBudget(
      handoffGrace: Duration.zero,
      beforeInventory: inventory,
    );
    manager = ArtworkCacheManager(
      cacheKey: 'review',
      budget: budget,
      standardCapacity: 1000,
      directory: io.Directory(p.join(root.path, 'payload')),
      repository: JsonCacheInfoRepository(path: p.join(root.path, 'index.json')),
      fileService: service,
    );
  }
  void hold(io.File file) => held.add(file as ArtworkCacheFile);

  test('cold first image starts HTTP before full-store inventory completes', () async {
    final resume = Completer<void>();
    final entered = Completer<void>();
    setup(
      inventory: () => resume.future,
      service: Service((_) async {
        entered.complete();
        return Response(Stream.value([1, 2, 3]), contentLength: 3);
      }),
    );
    final pending = manager.getSingleFile('first');
    try {
      await entered.future.timeout(const Duration(milliseconds: 300));
    } finally {
      resume.complete();
      hold(await pending);
    }
  });

  test('truncated indexed file is a cache miss instead of a corrupt hit', () async {
    setup();
    final file = await manager.putFile('image', Uint8List.fromList([1, 2, 3, 4]));
    hold(file);
    // Simulate a file damaged after publication; metadata still records 4 bytes.
    await io.File(file.path).writeAsBytes([1]);
    final cached = await manager.getFileFromCache('image');
    if (cached != null) hold(cached.file);
    expect(cached, isNull);
  });

  test('clear cancels a download already waiting for inventory', () async {
    final inventoryEntered = Completer<void>();
    final resume = Completer<void>();
    setup(
      inventory: () {
        inventoryEntered.complete();
        return resume.future;
      },
      service: Service((_) async => Response(Stream.value([1, 2]), contentLength: 2)),
    );
    final pending = manager.downloadFile('before-clear');
    final outcome = pending.then<Object>((value) {
      hold(value.file);
      return value;
    }, onError: (Object error) => error);
    await inventoryEntered.future;
    final clearing = budget.clear();
    resume.complete();
    await clearing;
    expect(await outcome, isA<ArtworkCacheCancelled>());
    expect(await budget.sizeBytes(), 0);
  });

  test('older forced response cannot overwrite a newer forced response', () async {
    final first = Completer<FileServiceResponse>();
    final second = Completer<FileServiceResponse>();
    final firstEntered = Completer<void>();
    final secondEntered = Completer<void>();
    var calls = 0;
    setup(service: Service((_) {
      if (++calls == 1) {
        firstEntered.complete();
        return first.future;
      }
      secondEntered.complete();
      return second.future;
    }));
    final old = manager.downloadFile('same', force: true);
    await firstEntered.future;
    final fresh = manager.downloadFile('same', force: true);
    await secondEntered.future;
    second.complete(Response(Stream.value([9, 9]), contentLength: 2));
    hold((await fresh).file);
    first.complete(Response(Stream.value([1, 1]), contentLength: 2));
    hold((await old).file);
    final cached = (await manager.getFileFromCache('same'))!;
    hold(cached.file);
    expect(await cached.file.readAsBytes(), [9, 9]);
  });

  test('concurrency bound and waiter progress use completion gates, not 30ms sleeps', () async {
    final responses = List.generate(6, (_) => Completer<FileServiceResponse>());
    final four = Completer<void>();
    final six = Completer<void>();
    var calls = 0;
    setup(service: Service((_) {
      final response = responses[calls++];
      if (calls == 4) four.complete();
      if (calls == 6) six.complete();
      return response.future;
    }));
    final pending = List.generate(6, (index) => manager.downloadFile('$index'));
    try {
      await four.future.timeout(const Duration(seconds: 3));
      expect(calls, 4);
      for (var i = 0; i < 4; i++) {
        responses[i].complete(Response(Stream.value([i]), contentLength: 1));
      }
      await six.future.timeout(const Duration(seconds: 3));
      expect(calls, 6);
    } finally {
      for (final response in responses) {
        if (!response.isCompleted) response.complete(Response(Stream.value([9]), contentLength: 1));
      }
      for (final result in await Future.wait(pending)) {
        hold(result.file);
      }
    }
    expect(await budget.sizeBytes(), 6);
  });

}
