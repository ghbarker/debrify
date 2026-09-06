import 'profile_authorization.dart';
import 'profile_bootstrap.dart';
import 'profile_preferences.dart';
import 'profile_runtime.dart';

/// Canonical onboarding readiness and retirement of its compatibility flag.
abstract final class ProfileOnboardingState {
  static const String _onboardingCompleteKey = 'initial_setup_complete_v1';

  static const Set<String> ownedKeys = {_onboardingCompleteKey};

  static Future<bool> isInitialSetupComplete() async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      return prefs.getBool(_onboardingCompleteKey) ?? false;
    }

    final scope = ProfileRuntime.capture();
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (profile == null ||
        !profile.isEnabled ||
        profile.visibleDataGeneration != scope.dataGeneration) {
      throw StateError('Active profile onboarding state is unavailable');
    }

    // Builds that first introduced profiles wrote onboarding state to two
    // places. Honor an explicitly stored value once (notably `false` from a
    // profile reset), reconcile it into the registry, then remove the
    // compatibility value. If the key is absent, the registry was already
    // correct for migrated Admins and Admin-created profiles.
    if (!prefs.containsKey(_onboardingCompleteKey)) {
      return profile.setupComplete;
    }
    final compatibilityValue = prefs.getBool(_onboardingCompleteKey);
    if (compatibilityValue == null) {
      throw const FormatException('Invalid onboarding completion state');
    }
    if (compatibilityValue != profile.setupComplete) {
      final authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      if (ProfileRuntime.capture() != scope ||
          authorization.profileId != scope.profileId) {
        throw StateError('Active profile onboarding session has changed');
      }
      await ProfileBootstrap.registry.setActiveProfileSetupComplete(
        profileId: authorization.profileId,
        setupComplete: compatibilityValue,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
    }
    if (!await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    return compatibilityValue;
  }

  static Future<void> setInitialSetupComplete(bool value) async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      await prefs.setBool(_onboardingCompleteKey, value);
      return;
    }

    final authorization = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await authorization.validate(ProfileBootstrap.registry);
    // Remove the retired compatibility value before the canonical write. If
    // authority changes, the stale scoped wrapper fails and no other profile
    // can be mutated. A later retry safely starts from the registry value.
    if (prefs.containsKey(_onboardingCompleteKey) &&
        !await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    if (profile.setupComplete == value) return;
    await ProfileBootstrap.registry.setActiveProfileSetupComplete(
      profileId: authorization.profileId,
      setupComplete: value,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
  }
}
