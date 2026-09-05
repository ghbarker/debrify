import 'dart:io';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final scope = ProfileScope(
    profileId: 'path-pin',
    dataGeneration: 7,
    sessionEpoch: 2,
  );
  final root = Directory(
    p.join(Directory.systemTemp.path, 'profile path pins'),
  );

  final rejected = <String>[
    '..',
    '../escape',
    'nested/../../escape',
    'nested/../../../escape',
    '../data-sibling/escape',
    'nested/../../data-sibling/escape',
    p.absolute('outside-profile.sqlite'),
    p.join(scope.storageDirectory(root, 'data').path, 'inside.sqlite'),
    if (Platform.isWindows) ...[
      r'..\escape',
      r'nested\..\..\escape',
      r'nested/..\..\escape',
      r'\escape',
      r'C:\escape',
      r'C:escape',
      r'C:..\escape',
      r'.\C:escape',
      r'nested\..\C:escape',
      r'E:escape',
      r'\\server\share\escape',
      '//server/share/escape',
    ],
  ];
  for (final relative in rejected) {
    test('real scope API rejects $relative', () {
      expect(() => scope.file(root, relative), throwsArgumentError);
      expect(
        () => scope.fileIn(root, 'documents', relative),
        throwsArgumentError,
      );
    });
  }

  final accepted = <String, String>{
    'db/catalog.sqlite': p.join('db', 'catalog.sqlite'),
    './db/catalog.sqlite': p.join('db', 'catalog.sqlite'),
    'cache/../db/catalog.sqlite': p.join('db', 'catalog.sqlite'),
    'db/./catalog.sqlite': p.join('db', 'catalog.sqlite'),
    'db/../catalog.sqlite': 'catalog.sqlite',
    '.../report..txt': p.join('...', 'report..txt'),
    'db/my file [1].sqlite': p.join('db', 'my file [1].sqlite'),
    'db/café_日本語.txt': p.join('db', 'café_日本語.txt'),
    'db/.hidden': p.join('db', '.hidden'),
    if (Platform.isWindows)
      r'cache\..\db\catalog.sqlite': p.join('db', 'catalog.sqlite'),
    // On POSIX these are filenames, not Windows drive/separator syntax.
    if (!Platform.isWindows) ...{
      'C:notes.txt': 'C:notes.txt',
      r'db\literal.sqlite': r'db\literal.sqlite',
      r'..\escape': r'..\escape',
    },
  };
  for (final entry in accepted.entries) {
    test('real scope API preserves contained path ${entry.key}', () {
      for (final area in ['data', 'documents', 'cache']) {
        final directory = scope.storageDirectory(root, area).path;
        final actual = scope.fileIn(root, area, entry.key).path;
        expect(actual, p.join(directory, entry.value));
        expect(p.isWithin(directory, actual), isTrue);
      }
    });
  }

  test('relative roots preserve their representation for valid paths', () {
    final relativeRoot = Directory(p.join('relative root', 'storage'));
    expect(
      scope.file(relativeRoot, p.join('db', 'catalog.sqlite')).path,
      p.join(
        'relative root',
        'storage',
        'profiles',
        'path-pin',
        'g',
        '7',
        'data',
        p.join('db', 'catalog.sqlite'),
      ),
    );
  });

  test('root-equal paths keep existing behavior without escaping', () {
    for (final relative in ['', '.', 'nested/..']) {
      final actual = scope.file(root, relative).path;
      expect(
        p.equals(
          p.normalize(actual),
          scope.storageDirectory(root, 'data').path,
        ),
        isTrue,
      );
    }
  });

  test('preference and generation identity stays unchanged', () {
    expect(scope.preferenceKey('theme'), 'p.path-pin.g.7.theme');
    expect(scope.cacheKey, 'p.path-pin.g.7.e.2');
    expect(
      scope.generationDirectory(root).path,
      p.join(root.path, 'profiles', 'path-pin', 'g', '7'),
    );
  });
}
