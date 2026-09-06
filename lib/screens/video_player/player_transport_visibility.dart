import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/platform_util.dart';
import 'constants/timing_constants.dart';

/// Coordinates visibility and menu focus using borrowed host UI resources.
class PlayerTransportVisibility {
  PlayerTransportVisibility({
    required this.visible,
    required this.barScope,
    required this.playPauseFocus,
    required this.rootFocus,
    required bool Function() isMounted,
    required bool Function() anyOverlayOpen,
    required bool Function() readAutoHideBlocker,
    required void Function(VoidCallback) commit,
  }) : _isMounted = isMounted,
       _anyOverlayOpen = anyOverlayOpen,
       _readAutoHideBlocker = readAutoHideBlocker,
       _commit = commit;

  final ValueNotifier<bool> visible;
  final FocusScopeNode barScope;
  final FocusNode playPauseFocus;
  final FocusNode rootFocus;
  final bool Function() _isMounted;
  final bool Function() _anyOverlayOpen;
  final bool Function() _readAutoHideBlocker;
  final void Function(VoidCallback) _commit;
  Timer? _hideTimer;
  bool _autoHideBlocked = false;
  bool menuVisible = false;

  void cancelAutoHide() => _hideTimer?.cancel();

  void scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(VideoPlayerTimingConstants.controlsAutoHideDuration, () {
      if (!_isMounted()) return;
      // Televisions dismiss the dock on INACTIVITY, the way an OTT transport
      // bar does, and only while something is actually playing. A paused TV
      // bar staying up is correct — BACK is how you dismiss that one.
      if (PlatformUtil.isTelevision) {
        // Nothing on screen to dismiss — let the timer lapse rather than
        // re-arming one that would poll forever behind a hidden bar.
        if (!visible.value) return;
        // BLOCKED, not finished. A tracks/episodes sheet is a ROUTE: it takes
        // focus, and the bar would be excluded underneath it, leaving nothing
        // sane to focus when the sheet closes. A scrub owns the bar outright,
        // and a paused player is meant to keep it.
        //
        // Re-arm instead of returning: this is a one-shot Timer, so a bare
        // return SPENT it — a scrub or a sheet lasting longer than the
        // interval meant the dock never auto-hid again for the rest of the
        // session. Re-arming makes the block a pause, not a cancellation.
        if (_readAutoHideBlocker()) {
          _autoHideBlocked = true;
          scheduleAutoHide();
          return;
        }
        if (_autoHideBlocked) {
          // The blocker cleared somewhere inside the last poll. Start the
          // interval again from NOW: closing a sheet must not be met by a
          // countdown that already ran out behind it.
          _autoHideBlocked = false;
          scheduleAutoHide();
          return;
        }
        // Deliberately NOT gated on "focus is inside the bar". Raising the bar
        // always focuses Play/Pause, so that test is true for the entire life
        // of the bar and the timer could never fire — the dock sat over
        // playing video until the user pressed BACK. Every key that reaches
        // the player and every bar action reschedules this timer, so what
        // actually elapses here is INACTIVITY, which is what an OTT dock
        // dismisses on. Route through hideBar so focus leaves the bar
        // before it is excluded; setting the flag alone would strand the
        // remote on a node that no longer exists.
        hideBar();
        return;
      }
      visible.value = false;
    });
  }

  void showBar() {
    visible.value = true;
    // A fresh raise starts from a clean slate: a stale "was blocked" left over
    // from the previous time the bar was up would silently buy this one an
    // extra interval before it could hide.
    _autoHideBlocked = false;
    scheduleAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted() || !visible.value) return;
      // An open overlay owns the remote — the bar must not pull focus out
      // from under it.
      if (_anyOverlayOpen()) return;
      if (!barScope.hasFocus) playPauseFocus.requestFocus();
    });
  }

  void hideBar() {
    visible.value = false;
    // With an overlay up, focus belongs to the overlay (its claim may still
    // be a frame away) — grabbing the root here would strand its DPAD.
    if (!_anyOverlayOpen()) rootFocus.requestFocus();
  }

  void toggleControls() {
    visible.value = !visible.value;
    if (visible.value) {
      scheduleAutoHide();
      // Identity rides IN the bar (IPTV zap panel / Debrify TV banner both
      // embed as the dock's info panel), so nothing floats when it rises.
    }
  }

  void wakeOnPointer() {
    // Don't disturb the base controls while an overlay owns the screen; the
    // cursor is already kept visible by _anyOverlayOpen() in the builder.
    if (_anyOverlayOpen()) return;
    if (!visible.value) {
      visible.value = true;
    }
    scheduleAutoHide();
  }

  void hideMenu() {
    if (!menuVisible) return;
    _commit(() => menuVisible = false);
    if (PlatformUtil.isTelevision) rootFocus.requestFocus();
  }

}
