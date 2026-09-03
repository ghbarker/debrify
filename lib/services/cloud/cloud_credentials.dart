import '../storage_service.dart';
import 'cloud_provider_id.dart';

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

  /// Playback [TorrentPlaybackService] definition: key non-empty, PikPak uses
  /// [StorageService.getPikPakEnabled] (not the email).
  static Future<bool> isPlaybackConfigured(CloudProviderId id) async {
    if (id == CloudProviderId.pikpak) {
      return StorageService.getPikPakEnabled();
    }
    final key = await apiKey(id);
    return key != null && key.isNotEmpty;
  }

  /// Magnet / share-sheet definition: API key plus integration enabled.
  static Future<bool> isMagnetConfigured(CloudProviderId id) async {
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
}
