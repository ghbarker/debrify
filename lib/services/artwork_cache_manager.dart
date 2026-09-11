import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:math';

import 'artwork_cache_budget.dart';
import 'artwork_cache_file.dart';
import 'artwork_cache_repository.dart';

class _FileSystem implements FileSystem {
  _FileSystem(String key, io.Directory? directory)
    : directory = directory == null
          ? getTemporaryDirectory().then(
              (base) => io.Directory(p.join(base.path, key)),
            )
          : Future.value(directory);
  final Future<io.Directory> directory;
  @override
  Future<fs.File> createFile(String name) async {
    final dir = await directory;
    await dir.create(recursive: true);
    return const LocalFileSystem().file(p.join(dir.path, name));
  }
}

/// CacheManager-compatible singleton with bounded, cancellable disk writes.
/// Uses only flutter_cache_manager's public Config and repository API. The
/// original cache keys/repositories remain readable across policy changes.
class ArtworkCacheManager extends CacheManager {
  factory ArtworkCacheManager({
    required String cacheKey,
    required ArtworkCacheBudget budget,
    required int standardCapacity,
    io.Directory? directory,
    CacheInfoRepository? repository,
    FileService? fileService,
    Future<void> Function()? initializePolicy,
    Future<io.RandomAccessFile> Function(String)? openFile,
  }) {
    final fileSystem = _FileSystem(cacheKey, directory);
    final defaults = Config(
      cacheKey,
      maxNrOfCacheObjects: standardCapacity,
      fileSystem: fileSystem,
    );
    final repo = ArtworkCacheRepository(repository ?? defaults.repo);
    final config = Config(
      cacheKey,
      maxNrOfCacheObjects: standardCapacity,
      stalePeriod: const Duration(days: 30),
      repo: repo,
      fileSystem: fileSystem,
      fileService: fileService ?? defaults.fileService,
    );
    final store = ArtworkCacheStore(
      cacheKey,
      fileSystem.directory,
      repo,
      standardCapacity,
    );
    budget.register(store);
    return ArtworkCacheManager._(
      config,
      budget,
      store,
      initializePolicy,
      openFile,
    );
  }

  ArtworkCacheManager._(
    super.config,
    this.budget,
    this.artworkStore,
    this.initializePolicy,
    this.openFile,
  );
  final ArtworkCacheBudget budget;
  final ArtworkCacheStore artworkStore;
  final Future<void> Function()? initializePolicy;
  final Future<io.RandomAccessFile> Function(String)? openFile;
  final _pending = <(String, int), Future<FileInfo>>{};

  Future<void> _ready({bool inventory = true}) async {
    await initializePolicy?.call();
    if (inventory) await budget.initialize();
  }

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    await _ready(inventory: false);
    return budget.transaction(() async {
      final object = await config.repo.get(key);
      if (object == null) return null;
      final dir = await artworkStore.directory;
      final path = p.join(dir.path, object.relativePath);
      if (!p.isWithin(dir.path, path) ||
          !await budget.adopt(path, artworkStore, key) ||
          !await io.File(path).exists()) {
        if (object.id != null) await config.repo.delete(object.id!);
        return null;
      }
      await budget.touch(path);
      budget.handoff(path);
      return FileInfo(
        ArtworkCacheFile(io.File(path), budget),
        FileSource.Cache,
        object.validTill,
        object.url,
      );
    });
  }

  @override
  Future<FileInfo?> getFileFromMemory(String key) => getFileFromCache(key);

  @override
  Future<fs.File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    final cached = await getFileFromCache(key ?? url);
    if (cached != null && cached.validTill.isAfter(DateTime.now())) {
      return cached.file;
    }
    return (await downloadFile(url, key: key, authHeaders: headers)).file;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final controller = StreamController<FileResponse>();
    Future<void> run() async {
      FileInfo? cached;
      try {
        await _ready(inventory: false);
        final token = budget.token();
        cached = await getFileFromCache(key ?? url);
        if (cached != null) controller.add(cached);
        if (cached == null || cached.validTill.isBefore(DateTime.now())) {
          final file = await _download(
            url,
            key ?? url,
            headers,
            token,
            progress: withProgress && cached == null
                ? (progress) {
                    if (controller.hasListener) controller.add(progress);
                  }
                : null,
          );
          if (controller.hasListener) controller.add(file);
        }
      } catch (error, stack) {
        final notFound =
            cached != null &&
            error is HttpExceptionWithStatus &&
            error.statusCode == 404;
        if ((cached == null || notFound) && controller.hasListener) {
          controller.addError(error, stack);
        }
        if (notFound) await removeFile(key ?? url);
      } finally {
        await controller.close();
      }
    }

    controller.onListen = () {
      unawaited(run());
    };
    return controller.stream;
  }

  @override
  Stream<FileInfo> getFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) => getFileStream(
    url,
    key: key,
    headers: headers,
  ).where((r) => r is FileInfo).cast<FileInfo>();

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    await _ready();
    return _download(
      url,
      key ?? url,
      authHeaders,
      budget.token(),
      force: force,
    );
  }

  Future<FileInfo> _download(
    String url,
    String key,
    Map<String, String>? headers,
    ArtworkCacheToken token, {
    bool force = false,
    void Function(DownloadProgress)? progress,
  }) async {
    await budget.initialize();
    budget.check(token);
    final id = (key, token.generation);
    if (!force && _pending.containsKey(id)) {
      return _consumer(await _pending[id]!);
    }
    final future = budget.downloadSlot(token, () async {
      final old = await config.repo.get(key);
      final requestHeaders = <String, String>{
        if (old?.eTag != null) io.HttpHeaders.ifNoneMatchHeader: old!.eTag!,
        ...?headers,
      };
      var abandoned = false;
      final request = config.fileService.get(url, headers: requestHeaders);
      unawaited(
        request.then((response) {
          if (abandoned) unawaited(response.content.listen(null).cancel());
        }, onError: (Object _) {}),
      );
      late FileServiceResponse response;
      try {
        response = await _untilCancelled(
          request,
          token,
          const Duration(seconds: 20),
        );
      } catch (_) {
        abandoned = true;
        rethrow;
      }
      if (response.statusCode == 304) {
        await response.content.listen(null).cancel();
        return budget.transaction(() async {
          budget.check(token);
          final dir = await artworkStore.directory;
          if (old == null ||
              !budget.available(p.join(dir.path, old.relativePath))) {
            throw const ArtworkCacheLimit();
          }
          final current = await config.repo.get(key);
          if (current == null) throw const ArtworkCacheLimit();
          final path = p.join(dir.path, current.relativePath);
          if (!budget.available(path) || !await io.File(path).exists()) {
            throw const ArtworkCacheLimit();
          }
          // A concurrent forced refresh may already have replaced the old ETag.
          if (current.relativePath == old.relativePath) {
            await config.repo.update(
              current.copyWith(validTill: response.validTill),
            );
          }
          await budget.touch(path);
          budget.handoff(path);
          return FileInfo(
            ArtworkCacheFile(io.File(path), budget),
            FileSource.Cache,
            response.validTill,
            url,
            statusCode: 304,
          );
        });
      }
      if (response.statusCode != 200 && response.statusCode != 202) {
        await response.content.listen(null).cancel();
        throw HttpExceptionWithStatus(
          response.statusCode,
          'Artwork request failed',
        );
      }
      final file = await _save(
        url,
        key,
        response.content,
        token,
        length: response.contentLength,
        eTag: response.eTag,
        validTill: response.validTill,
        extension: response.fileExtension,
        progress: progress,
      );
      return FileInfo(
        file,
        FileSource.Online,
        response.validTill,
        url,
        statusCode: response.statusCode,
      );
    });
    _pending[id] = future;
    try {
      return _consumer(await future);
    } finally {
      if (identical(_pending[id], future)) _pending.remove(id);
    }
  }

  FileInfo _consumer(FileInfo downloaded) {
    // Each waiter owns its handoff: one decoder completing must not unpin a
    // different consumer which has not started reading yet.
    final file = ArtworkCacheFile(io.File(downloaded.file.path), budget);
    (downloaded.file as ArtworkCacheFile).release();
    return FileInfo(
      file,
      downloaded.source,
      downloaded.validTill,
      downloaded.originalUrl,
      statusCode: downloaded.statusCode,
    );
  }

  Future<T> _untilCancelled<T>(
    Future<T> action,
    ArtworkCacheToken token,
    Duration timeout,
  ) => budget.untilCancelled(action, token, timeout);

  Future<fs.File> _save(
    String url,
    String key,
    Stream<List<int>> source,
    ArtworkCacheToken token, {
    int? length,
    String? eTag,
    required DateTime validTill,
    required String extension,
    void Function(DownloadProgress)? progress,
  }) async {
    final iterator = StreamIterator(source);
    String? temporary;
    io.RandomAccessFile? handle;
    try {
      budget.check(token);
      if (length != null && length > budget.fileLimit) {
        throw const ArtworkCacheLimit();
      }
      final dir = await artworkStore.directory;
      final random = Random.secure();
      final id = List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final suffix = extension.replaceFirst(RegExp(r'^\.'), '');
      final filename =
          '$id.${RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(suffix) ? suffix : 'file'}';
      temporary = p.join(dir.path, '$id.part');
      final path = p.join(dir.path, filename);
      await budget.begin(temporary, key, artworkStore, token);
      handle =
          await (openFile?.call(temporary) ??
              io.File(temporary).open(mode: io.FileMode.write));
      final deadline = DateTime.now().add(const Duration(minutes: 1));
      var received = 0;
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('Artwork transfer timed out');
        }
        final timeout = remaining < const Duration(seconds: 20)
            ? remaining
            : const Duration(seconds: 20);
        if (!await _untilCancelled(iterator.moveNext(), token, timeout)) break;
        final chunk = iterator.current;
        await budget.write(temporary, handle, chunk, token);
        received += chunk.length;
        progress?.call(DownloadProgress(url, length, received));
      }
      if (length != null && received != length) {
        throw const io.HttpException('Incomplete artwork');
      }
      await handle.close();
      handle = null;
      await budget.transaction(
        () => budget.publish(temporary!, path, token, () async {
          final old = await config.repo.get(key);
          await config.repo.updateOrInsert(
            CacheObject(
              url,
              key: key,
              id: old?.id,
              relativePath: filename,
              validTill: validTill,
              eTag: eTag,
              length: received,
            ),
          );
          if (old != null) budget.retire(p.join(dir.path, old.relativePath));
        }),
      );
      return ArtworkCacheFile(io.File(path), budget);
    } finally {
      try {
        await iterator.cancel().timeout(const Duration(seconds: 2));
      } finally {
        try {
          await handle?.close();
        } finally {
          if (temporary != null) await budget.abandon(temporary);
        }
      }
    }
  }

  @override
  Future<fs.File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) => putFileStream(
    url,
    Stream.value(fileBytes),
    key: key,
    eTag: eTag,
    maxAge: maxAge,
    fileExtension: fileExtension,
  );

  @override
  Future<fs.File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    await _ready();
    final token = budget.token();
    return budget.downloadSlot(
      token,
      () => _save(
        url,
        key ?? url,
        source,
        token,
        eTag: eTag,
        validTill: DateTime.now().add(maxAge),
        extension: fileExtension,
      ),
    );
  }

  @override
  Future<void> removeFile(String key) async {
    await _ready();
    final object = await budget.transaction(() async {
      final object = await config.repo.get(key);
      if (object?.id != null) await config.repo.delete(object!.id!);
      return object;
    });
    if (object != null) {
      final dir = await artworkStore.directory;
      final path = p.join(dir.path, object.relativePath);
      if (p.isWithin(dir.path, path)) await budget.remove(path);
    }
  }

  @override
  Future<void> emptyCache() async {
    await _ready();
    await budget.clear(artworkStore);
  }
}
