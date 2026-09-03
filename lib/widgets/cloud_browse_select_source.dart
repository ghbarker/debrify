import 'package:flutter/material.dart';

import '../screens/alldebrid/alldebrid_files_screen.dart';
import '../screens/pikpak/pikpak_files_screen.dart';
import '../screens/premiumize/premiumize_files_screen.dart';
import '../services/cloud/cloud_provider_id.dart';
import '../services/series_source_service.dart';

/// Bind-source cloud browsers for catalog, Trakt, and aggregated search.
/// RD/TorBox keep their download screens. Unknown → null (old `default`).
class CloudBrowseSelectSource {
  CloudBrowseSelectSource._();

  static Widget? page({
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) {
    switch (CloudProviderId.fromPlaybackId(provider)) {
      case CloudProviderId.premiumize:
        return PremiumizeFilesScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case CloudProviderId.alldebrid:
        return AllDebridFilesScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case CloudProviderId.pikpak:
        return PikPakFilesScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case CloudProviderId.debrid ||
          CloudProviderId.torbox ||
          null:
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
