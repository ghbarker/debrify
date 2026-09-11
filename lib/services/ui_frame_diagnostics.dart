import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Temporary, opt-in release measurements. Never captures content or consumes
/// input. Normal builds install no listeners. Each launch records at most five
/// minutes, with bounded two-second numeric batches rather than per-frame I/O.
class UiFrameDiagnostics {
  UiFrameDiagnostics({
    required this.enabled,
    void Function(String)? emit,
    this.captureDuration = const Duration(minutes: 5),
  }) : emit = emit ?? ((line) => debugPrint(line));

  static final instance = UiFrameDiagnostics(
    enabled: const bool.fromEnvironment('DEBRIFY_FRAME_TIMINGS'),
  );
  final bool enabled;
  final void Function(String) emit;
  final Duration captureDuration;
  static const _sampleLimit = 512;
  static const _eventLimit = 256;
  final _clock = Stopwatch();
  final _build = <int>[];
  final _raster = <int>[];
  final _span = <int>[];
  final _keys = <List<int>>[];
  final _navigation = <List<num>>[];
  Timer? _reportTimer, _stopTimer;
  bool _started = false, _active = false;
  int _frames = 0, _droppedEvents = 0, _windowStart = 0;

  void start() {
    if (!enabled || _started) return;
    _started = _active = true;
    _clock.start();
    WidgetsBinding.instance.addTimingsCallback(recordTimings);
    HardwareKeyboard.instance.addHandler(_onKey);
    _write({'event': 'start', 'limitMs': captureDuration.inMilliseconds});
    _reportTimer = Timer.periodic(const Duration(seconds: 2), (_) => flush());
    _stopTimer = Timer(captureDuration, stop);
  }

  // Zero means initial down, one repeat, two release. Direction is -1 or +1.
  // Event timestamps and receipt timestamps expose delayed input delivery;
  // they use different clock origins and must be compared as intervals.
  bool _onKey(KeyEvent event) {
    if (!_active ||
        (event.logicalKey != LogicalKeyboardKey.arrowUp &&
            event.logicalKey != LogicalKeyboardKey.arrowDown)) {
      return false;
    }
    if (_keys.length < _eventLimit) {
      _keys.add([
        _clock.elapsedMilliseconds,
        event is KeyRepeatEvent ? 1 : (event is KeyUpEvent ? 2 : 0),
        event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1,
        event.timeStamp.inMicroseconds,
      ]);
    } else {
      _droppedEvents++;
    }
    return false;
  }

  /// Numeric collection probes: 0 target, 1 focus request, 2 offset, 3 focus
  /// committed, 4 body built (row: 0 loading, 1 error, 2 all, 3 tabs, 4 rails,
  /// 5 mobile gallery). Body builds do not imply a route remains foreground.
  /// Row indices and pixel offsets only; never title IDs, labels or URLs.
  void navigation(int stage, int row, double offset, double target) {
    if (!_active) return;
    if (_navigation.length < _eventLimit) {
      _navigation.add([
        _clock.elapsedMilliseconds,
        stage,
        row,
        offset.round(),
        target.round(),
      ]);
    } else {
      _droppedEvents++;
    }
  }

  @visibleForTesting
  void recordTimings(List<FrameTiming> timings) {
    if (!_active) return;
    for (final timing in timings) {
      _frames++;
      if (_build.length >= _sampleLimit) continue;
      _build.add(timing.buildDuration.inMicroseconds);
      _raster.add(timing.rasterDuration.inMicroseconds);
      _span.add(timing.totalSpan.inMicroseconds);
    }
  }

  List<int> _stats(List<int> values) {
    if (values.isEmpty) return [0, 0, 0, 0];
    values.sort();
    return [
      (values.fold<int>(0, (a, b) => a + b) / values.length).round(),
      values[((values.length - 1) * .9).ceil()],
      values.last,
      values.where((v) => v > 16683).length,
    ];
  }

  @visibleForTesting
  void flush() {
    if (!_active) return;
    final cache = PaintingBinding.instance.imageCache;
    final now = _clock.elapsedMilliseconds;
    _write({
      'event': 'window', 'startMs': _windowStart, 'endMs': now,
      'frames': _frames, 'samples': _build.length,
      // Each duration tuple: mean, p90, maximum microseconds, >16.683ms count.
      'buildUs': _stats(_build), 'rasterUs': _stats(_raster),
      'spanUs': _stats(_span),
      'cacheBytes': cache.currentSizeBytes, 'cacheCount': cache.currentSize,
      'cacheLimitBytes': cache.maximumSizeBytes,
      'cacheLimitCount': cache.maximumSize,
      'liveImages': cache.liveImageCount,
      'pendingImages': cache.pendingImageCount,
      'droppedEvents': _droppedEvents,
    });
    // Small numeric chunks also fit the app's 512-character privacy log cap.
    for (final entry in {'keys': _keys, 'nav': _navigation}.entries) {
      for (var start = 0; start < entry.value.length; start += 6) {
        _write({
          'event': entry.key,
          'startMs': _windowStart,
          'endMs': now,
          'values': entry.value.sublist(
            start,
            (start + 6).clamp(0, entry.value.length),
          ),
        });
      }
    }
    _windowStart = now;
    _frames = _droppedEvents = 0;
    _build.clear();
    _raster.clear();
    _span.clear();
    _keys.clear();
    _navigation.clear();
  }

  void _write(Map<String, Object> fields) {
    try {
      // PrivacyLog deliberately redacts arbitrary JSON objects. This fixed,
      // content-free schema uses tab-separated scalar/array fields instead,
      // through the existing privacy sink rather than bypassing that filter.
      emit(
        'DEBRIFY_PERF ${fields.entries.map((e) => '${e.key}=${jsonEncode(e.value)}').join('\t')}',
      );
    } catch (_) {
      // A failed diagnostic sink cannot affect navigation.
    }
  }

  void stop() {
    if (!_active) return;
    flush();
    _active = false;
    _reportTimer?.cancel();
    _stopTimer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(recordTimings);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _clock.stop();
    _write({'event': 'stop', 'elapsedMs': _clock.elapsedMilliseconds});
  }
}
