import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Construction-only adaptation of 67ce7247. No decoder body is copied here.
// Scripted terminal metadata is not a decoded frame or native playback proof.
class _TerminalStreams extends mk.PlatformPlayer {
  _TerminalStreams(mk.PlayerConfiguration configuration)
    : super(configuration: configuration);
}

class _Properties implements mk.NativePlayer {
  _Properties(mk.PlayerConfiguration configuration, this.unexpected)
    : _streams = _TerminalStreams(configuration);

  final _TerminalStreams _streams;
  @override
  mk.PlayerConfiguration get configuration => _streams.configuration;
  @override
  mk.PlayerState get state => _streams.state;
  @override
  set state(mk.PlayerState value) => _streams.state = value;
  @override
  mk.PlayerStream get stream => _streams.stream;

  final List<String> unexpected;
  final reads = <String>[];
  final writes = <(String, String)>[];
  final scripts = <String, List<Future<String> Function()>>{};
  final responseOverrides = <String, String>{};
  final holds = <Completer<String>>[];
  bool allowMediaSwitch = false;

  Completer<String> holdNext(String property) {
    final held = Completer<String>();
    holds.add(held);
    scripts.putIfAbsent(property, () => []).add(() => held.future);
    return held;
  }
  bool closed = false;
  static const replies = {
    'hwdec-current': 'no',
    'current-vo': 'gpu',
    'current-ao': 'wasapi',
    'audio-out-params/channel-count': '2',
    'video-codec': 'h264',
    'audio-codec-name': 'aac',
    'audio-params/channel-count': '2',
    'audio-out-params/format': 'float',
  };

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    reads.add(property);
    if (!replies.containsKey(property)) {
      unexpected.add('getProperty:$property');
      throw StateError('Unscripted property $property');
    }
    final queue = scripts[property];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0)();
    return responseOverrides[property] ?? replies[property]!;
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    writes.add((property, value));
    if (property != 'video-zoom' &&
        !(allowMediaSwitch &&
            {'stream-lavf-o', 'sub-visibility', 'sub-delay'}.contains(property))) {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  void emitParams(mk.VideoParams params) {
    state = state.copyWith(videoParams: params);
    _streams.videoParamsController.add(params);
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    closed = true;
    await _streams.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('native:${invocation.memberName}');
    throw StateError('Unexpected native API ${invocation.memberName}');
  }
}

class _Player implements mk.Player {
  _Player(this.backend);
  final _Properties backend;

  @override
  mk.PlatformPlayer? get platform => backend;
  @override
  set platform(mk.PlatformPlayer? value) =>
      throw StateError('Unexpected platform replacement');
  @override
  mk.PlayerState get state => backend.state;
  @override
  mk.PlayerStream get stream => backend.stream;
  @override
  Future<void> dispose() => backend.dispose();

  final actions = <String>[];
  final opened = <mk.Playable>[];
  final openPlay = <bool>[];
  final subtitleIds = <String>[];

  void _requireMediaSwitch(String action) {
    if (!backend.allowMediaSwitch) {
      backend.unexpected.add('player:$action');
      throw StateError('Unscripted player action $action');
    }
    actions.add(action);
  }

  @override
  Future<void> pause() async => _requireMediaSwitch('pause');

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    _requireMediaSwitch('open');
    openPlay.add(play);
    opened.add(playable);
  }

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    _requireMediaSwitch('subtitle:${track.id}');
    subtitleIds.add(track.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    backend.unexpected.add('player:${invocation.memberName}');
    throw StateError('Unexpected player API ${invocation.memberName}');
  }
}

class _TexturelessVideo implements mkv.VideoController {
  _TexturelessVideo(this.player, this.unexpected);
  @override
  final mk.Player player;
  final List<String> unexpected;
  @override
  final platform = Completer<mkv.PlatformVideoController>();
  @override
  final notifier = ValueNotifier<mkv.PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);

  void close() {
    notifier.dispose();
    id.dispose();
    rect.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('video:${invocation.memberName}');
    throw StateError('Unexpected video API ${invocation.memberName}');
  }
}

class _Terminal extends PlayerTerminalBackend {
  final construction = <String>[];
  final unexpected = <String>[];
  _Properties? properties;
  _Player? player;
  _TexturelessVideo? video;

  @override
  void ensureInitialized() {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('bootstrap');
  }

  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('player');
    expect(configuration.logLevel, mk.MPVLogLevel.error);
    expect(configuration.ready, isNotNull);
    properties = _Properties(configuration, unexpected);
    return player = _Player(properties!);
  }

  @override
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('video');
    expect(player, same(this.player));
    return video = _TexturelessVideo(player, unexpected);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late _Terminal terminal;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'decoder-terminal-origin');
    StorageService.resetProfileCaches();
    final root = await Directory('.dart_tool').absolute.createTemp('decoder-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (
      call,
    ) async {
      switch (call.method) {
        case 'setFullScreen':
        case 'setBounds':
          return null;
        case 'getBounds':
          return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 720.0};
        case 'isFullScreen':
          return false;
        default:
          terminal.unexpected.add('window:${call.method}');
          throw StateError('Unexpected window call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(
      wake,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, (
      call,
    ) async {
      if (call.method == 'resetApplicationScreenBrightness') return null;
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      if (terminal.properties != null && !terminal.properties!.closed) {
        await terminal.properties!.dispose();
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
    } finally {
      PlayerTerminalBackend.debugOverride = previous;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
    }
  });

  const cycle = [
    'hwdec-current',
    'current-vo',
    'current-ao',
    'audio-out-params/channel-count',
  ];
  const tail = [
    'video-codec',
    'audio-codec-name',
    'audio-params/channel-count',
    'audio-out-params/format',
  ];
  const params = mk.VideoParams(w: 1280, h: 720);

  Future<void> arm(WidgetTester tester, [mk.VideoParams value = params]) async {
    terminal.properties!.emitParams(value);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> withHost(
    WidgetTester tester,
    Future<void> Function(_Properties, List<String>) exercise, {
    Future<Map<String, dynamic>?> Function()? next,
  }) async {
    final diagnostics = <String>[];
    await runZoned(() async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(MaterialApp(
          builder: (_, child) => AppThemeScope(
            theme: AppThemes.byId('spotlight'), child: child!),
          home: VideoPlayerScreen(
            videoUrl: '', title: 'Terminal diagnostic fixture',
            disableAutoResume: true, requestNextChannel: next),
        ));
        for (var i = 0; i < 20 && terminal.video == null; i++) {
          await tester.pump();
        }
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        final backend = terminal.properties!;
        backend.configuration.ready!();
        await tester.pump();
        expect(find.byType(Controls), findsOneWidget);
        expect(backend.reads, isEmpty);
        await exercise(backend, diagnostics);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Release any held terminal replies after host disposal even if an
        // assertion fails. No outstanding fake I/O survives override restoration.
        for (final held in terminal.properties?.holds ?? <Completer<String>>[]) {
          if (!held.isCompleted) held.complete('no');
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(terminal.unexpected, isEmpty);
      expect(terminal.properties!.closed, isTrue);
      expect(VideoOutputLease.isHeld, isFalse);
    }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      if (line.startsWith('DEBRIFY_PLAYER_DECODER ')) diagnostics.add(line);
      parent.print(zone, line);
    }));
  }

  testWidgets('completed probes dedupe but changed resolution reports', (tester) async {
    await withHost(tester, (backend, diagnostics) async {
      await arm(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.reads, [...cycle, ...cycle, ...tail]);
      expect(diagnostics, hasLength(1));
      await arm(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.reads, [
        ...cycle, ...cycle, ...tail, ...cycle, ...cycle, ...tail,
      ]);
      expect(diagnostics, hasLength(1));
      await arm(tester, const mk.VideoParams(w: 1920, h: 1080));
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.reads.length, 36);
      expect(diagnostics, hasLength(2));
      expect(diagnostics.last, contains('resolution=1920x1080'));
    });
  });

  testWidgets('invalid params stop the next poll after held success, then recover', (tester) async {
    await withHost(tester, (backend, diagnostics) async {
      final held = backend.holdNext('hwdec-current');
      await arm(tester);
      expect(backend.reads, ['hwdec-current']);
      backend.emitParams(const mk.VideoParams(w: 0, h: 0));
      await tester.pump();
      held.complete('no');
      await tester.pump();
      expect(backend.reads, cycle); // No guard between the four awaits.
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.reads, cycle);
      expect(diagnostics, isEmpty);
      await arm(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.reads, [...cycle, ...cycle, ...cycle, ...tail]);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('phase=stable'));
    });
  });

  testWidgets('held errors ignore token changes, dedupe, but stop after disposal', (tester) async {
    await withHost(tester, (backend, diagnostics) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        final held = backend.holdNext('hwdec-current');
        await arm(tester);
        expect(backend.reads.length, attempt + 1);
        backend.emitParams(const mk.VideoParams(w: 0, h: 0));
        await tester.pump();
        held.completeError(StateError('scripted property refusal'));
        await tester.pump();
        expect(diagnostics, hasLength(1));
        expect(diagnostics.single, contains('phase=error status=unavailable'));
        expect(diagnostics.single, contains('reason=property_query_failed'));
      }
      final held = backend.holdNext('hwdec-current');
      await arm(tester);
      expect(backend.reads, ['hwdec-current', 'hwdec-current', 'hwdec-current']);
      await tester.pumpWidget(const SizedBox.shrink());
      held.completeError(StateError('scripted post-dispose refusal'));
      await tester.pump();
      expect(diagnostics, hasLength(1));
    });
  });

  testWidgets('token invalidation during tail reads still reports stable metadata', (tester) async {
    await withHost(tester, (backend, diagnostics) async {
      final held = backend.holdNext('video-codec');
      await arm(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.reads, [...cycle, ...cycle, 'video-codec']);
      expect(diagnostics, isEmpty);
      backend.emitParams(const mk.VideoParams(w: 0, h: 0));
      await tester.pump();
      held.complete('h264');
      await tester.pump();
      expect(backend.reads, [...cycle, ...cycle, ...tail]);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('phase=stable status=software'));
      expect(diagnostics.single, contains('resolution=1280x720'));
    });
  });

  testWidgets('twelve incomplete cycles include final delay before partial report', (tester) async {
    await withHost(tester, (backend, diagnostics) async {
      backend.responseOverrides.addAll({
        'current-vo': 'null', 'current-ao': '',
        'audio-out-params/channel-count': '',
      });
      await arm(tester);
      final expected = <String>[...cycle];
      expect(backend.reads, expected);
      // Exactly eleven further cycles. This is a fixed clock trace, not polling.
      for (var attempt = 1; attempt < 12; attempt++) {
        await tester.pump(const Duration(milliseconds: 250));
        expected.addAll(cycle);
        expect(backend.reads, expected);
        expect(diagnostics, isEmpty);
      }
      await tester.pump(const Duration(milliseconds: 249));
      expect(backend.reads, expected);
      expect(diagnostics, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(backend.reads, [...expected, ...tail]);
      expect(backend.reads, hasLength(52));
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('phase=partial status=software'));
      expect(diagnostics.single, contains('output=unknown'));
    });
  });

  testWidgets('public next channel invalidates held error and resets diagnostic dedupe', (tester) async {
    var requests = 0;
    await withHost(tester, (backend, diagnostics) async {
      await arm(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('generation=0'));
      final held = backend.holdNext('hwdec-current');
      await arm(tester);
      expect(backend.reads.length, 13);
      backend.allowMediaSwitch = true;
      final controls = tester.widget<Controls>(find.byType(Controls));
      expect(controls.onNextChannel, isNotNull);
      controls.onNextChannel!(); // Actual public host callback, no State access.
      await tester.pump();
      expect(requests, 1);
      expect(terminal.player!.opened, hasLength(1));
      expect((terminal.player!.opened.single as mk.Media).uri,
          'https://decoder.invalid/next.mkv');
      expect(terminal.player!.actions, ['pause', 'open', 'subtitle:no']);
      expect(terminal.player!.openPlay, [true]);
      expect(terminal.player!.subtitleIds, ['no']);
      // The real subtitle application waits 50ms before returning to the host.
      await tester.pump(const Duration(milliseconds: 50));
      held.completeError(StateError('scripted old-media refusal'));
      await tester.pump();
      expect(diagnostics, hasLength(1));
      await arm(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(diagnostics, hasLength(2));
      expect(diagnostics.last, contains('generation=1 phase=stable'));
      expect(diagnostics.last, contains('resolution=1280x720'));
    }, next: () async {
      requests++;
      return {'url': 'https://decoder.invalid/next.mkv', 'title': 'Next fixture'};
    });
  });

  testWidgets('actual host probes after 150ms and requires two ordered matches', (
    tester,
  ) async {
    final diagnostics = <String>[];
    await runZoned(
      () async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(
            MaterialApp(
              builder: (_, child) => AppThemeScope(
                theme: AppThemes.byId('spotlight'),
                child: child!,
              ),
              home: const VideoPlayerScreen(
                videoUrl: '',
                title: 'Terminal diagnostic fixture',
                disableAutoResume: true,
              ),
            ),
          );
          // Bounded microtask/frame draining for real asynchronous preferences/init.
          for (var i = 0; i < 20 && terminal.video == null; i++) {
            await tester.pump();
          }
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
          final backend = terminal.properties!;
          backend
              .configuration
              .ready!(); // Actual host callback; no State access.
          await tester.pump();
          expect(find.byType(Controls), findsOneWidget);
          expect(terminal.unexpected, isEmpty);
          expect(backend.reads, isEmpty);
          const params = mk.VideoParams(w: 1280, h: 720);
          backend.emitParams(params);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 149));
          expect(backend.reads, isEmpty);
          await tester.pump(const Duration(milliseconds: 1));
          const cycle = [
            'hwdec-current',
            'current-vo',
            'current-ao',
            'audio-out-params/channel-count',
          ];
          expect(backend.reads, cycle);
          expect(diagnostics, isEmpty);
          await tester.pump(const Duration(milliseconds: 249));
          expect(backend.reads, cycle);
          await tester.pump(const Duration(milliseconds: 1));
          expect(backend.reads, [
            ...cycle,
            ...cycle,
            'video-codec',
            'audio-codec-name',
            'audio-params/channel-count',
            'audio-out-params/format',
          ]);
          expect(diagnostics, hasLength(1));
          expect(diagnostics.single, contains('phase=stable status=software'));
          expect(diagnostics.single, contains('output=gpu'));
          expect(diagnostics.single, contains('resolution=1280x720'));
          // The same live params re-arm the real probe; disposal cancels its timer.
          backend.emitParams(params);
          await tester.pump();
          final readsBeforeDispose = List<String>.of(backend.reads);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 500));
          expect(backend.reads, readsBeforeDispose);
          expect(diagnostics, hasLength(1));
          expect(backend.closed, isTrue);
          expect(VideoOutputLease.isHeld, isFalse);
          expect(terminal.unexpected, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          if (line.startsWith('DEBRIFY_PLAYER_DECODER ')) diagnostics.add(line);
          parent.print(
            zone,
            line,
          ); // Preserve every raw diagnostic; no suppression.
        },
      ),
    );
  });
}
