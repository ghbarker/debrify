import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/widgets/sources/source_binding_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StremioMeta _meta({
  required String id,
  required String type,
  String? imdbId,
  String name = 'Title',
}) => StremioMeta(id: id, imdbId: imdbId, type: type, name: name);

SeriesSource _source(String name, {String hash = 'h1'}) => SeriesSource(
  torrentHash: hash,
  torrentName: name,
  debridService: 'realdebrid',
  debridTorrentId: '1',
  boundAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('new file has no host-State private member access', () {
    final src = File(
      'lib/widgets/sources/source_binding_dialogs.dart',
    ).readAsStringSync();
    expect(src, isNot(contains(RegExp(r'^part of ', multiLine: true))));
    expect(src, isNot(contains('extension on _SearchScreenState')));
    for (final member in [
      '_imdbOf',
      '_refreshBoundSources',
      '_snack',
      '_openBindSources',
      '_openKeywordBind',
      '_showAddSourcePicker',
      '_pickAndSaveLocalSource',
      '_handleEditOrSelectSource',
      '_SearchScreenState',
    ]) {
      expect(src.contains(RegExp('$member\\b')), isFalse, reason: member);
    }
  });

  test('imdbOf matches origin _imdbOf', () {
    expect(
      SourceBindingDialogs.imdbOf(_meta(id: 'tt0101', type: 'movie')),
      'tt0101',
    );
    expect(
      SourceBindingDialogs.imdbOf(
        _meta(id: 'kitsu:1', type: 'movie', imdbId: 'tt0101'),
      ),
      'tt0101',
    );
    expect(
      SourceBindingDialogs.imdbOf(_meta(id: 'kitsu:1', type: 'movie')),
      isNull,
    );
    expect(
      SourceBindingDialogs.imdbOf(
        _meta(id: 'tt0101', type: 'movie', imdbId: ''),
      ),
      isNull,
    );
  });

  testWidgets('edit dialog: movie chrome, no first-match-wins, Remove', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SourceBindingDialogs.showEdit(
              context: context,
              item: _meta(
                id: 'tt1',
                type: 'movie',
                imdbId: 'tt1',
                name: 'Film',
              ),
              initial: [_source('Film.1080p')],
              onRefreshBound: () async {},
              onTorrentSearch: (_) {},
              onKeywordSearch: (_) {},
              onSnack: (_) {},
              isHostMounted: () => true,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Movie Source'), findsOneWidget);
    expect(find.text('Change Source'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Remove All'), findsNothing);
    expect(find.text('First match wins — reorder by priority'), findsNothing);
    expect(find.text('Film.1080p'), findsOneWidget);
  });

  testWidgets('edit dialog: series chrome, first-match-wins, Remove All', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SourceBindingDialogs.showEdit(
              context: context,
              item: _meta(
                id: 'tt2',
                type: 'series',
                imdbId: 'tt2',
                name: 'Show',
              ),
              initial: [
                _source('Show.S01', hash: 'a'),
                _source('Show.S02', hash: 'b'),
              ],
              onRefreshBound: () async {},
              onTorrentSearch: (_) {},
              onKeywordSearch: (_) {},
              onSnack: (_) {},
              isHostMounted: () => true,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Series Sources (2)'), findsOneWidget);
    expect(find.text('Add Source'), findsOneWidget);
    expect(find.text('Remove All'), findsOneWidget);
    expect(find.text('First match wins — reorder by priority'), findsOneWidget);
    expect(find.text('Change Source'), findsNothing);
  });

  testWidgets('add picker with no IMDb snacks the origin message', (
    tester,
  ) async {
    String? snack;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SourceBindingDialogs.showAdd(
              context: context,
              item: _meta(id: 'kitsu:1', type: 'movie', name: 'Film'),
              onRefreshBound: () async {},
              onTorrentSearch: (_) {},
              onKeywordSearch: (_) {},
              onSnack: (m) => snack = m,
              isHostMounted: () => true,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(snack, 'No IMDb match to pin a source for "Film".');
    expect(find.text('Add Source'), findsNothing);
  });

  testWidgets('add picker with no cloud keys still opens when local is on', (
    tester,
  ) async {
    var torrent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SourceBindingDialogs.showAdd(
              context: context,
              item: _meta(
                id: 'tt1',
                type: 'movie',
                imdbId: 'tt1',
                name: 'Film',
              ),
              onRefreshBound: () async {},
              onTorrentSearch: (_) => torrent++,
              onKeywordSearch: (_) {},
              onSnack: (_) {},
              isHostMounted: () => true,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Desktop: local binding is enabled, so the picker is not skipped.
    expect(find.text('Torrent Search (IMDb)'), findsOneWidget);
    expect(find.text('Local File or Folder'), findsOneWidget);
    expect(torrent, 0);
  });
}
