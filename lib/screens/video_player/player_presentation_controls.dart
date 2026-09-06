import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'models/gesture_state.dart';
import 'models/hud_state.dart';
import 'utils/aspect_mode_utils.dart';

/// Shared speed/aspect state used by the actual host UI and resume adapter.
/// Gesture admission, menu layout and native player lifetime remain in the host.
class PlayerPresentationControls {
  final ValueNotifier<AspectRatioHudState?> aspectRatioHud =
      ValueNotifier<AspectRatioHudState?>(null);
  AspectMode aspectMode = AspectMode.contain;
  double playbackSpeed = 1.0;
  double? speedBeforeHold;
  final ValueNotifier<bool> speedHoldHud = ValueNotifier<bool>(false);

  late mk.Player Function() _readPlayer;
  late void Function(VoidCallback) _commit;
  late Future<void> Function() _saveResume;
  late VoidCallback _autoHide;
  late bool Function() _isMounted;

  // Binding stores lazy operations; it does not read the player or resume owner.
  void bind({
    required mk.Player Function() readPlayer,
    required void Function(VoidCallback) commit,
    required Future<void> Function() saveResume,
    required VoidCallback autoHide,
    required bool Function() isMounted,
  }) {
    _readPlayer = readPlayer;
    _commit = commit;
    _saveResume = saveResume;
    _autoHide = autoHide;
    _isMounted = isMounted;
  }

  Future<void> applyAspectVideoZoom() async {
    final platform = _readPlayer().platform;
    if (platform is! mk.NativePlayer) return;
    final scale = AspectModeUtils.getScaleForMode(aspectMode);
    final zoom = math.log(scale) / math.ln2;
    try {
      await platform.setProperty('video-zoom', zoom.toStringAsFixed(6));
    } catch (e) {
      debugPrint('VideoPlayer: aspect zoom apply failed: $e');
    }
  }

  void cycleAspectMode() {
    AspectMode newMode;
    String modeName;
    IconData modeIcon;

    switch (aspectMode) {
      case AspectMode.contain:
        newMode = AspectMode.cover;
        modeName = 'Cover';
        modeIcon = Icons.crop_free_rounded;
        break;
      case AspectMode.cover:
        newMode = AspectMode.fitWidth;
        modeName = 'Fit Width';
        modeIcon = Icons.fit_screen_rounded;
        break;
      case AspectMode.fitWidth:
        newMode = AspectMode.fitHeight;
        modeName = 'Fit Height';
        modeIcon = Icons.fit_screen_rounded;
        break;
      case AspectMode.fitHeight:
        newMode = AspectMode.aspect16_9;
        modeName = '16:9';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect16_9:
        newMode = AspectMode.aspect4_3;
        modeName = '4:3';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect4_3:
        newMode = AspectMode.aspect21_9;
        modeName = '21:9';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect21_9:
        newMode = AspectMode.aspect1_1;
        modeName = '1:1';
        modeIcon = Icons.crop_square_rounded;
        break;
      case AspectMode.aspect1_1:
        newMode = AspectMode.aspect3_2;
        modeName = '3:2';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect3_2:
        newMode = AspectMode.aspect5_4;
        modeName = '5:4';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect5_4:
        newMode = AspectMode.cinemaZoom;
        modeName = 'Cinema Zoom';
        modeIcon = Icons.zoom_in_map_rounded;
        break;
      case AspectMode.cinemaZoom:
        newMode = AspectMode.contain;
        modeName = 'Contain';
        modeIcon = Icons.crop_free_rounded;
        break;
    }

    _commit(() {
      aspectMode = newMode;
    });
    unawaited(applyAspectVideoZoom());

    // Show elegant HUD feedback
    aspectRatioHud.value = AspectRatioHudState(
      aspectRatio: modeName,
      icon: modeIcon,
    );

    // Auto-hide the HUD after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_isMounted()) {
        aspectRatioHud.value = null;
      }
    });

    _autoHide();
    _saveResume();
  }

  void changeSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final idx = speeds.indexOf(playbackSpeed);
    final next = speeds[(idx + 1) % speeds.length];
    _readPlayer().setRate(next);
    _commit(() => playbackSpeed = next);
    _autoHide();
    _saveResume();
  }

  void setPlaybackSpeed(double v) {
    _readPlayer().setRate(v);
    _commit(() => playbackSpeed = v);
    _saveResume();
  }

  void setAspectModeDirect(AspectMode m) {
    if (m == aspectMode) return;
    _commit(() => aspectMode = m);
    unawaited(applyAspectVideoZoom());
    _saveResume();
  }

  void endHold(LongPressEndDetails details) {
    final prior = speedBeforeHold;
    if (prior == null) return;
    speedBeforeHold = null;
    if (!_isMounted()) return;
    _readPlayer().setRate(prior);
    _commit(() => playbackSpeed = prior);
    speedHoldHud.value = false;
  }

  void beginHold() {
    speedBeforeHold = playbackSpeed;
    _readPlayer().setRate(2.0);
    _commit(() => playbackSpeed = 2.0);
    speedHoldHud.value = true;
  }

  // Preserve the host's existing asymmetric notifier cleanup.
  void disposeSpeedHoldHud() => speedHoldHud.dispose();
}
