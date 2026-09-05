import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/playback/subtitle_track_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Lib-call pin of `SubtitleTrackController` **before** the V1-fix move.
///
/// Existing `subtitle_track_controller_pin_test.dart` only greps source.
/// This file imports and calls the unit (gate h).
void main() {
  test('normalisedSubtitleContentType: only series stays series', () {
    expect(normalisedSubtitleContentType('series'), 'series');
    expect(normalisedSubtitleContentType('Series'), 'series');
    expect(normalisedSubtitleContentType('movie'), 'movie');
    expect(normalisedSubtitleContentType('tv'), 'movie');
  });

  test('subtitleSearchDisplayLabel adds year and SxEy for series', () {
    const show = StremioMeta(
      id: 'tt1',
      type: 'series',
      name: 'Show',
      year: '2020',
    );
    expect(
      subtitleSearchDisplayLabel(
        show,
        contentType: 'series',
        season: 1,
        episode: 2,
      ),
      'Show (2020) S1E2',
    );
    const film = StremioMeta(id: 'tt2', type: 'movie', name: 'Film', year: '  ');
    expect(
      subtitleSearchDisplayLabel(film, contentType: 'movie', season: 1, episode: 2),
      'Film',
    );
  });

  test('subtitlePreferenceMatchesAttempt: no / uri / embedded ladders', () {
    final noTrack = SubtitleApplyAttempt(
      generation: 1,
      requested: mk.SubtitleTrack.no(),
      previous: mk.SubtitleTrack.no(),
      source: 'test',
      previousStremioId: null,
      previousExternalPath: null,
    );
    expect(subtitlePreferenceMatchesAttempt('no', noTrack), isTrue);
    expect(subtitlePreferenceMatchesAttempt('2', noTrack), isFalse);

    final uri = SubtitleApplyAttempt(
      generation: 1,
      requested: mk.SubtitleTrack.uri('file:///tmp/a.srt'),
      previous: mk.SubtitleTrack.no(),
      source: 'test',
      previousStremioId: 'abc',
      previousExternalPath: '/tmp/a.srt',
    );
    expect(subtitlePreferenceMatchesAttempt('stremio:abc', uri), isTrue);
    expect(subtitlePreferenceMatchesAttempt('2', uri), isFalse);
  });
}
