import 'package:flutter/material.dart';

import '../series_source_service.dart';
import 'cloud_provider_id.dart';

/// Flutter colors/icons. String identity lives on [CloudProviderId].
///
/// Lookup rules, on purpose:
/// - [label]/[code]/[gradient]/[icon]: exact playback id (`debrid`, not `rd`)
/// - [catalogChip]/[catalogTitle]: [CloudProviderId.tryParse]; `auto` → AUTO
/// - [playlistBadge]: playlist JSON; empty → RD, `webdav` → DV, else two letters
/// - [sourceChip]: stored id (`rd`); local is `Local`, not [label]'s `On-device`
class CloudProviderChrome {
  CloudProviderChrome._();

  static const _indigo = [Color(0xFF6366F1), Color(0xFF4338CA)];

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
      CloudProviderId.pikpak || null => _indigo,
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

  /// `auto` / unknown → `AUTO`, not the first letter of the string.
  static String catalogChip(String provider) {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return 'AUTO';
    return id.chipCode;
  }

  static String? catalogTitle(String provider) {
    return CloudProviderId.tryParse(provider)?.displayName;
  }

  /// Playlist card glyph. Not [catalogChip]: empty is RD, unknown is two
  /// letters, WebDAV is DV.
  static String playlistBadge(String? raw) {
    if (raw == null || raw.isEmpty) return CloudProviderId.debrid.chipCode;
    switch (raw.toLowerCase()) {
      case 'webdav':
        return 'DV';
      case 'pik-pak':
      case 'pik_pak':
        return CloudProviderId.pikpak.chipCode;
      default:
        return CloudProviderId.tryParse(raw)?.chipCode ??
            raw.substring(0, 2).toUpperCase();
    }
  }

  /// Bind-source chip. TorBox is blue here; playback [gradient] is purple.
  static ({String label, Color color}) sourceChip(String stored) => (
        label: _sourceLabel(stored),
        color: _sourceColor(stored),
      );

  static String _sourceLabel(String stored) {
    switch (stored) {
      case SeriesSource.localService:
        return 'Local';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      default:
        return CloudProviderId.fromStoredId(stored)?.displayName ?? stored;
    }
  }

  static Color _sourceColor(String stored) {
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
