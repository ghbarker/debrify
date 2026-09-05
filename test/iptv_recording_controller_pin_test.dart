import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pin of IPTV recording *before* `IptvRecordingController`.
///
/// Origin: `lib/screens/video_player_screen.dart`
/// `_recordingFileName` / `_recordingTargetPath` uniquify (~6446–6744),
/// `_toggleRecording` engine-first / desktop / tee ladder (~6188–6359),
/// `_engineRecordUrlForCurrent` / `_playingLiveUrl` (~6362–6407),
/// `_currentRecordingResource` source lookup (~6461–6494).
///
/// This file must not import `iptv_recording_controller.dart`.
///
/// Decision ladders are transcribed from the origin and source-locked. After
/// the move the same bodies live on the extracted file; this pin must keep
/// passing without edits (gate h).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final origin = _recordingOriginSource();

  group('filename sanitizer (origin _recordingFileName)', () {
    test('strips punctuation, collapses spaces, defaults empty to recording', () {
      expect(_originSafeBaseName('BBC One'), 'BBC_One');
      expect(_originSafeBaseName('  CNN  News  '), 'CNN_News');
      expect(_originSafeBaseName('HBO@\$#!'), 'HBO');
      expect(_originSafeBaseName('---'), '---');
      expect(_originSafeBaseName('@@@'), 'recording');
      expect(_originSafeBaseName(''), 'recording');
      expect(origin, contains(r"RegExp(r'[^A-Za-z0-9 _-]')"));
      expect(origin, contains(r"RegExp(r'\s+')"));
      expect(origin, contains("safeName.isEmpty ? 'recording' : safeName"));
    });

    test('truncates the base to 60 characters before the stamp', () {
      final long = 'A' * 80;
      expect(_originSafeBaseName(long).length, 60);
      expect(origin, contains('base.substring(0, 60)'));
    });

    test('engine filename is <base>_<yyyyMMdd_HHmmss>.ts', () {
      final now = DateTime(2026, 9, 5, 12, 7, 8);
      expect(
        _originRecordingFileName('BBC One', now),
        'BBC_One_20260905_120708.ts',
      );
      expect(
        _originRecordingFileName('@@@', now),
        'recording_20260905_120708.ts',
      );
      expect(origin, contains(r"'${base}_$stamp.ts'"));
      expect(origin, contains("two(now.month)"));
    });
  });

  group('target-path uniquify (origin _recordingTargetPath)', () {
    test('default extension is mkv (tee); desktop capture passes ts', () {
      expect(origin, contains("String extension = 'mkv'"));
      expect(origin, contains("extension: 'ts'"));
      expect(
        origin,
        contains("DesktopRecordingService.instance.isSupported"),
      );
    });

    test('existing file steps aside with _2 then _3; 99 collisions use microseconds',
        () async {
      final dir = await Directory.systemTemp.createTemp('v14-rec-pin-');
      addTearDown(() => dir.delete(recursive: true));
      final prefix = '${dir.path}${Platform.pathSeparator}BBC_One_20260905_120708';
      final now = DateTime(2026, 9, 5, 12, 7, 8, 0, 42);

      expect(
        await _originUniquifyCandidate(prefix, 'ts', now),
        '$prefix.ts',
      );

      await File('$prefix.ts').writeAsString('a');
      expect(
        await _originUniquifyCandidate(prefix, 'ts', now),
        '${prefix}_2.ts',
      );

      await File('${prefix}_2.ts').writeAsString('b');
      expect(
        await _originUniquifyCandidate(prefix, 'ts', now),
        '${prefix}_3.ts',
      );

      await File('$prefix.mkv').writeAsString('tee');
      expect(
        await _originUniquifyCandidate(prefix, 'mkv', now),
        '${prefix}_2.mkv',
      );

      for (var n = 2; n < 100; n++) {
        await File('${prefix}_$n.ts').writeAsString('$n');
      }
      expect(
        await _originUniquifyCandidate(prefix, 'ts', now),
        '${prefix}_${now.microsecondsSinceEpoch}.ts',
      );

      expect(
        origin,
        contains('for (var n = 2; n < 100 && await File(candidate).exists(); n++)'),
      );
      expect(
        origin,
        contains(r"'${prefix}_${now.microsecondsSinceEpoch}.$extension'"),
      );
    });
  });

  group('engine-first / desktop / tee (origin _toggleRecording)', () {
    test('desktop capture of the current channel stops first', () {
      expect(
        _originToggleDecision(desktopCaptureCurrent: true),
        _OriginTogglePath.stopDesktop,
      );
      expect(origin, contains('final desktopCapture = _desktopCaptureForCurrent()'));
    });

    test('engine task of the current channel stops next', () {
      expect(
        _originToggleDecision(engineTaskPresent: true),
        _OriginTogglePath.stopEngine,
      );
      expect(origin, contains('final engineTask = _engineTaskId'));
    });

    test('tee stream-record stops when neither service owns the capture', () {
      expect(
        _originToggleDecision(teeRecording: true),
        _OriginTogglePath.stopTee,
      );
      expect(origin, contains('if (_isRecording)'));
    });

    test('Android + engine flag + supported starts the engine when URL exists', () {
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
        ),
        _OriginTogglePath.startEngine,
      );
      expect(
        origin,
        contains('Platform.isAndroid && _engineFlagOn && _recordingSupported'),
      );
    });

    test('engine limit / unreachable / generic failure stay distinct', () {
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
          engineErrorCode: 'recording_limit_reached',
        ),
        _OriginTogglePath.engineLimitReached,
      );
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
          engineErrorCode: 'engine_unsupported',
        ),
        _OriginTogglePath.engineTeeFallback,
      );
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
          engineErrorCode: 'fgs_not_allowed',
        ),
        _OriginTogglePath.engineTeeFallback,
      );
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
          engineErrorCode: 'missing_plugin',
        ),
        _OriginTogglePath.engineTeeFallback,
      );
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
          profileCommitted: true,
          engineErrorCode: 'engine_unsupported',
        ),
        _OriginTogglePath.engineFailed,
      );
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
          engineErrorCode: 'other',
        ),
        _OriginTogglePath.engineFailed,
      );
      expect(origin, contains("'recording_limit_reached'"));
      expect(origin, contains("'engine_unsupported'"));
      expect(origin, contains("'fgs_not_allowed'"));
      expect(origin, contains("'missing_plugin'"));
    });

    test('committed profile + no engine URL aborts; otherwise fall through', () {
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: false,
          profileCommitted: true,
        ),
        _OriginTogglePath.profileUnsafeStream,
      );
      expect(
        _originToggleDecision(
          isAndroid: true,
          engineFlagOn: true,
          recordingSupported: true,
          hasChannel: true,
          hasRecordUrl: false,
          desktopServiceSupported: false,
        ),
        _OriginTogglePath.startTee,
      );
      expect(origin, contains('This stream cannot be recorded safely'));
    });

    test('desktop service + supported starts a ts capture; HLS says so', () {
      expect(
        _originToggleDecision(
          recordingSupported: true,
          desktopServiceSupported: true,
          hasChannel: true,
          hasRecordUrl: true,
        ),
        _OriginTogglePath.startDesktop,
      );
      expect(
        _originToggleDecision(
          recordingSupported: true,
          desktopServiceSupported: true,
          hasChannel: true,
          hasRecordUrl: false,
        ),
        _OriginTogglePath.desktopHlsAbort,
      );
      expect(
        _originToggleDecision(
          recordingSupported: true,
          desktopServiceSupported: true,
          hasChannel: false,
        ),
        _OriginTogglePath.desktopNoChannel,
      );
      expect(
        origin,
        contains("This channel can't be recorded on desktop (HLS stream)"),
      );
    });

    test('otherwise the tee is the fallback recorder', () {
      expect(_originToggleDecision(), _OriginTogglePath.startTee);
      expect(origin, contains('await _startRecording()'));
    });
  });

  group('engine record URL (origin _engineRecordUrlForCurrent)', () {
    test('non-live / missing / non-http never go to the engine', () {
      expect(
        _originEngineRecordUrl(hasChannel: false, isLive: true, playing: 'http://x'),
        isNull,
      );
      expect(
        _originEngineRecordUrl(hasChannel: true, isLive: false, playing: 'http://x'),
        isNull,
      );
      expect(
        _originEngineRecordUrl(hasChannel: true, isLive: true, playing: null),
        isNull,
      );
      expect(
        _originEngineRecordUrl(
          hasChannel: true,
          isLive: true,
          playing: 'rtmp://live.example/stream',
        ),
        isNull,
      );
      expect(origin, contains("channel.isLive != true"));
      expect(origin, contains("!playing.startsWith('http://')"));
    });

    test('hls/dash probe uses the Xtream twin; nonempty progressive uses playing', () {
      expect(
        _originEngineRecordUrl(
          hasChannel: true,
          isLive: true,
          playing: 'http://x/live/u/p/1.m3u8',
          format: 'hls',
          xtreamTwin: 'http://x/live/u/p/1.ts',
        ),
        'http://x/live/u/p/1.ts',
      );
      expect(
        _originEngineRecordUrl(
          hasChannel: true,
          isLive: true,
          playing: 'https://cdn/dash.mpd',
          format: 'DASH',
          xtreamTwin: null,
        ),
        isNull,
      );
      expect(
        _originEngineRecordUrl(
          hasChannel: true,
          isLive: true,
          playing: 'http://x/live.ts',
          format: 'mpegts',
        ),
        'http://x/live.ts',
      );
      expect(
        _originEngineRecordUrl(
          hasChannel: true,
          isLive: true,
          playing: 'http://x/live/u/p/1',
          format: '',
          engineRecordable: 'http://x/live/u/p/1',
        ),
        'http://x/live/u/p/1',
      );
      expect(origin, contains("lower.contains('hls') || lower.contains('dash')"));
      expect(origin, contains('LiveRecordingService.xtreamTsTwin(playing)'));
      expect(origin, contains('LiveRecordingService.engineRecordableUrl(playing)'));
    });
  });

  group('playing live URL + resource lookup', () {
    test('plain channels use channel.url; stremio uses the resolved stream', () {
      expect(
        _originPlayingLiveUrl(
          channelUrl: 'http://x/1.ts',
          currentStreamUrl: 'http://stale',
        ),
        'http://x/1.ts',
      );
      expect(
        _originPlayingLiveUrl(
          channelUrl: 'stremio-tv://addon/ch',
          currentStreamUrl: 'http://resolved/live.ts',
        ),
        'http://resolved/live.ts',
      );
      expect(
        _originPlayingLiveUrl(
          channelUrl: 'stremio-tv://addon/ch',
          currentStreamUrl: 'stremio-tv://still-unresolved',
        ),
        isNull,
      );
      expect(origin, contains("!channel.url.startsWith('stremio-tv://')"));
    });

    test('resource id prefers live playlist id, then series, then launch source', () {
      expect(
        _originResourceSourceId(
          livePlaylistId: 'live-a',
          seriesPlaylistId: 'series-b',
          launchSourceId: 'launch-c',
        ),
        'live-a',
      );
      expect(
        _originResourceSourceId(
          livePlaylistId: null,
          seriesPlaylistId: 'series-b',
          launchSourceId: 'launch-c',
        ),
        'series-b',
      );
      expect(
        _originResourceSourceId(
          livePlaylistId: null,
          seriesPlaylistId: null,
          launchSourceId: 'launch-c',
        ),
        'launch-c',
      );
      expect(origin, contains("channel?.attributes['source_playlist_id']"));
      expect(origin, contains("channel?.attributes['series_playlist_id']"));
      expect(origin, contains('widget.iptvSourceId'));
    });
  });

  group('probe + active flag (origin _recordingSupported / _recordingActiveNow)', () {
    test('deny-by-default on Android; desktop is native && allowed', () {
      expect(
        _originProbeSupported(
          recordingsAllowed: true,
          nativeBackend: true,
          isAndroid: false,
        ),
        isTrue,
      );
      expect(
        _originProbeSupported(
          recordingsAllowed: true,
          nativeBackend: true,
          isAndroid: true,
        ),
        isFalse,
      );
      expect(
        _originProbeSupported(
          recordingsAllowed: false,
          nativeBackend: true,
          isAndroid: false,
        ),
        isFalse,
      );
      expect(origin, contains('recordingsAllowed && nativeBackend && !Platform.isAndroid'));
    });

    test('active is tee or engine task or desktop capture of this channel', () {
      expect(
        _originRecordingActiveNow(
          teeRecording: false,
          engineTaskId: null,
          desktopCaptureCurrent: false,
        ),
        isFalse,
      );
      expect(
        _originRecordingActiveNow(
          teeRecording: true,
          engineTaskId: null,
          desktopCaptureCurrent: false,
        ),
        isTrue,
      );
      expect(
        _originRecordingActiveNow(
          teeRecording: false,
          engineTaskId: 'task-1',
          desktopCaptureCurrent: false,
        ),
        isTrue,
      );
      expect(
        _originRecordingActiveNow(
          teeRecording: false,
          engineTaskId: null,
          desktopCaptureCurrent: true,
        ),
        isTrue,
      );
      expect(origin, contains('_desktopCaptureForCurrent() != null'));
    });
  });
}

/// Bodies live on the god file until the move; after the move they live on
/// the controller. The pin must keep passing without edits (gate h).
String _recordingOriginSource() {
  final moved = File('lib/services/playback/iptv_recording_controller.dart');
  if (moved.existsSync()) {
    return moved.readAsStringSync();
  }
  return File('lib/screens/video_player_screen.dart').readAsStringSync();
}

String _originSafeBaseName(String channelName) {
  final safeName = channelName
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  var base = safeName.isEmpty ? 'recording' : safeName;
  if (base.length > 60) base = base.substring(0, 60);
  return base;
}

String _originRecordingFileName(String channelName, DateTime now) {
  final base = _originSafeBaseName(channelName);
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return '${base}_$stamp.ts';
}

Future<String> _originUniquifyCandidate(
  String prefix,
  String extension,
  DateTime now,
) async {
  var candidate = '$prefix.$extension';
  for (var n = 2; n < 100 && await File(candidate).exists(); n++) {
    candidate = '${prefix}_$n.$extension';
  }
  if (await File(candidate).exists()) {
    candidate = '${prefix}_${now.microsecondsSinceEpoch}.$extension';
  }
  return candidate;
}

enum _OriginTogglePath {
  stopDesktop,
  stopEngine,
  stopTee,
  startEngine,
  engineLimitReached,
  engineTeeFallback,
  engineFailed,
  profileUnsafeStream,
  desktopNoChannel,
  desktopHlsAbort,
  startDesktop,
  startTee,
}

_OriginTogglePath _originToggleDecision({
  bool desktopCaptureCurrent = false,
  bool engineTaskPresent = false,
  bool teeRecording = false,
  bool isAndroid = false,
  bool engineFlagOn = false,
  bool recordingSupported = false,
  bool desktopServiceSupported = false,
  bool hasChannel = true,
  bool hasRecordUrl = true,
  bool profileCommitted = false,
  String? engineErrorCode,
}) {
  if (desktopCaptureCurrent) return _OriginTogglePath.stopDesktop;
  if (engineTaskPresent) return _OriginTogglePath.stopEngine;
  if (teeRecording) return _OriginTogglePath.stopTee;
  if (isAndroid && engineFlagOn && recordingSupported) {
    if (hasChannel && hasRecordUrl) {
      if (engineErrorCode == null) return _OriginTogglePath.startEngine;
      if (engineErrorCode == 'recording_limit_reached') {
        return _OriginTogglePath.engineLimitReached;
      }
      if (!profileCommitted &&
          (engineErrorCode == 'engine_unsupported' ||
              engineErrorCode == 'fgs_not_allowed' ||
              engineErrorCode == 'missing_plugin')) {
        return _OriginTogglePath.engineTeeFallback;
      }
      return _OriginTogglePath.engineFailed;
    }
    if (profileCommitted) return _OriginTogglePath.profileUnsafeStream;
  }
  if (desktopServiceSupported && recordingSupported) {
    if (!hasChannel) return _OriginTogglePath.desktopNoChannel;
    if (!hasRecordUrl) return _OriginTogglePath.desktopHlsAbort;
    return _OriginTogglePath.startDesktop;
  }
  return _OriginTogglePath.startTee;
}

String? _originEngineRecordUrl({
  required bool hasChannel,
  required bool isLive,
  required String? playing,
  String format = '',
  String? xtreamTwin,
  String? engineRecordable,
}) {
  if (!hasChannel || !isLive) return null;
  if (playing == null || playing.isEmpty) return null;
  if (!playing.startsWith('http://') && !playing.startsWith('https://')) {
    return null;
  }
  final lower = format.toLowerCase();
  if (lower.contains('hls') || lower.contains('dash')) {
    return xtreamTwin;
  }
  if (lower.isNotEmpty) {
    return playing;
  }
  return engineRecordable;
}

String? _originPlayingLiveUrl({
  required String channelUrl,
  required String? currentStreamUrl,
}) {
  if (!channelUrl.startsWith('stremio-tv://')) return channelUrl;
  final resolved = currentStreamUrl;
  if (resolved == null || resolved.startsWith('stremio-tv://')) return null;
  return resolved;
}

String? _originResourceSourceId({
  required String? livePlaylistId,
  required String? seriesPlaylistId,
  required String? launchSourceId,
}) {
  return livePlaylistId ?? seriesPlaylistId ?? launchSourceId;
}

bool _originProbeSupported({
  required bool recordingsAllowed,
  required bool nativeBackend,
  required bool isAndroid,
}) {
  return recordingsAllowed && nativeBackend && !isAndroid;
}

bool _originRecordingActiveNow({
  required bool teeRecording,
  required String? engineTaskId,
  required bool desktopCaptureCurrent,
}) {
  return teeRecording || engineTaskId != null || desktopCaptureCurrent;
}
