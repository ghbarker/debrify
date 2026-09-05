import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search/keyword_search_screen.dart';
import 'package:debrify/screens/search/keyword_search_controller.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Follow-up origin-path pin for G1'-3 / #90.
///
/// The merge pin (`keyword_search_pin_test.dart`) only grepped source text
/// and re-implemented helpers in the test file. Gate (h) requires a widget
/// test that drives [KeywordSearchScreen] / [KeywordSearchController] in lib.
///
/// Quirks exercised here (keep; do not "fix"):
/// * Empty query surfaces Sources + the "Keyword torrent search" prompt.
/// * `kwError` paints "Search failed" and the controller message.
/// * Empty `kwAll` after a query is "No results"; nonempty `kwAll` with
///   empty `kwResults` is "No matches".
/// * A controller notify rebuilds the screen State (the extracted listener).
class _Probe extends KeywordSearchController {
  void paint({
    String query = '',
    String? error,
    List<Torrent> all = const [],
    List<Torrent> results = const [],
  }) {
    kwQuery = query;
    kwError = error;
    kwAll = List<Torrent>.of(all);
    kwResults = List<Torrent>.of(results);
    kwLoading = false;
    notifyListeners();
  }
}

Torrent _t(String name) => Torrent(
  rowid: 0,
  infohash: 'abc',
  name: name,
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 1,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'tb',
);

Future<void> _pump(
  WidgetTester tester,
  _Probe controller, {
  Future<void> Function()? onOpenSources,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          AppThemeScope(theme: AppThemes.legacy, child: child!),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: KeywordSearchScreen(
            controller: controller,
            isTelevision: false,
            onOpenStream: (context, torrent, sources, index, keyword) {},
            onBulkAdd: (context, torrents, keyword) async => false,
            onOpenSources: onOpenSources ?? () async {},
            onFocusSearchField: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('empty query shows Sources and the keyword prompt', (
    tester,
  ) async {
    final c = _Probe();
    var opened = 0;
    await _pump(tester, c, onOpenSources: () async {
      opened++;
    });

    expect(find.text('Keyword torrent search'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(
      find.textContaining('Type a title and press search'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sources'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('controller notify paints Search failed on the screen State', (
    tester,
  ) async {
    final c = _Probe();
    await _pump(tester, c);
    expect(find.text('Search failed'), findsNothing);

    c.paint(error: 'all engines errored');
    await tester.pump();

    expect(find.text('Search failed'), findsOneWidget);
    expect(find.text('all engines errored'), findsOneWidget);
    expect(find.text('Keyword torrent search'), findsNothing);
  });

  testWidgets('query with empty all is No results; filtered empty is No matches', (
    tester,
  ) async {
    final c = _Probe();
    await _pump(tester, c);

    c.paint(query: 'dune');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    expect(find.textContaining('Nothing found for'), findsOneWidget);

    c.paint(query: 'dune', all: [_t('Dune 2021')]);
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.textContaining('match your filters'), findsOneWidget);
  });
}
