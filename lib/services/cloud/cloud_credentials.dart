import '../storage_service.dart';
import 'cloud_provider_id.dart';

/// Which "is this provider set up?" question to ask.
///
/// One `(needsKey, needsToggle)` row per surface — not aliases:
/// playback key/enabled, magnet key+toggle, Stremio TV picker, Stremio
/// resolve (PM/AD toggle-only). Per-torrent skip (blocked RD, auto TorBox
/// cache) stays on [StremioTvResolveGate].
enum CloudSurface { playback, magnet, stremioPicker, stremioResolve }

/// Old name for [CloudSurface]. Kept one release for existing call sites.
@Deprecated('Use CloudSurface')
typedef CloudConfiguredCheck = CloudSurface;

/// Key/toggle pair for [CloudCredentials.configured].
class CloudSurfaceNeeds {
  const CloudSurfaceNeeds({required this.needsKey, required this.needsToggle});

  final bool needsKey;
  final bool needsToggle;

  /// One table per surface. PikPak's "toggle" is [StorageService.getPikPakEnabled]
  /// (not an integration-enabled flag and not the email).
  static CloudSurfaceNeeds forId(CloudProviderId id, CloudSurface surface) {
    return switch ((surface, id)) {
      (CloudSurface.playback, CloudProviderId.pikpak) =>
        const CloudSurfaceNeeds(needsKey: false, needsToggle: true),
      (CloudSurface.playback, _) => const CloudSurfaceNeeds(
        needsKey: true,
        needsToggle: false,
      ),
      (CloudSurface.magnet, CloudProviderId.pikpak) => const CloudSurfaceNeeds(
        needsKey: false,
        needsToggle: true,
      ),
      (CloudSurface.magnet, _) => const CloudSurfaceNeeds(
        needsKey: true,
        needsToggle: true,
      ),
      (CloudSurface.stremioPicker, CloudProviderId.debrid) ||
      (
        CloudSurface.stremioPicker,
        CloudProviderId.torbox,
      ) => const CloudSurfaceNeeds(needsKey: true, needsToggle: false),
      (CloudSurface.stremioPicker, CloudProviderId.pikpak) =>
        const CloudSurfaceNeeds(needsKey: false, needsToggle: true),
      (CloudSurface.stremioPicker, _) => const CloudSurfaceNeeds(
        needsKey: true,
        needsToggle: true,
      ),
      (CloudSurface.stremioResolve, CloudProviderId.premiumize) ||
      (
        CloudSurface.stremioResolve,
        CloudProviderId.alldebrid,
      ) => const CloudSurfaceNeeds(needsKey: false, needsToggle: true),
      (CloudSurface.stremioResolve, _) => const CloudSurfaceNeeds(
        needsKey: false,
        needsToggle: false,
      ),
    };
  }
}

/// Facade over [StorageService] cloud-provider credentials.
///
/// Preference keys stay in StorageService (profile-owned). New call sites
/// should read through this type so playback, magnets, backups, and tests
/// share one mapping.
class CloudCredentials {
  CloudCredentials._();

  static Future<String?> apiKey(CloudProviderId id) async {
    switch (id) {
      case CloudProviderId.debrid:
        return StorageService.getApiKey();
      case CloudProviderId.torbox:
        return StorageService.getTorboxApiKey();
      case CloudProviderId.premiumize:
        return StorageService.getPremiumizeApiKey();
      case CloudProviderId.alldebrid:
        return StorageService.getAllDebridApiKey();
      case CloudProviderId.pikpak:
        return StorageService.getPikPakEmail();
    }
  }

  /// Dispatch for the four credential dialects.
  static Future<bool> configured(
    CloudProviderId id,
    CloudSurface surface,
  ) async {
    final spec = CloudSurfaceNeeds.forId(id, surface);
    if (spec.needsKey) {
      final key = await apiKey(id);
      if (key == null || key.isEmpty) return false;
    }
    if (spec.needsToggle) {
      if (!await _toggleEnabled(id)) return false;
    }
    return true;
  }

  static Future<bool> _toggleEnabled(CloudProviderId id) {
    switch (id) {
      case CloudProviderId.debrid:
        return StorageService.getRealDebridIntegrationEnabled();
      case CloudProviderId.torbox:
        return StorageService.getTorboxIntegrationEnabled();
      case CloudProviderId.premiumize:
        return StorageService.getPremiumizeIntegrationEnabled();
      case CloudProviderId.alldebrid:
        return StorageService.getAllDebridIntegrationEnabled();
      case CloudProviderId.pikpak:
        return StorageService.getPikPakEnabled();
    }
  }

  /// Playback [TorrentPlaybackService] definition: key non-empty, PikPak uses
  /// [StorageService.getPikPakEnabled] (not the email).
  @Deprecated('Use configured(id, CloudSurface.playback)')
  static Future<bool> isPlaybackConfigured(CloudProviderId id) =>
      configured(id, CloudSurface.playback);

  /// Magnet / share-sheet definition: API key plus integration enabled.
  @Deprecated('Use configured(id, CloudSurface.magnet)')
  static Future<bool> isMagnetConfigured(CloudProviderId id) =>
      configured(id, CloudSurface.magnet);

  /// Stremio TV *picker* on the Stremio TV screen. Not playback
  /// (PM/AD skip the integration toggle there) and not magnet
  /// (RD/TB require the integration toggle there). PikPak is enabled-only.
  /// Settings (`stremio_tv_settings_page`) is a different list: no PM/AD.
  @Deprecated('Use configured(id, CloudSurface.stremioPicker)')
  static Future<bool> isStremioAvailable(CloudProviderId id) =>
      configured(id, CloudSurface.stremioPicker);

  /// Stremio TV resolve gate for PM/AD (toggle-only). Not picker (key+toggle)
  /// and not per-torrent skip (blocked RD / auto TorBox cache).
  @Deprecated('Use configured(id, CloudSurface.stremioResolve)')
  static Future<bool> isStremioResolveConfigured(CloudProviderId id) =>
      configured(id, CloudSurface.stremioResolve);

  /// Picker rows for the Stremio TV screen. Order is RD → TB → PikPak → PM → AD
  /// (PikPak before Premiumize — not [CloudProviderId.playbackPrecedence]).
  /// Labels are [CloudProviderId.catalogChoice] (`realdebrid` / `Real-Debrid`),
  /// not Magic TV `Real Debrid`.
  static Future<List<MapEntry<String, String>>> stremioPickerChoices() async {
    const order = [
      CloudProviderId.debrid,
      CloudProviderId.torbox,
      CloudProviderId.pikpak,
      CloudProviderId.premiumize,
      CloudProviderId.alldebrid,
    ];
    final out = <MapEntry<String, String>>[];
    for (final id in order) {
      if (await configured(id, CloudSurface.stremioPicker)) {
        out.add(id.catalogChoice);
      }
    }
    return out;
  }

  /// Secrets included in a credentialed backup (same JSON keys as today).
  static Future<Map<String, dynamic>> backupSecrets() async {
    final out = <String, dynamic>{};
    final rd = await StorageService.getApiKey();
    final tb = await StorageService.getTorboxApiKey();
    final pm = await StorageService.getPremiumizeApiKey();
    final ad = await StorageService.getAllDebridApiKey();
    final email = await StorageService.getPikPakEmail();
    final password = await StorageService.getPikPakPassword();
    if (rd != null && rd.isNotEmpty) out['realDebridApiKey'] = rd;
    if (tb != null && tb.isNotEmpty) out['torboxApiKey'] = tb;
    if (pm != null && pm.isNotEmpty) out['premiumizeApiKey'] = pm;
    if (ad != null && ad.isNotEmpty) out['allDebridApiKey'] = ad;
    if (email != null && email.isNotEmpty) {
      out['pikpak'] = <String, dynamic>{
        'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
      };
    }
    return out;
  }

  /// Post-add action (`choose` / `play` / …). Real-Debrid uses the unprefixed
  /// `post_torrent_action` key — that is load-bearing.
  static Future<String> postTorrentAction(CloudProviderId id) {
    switch (id) {
      case CloudProviderId.torbox:
        return StorageService.getTorboxPostTorrentAction();
      case CloudProviderId.premiumize:
        return StorageService.getPremiumizePostTorrentAction();
      case CloudProviderId.alldebrid:
        return StorageService.getAllDebridPostTorrentAction();
      case CloudProviderId.pikpak:
        return StorageService.getPikPakPostTorrentAction();
      case CloudProviderId.debrid:
        return StorageService.getPostTorrentAction();
    }
  }
}
