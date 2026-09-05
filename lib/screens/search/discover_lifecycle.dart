import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/discover_prefs.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/youtube_service.dart';

/// Discover's focus, trailer signals, settings bridges and timer lifetime.
/// Only layout/card preference changes notify the containing screen.
class DiscoverLifecycle extends ChangeNotifier {
  final FocusNode sourceNode = FocusNode(debugLabel: 'disc_source');
  final ValueNotifier<StremioMeta?> focused = ValueNotifier(null);
  final ValueNotifier<YoutubeResolvedStreams?> trailerStreams = ValueNotifier(null);
  final ValueNotifier<bool> trailerLoading = ValueNotifier(false);
  final ValueNotifier<double> trailerVolume = ValueNotifier(0);
  final ValueNotifier<double> takeover = ValueNotifier(0);
  final ValueNotifier<StremioMeta?> trailerMeta = ValueNotifier(null);
  final ValueNotifier<StremioMeta?> shown = ValueNotifier(null);
  final ValueNotifier<bool> trailerShowing = ValueNotifier(false);
  final ValueNotifier<bool> theater = ValueNotifier(false);
  Timer? _theaterTimer;
  static const Duration _theaterDelay = Duration(seconds: 5);
  static String _layoutCached = 'stage';
  String layout = _layoutCached;
  bool showTypeTags = DiscoverPrefs.showTypeTags;
  bool showRatings = DiscoverPrefs.showRatings;
  bool showTitles = DiscoverPrefs.showTitles;
  bool _disposed = false;
  bool _television = false;

  // Construction stays eager for every host variant. Registration happens
  // only at the existing Discover init point, after pending handoff handling.
  void start({required bool isTelevision}) {
    _television = isTelevision;
    MainPageBridge.discoverCardSettingsChanged = _onCardSettingsChanged;
    if (isTelevision) {
      takeover.addListener(_relayChromeDim);
      trailerShowing.addListener(_onShowingChanged);
      unawaited(_loadLayout());
      MainPageBridge.discoverLayoutChanged = _onLayoutChanged;
    }
  }

  void onFocused(StremioMeta item) => focused.value = item;

  void _onShowingChanged() {
    _theaterTimer?.cancel();
    if (trailerShowing.value) {
      _theaterTimer = Timer(_theaterDelay, () {
        if (!_disposed && trailerShowing.value) theater.value = true;
      });
    } else {
      theater.value = false;
    }
  }

  void _relayChromeDim() => MainPageBridge.tvChromeDim.value = takeover.value;

  Future<void> _loadLayout() async {
    final nextLayout = await StorageService.getDiscoverLayout();
    // Origin updates the process cache even if this owner was disposed while
    // reading. Preserve that before checking whether a UI commit is allowed.
    _layoutCached = nextLayout;
    if (_disposed || nextLayout == layout) return;
    layout = nextLayout;
    notifyListeners();
  }

  void _onLayoutChanged() {
    if (_disposed) return;
    trailerStreams.value = null;
    trailerMeta.value = null;
    trailerLoading.value = false;
    trailerShowing.value = false;
    theater.value = false;
    _theaterTimer?.cancel();
    takeover.value = 0;
    unawaited(_loadLayout());
  }

  void _onCardSettingsChanged() {
    if (_disposed) return;
    final nextShowTypeTags = DiscoverPrefs.showTypeTags;
    final nextShowRatings = DiscoverPrefs.showRatings;
    final nextShowTitles = DiscoverPrefs.showTitles;
    if (nextShowTypeTags == showTypeTags &&
        nextShowRatings == showRatings &&
        nextShowTitles == showTitles) {
      return;
    }
    showTypeTags = nextShowTypeTags;
    showRatings = nextShowRatings;
    showTitles = nextShowTitles;
    notifyListeners();
  }

  void resetForNarrowCanvas() {
    if (takeover.value != 0 || trailerShowing.value || theater.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        takeover.value = 0;
        trailerShowing.value = false;
        theater.value = false;
      });
    }
  }

  @override
  void dispose({bool? isTelevision}) {
    _disposed = true;
    sourceNode.dispose();
    focused.dispose();
    if (MainPageBridge.discoverCardSettingsChanged == _onCardSettingsChanged) {
      MainPageBridge.discoverCardSettingsChanged = null;
    }
    // The compatibility host reads its current flags at disposal, not only
    // its startup flags. Standalone owners can use the recorded start mode.
    if (isTelevision ?? _television) {
      takeover.removeListener(_relayChromeDim);
      trailerShowing.removeListener(_onShowingChanged);
      _theaterTimer?.cancel();
      if (MainPageBridge.discoverLayoutChanged == _onLayoutChanged) {
        MainPageBridge.discoverLayoutChanged = null;
      }
      if (MainPageBridge.tvChromeDim.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvChromeDim.value = 0;
        });
      }
    }
    trailerStreams.dispose();
    trailerLoading.dispose();
    trailerVolume.dispose();
    takeover.dispose();
    trailerMeta.dispose();
    shown.dispose();
    trailerShowing.dispose();
    theater.dispose();
    super.dispose();
  }
}
