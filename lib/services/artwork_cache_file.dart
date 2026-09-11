import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';

import 'artwork_cache_budget.dart';

/// CachedNetworkImage reads through this File, so eviction cannot unlink a
/// decoder's active read. A returned handle is read-only; writes use the manager.
class ArtworkCacheFile extends ForwardingFileSystemEntity<File, io.File>
    with ForwardingFile {
  ArtworkCacheFile(this.delegate, this.budget)
    : _release = budget.pin(delegate.path) {
    _finalizer.attach(this, _release, detach: this);
  }
  static final _finalizer = Finalizer<void Function()>((release) => release());
  final void Function() _release;

  /// Optional deterministic release for callers finished with this handle.
  /// A delayed consumer is protected until its first read finishes. Normal
  /// reads release automatically, so disk capacity never waits for decoder GC.
  /// After reading, acquire a new manager lookup before reusing an evicted file.
  void release() {
    _finalizer.detach(this);
    _release();
    budget.finishHandoff(path);
  }

  @override
  final io.File delegate;
  final ArtworkCacheBudget budget;
  @override
  FileSystem get fileSystem => const LocalFileSystem();
  @override
  File wrapFile(io.File file) => ArtworkCacheFile(file, budget);
  @override
  Directory wrapDirectory(io.Directory directory) =>
      fileSystem.directory(directory.path);
  @override
  Link wrapLink(io.Link link) => fileSystem.link(link.path);

  Future<T> _read<T>(Future<T> Function() read) async {
    final release = budget.pin(path);
    try {
      return await read();
    } finally {
      release();
      this.release();
    }
  }

  T _readSync<T>(T Function() read) {
    final active = budget.pin(path);
    try {
      return read();
    } finally {
      active();
      release();
    }
  }

  @override
  Uint8List readAsBytesSync() => _readSync(delegate.readAsBytesSync);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      _readSync(() => delegate.readAsStringSync(encoding: encoding));
  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      _readSync(() => delegate.readAsLinesSync(encoding: encoding));

  @override
  Future<Uint8List> readAsBytes() => _read(delegate.readAsBytes);
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _read(() => delegate.readAsString(encoding: encoding));
  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      _read(() => delegate.readAsLines(encoding: encoding));
  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    final release = budget.pin(path);
    try {
      yield* delegate.openRead(start, end);
    } finally {
      release();
      this.release();
    }
  }

  @override
  Future<io.RandomAccessFile> open({
    io.FileMode mode = io.FileMode.read,
  }) async {
    if (mode != io.FileMode.read) {
      throw UnsupportedError('Use the artwork manager to write');
    }
    final release = budget.pin(path);
    try {
      return _Reader(await delegate.open(), release);
    } catch (_) {
      release();
      rethrow;
    } finally {
      this.release();
    }
  }

  @override
  io.RandomAccessFile openSync({io.FileMode mode = io.FileMode.read}) {
    if (mode != io.FileMode.read) {
      throw UnsupportedError('Use the artwork manager to write');
    }
    final release = budget.pin(path);
    try {
      return _Reader(delegate.openSync(), release);
    } catch (_) {
      release();
      rethrow;
    } finally {
      this.release();
    }
  }

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      throw UnsupportedError('Use the artwork manager to write');
  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      throw UnsupportedError('Use the artwork manager to write');
  @override
  Future<File> delete({bool recursive = false}) =>
      throw UnsupportedError('Use the artwork manager to remove');
  @override
  void deleteSync({bool recursive = false}) =>
      throw UnsupportedError('Use the artwork manager to remove');
  @override
  Future<File> rename(String newPath) =>
      throw UnsupportedError('Use the artwork manager to write');
  @override
  File renameSync(String newPath) =>
      throw UnsupportedError('Use the artwork manager to write');
  @override
  Future<File> copy(String newPath) =>
      throw UnsupportedError('Use the artwork manager to write');
  @override
  File copySync(String newPath) =>
      throw UnsupportedError('Use the artwork manager to write');

  @override
  io.IOSink openWrite({
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
  }) => throw UnsupportedError('Use the artwork manager to write');
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    io.FileMode mode = io.FileMode.write,
    bool flush = false,
  }) => throw UnsupportedError('Use the artwork manager to write');
  @override
  void writeAsBytesSync(
    List<int> bytes, {
    io.FileMode mode = io.FileMode.write,
    bool flush = false,
  }) => throw UnsupportedError('Use the artwork manager to write');
  @override
  Future<File> writeAsString(
    String contents, {
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => throw UnsupportedError('Use the artwork manager to write');
  @override
  void writeAsStringSync(
    String contents, {
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => throw UnsupportedError('Use the artwork manager to write');
}

class _Reader with ForwardingRandomAccessFile {
  _Reader(this.delegate, this.release);
  @override
  final io.RandomAccessFile delegate;
  final void Function() release;
  @override
  Future<void> close() async {
    try {
      await delegate.close();
    } finally {
      release();
    }
  }

  @override
  void closeSync() {
    try {
      delegate.closeSync();
    } finally {
      release();
    }
  }
}
