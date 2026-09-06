import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/aspect_ratio_hud.dart';
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
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Harness adapted from the accepted construction-assisted decoder fixture.
// Only external SDK state and terminal operations are scripted; host controls,
// gesture policy, aspect conversion and resume persistence remain real lib code.
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
  bool closed = false;
  Future<void>? disposal;
  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    reads.add(property);
    unexpected.add('getProperty:$property');
    throw StateError('Unscripted property $property');
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    writes.add((property, value));
    if (property != 'video-zoom') {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  void emitPlayback(Duration position) {
    state = state.copyWith(
      playing: true,
      duration: const Duration(minutes: 10),
      position: position,
    );
    _streams.durationController.add(state.duration);
    _streams.positionController.add(position);
    _streams.playingController.add(true);
  }

  @override
  Future<void> dispose({bool synchronized = true}) =>
      disposal ??= closeStreams();
  Future<void> closeStreams() async {
    await _streams.dispose();
    closed = true;
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

  final rates = <double>[];
  @override
  Future<void> setRate(double value) async {
    rates.add(value);
    backend.state = backend.state.copyWith(rate: value);
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
  Object? primaryFailure;
  StackTrace? primaryStack;

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
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('presentation-');
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
    } catch (error, stack) {
      debugPrintSynchronously('PRESENTATION_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
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

  Future<void> withHost(
    WidgetTester tester,
    Future<void> Function(_Properties) exercise,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    primaryFailure = null;
    primaryStack = null;
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
          home: const VideoPlayerScreen(
            videoUrl: '',
            title: 'Presentation fixture',
            disableAutoResume: true,
          ),
        ),
      );
      // Accepted fixture construction bound, not a behavior timing assertion.
      for (var i = 0; i < 20 && terminal.video == null; i++) {
        await tester.pump();
      }
      expect(terminal.construction, ['bootstrap', 'player', 'video']);
      final backend = terminal.properties!;
      backend.configuration.ready!();
      backend.emitPlayback(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(Controls), findsOneWidget);
      expect(backend.reads, isEmpty);
      await exercise(backend);
      expect(terminal.unexpected, isEmpty);
    } catch (error, stack) {
      primaryFailure = error;
      primaryStack = stack;
      debugPrintSynchronously('PRESENTATION_PRIMARY $error\n$stack');
      rethrow;
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
        if (terminal.properties != null) await terminal.properties!.dispose();
        expect(VideoOutputLease.isHeld, isFalse);
        expect(terminal.unexpected, isEmpty);
      } catch (error, stack) {
        debugPrintSynchronously('PRESENTATION_CLEANUP $error\n$stack');
        if (primaryFailure != null) {
          Error.throwWithStackTrace(primaryFailure!, primaryStack!);
        }
        rethrow;
      }
    }
  }

  PlayerMenuPanel menu(WidgetTester tester) =>
      tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
  Future<void> closeMenu(WidgetTester tester) async {
    menu(tester).onClose();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlayerMenuPanel), findsNothing);
  }

  testWidgets(
    'public speed menu and pointer hold restore speed and save prior speed on disposal',
    (tester) async {
      await withHost(tester, (backend) async {
        tester.widget<Controls>(find.byType(Controls)).onSpeed();
        await tester.pump();
        menu(tester).onSpeedSelected(1.25);
        await tester.pump();
        expect(terminal.player!.rates, [1.25]);
        expect(tester.widget<Controls>(find.byType(Controls)).speed, 1.25);
        final selected = await StorageService.getVideoPlaybackState(
          videoTitle: 'Presentation fixture',
        );
        expect(selected, isNotNull);
        expect(selected!['speed'], 1.25);
        await closeMenu(tester);

        final hold = await tester.startGesture(const Offset(640, 360));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
        await tester.pump();
        expect(terminal.player!.rates, [1.25, 2.0]);
        expect(tester.widget<Controls>(find.byType(Controls)).speed, 2.0);
        final hud = find.ancestor(
          of: find.text('2× Speed'),
          matching: find.byType(AnimatedOpacity),
        );
        expect(tester.widget<AnimatedOpacity>(hud).opacity, 1);
        await hold.up();
        await tester.pump();
        expect(terminal.player!.rates, [1.25, 2.0, 1.25]);
        expect(tester.widget<Controls>(find.byType(Controls)).speed, 1.25);
        expect(tester.widget<AnimatedOpacity>(hud).opacity, 0);

        final heldAtDisposal = await tester.startGesture(
          const Offset(640, 360),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
        await tester.pump();
        expect(terminal.player!.rates, [1.25, 2.0, 1.25, 2.0]);
        backend.emitPlayback(const Duration(seconds: 4));
        await tester.pump();
        final before = await StorageService.getVideoPlaybackState(
          videoTitle: 'Presentation fixture',
        );
        expect(before!['positionMs'], lessThan(4000));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
        await backend.dispose();
        final disposed = await StorageService.getVideoPlaybackState(
          videoTitle: 'Presentation fixture',
        );
        expect(disposed!['positionMs'], 4000);
        expect(disposed['speed'], 1.25);
        expect(terminal.player!.rates.last, 2.0);
        expect(VideoOutputLease.isHeld, isFalse);
        await heldAtDisposal.up();
      });
    },
  );

  testWidgets(
    'public aspect selection no-op and desktop cycle apply zoom and preserve HUD disposal',
    (tester) async {
      await withHost(tester, (backend) async {
        tester.widget<Controls>(find.byType(Controls)).onAspect();
        await tester.pump();
        final initialWrites = backend.writes.length;
        menu(tester).onAspectSelected(AspectMode.cinemaZoom);
        await tester.pump();
        expect(backend.writes.skip(initialWrites).toList(), [
          ('video-zoom', '0.415037'),
        ]);
        expect(
          tester.widget<Controls>(find.byType(Controls)).aspectMode,
          AspectMode.cinemaZoom,
        );
        final selected = await StorageService.getVideoPlaybackState(
          videoTitle: 'Presentation fixture',
        );
        expect(selected!['aspect'], 'cinemaZoom');
        final count = backend.writes.length;
        menu(tester).onAspectSelected(AspectMode.cinemaZoom);
        await tester.pump();
        expect(backend.writes, hasLength(count));
        await closeMenu(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();
        expect(
          tester.widget<Controls>(find.byType(Controls)).aspectMode,
          AspectMode.contain,
        );
        expect(backend.writes.last, ('video-zoom', '0.000000'));
        final containHud = find.descendant(
          of: find.byType(AspectRatioHud), matching: find.text('Contain'));
        expect(containHud, findsOneWidget);
        final cycled = await StorageService.getVideoPlaybackState(
          videoTitle: 'Presentation fixture',
        );
        expect(cycled!['aspect'], 'contain');
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pump();
        expect(containHud, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();
        expect(
          tester.widget<Controls>(find.byType(Controls)).aspectMode,
          AspectMode.cover,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1500));
        expect(tester.takeException(), isNull);
      });
    },
  );
}
