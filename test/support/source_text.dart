import 'dart:io';

import 'package:path/path.dart' as p;

/// Read a repo file for source-grep tests. Normalize CRLF so `indexOf`
/// markers written as `\n` still match on Windows checkouts.
String readSource(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Compare a filesystem path as POSIX segments (Windows backslashes).
String posixPath(String path) => p.posix.normalize(path.replaceAll(r'\', '/'));

/// Delete a temp tree. Windows AV / open handles raise [FileSystemException]
/// (often [PathAccessException]); retry instead of failing the suite.
Future<void> deleteTempTree(Directory dir) async {
  Object? last;
  for (var attempt = 0; attempt < 6; attempt++) {
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      return;
    } on FileSystemException catch (e) {
      last = e;
      await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
    }
  }
  if (last != null) {
    throw last;
  }
}
