import 'package:flutter/material.dart';

import '../series_source_service.dart';
import 'cloud_provider_id.dart';

/// Playback chrome uses exact playback ids. Catalog/bind-source helpers parse
/// stored ids. [label] does not map `rd`; [sourceLabel] maps `rd` → Real-Debrid
/// and local → `Local` (not [label]'s `On-device`).
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

  /// Edit-Sources chip. Stored ids (`rd`), not playback (`debrid`).
  static String sourceLabel(String stored) {
    switch (stored) {
      case SeriesSource.localService:
        return 'Local';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      default:
        return CloudProviderId.fromStoredId(stored)?.displayName ?? stored;
    }
  }

  /// Edit-Sources chip color. Not [gradient] — TorBox is blue here, purple
  /// on the playback loader.
  static Color sourceColor(String stored) {
    switch (stored) {
      case SeriesSource.localService:
        return const Color(0xFF60A5FA);
      case SeriesSource.addonDirectService:
        return const Color(0xFFA78BFA);
      default:
        return switch (CloudProviderId.fromStoredId(stored)) {
          CloudProviderId.debrid => const Color(0xFF10B981),
          CloudProviderId.torbox => const Color(0xFF3B82F6),
          CloudProviderId.pikpak => const Color(0xFFF59E0B),
          CloudProviderId.premiumize => const Color(0xFFFB923C),
          CloudProviderId.alldebrid => const Color(0xFF26A69A),
          null => Colors.white54,
        };
    }
  }
}
