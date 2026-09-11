import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import 'artwork_cache_budget.dart';
import 'artwork_cache_file.dart';
import 'browsing_cache_preferences.dart';
import 'debrify_image_cache.dart';
import 'metadata_preferences_service.dart';
import 'metadata_provider_service.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

typedef _ItemKey = (String, String, String?, String?, String?, String?);
typedef ArtworkPresentationLoader =
    Future<MetadataPresentation> Function(
      StremioMeta item, {
      MetadataPreferences? preferences,
      bool Function()? isRelevant,
    });

/// Warms one disk file at a time from already-discovered collection items.
/// Does not page catalogues, decode images, or own the shared cache manager.
/// Call update with the current snapshot; a profile switch discards that snapshot
/// until its owner supplies items for the new profile.
class CollectionArtworkWarmup with WidgetsBindingObserver {
  CollectionArtworkWarmup({
    required this.scrolling,
    required this.isCurrent,
    this.onProgress,
    @visibleForTesting Future<File> Function(String)? loadFile,
    @visibleForTesting void Function(File)? releaseFile,
    @visibleForTesting Future<int> Function()? cacheBytes,
    @visibleForTesting ArtworkPresentationLoader? present,
    @visibleForTesting Future<ProfilePreferences> Function()? openPreferences,
    @visibleForTesting DateTime Function()? now,
  }) : _loadFile = loadFile ?? DebrifyImageCache.manager.getSingleFile,
       _releaseFile = releaseFile ?? releaseArtworkCacheFile,
       _cacheBytes = cacheBytes ?? DebrifyImageCache.admissionSizeBytes,
       _present = present ?? MetadataProviderService.instance.present,
       _openPreferences = openPreferences ?? ProfilePreferences.instance,
       _now = now ?? DateTime.now {
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    scrolling.addListener(_scrollChanged);
    ProfileRuntime.scope.addListener(_profileChanged);
    MetadataPreferencesService.revision.addListener(_policyChanged);
    BrowsingCachePreferences.notifier.addListener(_optionsChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_timings);
    unawaited(_initialize());
  }

  static const idleDelay = Duration(milliseconds: 250);
  // The cache admits individual files up to 32 MiB. Leave that much room so
  // speculative work stops before it starts cycling through the global LRU.
  static const budgetHeadroomBytes = 32 * 1024 * 1024;
  static const pressureDelay = Duration(seconds: 30);
  static const slowFrameDelay = Duration(seconds: 2);

  final ValueListenable<bool> scrolling;
  final bool Function() isCurrent;

  /// Processed items, including duplicates, absent artwork and exhausted retries;
  /// deliberately carries neither image URLs nor metadata identities.
  final void Function(int completed, int total)? onProgress;
  final Future<File> Function(String) _loadFile;
  final void Function(File) _releaseFile;
  final Future<int> Function() _cacheBytes;
  final ArtworkPresentationLoader _present;
  final Future<ProfilePreferences> Function() _openPreferences;
  final DateTime Function() _now;
  Map<_ItemKey, StremioMeta> _items = {};
  final _priority = <_ItemKey>[];
  // Add-on configuration is immutable. Its digest is shared by every title;
  // hashing it per item would put bulk CPU work back into the row build.
  final _sourceKeys = Expando<String>();
  final _done = <_ItemKey>{};
  final _urls = <String>{};
  final _failures = <_ItemKey, int>{};
  bool _landscape = false, _disposed = false, _busy = false, _ready = false;
  int _generation = 0;
  Timer? _timer;
  DateTime? _resumeAfter;
  AppLifecycleState? _lifecycle;
  (Object?, int, String?)? _policy;
  bool Function()? _policyStillCurrent;

  /// getSingleFile returns a leased handle. No read/decode is needed to warm
  /// disk, so explicitly release even a late result after cancellation.
  static void releaseArtworkCacheFile(File file) {
    if (file is ArtworkCacheFile) file.release();
  }

  Future<void> _initialize() async {
    await BrowsingCachePreferences.initialize();
    if (_disposed) return;
    _ready = true;
    _schedule();
  }

  _ItemKey _key(StremioMeta item) => (
    item.type,
    item.id,
    item.imdbId,
    item.poster,
    item.background,
    item.sourceAddon == null
        ? null
        : (_sourceKeys[item.sourceAddon!] ??=
              item.sourceAddon!.sourceBindingKey),
  );

  void update(Iterable<StremioMeta> items, {required bool landscape}) {
    if (_disposed) return;
    if (_policyStillCurrent?.call() == false) {
      _done.clear();
      _urls.clear();
      _failures.clear();
    }
    final next = {for (final item in items) _key(item): item};
    if (_landscape == landscape && mapEquals(_items, next)) {
      _reportProgress();
      _schedule();
      return;
    }
    _generation++;
    if (_landscape != landscape) {
      _done.clear();
      _urls.clear();
    }
    _landscape = landscape;
    _items = next;
    _priority.removeWhere((key) => !next.containsKey(key));
    _done.removeWhere((key) => !next.containsKey(key));
    _failures.removeWhere((key, _) => !next.containsKey(key));
    _reportProgress();
    _schedule();
  }

  /// Reorder pending work around the viewport without cancelling a download or
  /// forgetting completed files. Unknown items cannot introduce new work.
  void prioritize(Iterable<StremioMeta> items) {
    if (_disposed) return;
    _priority
      ..clear()
      ..addAll(items.map(_key).where(_items.containsKey).toSet());
    _schedule();
  }

  void _reportProgress() {
    if (_disposed) return;
    try {
      onProgress?.call(_done.length, _items.length);
    } catch (_) {
      // Optional observers cannot stop warming or escape onto the UI isolate.
    }
  }

  void _failedItem(_ItemKey key) {
    final attempts = (_failures[key] ?? 0) + 1;
    if (attempts >= 3) {
      _done.add(key);
      _failures.remove(key);
      _reportProgress();
    } else {
      _failures[key] = attempts;
    }
  }

  bool get _allowed =>
      !_disposed &&
      _ready &&
      ProfileRuntime.isInitialized &&
      !ProfileRuntime.isInMaintenance &&
      BrowsingCachePreferences.current.expandedArtwork &&
      !scrolling.value &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed) &&
      isCurrent() &&
      (_resumeAfter == null || !_now().isBefore(_resumeAfter!));

  void _schedule([Duration delay = idleDelay]) {
    if (_disposed ||
        !_ready ||
        _busy ||
        _timer != null ||
        _done.length == _items.length ||
        !BrowsingCachePreferences.current.expandedArtwork ||
        scrolling.value ||
        (_lifecycle != null && _lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    final remaining = _resumeAfter?.difference(_now());
    if (remaining != null && remaining > delay) delay = remaining;
    // A route callback has no notifier; poll gently while covered to resume.
    if (!isCurrent() && delay < const Duration(seconds: 1)) {
      delay = const Duration(seconds: 1);
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_step());
    });
  }

  void _invalidate() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void _scrollChanged() {
    _invalidate();
    _schedule();
  }

  void _profileChanged() {
    _invalidate();
    _items.clear();
    _priority.clear();
    _done.clear();
    _urls.clear();
    _failures.clear();
    _policy = null;
    _policyStillCurrent = null;
  }

  void _policyChanged() {
    _invalidate();
    _done.clear();
    _urls.clear();
    _failures.clear();
    _policy = null;
    _policyStillCurrent = null;
    _schedule();
  }

  void _optionsChanged() {
    _invalidate();
    _schedule();
  }

  void _rest(Duration duration) {
    final until = _now().add(duration);
    if (_resumeAfter == null || until.isAfter(_resumeAfter!)) {
      _resumeAfter = until;
    }
    _invalidate();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _invalidate();
    _schedule();
  }

  @override
  void didHaveMemoryPressure() => _rest(pressureDelay);

  void _timings(List<FrameTiming> timings) {
    if (_disposed ||
        !BrowsingCachePreferences.current.expandedArtwork ||
        _done.length == _items.length) {
      return;
    }
    if (timings.any(
      (frame) =>
          frame.buildDuration > const Duration(milliseconds: 20) ||
          frame.rasterDuration > const Duration(milliseconds: 20) ||
          frame.totalSpan > const Duration(milliseconds: 40),
    )) {
      _rest(slowFrameDelay);
    }
  }

  Future<void> _step() async {
    if (!_allowed) {
      _schedule();
      return;
    }
    _busy = true;
    final generation = _generation;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool relevant() =>
        generation == _generation &&
        _allowed &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    _ItemKey? workingKey;
    try {
      final preferences = await MetadataPreferencesService.loadForBackground(
        isCurrent: relevant,
      );
      if (preferences == null || !relevant()) {
        if (relevant()) _rest(slowFrameDelay);
        return;
      }
      final access = await _openPreferences();
      if (!relevant()) return;
      final raw = access.getString(MetadataPreferencesService.key);
      Object? decoded;
      try {
        decoded = raw == null ? null : jsonDecode(raw);
      } on FormatException {
        // Match the metadata service's malformed/imported value defaults.
      }
      final snapshot = decoded is Map<String, dynamic>
          ? MetadataPreferences.fromJson(decoded)
          : MetadataPreferences();
      // The background load and retained raw facade must describe the same
      // policy. Comparing decoded values also catches an intervening A/B/A read.
      if (jsonEncode(snapshot.toJson()) != jsonEncode(preferences.toJson())) {
        _rest(slowFrameDelay);
        return;
      }
      bool policyCurrent() {
        if (!relevant()) return false;
        try {
          return access.getString(MetadataPreferencesService.key) == raw;
        } catch (_) {
          return false;
        }
      }

      final policy = (scope, revision, raw);
      if (_policy != policy) {
        _policy = policy;
        _done.clear();
        _urls.clear();
        _failures.clear();
      }
      // This long-lived check intentionally excludes the per-request generation
      // and idle state: ordinary scrolling must not discard completed work.
      _policyStillCurrent = () {
        if (scope != ProfileRuntime.scope.value ||
            revision != MetadataPreferencesService.revision.value) {
          return false;
        }
        try {
          return access.getString(MetadataPreferencesService.key) == raw;
        } catch (_) {
          return false;
        }
      };
      final key =
          _priority.where((key) => !_done.contains(key)).firstOrNull ??
          _items.keys.where((key) => !_done.contains(key)).firstOrNull;
      if (key == null) return;
      workingKey = key;
      final bytes = await _cacheBytes();
      if (!policyCurrent()) return;
      if (bytes < 0 ||
          bytes + budgetHeadroomBytes >=
              BrowsingCachePreferences.current.artworkBudgetBytes) {
        _rest(pressureDelay);
        return;
      }
      final result = await _present(
        _items[key]!,
        // Warming disk artwork needs neither titles nor descriptions. Keep
        // both artwork providers for the rail's existing fallback behavior.
        preferences: preferences.copyWith(
          providers: {
            ...preferences.providers,
            MetadataCategory.information: MetadataPreferences.current,
          },
        ),
        isRelevant: policyCurrent,
      );
      if (!policyCurrent()) return;
      final category = _landscape
          ? MetadataCategory.backgrounds
          : MetadataCategory.posters;
      final custom =
          preferences.provider(category) != MetadataPreferences.current;
      // Match the rail's provider policy; a custom backdrop cannot silently
      // fall through to a current-provider poster when fallback is disabled.
      final fallback = !custom || preferences.fallback
          ? result.item.poster
          : null;
      final url =
          custom &&
              !preferences.fallback &&
              result.unavailable.contains(category)
          ? null
          : _landscape
          ? result.item.background ?? fallback
          : result.item.poster;
      if ((url == null || url.trim().isEmpty) && result.retryable) {
        throw StateError('Artwork presentation can retry');
      }
      if (url != null && url.trim().isNotEmpty && !_urls.contains(url)) {
        final file = await _loadFile(url);
        try {
          if (!policyCurrent()) return;
          _urls.add(url);
        } finally {
          _releaseFile(file);
        }
      }
      _done.add(key);
      _failures.remove(key);
      _reportProgress();
    } on ArtworkCacheLimit {
      // The manager uses the same exception for a full global budget and an
      // individual oversized file. Recheck space before deciding to pause:
      // an oversized first URL must not starve every subsequent item forever.
      try {
        final bytes = await _cacheBytes();
        if (!relevant()) return;
        if (bytes < 0 ||
            bytes + budgetHeadroomBytes >=
                BrowsingCachePreferences.current.artworkBudgetBytes) {
          _rest(pressureDelay);
        } else {
          if (workingKey != null) _failedItem(workingKey);
          _rest(slowFrameDelay);
        }
      } catch (_) {
        // Unknown capacity cannot authorize another speculative transfer.
        _rest(pressureDelay);
      }
    } on ArtworkCacheCancelled {
      _rest(slowFrameDelay);
    } catch (_) {
      // Optional work must not produce an unhandled exception or a hot retry.
      // Nor may one broken URL starve every remaining discovered image.
      if (workingKey != null && relevant()) {
        _failedItem(workingKey);
      }
      _rest(slowFrameDelay);
    } finally {
      _busy = false;
      _schedule();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _invalidate();
    scrolling.removeListener(_scrollChanged);
    ProfileRuntime.scope.removeListener(_profileChanged);
    MetadataPreferencesService.revision.removeListener(_policyChanged);
    BrowsingCachePreferences.notifier.removeListener(_optionsChanged);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    _items.clear();
    _priority.clear();
    _done.clear();
    _urls.clear();
    _failures.clear();
    _policyStillCurrent = null;
  }
}
