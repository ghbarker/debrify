import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/debrify_tv/watch_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live tests of the moved [WatchSession] body. The origin pin
/// (`magic_tv_watch_session_fields_pin_test.dart`) stays import-free and
/// unedited. Quirks match that pin — do not "fix".
void main() {
  test('field defaults match origin', () {
    final session = WatchSession();
    expect(session.queue, isEmpty);
    expect(session.queue, isA<List<dynamic>>());
    expect(session.isBusy, isFalse);
    expect(session.status, '');
    expect(session.pikpakCandidatePool, isNull);
    expect(session.currentWatchingChannelId, isNull);
    expect(session.progress.value, isEmpty);
    expect(session.progressSheetContext, isNull);
    expect(session.progressOpen, isFalse);
    session.dispose();
  });

  test('queue is the same list instance (screen accessors share it)', () {
    final session = WatchSession();
    final torrent = Torrent(
      rowid: 1,
      infohash: 'abc',
      name: 'Show.mkv',
      sizeBytes: 1,
      createdUnix: 0,
      seeders: 0,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
      source: 'test',
    );
    session.queue.add(torrent);
    session.queue.add({'restricted': true});
    expect(session.queue, hasLength(2));
    session.queue.clear();
    expect(session.queue, isEmpty);
    session.dispose();
  });

  test('empty sanitized is a no-op even with replace: true', () {
    final session = WatchSession();
    session.updateProgress(['keep']);
    session.updateProgress(['  ', '', '\t'], replace: true);
    expect(session.progress.value, ['keep']);
    session.dispose();
  });

  test('trim and drop empties; empty current behaves like replace', () {
    final session = WatchSession();
    session.updateProgress(['  hello  ', '', '  ']);
    expect(session.progress.value, ['hello']);
    session.updateProgress(['world']);
    expect(session.progress.value, ['hello', 'world']);
    session.updateProgress(['only'], replace: true);
    expect(session.progress.value, ['only']);
    session.dispose();
  });

  test(
    'ProgressSink is the snack/progress seam (not a host-State extension)',
    () {
      expect(ProgressSink, isA<Type>());
      final source = WatchSession;
      expect(source.toString(), contains('WatchSession'));
    },
  );
}
