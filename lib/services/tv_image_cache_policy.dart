import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'diagnostic_log.dart';

/// Process-wide decoded-image allowance for a confirmed Android TV.
/// The byte limits cover ImageCache's retained entries, not all live textures.
class TvImageCachePolicy with WidgetsBindingObserver {
  TvImageCachePolicy({
    required this.cache,
    Future<Map<String, dynamic>?> Function()? readMemory,
    DateTime Function()? now,
    DiagnosticLog? diagnostics,
  }) : _readMemory = readMemory ?? _readNativeMemory,
       _now = now ?? DateTime.now,
       _diagnostics = diagnostics ?? DiagnosticLog.instance;

  static const baselineBytes = 56 << 20;
  static const expandedBytes = 128 << 20;
  static const maximumBytes = 384 << 20;
  static const _nativeReserveBytes = 128 << 20;
  static const _growthMarginBytes = 64 << 20;
  static const cooldown = Duration(minutes: 5);
  final ImageCache cache;
  final Future<Map<String, dynamic>?> Function() _readMemory;
  final DateTime Function() _now;
  final DiagnosticLog _diagnostics;
  Timer? _timer;
  bool _started = false, _disposed = false, _foreground = true;
  bool _scheduled = false, _refreshing = false, _nativePending = false;
  int _budget = baselineBytes;
  int _generation = 0;
  DateTime? _blockedUntil;

  static Future<Map<String, dynamic>?> _readNativeMemory() =>
      const MethodChannel(
        'com.debrify.app/memory',
      ).invokeMapMethod<String, dynamic>('getMemoryInfo');

  /// Establish the fallback immediately; native work waits until after the
  /// first frame and runs at idle priority, never holding up startup.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _baseline();
    final binding = WidgetsBinding.instance;
    _foreground =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    if (_foreground) _startTimer();
    binding.addPostFrameCallback((_) => _scheduleRefresh());
  }

  void _allowance(int bytes, int entries, String reason, {int? available}) {
    _budget = bytes;
    final changed =
        cache.maximumSizeBytes != bytes || cache.maximumSize != entries;
    cache.maximumSizeBytes = bytes;
    cache.maximumSize = entries;
    if (changed) {
      _diagnostics.recordEvent(
        source: 'image_cache',
        event: 'allowance_changed',
        fields: {
          'budgetBytes': bytes,
          'entries': entries,
          'reason': DiagnosticLabel(reason),
          if (available != null) 'availableMemory': available,
        },
      );
    }
  }

  void _baseline({String reason = 'baseline', int? available}) {
    _allowance(baselineBytes, 256, reason, available: available);
  }

  void _fallback(String reason, {int? available}) {
    _baseline(reason: reason, available: available);
    _blockedUntil = _now().add(cooldown);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _scheduleRefresh(),
    );
  }

  void _scheduleRefresh() {
    if (_disposed || !_foreground || _scheduled) return;
    _scheduled = true;
    final generation = _generation;
    unawaited(
      SchedulerBinding.instance.scheduleTask(() async {
        _scheduled = false;
        if (generation != _generation) {
          _scheduleRefresh(); // A resume needs a new request, never old work.
          return;
        }
        await _refresh();
      }, Priority.idle),
    );
  }

  Future<void> _refresh() async {
    if (!_started ||
        _disposed ||
        !_foreground ||
        _refreshing ||
        _nativePending) {
      return;
    }
    _refreshing = true;
    _nativePending = true;
    final generation = _generation;
    final pending = Future<Map<String, dynamic>?>.sync(_readMemory);
    // A timed-out platform call can still be running. Don't overlap it with a
    // second call; its late result must never restore an expired allowance.
    unawaited(
      pending.then<void>(
        (_) {
          _nativePending = false;
        },
        onError: (Object _, StackTrace __) {
          _nativePending = false;
        },
      ),
    );
    try {
      final memory = await pending.timeout(const Duration(seconds: 1));
      if (_disposed || !_foreground || generation != _generation) return;
      final available = memory?['availableBytes'];
      final total = memory?['totalBytes'];
      final threshold = memory?['thresholdBytes'];
      if (available is! int ||
          total is! int ||
          threshold is! int ||
          available < 0 ||
          total <= 0 ||
          available > total ||
          threshold < 0 ||
          threshold > total ||
          memory?['lowMemory'] != false ||
          memory?['lowRamDevice'] != false ||
          total < (3 << 30)) {
        _fallback(
          'unsafe_or_invalid_memory',
          available:
              available is int &&
                  available >= 0 &&
                  total is int &&
                  available <= total
              ? available
              : null,
        );
        return;
      }
      // Ten percent is a free-memory floor, never an allocation target. Also
      // stay above Android's warning threshold with a separate native reserve.
      final tenth = (total + 9) ~/ 10;
      final nativeFloor = threshold + _nativeReserveBytes;
      final floor = tenth > nativeFloor ? tenth : nativeFloor;
      final used = cache.currentSizeBytes.clamp(0, _budget);
      // Retained bytes are already reflected in available memory. Reserve two
      // bytes per still-unused allowance byte for further decoded CPU pixels
      // and GPU textures. This is a conservative estimate, not a RAM guarantee.
      final retainedHeadroom = floor + 2 * (_budget - used);
      if (available < retainedHeadroom) {
        _fallback('insufficient_headroom', available: available);
        return;
      }
      if (_blockedUntil != null && _now().isBefore(_blockedUntil!)) {
        _baseline(reason: 'cooldown', available: available);
        return;
      }
      // Start with 128 MiB. Further growth needs real retained-cache demand,
      // not merely a large device or pending decodes. One step per fresh read
      // means normal foreground polling can grow at most once per 30 seconds.
      final next = _budget == baselineBytes
          ? expandedBytes
          : _budget < maximumBytes && used * 4 >= _budget * 3
          ? _budget + expandedBytes
          : _budget;
      if (next == _budget) return;
      // Reserve all remaining room in the proposed allowance, including unused
      // room in the old allowance, plus hysteresis above the retention floor.
      if (available < floor + 2 * (next - used) + _growthMarginBytes) return;
      _allowance(next, (next >> 20) * 4, 'headroom', available: available);
    } catch (error) {
      if (!_disposed && _foreground && generation == _generation) {
        _fallback(
          error is TimeoutException ? 'read_timeout' : 'read_unavailable',
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (_disposed) return;
    _generation++;
    _fallback('memory_pressure');
    cache.clear(); // Release retained entries; mounted/live images stay valid.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _generation++;
      _timer?.cancel();
      _baseline(reason: 'background'); // Never retain a verdict across a pause.
    } else {
      _startTimer();
      _scheduleRefresh();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _baseline(reason: 'disposed');
  }

  @visibleForTesting
  Future<void> debugRefresh() => _refresh();
}
