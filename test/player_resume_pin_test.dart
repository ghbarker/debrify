import 'dart:io';

import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pin of the Flutter player's resume path *before* `ResumeController` exists.
///
/// Origin: `lib/screens/video_player_screen.dart` `_resumeKey` through
/// `_saveResume` (~10229–10958 after V1-0). This file must not import
/// `resume_controller.dart`.
///
/// Key grammar is executed through [VideoPlayerLauncher.resumeIdForEntry]
/// (the public twin of `_resumeIdForEntry`) and through the player's own
/// string-compare helpers transcribed below; the origin source is required
/// to still contain those helpers. Restore / save / seek-guard decisions
/// are the origin if-ladders, executed here and source-locked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final origin = _resumeOriginSource();

  group('resume key grammar (origin _resumeIdForEntry / _resumeKey)', () {
    test('torbox web download wins over torrent id', () {
      final entry = PlaylistEntry(
        url: 'https://tb/a',
        title: 'Show.S01E01.mkv',
        provider: 'TorBox',
        torboxTorrentId: 11,
        torboxWebDownloadId: 22,
        torboxFileId: 33,
      );
      expect(
        _originTorboxResumeKeyForEntry(entry),
        'torbox_web_22_33',
      );
      expect(
        VideoPlayerLauncher.resumeIdForEntry(entry),
        'torbox_web_22_33',
      );
      expect(origin, contains("return 'torbox_web_\${webDownloadId}_\$fileId'"));
    });

    test('torbox torrent+file key when web id is missing', () {
      final entry = PlaylistEntry(
        url: 'https://tb/b',
        title: 'Show.S01E02.mkv',
        provider: 'torbox',
        torboxTorrentId: 11,
        torboxFileId: 33,
      );
      expect(_originTorboxResumeKeyForEntry(entry), 'torbox_11_33');
      expect(VideoPlayerLauncher.resumeIdForEntry(entry), 'torbox_11_33');
      expect(origin, contains("return 'torbox_\${torrentId}_\$fileId'"));
    });

    test('torbox without file id falls through to filename hash', () {
      final entry = PlaylistEntry(
        url: 'https://tb/c',
        title: 'Show.S01E03.mkv',
        provider: 'torbox',
        torboxTorrentId: 11,
      );
      expect(_originTorboxResumeKeyForEntry(entry), isNull);
      expect(
        _originResumeIdForEntry(entry, fallbackTitle: 'Ignored'),
        _originFilenameHash('Show.S01E03.mkv'),
      );
      expect(origin, contains('ResumeKey: torbox entry missing IDs'));
    });

    test('player keys torbox only via provider.toLowerCase() == torbox', () {
      final other = PlaylistEntry(
        url: 'https://x',
        title: 'Movie.mkv',
        provider: 'realdebrid',
        torboxTorrentId: 1,
        torboxFileId: 2,
      );
      expect(_originTorboxResumeKeyForEntry(other), isNull);
      expect(origin, contains("if (provider == 'torbox')"));
    });

    test('pikpak file id key; empty file id falls through to hash', () {
      final keyed = PlaylistEntry(
        url: 'https://pk/a',
        title: 'Film.mkv',
        provider: 'PikPak',
        pikpakFileId: 'file-9',
      );
      expect(_originPikpakResumeKeyForEntry(keyed), 'pikpak_file-9');
      expect(VideoPlayerLauncher.resumeIdForEntry(keyed), 'pikpak_file-9');

      final empty = PlaylistEntry(
        url: 'https://pk/b',
        title: 'Film.mkv',
        provider: 'pikpak',
        pikpakFileId: '',
      );
      expect(_originPikpakResumeKeyForEntry(empty), isNull);
      expect(
        _originResumeIdForEntry(empty, fallbackTitle: 'Fallback'),
        _originFilenameHash('Film.mkv'),
      );
      expect(origin, contains("return 'pikpak_\$fileId'"));
    });

    test('empty entry title uses fallback title for the hash', () {
      final entry = const PlaylistEntry(url: 'https://x', title: '');
      expect(
        _originResumeIdForEntry(entry, fallbackTitle: 'Launch Title.mp4'),
        _originFilenameHash('Launch Title.mp4'),
      );
      expect(
        origin,
        contains('entry.title.isNotEmpty ? entry.title :'),
      );
    });

    test('_resumeKey prefers playlist entry, then IPTV url, then videoUrl', () {
      expect(
        origin,
        contains('// Note: This is the expected path for Debrify TV mode'),
      );
      expect(
        origin,
        contains(
          "// channel in the session to the URL the player was OPENED with — zap to",
        ),
      );
    });
  });

  group('restore target (origin _maybeRestoreResume)', () {
    test('auto-advance and manual-without-progress skip restore', () {
      expect(_originShouldRestoreResume(isAutoAdvancing: true), isFalse);
      expect(
        _originShouldRestoreResume(
          isManualEpisodeSelection: true,
          allowResumeForManualSelection: false,
        ),
        isFalse,
      );
      expect(
        _originShouldRestoreResume(
          isManualEpisodeSelection: true,
          allowResumeForManualSelection: true,
        ),
        isTrue,
      );
      expect(origin, contains('If this is auto-advancing, don\'t restore position'));
      expect(
        origin,
        contains("Don't reset _isManualEpisodeSelection here"),
      );
    });

    test('preferLocalResume seeks any in-range position, even past 90%', () {
      const durMs = 100000;
      // 93% — past the normal hiMs window.
      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: 93000,
          traktMs: 10000,
          preferLocalResume: true,
        ),
        93000,
      );
      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: 0,
          traktMs: 50000,
          preferLocalResume: true,
        ),
        isNull,
      );
      expect(origin, contains('if (preferLocalResume)'));
      expect(
        origin,
        contains('if (localMs > 0 && localMs < dur.inMilliseconds)'),
      );
    });

    test('explicit launch tracker percent wins outright when seekable', () {
      const durMs = 100000;
      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: 80000,
          traktMs: 25000,
          explicitLaunch: true,
        ),
        25000,
      );
      expect(origin, contains('if (explicitLaunch && traktMs > loMs && traktMs < hiMs)'));
    });

    test('furthest of local and remote wins inside the 2s–90% window', () {
      const durMs = 100000;
      final loMs =
          VideoPlayerTimingConstants.minimumPlaybackPosition.inMilliseconds;
      expect(loMs, 2000);

      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: 40000,
          traktMs: 60000,
        ),
        60000,
      );
      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: 70000,
          traktMs: 20000,
        ),
        70000,
      );
      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: loMs,
          traktMs: 0,
        ),
        isNull,
      );
      expect(
        origin,
        contains('final hiMs = (dur.inMilliseconds * 0.9).floor();'),
      );
    });

    test('local past 90% starts fresh; rewatch zeros a completed local', () {
      const durMs = 100000;
      expect(
        _originChooseResumeTargetMs(
          durationMs: durMs,
          localMs: 95000,
          traktMs: 20000,
        ),
        isNull,
      );
      expect(
        hasActiveTraktEpisodeRewatch(
          traktPercent: 40,
          simklPercent: null,
          mdblistPercent: null,
        ),
        isTrue,
      );
      expect(
        origin,
        contains('if (localMs >= hiMs && localMs > 0) return;'),
      );
      expect(origin, contains('hasActiveTraktEpisodeRewatch('));
    });
  });

  group('save skips (origin _saveResume)', () {
    test('validation gate, unreadiness, IPTV transition, manual debounce', () {
      expect(
        _originShouldSkipSave(validationGateActive: true, isReady: true),
        isTrue,
      );
      expect(
        _originShouldSkipSave(validationGateActive: false, isReady: false),
        isTrue,
      );
      expect(
        _originShouldSkipSave(
          isReady: true,
          iptvActive: true,
          isTransitioning: true,
        ),
        isTrue,
      );
      expect(
        _originShouldSkipSave(
          isReady: true,
          isManualEpisodeSelection: true,
          debounced: true,
        ),
        isTrue,
      );
      expect(
        _originShouldSkipSave(isReady: true, durationMs: 0),
        isTrue,
      );
      expect(
        origin,
        contains('If this is a manual episode selection and it\'s been less than 30 seconds, skip saving'),
      );
      expect(
        origin,
        contains('Nothing is lost by skipping: the next tick saves once the switch lands.'),
      );
    });

    test('held unlanded target at or past duration skips the tick', () {
      expect(
        _originSavePositionMs(
          positionMs: 100,
          durationMs: 50000,
          heldTargetMs: 50000,
        ),
        isNull,
      );
      expect(
        _originSavePositionMs(
          positionMs: 100,
          durationMs: 50000,
          heldTargetMs: 20000,
        ),
        20000,
      );
      expect(origin, contains('if (heldTarget >= dur.inMilliseconds)'));
    });

    test('finished local movie blocks autosave recreate', () {
      expect(
        _originShouldSkipSave(
          isReady: true,
          durationMs: 100000,
          currentMovieMarkedAsFinished: true,
          currentLocalMovieImdbId: 'tt1',
        ),
        isTrue,
      );
      expect(
        origin,
        contains('Do not let the autosave'),
      );
    });

    test('legacy resume store is StorageService.upsertVideoResume', () {
      expect(origin, contains('StorageService.upsertVideoResume('));
      expect(origin, contains('StorageService.getVideoResume('));
      expect(origin, contains('StorageService.saveVideoPlaybackState('));
      expect(origin, contains('StorageService.saveSeriesPlaybackState('));
    });
  });

  group('seek guard (origin _seekForResume)', () {
    test('near-finished (≥80%) is not armed; below 80% is', () {
      expect(_originResumeSeekIsNearFinished(targetMs: 80000, durationMs: 100000), isTrue);
      expect(_originResumeSeekIsNearFinished(targetMs: 79999, durationMs: 100000), isFalse);
      expect(_originResumeSeekIsNearFinished(targetMs: 1, durationMs: 0), isFalse);
      expect(
        origin,
        contains(
          'final nearFinished = durMs > 0 && targetMs >= (durMs * 0.8).floor();',
        ),
      );
    });
  });
}

/// Bodies live on the god file until the move; after the move they live on
/// the controller. The pin must keep passing without edits (gate h).
String _resumeOriginSource() {
  for (final path in [
    'lib/screens/video_player/resume_controller.dart',
    'lib/services/playback/resume_controller.dart',
  ]) {
    final moved = File(path);
    if (moved.existsSync()) return moved.readAsStringSync();
  }
  return File('lib/screens/video_player_screen.dart').readAsStringSync();
}

/// Origin `_torboxResumeKeyForEntry` — string-compare, not the cloud port.
String? _originTorboxResumeKeyForEntry(PlaylistEntry entry) {
  final provider = entry.provider?.toLowerCase();
  if (provider == 'torbox') {
    final torrentId = entry.torboxTorrentId;
    final webDownloadId = entry.torboxWebDownloadId;
    final fileId = entry.torboxFileId;
    if (webDownloadId != null && fileId != null) {
      return 'torbox_web_${webDownloadId}_$fileId';
    }
    if (torrentId != null && fileId != null) {
      return 'torbox_${torrentId}_$fileId';
    }
  }
  return null;
}

/// Origin `_pikpakResumeKeyForEntry`.
String? _originPikpakResumeKeyForEntry(PlaylistEntry entry) {
  final provider = entry.provider?.toLowerCase();
  if (provider == 'pikpak') {
    final fileId = entry.pikpakFileId;
    if (fileId != null && fileId.isNotEmpty) {
      return 'pikpak_$fileId';
    }
  }
  return null;
}

/// Origin `_generateFilenameHash`.
String _originFilenameHash(String filename) {
  final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
  return nameWithoutExt.hashCode.toString();
}

/// Origin `_resumeIdForEntry`.
String _originResumeIdForEntry(
  PlaylistEntry entry, {
  required String fallbackTitle,
}) {
  final torboxKey = _originTorboxResumeKeyForEntry(entry);
  if (torboxKey != null) return torboxKey;
  final pikpakKey = _originPikpakResumeKeyForEntry(entry);
  if (pikpakKey != null) return pikpakKey;
  final name = entry.title.isNotEmpty ? entry.title : fallbackTitle;
  return _originFilenameHash(name);
}

bool _originShouldRestoreResume({
  bool isAutoAdvancing = false,
  bool isManualEpisodeSelection = false,
  bool allowResumeForManualSelection = false,
}) {
  if (isAutoAdvancing) return false;
  if (isManualEpisodeSelection && !allowResumeForManualSelection) {
    return false;
  }
  return true;
}

/// Origin `_maybeRestoreResume` target after local/trakt ms are known.
///
/// `null` means start fresh / no seek. Rewatch zeroing of [localMs] is
/// applied by the caller before this, matching the origin order.
int? _originChooseResumeTargetMs({
  required int durationMs,
  required int localMs,
  required int traktMs,
  bool preferLocalResume = false,
  bool explicitLaunch = false,
}) {
  if (preferLocalResume) {
    if (localMs > 0 && localMs < durationMs) return localMs;
    return null;
  }
  final loMs =
      VideoPlayerTimingConstants.minimumPlaybackPosition.inMilliseconds;
  final hiMs = (durationMs * 0.9).floor();
  if (explicitLaunch && traktMs > loMs && traktMs < hiMs) {
    return traktMs;
  }
  if (localMs >= hiMs && localMs > 0) return null;
  final traktCand = (traktMs > loMs && traktMs < hiMs) ? traktMs : 0;
  final localCand = (localMs > loMs && localMs < hiMs) ? localMs : 0;
  final target = traktCand > localCand ? traktCand : localCand;
  return target > 0 ? target : null;
}

bool _originShouldSkipSave({
  bool validationGateActive = false,
  bool isReady = true,
  bool iptvActive = false,
  bool isTransitioning = false,
  bool isManualEpisodeSelection = false,
  bool debounced = false,
  int durationMs = 100000,
  bool currentMovieMarkedAsFinished = false,
  String? currentLocalMovieImdbId,
}) {
  if (validationGateActive || !isReady) return true;
  if (iptvActive && isTransitioning) return true;
  if (isManualEpisodeSelection && debounced) return true;
  if (durationMs <= 0) return true;
  if (currentMovieMarkedAsFinished && currentLocalMovieImdbId != null) {
    return true;
  }
  return false;
}

/// Origin persist position after the write-guard check. `null` = skip tick.
int? _originSavePositionMs({
  required int positionMs,
  required int durationMs,
  int? heldTargetMs,
}) {
  if (heldTargetMs != null) {
    if (heldTargetMs >= durationMs) return null;
    return heldTargetMs;
  }
  return positionMs;
}

bool _originResumeSeekIsNearFinished({
  required int targetMs,
  required int durationMs,
}) {
  return durationMs > 0 && targetMs >= (durationMs * 0.8).floor();
}
