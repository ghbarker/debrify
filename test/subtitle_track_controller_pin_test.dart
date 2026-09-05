import 'dart:io';

import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pin of subtitle/track restore + addon-fetch *before* `SubtitleTrackController`.
///
/// Origin: `lib/screens/video_player_screen.dart`
/// `_waitForSubtitleTracks` / `_setSubtitleTrackWithDiagnostics` (~3887–4065)
/// and `_resetSubtitleState` through `_subtitlePreferenceMatchesAttempt`
/// (~13718–14445), plus the identify-title **fetch tail**
/// (`_identifyTitleAndFetchSubtitles`) and `_subtitleIdentityLabelForSheet`.
///
/// This file must not import `subtitle_track_controller.dart`.
///
/// Decision ladders are transcribed from the origin and source-locked. After
/// the move the same bodies live on the extracted file; this pin must keep
/// passing without edits (gate h).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final origin = _subtitleOriginSource();

  group('stored subtitle id is a choice (origin _restoreTrackPreferences)', () {
    test('null / empty / auto are no-choice and take the default-language path', () {
      expect(_originStoredSubtitleIsChoice(null), isFalse);
      expect(_originStoredSubtitleIsChoice(''), isFalse);
      expect(_originStoredSubtitleIsChoice('auto'), isFalse);
      expect(
        _originRestoreSubtitlePath(subtitleTrackId: 'auto', trackExists: true),
        _OriginRestoreSubtitlePath.defaultLanguage,
      );
      expect(
        origin,
        contains("subtitleTrackId != 'auto'"),
      );
      expect(
        origin,
        contains(
          "stored subtitle id=\$subtitleTrackId treated as no-choice → default-language path",
        ),
      );
    });

    test('stored id missing from this file falls through to default-language', () {
      expect(
        _originRestoreSubtitlePath(subtitleTrackId: '2', trackExists: false),
        _OriginRestoreSubtitlePath.defaultLanguage,
      );
      expect(
        origin,
        contains(
          'stored subtitle id=\$subtitleTrackId not in this file → default-language path',
        ),
      );
    });

    test('stored id that exists is applied unless it conflicts with default lang', () {
      expect(
        _originRestoreSubtitlePath(subtitleTrackId: '2', trackExists: true),
        _OriginRestoreSubtitlePath.applyStored,
      );
      expect(
        _originRestoreSubtitlePath(
          subtitleTrackId: '2',
          trackExists: true,
          conflictsWithDefault: true,
        ),
        _OriginRestoreSubtitlePath.defaultLanguage,
      );
      expect(
        origin,
        contains('conflicts with default=\$defaultLang → default-language path'),
      );
    });

    test('stored no is never a default-language conflict', () {
      expect(
        _originStoredSubtitleConflictsWithDefault(
          subtitleTrackId: 'no',
          defaultLang: 'off',
          trackLanguage: null,
          trackTitle: null,
        ),
        isFalse,
      );
      expect(
        _originStoredSubtitleConflictsWithDefault(
          subtitleTrackId: '2',
          defaultLang: 'off',
          trackLanguage: 'eng',
          trackTitle: 'English',
        ),
        isTrue,
      );
      expect(origin, contains("subtitleTrackId != 'no'"));
    });

    test('bare mpv ordinal is stale when language no longer matches default', () {
      expect(
        _originStoredSubtitleConflictsWithDefault(
          subtitleTrackId: '3',
          defaultLang: 'es',
          trackLanguage: 'eng',
          trackTitle: 'English',
        ),
        isTrue,
      );
      expect(
        _originStoredSubtitleConflictsWithDefault(
          subtitleTrackId: '3',
          defaultLang: 'en',
          trackLanguage: 'eng',
          trackTitle: 'SDH',
        ),
        isFalse,
      );
      expect(
        origin,
        contains('the ids are bare mpv ordinals'),
      );
    });
  });

  group('track preference keying (origin restore + persist)', () {
    test('series playlist uses series title for the whole series', () {
      expect(
        _originTrackPrefTarget(
          hasSeriesPlaylist: true,
          isSeries: true,
          seriesTitle: 'The Show',
          videoTitle: 'The.Show.S01E01.mkv',
        ),
        (series: true, title: 'The Show'),
      );
      expect(
        _originTrackPrefTarget(
          hasSeriesPlaylist: true,
          isSeries: true,
          seriesTitle: null,
          videoTitle: 'x',
        ),
        (series: true, title: 'Unknown Series'),
      );
      expect(origin, contains("seriesPlaylist.seriesTitle ?? 'Unknown Series'"));
    });

    test('non-series uses video title, empty → Unknown Video', () {
      expect(
        _originTrackPrefTarget(
          hasSeriesPlaylist: false,
          isSeries: false,
          seriesTitle: null,
          videoTitle: 'Movie.mkv',
        ),
        (series: false, title: 'Movie.mkv'),
      );
      expect(
        _originTrackPrefTarget(
          hasSeriesPlaylist: true,
          isSeries: false,
          seriesTitle: 'Collection',
          videoTitle: '',
        ),
        (series: false, title: 'Unknown Video'),
      );
      expect(origin, contains('widget.title.isNotEmpty'));
      expect(origin, contains("'Unknown Video'"));
    });
  });

  group('addon auto-select (origin _fetchAndMaybeAutoSelectAddonSubtitle)', () {
    test('no IMDb aborts before fetch', () {
      expect(
        _originAddonAutoSelectDecision(imdbId: null),
        _OriginAddonAutoSelect.abortNoImdb,
      );
      expect(
        _originAddonAutoSelectDecision(imdbId: ''),
        _OriginAddonAutoSelect.abortNoImdb,
      );
      expect(origin, contains('ABORT — no IMDB ID for addon subtitle fetch'));
    });

    test('embedded applied / user manual / empty / off skip auto-select', () {
      expect(
        _originAddonAutoSelectDecision(imdbId: 'tt1', embeddedApplied: true),
        _OriginAddonAutoSelect.skipEmbedded,
      );
      expect(
        _originAddonAutoSelectDecision(imdbId: 'tt1', userManual: true),
        _OriginAddonAutoSelect.skipManual,
      );
      expect(
        _originAddonAutoSelectDecision(imdbId: 'tt1', subtitleCount: 0),
        _OriginAddonAutoSelect.skipEmpty,
      );
      expect(
        _originAddonAutoSelectDecision(imdbId: 'tt1', defaultLang: 'off'),
        _OriginAddonAutoSelect.skipOff,
      );
      expect(origin, contains('SKIP — embedded subtitle already applied'));
      expect(origin, contains('SKIP — user manually selected a subtitle this session'));
      expect(origin, contains('SKIP — subtitles set to off'));
    });

    test('no preference defaults the match target to English', () {
      expect(_originAddonTargetLang(null), 'en');
      expect(_originAddonTargetLang('fr'), 'fr');
      expect(origin, contains("final targetLang = defaultLang ?? 'en'"));
    });

    test('cache key is imdb:season:episode when both S/E are present', () {
      expect(_originAddonCacheKey('tt1', null, null), 'tt1');
      expect(_originAddonCacheKey('tt1', 1, null), 'tt1');
      expect(_originAddonCacheKey('tt1', 1, 2), 'tt1:1:2');
      expect(
        origin,
        contains(r"'$imdbId:$season:$episode'"),
      );
    });
  });

  group('persist match (origin _subtitlePreferenceMatchesAttempt)', () {
    test('no-track apply matches only persisted no', () {
      expect(
        _originSubtitlePreferenceMatchesAttempt(
          subtitle: 'no',
          requestedId: 'no',
          requestedUri: false,
          requestedData: false,
        ),
        isTrue,
      );
      expect(
        _originSubtitlePreferenceMatchesAttempt(
          subtitle: '2',
          requestedId: 'no',
          requestedUri: false,
          requestedData: false,
        ),
        isFalse,
      );
      expect(origin, contains("if (attempt.requested.id == 'no') return subtitle == 'no'"));
    });

    test('uri/data apply matches any stremio: persist id', () {
      expect(
        _originSubtitlePreferenceMatchesAttempt(
          subtitle: 'stremio:abc',
          requestedId: 'file',
          requestedUri: true,
          requestedData: false,
        ),
        isTrue,
      );
      expect(
        _originSubtitlePreferenceMatchesAttempt(
          subtitle: '2',
          requestedId: 'file',
          requestedUri: true,
          requestedData: false,
        ),
        isFalse,
      );
      expect(origin, contains("return subtitle.startsWith('stremio:')"));
    });

    test('embedded apply matches the requested id', () {
      expect(
        _originSubtitlePreferenceMatchesAttempt(
          subtitle: '3',
          requestedId: '3',
          requestedUri: false,
          requestedData: false,
        ),
        isTrue,
      );
      expect(
        _originSubtitlePreferenceMatchesAttempt(
          subtitle: '2',
          requestedId: '3',
          requestedUri: false,
          requestedData: false,
        ),
        isFalse,
      );
    });
  });

  group('identity helpers left for V1-3', () {
    test('only series stays series; everything else is movie', () {
      expect(_originNormalisedContentType('series'), 'series');
      expect(_originNormalisedContentType('Series'), 'series');
      expect(_originNormalisedContentType('movie'), 'movie');
      expect(_originNormalisedContentType('tv'), 'movie');
      expect(
        origin,
        contains("type.toLowerCase() == 'series' ? 'series' : 'movie'"),
      );
    });

    test('display label adds year and SxEy for series', () {
      expect(
        _originSubtitleSearchDisplayLabel(
          name: 'Show',
          year: '2020',
          contentType: 'series',
          season: 1,
          episode: 2,
        ),
        'Show (2020) S1E2',
      );
      expect(
        _originSubtitleSearchDisplayLabel(
          name: 'Film',
          year: '  ',
          contentType: 'movie',
          season: 1,
          episode: 2,
        ),
        'Film',
      );
      expect(origin, contains(r"'$title S${season}E$episode'"));
    });

    test('sheet label prefers manual Subtitles for, else Detected, else null', () {
      expect(
        _originSubtitleIdentityLabelForSheet(
          manualLabel: 'Show (2020) S1E01',
          detectedTitle: 'Other',
        ),
        'Subtitles for Show (2020) S1E01',
      );
      expect(
        _originSubtitleIdentityLabelForSheet(
          manualLabel: '  ',
          detectedTitle: 'Detected Title',
        ),
        'Detected: Detected Title',
      );
      expect(
        _originSubtitleIdentityLabelForSheet(
          manualLabel: null,
          detectedTitle: '',
        ),
        isNull,
      );
      expect(origin, contains("return 'Subtitles for \$manualLabel'"));
      expect(origin, contains("return 'Detected: \$detectedTitle'"));
    });

    test('identify fetch rejects IMDb ids that are not tt…', () {
      expect(_originIdentifyImdbUsable(null), isFalse);
      expect(_originIdentifyImdbUsable('nm123'), isFalse);
      expect(_originIdentifyImdbUsable('tt123'), isTrue);
      expect(origin, contains("!imdbId.startsWith('tt')"));
      expect(origin, contains('Selected title has no IMDb ID'));
    });
  });

  group('wait + android reject (origin _waitForSubtitleTracks / set diagnostics)', () {
    test('auto and no are not real tracks; empty id is not real either', () {
      expect(_originHasRealSubtitleTracks(['auto', 'no']), isFalse);
      expect(_originHasRealSubtitleTracks(['auto', 'no', '']), isFalse);
      expect(_originHasRealSubtitleTracks(['auto', '2']), isTrue);
      expect(
        origin,
        contains("t.id != 'auto' && t.id != 'no' && t.id.isNotEmpty"),
      );
    });

    test('android bitmap reject only when not TV and not direct MediaCodec', () {
      expect(
        _originAndroidBitmapReject(
          isAndroid: true,
          isAndroidTv: false,
          requiresNative: true,
          directMediaCodec: false,
        ),
        isTrue,
      );
      expect(
        _originAndroidBitmapReject(
          isAndroid: true,
          isAndroidTv: true,
          requiresNative: true,
          directMediaCodec: false,
        ),
        isFalse,
      );
      expect(
        _originAndroidBitmapReject(
          isAndroid: true,
          isAndroidTv: false,
          requiresNative: true,
          directMediaCodec: true,
        ),
        isFalse,
      );
      expect(
        origin,
        contains('Bitmap subtitles require MediaCodec + GPU'),
      );
    });

    test('temp download writes a file so libmpv can detect encoding', () {
      expect(
        origin,
        contains("via `http.Response.body` would silently corrupt"),
      );
      expect(origin, contains('stremio_sub_'));
      expect(origin, contains('_cleanupTempSubtitleFilesSync'));
    });
  });
}

/// Bodies live on the god file until the move; after the move they live on
/// the controller. The pin must keep passing without edits (gate h).
String _subtitleOriginSource() {
  for (final path in [
    'lib/screens/video_player/subtitle_track_controller.dart',
    'lib/services/playback/subtitle_track_controller.dart',
  ]) {
    final moved = File(path);
    if (moved.existsSync()) return moved.readAsStringSync();
  }
  return File('lib/screens/video_player_screen.dart').readAsStringSync();
}

bool _originStoredSubtitleIsChoice(String? subtitleTrackId) {
  return subtitleTrackId != null &&
      subtitleTrackId.isNotEmpty &&
      subtitleTrackId != 'auto';
}

enum _OriginRestoreSubtitlePath { applyStored, defaultLanguage }

_OriginRestoreSubtitlePath _originRestoreSubtitlePath({
  required String? subtitleTrackId,
  required bool trackExists,
  bool conflictsWithDefault = false,
}) {
  if (subtitleTrackId != null &&
      subtitleTrackId.isNotEmpty &&
      subtitleTrackId != 'auto') {
    if (trackExists) {
      if (conflictsWithDefault) {
        return _OriginRestoreSubtitlePath.defaultLanguage;
      }
      return _OriginRestoreSubtitlePath.applyStored;
    }
    return _OriginRestoreSubtitlePath.defaultLanguage;
  }
  return _OriginRestoreSubtitlePath.defaultLanguage;
}

bool _originStoredSubtitleConflictsWithDefault({
  required String subtitleTrackId,
  required String? defaultLang,
  required String? trackLanguage,
  required String? trackTitle,
}) {
  return subtitleTrackId != 'no' &&
      defaultLang != null &&
      (defaultLang == 'off' ||
          !(LanguageMapper.matchesLanguage(defaultLang, trackLanguage) ||
              LanguageMapper.matchesLanguage(defaultLang, trackTitle)));
}

({bool series, String title}) _originTrackPrefTarget({
  required bool hasSeriesPlaylist,
  required bool isSeries,
  required String? seriesTitle,
  required String videoTitle,
}) {
  if (hasSeriesPlaylist && isSeries) {
    return (series: true, title: seriesTitle ?? 'Unknown Series');
  }
  return (
    series: false,
    title: videoTitle.isNotEmpty ? videoTitle : 'Unknown Video',
  );
}

enum _OriginAddonAutoSelect {
  abortNoImdb,
  skipEmbedded,
  skipManual,
  skipEmpty,
  skipOff,
  match,
}

_OriginAddonAutoSelect _originAddonAutoSelectDecision({
  required String? imdbId,
  bool embeddedApplied = false,
  bool userManual = false,
  int subtitleCount = 2,
  String? defaultLang = 'en',
}) {
  if (imdbId == null || imdbId.isEmpty) {
    return _OriginAddonAutoSelect.abortNoImdb;
  }
  if (embeddedApplied) return _OriginAddonAutoSelect.skipEmbedded;
  if (userManual) return _OriginAddonAutoSelect.skipManual;
  if (subtitleCount == 0) return _OriginAddonAutoSelect.skipEmpty;
  if (defaultLang == 'off') return _OriginAddonAutoSelect.skipOff;
  return _OriginAddonAutoSelect.match;
}

String _originAddonTargetLang(String? defaultLang) => defaultLang ?? 'en';

String _originAddonCacheKey(String imdbId, int? season, int? episode) {
  return season != null && episode != null ? '$imdbId:$season:$episode' : imdbId;
}

bool _originSubtitlePreferenceMatchesAttempt({
  required String subtitle,
  required String requestedId,
  required bool requestedUri,
  required bool requestedData,
}) {
  if (requestedId == 'no') return subtitle == 'no';
  if (requestedUri || requestedData) {
    return subtitle.startsWith('stremio:');
  }
  return subtitle == requestedId;
}

String _originNormalisedContentType(String type) =>
    type.toLowerCase() == 'series' ? 'series' : 'movie';

String _originSubtitleSearchDisplayLabel({
  required String name,
  String? year,
  required String contentType,
  int? season,
  int? episode,
}) {
  final trimmedYear = year?.trim();
  final title = trimmedYear != null && trimmedYear.isNotEmpty
      ? '$name ($trimmedYear)'
      : name;
  if (contentType == 'series' && season != null && episode != null) {
    return '$title S${season}E$episode';
  }
  return title;
}

String? _originSubtitleIdentityLabelForSheet({
  required String? manualLabel,
  required String detectedTitle,
}) {
  final trimmed = manualLabel?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return 'Subtitles for $trimmed';
  }
  if (detectedTitle.isEmpty) return null;
  return 'Detected: $detectedTitle';
}

bool _originIdentifyImdbUsable(String? imdbId) =>
    imdbId != null && imdbId.startsWith('tt');

bool _originHasRealSubtitleTracks(Iterable<String> ids) =>
    ids.any((id) => id != 'auto' && id != 'no' && id.isNotEmpty);

bool _originAndroidBitmapReject({
  required bool isAndroid,
  required bool isAndroidTv,
  required bool requiresNative,
  required bool directMediaCodec,
}) {
  return isAndroid &&
      !isAndroidTv &&
      requiresNative &&
      !directMediaCodec;
}
