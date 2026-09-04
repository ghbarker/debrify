import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layering check warns on current main without failing', () async {
    final result = await Process.run('dart', [
      'run',
      'tool/check_layering.dart',
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = '${result.stdout}';
    expect(out, contains('Import layering'));
    expect(out, contains('warn-only'));
    expect(out, contains('models: no Flutter'));
    expect(out, contains('widgets: never screens'));
  });

  test('strict mode still fails while Phase 2 has violations', () async {
    final result = await Process.run('dart', [
      'run',
      'tool/check_layering.dart',
      '--strict',
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 1, reason: result.stdout.toString());
    expect('${result.stdout}', contains('strict'));
  });
}
