import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// M1-0 characterisation of WatchSession origin fields and progress/snack
/// sinks **before** they move to `lib/screens/debrify_tv/watch_session.dart`.
///
/// Does not import that file (it does not exist on the parent of the move).
/// After the move this suite still matches the same members (optional
/// leading underscore) by also reading the new file when present — same
/// pattern as `tv_home_stage_layouts_pin_test.dart`.
///
/// Quirks pinned here (keep, do not "fix"):
/// * `_queue` is `List<dynamic>` (Torrent **or** RD-restricted link maps).
/// * `_status` starts as `''`, `_isBusy` as `false`, watching id and
///   PikPak pool as null, progress lines as `[]`, dialog closed.
/// * `_updateProgress` trims, drops empty, and **no-ops** when the
///   sanitized list is empty — even with `replace: true` (does not clear).
/// * Empty current lines behave like replace (`replace || value.isEmpty`).
/// * `_closeProgressDialog` returns immediately when `!_progressOpen`.
/// * `_showSnack` no-ops when `!mounted`; default colour `Colors.blueGrey`;
///   duration is 3 seconds.
String _host() => File(
  'lib/screens/magic_tv_screen.dart',
).readAsStringSync().replaceAll('\r\n', '\n');

/// Host plus the extracted WatchSession file so this suite stays green
/// after the verbatim field/sink move.
String _sessionSources() {
  final buf = StringBuffer(_host());
  final moved = File('lib/screens/debrify_tv/watch_session.dart');
  if (moved.existsSync()) {
    buf.writeln(moved.readAsStringSync().replaceAll('\r\n', '\n'));
  }
  return buf.toString();
}

/// Replica of origin `_updateProgress` (~691–707) over a list, so the
/// quirks run on this commit against the algorithm the source pin locks.
List<String> _applyOriginProgressUpdate(
  List<String> current,
  Iterable<String> messages, {
  bool replace = false,
}) {
  final sanitized = messages
      .map((message) => message.trim())
      .where((message) => message.isNotEmpty)
      .toList();
  if (sanitized.isEmpty) {
    return current;
  }

  if (replace || current.isEmpty) {
    return sanitized;
  }

  return List<String>.from(current)..addAll(sanitized);
}

void main() {
  late String host;
  late String sources;

  setUpAll(() {
    host = _host();
    sources = _sessionSources();
  });

  test('this pin does not import WatchSession', () {
    final pin = File(
      'test/magic_tv_watch_session_fields_pin_test.dart',
    ).readAsStringSync();
    expect(
      RegExp(r"^import .+watch_session\.dart", multiLine: true).hasMatch(pin),
      isFalse,
    );
  });

  group('WatchSession origin field defaults', () {
    test('queue is List<dynamic>, starts empty', () {
      expect(sources, contains(RegExp(r'final List<dynamic> _?queue = \[\];')));
      expect(
        sources,
        contains(
          '// Mixed queue: can contain Torrent items or RD-restricted link maps',
        ),
      );
    });

    test('isBusy starts false; status starts empty', () {
      expect(sources, contains(RegExp(r'bool _?isBusy = false;')));
      expect(sources, contains(RegExp(r"String _?status = '';")));
    });

    test('PikPak pool and watching channel id start null', () {
      expect(
        sources,
        contains(RegExp(r'List<Torrent>\? _?pikpakCandidatePool;')),
      );
      expect(
        sources,
        contains(
          RegExp(
            r'String\?\s*_?currentWatchingChannelId; // Track currently playing channel for switching',
          ),
        ),
      );
    });

    test('progress dialog starts empty and closed', () {
      expect(
        sources,
        contains(
          RegExp(
            r'final ValueNotifier<List<String>> _?progress = ValueNotifier<List<String>>\(\[\]\);',
          ),
        ),
      );
      expect(
        sources,
        contains(RegExp(r'BuildContext\? _?progressSheetContext;')),
      );
      expect(sources, contains(RegExp(r'bool _?progressOpen = false;')));
    });
  });

  group('_updateProgress origin algorithm', () {
    test('source still trims, drops empty, replace-or-empty, else append', () {
      expect(sources, contains('.map((message) => message.trim())'));
      expect(sources, contains('.where((message) => message.isNotEmpty)'));
      expect(
        sources,
        contains(RegExp(r'if \(replace \|\| _?progress\.value\.isEmpty\)')),
      );
      expect(sources, contains('..addAll(sanitized)'));
      expect(
        sources,
        contains(
          RegExp(
            r'void _?updateProgress\(Iterable<String> messages, \{bool replace = false\}\)',
          ),
        ),
      );
    });

    test('empty sanitized is a no-op even with replace: true', () {
      expect(
        _applyOriginProgressUpdate(['keep'], ['  ', '', '\t'], replace: true),
        ['keep'],
      );
      expect(_applyOriginProgressUpdate([], ['   '], replace: true), isEmpty);
    });

    test('trim and drop empties before write', () {
      expect(_applyOriginProgressUpdate([], ['  hello  ', '', '  ']), [
        'hello',
      ]);
    });

    test('empty current lines behave like replace', () {
      expect(_applyOriginProgressUpdate([], ['a', 'b']), ['a', 'b']);
      expect(_applyOriginProgressUpdate(['old'], ['a', 'b'], replace: true), [
        'a',
        'b',
      ]);
    });

    test('non-empty current appends when replace is false', () {
      expect(_applyOriginProgressUpdate(['hello'], ['world']), [
        'hello',
        'world',
      ]);
    });
  });

  group('progress dialog + snack sinks stay on the host State', () {
    test('_closeProgressDialog returns immediately when not open', () {
      expect(host, contains('void _closeProgressDialog()'));
      expect(
        host,
        contains(
          'if (!_progressOpen) {\n'
          '      return;\n'
          '    }',
        ),
      );
    });

    test('_showSnack no-ops when unmounted; blueGrey; 3 seconds', () {
      expect(
        host,
        contains(
          'void _showSnack(String message, {Color color = Colors.blueGrey})',
        ),
      );
      expect(host, contains('if (!mounted) return;'));
      expect(host, contains('duration: const Duration(seconds: 3),'));
    });
  });
}
