import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';
import 'package:debrify/services/scrobble/scrobble.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pin of the video_player Trakt / Simkl / MDBList scrobble machines
/// before they are wired out of `video_player_screen.dart`.
///
/// Bodies were transcribed from origin/main:
/// `_initTraktScrobble` / `_traktScrobble` / `_startTraktHeartbeat` /
/// `_traktScrobbleSeek` (~1782–1998), the Simkl mirror (~2006–2180),
/// and the MDBList session hunk (~2183–2320).
void main() {
  TrackingSourcePolicy policyOf(Set<TrackingSource> targets) =>
      TrackingSourcePolicy(
        scrobbleTargets: targets,
        progressSource: WatchProgressSource.smart,
        homeTickSources: const {},
      );

  group('Trakt machine', () {
    test('play POSTs start; second start is deduped', () async {
      final rec = _Recorder();
      final clock = _Clock();
      final trakt = rec.trakt(clock);
      await trakt.init();
      clock.isPlaying = true;
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      expect(rec.calls, ['trakt.start:tt0111161:0.0:-:-']);
      trakt.onPlaying(true, wasPlaying: true, isTransitioning: false);
      expect(rec.calls, ['trakt.start:tt0111161:0.0:-:-']);
      trakt.onDispose();
    });

    test('start/pause above 80% become stop', () async {
      final rec = _Recorder();
      final clock = _Clock(persistablePosition: const Duration(minutes: 81));
      final trakt = rec.trakt(clock);
      await trakt.init();
      clock.isPlaying = true;
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      expect(rec.calls, ['trakt.stop:tt0111161:81.0:-:-']);
      expect(trakt.lastScrobbleAction, 'stop');
      trakt.onDispose();
    });

    test('heartbeat force-sends start; >80% stops and ends timer', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final clock = _Clock(
          persistablePosition: const Duration(minutes: 10),
          isPlaying: true,
        );
        final trakt = rec.trakt(clock);
        trakt.enabled = true;
        trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
        expect(rec.calls, ['trakt.start:tt0111161:10.0:-:-']);
        async.elapse(const Duration(minutes: 2));
        expect(rec.calls.last, 'trakt.start:tt0111161:10.0:-:-');
        clock.persistablePosition = const Duration(minutes: 81);
        async.elapse(const Duration(minutes: 2));
        expect(rec.calls.last, 'trakt.stop:tt0111161:81.0:-:-');
        final afterStop = rec.calls.length;
        async.elapse(const Duration(minutes: 4));
        expect(rec.calls.length, afterStop);
        trakt.onDispose();
      });
    });

    test('seek always re-sends start (or stop above 80%)', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final trakt = rec.trakt(clock);
      await trakt.init();
      clock.isPlaying = true;
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      rec.calls.clear();
      trakt.onSeek(const Duration(minutes: 20));
      expect(rec.calls, ['trakt.start:tt0111161:20.0:-:-']);
      rec.calls.clear();
      trakt.onSeek(const Duration(minutes: 40));
      expect(rec.calls, ['trakt.start:tt0111161:40.0:-:-']);
      rec.calls.clear();
      trakt.onSeek(const Duration(minutes: 85));
      expect(rec.calls, ['trakt.stop:tt0111161:85.0:-:-']);
      trakt.onDispose();
    });

    test('init while already playing sends start now', () async {
      final rec = _Recorder();
      final clock = _Clock(
        isPlaying: true,
        persistablePosition: const Duration(minutes: 5),
      );
      final trakt = rec.trakt(clock);
      await trakt.init();
      expect(rec.calls, ['trakt.start:tt0111161:5.0:-:-']);
      expect(trakt.lastScrobbleAction, 'start');
      trakt.onDispose();
    });

    test('unresolved series season/episode still POSTs (latent gap)', () async {
      final rec = _Recorder();
      final clock = _Clock(contentType: 'series', isPlaying: true);
      final trakt = rec.trakt(clock);
      await trakt.init();
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      expect(rec.calls, ['trakt.start:tt0111161:0.0:-:-']);
      trakt.onDispose();
    });

    test('policy.scrobbles(trakt) false never POSTs', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final trakt = rec.trakt(clock, policy: policyOf({TrackingSource.simkl}));
      await trakt.init();
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      expect(trakt.enabled, isFalse);
      expect(rec.calls, isEmpty);
    });

    test('requested=false never POSTs', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final trakt = rec.trakt(clock, requested: false);
      await trakt.init();
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      expect(rec.calls, isEmpty);
    });

    test('validation gate swallows start/pause/stop/seek', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true, validationGateActive: true);
      final trakt = rec.trakt(clock);
      await trakt.init();
      trakt.onPlaying(true, wasPlaying: false, isTransitioning: false);
      trakt.onSeek(const Duration(minutes: 10));
      trakt.onEnded();
      expect(rec.calls, isEmpty);
    });
  });

  group('Simkl machine', () {
    test('play does NOT POST /scrobble/start; stamps local start', () async {
      final rec = _Recorder();
      final clock = _Clock();
      final simkl = rec.simkl(clock);
      await simkl.init();
      clock.isPlaying = true;
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      expect(rec.calls, isEmpty);
      expect(simkl.lastScrobbleAction, 'start');
      simkl.onDispose();
    });

    test('pause POSTs pause; start action maps to pause POST', () async {
      final rec = _Recorder();
      final clock = _Clock(persistablePosition: const Duration(minutes: 15));
      final simkl = rec.simkl(clock);
      await simkl.init();
      clock.isPlaying = true;
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      clock.isPlaying = false;
      simkl.onPlaying(false, wasPlaying: true, isTransitioning: false);
      expect(rec.calls, ['simkl.pause:tt0111161:15.0:-:-']);
      expect(simkl.lastScrobbleAction, 'pause');
    });

    test('heartbeat POSTs pause and leaves marker start', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final clock = _Clock(
          persistablePosition: const Duration(minutes: 10),
          isPlaying: true,
        );
        final simkl = rec.simkl(clock);
        simkl.enabled = true;
        simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
        expect(rec.calls, isEmpty);
        expect(simkl.lastScrobbleAction, 'start');
        async.elapse(const Duration(minutes: 2));
        expect(rec.calls, ['simkl.pause:tt0111161:10.0:-:-']);
        expect(simkl.lastScrobbleAction, 'start');
        clock.isPlaying = false;
        simkl.onPlaying(false, wasPlaying: true, isTransitioning: false);
        expect(rec.calls.last, 'simkl.pause:tt0111161:10.0:-:-');
        expect(simkl.lastScrobbleAction, 'pause');
        simkl.onDispose();
      });
    });

    test('heartbeat >80% POSTs stop and ends timer', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final clock = _Clock(
          persistablePosition: const Duration(minutes: 10),
          isPlaying: true,
        );
        final simkl = rec.simkl(clock);
        simkl.enabled = true;
        simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
        clock.persistablePosition = const Duration(minutes: 81);
        async.elapse(const Duration(minutes: 2));
        expect(rec.calls, ['simkl.stop:tt0111161:81.0:-:-']);
        final n = rec.calls.length;
        async.elapse(const Duration(minutes: 4));
        expect(rec.calls.length, n);
        simkl.onDispose();
      });
    });

    test('incomplete series season/episode is skipped', () async {
      final rec = _Recorder();
      final clock = _Clock(
        contentType: 'series',
        persistablePosition: const Duration(minutes: 15),
      );
      final simkl = rec.simkl(clock);
      await simkl.init();
      clock.isPlaying = true;
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      clock.isPlaying = false;
      simkl.onPlaying(false, wasPlaying: true, isTransitioning: false);
      simkl.onSeek(const Duration(minutes: 85));
      simkl.onEnded();
      expect(rec.calls, isEmpty);
    });

    test('resolved series season/episode is sent', () async {
      final rec = _Recorder();
      final clock = _Clock(
        contentType: 'series',
        season: 1,
        episode: 8,
        persistablePosition: const Duration(minutes: 15),
      );
      final simkl = rec.simkl(clock);
      await simkl.init();
      clock.isPlaying = true;
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      clock.isPlaying = false;
      simkl.onPlaying(false, wasPlaying: true, isTransitioning: false);
      expect(rec.calls, ['simkl.pause:tt0111161:15.0:1:8']);
    });

    test('seek is transition-only', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final simkl = rec.simkl(clock);
      await simkl.init();
      clock.isPlaying = true;
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      simkl.onSeek(const Duration(minutes: 20));
      expect(rec.calls, isEmpty);
      simkl.onSeek(const Duration(minutes: 85));
      expect(rec.calls, ['simkl.stop:tt0111161:85.0:-:-']);
      rec.calls.clear();
      simkl.onSeek(const Duration(minutes: 90));
      expect(rec.calls, isEmpty);
      simkl.onSeek(const Duration(minutes: 40));
      expect(rec.calls, ['simkl.pause:tt0111161:40.0:-:-']);
      expect(simkl.lastScrobbleAction, 'pause');
      simkl.onDispose();
    });

    test('init while already playing stamps start and does not POST', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final simkl = rec.simkl(clock);
      await simkl.init();
      expect(rec.calls, isEmpty);
      expect(simkl.lastScrobbleAction, 'start');
      simkl.onDispose();
    });

    test('policy.scrobbles(simkl) false never POSTs', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final simkl = rec.simkl(clock, policy: policyOf({TrackingSource.trakt}));
      await simkl.init();
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      clock.isPlaying = false;
      simkl.onPlaying(false, wasPlaying: true, isTransitioning: false);
      expect(simkl.enabled, isFalse);
      expect(rec.calls, isEmpty);
    });

    test('pause at >80% becomes stop', () async {
      final rec = _Recorder();
      final clock = _Clock(persistablePosition: const Duration(minutes: 81));
      final simkl = rec.simkl(clock);
      await simkl.init();
      clock.isPlaying = true;
      simkl.onPlaying(true, wasPlaying: false, isTransitioning: false);
      clock.isPlaying = false;
      simkl.onPlaying(false, wasPlaying: true, isTransitioning: false);
      expect(rec.calls, ['simkl.stop:tt0111161:81.0:-:-']);
    });
  });

  group('MDBList target wrapper', () {
    test('play checkpoints pause and never start', () async {
      final rec = _Recorder();
      final clock = _Clock();
      final mdblist = rec.mdblist(clock);
      await mdblist.init();
      clock.isPlaying = true;
      mdblist.onPlaying(true, wasPlaying: false, isTransitioning: false);
      await mdblist.session!.flush();
      expect(rec.calls, ['mdblist.pause:tt0111161:1.0']);
    });

    test(
      'incomplete series season/episode does not create a session',
      () async {
        final rec = _Recorder();
        final clock = _Clock(contentType: 'series');
        final mdblist = rec.mdblist(clock);
        await mdblist.init();
        expect(mdblist.session, isNull);
        clock.isPlaying = true;
        mdblist.onPlaying(true, wasPlaying: false, isTransitioning: false);
        expect(rec.calls, isEmpty);
      },
    );

    test('policy.scrobbles(mdblist) false never creates a session', () async {
      final rec = _Recorder();
      final clock = _Clock();
      final mdblist = rec.mdblist(
        clock,
        policy: policyOf({TrackingSource.trakt}),
      );
      await mdblist.init();
      expect(mdblist.session, isNull);
    });

    test('waits for playerReady before creating the session', () async {
      final rec = _Recorder();
      final clock = _Clock();
      final ready = Completer<void>();
      final mdblist = rec.mdblist(clock, playerReady: ready.future);
      final init = mdblist.init();
      await Future<void>.delayed(Duration.zero);
      expect(mdblist.session, isNull);
      ready.complete();
      await init;
      expect(mdblist.session, isNotNull);
    });

    test('ended completes; dispose exits', () async {
      final rec = _Recorder();
      final clock = _Clock(
        persistablePosition: const Duration(minutes: 30),
        position: const Duration(minutes: 30),
      );
      final mdblist = rec.mdblist(clock);
      await mdblist.init();
      clock.isPlaying = true;
      mdblist.onPlaying(true, wasPlaying: false, isTransitioning: false);
      await mdblist.session!.flush();
      rec.calls.clear();
      clock.persistablePosition = const Duration(minutes: 85);
      clock.position = const Duration(minutes: 85);
      mdblist.onEnded();
      await mdblist.session!.flush();
      expect(rec.calls, ['mdblist.stop:tt0111161:100.0']);
    });
  });

  group('ScrobbleCoordinator', () {
    test('fans out independently; Simkl stays pause-centric', () async {
      final rec = _Recorder();
      final clock = _Clock();
      final trakt = rec.trakt(clock);
      final simkl = rec.simkl(clock);
      final mdblist = rec.mdblist(clock);
      final coordinator = ScrobbleCoordinator(
        playback: clock.playback,
        targets: [trakt, simkl, mdblist],
      );
      await coordinator.init();
      clock.isPlaying = true;
      coordinator.onPlaying(true, wasPlaying: false, isTransitioning: false);
      await mdblist.session!.flush();
      expect(rec.calls, [
        'trakt.start:tt0111161:0.0:-:-',
        'mdblist.pause:tt0111161:1.0',
      ]);
      rec.calls.clear();
      clock.persistablePosition = const Duration(minutes: 15);
      clock.position = const Duration(minutes: 15);
      clock.isPlaying = false;
      coordinator.onPlaying(false, wasPlaying: true, isTransitioning: false);
      await mdblist.session!.flush();
      expect(rec.calls, contains('trakt.pause:tt0111161:15.0:-:-'));
      expect(rec.calls, contains('simkl.pause:tt0111161:15.0:-:-'));
      expect(rec.calls, contains('mdblist.pause:tt0111161:15.0'));
      coordinator.onDispose();
    });

    test('outgoing episode stops Trakt/Simkl but not MDBList', () async {
      final rec = _Recorder();
      final clock = _Clock(
        persistablePosition: const Duration(minutes: 20),
        position: const Duration(minutes: 20),
      );
      final trakt = rec.trakt(clock);
      final simkl = rec.simkl(clock);
      final mdblist = rec.mdblist(clock);
      final coordinator = ScrobbleCoordinator(
        playback: clock.playback,
        targets: [trakt, simkl, mdblist],
      );
      await coordinator.init();
      clock.isPlaying = true;
      coordinator.onPlaying(true, wasPlaying: false, isTransitioning: false);
      await mdblist.session!.flush();
      rec.calls.clear();
      coordinator.onOutgoingEpisode();
      await mdblist.session!.flush();
      expect(rec.calls, contains('trakt.stop:tt0111161:20.0:-:-'));
      expect(rec.calls, contains('simkl.stop:tt0111161:20.0:-:-'));
      expect(rec.calls.where((c) => c.startsWith('mdblist')), isEmpty);
      coordinator.onDispose();
    });

    test('first duration only arms MDBList', () async {
      final rec = _Recorder();
      final clock = _Clock(isPlaying: true);
      final trakt = rec.trakt(clock);
      final simkl = rec.simkl(clock);
      final mdblist = rec.mdblist(clock);
      await Future.wait([trakt.init(), simkl.init(), mdblist.init()]);
      trakt.enabled = true;
      simkl.enabled = true;
      rec.calls.clear();
      mdblist.onDurationBecameReady();
      await mdblist.session!.flush();
      expect(rec.calls, ['mdblist.pause:tt0111161:1.0']);
      trakt.onDispose();
      simkl.onDispose();
    });

    test(
      'resume-after-gate: Trakt start, Simkl stamp only, MDBList play',
      () async {
        final rec = _Recorder();
        final clock = _Clock(
          persistablePosition: const Duration(minutes: 12),
          position: const Duration(minutes: 12),
        );
        final trakt = rec.trakt(clock);
        final simkl = rec.simkl(clock);
        final mdblist = rec.mdblist(clock);
        final coordinator = ScrobbleCoordinator(
          playback: clock.playback,
          targets: [trakt, simkl, mdblist],
        );
        await coordinator.init();
        expect(rec.calls, isEmpty);
        clock.isPlaying = true;
        coordinator.resumeAfterValidationGate();
        await mdblist.session!.flush();
        expect(rec.calls, contains('trakt.start:tt0111161:12.0:-:-'));
        expect(rec.calls.where((c) => c.startsWith('simkl.start')), isEmpty);
        expect(simkl.lastScrobbleAction, 'start');
        expect(rec.calls, contains('mdblist.pause:tt0111161:12.0'));
        coordinator.onDispose();
      },
    );
  });
}

class _Clock {
  _Clock({
    this.contentType = 'movie',
    this.position = Duration.zero,
    this.persistablePosition = Duration.zero,
    this.isPlaying = false,
    this.validationGateActive = false,
    this.season,
    this.episode,
  });

  String? imdbId = 'tt0111161';
  String? contentType;
  Duration duration = const Duration(minutes: 100);
  Duration position;
  Duration persistablePosition;
  bool isPlaying;
  bool validationGateActive;
  bool mounted = true;
  int? season;
  int? episode;

  ScrobblePlayback get playback => ScrobblePlayback(
    imdbIdOf: () => imdbId,
    contentTypeOf: () => contentType,
    durationOf: () => duration,
    positionOf: () => position,
    persistablePositionOf: () => persistablePosition,
    isPlayingOf: () => isPlaying,
    validationGateActiveOf: () => validationGateActive,
    mountedOf: () => mounted,
    seasonEpisodeOf: () => (season: season, episode: episode),
  );
}

class _Recorder {
  final calls = <String>[];

  Future<bool> _send(
    String label,
    String imdb,
    double progress, {
    int? season,
    int? episode,
  }) async {
    calls.add(
      '$label:$imdb:${progress.toStringAsFixed(1)}:${season ?? '-'}:${episode ?? '-'}',
    );
    return true;
  }

  Future<MdblistResult<Map<String, dynamic>>> _mdblistSend(
    String action,
    MdblistScrobbleTarget target,
    double progress,
  ) async {
    calls.add(
      'mdblist.$action:${target.ids.imdb}:${progress.toStringAsFixed(1)}',
    );
    return const MdblistResult.success({});
  }

  TraktScrobbleTarget trakt(
    _Clock clock, {
    bool requested = true,
    TrackingSourcePolicy? policy,
  }) => TraktScrobbleTarget(
    requested: requested,
    playback: clock.playback,
    scrobbleStart: (imdb, progress, {season, episode}) =>
        _send('trakt.start', imdb, progress, season: season, episode: episode),
    scrobblePause: (imdb, progress, {season, episode}) =>
        _send('trakt.pause', imdb, progress, season: season, episode: episode),
    scrobbleStop: (imdb, progress, {season, episode}) =>
        _send('trakt.stop', imdb, progress, season: season, episode: episode),
    isAuthenticated: () async => true,
    loadPolicy: () async =>
        policy ??
        TrackingSourcePolicy(
          scrobbleTargets: {TrackingSource.trakt},
          progressSource: WatchProgressSource.smart,
          homeTickSources: const {},
        ),
  );

  SimklScrobbleTarget simkl(
    _Clock clock, {
    bool requested = true,
    TrackingSourcePolicy? policy,
  }) => SimklScrobbleTarget(
    requested: requested,
    playback: clock.playback,
    scrobblePause: (imdb, progress, {season, episode}) =>
        _send('simkl.pause', imdb, progress, season: season, episode: episode),
    scrobbleStop: (imdb, progress, {season, episode}) =>
        _send('simkl.stop', imdb, progress, season: season, episode: episode),
    isAuthenticated: () async => true,
    loadPolicy: () async =>
        policy ??
        TrackingSourcePolicy(
          scrobbleTargets: {TrackingSource.simkl},
          progressSource: WatchProgressSource.smart,
          homeTickSources: const {},
        ),
  );

  MdblistScrobbleSessionTarget mdblist(
    _Clock clock, {
    TrackingSourcePolicy? policy,
    Future<void>? playerReady,
  }) => MdblistScrobbleSessionTarget(
    requested: true,
    playback: clock.playback,
    playerReady: playerReady ?? Future.value(),
    featureEnabled: true,
    loadPolicy: () async =>
        policy ??
        TrackingSourcePolicy(
          scrobbleTargets: {TrackingSource.mdblist},
          progressSource: WatchProgressSource.smart,
          homeTickSources: const {},
        ),
    captureCapability: () async => null,
    createSession: ({required target, required capability}) =>
        MdblistScrobbleSession(
          target: target,
          budgetAvailable: () => true,
          sender: _mdblistSend,
        ),
  );
}
