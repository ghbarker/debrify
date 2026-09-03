import 'package:flutter/material.dart';

import '../series_source_service.dart';
import 'cloud_provider_id.dart';

/// Labels, chips, and action-sheet chrome for cloud providers.
///
/// Playback ids (`debrid`) and a few non-cloud loader ids (`preparing`,
/// `stream`, local/addon binds) live here so [TorrentPlaybackService] is not
/// the only copy of the mapping.
class CloudProviderChrome {
  CloudProviderChrome._();

  static String label(String provider) {
    switch (provider) {
      case 'preparing':
        return 'Preparing';
      case 'debrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'premiumize':
        return 'Premiumize';
      case 'alldebrid':
        return 'AllDebrid';
      case 'pikpak':
        return 'PikPak';
      case SeriesSource.localService:
        return 'On-device';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      case 'stream':
        return 'Stream';
      default:
        return provider;
    }
  }

  /// Two-letter glyph for the Pipeline loader chip.
  static String code(String provider) {
    switch (provider) {
      case 'preparing':
        return '···';
      case 'debrid':
        return 'RD';
      case 'torbox':
        return 'TB';
      case 'premiumize':
        return 'PM';
      case 'alldebrid':
        return 'AD';
      case 'pikpak':
        return 'PP';
      case 'stream':
        return 'TV';
      case SeriesSource.addonDirectService:
        return 'DL';
      default:
        return provider.isEmpty ? '·' : provider.substring(0, 1).toUpperCase();
    }
  }

  static List<Color> gradient(String provider) {
    switch (provider) {
      case 'debrid':
        return const [Color(0xFF10B981), Color(0xFF059669)];
      case 'torbox':
        return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
      case 'premiumize':
        return const [Color(0xFFF59E0B), Color(0xFFD97706)];
      case 'alldebrid':
        return const [Color(0xFF26A69A), Color(0xFF00796B)];
      case 'pikpak':
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
      default:
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
    }
  }

  static IconData icon(String provider) {
    switch (provider) {
      case 'debrid':
        return Icons.cloud_download_rounded;
      case 'torbox':
        return Icons.flash_on_rounded;
      case 'premiumize':
        return Icons.workspace_premium_rounded;
      case 'alldebrid':
        return Icons.all_inclusive_rounded;
      case 'pikpak':
        return Icons.cloud_circle_rounded;
      default:
        return Icons.cloud_download_rounded;
    }
  }

  /// Catalog / Stremio TV ids use `realdebrid` instead of playback `debrid`.
  /// `auto` and unknown strings are `AUTO` (not a guess at the first letter).
  static String catalogChip(String provider) {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return 'AUTO';
    return code(id.playbackId);
  }

  /// Null when [provider] is not a known cloud id so the caller can render Auto.
  static String? catalogTitle(String provider) {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return null;
    return label(id.playbackId);
  }
}
