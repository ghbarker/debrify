import 'dart:io';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('scope produces stable generation-aware keys and paths', () {
    final scope = ProfileScope(
      profileId: 'profile-abc_123',
      dataGeneration: 7,
      sessionEpoch: 4,
    );

    expect(scope.preferencePrefix, 'p.profile-abc_123.g.7.');
    expect(scope.preferenceKey('theme'), 'p.profile-abc_123.g.7.theme');
    final root = Directory(p.join(Directory.systemTemp.path, 'profile-root'));
    final file = scope.file(root, p.join('db', 'catalog.sqlite'));
    expect(
      file.path,
      p.join(
        root.path,
        'profiles',
        'profile-abc_123',
        'g',
        '7',
        'data',
        'db',
        'catalog.sqlite',
      ),
    );
    expect(
      p.isWithin(scope.storageDirectory(root, 'data').path, file.path),
      isTrue,
    );
  });

  test('scope rejects unsafe identifiers and traversal', () {
    expect(
      () => ProfileScope(
        profileId: '../admin',
        dataGeneration: 1,
        sessionEpoch: 0,
      ),
      throwsArgumentError,
    );
    final scope = ProfileScope(
      profileId: 'safe',
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    expect(() => scope.file(Directory.systemTemp, '..'), throwsArgumentError);
    expect(
      () => scope.file(Directory.systemTemp, p.absolute('escape')),
      throwsArgumentError,
    );
    expect(
      () => scope.file(Directory.systemTemp, '../escape'),
      throwsArgumentError,
    );
    if (Platform.isWindows) {
      expect(
        () => scope.file(Directory.systemTemp, r'..\escape'),
        throwsArgumentError,
      );
    }
  });
}
