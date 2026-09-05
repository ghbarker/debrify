import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
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

// RETROSPECTIVE feasibility only, not pin-before-move compliance or V1 coverage.
// Identical bytes with Flutter 3.44.8 target the original V1-1 parent
// bc46babab2e1f1b367c3e5d89505dee1d0b64b93 and current production base
// 90b77818e951295a12cca8d410384a3a7d5541ed.
// LIBMPV_LIBRARY_PATH points at an already-installed native library. The window
// and texture channel fixtures are external platform replies, not player logic.
// Audio decoding/host mount/disposal and the host's identify-cancel path are proven.
// The zero-width audio source
// does NOT satisfy the video startup watchdog. No rendered frame, successful
// video readiness, successful identification, resume/subtitle application or
// recording/zap is claimed.

class _Routes extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

Map<String, Object?> _prefsSnapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Uint8List _silentWave() {
  const dataSize = 8000 * 2 * 60;
  final bytes = Uint8List(44 + dataSize);
  final header = ByteData.sublistView(bytes);
  void ascii(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVEfmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 8000, Endian.little);
  header.setUint32(28, 16000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataSize, Endian.little);
  return bytes;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: 'Real native host did not reach readiness');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File media;
  final outputCalls = <String>[];
  const videoChannel = MethodChannel('com.alexmercerind/media_kit_video');
  const windowChannel = MethodChannel('window_manager');
  const brightnessChannel = MethodChannel(
    'github.com/aaassseee/screen_brightness',
  );
  const wakeChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'v1-native-origin');
    StorageService.resetProfileCaches();
    root = await Directory('.dart_tool').absolute.createTemp('v1-host-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    media = File('${root.path}/Origin.wav');
    await media.writeAsBytes(_silentWave());
    outputCalls.clear();
    mk.MediaKit.ensureInitialized(
      libmpv: Platform.environment['LIBMPV_LIBRARY_PATH'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
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
          throw StateError('Unexpected window call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(
      wakeChannel,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightnessChannel, (
      call,
    ) async {
      switch (call.method) {
        case 'resetApplicationScreenBrightness':
          return null;
        default:
          throw StateError('Unexpected brightness call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(videoChannel, (
      call,
    ) async {
      outputCalls.add(call.method);
      switch (call.method) {
        case 'VideoOutputManager.Create':
          final handle = int.parse(call.arguments['handle'] as String);
          // A texture allocation reply, with no rendered frame claimed.
          await binding.defaultBinaryMessenger.handlePlatformMessage(
            videoChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('VideoOutput.Resize', {
                'handle': handle,
                'id': 1,
                'rect': {'left': 0, 'top': 0, 'width': 0, 'height': 0},
              }),
            ),
            (_) {},
          );
          return null;
        case 'VideoOutputManager.SetSize':
        case 'VideoOutputManager.Dispose':
          return null;
        default:
          throw StateError('Unexpected video output call ${call.method}');
      }
    });
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(videoChannel, null);
    binding.defaultBinaryMessenger.setMockMessageHandler(wakeChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      brightnessChannel,
      null,
    );
    await DebrifyTvDatabase.instance.debugResetScopeState();
    StorageService.resetProfileCaches();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    await root.delete(recursive: true);
  });

  testWidgets('retrospective origin: actual host identify cancel preserves state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final routes = _Routes();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        builder: (_, child) =>
            AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
        home: VideoPlayerScreen(
          videoUrl: media.uri.toString(),
          title: 'Origin.wav',
          disableAutoResume: true,
        ),
      ),
    );
    await _until(tester, () => find.byType(mkv.Video).evaluate().isNotEmpty);
    final player = tester
        .widget<mkv.Video>(find.byType(mkv.Video))
        .controller
        .player;
    await _until(
      tester,
      () => player.state.duration == const Duration(seconds: 60),
    );
    expect(player.platform, isA<mk.NativePlayer>());
    await _until(
      tester,
      () => player.state.position > const Duration(seconds: 1),
    );
    expect(outputCalls, contains('VideoOutputManager.Create'));
    expect(find.byType(VideoPlayerScreen), findsOneWidget);

    try {
      // Capture callbacks from widgets built by the actual host State. No local
      // controller/session surrogate, private access or extracted route import.
      final controls = tester.widget<Controls>(find.byType(Controls));
      controls.onSpeed();
      await tester.pump();
      final menu = tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
      expect(menu.onIdentifyTitle, isNotNull);
      final identityBefore = [
        menu.contentImdbId,
        menu.contentType,
        menu.contentSeason,
        menu.contentEpisode,
        menu.subtitleIdentityLabel,
        menu.selectedSubtitleId,
      ];
      final prefs = await SharedPreferences.getInstance();
      final prefsBefore = _prefsSnapshot(prefs);
      final audioBefore = player.state.track.audio.id;
      final subtitleBefore = player.state.track.subtitle.id;
      var completed = false;
      Object? result = Object();
      final completion = menu.onIdentifyTitle!().then((value) {
        result = value;
        completed = true;
      });
      await _until(
        tester,
        () => find.text('FIX THE TITLE').evaluate().isNotEmpty,
      );
      expect(completed, isFalse);
      expect(
        routes.pushes,
        2,
      ); // Actual player route and actual identify route.
      expect(routes.pops, 0);
      await tester.pump(const Duration(milliseconds: 300));
      final header = find
          .ancestor(of: find.text('FIX THE TITLE'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: header, matching: find.byType(IconButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _until(tester, () => completed);
      await completion;
      expect(result, isNull);
      expect(find.text('FIX THE TITLE'), findsNothing);
      expect(routes.pops, 1);
      expect(find.byType(PlayerMenuPanel), findsOneWidget);
      expect(player.state.track.audio.id, audioBefore);
      expect(player.state.track.subtitle.id, subtitleBefore);
      expect(_prefsSnapshot(prefs), prefsBefore);
      // Reopen from the real host so stale widget configuration cannot hide an
      // accidental identity/selection mutation behind the cancelled route.
      tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).onClose();
      await tester.pump();
      tester.widget<Controls>(find.byType(Controls)).onSpeed();
      await tester.pump();
      final reopened = tester.widget<PlayerMenuPanel>(
        find.byType(PlayerMenuPanel),
      );
      expect([
        reopened.contentImdbId,
        reopened.contentType,
        reopened.contentSeason,
        reopened.contentEpisode,
        reopened.subtitleIdentityLabel,
        reopened.selectedSubtitleId,
      ], identityBefore);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _until(tester, () => !VideoOutputLease.isHeld);
      expect(outputCalls, contains('VideoOutputManager.Dispose'));
      // NativePlayer open/dispose and startup readiness create timeout futures.
      // Allow them to expire after unmount; never suppress pending-timer failures.
      await tester.pump(const Duration(seconds: 15));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 6));
    }
  });
}
