import 'dart:io';

import 'package:path/path.dart' as p;

/// Read a repo file for source-grep tests. Normalize CRLF so `indexOf`
/// markers written as `\n` still match on Windows checkouts.
String readSource(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Compare a filesystem path as POSIX segments (Windows backslashes).
String posixPath(String path) => p.posix.normalize(path.replaceAll(r'\', '/'));

/// Delete only after the caller has closed its resources. An ownership failure
/// must stay visible; delaying and retrying cannot establish correct teardown.
Future<void> deleteTempTree(Directory dir) async {
  if (await dir.exists()) await dir.delete(recursive: true);
}
