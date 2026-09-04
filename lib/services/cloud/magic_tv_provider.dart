import 'cloud_provider_id.dart';

/// Debrify TV preferred pick and overlay strings.
///
/// Fallback walks [CloudProviderId.playbackPrecedence]. Preferred is the
/// Magic TV chip id (`real_debrid`), not Settings default torrent provider
/// (`debrid` / `none`).
class MagicTvProvider {
  MagicTvProvider._();

  /// Overlay / snack copy. Unknown and Real-Debrid both print `Real Debrid`.
  /// Not [CloudProviderId.displayName] (`Real-Debrid` / `TorBox`).
  static String display(String provider) {
    if (provider == CloudProviderId.torbox.magicTvId) return 'Torbox';
    if (provider == CloudProviderId.pikpak.magicTvId) return 'PikPak';
    if (provider == CloudProviderId.premiumize.magicTvId) return 'Premiumize';
    if (provider == CloudProviderId.alldebrid.magicTvId) return 'AllDebrid';
    return 'Real Debrid';
  }

  static Map<CloudProviderId, bool> availability({
    required bool realDebrid,
    required bool torbox,
    required bool pikpak,
    required bool premiumize,
    required bool allDebrid,
  }) => {
    CloudProviderId.debrid: realDebrid,
    CloudProviderId.torbox: torbox,
    CloudProviderId.pikpak: pikpak,
    CloudProviderId.premiumize: premiumize,
    CloudProviderId.alldebrid: allDebrid,
  };

  static String pickDefault({
    required String? preferred,
    required Map<CloudProviderId, bool> available,
  }) {
    final preferredId = preferred == null
        ? null
        : CloudProviderId.fromMagicTvId(preferred);
    if (preferredId != null && available[preferredId] == true) {
      return preferredId.magicTvId;
    }
    for (final id in CloudProviderId.playbackPrecedence) {
      if (available[id] == true) return id.magicTvId;
    }
    return CloudProviderId.debrid.magicTvId;
  }
}
