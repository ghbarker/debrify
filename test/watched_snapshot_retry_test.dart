import 'package:debrify/services/watched_snapshot_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transient storage failures recover the watched snapshot', () async {
    var attempts = 0;
    final result = await readWatchedSnapshotWithRetry(() async {
      if (++attempts < 3) throw StateError('Storage unavailable');
      return {'tt1'};
    }, retryDelay: Duration.zero);
    expect(result, {'tt1'});
    expect(attempts, 3);
  });

  test('persistent failure is bounded and remains observable', () async {
    var attempts = 0;
    await expectLater(
      readWatchedSnapshotWithRetry(() async {
        attempts++;
        throw StateError('Storage unavailable');
      }, retryDelay: Duration.zero),
      throwsStateError,
    );
    expect(attempts, 3);
  });
}
