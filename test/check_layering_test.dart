import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

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

class _LockedDirectory implements Directory {
  int attempts = 0;
  final failure = const FileSystemException('still owned by a resource');

  @override
  bool existsSync() => true;

  @override
  Future<bool> exists() async => true;

  @override
  void deleteSync({bool recursive = false}) {
    attempts++;
    throw failure;
  }

  @override
  Future<Directory> delete({bool recursive = false}) async {
    attempts++;
    throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'temp cleanup exposes resource ownership failures without retries',
    () async {
      final directory = _LockedDirectory();
      await expectLater(
        deleteTempTree(directory),
        throwsA(same(directory.failure)),
      );
      expect(directory.attempts, 1);
    },
  );

  test('temp cleanup removes a tree after its file handle is closed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'c0 closed handle ',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/owned.txt');
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeString('owned');
    } finally {
      await handle.close();
    }
    await deleteTempTree(directory);
    expect(await directory.exists(), isFalse);
    await deleteTempTree(directory); // Already absent is harmless.
  });

  test('checker executable is an actual native SDK binary', () async {
    final executable = _dartExecutable();
    expect(File(executable).isAbsolute, isTrue);
    expect(File(executable).existsSync(), isTrue);
    if (Platform.isWindows) expect(executable, endsWith('.exe'));
    final result = await Process.run(executable, ['--version']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}${result.stderr}', contains('Dart SDK version'));
  });
  test(
    'non-strict exits 0 when count is within the committed ceiling',
    () async {
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
        lessThanOrEqualTo(int.parse(match.group(2)!)),
        reason: 'improvements below the ceiling must remain green',
      );
    },
  );

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
    expect(payload['count'], lessThanOrEqualTo(payload['ceiling'] as int));
    expect(payload['violations'], isA<List<dynamic>>());
    final first = (payload['violations'] as List).first as Map<String, dynamic>;
    expect(first['id'], contains('|'));
    expect(first['file'], isNotEmpty);
    expect(first['rule'], isNotEmpty);
  });

  test(
    '--root preserves duplicate occurrences and paths containing spaces',
    () async {
      final root = await Directory.systemTemp.createTemp('c0 layering root ');
      addTearDown(() => deleteTempTree(root));
      final services = await Directory(
        '${root.path}/lib/services',
      ).create(recursive: true);
      await File('${services.path}/duplicate.dart').writeAsString(
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:flutter/widgets.dart';\n",
      );
      final result = await _runLayering(['--root', root.path, '--json']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final payload = jsonDecode('${result.stdout}') as Map<String, dynamic>;
      expect(payload['count'], 2);
      final rows = payload['violations'] as List<dynamic>;
      expect(rows, hasLength(2));
      expect(rows[0]['id'], rows[1]['id']);
      expect(rows[0]['file'], 'lib/services/duplicate.dart');
    },
  );

  test('strict mode still fails while Phase 2 has violations', () async {
    final result = await _runLayering(const ['--strict']);
    expect(result.exitCode, 1, reason: result.stdout.toString());
    expect('${result.stdout}', contains('strict'));
  });
}
