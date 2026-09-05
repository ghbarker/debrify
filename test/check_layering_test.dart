import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locate the Dart SDK `dart` binary. Do not use `runInShell: true`
/// (Windows cmd wrapping is a gate-2 flake).
String _dartExecutable() {
  final exe = File(Platform.resolvedExecutable);
  final sibling = File(
    '${exe.parent.path}${Platform.pathSeparator}'
    'dart${Platform.isWindows ? '.exe' : ''}',
  );
  if (sibling.existsSync()) return sibling.path;
  var dir = exe.parent;
  for (var i = 0; i < 10; i++) {
    final sdk = File(
      '${dir.path}${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin'
      '${Platform.pathSeparator}dart${Platform.isWindows ? '.exe' : ''}',
    );
    if (sdk.existsSync()) return sdk.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return 'dart';
}

Future<ProcessResult> _runLayering(List<String> extra) {
  return Process.run(_dartExecutable(), [
    'run',
    'tool/check_layering.dart',
    ...extra,
  ], workingDirectory: Directory.current.path);
}

void main() {
  test('non-strict exits 0 when count equals the committed ceiling', () async {
    final result = await _runLayering(const []);
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
    final result = await _runLayering(const ['--over-ceiling']);
    expect(result.exitCode, 1, reason: result.stdout.toString());
    final out = '${result.stdout}';
    expect(out, contains('over-ceiling'));
    expect(out, contains('GROWTH'));
  });

  test('--all prints every violation (cap=40 hides the rest)', () async {
    final jsonRun = await _runLayering(const ['--json']);
    expect(jsonRun.exitCode, 0, reason: jsonRun.stderr.toString());
    final count =
        (jsonDecode('${jsonRun.stdout}') as Map<String, dynamic>)['count']
            as int;
    final capped = await _runLayering(const []);
    final all = await _runLayering(const ['--all']);
    expect(capped.exitCode, 0);
    expect(all.exitCode, 0);
    if (count > 40) {
      expect('${capped.stdout}', contains('more (pass --all'));
      expect('${all.stdout}', isNot(contains('more (pass --all')));
    }
  });

  test('--json reports ids and a count for the Leaves table', () async {
    final result = await _runLayering(const ['--json']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final payload = jsonDecode('${result.stdout}') as Map<String, dynamic>;
    expect(payload['count'], isA<int>());
    expect(payload['count'], greaterThan(0));
    expect(payload['ceiling'], payload['count']);
    expect(payload['violations'], isA<List<dynamic>>());
    final first = (payload['violations'] as List).first as Map<String, dynamic>;
    expect(first['id'], contains('|'));
    expect(first['file'], isNotEmpty);
    expect(first['rule'], isNotEmpty);
  });

  test('strict mode still fails while Phase 2 has violations', () async {
    final result = await _runLayering(const ['--strict']);
    expect(result.exitCode, 1, reason: result.stdout.toString());
    expect('${result.stdout}', contains('strict'));
  });
}
