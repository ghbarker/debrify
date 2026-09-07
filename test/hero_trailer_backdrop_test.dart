import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/trailer_engine.dart';

void main() {
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets(
    'TV: an underlay engine accepts a foreground start and carries the '
    'fullscreen chrome with D-pad control',
    (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      final engine = _PendingFirstFrameEngine();
      var foreground = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              // The chrome's seek bar is a Slider — Material, as the detail
              // page's Scaffold provides in production.
              return Material(
                child: HeroTrailerBackdrop(
                  imageUrl: null,
                  videoUrl: 'https://example.invalid/trailer.mp4',
                  enabled: true,
                  foreground: foreground,
                  startDelay: Duration.zero,
                  videoBlurSigma: 0,
                  engineFactory: () async => engine,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      HeroTrailerBackdropState state() => tester
          .state<HeroTrailerBackdropState>(find.byType(HeroTrailerBackdrop));
      expect(engine.rendersUnderlay, isTrue);
      expect(engine.opened, isTrue);
      // Live but pre-frame: the buffer window a Trailer press can land in. The
      // native underlay is no longer a refusal — the press parks on the frame.
      expect(state().canPromote, isFalse);
      expect(state().requestForegroundStart(), isTrue);
      // The native firstFrame event (mapped to firstFrameRendered) is what
      // makes the surface promotable.
      final ready = state().whenPromotable();
      engine.renderFirstFrame();
      await tester.pump();
      expect(await ready, isTrue);
      expect(state().canPromote, isTrue);

      // Promote: unmuted to full on the native engine, chrome painted over the
      // underlay, and the chrome's node holds focus for the remote.
      rebuild(() => foreground = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.volumes.last, 100);
      expect(find.byTooltip('Close trailer'), findsOneWidget);
      final chrome = Focus.of(tester.element(find.byTooltip('Close trailer')));
      expect(chrome.hasPrimaryFocus, isTrue);
      // Select = pause, Select again = play; → seeks +10s.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(engine.pauses, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(engine.plays, greaterThanOrEqualTo(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(engine.seeks.last, const Duration(seconds: 10));

      // Demote: back to the ambient level, still playing, chrome gone.
      final playsBefore = engine.plays;
      rebuild(() => foreground = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.volumes.last, 70);
      expect(engine.plays, greaterThan(playsBefore));
      expect(engine.disposed, isFalse);
      expect(find.byTooltip('Close trailer'), findsNothing);
      // Drain the chrome auto-hide timer.
      await tester.pump(const Duration(seconds: 4));
    },
  );
  testWidgets('mounts the render surface before the first frame arrives', (
    tester,
  ) async {
    final engine = _PendingFirstFrameEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: HeroTrailerBackdrop(
          imageUrl: null,
          videoUrl: 'https://example.invalid/trailer.mp4',
          enabled: true,
          startDelay: Duration.zero,
          engineFactory: () async => engine,
        ),
      ),
    );
    // Advance the zero-duration start timer, then render the setState that
    // attaches the engine.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(engine.opened, isTrue);
    expect(engine.firstFrameCompleted, isFalse);
    expect(engine.buildVideoCalls, greaterThan(0));
  });

  testWidgets(
    'whenPromotable resolves true on the first frame and false on teardown',
    (tester) async {
      var engine = _PendingFirstFrameEngine();
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return HeroTrailerBackdrop(
                imageUrl: null,
                videoUrl: 'https://example.invalid/trailer.mp4',
                enabled: enabled,
                startDelay: Duration.zero,
                engineFactory: () async => engine,
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      HeroTrailerBackdropState state() => tester
          .state<HeroTrailerBackdropState>(find.byType(HeroTrailerBackdrop));
      expect(state().canPromote, isFalse);

      // Parked during the buffer window; the rendered frame releases it.
      var ready = state().whenPromotable();
      engine.renderFirstFrame();
      await tester.pump();
      expect(await ready, isTrue);
      expect(state().canPromote, isTrue);
      // Already promotable → answered at once.
      expect(await state().whenPromotable(), isTrue);

      // A teardown while parked (the master switch flips off) answers false
      // instead of leaving the caller waiting on a player that won't come.
      rebuild(() => enabled = false);
      await tester.pump();
      expect(state().canPromote, isFalse);
      engine = _PendingFirstFrameEngine();
      rebuild(() => enabled = true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      ready = state().whenPromotable();
      rebuild(() => enabled = false);
      await tester.pump();
      expect(await ready, isFalse);
    },
  );
}

/// Reports as the TV native-underlay engine ([rendersUnderlay] true).
class _PendingFirstFrameEngine implements TrailerEngine {
  final Completer<void> _firstFrame = Completer<void>();
  // Reports play/pause back like ExoPlayer's onIsPlayingChanged.
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  bool opened = false;
  bool disposed = false;
  int buildVideoCalls = 0;
  int plays = 0;
  int pauses = 0;
  final List<double> volumes = [];
  final List<Duration> seeks = [];

  bool get firstFrameCompleted => _firstFrame.isCompleted;

  void renderFirstFrame() {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  @override
  bool get rendersUnderlay => true;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<void> get errorStream => const Stream<void>.empty();

  @override
  Future<void> get firstFrameRendered => _firstFrame.future;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    opened = true;
    volumes.add(volume);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> play() async {
    plays++;
    if (!_playing.isClosed) _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    if (!_playing.isClosed) _playing.add(false);
  }

  @override
  void detach() {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _playing.close();
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) {
    buildVideoCalls++;
    return const SizedBox.expand();
  }
}
