import '../profiles/profile_credential_facade.dart';
import '../profiles/profile_preferences.dart';
import '../secret_vault.dart';

/// Profile-owned cloud credential keys and SecretVault access.
///
/// [StorageService] stays the public static facade. Persisted names must not
/// change; they match [CloudProviderId.credentialKey].
class CloudSecretPrefs {
  CloudSecretPrefs._();

  static const realDebridApiKey = 'real_debrid_api_key';
  static const torboxApiKey = 'torbox_api_key';
  static const premiumizeApiKey = 'premiumize_api_key';
  static const allDebridApiKey = 'alldebrid_api_key';
  static const pikpakEmail = 'pikpak_email';
  static const pikpakPassword = 'pikpak_password';

  static Future<String?> read(
    String key, {
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        key,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, key);
  }

  static Future<void> write(String key, String value) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, key, value);
  }

  static Future<void> delete(String key) async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(key)) {
      await prefs.remove(key);
    }
  }

  static Future<bool> isConfigured(String key) async {
    final presence = await ProfileCredentialFacade.isConfigured(key);
    if (presence.handled) return presence.configured;
    final value = await read(key);
    return value != null && value.isNotEmpty;
  }
}
