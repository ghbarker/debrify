import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/utils/movie_parser.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pin of the identify-title sheet *before* `identify_title_sheet.dart` exists.
///
/// Origin: `lib/screens/video_player_screen.dart`
/// `_identitySearchInitialQuery` through `_showIdentifyTitleSearchSheet`
/// (~13066–13520 after V1-1) plus `_requestSeasonEpisodeForIdentity`.
/// This file must not import `identify_title_sheet.dart`.
///
/// Filter / query / poster / subtitle decisions are the origin if-ladders,
/// executed here and source-locked. After the move the same bodies live on
/// the extracted file; this pin must keep passing without edits (gate h).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final origin = _identifyOriginSource();

  group('initial query (origin _identitySearchInitialQuery)', () {
    test('series parser title wins when the filename is a series', () {
      const raw = 'Show.Name.S01E02.1080p.mkv';
      final series = SeriesParser.parseFilename(raw);
      expect(series.isSeries, isTrue);
      expect(series.title?.trim(), isNotEmpty);
      expect(_originIdentitySearchInitialQuery(raw), series.title!.trim());
      expect(origin, contains('final seriesInfo = SeriesParser.parseFilename(rawTitle);'));
      expect(
        origin,
        contains(
          'if (seriesInfo.isSeries && seriesTitle != null && seriesTitle.isNotEmpty)',
        ),
      );
    });

    test('movie parser title wins when there is no series hit', () {
      const raw = 'The.Movie.2020.1080p.mkv';
      final series = SeriesParser.parseFilename(raw);
      expect(series.isSeries, isFalse);
      final movie = MovieParser.parseFilename(raw);
      expect(movie.title?.trim(), isNotEmpty);
      expect(_originIdentitySearchInitialQuery(raw), movie.title!.trim());
      expect(origin, contains('final movieInfo = MovieParser.parseFilename(rawTitle);'));
    });

    test('no series/movie title strips video extension and [._]+ to spaces', () {
      const raw = 'Some_File.Name.mkv';
      expect(SeriesParser.parseFilename(raw).isSeries, isFalse);
      expect(MovieParser.parseFilename(raw).title, isNull);
      expect(_originIdentitySearchInitialQuery(raw), 'Some File Name');
      expect(
        origin,
        contains(
          r"r'\.(mkv|mp4|avi|mov|wmv|flv|webm|m4v|ts|mpg|mpeg)$'",
        ),
      );
      expect(origin, contains("replaceAll(RegExp(r'[._]+'), ' ')"));
    });
  });

  group('filter (origin _filterIdentitySearchResults)', () {
    test('drops metas without a tt IMDb id', () {
      final kept = _originFilterIdentitySearchResults([
        const StremioMeta(id: 'x', type: 'movie', name: 'No id'),
        const StremioMeta(
          id: 'tt1',
          imdbId: 'nm123',
          type: 'movie',
          name: 'Wrong prefix',
        ),
        const StremioMeta(
          id: 'tt2',
          imdbId: 'tt7654321',
          type: 'movie',
          name: 'Kept',
        ),
      ]);
      expect(kept.map((m) => m.name), ['Kept']);
      expect(origin, contains("if (imdbId == null || !imdbId.startsWith('tt')) continue;"));
    });

    test('keeps only movie and series types', () {
      final kept = _originFilterIdentitySearchResults([
        const StremioMeta(
          id: 'tt1',
          imdbId: 'tt1',
          type: 'channel',
          name: 'Live',
        ),
        const StremioMeta(
          id: 'tt2',
          imdbId: 'tt2',
          type: 'tv',
          name: 'Tv',
        ),
        const StremioMeta(
          id: 'tt3',
          imdbId: 'tt3',
          type: 'Movie',
          name: 'Film',
        ),
        const StremioMeta(
          id: 'tt4',
          imdbId: 'tt4',
          type: 'SERIES',
          name: 'Show',
        ),
      ]);
      expect(kept.map((m) => m.name).toList()..sort(), ['Film', 'Show']);
      expect(origin, contains("if (type != 'movie' && type != 'series') continue;"));
    });

    test('same IMDb as movie and series both survive (key is type:imdb)', () {
      final kept = _originFilterIdentitySearchResults([
        const StremioMeta(
          id: 'tt9',
          imdbId: 'tt9',
          type: 'movie',
          name: 'As movie',
        ),
        const StremioMeta(
          id: 'tt9',
          imdbId: 'tt9',
          type: 'series',
          name: 'As series',
        ),
      ]);
      expect(kept.map((m) => m.name).toSet(), {'As movie', 'As series'});
      expect(origin, contains(r"final key = '$type:$imdbId';"));
    });

    test('poster scores 2, year scores 1; first wins a tie', () {
      final first = const StremioMeta(
        id: 'tt1',
        imdbId: 'tt1',
        type: 'movie',
        name: 'First',
        year: '1999',
      );
      final poster = const StremioMeta(
        id: 'tt1',
        imdbId: 'tt1',
        type: 'movie',
        name: 'Poster',
        poster: 'https://p/a.jpg',
      );
      final both = const StremioMeta(
        id: 'tt1',
        imdbId: 'tt1',
        type: 'movie',
        name: 'Both',
        poster: 'https://p/b.jpg',
        year: '2001',
      );

      expect(
        _originFilterIdentitySearchResults([first, poster]).single.name,
        'Poster',
      );
      expect(
        _originFilterIdentitySearchResults([poster, both]).single.name,
        'Both',
      );
      expect(
        _originFilterIdentitySearchResults([first, first]).single.name,
        'First',
      );
      expect(
        origin,
        contains('(existing.poster != null ? 2 : 0) + (existing.year != null ? 1 : 0)'),
      );
    });
  });

  group('poster + tile subtitle', () {
    test('// protocol-relative becomes https:; blank is null', () {
      expect(_originNormalisePosterUrl(null), isNull);
      expect(_originNormalisePosterUrl(''), isNull);
      expect(_originNormalisePosterUrl('   '), isNull);
      expect(_originNormalisePosterUrl('//cdn.example/p.jpg'), 'https://cdn.example/p.jpg');
      expect(
        _originNormalisePosterUrl('https://cdn.example/p.jpg'),
        'https://cdn.example/p.jpg',
      );
      expect(origin, contains("if (url.startsWith('//')) return 'https:\$url';"));
    });

    test('non-series types label Movie; blank year/addon omitted', () {
      expect(
        _originIdentityMetaSubtitle(
          const StremioMeta(id: 'a', type: 'channel', name: 'X'),
        ),
        'Movie',
      );
      expect(
        _originIdentityMetaSubtitle(
          const StremioMeta(
            id: 'b',
            type: 'series',
            name: 'Y',
            year: '  ',
          ),
        ),
        'Series',
      );
      expect(
        _originIdentityMetaSubtitle(
          const StremioMeta(
            id: 'c',
            type: 'movie',
            name: 'Z',
            year: '2018',
            sourceAddon: null,
          ),
        ),
        'Movie | 2018',
      );

      final addon = StremioAddon(
        id: 'cine',
        name: 'Cinemeta',
        manifestUrl: 'https://example/manifest.json',
        baseUrl: 'https://example',
      );
      expect(
        _originIdentityMetaSubtitle(
          StremioMeta(
            id: 'd',
            type: 'series',
            name: 'W',
            year: '2011',
            sourceAddon: addon,
          ),
        ),
        'Series | 2011 | Cinemeta',
      );
      expect(
        origin,
        contains("meta.type.toLowerCase() == 'series' ? 'Series' : 'Movie'"),
      );
    });
  });

  group('sheet grammar (origin _showIdentifyTitleSearchSheet)', () {
    test('right-side glass panel, not a Material bottom sheet', () {
      expect(
        origin,
        contains(
          '// Right-side glass panel (the player menu\'s grammar) rather than the old',
        ),
      );
      expect(origin, contains("'FIX THE TITLE'"));
      expect(origin, contains("'Search movie or show'"));
      expect(origin, contains("'Search failed. Try again.'"));
      expect(origin, contains("'No IMDb-backed results found'"));
    });

    test('empty query resets hasSearched; suffix search does not arm TV focus', () {
      expect(origin, contains('hasSearched = false;'));
      expect(
        origin,
        contains('searchSubmitFocus.arm(enabled: PlatformUtil.isTelevision);'),
      );
      expect(
        origin,
        contains('onPressed: () => runSearch('),
      );
      expect(origin, contains('onSubmitted: (value) =>'));
    });

    test('compact <720 is full width; else 46% clamped 430–560', () {
      expect(origin, contains('final compact = screenSize.width < 720;'));
      expect(
        origin,
        contains('(screenSize.width * 0.46).clamp(430.0, 560.0)'),
      );
    });

    test('Android TV panel is opaque 0xF5101012', () {
      expect(origin, contains('const Color(0xF5101012)'));
      expect(
        origin,
        contains('const Color(0xFF101012).withValues(alpha: 0.86)'),
      );
    });

    test('seam returns StremioMeta from showGeneralDialog', () {
      expect(origin, contains('showGeneralDialog<StremioMeta>('));
      expect(origin, contains('Navigator.of(context).pop(meta)'));
    });
  });

  group('season/episode dialog (origin _requestSeasonEpisodeForIdentity)', () {
    test('Apply rejects season/episode <= 0 or unparseable', () {
      expect(_originSeasonEpisodeValid(seasonText: '1', episodeText: '2'), isTrue);
      expect(_originSeasonEpisodeValid(seasonText: '0', episodeText: '1'), isFalse);
      expect(_originSeasonEpisodeValid(seasonText: '1', episodeText: '0'), isFalse);
      expect(_originSeasonEpisodeValid(seasonText: '-1', episodeText: '1'), isFalse);
      expect(_originSeasonEpisodeValid(seasonText: 's1', episodeText: '2'), isFalse);
      expect(origin, contains("'Enter a valid season and episode.'"));
      expect(origin, contains("'Which episode?'"));
    });
  });
}

/// Bodies live on the god file until the move; after the move they live on
/// the extracted sheet. The pin must keep passing without edits (gate h).
String _identifyOriginSource() {
  final parts = <String>[];
  final moved = File('lib/widgets/player/identify_title_sheet.dart');
  if (moved.existsSync()) {
    parts.add(moved.readAsStringSync());
  }
  parts.add(File('lib/screens/video_player_screen.dart').readAsStringSync());
  return parts.join('\n');
}

/// Origin `_identitySearchInitialQuery`.
String _originIdentitySearchInitialQuery(String rawTitle) {
  final seriesInfo = SeriesParser.parseFilename(rawTitle);
  final seriesTitle = seriesInfo.title?.trim();
  if (seriesInfo.isSeries && seriesTitle != null && seriesTitle.isNotEmpty) {
    return seriesTitle;
  }

  final movieInfo = MovieParser.parseFilename(rawTitle);
  final movieTitle = movieInfo.title?.trim();
  if (movieTitle != null && movieTitle.isNotEmpty) {
    return movieTitle;
  }

  return rawTitle
      .replaceAll(
        RegExp(
          r'\.(mkv|mp4|avi|mov|wmv|flv|webm|m4v|ts|mpg|mpeg)$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Origin `_filterIdentitySearchResults`.
List<StremioMeta> _originFilterIdentitySearchResults(List<StremioMeta> metas) {
  final bestByKey = <String, StremioMeta>{};

  for (final meta in metas) {
    final imdbId = meta.effectiveImdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) continue;

    final type = meta.type.toLowerCase();
    if (type != 'movie' && type != 'series') continue;

    final key = '$type:$imdbId';
    final existing = bestByKey[key];
    if (existing == null) {
      bestByKey[key] = meta;
      continue;
    }

    final existingScore =
        (existing.poster != null ? 2 : 0) + (existing.year != null ? 1 : 0);
    final newScore =
        (meta.poster != null ? 2 : 0) + (meta.year != null ? 1 : 0);
    if (newScore > existingScore) {
      bestByKey[key] = meta;
    }
  }

  return bestByKey.values.toList(growable: false);
}

/// Origin `_normalisePosterUrl`.
String? _originNormalisePosterUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  if (url.startsWith('//')) return 'https:$url';
  return url;
}

/// Origin `_identityMetaSubtitle`.
String _originIdentityMetaSubtitle(StremioMeta meta) {
  final parts = <String>[
    meta.type.toLowerCase() == 'series' ? 'Series' : 'Movie',
    if (meta.year != null && meta.year!.trim().isNotEmpty) meta.year!,
    if (meta.sourceAddon?.name.trim().isNotEmpty == true)
      meta.sourceAddon!.name,
  ];
  return parts.join(' | ');
}

/// Origin Apply button in `_requestSeasonEpisodeForIdentity`.
bool _originSeasonEpisodeValid({
  required String seasonText,
  required String episodeText,
}) {
  final season = int.tryParse(seasonText.trim());
  final episode = int.tryParse(episodeText.trim());
  if (season == null ||
      season <= 0 ||
      episode == null ||
      episode <= 0) {
    return false;
  }
  return true;
}
