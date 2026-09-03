import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences + ProfileRuntime reset used by characterization tests.
Future<void> installLegacyPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(values));
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
}
