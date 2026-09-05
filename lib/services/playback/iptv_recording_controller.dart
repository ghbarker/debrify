import 'package:debrify/services/storage/iptv_prefs.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import '../../models/iptv_playlist.dart';
import '../../models/profiles/profile_policy.dart';
import '../../utils/app_storage.dart';
import '../android_native_downloader.dart';
import '../desktop_recording_service.dart';
import '../live_recording_service.dart';
import '../profiles/profile_policy_guard.dart';
import '../profiles/profile_runtime.dart';

/// Live player state the moved IPTV recording functions read and write.
///
/// Implemented by the player State. Named without host `_` prefixes so this
/// file compiles with those members removed (gate g).
abstract class IptvRecordingSession {
  mk.Player get player;
  bool get playerCreated;
  bool get isMounted;

  IptvChannel? get currentIptvChannel;
  bool get iptvZapBannerOwnsIdentity;
  String? get currentStreamUrl;

  /// Origin `widget.iptvSourceId`.
  String? get iptvSourceId;

  /// Origin `widget.iptvSources`.
  List<Map<String, dynamic>>? get iptvSources;

  void runSetState(VoidCallback updates);
  void showSnackBar(String message);
  Future<bool> ensureCapacity();
}

/// Player IPTV recording: libmpv tee, Android engine, desktop capture.
///
/// Bodies moved from `_VideoPlayerScreenState`. Mutations go through
/// [IptvRecordingSession]. Overlay reads [supported] / [active] notifiers.
class IptvRecordingController {
  IptvRecordingController(this.session);

  final IptvRecordingSession session;

  /// Origin `_recordingSupported`.
  final ValueNotifier<bool> supported = ValueNotifier(false);

  /// Origin `_recordingActiveNow` — tee, engine task, or desktop capture.
  final ValueNotifier<bool> active = ValueNotifier(false);

  // ── IPTV recording (libmpv `stream-record`) ─────────────────────────────
  /// True once the player is confirmed to run on a native (libmpv) backend —
  /// recording is unavailable on the web backend.
  bool _recordingSupported = false;
  bool _isRecording = false;

  /// Filesystem path libmpv is writing the active recording to.
  String? _recordingTempPath;

  /// The recording ENGINE's capture of the CURRENTLY PLAYING live channel
  /// (LiveRecordingService task id), or null. Independent of the tee's
  /// [_isRecording]: an engine capture belongs to the service, not this
  /// widget, so nothing in this screen's lifecycle may stop it implicitly.
  String? _engineTaskId;

  /// Engine-vs-tee flag (Settings → IPTV → Recording), loaded at player setup.
  bool _engineFlagOn = false;

  /// Supersedes stale engine-state refreshes (zap during a query round-trip).
  int _engineRefreshTicket = 0;

  /// Tap on mpv's log stream while a TEE recording is armed. stream-record
  /// failing INSIDE mpv (its own fopen refused, demuxer that can't dump) is
  /// completely invisible otherwise — the property set succeeds, Dart sees no
  /// error, and no file ever appears. Only errors surface by default (the
  /// player config requests error-level logs), which is exactly the band
  /// stream-record failures log in.
  StreamSubscription<mk.PlayerLog>? _recordLogSub;

  /// Repaints the Record button when a desktop capture starts or ends behind
  /// this screen's back — a scheduled one firing on the channel being watched,
  /// or any capture self-ending (stream drop, 6h cap). Sampling on rebuild
  /// alone would leave the button claiming to record something already dead.
  ///
  /// This screen deliberately keeps NO handle on a desktop capture. Desktop has
  /// no tee (mpv can't mux on media_kit's libs) and no Android engine — the raw
  /// HTTP copy is the only recorder there — but like the engine it belongs to
  /// the SERVICE, so closing the player leaves it running and nothing here may
  /// stop it implicitly. [_desktopCaptureForCurrent] asks the service instead,
  /// which is also what makes a SCHEDULER-started capture stoppable from this
  /// same button.
  VoidCallback? _desktopRecordingRevisionListener;

  /// Bumped whenever a stop, a channel change or a teardown supersedes an
  /// in-flight [_startRecording]. That start does async work (storage lookup,
  /// mkdir) during which `_isRecording` is still false, so the stop-if-
  /// recording checks elsewhere cannot see it; without this token the awaits
  /// could resume and arm libmpv on the NEW channel under the OLD channel's
  /// filename, or arm an already-disposed player and leave the file untracked.
  int _recordingStartGen = 0;

  /// Record is offered only for live IPTV on a libmpv backend.
  bool get canRecord =>
      _recordingSupported && session.iptvZapBannerOwnsIdentity;

  /// Origin `_isRecording` (libmpv tee only). Decoder fallback reads this.
  bool get isTeeRecording => _isRecording;

  bool get engineFlagOn => _engineFlagOn;

  /// One truth for "is this playback being recorded right now", shared by
  /// the dock's Record button and the styled zap banner's REC tag — the
  /// three mechanisms are libmpv stream-record, the Android recording
  /// engine, and the desktop capture process.
  bool get recordingActiveNow =>
      _isRecording ||
      _engineTaskId != null ||
      _desktopCaptureForCurrent() != null;

  void _publishActive() {
    final next = recordingActiveNow;
    if (active.value != next) active.value = next;
  }

  void _syncSupportedNotifier() {
    if (supported.value != _recordingSupported) {
      supported.value = _recordingSupported;
    }
  }

  void _repaintHost() {
    _publishActive();
    if (session.isMounted) session.runSetState(() {});
  }

  void _setEngineTaskId(String? id) {
    _engineTaskId = id;
    _publishActive();
    if (session.isMounted) session.runSetState(() {});
  }

  void _setTeeRecording({required bool on, String? path}) {
    _isRecording = on;
    _recordingTempPath = path;
    _publishActive();
    if (session.isMounted) session.runSetState(() {});
  }

  /// libmpv exposes `stream-record`; the web backend does not. Gate the
  /// record control on having a native player — and, on Android, on the
  /// finished file being publishable at all. Below API 29 there is no
  /// MediaStore.Downloads and no WRITE_EXTERNAL_STORAGE, so a recording
  /// could only sit in app-private storage the user can't reach — offering
  /// the button would just be a way to lose footage.
  ///
  /// Deny-by-default: Android starts unsupported and flips true only on a
  /// positive probe. The opposite order would leave a rebuild window where
  /// an API 21–28 device shows Record, and a tap in that window starts a
  /// recording whose Stop button the probe then hides.
  void probeSupport() {
    final nativeBackend = session.player.platform is mk.NativePlayer;
    // A profile without the recordings feature never sees Record — the
    // platform probe below must not be able to flip it back on.
    final recordingsAllowed = ProfilePolicyGuard.allowsSync(
      ProfileFeature.recordings,
    );
    _recordingSupported =
        recordingsAllowed && nativeBackend && !Platform.isAndroid;
    _syncSupportedNotifier();
    if (recordingsAllowed && nativeBackend && Platform.isAndroid) {
      unawaited(
        AndroidNativeDownloader.canPublishRecordings().then((canPublish) {
          if (!canPublish || !session.isMounted) return;
          _recordingSupported = true;
          _syncSupportedNotifier();
          session.runSetState(() {});
        }),
      );
      // Engine flag + any capture of this channel already running (a recording
      // started in an earlier player session survives into this one).
      unawaited(
        LiveRecordingService.engineEnabled().then((on) {
          if (!session.isMounted) return;
          _engineFlagOn = on || ProfileRuntime.isProfileCommitted;
          if (_engineFlagOn) unawaited(_refreshEngineRecordingState());
        }),
      );
    }
  }

  /// Observe, don't sample: see [_desktopRecordingRevisionListener].
  void observeDesktopRevision() {
    if (DesktopRecordingService.instance.isSupported) {
      void onRevision() {
        _publishActive();
        if (session.isMounted) session.runSetState(() {});
      }

      _desktopRecordingRevisionListener = onRevision;
      DesktopRecordingService.instance.revision.addListener(onRevision);
    }
  }

  void detachDesktopRevision() {
    final revisionListener = _desktopRecordingRevisionListener;
    if (revisionListener != null) {
      DesktopRecordingService.instance.revision.removeListener(
        revisionListener,
      );
      _desktopRecordingRevisionListener = null;
    }
  }

  Future<void> refreshEngineState() => _refreshEngineRecordingState();

  /// Finalize any in-progress recording before the player is torn down. The
  /// bump also cancels a start still awaiting its storage setup (it would
  /// otherwise arm a disposed player and leave the file untracked).
  ///
  /// Done inline rather than through `_stopRecording`: dispose() cannot await,
  /// so that call would race `_player.dispose()` a few lines below AND reach
  /// its own setState() mid-teardown. The order that matters is preserved by
  /// hand — state cleared now, publish handed off immediately (it reads the
  /// .ts from disk and never touches mpv), property clear issued best-effort.
  /// A live .ts stays playable even if its tail is lost to the teardown, and
  /// the lifecycle listener above already caught the common backgrounding
  /// case with a clean, awaited flush.
  void finalizeOnDispose() {
    _recordingStartGen++;
    if (_isRecording) {
      final path = _recordingTempPath;
      final platform = session.playerCreated ? session.player.platform : null;
      _isRecording = false;
      _recordingTempPath = null;
      _publishActive();
      if (platform is mk.NativePlayer) {
        // Publication is CHAINED after the property clear, not run alongside
        // it: libmpv keeps appending until stream-record is cleared, and a
        // concurrent copy could reach EOF early, publish a truncated file and
        // delete the source out from under the still-writing muxer.
        unawaited(
          platform
              .setProperty('stream-record', '')
              .catchError(
                (Object e) => debugPrint(
                  'VideoPlayer: stop recording on dispose failed: $e',
                ),
              )
              .whenComplete(() {
                if (path != null && Platform.isAndroid) {
                  _publishRecording(path, userInitiated: false);
                }
              }),
        );
      } else if (path != null && Platform.isAndroid) {
        unawaited(_publishRecording(path, userInitiated: false));
      }
    }
  }

  void dispose() {
    _untapMpvLogs();
    supported.dispose();
    active.dispose();
  }

  DesktopRecordingCapture? _desktopCaptureForCurrent() {
    final channel = session.currentIptvChannel;
    if (channel == null) return null;
    final playing = _playingLiveUrl(channel);
    if (playing == null) return null;
    final service = DesktopRecordingService.instance;
    final direct = service.captureForUrl(playing);
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(playing);
    return twin != null ? service.captureForUrl(twin) : null;
  }

  Future<void> toggle() async {
    // Desktop capture of the current channel: stop it.
    final desktopCapture = _desktopCaptureForCurrent();
    if (desktopCapture != null) {
      final savedPath = desktopCapture.path;
      final bytes = await desktopCapture.stop();
      if (!session.isMounted) return;
      // The revision listener has already repainted (the capture ended during
      // that await); this only guarantees it for the pathological case where
      // the notification was swallowed.
      _repaintHost();
      session.showSnackBar(
        bytes > 0
            ? 'Recording saved: $savedPath'
            : 'Recording failed — nothing was captured',
      );
      return;
    }
    // Engine capture of the current channel: stop it. Finalization is async in
    // the service; its "Saved" notification is the confirmation.
    final engineTask = _engineTaskId;
    if (engineTask != null) {
      _setEngineTaskId(null);
      final ok = await LiveRecordingService.stop(engineTask);
      if (!session.isMounted) return;
      session.showSnackBar(
        ok
            ? 'Recording stopped — saving to Downloads/Debrify/Recordings'
            : "Couldn't stop recording",
      );
      return;
    }
    if (_isRecording) {
      await stop();
      return;
    }
    // Engine first on Android: its capture survives zaps, Home, even the app
    // dying. The tee stays as the fallback — and as the only recorder for true
    // HLS, which mpv can capture but the engine cannot.
    if (Platform.isAndroid && _engineFlagOn && _recordingSupported) {
      final channel = session.currentIptvChannel;
      final recordUrl = await _engineRecordUrlForCurrent();
      if (channel != null && recordUrl != null) {
        if (!await session.ensureCapacity()) return;
        if (!session.isMounted) return;
        // This path skips ensureEngineReady (support was pre-checked), so
        // the one-time notification ask lives here explicitly — fire-and-
        // forget, so an unanswered dialog can't delay the capture.
        unawaited(LiveRecordingService.ensureNotificationPermission());
        final resource = await _currentRecordingResource();
        if (!session.isMounted) return;
        final result = await LiveRecordingService.start(
          url: recordUrl,
          fileName: _recordingFileName(channel.name),
          channelName: channel.name,
          headers: channel.playbackHeaders,
          connectionResourceId: resource?.id,
          resourceAuthorizationRevision: resource?.revision,
        );
        if (!session.isMounted) return;
        if (result.ok) {
          _setEngineTaskId(result.id);
          session.showSnackBar(
            'Recording in background — keeps going if you zap or leave. '
            'Stop from here or the notification.',
          );
        } else if (result.errorCode == 'recording_limit_reached') {
          session.showSnackBar(
            'Recording limit reached — free a slot or raise the limit '
            'in IPTV settings',
          );
        } else if (!ProfileRuntime.isProfileCommitted &&
            (result.errorCode == 'engine_unsupported' ||
                result.errorCode == 'fgs_not_allowed' ||
                result.errorCode == 'missing_plugin')) {
          // Engine unreachable: the tee still works, with its semantics.
          await _startRecording();
        } else {
          session.showSnackBar("Couldn't start recording");
        }
        return;
      }
      // recordUrl == null: true segmented stream (no Xtream twin) — only the
      // tee can capture what mpv is demuxing. Fall through.
      if (ProfileRuntime.isProfileCommitted) {
        session.showSnackBar('This stream cannot be recorded safely');
        return;
      }
    }
    // Desktop: the raw HTTP capture is the ONLY recorder that works — the mpv
    // tee is dead on media_kit's stock libs (no muxers in its FFmpeg). Never
    // fall through to the tee here; for unrecordable streams say so instead
    // of starting something that provably writes nothing.
    if (DesktopRecordingService.instance.isSupported && _recordingSupported) {
      final channel = session.currentIptvChannel;
      final recordUrl = await _engineRecordUrlForCurrent();
      if (channel == null) return;
      if (recordUrl == null) {
        session.showSnackBar(
          "This channel can't be recorded on desktop (HLS stream)",
        );
        return;
      }
      if (!await session.ensureCapacity()) return;
      if (!session.isMounted) return;
      // Raw byte copy → the capture IS a transport stream: .ts, not the
      // tee's .mkv.
      final path = await _recordingTargetPath(channel.name, extension: 'ts');
      // The screen may have closed during that await. Starting now would be
      // legitimate — captures outlive this screen — but the state below can't
      // be set on a dead widget, and the user asked for this from a surface
      // that is gone.
      if (!session.isMounted) return;
      // No onFinished: endings are announced app-wide by the reporter in
      // main(), which is still alive when this screen isn't, and the revision
      // listener repaints the button. A screen-scoped callback would only
      // duplicate the toast while the player happens to be open.
      final resource = await _currentRecordingResource();
      if (!session.isMounted) return;
      final capture = await DesktopRecordingService.instance.start(
        url: recordUrl,
        path: path,
        channelName: channel.name,
        headers: channel.playbackHeaders,
        connectionResourceId: resource?.id,
        resourceAuthorizationRevision: resource?.revision,
      );
      if (!session.isMounted) return;
      if (capture == null) {
        session.showSnackBar("Couldn't start recording");
        return;
      }
      _repaintHost();
      session.showSnackBar(
        'Recording in background — keeps going if you zap or leave. '
        'Stop from here or Settings → Recordings.',
      );
      return;
    }
    await _startRecording();
  }

  /// The URL actually PLAYING for [channel]. NOT `session.currentStreamUrl` for
  /// plain channels — the zap path never updates that field, so after a zap
  /// it still holds the previous channel's URL, and matching on it would pin
  /// the Record button (and its Stop!) to the wrong capture. The channel's
  /// own URL is the identity for everything except Stremio, whose playing URL
  /// is the resolved candidate only `session.currentStreamUrl` knows.
  String? _playingLiveUrl(IptvChannel channel) {
    if (!channel.url.startsWith('stremio-tv://')) return channel.url;
    final resolved = session.currentStreamUrl;
    if (resolved == null || resolved.startsWith('stremio-tv://')) return null;
    return resolved;
  }

  /// The URL the ENGINE should capture for the current live channel, or null
  /// when only the tee can record it. mpv's own `file-format` is ground truth
  /// for what's actually playing (extension-less URLs lie); the URL shape is
  /// the fallback when the probe is unavailable.
  Future<String?> _engineRecordUrlForCurrent() async {
    final channel = session.currentIptvChannel;
    if (channel == null || channel.isLive != true) return null;
    final playing = _playingLiveUrl(channel);
    if (playing == null || playing.isEmpty) return null;
    // The engine speaks HTTP only. rtmp/rtsp/udp/... channels go to the tee —
    // mpv plays them, so mpv can record them. Checked BEFORE the probe: mpv
    // reports e.g. "flv" for RTMP, which would read as progressive below.
    if (!playing.startsWith('http://') && !playing.startsWith('https://')) {
      return null;
    }
    String format = '';
    final platform = session.player.platform;
    if (platform is mk.NativePlayer) {
      try {
        format = await platform.getProperty('file-format');
      } catch (_) {}
    }
    final lower = format.toLowerCase();
    if (lower.contains('hls') || lower.contains('dash')) {
      // Segmented for sure — only an Xtream `.ts` twin can rescue it.
      return LiveRecordingService.xtreamTsTwin(playing);
    }
    if (lower.isNotEmpty) {
      // Probe says progressive: record exactly what's playing.
      return playing;
    }
    return LiveRecordingService.engineRecordableUrl(playing);
  }

  /// Re-derive [_engineTaskId] from the native registry — a capture may have
  /// been started in an earlier player session, or stopped from the
  /// notification while this screen was open.
  Future<void> _refreshEngineRecordingState() async {
    if (!Platform.isAndroid || !_engineFlagOn) return;
    final channel = session.currentIptvChannel;
    if (channel == null || channel.isLive != true) {
      if (_engineTaskId != null && session.isMounted) {
        _setEngineTaskId(null);
      }
      return;
    }
    final ticket = ++_engineRefreshTicket;
    final playing = _playingLiveUrl(channel);
    if (playing == null) {
      if (_engineTaskId != null) _setEngineTaskId(null);
      return;
    }
    final twin = LiveRecordingService.xtreamTsTwin(playing);
    final recordings = await LiveRecordingService.query();
    if (!session.isMounted || ticket != _engineRefreshTicket) return;
    String? found;
    for (final r in recordings) {
      if (r.isRecording &&
          (r.url == playing || (twin != null && r.url == twin))) {
        found = r.taskId;
        break;
      }
    }
    if (found != _engineTaskId) {
      _setEngineTaskId(found);
    }
  }

  /// `<Channel>_<yyyyMMdd_HHmmss>.ts` — same shape as the tee's target path
  /// (which additionally uniquifies against its own directory; MediaStore
  /// uniquifies for the engine).
  String _recordingFileName(String channelName) {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${base}_$stamp.ts';
  }

  Future<({String id, int revision})?> _currentRecordingResource() async {
    final channel = session.currentIptvChannel;
    final sourceId =
        channel?.attributes['source_playlist_id'] ??
        channel?.attributes['series_playlist_id'] ??
        session.iptvSourceId /* widget.iptvSourceId */;
    if (sourceId == null) return null;
    // Fresh read first: the launch payload's revision predates any sources
    // edit made while this player lives (PiP, background), and every edit
    // bumps every source's revision — a stale one would be refused at start.
    try {
      final playlists = await IptvPrefs.getIptvPlaylists(
        forSettings: false,
      );
      for (final playlist in playlists) {
        if (playlist.id != sourceId) continue;
        final id = playlist.connectionResourceId;
        final revision = playlist.connectionResourceRevision;
        if (id != null && id.isNotEmpty && revision != null) {
          return (id: id, revision: revision);
        }
      }
    } catch (_) {
      // Storage unavailable mid-session: fall through to the launch payload.
    }
    for (final source
        in session.iptvSources ?? const <Map<String, dynamic>>[]) {
      if (source['id'] != sourceId) continue;
      final id = source['connectionResourceId']?.toString();
      final revision = (source['connectionResourceRevision'] as num?)?.toInt();
      if (id != null && id.isNotEmpty && revision != null) {
        return (id: id, revision: revision);
      }
    }
    return null;
  }

  /// Print mpv log lines that matter while a tee recording runs.
  void _tapMpvLogsForRecording() {
    _recordLogSub?.cancel();
    _recordLogSub = session.player.stream.log.listen((log) {
      final level = log.level.toLowerCase();
      if (level != 'error' && level != 'fatal') return;
      debugPrint('VideoPlayer: mpv[${log.level}] ${log.prefix}: ${log.text}');
    });
  }

  void _untapMpvLogs() {
    _recordLogSub?.cancel();
    _recordLogSub = null;
  }

  Future<void> _startRecording() async {
    if (!session.playerCreated) return;
    final platform = session.player.platform;
    if (platform is! mk.NativePlayer) return;
    final channel = session.currentIptvChannel;
    if (channel == null) return;
    final gen = ++_recordingStartGen;
    try {
      final path = await _recordingTargetPath(channel.name);
      final parent = Directory(path).parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      // The channel (or the whole screen) may have gone while the storage work
      // ran. Arming now would tee the NEW stream into the old channel's file.
      if (gen != _recordingStartGen ||
          !session.isMounted ||
          !session.playerCreated) {
        return;
      }
      _tapMpvLogsForRecording();
      await platform.setProperty('stream-record', path);
      // Read the property back: proves whether mpv actually ACCEPTED the
      // target (a silent internal failure leaves it set but writes nothing —
      // the log tap above catches that case).
      var echoed = '';
      try {
        echoed = await platform.getProperty('stream-record');
      } catch (_) {}
      debugPrint(
        'VideoPlayer: stream-record armed — mpv reports "$echoed" '
        '(want "$path")',
      );
      if (gen != _recordingStartGen || !session.isMounted) {
        // Lost the race inside setProperty itself: disarm rather than leave an
        // untracked recording running on someone else's stream.
        _untapMpvLogs();
        await _disarmStrayRecording(platform, path);
        return;
      }
      _setTeeRecording(on: true, path: path);
      // Crash insurance: registered natively so the file gets published on
      // next launch even if this process never reaches _stopRecording.
      if (Platform.isAndroid) {
        unawaited(
          AndroidNativeDownloader.registerPendingRecording(
            path: path,
            fileName: path.split(Platform.pathSeparator).last,
            mimeType: 'video/x-matroska',
          ),
        );
      }
      session.showSnackBar(
        // The tee records what the player reads, so on Android (where the
        // engine exists as the contrast) say the semantics out loud.
        Platform.isAndroid
            ? 'Recording started (stops if you leave the channel)'
            : 'Recording started',
      );
    } catch (e) {
      _untapMpvLogs();
      debugPrint('VideoPlayer: start recording failed: $e');
      if (!session.isMounted) return;
      session.showSnackBar('Could not start recording');
    }
  }

  /// Undo a recording that got armed after its channel or screen went away.
  /// The stub file is milliseconds old, so dropping it loses nothing a user
  /// would recognise as a recording.
  Future<void> _disarmStrayRecording(
    mk.NativePlayer platform,
    String path,
  ) async {
    try {
      await platform.setProperty('stream-record', '');
    } catch (e) {
      debugPrint('VideoPlayer: disarm stray recording failed: $e');
    }
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('VideoPlayer: stray recording cleanup failed: $e');
    }
  }

  /// Stop the active recording. Auto-stops (channel change / dispose) pass
  /// [userInitiated] = false to stay quiet.
  Future<void> stop({bool userInitiated = true}) async {
    // A stop supersedes an in-flight start too — including one that has not
    // yet flipped `_isRecording` and so is invisible to the check below.
    _recordingStartGen++;
    if (!_isRecording) return;
    final path = _recordingTempPath;
    final platform = session.playerCreated ? session.player.platform : null;
    // Flip state first so a rapid re-tap / channel switch can't double-stop.
    _setTeeRecording(on: false, path: null);
    try {
      if (platform is mk.NativePlayer) {
        await platform.setProperty('stream-record', '');
      }
    } catch (e) {
      debugPrint('VideoPlayer: stop recording failed: $e');
    }
    _untapMpvLogs();
    if (path == null) return;
    // VERIFY before claiming anything: mpv can accept `stream-record` and
    // still write nothing (internal fopen refused, undumpable demuxer) — the
    // first macOS test hit exactly that, with a "saved" message over an empty
    // folder.
    var fileBytes = 0;
    try {
      final file = File(path);
      if (await file.exists()) fileBytes = await file.length();
    } catch (_) {}
    debugPrint(
      'VideoPlayer: tee recording stopped — $fileBytes bytes on disk at $path',
    );
    final fileOk = fileBytes > 0;
    // Publish to a user-visible location. On Android the file lives in
    // app-private storage, so hand it to the native MediaStore publisher; on
    // desktop it's already under the user's Downloads.
    if (fileOk && Platform.isAndroid) {
      unawaited(_publishRecording(path, userInitiated: userInitiated));
    } else if (userInitiated && session.isMounted) {
      session.showSnackBar(
        fileOk
            ? 'Recording saved: $path'
            : 'Recording failed — mpv wrote no file (see logs)',
      );
    }
  }

  Future<void> _publishRecording(
    String path, {
    required bool userInitiated,
  }) async {
    var published = false;
    try {
      final fileName = path.split(Platform.pathSeparator).last;
      final uri = await AndroidNativeDownloader.saveLocalFile(
        path: path,
        fileName: fileName,
        mimeType: 'video/x-matroska',
      );
      published = uri != null;
    } catch (e) {
      debugPrint('VideoPlayer: publish recording failed: $e');
    }
    if (!userInitiated || !session.isMounted) return;
    // On failure, don't claim a save the user can't find: the file sits in
    // app-private storage, its registry entry survives (only a successful
    // publish clears it), and the next app launch re-attempts the publish.
    session.showSnackBar(
      published
          ? 'Recording saved to Downloads/Debrify/Recordings'
          : "Recording couldn't be added to Downloads — "
                'will retry next launch',
    );
  }

  /// A path no other recording is using. The second-resolution stamp alone
  /// collides when the same channel is stopped and restarted inside one
  /// second, and that collision is destructive: libmpv would truncate (or
  /// append to) the previous file, and on Android the still-running publisher
  /// deletes its source once copied — taking the NEW recording with it. An
  /// existing file therefore means "in use": step aside with a suffix.
  ///
  /// Default `.mkv` (the TEE): mpv's recorder picks the output muxer from the
  /// filename, and media_kit's decode-trimmed FFmpeg ships no `mpegts` muxer
  /// ("recorder: Output format not found" → recording silently disabled —
  /// found live on macOS). Matroska is the only sane target IF a muxer
  /// exists. Raw byte copiers (the desktop capture, the Android engine) pass
  /// `extension: 'ts'` — their bytes ARE a transport stream, no muxer
  /// involved.
  Future<String> _recordingTargetPath(
    String channelName, {
    String extension = 'mkv',
  }) async {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';

    Directory dir;
    if (Platform.isAndroid) {
      dir =
          (await getExternalStorageDirectory()) ?? await AppStorage.documents();
    } else {
      dir = (await getDownloadsDirectory()) ?? await AppStorage.documents();
    }
    final sep = Platform.pathSeparator;
    final prefix = '${dir.path}${sep}Debrify${sep}Recordings$sep${base}_$stamp';

    var candidate = '$prefix.$extension';
    for (var n = 2; n < 100 && await File(candidate).exists(); n++) {
      candidate = '${prefix}_$n.$extension';
    }
    // Pathological (99 restarts in one second): fall back to microseconds,
    // which cannot collide with any of the names tried above.
    if (await File(candidate).exists()) {
      candidate = '${prefix}_${now.microsecondsSinceEpoch}.$extension';
    }
    return candidate;
  }
}
