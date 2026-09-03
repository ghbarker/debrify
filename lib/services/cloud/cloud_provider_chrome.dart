import 'package:flutter/material.dart';

import '../series_source_service.dart';
import 'cloud_provider_id.dart';

/// Flutter chrome for playback ids and a few non-cloud loader ids.
///
/// Cloud string identity ([CloudProviderId.displayName], [CloudProviderId.chipCode],
/// [CloudProviderId.overlayTitle]) lives on the enum so this file only maps
/// colors/icons and ids Flutter owns (`preparing`, `stream`, local/addon).
///
/// [label] / [code] / [gradient] / [icon] match **playback** ids only — do not
/// parse `rd` / `realdebrid` here; [TorrentPlaybackService._label] historically
/// passed those strings through unchanged. Catalog surfaces use [catalogChip]
/// / [catalogTitle], which do parse aliases.
class CloudProviderChrome {
  CloudProviderChrome._();

  static String label(String provider) {
    switch (provider) {
      case 'preparing':
        return 'Preparing';
      case SeriesSource.localService:
        return 'On-device';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      case 'stream':
        return 'Stream';
      default:
        return CloudProviderId.fromPlaybackId(provider)?.displayName ??
            provider;
    }
  }

  /// Two-letter glyph for the Pipeline loader chip.
  static String code(String provider) {
    switch (provider) {
      case 'preparing':
        return '···';
      case 'stream':
        return 'TV';
      case SeriesSource.addonDirectService:
        return 'DL';
      default:
        final cloud = CloudProviderId.fromPlaybackId(provider);
        if (cloud != null) return cloud.chipCode;
        return provider.isEmpty ? '·' : provider.substring(0, 1).toUpperCase();
    }
  }

  static List<Color> gradient(String provider) {
    return switch (CloudProviderId.fromPlaybackId(provider)) {
      CloudProviderId.debrid => const [
        Color(0xFF10B981),
        Color(0xFF059669),
      ],
      CloudProviderId.torbox => const [
        Color(0xFF8B5CF6),
        Color(0xFF7C3AED),
      ],
      CloudProviderId.premiumize => const [
        Color(0xFFF59E0B),
        Color(0xFFD97706),
      ],
      CloudProviderId.alldebrid => const [
        Color(0xFF26A69A),
        Color(0xFF00796B),
      ],
      CloudProviderId.pikpak || null => const [
        Color(0xFF6366F1),
        Color(0xFF4338CA),
      ],
    };
  }

  static IconData icon(String provider) {
    return switch (CloudProviderId.fromPlaybackId(provider)) {
      CloudProviderId.debrid => Icons.cloud_download_rounded,
      CloudProviderId.torbox => Icons.flash_on_rounded,
      CloudProviderId.premiumize => Icons.workspace_premium_rounded,
      CloudProviderId.alldebrid => Icons.all_inclusive_rounded,
      CloudProviderId.pikpak => Icons.cloud_circle_rounded,
      null => Icons.cloud_download_rounded,
    };
  }

  /// Catalog / Stremio TV ids use `realdebrid` instead of playback `debrid`.
  /// `auto` and unknown strings are `AUTO` (not a guess at the first letter).
  static String catalogChip(String provider) {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return 'AUTO';
    return id.chipCode;
  }

  /// Null when [provider] is not a known cloud id so the caller can render Auto.
  static String? catalogTitle(String provider) {
    return CloudProviderId.tryParse(provider)?.displayName;
  }
}
