import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io' as io;

import 'package:debrify/services/artwork_cache_budget.dart';
import 'package:debrify/services/artwork_cache_file.dart';
import 'package:debrify/services/artwork_cache_manager.dart';
import 'package:file/file.dart' as fs;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class Response implements FileServiceResponse {
  Response(this.content, {this.contentLength, this.statusCode = 200});
  @override
  final Stream<List<int>> content;
  @override
  final int? contentLength;
  @override
  final int statusCode;
  @override
  String? get eTag => 'test-etag';
  @override
  String get fileExtension => '.png';
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
}

class Service extends FileService {
  Service(this.respond);
  final Future<FileServiceResponse> Function(String) respond;
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) =>
      respond(url);
}

class DiskFull with fs.ForwardingRandomAccessFile {
  DiskFull(this.delegate);
  @override
  final io.RandomAccessFile delegate;
  @override
  Future<io.RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    await delegate.writeFrom(buffer, start, start + 1);
    throw io.FileSystemException(
      'Disk full',
      delegate.path,
      const io.OSError('ENOSPC', 28),
    );
  }
}

void release(io.File file) => (file as ArtworkCacheFile).release();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;
  late io.Directory root;
  late ArtworkCacheBudget budget;
  late ArtworkCacheManager images;
  late ArtworkCacheManager logos;
  final held = <io.File>[];
  var tick = DateTime.now();

  ArtworkCacheManager manager(
    String name, {
    FileService? service,
    Future<io.RandomAccessFile> Function(String)? openFile,
  }) => ArtworkCacheManager(
    cacheKey: name,
    budget: budget,
    standardCapacity: name == 'images' ? 2 : 3,
    directory: io.Directory(p.join(root.path, name)),
    repository: JsonCacheInfoRepository(path: p.join(root.path, '$name.json')),
    fileService: service,
    openFile: openFile,
  );
  Future<io.File> put(ArtworkCacheManager manager, String key, int size) async {
    tick = tick.add(const Duration(seconds: 1));
    final file = await manager.putFile(
      'https://artwork.invalid/$key',
      Uint8List(size),
      key: key,
    );
    held.add(file);
    return file;
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await budget.apply(expanded: budget.expanded, bytes: budget.budgetBytes);
  }

  Future<int> physicalBytes() async {
    var bytes = 0;
    for (final name in ['images', 'logos']) {
      final directory = io.Directory(p.join(root.path, name));
      if (!await directory.exists()) continue;
      await for (final file in directory.list(recursive: true)) {
        if (file is io.File) bytes += await file.length();
      }
    }
    return bytes;
  }

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp('artwork-test-');
    budget = ArtworkCacheBudget(
      maxFileBytes: 64,
      handoffGrace: Duration.zero,
      now: () => tick,
    );
  });
  tearDown(() async {
    for (final file in held) {
      release(file);
    }
    held.clear();
    await budget.dispose();
    await images.dispose();
    await logos.dispose();
    await root.delete(recursive: true);
  });
  void standard({
    FileService? service,
    Future<io.RandomAccessFile> Function(String)? openFile,
  }) {
    images = manager('images', service: service, openFile: openFile);
    logos = manager('logos');
  }

  test(
    'combined actual originals, variant keys and logo stream bytes obey LRU',
    () async {
      standard();
      await budget.apply(expanded: true, bytes: 12);
      final original = await put(images, 'original', 4);
      release(original);
      final variant = await images.putFileStream(
        'url',
        Stream.value([1, 2, 3, 4]),
        key: 'resized_w20_original',
      );
      held.add(variant);
      release(variant);
      final logo = await put(logos, 'logo', 4);
      release(logo);
      await settle();
      expect(await budget.sizeBytes(), 12);
      expect(await physicalBytes(), 12);
      tick = tick.add(const Duration(seconds: 1));
      final hit = (await images.getFileFromCache('original'))!;
      release(hit.file);
      await settle();
      final next = await put(logos, 'next', 4);
      expect(await images.getFileFromCache('resized_w20_original'), isNull);
      final retained = (await images.getFileFromCache('original'))!;
      held.add(retained.file);
      expect(await retained.file.readAsBytes(), Uint8List(4));
      expect(await next.length(), 4);
      expect(await budget.sizeBytes(), 12);
      expect(await physicalBytes(), 12);
    },
  );

  test(
    'off retains each store count policy and switching retains manager identity',
    () async {
      standard();
      final identity = images;
      await budget.apply(expanded: false, bytes: 1);
      for (var i = 0; i < 4; i++) {
        release(await put(images, '$i', 4));
        release(await put(logos, '$i', 4));
        await settle();
      }
      expect((await images.config.repo.getAllObjects()).length, 2);
      expect((await logos.config.repo.getAllObjects()).length, 3);
      expect(await budget.sizeBytes(), 20);
      await budget.apply(expanded: true, bytes: 8);
      expect(identical(identity, images), isTrue);
      expect(await budget.sizeBytes(), 8);
    },
  );

  test(
    'stream-complete FileInfo remains readable after clear beyond grace',
    () async {
      standard();
      final original = await put(images, 'same', 8);
      release(original);
      final responses = await images.getFileStream('url', key: 'same').toList();
      final file = (responses.single as FileInfo).file;
      held.add(file);
      await budget.clear();
      await settle();
      expect(await images.getFileFromCache('same'), isNull);
      expect(await physicalBytes(), 8);
      expect(await file.readAsBytes(), Uint8List(8));
      release(file);
      await settle();
      expect(await physicalBytes(), 0);
    },
  );

  test(
    'lower budget retains reader, blocks new bytes, then reclaims on release',
    () async {
      standard();
      await budget.apply(expanded: true, bytes: 16);
      final reader = await put(images, 'reader', 12);
      await budget.apply(expanded: true, bytes: 4);
      await expectLater(
        put(logos, 'blocked', 1),
        throwsA(isA<ArtworkCacheLimit>()),
      );
      expect(await budget.sizeBytes(), 12);
      expect(await reader.readAsBytes(), Uint8List(12));
      release(reader);
      await settle();
      expect(await physicalBytes(), 0);
      final accepted = await put(logos, 'accepted', 4);
      expect(await accepted.length(), 4);
      expect(await physicalBytes(), 4);
    },
  );

  for (final length in <int?>[null, 2, 20]) {
    test(
      'rejects oversized or inconsistent content length $length without partial publication',
      () async {
        standard(
          service: Service(
            (_) async => Response(
              Stream.fromIterable([
                [1, 2, 3],
                [4, 5, 6],
              ]),
              contentLength: length,
            ),
          ),
        );
        await budget.apply(expanded: true, bytes: length == 2 ? 8 : 4);
        await expectLater(
          images.downloadFile('https://artwork.invalid/a'),
          throwsA(anyOf(isA<ArtworkCacheLimit>(), isA<io.HttpException>())),
        );
        expect(
          await images.getFileFromCache('https://artwork.invalid/a'),
          isNull,
        );
        expect(await budget.sizeBytes(), 0);
        expect(await physicalBytes(), 0);
        expect(await (await put(images, 'recovery', 4)).length(), 4);
      },
    );
  }

  test('truncated successful response releases bytes', () async {
    standard(
      service: Service(
        (_) async => Response(Stream.value([1, 2]), contentLength: 4),
      ),
    );
    await expectLater(
      images.downloadFile('https://artwork.invalid/a'),
      throwsA(isA<io.HttpException>()),
    );
    expect(await physicalBytes(), 0);
    expect(await budget.sizeBytes(), 0);
  });

  test('real HTTP valid artwork round trip and 206 rejection', () async {
    budget = ArtworkCacheBudget(
      maxFileBytes: 1024,
      handoffGrace: Duration.zero,
    );
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
    );
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = io.ContentType('image', 'png');
      request.response.statusCode = request.uri.path == '/partial' ? 206 : 200;
      request.response.contentLength = png.length;
      request.response.add(png);
      await request.response.close();
    });
    standard();
    final base = 'http://127.0.0.1:${server.port}';
    final info = await images.downloadFile('$base/good');
    held.add(info.file);
    expect(await info.file.readAsBytes(), png);
    final codec = await ui.instantiateImageCodec(await info.file.readAsBytes());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1);
    frame.image.dispose();
    codec.dispose();
    final cached = await images.getSingleFile('$base/good');
    held.add(cached);
    expect(cached.path, info.file.path);
    await expectLater(
      images.downloadFile('$base/partial'),
      throwsA(isA<HttpExceptionWithStatus>()),
    );
    expect(await physicalBytes(), png.length);
  });

  test(
    'disk full after a partial physical write cleans reservation and recovers',
    () async {
      var fail = true;
      standard(
        openFile: (path) async {
          final file = await io.File(path).open(mode: io.FileMode.write);
          return fail ? DiskFull(file) : file;
        },
      );
      await budget.apply(expanded: true, bytes: 8);
      await expectLater(
        put(images, 'bad', 4),
        throwsA(isA<io.FileSystemException>()),
      );
      expect(await physicalBytes(), 0);
      expect(await budget.sizeBytes(), 0);
      fail = false;
      expect(await (await put(images, 'good', 8)).length(), 8);
    },
  );

  test(
    'clear cancels old same-key stream without removing fresh replacement',
    () async {
      final old = StreamController<List<int>>();
      final entered = Completer<void>();
      var count = 0;
      standard(
        service: Service((_) async {
          count++;
          if (count == 1) {
            entered.complete();
            return Response(old.stream);
          }
          return Response(Stream.value([7, 8, 9]), contentLength: 3);
        }),
      );
      await budget.apply(expanded: true, bytes: 8);
      final first = images.downloadFile('https://artwork.invalid/same');
      final cancelled = expectLater(
        first,
        throwsA(isA<ArtworkCacheCancelled>()),
      );
      await entered.future;
      old.add([1, 2]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await budget.sizeBytes(), 2);
      await budget.clear();
      final fresh = await images.downloadFile('https://artwork.invalid/same');
      held.add(fresh.file);
      old.add([3, 4, 5]);
      await old.close();
      await cancelled;
      await settle();
      final cached = (await images.getFileFromCache(
        'https://artwork.invalid/same',
      ))!;
      held.add(cached.file);
      expect(await cached.file.readAsBytes(), [7, 8, 9]);
      expect(cached.file.path, fresh.file.path);
      expect(await physicalBytes(), 3);
    },
  );

  test(
    'concurrent unknown streams share combined budget including partial files',
    () async {
      standard();
      await budget.apply(expanded: true, bytes: 8);
      final first = StreamController<List<int>>();
      final pending = images.putFileStream('first', first.stream);
      first.add([1, 2, 3, 4, 5, 6]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await budget.sizeBytes(), 6);
      await expectLater(
        put(logos, 'other', 3),
        throwsA(isA<ArtworkCacheLimit>()),
      );
      expect(await physicalBytes(), 6);
      await first.close();
      final file = await pending;
      held.add(file);
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    },
  );

  test('cached first image does not wait for delayed disk inventory', () async {
    final inventory = Completer<void>();
    budget = ArtworkCacheBudget(
      handoffGrace: Duration.zero,
      beforeInventory: () => inventory.future,
    );
    standard();
    final dir = await images.artworkStore.directory;
    await dir.create(recursive: true);
    await io.File(p.join(dir.path, 'existing.png')).writeAsBytes([1, 2, 3, 4]);
    await images.config.repo.insert(
      CacheObject(
        'url',
        key: 'existing',
        relativePath: 'existing.png',
        validTill: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    var inventoryFinished = false;
    final applying = budget
        .apply(expanded: true, bytes: 8)
        .then((_) => inventoryFinished = true);
    final watch = Stopwatch()..start();
    final hit = await images
        .getSingleFile('url', key: 'existing')
        .timeout(const Duration(milliseconds: 500));
    held.add(hit);
    expect(await hit.readAsBytes(), [1, 2, 3, 4]);
    expect(inventoryFinished, isFalse);
    // A bounded cached read is observable even with inventory held indefinitely.
    expect(watch.elapsedMilliseconds, lessThan(500));
    debugPrint(
      'Cached read with inventory held: ${watch.elapsedMicroseconds} us',
    );
    inventory.complete();
    await applying;
    expect(await budget.sizeBytes(), 4);
  });

  test(
    'restart inventories orphan originals and partials across both stores',
    () async {
      standard();
      for (final name in ['images', 'logos']) {
        final dir = io.Directory(p.join(root.path, name));
        await dir.create(recursive: true);
        await io.File(
          p.join(dir.path, 'orphan.png'),
        ).writeAsBytes(Uint8List(6));
        await io.File(
          p.join(dir.path, 'interrupted.part'),
        ).writeAsBytes(Uint8List(3));
      }
      await budget.apply(expanded: true, bytes: 8);
      expect(await physicalBytes(), 6);
      expect(await budget.sizeBytes(), 6);
      expect(
        await io.File(p.join(root.path, 'images', 'interrupted.part')).exists(),
        isFalse,
      );
      expect(
        await io.File(p.join(root.path, 'logos', 'interrupted.part')).exists(),
        isFalse,
      );
    },
  );

  test(
    'policy reduction invalidates an in-flight put and releases its partial',
    () async {
      standard();
      await budget.apply(expanded: true, bytes: 16);
      final stream = StreamController<List<int>>();
      final pending = images.putFileStream('pending', stream.stream);
      final rejected = expectLater(
        pending,
        throwsA(isA<ArtworkCacheCancelled>()),
      );
      stream.add([1, 2, 3, 4, 5, 6]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await physicalBytes(), 6);
      await budget.apply(expanded: true, bytes: 4);
      stream.add([7, 8]);
      await stream.close();
      await rejected;
      expect(await budget.sizeBytes(), 0);
      expect(await images.getFileFromCache('pending'), isNull);
      expect(await (await put(logos, 'fresh', 4)).length(), 4);
    },
  );

  test(
    'late old HTTP headers after clear cannot publish or delete same-key fresh file',
    () async {
      final old = Completer<FileServiceResponse>();
      final entered = Completer<void>();
      var calls = 0;
      standard(
        service: Service((_) async {
          if (++calls == 1) {
            entered.complete();
            return old.future;
          }
          return Response(Stream.value([9, 8]), contentLength: 2);
        }),
      );
      final pending = images.downloadFile('same');
      final rejected = expectLater(
        pending,
        throwsA(isA<ArtworkCacheCancelled>()),
      );
      await entered.future;
      await budget.clear();
      final fresh = await images.downloadFile('same');
      held.add(fresh.file);
      old.complete(Response(Stream.value([1, 2, 3]), contentLength: 3));
      await rejected;
      await settle();
      final cached = (await images.getFileFromCache('same'))!;
      held.add(cached.file);
      expect(await cached.file.readAsBytes(), [9, 8]);
      expect(await physicalBytes(), 2);
    },
  );

  test(
    'opened reader remains valid when FileInfo lease releases during clear',
    () async {
      standard();
      final file = await put(images, 'reader', 4);
      final reader = await file.open();
      release(file);
      await budget.clear();
      await settle();
      expect(await reader.read(4), Uint8List(4));
      expect(await physicalBytes(), 4);
      await reader.close();
      await settle();
      expect(await physicalBytes(), 0);
    },
  );

  test(
    'same-key replacement does not delete or mutate a retained original',
    () async {
      standard();
      await budget.apply(expanded: true, bytes: 16);
      final old = await put(images, 'same', 4);
      final replacement = await images.putFile(
        'url',
        Uint8List.fromList([9, 8, 7]),
        key: 'same',
      );
      held.add(replacement);
      expect(await old.readAsBytes(), Uint8List(4));
      expect(await replacement.readAsBytes(), [9, 8, 7]);
      release(old);
      await settle();
      final lookup = (await images.getFileFromCache('same'))!;
      held.add(lookup.file);
      expect(lookup.file.path, replacement.path);
      expect(await budget.sizeBytes(), 3);
    },
  );

  test(
    'closed repositories restart with persisted metadata and LRU order',
    () async {
      standard();
      await budget.apply(expanded: true, bytes: 16);
      release(await put(images, 'old', 4));
      release(await put(logos, 'new', 4));
      await settle();
      await budget.dispose();
      await images.dispose();
      await logos.dispose();
      budget = ArtworkCacheBudget(handoffGrace: Duration.zero);
      standard();
      await budget.apply(expanded: true, bytes: 4);
      expect(await images.getFileFromCache('old'), isNull);
      final retained = (await logos.getFileFromCache('new'))!;
      held.add(retained.file);
      expect(await retained.file.readAsBytes(), Uint8List(4));
      expect(await physicalBytes(), 4);
    },
  );

  test(
    'network concurrency is bounded across stores and pending callers deduplicate',
    () async {
      final responses = List.generate(
        6,
        (_) => Completer<FileServiceResponse>(),
      );
      var calls = 0;
      var pendingRequests = 0;
      var peakPendingRequests = 0;
      final firstBatchStarted = Completer<void>();
      final allStarted = Completer<void>();
      final service = Service((_) {
        final response = responses[calls++];
        pendingRequests++;
        if (pendingRequests > peakPendingRequests) {
          peakPendingRequests = pendingRequests;
        }
        if (calls == 4) firstBatchStarted.complete();
        if (calls == 6) allStarted.complete();
        return response.future.whenComplete(() => pendingRequests--);
      });
      images = manager('images', service: service);
      logos = manager('logos', service: service);
      await budget.apply(expanded: true, bytes: 32);
      final futures = List.generate(
        6,
        (index) => (index.isEven ? images : logos).downloadFile('$index'),
      );
      final duplicate = images.downloadFile('0');
      await firstBatchStarted.future.timeout(const Duration(seconds: 5));
      expect(calls, 4);
      for (var i = 0; i < 4; i++) {
        responses[i].complete(Response(Stream.value([i]), contentLength: 1));
      }
      await allStarted.future.timeout(const Duration(seconds: 5));
      expect(calls, 6);
      for (var i = 4; i < 6; i++) {
        responses[i].complete(Response(Stream.value([i]), contentLength: 1));
      }
      final files = await Future.wait(futures);
      held.addAll(files.map((f) => f.file));
      final same = await duplicate;
      held.add(same.file);
      expect(identical(same.file, files.first.file), isFalse);
      expect(same.file.path, files.first.file.path);
      expect(peakPendingRequests, 4);
      expect(calls, 6);
      expect(await physicalBytes(), 6);
    },
  );

  test(
    'read-only returned handles cannot bypass byte accounting with writes',
    () async {
      standard();
      final file = await put(images, 'readonly', 4);
      expect(() => file.writeAsBytes([1]), throwsUnsupportedError);
      expect(() => file.openWrite(), throwsUnsupportedError);
      expect(() => file.delete(), throwsUnsupportedError);
      expect(
        () => file.rename(p.join(root.path, 'moved')),
        throwsUnsupportedError,
      );
      await expectLater(
        file.open(mode: io.FileMode.write),
        throwsUnsupportedError,
      );
      expect(await file.readAsBytes(), Uint8List(4));
      expect(await budget.sizeBytes(), 4);
    },
  );

  test(
    'inventory failure can retry without poisoning future cache writes',
    () async {
      var fail = true;
      budget = ArtworkCacheBudget(
        handoffGrace: Duration.zero,
        beforeInventory: () async {
          if (fail) throw const io.FileSystemException('Inventory unavailable');
        },
      );
      standard();
      await expectLater(
        budget.apply(expanded: true, bytes: 8),
        throwsA(isA<io.FileSystemException>()),
      );
      fail = false;
      await budget.apply(expanded: true, bytes: 8);
      expect(await (await put(images, 'after-retry', 4)).length(), 4);
      expect(await budget.sizeBytes(), 4);
    },
  );

  test(
    'HTTP 304 revalidates existing immutable bytes without another payload',
    () async {
      standard(
        service: Service(
          (_) async => Response(const Stream.empty(), statusCode: 304),
        ),
      );
      final old = await images.putFile(
        'url',
        Uint8List.fromList([1, 2, 3]),
        key: 'etag',
        eTag: 'test-etag',
        maxAge: const Duration(seconds: -1),
      );
      held.add(old);
      final responses = await images.getFileStream('url', key: 'etag').toList();
      expect(responses.whereType<FileInfo>().length, 2);
      final fresh = responses.last as FileInfo;
      held.addAll(responses.whereType<FileInfo>().map((f) => f.file));
      expect(fresh.statusCode, 304);
      expect(fresh.file.path, old.path);
      expect(await fresh.file.readAsBytes(), [1, 2, 3]);
      expect(await physicalBytes(), 3);
    },
  );

  test(
    'HTTP 404 retires lookup but does not break already yielded stale reader',
    () async {
      standard(
        service: Service(
          (_) async => Response(const Stream.empty(), statusCode: 404),
        ),
      );
      final old = await images.putFile(
        'url',
        Uint8List(4),
        maxAge: const Duration(seconds: -1),
      );
      held.add(old);
      final files = <FileInfo>[];
      final errors = <Object>[];
      final done = Completer<void>();
      images
          .getFileStream('url')
          .listen(
            (response) {
              if (response is FileInfo) files.add(response);
            },
            onError: (Object error) => errors.add(error),
            onDone: done.complete,
          );
      await done.future;
      held.addAll(files.map((f) => f.file));
      expect(files.length, 1);
      expect(errors.single, isA<HttpExceptionWithStatus>());
      expect(await images.getFileFromCache('url'), isNull);
      expect(await files.single.file.readAsBytes(), Uint8List(4));
    },
  );

  test(
    'completed normal reads release capacity without GC and next failed lookup retries',
    () async {
      var requests = 0;
      standard(
        service: Service((_) async {
          requests++;
          return Response(Stream.value([9, 8, 7, 6]), contentLength: 4);
        }),
      );
      await budget.apply(expanded: true, bytes: 16);
      final heldReader = await put(images, 'held', 12);
      await budget.apply(expanded: true, bytes: 4);
      await expectLater(
        images.getSingleFile('fresh'),
        throwsA(isA<ArtworkCacheLimit>()),
      );
      final cached = (await images.getFileFromCache('held'))!;
      held.add(cached.file);
      expect(await cached.file.readAsBytes(), Uint8List(12));
      // Complete the original reader normally, deliberately keeping both File
      // objects strongly referenced. No explicit release and no forced GC.
      expect(await heldReader.readAsBytes(), Uint8List(12));
      final fresh = await images.getSingleFile('fresh');
      held.add(fresh);
      expect(await fresh.readAsBytes(), [9, 8, 7, 6]);
      expect(requests, 2);
      expect(await physicalBytes(), 4);
      expect(await budget.sizeBytes(), 4);
    },
  );

  test(
    'fast browsing holds completed FileInfo objects without exhausting disk leases',
    () async {
      standard(
        service: Service(
          (url) async =>
              Response(Stream.value([url.length, 2, 3, 4]), contentLength: 4),
        ),
      );
      await budget.apply(expanded: true, bytes: 8);
      final retainedInfos = <FileInfo>[];
      for (var i = 0; i < 30; i++) {
        final info = await images.downloadFile('url-$i');
        retainedInfos.add(info);
        held.add(info.file);
        expect((await info.file.readAsBytes()).length, 4);
      }
      expect(retainedInfos.length, 30);
      expect(await physicalBytes(), lessThanOrEqualTo(8));
      expect(await budget.sizeBytes(), lessThanOrEqualTo(8));
    },
  );

  test(
    'deduplicated downloads grant separate delayed consumer handoffs',
    () async {
      final response = Completer<FileServiceResponse>();
      standard(service: Service((_) => response.future));
      final first = images.downloadFile('same');
      final second = images.downloadFile('same');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      response.complete(Response(Stream.value([1, 2, 3]), contentLength: 3));
      final a = await first;
      final b = await second;
      held.addAll([a.file, b.file]);
      expect(identical(a.file, b.file), isFalse);
      await budget.clear();
      expect(await a.file.readAsBytes(), [1, 2, 3]);
      await settle();
      expect(await physicalBytes(), 3);
      expect(await b.file.readAsBytes(), [1, 2, 3]);
      await settle();
      expect(await physicalBytes(), 0);
    },
  );
}
