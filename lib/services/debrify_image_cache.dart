import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'artwork_cache_budget.dart';
import 'artwork_cache_manager.dart';
import 'browsing_cache_preferences.dart';

/// Shared artwork disk caches; DefaultCacheManager and decoded RAM are separate.
/// Existing manager identities and disk-store keys survive policy changes.
class DebrifyImageCache {
  DebrifyImageCache._();

  static final _budget = ArtworkCacheBudget();
  static final CacheManager manager = ArtworkCacheManager(
    cacheKey: 'debrifyImageCache',
    budget: _budget,
    standardCapacity: 1000,
    initializePolicy: _initialize,
  );
  static final CacheManager iptvLogos = ArtworkCacheManager(
    cacheKey: 'debrifyIptvLogoCache',
    budget: _budget,
    standardCapacity: 2000,
    initializePolicy: _initialize,
  );
  static Future<void>? _initialization;

  static Future<void> _initialize() => _initialization ??= () async {
    // Register both stores before scanning, including logo-only sessions.
    manager;
    iptvLogos;
    await BrowsingCachePreferences.initialize();
    BrowsingCachePreferences.notifier.addListener(_policyChanged);
    final options = BrowsingCachePreferences.current;
    _budget.configure(
      expanded: options.expandedArtwork,
      bytes: options.artworkBudgetBytes,
    );
  }();

  static void _policyChanged() {
    unawaited(
      applyPolicy().catchError((Object _) {
        debugPrint('Artwork cache cleanup failed; a later apply can retry.');
      }),
    );
  }

  static Future<void> _applyCurrent() {
    final options = BrowsingCachePreferences.current;
    return _budget.apply(
      expanded: options.expandedArtwork,
      bytes: options.artworkBudgetBytes,
    );
  }

  /// Bootstrap after the first frame (unawaited with error handling), then await
  /// when changing settings. Installs the preference listener without putting
  /// inventory ahead of runApp or a cached image read.
  static Future<void> applyPolicy() async {
    await _initialize();
    await _applyCurrent();
  }

  /// Actual payload bytes in these two stores, including variants and partials.
  /// Readers may retain bytes after clear/decrease; new writes still account for
  /// every retained byte before admission. After a reduction, retained files can
  /// exceed the new cap up to the previously admitted total (or the existing
  /// standard cache when first enabling). No further bytes are admitted until
  /// there is room. Each new file is at most 32 MiB, with four writes at once;
  /// their partial bytes also count. Metadata/decoded RAM/DefaultCacheManager
  /// are separate. Normal reads release their lease on completion; an unread
  /// abandoned handle falls back to GC. Acquire a fresh lookup for a later read
  /// if the old file has since been evicted. Capacity failures are not cached:
  /// a subsequent lookup retries once readers finish.
  static Future<int> sizeBytes() async {
    await _initialize();
    return _budget.sizeBytes();
  }

  /// Cancel old writes and clear lookups. Files with live consumer leases are
  /// deleted after their first read/release/GC; delayed first reads remain safe.
  static Future<void> clear() async {
    await _initialize();
    await _budget.clear();
  }
}
