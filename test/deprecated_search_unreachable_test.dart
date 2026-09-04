import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins that the legacy Home board (`TorrentSearchScreen`) and `CatalogBrowser`
/// are not live-routed. Construction and imports in `lib/screens/deprecated/`
/// and in `catalog_browser.dart` itself are ignored; commented-out lines are
/// stripped so the old `main.dart` commented import does not count.
void main() {
  test('deprecated torrent search is not imported or routed from live navigation',
      () {
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      if (rel.contains('/deprecated/')) continue;
      if (rel == 'lib/widgets/catalog_browser.dart') continue;
      final code = _code(file);
      if (RegExp(r"""import\s+['"][^'"]*torrent_search_screen\.dart['"]""")
          .hasMatch(code)) {
        offenders.add('$rel imports torrent_search_screen.dart');
      }
      if (RegExp(r"""import\s+['"][^'"]*catalog_browser\.dart['"]""")
          .hasMatch(code)) {
        offenders.add('$rel imports catalog_browser.dart');
      }
      if (RegExp(r'(?<![A-Za-z0-9_])TorrentSearchScreen\s*\(').hasMatch(code)) {
        offenders.add('$rel constructs TorrentSearchScreen');
      }
      if (RegExp(r'(?<![A-Za-z0-9_])CatalogBrowser\s*\(').hasMatch(code)) {
        offenders.add('$rel constructs CatalogBrowser');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'legacy torrent search / CatalogBrowser still reachable from live '
          'lib/: $offenders',
    );
  });
}

final String _root = Directory.current.path;

Iterable<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _rel(File f) {
  final path = f.path.replaceAll(r'\', '/');
  final root = _root.replaceAll(r'\', '/');
  return path.startsWith('$root/') ? path.substring(root.length + 1) : path;
}

String _code(File f) => f
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');
