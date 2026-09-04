import 'package:flutter/material.dart';

import '../../services/cloud/cloud_capabilities.dart';
import '../../services/cloud/cloud_port_feature.dart';
import '../../services/cloud/cloud_provider_id.dart';
import '../../services/cloud/cloud_provider_port.dart';
import '../../services/cloud/cloud_provider_registry.dart';
import '../../widgets/cloud_provider_chrome.dart';
import '../../widgets/pipeline_loading_overlay.dart';

/// Stremio TV provider-string dispatch. Persisted picker ids stay
/// [CloudProviderId.playlistStoredProvider] (`realdebrid`, not playback
/// `debrid` and not Magic TV `real_debrid`). `auto` is the frozen sentinel,
/// not a provider id.
///
/// Production adapters are routed with capability `is` checks. Fat-port
/// [FakeCloudProvider] (P1) does not implement those types, so [supports]
/// is the fallback — same dual path as [CloudProviderRegistry.prepareMagicTv].
class StremioTvDispatch {
  StremioTvDispatch._();

  static CloudProviderPort? portFor(String stremioId) {
    final id = CloudProviderId.tryParse(stremioId);
    if (id == null) return null;
    return CloudProviderRegistry.instance[id];
  }

  /// Overlay cache-check stage. TorBox [CloudCachedHashes] or Premiumize
  /// [CloudCheckCache]. Auto / RD / AllDebrid / PikPak stay false (no
  /// explicit filter HTTP). Not auto-play [StremioTvTorboxCache.load].
  static bool hasCacheCheck(String stremioId) {
    final port = portFor(stremioId);
    if (port == null) return false;
    if (port is CloudCachedHashes || port is CloudCheckCache) return true;
    return port.supports(CloudPortFeature.cachedHashes) ||
        port.supports(CloudPortFeature.checkCache);
  }

  /// DebugPrint brand during [StremioTvCacheFilter] `onChecked`.
  ///
  /// Quirk: anything that is not a [CloudCachedHashes] port prints
  /// Premiumize — even `auto` / `realdebrid`. `onChecked` only fires for
  /// the TorBox and Premiumize filters today.
  static String cacheCheckDebugLabel(String stremioId) {
    final port = portFor(stremioId);
    if (port == null) return CloudProviderId.premiumize.displayName;
    if (port is CloudCachedHashes) return port.id.displayName;
    if (port.supports(CloudPortFeature.cachedHashes)) {
      return port.id.displayName;
    }
    return CloudProviderId.premiumize.displayName;
  }

  /// Play-loader chrome. Auto / unknown stays `Debrid` / `DB` / overlay
  /// accent — not catalog `AUTO`. Lookup is [CloudProviderId.tryParse] so
  /// `realdebrid` hits RD; [CloudProviderId.fromPlaybackId] would miss.
  static ({String label, String code, Color color, bool cacheCheck})
  overlayInfo(String stremioId) {
    final id = CloudProviderId.tryParse(stremioId);
    if (id == null) {
      return (
        label: 'Debrid',
        code: 'DB',
        color: PipelineLoadingOverlay.accent,
        cacheCheck: false,
      );
    }
    return (
      label: id.displayName,
      code: id.chipCode,
      color: CloudProviderChrome.gradient(id.playbackId).first,
      cacheCheck: hasCacheCheck(stremioId),
    );
  }
}
