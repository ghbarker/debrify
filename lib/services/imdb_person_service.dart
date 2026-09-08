import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/stremio_addon.dart';

/// A person from IMDb and the titles IMDb lists them as "known for".
class ImdbPerson {
  /// IMDb name id, e.g. "nm0000209".
  final String nameId;
  final String name;
  final String? imageUrl;

  /// Known-for titles, already shaped like recommendations so the same
  /// opener that handles "More Like This" can open them: `id` is the IMDb id
  /// and `type` is 'movie' or 'series'.
  final List<StremioMeta> knownFor;

  const ImdbPerson({
    required this.nameId,
    required this.name,
    this.imageUrl,
    required this.knownFor,
  });
}

/// Fetches a person's known-for titles from IMDb's GraphQL endpoint.
///
/// Same endpoint and request shape as [ImdbEnrichmentService]; the person is
/// keyed by the `name.id` the enrichment query now carries on every cast
/// credit. Never throws — a failed or malformed fetch logs and returns null.
class ImdbPersonService {
  static const String _endpoint = 'https://graphql.imdb.com/';

  static const String _query = r'''
    query KnownFor($id: ID!) {
      name(id: $id) {
        id
        nameText { text }
        primaryImage { url }
        knownFor(first: 24) {
          edges {
            node {
              title {
                id
                titleText { text }
                primaryImage { url }
                releaseYear { year }
                titleType { id }
                ratingsSummary { aggregateRating }
              }
            }
          }
        }
      }
    }
  ''';

  static final Map<String, ImdbPerson> _cache = {};

  @visibleForTesting
  static void debugClearCache() => _cache.clear();

  static Future<ImdbPerson?> fetchKnownFor(String nameId) async {
    if (nameId.isEmpty) return null;

    final cached = _cache[nameId];
    if (cached != null) return cached;

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0',
          // See ImdbEnrichmentService: the edge 403s without an imdb.com
          // referer.
          'Referer': 'https://www.imdb.com/',
        },
        body: json.encode({
          'query': _query,
          'variables': {'id': nameId},
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('ImdbPerson: HTTP ${response.statusCode} for $nameId');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final person = parse(data, nameId);
      if (person == null) {
        debugPrint('ImdbPerson: no name payload for $nameId');
        return null;
      }
      _cache[nameId] = person;
      return person;
    } catch (e) {
      debugPrint('ImdbPerson: failed for $nameId: $e');
      return null;
    }
  }

  /// Maps a decoded GraphQL response body to an [ImdbPerson]. Pure, so it is
  /// what the fixture tests exercise. Null when the body carries no `name`.
  static ImdbPerson? parse(Map<String, dynamic> body, String nameId) {
    final name = (body['data'] as Map?)?['name'] as Map?;
    if (name == null) return null;

    final text = (name['nameText'] as Map?)?['text'] as String?;
    final imageUrl = (name['primaryImage'] as Map?)?['url'] as String?;
    final edges = (name['knownFor'] as Map?)?['edges'] as List? ?? const [];

    final titles = <StremioMeta>[];
    final seen = <String>{};
    for (final edge in edges) {
      final title = ((edge as Map?)?['node'] as Map?)?['title'] as Map?;
      if (title == null) continue;
      final id = title['id'] as String?;
      final titleText = (title['titleText'] as Map?)?['text'] as String?;
      if (id == null || id.isEmpty || titleText == null) continue;
      if (!seen.add(id)) continue;
      final year = (title['releaseYear'] as Map?)?['year'];
      final rating = (title['ratingsSummary'] as Map?)?['aggregateRating'];
      titles.add(
        StremioMeta(
          id: id,
          imdbId: id,
          type: typeFor((title['titleType'] as Map?)?['id'] as String?),
          name: titleText,
          poster: (title['primaryImage'] as Map?)?['url'] as String?,
          year: year is num ? '${year.toInt()}' : null,
          imdbRating: rating is num ? rating.toDouble() : null,
        ),
      );
    }

    return ImdbPerson(
      nameId: (name['id'] as String?) ?? nameId,
      name: text ?? '',
      imageUrl: imageUrl,
      knownFor: titles,
    );
  }

  /// IMDb `titleType.id` → Stremio type. Series-shaped ids become 'series';
  /// everything else (movie, tvMovie, video, short, …) opens as a movie.
  static String typeFor(String? titleTypeId) => switch (titleTypeId) {
    'tvSeries' || 'tvMiniSeries' => 'series',
    _ => 'movie',
  };
}
