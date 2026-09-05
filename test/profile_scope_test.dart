import 'dart:io';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final scope = ProfileScope(
    profileId: 'c0-origin',
    dataGeneration: 1,
    sessionEpoch: 0,
  );

  test('origin fileIn rejects native absolute paths', () {
    final absolute = p.absolute('c0-outside-profile');
    expect(
      () => scope.fileIn(Directory.systemTemp, 'data', absolute),
      throwsArgumentError,
    );
  });

  test('origin fileIn preserves valid nested native paths', () {
    final relative = p.join('db', 'catalog.sqlite');
    expect(
      scope.fileIn(Directory.systemTemp, 'data', relative).path,
      p.join(scope.storageDirectory(Directory.systemTemp, 'data').path, relative),
    );
  });
}
