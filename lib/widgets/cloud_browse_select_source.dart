import 'package:flutter/material.dart';

import '../screens/alldebrid/alldebrid_files_screen.dart';
import '../screens/pikpak/pikpak_files_screen.dart';
import '../screens/premiumize/premiumize_files_screen.dart';
import '../services/series_source_service.dart';

/// Bind-source cloud browsers shared by catalog, Trakt, and aggregated search.
///
/// Real-Debrid and TorBox use their own download screens (not this helper).
/// Unknown providers return null so the caller does nothing — same as the
/// old `default: return`.
class CloudBrowseSelectSource {
  CloudBrowseSelectSource._();

  static Widget? page({
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) {
    switch (provider) {
      case 'premiumize':
        return PremiumizeFilesScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case 'alldebrid':
        return AllDebridFilesScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case 'pikpak':
        return PikPakFilesScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      default:
        return null;
    }
  }

  static void push(
    BuildContext context, {
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) {
    final screen = page(
      provider: provider,
      query: query,
      onSourceSelected: onSourceSelected,
    );
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}
