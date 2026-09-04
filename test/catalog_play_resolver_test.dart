import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/playback/catalog_play_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

StremioMeta _meta({
  required String id,
  required String type,
  String? imdbId,
  String name = 'Title',
  String? year,
  String? poster,
}) => StremioMeta(
  id: id,
  imdbId: imdbId,
  type: type,
  name: name,
  year: year,
  poster: poster,
);

CatalogPlayResolver _resolver() => CatalogPlayResolver(
  isTraktAuthenticated: () => false,
  isSimklAuthenticated: () => false,
  isMdblistAuthenticated: () => false,
  traktByImdb: const {},
  imdbOf: (item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  },
);

void main() {
  test('movieSelection keeps raw catalog id when there is no tt id', () {
    final sel = _resolver().movieSelection(
      _meta(id: 'iptv:7', type: 'tv', name: 'News'),
      isTraktSource: true,
    );
    expect(sel.imdbId, 'iptv:7');
    expect(sel.isSeries, isFalse);
    expect(sel.traktSource, isTrue);
  });

  test('resumableMoviePercent is [1, 90); MDBList is [1, 80)', () {
    final r = _resolver();
    expect(r.resumableMoviePercent(0.5), isNull);
    expect(r.resumableMoviePercent(1), 1);
    expect(r.resumableMoviePercent(90), isNull);
    expect(r.resumableMdblistPercent(79.9), 79.9);
    expect(r.resumableMdblistPercent(80), isNull);
  });

  test('onCatalogBrowse: series opens episodes; movie is a PlaySelection', () {
    final r = _resolver();
    expect(
      r.onCatalogBrowse(_meta(id: 'tt1', type: 'series')).openEpisodes,
      isTrue,
    );
    final movie = r.onCatalogBrowse(
      _meta(id: 'tt2', type: 'movie', name: 'Film'),
      isMdblistSource: true,
    );
    expect(movie.openEpisodes, isFalse);
    expect(movie.selection?.imdbId, 'tt2');
    expect(movie.selection?.mdblistSource, isTrue);
  });

  test('new file has no host-State private member access', () {
    final src = File(
      'lib/services/playback/catalog_play_resolver.dart',
    ).readAsStringSync();
    expect(src, isNot(contains(RegExp(r"^part of ", multiLine: true))));
    expect(src, isNot(contains('extension on _SearchScreenState')));
    for (final member in [
      '_isTraktAuthenticated',
      '_isSimklAuthenticated',
      '_isMdblistAuthenticated',
      '_traktByImdb',
      '_seriesResumeCache',
      '_traktMoviePctMemo',
      '_activeAddonId',
      '_capturePlayArt',
      '_playSelection',
      '_browseSelection',
      '_openEpisodes',
      '_pendingPlayArt',
    ]) {
      expect(src.contains(RegExp('$member\\b')), isFalse, reason: member);
    }
  });
}
