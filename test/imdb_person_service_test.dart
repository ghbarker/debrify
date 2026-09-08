import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/imdb_person_service.dart';

/// Shape of IMDb's `name(id:) { knownFor }` reply, verified against the live
/// endpoint: each edge nests the title under `node.title`.
Map<String, dynamic> _fixture() => {
  'data': {
    'name': {
      'id': 'nm0000209',
      'nameText': {'text': 'Tim Robbins'},
      'primaryImage': {'url': 'https://img/tim.jpg'},
      'knownFor': {
        'edges': [
          {
            'node': {
              'title': {
                'id': 'tt0111161',
                'titleText': {'text': 'The Shawshank Redemption'},
                'primaryImage': {'url': 'https://img/shawshank.jpg'},
                'releaseYear': {'year': 1994},
                'titleType': {'id': 'movie'},
                'ratingsSummary': {'aggregateRating': 9.3},
              },
            },
          },
          {
            'node': {
              'title': {
                'id': 'tt2364582',
                'titleText': {'text': 'Castle Rock'},
                'primaryImage': null,
                'releaseYear': {'year': 2018},
                'titleType': {'id': 'tvSeries'},
                'ratingsSummary': {'aggregateRating': 7},
              },
            },
          },
          {
            'node': {
              'title': {
                'id': 'tt1234567',
                'titleText': {'text': 'A Miniseries'},
                'releaseYear': null,
                'titleType': {'id': 'tvMiniSeries'},
                'ratingsSummary': null,
              },
            },
          },
          // Duplicate id: IMDb occasionally lists the same title twice.
          {
            'node': {
              'title': {
                'id': 'tt0111161',
                'titleText': {'text': 'The Shawshank Redemption'},
                'titleType': {'id': 'movie'},
              },
            },
          },
          // Missing id: unopenable, so dropped.
          {
            'node': {
              'title': {
                'titleText': {'text': 'Ghost'},
                'titleType': {'id': 'movie'},
              },
            },
          },
        ],
      },
    },
  },
};

void main() {
  group('ImdbPersonService.parse', () {
    test('maps the person and known-for titles to StremioMetas', () {
      final person = ImdbPersonService.parse(_fixture(), 'nm0000209')!;
      expect(person.nameId, 'nm0000209');
      expect(person.name, 'Tim Robbins');
      expect(person.imageUrl, 'https://img/tim.jpg');

      expect(person.knownFor.map((m) => m.id), [
        'tt0111161',
        'tt2364582',
        'tt1234567',
      ]);

      final movie = person.knownFor[0];
      expect(movie.type, 'movie');
      expect(movie.imdbId, 'tt0111161');
      expect(movie.name, 'The Shawshank Redemption');
      expect(movie.poster, 'https://img/shawshank.jpg');
      expect(movie.year, '1994');
      expect(movie.imdbRating, 9.3);

      final series = person.knownFor[1];
      expect(series.type, 'series');
      expect(series.poster, isNull);
      expect(series.year, '2018');
      expect(series.imdbRating, 7.0);

      final mini = person.knownFor[2];
      expect(mini.type, 'series');
      expect(mini.year, isNull);
      expect(mini.imdbRating, isNull);
    });

    test('titleType → Stremio type', () {
      expect(ImdbPersonService.typeFor('tvSeries'), 'series');
      expect(ImdbPersonService.typeFor('tvMiniSeries'), 'series');
      expect(ImdbPersonService.typeFor('movie'), 'movie');
      expect(ImdbPersonService.typeFor('tvMovie'), 'movie');
      expect(ImdbPersonService.typeFor(null), 'movie');
    });

    test('a body without a name payload is null, never a throw', () {
      expect(
        ImdbPersonService.parse({
          'data': {'name': null},
        }, 'nm1'),
        isNull,
      );
      expect(ImdbPersonService.parse({}, 'nm1'), isNull);
      expect(
        ImdbPersonService.parse({
          'errors': [
            {'message': 'nope'},
          ],
        }, 'nm1'),
        isNull,
      );
    });

    test('a name with no knownFor edges is a person with no titles', () {
      final person = ImdbPersonService.parse({
        'data': {
          'name': {
            'nameText': {'text': 'Nobody'},
          },
        },
      }, 'nm2')!;
      expect(person.nameId, 'nm2', reason: 'falls back to the requested id');
      expect(person.name, 'Nobody');
      expect(person.knownFor, isEmpty);
    });
  });
}
