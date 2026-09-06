import 'dart:convert';

import '../profiles/profile_preferences.dart';

/// Installation-wide remote preferences, separate from pairing and sessions.
abstract final class RemoteDevicePrefs {
  static const String _remoteControlEnabledKey = 'remote_control_enabled';
  static const String _remoteIntroShownKey = 'remote_intro_shown';
  static const String _remoteTvDeviceNameKey = 'remote_tv_device_name';
  static const String _remoteLastDeviceKey = 'remote_last_device';

  static const Set<String> ownedKeys = {
    _remoteControlEnabledKey,
    _remoteIntroShownKey,
    _remoteTvDeviceNameKey,
    _remoteLastDeviceKey,
  };

  static Future<bool> getRemoteControlEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteControlEnabledKey) ?? true;
  }

  static Future<void> setRemoteControlEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteControlEnabledKey, enabled);
  }

  static Future<bool> getRemoteIntroShown() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteIntroShownKey) ?? false;
  }

  static Future<void> setRemoteIntroShown(bool shown) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteIntroShownKey, shown);
  }

  static Future<String?> getRemoteTvDeviceName() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_remoteTvDeviceNameKey);
  }

  static Future<void> setRemoteTvDeviceName(String name) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteTvDeviceNameKey, name);
  }

  static Future<Map<String, dynamic>?> getRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    final raw = prefs.getString(_remoteLastDeviceKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setRemoteLastDevice(Map<String, dynamic> device) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteLastDeviceKey, jsonEncode(device));
  }

  static Future<void> clearRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    await prefs.remove(_remoteLastDeviceKey);
  }
}
