import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'profiles/profile_preferences.dart';

/// Resource policy belongs to this installation, never a synced profile.
@immutable
class BrowsingCacheOptions {
  static const titleSizesMb = [10, 25, 50, 100];
  static const artworkSizesMb = [128, 256, 512, 1024, 2048];

  const BrowsingCacheOptions({
    this.rememberTitles = false,
    this.titleSizeMb = 25,
    this.expandedArtwork = false,
    this.artworkSizeMb = 512,
    this.prefetchMovieStreams = true,
  });

  final bool rememberTitles;
  final int titleSizeMb;
  final bool expandedArtwork;
  final int artworkSizeMb;
  final bool prefetchMovieStreams;

  int get titleBudgetBytes => titleSizeMb * 1024 * 1024;
  int get artworkBudgetBytes => artworkSizeMb * 1024 * 1024;

  BrowsingCacheOptions copyWith({
    bool? rememberTitles,
    int? titleSizeMb,
    bool? expandedArtwork,
    int? artworkSizeMb,
    bool? prefetchMovieStreams,
  }) => BrowsingCacheOptions(
    rememberTitles: rememberTitles ?? this.rememberTitles,
    titleSizeMb: titleSizeMb ?? this.titleSizeMb,
    expandedArtwork: expandedArtwork ?? this.expandedArtwork,
    artworkSizeMb: artworkSizeMb ?? this.artworkSizeMb,
    prefetchMovieStreams: prefetchMovieStreams ?? this.prefetchMovieStreams,
  );

  factory BrowsingCacheOptions.fromJson(Map<String, dynamic> json) =>
      BrowsingCacheOptions(
        rememberTitles: json['rememberTitles'] == true,
        titleSizeMb:
            json['titleSizeMb'] is int &&
                titleSizesMb.contains(json['titleSizeMb'])
            ? json['titleSizeMb'] as int
            : 25,
        expandedArtwork: json['expandedArtwork'] == true,
        artworkSizeMb:
            json['artworkSizeMb'] is int &&
                artworkSizesMb.contains(json['artworkSizeMb'])
            ? json['artworkSizeMb'] as int
            : 512,
        prefetchMovieStreams: json['prefetchMovieStreams'] != false,
      );

  Map<String, dynamic> toJson() => {
    'rememberTitles': rememberTitles,
    'titleSizeMb': titleSizeMb,
    'expandedArtwork': expandedArtwork,
    'artworkSizeMb': artworkSizeMb,
    'prefetchMovieStreams': prefetchMovieStreams,
  };
}

abstract final class BrowsingCachePreferences {
  static const key = 'browsing_cache_options_v1';
  static final notifier = ValueNotifier(const BrowsingCacheOptions());
  static BrowsingCacheOptions get current => notifier.value;
  static final _lock = Lock();
  static Future<void>? _initialization;

  static Future<void> initialize() =>
      _initialization ??= _lock.synchronized(() async {
        try {
          final prefs = await DevicePreferences.instance();
          final raw = prefs.getString(key);
          notifier.value = raw == null
              ? const BrowsingCacheOptions()
              : BrowsingCacheOptions.fromJson(
                  jsonDecode(raw) as Map<String, dynamic>,
                );
        } catch (_) {
          notifier.value = const BrowsingCacheOptions();
        }
      });

  static Future<void> update(BrowsingCacheOptions value) async {
    await initialize();
    await _lock.synchronized(() async {
      final normalized = BrowsingCacheOptions.fromJson(value.toJson());
      final prefs = await DevicePreferences.instance();
      if (!await prefs.setString(key, jsonEncode(normalized.toJson()))) {
        throw StateError('Could not save browsing preferences');
      }
      notifier.value = normalized;
    });
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialization = null;
    notifier.value = const BrowsingCacheOptions();
  }
}
