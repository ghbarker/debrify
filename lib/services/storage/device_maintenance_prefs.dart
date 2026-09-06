import '../profiles/profile_preferences.dart';

/// Installation-wide support and update preferences, not network or install authority.
abstract final class DeviceMaintenancePrefs {
  static const String _supportRemoteConfigCacheKey =
      'support_remote_config_cache_v1';
  static const String _dismissedDonationCampaignIdsKey =
      'dismissed_donation_campaign_ids_v1';
  static const String _updateAutoCheckEnabledKey = 'update_auto_check_enabled';
  static const String _updateIgnoredVersionKey = 'update_ignored_version';

  static const Set<String> ownedKeys = {
    _supportRemoteConfigCacheKey,
    _dismissedDonationCampaignIdsKey,
    _updateAutoCheckEnabledKey,
    _updateIgnoredVersionKey,
  };

  static Future<String?> getSupportRemoteConfigCache() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_supportRemoteConfigCacheKey);
  }

  static Future<void> setSupportRemoteConfigCache(String json) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_supportRemoteConfigCacheKey, json);
  }

  static Future<List<String>> getDismissedDonationCampaignIds() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
  }

  static Future<void> dismissDonationCampaign(String campaignId) async {
    final prefs = await DevicePreferences.instance();
    final ids =
        prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
    if (ids.contains(campaignId)) return;
    ids.add(campaignId);
    await prefs.setStringList(_dismissedDonationCampaignIdsKey, ids);
  }

  static Future<bool> getUpdateAutoCheckEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_updateAutoCheckEnabledKey) ?? true;
  }

  static Future<void> setUpdateAutoCheckEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_updateAutoCheckEnabledKey, enabled);
  }

  static Future<String?> getIgnoredUpdateVersion() async {
    final prefs = await DevicePreferences.instance();
    final value = prefs.getString(_updateIgnoredVersionKey);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> setIgnoredUpdateVersion(String? version) async {
    final prefs = await DevicePreferences.instance();
    if (version == null || version.trim().isEmpty) {
      await prefs.remove(_updateIgnoredVersionKey);
    } else {
      await prefs.setString(_updateIgnoredVersionKey, version);
    }
  }
}
