import 'dart:async';
import 'dart:ui' as ui;

import 'package:debrify/services/tv_image_cache_policy.dart';
import 'package:debrify/services/diagnostic_log.dart' as diagnostics;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> memory({
  int available = 2 << 30,
  int total = 4 << 30,
  int threshold = 256 << 20,
  bool lowMemory = false,
  bool lowRam = false,
}) => {
  'availableBytes': available,
  'totalBytes': total,
  'thresholdBytes': threshold,
  'lowMemory': lowMemory,
  'lowRamDevice': lowRam,
};

class _Diagnostics extends diagnostics.DiagnosticLog {
  final events = <Map<String, Object?>>[];
  @override
  void recordEvent({
    required String source,
    required String event,
    diagnostics.DiagnosticLevel level = diagnostics.DiagnosticLevel.info,
    Map<String, Object?> fields = const {},
    bool flushImmediately = false,
    bool durable = false,
  }) {
    expect(source, 'image_cache');
    expect(event, 'allowance_changed');
    events.add(fields);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageCache cache;
  late TvImageCachePolicy policy;
  late DateTime now;
  setUp(() {
    cache = ImageCache();
    now = DateTime.utc(2026);
  });
  tearDown(() {
    policy.dispose();
    cache.clear();
    cache.clearLiveImages();
  });
  void create(Future<Map<String, dynamic>?> Function() read) {
    policy = TvImageCachePolicy(cache: cache, readMemory: read, now: () => now)
      ..start();
  }

  Future<void> drainIdle(WidgetTester tester) async {
    // Widget pumps don't service SchedulerBinding's idle task queue. Exercise
    // its public test driver, then drain the event-loop callback it requested.
    for (var i = 0; i < 8; i++) {
      if (!tester.binding.handleEventLoopCallback()) break;
    }
    await tester.pump(Duration.zero);
  }

  void policyTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        policy.dispose();
        await drainIdle(tester);
      }
    });
  }

  void baseline() {
    expect(cache.maximumSize, 256);
    expect(cache.maximumSizeBytes, 56 << 20);
  }

  void expanded() {
    expect(cache.maximumSize, 512);
    expect(cache.maximumSizeBytes, 128 << 20);
  }

  policyTest(
    'diagnostics record changed allowances only, with structural fields',
    (tester) async {
      final log = _Diagnostics();
      policy = TvImageCachePolicy(
        cache: cache,
        readMemory: () async => memory(),
        now: () => now,
        diagnostics: log,
      )..start();
      expect(log.events.length, 1);
      await policy.debugRefresh();
      expect(log.events.length, 2);
      await policy.debugRefresh();
      expect(log.events.length, 2);
      expect(log.events.last['budgetBytes'], 128 << 20);
      expect(log.events.last['entries'], 512);
      expect(log.events.last['availableMemory'], 2 << 30);
      expect(
        (log.events.last['reason'] as diagnostics.DiagnosticLabel).value,
        'headroom',
      );
      policy.didHaveMemoryPressure();
      expect(log.events.length, 3);
      expect(
        (log.events.last['reason'] as diagnostics.DiagnosticLabel).value,
        'memory_pressure',
      );
      policy.didHaveMemoryPressure();
      await policy.debugRefresh();
      expect(log.events.length, 3);
    },
  );

  policyTest('resume before old read completes cannot expand from that read', (
    tester,
  ) async {
    var calls = 0;
    var native = Completer<Map<String, dynamic>?>();
    create(() {
      calls++;
      return native.future;
    });
    final oldRead = policy.debugRefresh();
    await tester.pump(
      Duration.zero,
    ); // Queue initial idle work, then invalidate it.
    policy.didChangeAppLifecycleState(AppLifecycleState.paused);
    policy.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    await policy.debugRefresh();
    expect(calls, 1);
    native.complete(memory());
    await oldRead;
    baseline();
    native = Completer<Map<String, dynamic>?>();
    final newRead = policy.debugRefresh();
    expect(calls, 2);
    native.complete(memory());
    await newRead;
    expanded();
  });

  policyTest(
    'foreground timer polls every 30 seconds and stops in background',
    (tester) async {
      var calls = 0;
      create(() async {
        calls++;
        return memory();
      });
      await tester.pumpWidget(const SizedBox()); // Supply the first app frame.
      await drainIdle(tester);
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 29));
      await drainIdle(tester);
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      await drainIdle(tester);
      expect(calls, 2);
      policy.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 90));
      expect(calls, 2);
      policy.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await drainIdle(tester);
      expect(calls, 3);
    },
  );

  policyTest('starts synchronously bounded; valid fresh native map expands', (
    tester,
  ) async {
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.debrify.app/memory'),
      (call) async {
        expect(call.method, 'getMemoryInfo');
        calls++;
        return memory();
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.debrify.app/memory'),
        null,
      ),
    );
    policy = TvImageCachePolicy(cache: cache, now: () => now)..start();
    baseline();
    expect(calls, 0);
    await policy.debugRefresh();
    expect(calls, 1);
    expanded();
  });

  policyTest('eligibility, reserve and hysteresis boundaries', (tester) async {
    var sample = memory(
      available: 1 << 30,
      total: 3 << 30,
      threshold: 768 << 20,
    );
    create(() async => sample);
    await policy.debugRefresh();
    expanded();
    sample = memory(available: 768 << 20, threshold: 640 << 20);
    await policy.debugRefresh();
    expanded();
    sample = memory(available: (768 << 20) - 1);
    await policy.debugRefresh();
    baseline();
    sample = memory();
    now = now.add(const Duration(minutes: 4, seconds: 59));
    await policy.debugRefresh();
    baseline();
    now = now.add(const Duration(seconds: 1));
    await policy.debugRefresh();
    expanded();
    sample = memory(available: 1 << 30, threshold: (896 << 20) + 1);
    await policy.debugRefresh();
    baseline(); // Above 768 MiB, but below the retained threshold reserve.
  });

  policyTest(
    'invalid or unsafe readings fail closed, including after expansion',
    (tester) async {
      Map<String, dynamic>? sample = memory();
      create(() async => sample);
      final unsafe = <Map<String, dynamic>?>[
        null,
        {},
        memory(lowMemory: true),
        memory(lowRam: true),
        memory(total: (3 << 30) - 1),
        memory(available: (1 << 30) - 1),
        memory(available: 1 << 30, threshold: (768 << 20) + 1),
        memory(available: -1),
        memory(available: 5 << 30),
        memory(threshold: -1),
        memory(threshold: 5 << 30),
        {...memory(), 'lowMemory': null},
        {...memory(), 'lowRamDevice': 'false'},
        {...memory(), 'availableBytes': 2147483648.0},
      ];
      for (final invalid in unsafe) {
        policy.didHaveMemoryPressure();
        now = now.add(const Duration(minutes: 5));
        sample = invalid;
        await policy.debugRefresh();
        baseline();
      }
      now = now.add(const Duration(minutes: 5));
      sample = memory();
      await policy.debugRefresh();
      expanded();
      sample = null;
      await policy.debugRefresh();
      baseline();
    },
  );

  policyTest(
    'read errors and timeout fall back; timed-out native call never overlaps',
    (tester) async {
      var calls = 0;
      var fail = false;
      final native = Completer<Map<String, dynamic>?>();
      create(() {
        calls++;
        if (fail) throw PlatformException(code: 'unavailable');
        return native.future;
      });
      final first = policy.debugRefresh();
      await policy.debugRefresh();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      await first;
      baseline();
      now = now.add(const Duration(minutes: 6));
      await policy.debugRefresh();
      expect(calls, 1);
      native.complete(memory());
      await tester.pump(Duration.zero);
      baseline(); // Late success from the timed-out call cannot expand.
      fail = true;
      await policy.debugRefresh();
      expect(calls, 2);
      baseline();
    },
  );

  policyTest(
    'pressure and disposal invalidate an in-flight successful reading',
    (tester) async {
      var native = Completer<Map<String, dynamic>?>();
      create(() => native.future);
      final first = policy.debugRefresh();
      policy.didHaveMemoryPressure();
      native.complete(memory());
      await first;
      baseline();
      now = now.add(const Duration(minutes: 5));
      native = Completer<Map<String, dynamic>?>();
      final second = policy.debugRefresh();
      policy.dispose();
      native.complete(memory());
      await second;
      baseline();
    },
  );

  policyTest(
    'background suspends reads and invalidates old data; resume needs fresh data',
    (tester) async {
      var calls = 0;
      var native = Completer<Map<String, dynamic>?>();
      create(() {
        calls++;
        return native.future;
      });
      final first = policy.debugRefresh();
      policy.didChangeAppLifecycleState(AppLifecycleState.paused);
      native.complete(memory());
      await first;
      baseline();
      await tester.pump(const Duration(seconds: 90));
      await policy.debugRefresh();
      expect(calls, 1);
      policy.didChangeAppLifecycleState(AppLifecycleState.resumed);
      native = Completer<Map<String, dynamic>?>();
      final second = policy.debugRefresh();
      expect(calls, 2);
      native.complete(memory());
      await second;
      expanded();
    },
  );

  policyTest(
    'expanded cache is byte bounded; pressure releases retained but preserves visible image',
    (tester) async {
      create(() async => memory());
      await policy.debugRefresh();
      final picture = ui.PictureRecorder();
      Canvas(picture).drawColor(Colors.green, BlendMode.src);
      final recorded = picture.endRecording();
      final source = (await tester.runAsync(
        () => recorded.toImage(1024, 1024),
      ))!;
      recorded.dispose();
      addTearDown(source.dispose);
      ImageInfo? visible;
      final listener = ImageStreamListener((info, _) => visible = info);
      ImageStreamCompleter? active;
      for (var i = 0; i < 40; i++) {
        final stream = cache.putIfAbsent(
          i,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: source.clone())),
          ),
        )!;
        if (i == 39) {
          active = stream;
          active.addListener(listener);
        }
        await tester.pump(Duration.zero);
      }
      expect(cache.currentSize, 32);
      expect(cache.currentSizeBytes, 128 << 20);
      expect(visible!.image.width, 1024);
      policy.didHaveMemoryPressure();
      baseline();
      expect(cache.currentSize, 0);
      expect(cache.liveImageCount, 1);
      expect(visible!.image.width, 1024);
      active!.removeListener(listener);
      visible!.dispose();
    },
  );
}
