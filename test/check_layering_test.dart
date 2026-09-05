import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-strict exits 0 when count equals the committed ceiling', () async {
    final result = await Process.run('dart', [
      'run',
      'tool/check_layering.dart',
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = '${result.stdout}';
    expect(out, contains('Import layering'));
    expect(out, contains('fail-on-growth'));
    expect(out, contains('models: no Flutter'));
    expect(out, contains('widgets: never screens'));
    final match = RegExp(
      r'(\d+) violation\(s\) \(ceiling (\d+)\)',
    ).firstMatch(out);
    expect(match, isNotNull, reason: out);
    expect(
      int.parse(match!.group(1)!),
      int.parse(match.group(2)!),
      reason: 'count must equal the committed ceiling',
    );
  });

  test('over-ceiling probe fails (growth gate)', () async {
    final result = await Process.run('dart', [
      'run',
      'tool/check_layering.dart',
      '--over-ceiling',
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 1, reason: result.stdout.toString());
    final out = '${result.stdout}';
    expect(out, contains('over-ceiling'));
    expect(out, contains('GROWTH'));
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
