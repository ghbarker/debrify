import '../storage_service.dart';
import 'cloud_provider_id.dart';

/// Which "is this provider set up?" question to ask.
///
/// These are three different StorageService combinations, not aliases:
/// playback key/enabled, magnet key+toggle, Stremio TV picker.
/// Per-torrent Stremio resolve (`canAttempt`) is not a credentials check.
enum CloudConfiguredCheck {
  playback,
  magnet,
  stremioPicker,
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

  /// Dispatch for the three credential dialects. Wrappers below stay for
  /// existing call sites; do not fold Stremio resolve-skip into this.
  static Future<bool> configured(
    CloudProviderId id,
    CloudConfiguredCheck check,
  ) {
    switch (check) {
      case CloudConfiguredCheck.playback:
        return _playbackConfigured(id);
      case CloudConfiguredCheck.magnet:
        return _magnetConfigured(id);
      case CloudConfiguredCheck.stremioPicker:
        return _stremioPickerConfigured(id);
    }
  }

  /// Playback [TorrentPlaybackService] definition: key non-empty, PikPak uses
  /// [StorageService.getPikPakEnabled] (not the email).
  static Future<bool> isPlaybackConfigured(CloudProviderId id) =>
      configured(id, CloudConfiguredCheck.playback);

  /// Magnet / share-sheet definition: API key plus integration enabled.
  static Future<bool> isMagnetConfigured(CloudProviderId id) =>
      configured(id, CloudConfiguredCheck.magnet);

  /// Stremio TV *picker* on the Stremio TV screen. Not playback
  /// (PM/AD skip the integration toggle there) and not magnet
  /// (RD/TB require the integration toggle there). PikPak is enabled-only.
  /// Settings (`stremio_tv_settings_page`) is a different list: no PM/AD.
  static Future<bool> isStremioAvailable(CloudProviderId id) =>
      configured(id, CloudConfiguredCheck.stremioPicker);

  static Future<bool> _playbackConfigured(CloudProviderId id) async {
    if (id == CloudProviderId.pikpak) {
      return StorageService.getPikPakEnabled();
    }
    final key = await apiKey(id);
    return key != null && key.isNotEmpty;
  }

  static Future<bool> _magnetConfigured(CloudProviderId id) async {
    switch (id) {
      case CloudProviderId.debrid:
        final key = await StorageService.getApiKey();
        final enabled = await StorageService.getRealDebridIntegrationEnabled();
        return key != null && key.isNotEmpty && enabled;
      case CloudProviderId.torbox:
        final key = await StorageService.getTorboxApiKey();
        final enabled = await StorageService.getTorboxIntegrationEnabled();
        return key != null && key.isNotEmpty && enabled;
      case CloudProviderId.premiumize:
        final key = await StorageService.getPremiumizeApiKey();
        final enabled = await StorageService.getPremiumizeIntegrationEnabled();
        return key != null && key.isNotEmpty && enabled;
      case CloudProviderId.alldebrid:
        final key = await StorageService.getAllDebridApiKey();
        final enabled = await StorageService.getAllDebridIntegrationEnabled();
        return key != null && key.isNotEmpty && enabled;
      case CloudProviderId.pikpak:
        return StorageService.getPikPakEnabled();
    }
  }

  static Future<bool> _stremioPickerConfigured(CloudProviderId id) async {
    switch (id) {
      case CloudProviderId.debrid:
      case CloudProviderId.torbox:
        final key = await apiKey(id);
        return key != null && key.isNotEmpty;
      case CloudProviderId.pikpak:
        return StorageService.getPikPakEnabled();
      case CloudProviderId.premiumize:
        final key = await StorageService.getPremiumizeApiKey();
        final enabled = await StorageService.getPremiumizeIntegrationEnabled();
        return enabled && key != null && key.isNotEmpty;
      case CloudProviderId.alldebrid:
        final key = await StorageService.getAllDebridApiKey();
        final enabled = await StorageService.getAllDebridIntegrationEnabled();
        return enabled && key != null && key.isNotEmpty;
    }
  }

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
      if (await configured(id, CloudConfiguredCheck.stremioPicker)) {
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
