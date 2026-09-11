import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:debrify/services/ui_frame_diagnostics.dart';
import 'package:debrify/services/profiles/privacy_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> events;
  late List<String> lines;
  UiFrameDiagnostics make({bool enabled = true}) => UiFrameDiagnostics(
    enabled: enabled,
    captureDuration: const Duration(seconds: 5),
    emit: (line) {
      lines.add(line);
      events.add(
        Map.fromEntries(
          line.substring('DEBRIFY_PERF '.length).split('\t').map((field) {
            final separator = field.indexOf('=');
            return MapEntry(
              field.substring(0, separator),
              jsonDecode(field.substring(separator + 1)),
            );
          }),
        ),
      );
    },
  );
  setUp(() {
    events = [];
    lines = [];
  });
  tearDown(() {
    for (final line in lines) {
      expect(PrivacyLog.redact(line), line);
    }
  });

  testWidgets('normal build is inert and start/stop are idempotent', (
    tester,
  ) async {
    expect(UiFrameDiagnostics.instance.enabled, isFalse);
    final diagnostics = make(enabled: false)..start();
    diagnostics.navigation(0, 1, 0, 100);
    diagnostics.flush();
    diagnostics.stop();
    await tester.pump(const Duration(seconds: 6));
    expect(events, isEmpty);
  });

  testWidgets(
    'real key dispatch is preserved and capture stops automatically',
    (tester) async {
      var delivered = 0;
      final focus = FocusNode();
      await tester.pumpWidget(
        Focus(
          focusNode: focus,
          onKeyEvent: (_, event) {
            delivered++;
            return KeyEventResult.handled;
          },
          child: const SizedBox(),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      final diagnostics = make()
        ..start()
        ..start();
      addTearDown(diagnostics.stop);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      diagnostics.flush();
      final keys =
          events.where((e) => e['event'] == 'keys').single['values'] as List;
      expect(delivered, 5);
      expect(keys.map((e) => e[1]), [0, 1, 2]);
      expect(keys.every((e) => e[2] == 1), isTrue);
      expect(events.where((e) => e['event'] == 'start').length, 1);
      await tester.pump(const Duration(seconds: 6));
      expect(events.last['event'], 'stop');
      final stoppedCount = events.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      diagnostics.flush();
      diagnostics.start();
      await tester.pump(const Duration(seconds: 6));
      expect(events.length, stoppedCount);
      expect(delivered, 7);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    },
  );

  testWidgets(
    'engine callback reports UI and raster separately, then detaches',
    (tester) async {
      final oldCallback = binding.platformDispatcher.onReportTimings;
      final diagnostics = make()..start();
      addTearDown(diagnostics.stop);
      binding.platformDispatcher.onReportTimings!([
        FrameTiming(
          vsyncStart: 0,
          buildStart: 100,
          buildFinish: 20100,
          rasterStart: 20200,
          rasterFinish: 24200,
          rasterFinishWallTime: 24200,
        ),
      ]);
      diagnostics.flush();
      final window = events.last;
      expect(window['frames'], 1);
      expect(window['buildUs'], [20000, 20000, 20000, 1]);
      expect(window['rasterUs'], [4000, 4000, 4000, 0]);
      expect(
        window['cacheLimitBytes'],
        PaintingBinding.instance.imageCache.maximumSizeBytes,
      );
      diagnostics.stop();
      expect(binding.platformDispatcher.onReportTimings, oldCallback);
    },
  );

  testWidgets('overload stays bounded, batches fit logcat, and buffers reset', (
    tester,
  ) async {
    final diagnostics = make()..start();
    addTearDown(diagnostics.stop);
    final timing = FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: 2000,
      rasterStart: 2000,
      rasterFinish: 4000,
      rasterFinishWallTime: 4000,
    );
    diagnostics.recordTimings(List.filled(1000, timing));
    for (var i = 0; i < 1000; i++) {
      diagnostics.navigation(2, i, i.toDouble(), i + 100.0);
    }
    diagnostics.flush();
    final window = events.firstWhere((e) => e['event'] == 'window');
    expect(window['frames'], 1000);
    expect(window['samples'], 512);
    expect(window['droppedEvents'], 744);
    expect(
      events
          .where((e) => e['event'] == 'nav')
          .expand((e) => e['values'] as List)
          .length,
      256,
    );
    expect(lines.every((line) => utf8.encode(line).length <= 512), isTrue);
    diagnostics.flush();
    expect(events.last['frames'], 0);
    expect(events.last['droppedEvents'], 0);
    diagnostics.stop();
  });
}
