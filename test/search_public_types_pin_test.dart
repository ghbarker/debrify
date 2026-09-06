import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G1'-0 characterisation of the Home/Search board types **before** they
/// drop their library-private underscore. Pin commit must stay green on
/// its own (does not import a not-yet-created file).
///
/// Quirks pinned here (keep, do not "fix"):
/// * Board mode values stay catalog / keyword / lists.
/// * Continue-watching kinds stay local / trakt / simkl / mdblist / iptv.
/// * Favourites kinds stay watchlistMovies / watchlistSeries / iptv /
///   debrify / stremio / playlist.
/// * `_FavRowRef` is value-equal on `(kind, list)` with `list == -1` for
///   singleton rows and `isIptvList` when `list >= 0`.
/// * `_ArtPosterState` stays the private State class of the poster widget.
///
/// After the rename this suite still matches the same members (optional
/// leading underscore, or the `SearchBoardMode` domain name if `Mode`
/// collides).
String _host() => File('lib/screens/search_screen.dart').readAsStringSync();

String _stageWidgets() =>
    File('lib/screens/search/search_stage_widgets.dart').readAsStringSync();

/// G1'-4 moved `CwKind` / `CwRow` onto the controller. Fall back to the
/// stage part so the G1'-0 pin commit still reads.
String _cwTypes() {
  final controller = File('lib/screens/search/continue_watching_controller.dart')
          .existsSync()
      ? File('lib/screens/search/continue_watching_controller.dart')
      : File('lib/services/home/continue_watching_controller.dart');
  if (controller.existsSync()) return controller.readAsStringSync();
  return _stageWidgets();
}

String _cardWidgets() =>
    File('lib/screens/search/favourite_art_cell.dart').readAsStringSync();

void main() {
  late String host;
  late String cards;

  setUpAll(() {
    host = _host();
    cards = _cardWidgets();
  });

  group('board type shapes (G1\'-0 pin)', () {
    test('mode enum is catalog / keyword / lists', () {
      expect(
        host,
        contains(
          RegExp(
            r'enum (_Mode|Mode|SearchBoardMode) \{ catalog, keyword, lists \}',
          ),
        ),
      );
    });

    test('continue-watching kinds stay local / trakt / simkl / mdblist / iptv', () {
      expect(
        _cwTypes(),
        contains(
          RegExp(
            r'enum _?CwKind \{ local, trakt, simkl, mdblist, iptv \}',
          ),
        ),
      );
    });

    test('CwRow carries kind, items, nodes, progress and remove', () {
      final cw = _cwTypes();
      expect(cw, contains(RegExp(r'class _?CwRow \{')));
      expect(cw, contains(RegExp(r'final _?CwKind kind;')));
      expect(cw, contains('final List<StremioMeta> items;'));
      expect(cw, contains('final List<FocusNode> nodes;'));
      expect(
        cw,
        contains('final double? Function(StremioMeta) progressOf;'),
      );
      expect(
        cw,
        contains('final Future<void> Function(StremioMeta) onRemove;'),
      );
    });

    test('favourites kinds stay the six leading-row values', () {
      final favourites = File(
        'lib/screens/search/fav_row_ref.dart',
      ).readAsStringSync();
      expect(
        host,
        contains("export 'search/fav_row_ref.dart' show FavKind, FavRowRef;"),
      );
      expect(
        favourites,
        contains(
          RegExp(
            r'enum _?FavKind \{\s*'
            r'watchlistMovies,\s*'
            r'watchlistSeries,\s*'
            r'iptv,\s*'
            r'debrify,\s*'
            r'stremio,\s*'
            r'playlist,\s*'
            r'\}',
          ),
        ),
      );
    });

    test('FavRowRef is value-equal on kind + list; IPTV lists use list >= 0', () {
      final favourites = File(
        'lib/screens/search/fav_row_ref.dart',
      ).readAsStringSync();
      expect(favourites, contains(RegExp(r'class _?FavRowRef \{')));
      expect(favourites, contains(RegExp(r'final _?FavKind kind;')));
      expect(favourites, contains('final int list;'));
      expect(
        favourites,
        contains(RegExp(r'const _?FavRowRef\(this\.kind, \[this\.list = -1\]\);')),
      );
      expect(favourites, contains('bool get isIptvList => list >= 0;'));
      expect(
        favourites,
        contains(
          RegExp(
            r'other is _?FavRowRef && other\.kind == kind && other\.list == list',
          ),
        ),
      );
    });

    test('FavArtCell is a StatelessWidget; ArtPoster is a StatefulWidget', () {
      expect(
        cards,
        contains(RegExp(r'class _?FavArtCell extends StatelessWidget \{')),
      );
      expect(
        cards,
        contains(RegExp(r'class _?ArtPoster extends StatefulWidget \{')),
      );
      expect(
        cards,
        contains(
          RegExp(r'State<_?ArtPoster> createState\(\) => _ArtPosterState\(\);'),
        ),
      );
      expect(
        cards,
        contains(
          RegExp(r'class _ArtPosterState extends State<_?ArtPoster> \{'),
        ),
      );
    });
  });
}
