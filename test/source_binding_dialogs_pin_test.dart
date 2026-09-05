import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

/// G1'-2 characterisation of the source edit/add dialogs **before**
/// the move out of `search_screen.dart`.
///
/// Pin commit must stay green on its own and must not import
/// `source_binding_dialogs.dart`. After the move this file still matches
/// the same bodies (it reads the new file when that file exists).
///
/// Quirks pinned here (keep, do not "fix"):
/// * Movie vs not-movie is `item.type == 'movie'` — any other type
///   (series, tv, …) gets the series dialog (reorder, "Add Source",
///   "Series Sources (N)", Remove All when count > 1).
/// * Edit with a null IMDb or empty `initial` returns without opening
///   the add picker.
/// * Series subtitle is "First match wins — reorder by priority".
/// * Reorder: `if (newIndex > oldIndex) newIndex--;` then
///   `setSources` is not awaited.
/// * Last-source delete uses `closeIfEmpty` on the **dialog** route
///   (callback, not a captured BuildContext). Remove All / movie Remove
///   pop themselves after `removeAllSources`.
/// * Change/Add pops the edit dialog, then opens the add picker.
/// * No-IMDb add picker snacks
///   `No IMDb match to pin a source for "${item.name}".`
/// * No cloud providers and no local option → skip picker, torrent search.
/// * Movie save replaces (`setSources([source])`); series appends
///   (`addSource`). Same split for local pick.
/// * Navigator is captured before the API-key awaits.
/// * Dialog chrome: max 450×500, slate `0xFF1E293B`, link `0xFF60A5FA`,
///   indigo `0xFF6366F1`.
///
/// Origin: `lib/screens/search_screen.dart` `_showEditSourceDialog`,
/// `_showAddSourcePicker`, `_pickAndSaveLocalSource`,
/// `_buildSourceListTile` (~10686–11188).
String _origin() {
  final moved = File('lib/widgets/sources/source_binding_dialogs.dart');
  if (moved.existsSync()) return moved.readAsStringSync();
  final host = File('lib/screens/search_screen.dart').readAsStringSync();
  final start = host.indexOf('Future<void> _showEditSourceDialog(');
  final end = host.indexOf('Future<void> _addToStremioTvFromDetail(');
  if (start < 0 || end < 0 || end <= start) {
    throw StateError('G1\'-2 origin region not found in search_screen.dart');
  }
  return host.substring(start, end);
}

StremioMeta _meta({
  required String id,
  required String type,
  String? imdbId,
  String name = 'Title',
}) => StremioMeta(id: id, imdbId: imdbId, type: type, name: name);

/// Origin `_imdbOf` — empty string and non-`tt` catalog ids are null.
String? imdbOf(StremioMeta item) {
  final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return (id != null && id.isNotEmpty) ? id : null;
}

/// Origin `isMovie = item.type == 'movie'`.
bool isMovieMeta(StremioMeta item) => item.type == 'movie';

/// Origin edit-dialog title.
String editDialogTitle(StremioMeta item, int sourceCount) =>
    isMovieMeta(item) ? 'Movie Source' : 'Series Sources ($sourceCount)';

/// Origin Change Source / Add Source label.
String addOrChangeLabel(StremioMeta item) =>
    isMovieMeta(item) ? 'Change Source' : 'Add Source';

/// Origin Remove All visibility.
bool showRemoveAll(StremioMeta item, int sourceCount) =>
    !isMovieMeta(item) && sourceCount > 1;

/// Origin skip-picker: no cloud keys and no local option.
bool skipAddPicker({
  required bool rdEnabled,
  required bool torboxEnabled,
  required bool premiumizeEnabled,
  required bool allDebridEnabled,
  required bool pikpakEnabled,
  required bool supportsLocal,
}) =>
    !rdEnabled &&
    !torboxEnabled &&
    !premiumizeEnabled &&
    !allDebridEnabled &&
    !pikpakEnabled &&
    !supportsLocal;

/// Origin ReorderableListView `onReorder` index adjust.
int reorderInsertIndex(int oldIndex, int newIndex) {
  if (newIndex > oldIndex) newIndex--;
  return newIndex;
}

/// Origin movie replaces the list; series appends.
bool movieReplacesSources(StremioMeta item) => item.type == 'movie';

void main() {
  late String origin;

  setUpAll(() {
    origin = _origin();
  });

  group('origin source (G1\'-2 pin)', () {
    test('movie vs series chrome and first-match-wins copy stay', () {
      expect(origin, contains("'Movie Source'"));
      expect(origin, contains("'Series Sources (\${sources.length})'"));
      expect(origin, contains("'First match wins — reorder by priority'"));
      expect(origin, contains("'Change Source'"));
      expect(origin, contains("'Add Source'"));
      expect(origin, contains('Icons.swap_horiz_rounded'));
      expect(origin, contains('Icons.add_rounded'));
      expect(origin, contains('ReorderableListView.builder'));
      expect(origin, contains('if (newIndex > oldIndex) newIndex--;'));
    });

    test('remove / closeIfEmpty / empty-initial early return stay', () {
      expect(origin, contains("'Remove All'"));
      expect(origin, contains("'Remove'"));
      expect(origin, contains('closeIfEmpty'));
      expect(origin, contains('if (updated.isEmpty) closeIfEmpty()'));
      expect(origin, contains('if (sources.isEmpty) return;'));
      expect(origin, contains('pops the dialog via its OWN route'));
    });

    test('add-picker skip, no-IMDb snack, and movie/series save stay', () {
      expect(origin, contains('No IMDb match to pin a source for "'));
      expect(origin, contains('No cloud providers and no local option'));
      expect(origin, contains('Capture the navigator before the awaits'));
      expect(
        origin,
        contains('SeriesSourceService.setSources(imdbId, [source])'),
      );
      expect(origin, contains('SeriesSourceService.addSource(imdbId, source)'));
      expect(origin, contains('Local source set: \${source.torrentName}'));
      expect(origin, contains('showAddSourcePickerDialog'));
    });

    test('dialog constraints and chrome colors stay', () {
      expect(origin, contains('maxWidth: 450'));
      expect(origin, contains('maxHeight: 500'));
      expect(origin, contains('Color(0xFF1E293B)'));
      expect(origin, contains('Color(0xFF60A5FA)'));
      expect(origin, contains('Color(0xFF6366F1)'));
      expect(origin, contains('item.type == \'movie\''));
    });

    test('does not invent a new Mode enum; G1\'-0 board types stay public', () {
      expect(origin, isNot(contains(RegExp(r'enum Mode \{'))));
      final host = File('lib/screens/search_screen.dart').readAsStringSync();
      expect(
        host,
        contains('enum SearchBoardMode { catalog, keyword, lists }'),
      );
      final cwTypes = File(
        'lib/services/home/continue_watching_controller.dart',
      );
      expect(
        (cwTypes.existsSync()
                ? cwTypes
                : File('lib/screens/search/search_stage_widgets.dart'))
            .readAsStringSync(),
        contains('enum CwKind { local, trakt, simkl, mdblist, iptv }'),
      );
    });
  });

  group('pure decision tables (origin algorithm)', () {
    test('imdbOf requires a tt id or non-empty imdbId', () {
      expect(imdbOf(_meta(id: 'tt0101', type: 'movie')), 'tt0101');
      expect(
        imdbOf(_meta(id: 'kitsu:1', type: 'movie', imdbId: 'tt0101')),
        'tt0101',
      );
      expect(imdbOf(_meta(id: 'kitsu:1', type: 'movie')), isNull);
      expect(imdbOf(_meta(id: 'tt0101', type: 'movie', imdbId: '')), isNull);
      expect(imdbOf(_meta(id: 'iptv:7', type: 'tv')), isNull);
    });

    test('non-movie types get series chrome (type == movie only)', () {
      final movie = _meta(id: 'tt1', type: 'movie', name: 'Film');
      final series = _meta(id: 'tt2', type: 'series', name: 'Show');
      final tv = _meta(id: 'tt3', type: 'tv', name: 'News');
      expect(editDialogTitle(movie, 1), 'Movie Source');
      expect(editDialogTitle(series, 2), 'Series Sources (2)');
      expect(editDialogTitle(tv, 1), 'Series Sources (1)');
      expect(addOrChangeLabel(movie), 'Change Source');
      expect(addOrChangeLabel(series), 'Add Source');
      expect(addOrChangeLabel(tv), 'Add Source');
      expect(showRemoveAll(movie, 3), isFalse);
      expect(showRemoveAll(series, 1), isFalse);
      expect(showRemoveAll(series, 2), isTrue);
      expect(movieReplacesSources(movie), isTrue);
      expect(movieReplacesSources(series), isFalse);
      expect(movieReplacesSources(tv), isFalse);
    });

    test('skip picker only when every cloud and local option is off', () {
      expect(
        skipAddPicker(
          rdEnabled: false,
          torboxEnabled: false,
          premiumizeEnabled: false,
          allDebridEnabled: false,
          pikpakEnabled: false,
          supportsLocal: false,
        ),
        isTrue,
      );
      expect(
        skipAddPicker(
          rdEnabled: true,
          torboxEnabled: false,
          premiumizeEnabled: false,
          allDebridEnabled: false,
          pikpakEnabled: false,
          supportsLocal: false,
        ),
        isFalse,
      );
      expect(
        skipAddPicker(
          rdEnabled: false,
          torboxEnabled: false,
          premiumizeEnabled: false,
          allDebridEnabled: false,
          pikpakEnabled: false,
          supportsLocal: true,
        ),
        isFalse,
      );
    });

    test('reorder index shrinks when moving down the list', () {
      expect(reorderInsertIndex(0, 2), 1);
      expect(reorderInsertIndex(2, 0), 0);
      expect(reorderInsertIndex(1, 1), 1);
    });
  });
}
