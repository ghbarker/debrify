import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_detail/detail_trailer_controller.dart';
import 'package:debrify/services/storage/ambient_trailer_prefs.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/trailer_engine.dart';

/// The Trailer press must end in full-page IN-APP playback off-TV — the
/// backdrop's own player promoted in place — whatever state the ambient
/// pipeline is in when the user presses. The standalone player is the
/// fallback only where the in-place path is impossible (TV here).
///
/// Drives the real [DetailTrailerController] + [HeroTrailerBackdrop] pair
/// through a host wired exactly as `MergedDetailScreen` wires them (URL and
/// enabled follow `foregroundRequested`), with a scripted engine standing in
/// for the platform decoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const streams = YoutubeResolvedStreams(
    playUrl: 'https://example.invalid/trailer-video.mp4',
    audioUrl: 'https://example.invalid/trailer-audio.m4a',
  );

  Future<_Harness> pumpHost(
    WidgetTester tester, {
    bool autoplay = true,
    bool isTelevision = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AmbientTrailerPrefs.setDetailTrailerAutoplayEnabled(autoplay);
    final harness = _Harness();
    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          isTelevision: isTelevision,
          engineFactory: () async {
            final engine = _ScriptedEngine();
            harness.engines.add(engine);
            return engine;
          },
          resolver: (ytId) async {
            harness.resolves.add(ytId);
            return streams;
          },
          launcher: (context, args) async {
            harness.launches.add(args);
          },
        ),
      ),
    );
    // load(): prefs reads → resolve → (autoplay) the zero-delay start timer →
    // the async engine factory → the setState that attaches the engine.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    return harness;
  }

  DetailTrailerController controllerOf(WidgetTester tester) =>
      tester.state<_HostState>(find.byType(_Host)).trailer;

  HeroTrailerBackdropState backdropOf(WidgetTester tester) =>
      tester.state<HeroTrailerBackdropState>(find.byType(HeroTrailerBackdrop));

  /// Clears the 25s autoplay-spinner safety net and the foreground chrome's
  /// auto-hide so no timer outlives the test.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 26));
  }

  testWidgets(
    'a press while the ambient trailer is still buffering promotes on the '
    'first frame — no standalone player',
    (tester) async {
      final h = await pumpHost(tester);
      final trailer = controllerOf(tester);
      expect(trailer.autoplayEnabled, isTrue);
      expect(h.engines, hasLength(1));
      final engine = h.engines.single;
      expect(engine.opened, isTrue);
      // The buffer window: engine live, no frame yet → not promotable.
      expect(backdropOf(tester).canPromote, isFalse);

      await tester.tap(find.text('Trailer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // Waiting, visibly, and nothing was launched or promoted onto black.
      expect(trailer.loading, isTrue);
      expect(trailer.foreground, isFalse);
      expect(find.text('Loading trailer…'), findsOneWidget);
      expect(h.launches, isEmpty);
      // The same engine is kept — the fresh resolve returned the same URL.
      expect(h.engines, hasLength(1));

      engine.renderFirstFrame();
      await tester.pump();
      await tester.pump();

      expect(trailer.foreground, isTrue);
      expect(trailer.loading, isFalse);
      expect(h.launches, isEmpty);
      expect(backdropOf(tester).canPromote, isTrue);
      // Promotion is audible and playing; the watch starts at the top rather
      // than past the ambient intro skip.
      expect(engine.volumes.last, 100);
      expect(engine.seeks, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byTooltip('Close trailer'), findsOneWidget);

      await drain(tester);
    },
  );

  testWidgets(
    'with autoplay off a press starts the backdrop engine, then promotes it',
    (tester) async {
      final h = await pumpHost(tester, autoplay: false);
      final trailer = controllerOf(tester);
      expect(trailer.autoplayEnabled, isFalse);
      expect(trailer.streams, isNull);
      expect(h.engines, isEmpty);
      expect(h.resolves, isEmpty);

      await tester.tap(find.text('Trailer'));
      await tester.pump();
      // Resolve lands → the host hands the URL over → zero-delay start → the
      // async factory → engine attached.
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));

      expect(h.resolves, ['synthetic-trailer']);
      expect(trailer.foregroundRequested, isTrue);
      expect(h.engines, hasLength(1));
      final engine = h.engines.single;
      expect(engine.opened, isTrue);
      expect(trailer.foreground, isFalse);
      expect(h.launches, isEmpty);

      engine.renderFirstFrame();
      await tester.pump();
      await tester.pump();

      expect(trailer.foreground, isTrue);
      expect(h.launches, isEmpty);
      expect(engine.volumes.last, 100);

      // Closing hands the surface back to the ambient rules — and with
      // autoplay off that means no player at all.
      trailer.exitForeground(tester.element(find.byType(_Host)));
      await tester.pump();
      await tester.pump();

      expect(trailer.foreground, isFalse);
      expect(trailer.foregroundRequested, isFalse);
      expect(engine.disposed, isTrue);
      expect(backdropOf(tester).canPromote, isFalse);
      await tester.pump();
      expect(trailer.ambientPlaying, isFalse);

      await drain(tester);
    },
  );

  testWidgets('closing the fullscreen trailer restores the ambient loop', (
    tester,
  ) async {
    final h = await pumpHost(tester);
    final trailer = controllerOf(tester);
    final engine = h.engines.single;
    engine.renderFirstFrame();
    await tester.pump();
    await tester.pump();
    expect(trailer.ambientPlaying, isTrue);
    expect(backdropOf(tester).canPromote, isTrue);
    // The ambient loop skipped its intro card.
    expect(engine.seeks, [const Duration(seconds: 5)]);

    // Seamless: frames on screen → promoted in place, synchronously.
    await tester.tap(find.text('Trailer'));
    await tester.pump();
    expect(trailer.foreground, isTrue);
    expect(trailer.ambientPlaying, isFalse);
    expect(engine.volumes.last, 100);
    expect(h.launches, isEmpty);
    // Only the ambient prefetch resolved — the seamless path re-resolves
    // nothing.
    expect(h.resolves, hasLength(1));

    trailer.exitForeground(tester.element(find.byType(_Host)));
    await tester.pump();
    await tester.pump();

    expect(trailer.foreground, isFalse);
    // Same engine, quiet again, still promotable, and reported as ambient.
    expect(h.engines, hasLength(1));
    expect(engine.disposed, isFalse);
    expect(engine.volumes.last, 70);
    expect(backdropOf(tester).canPromote, isTrue);
    expect(trailer.ambientPlaying, isTrue);

    await drain(tester);
  });

  testWidgets('TV without frames on screen keeps the standalone player', (
    tester,
  ) async {
    // The backdrop is never asked to start for the press, exactly as before.
    final h = await pumpHost(tester, autoplay: false, isTelevision: true);
    final trailer = controllerOf(tester);

    await tester.tap(find.text('Trailer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(h.launches, hasLength(1));
    expect(h.launches.single.videoUrl, streams.playUrl);
    expect(h.launches.single.audioUrl, streams.audioUrl);
    expect(h.engines, isEmpty);
    expect(trailer.foreground, isFalse);
    expect(trailer.foregroundRequested, isFalse);
    await drain(tester);
  });

  testWidgets('TV with frames on screen keeps its in-place promotion', (
    tester,
  ) async {
    final h = await pumpHost(tester, isTelevision: true);
    final trailer = controllerOf(tester);
    h.engines.single.renderFirstFrame();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Trailer'));
    await tester.pump();
    expect(trailer.foreground, isTrue);
    expect(h.launches, isEmpty);
    await drain(tester);
  });
}

class _Harness {
  final List<_ScriptedEngine> engines = [];
  final List<String> resolves = [];
  final List<VideoPlayerLaunchArgs> launches = [];
}

/// Wired like `MergedDetailScreen`: the backdrop's URL and enabled follow the
/// controller's `foregroundRequested` alongside the autoplay setting.
class _Host extends StatefulWidget {
  const _Host({
    required this.isTelevision,
    required this.engineFactory,
    required this.resolver,
    required this.launcher,
  });

  final bool isTelevision;
  final Future<TrailerEngine> Function() engineFactory;
  final Future<YoutubeResolvedStreams?> Function(String ytId) resolver;
  final Future<void> Function(BuildContext, VideoPlayerLaunchArgs) launcher;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  static const _item = StremioMeta(
    id: 'tt0000001',
    type: 'movie',
    name: 'Trailer Movie',
    trailerYtId: 'synthetic-trailer',
  );

  final FocusNode _leftEntry = FocusNode();

  late final DetailTrailerController trailer = DetailTrailerController(
    read: () => DetailTrailerInputs(
      routeItem: _item,
      item: _item,
      isTelevision: widget.isTelevision,
      leftEntryFocusNode: _leftEntry,
    ),
    streamResolver: widget.resolver,
    standaloneLauncher: widget.launcher,
  );

  bool get _wantsTrailerVideo =>
      trailer.foregroundRequested || trailer.autoplayEnabled;

  @override
  void initState() {
    super.initState();
    trailer.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) trailer.load(context);
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    trailer.removeListener(_rebuild);
    trailer.dispose();
    _leftEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: HeroTrailerBackdrop(
              key: trailer.backdropKey,
              imageUrl: null,
              videoUrl: _wantsTrailerVideo ? trailer.streams?.playUrl : null,
              audioUrl: _wantsTrailerVideo ? trailer.streams?.audioUrl : null,
              startDelay: Duration.zero,
              enabled: trailer.autoplayEnabled || trailer.foregroundRequested,
              foreground: trailer.foreground,
              onRequestClose: () => trailer.exitForeground(context),
              onPlayingChanged: trailer.setAmbientPlaying,
              engineFactory: widget.engineFactory,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: trailer.foreground,
              child: Center(
                child: TextButton(
                  onPressed: () => trailer.play(context),
                  child: const Text('Trailer'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A decoder stand-in whose first frame the test releases by hand.
class _ScriptedEngine implements TrailerEngine {
  final Completer<void> _firstFrame = Completer<void>();
  bool opened = false;
  bool disposed = false;
  final List<double> volumes = [];
  final List<Duration> seeks = [];

  void renderFirstFrame() {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  @override
  bool get rendersUnderlay => false;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

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
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  void detach() {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) =>
      const SizedBox.expand();
}
