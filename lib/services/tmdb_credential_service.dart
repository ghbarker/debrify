import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import 'metadata_preferences_service.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/device_key_provider.dart';
import 'profiles/profile_authorization.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_lock_controller.dart';
import 'profiles/profile_runtime.dart';
import 'secret_vault.dart';

/// A request's credential and authorization, never a UI view model.
class TmdbCredentialSnapshot {
  TmdbCredentialSnapshot(this.token, this.isCurrent, this._authorize);
  final String token;
  final bool Function() isCurrent;
  final Future<void> Function() _authorize;

  Future<void> validate() async {
    if (!isCurrent()) throw StateError('TMDB configuration changed');
    await _authorize();
    if (!isCurrent()) throw StateError('TMDB configuration changed');
  }
}

/// Profile-owned runtime override; build credentials remain a fallback.
/// Committed profiles use the resource vault, not preference secret strings.
abstract final class TmdbCredentialService {
  static const key = 'tmdb_read_access_token';
  static const slot = 'metadata.tmdb';
  static const buildToken = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');
  static final revision = ValueNotifier<int>(0);
  static var _writes = Lock();
  static bool _listening = false;
  static Future<void>? _loading;
  static String? _override;
  static Object? _scope;
  static int _loadGeneration = 0;

  static String get effectiveToken => _scope == ProfileRuntime.scope.value
      ? (_override ?? buildToken).trim()
      : buildToken.trim();
  static bool get hasOverride =>
      _scope == ProfileRuntime.scope.value && _override != null;

  /// Call after ProfileBootstrap. Scope and lock changes revoke work immediately.
  static Future<void> initialize() {
    if (_listening) return _loading ?? Future<void>.value();
    _listening = true;
    ProfileRuntime.scope.addListener(_scopeChanged);
    ProfileLockController.instance.lockedProfileId.addListener(_scopeChanged);
    return _startRefresh();
  }

  static Future<void> _startRefresh() {
    final work = refresh().catchError((Object _) {});
    _loading = work;
    unawaited(
      work.then((_) {
        if (identical(_loading, work)) _loading = null;
      }),
    );
    return work;
  }

  static void _notify() {
    revision.value++;
    MetadataPreferencesService.revision.value++;
  }

  static void _scopeChanged() {
    _loadGeneration++;
    _override = null;
    _scope = ProfileRuntime.scope.value;
    _notify();
    // A failed refresh must not poison initialize/capture until another switch.
    // Each capture still performs a fresh, authorized read.
    _startRefresh();
  }

  static Future<void> refresh() async {
    final generation = ++_loadGeneration;
    final scope = ProfileRuntime.scope.value;
    final read = await _read();
    await read.authorize();
    if (generation != _loadGeneration || scope != ProfileRuntime.scope.value) {
      return;
    }
    final value = read.value?.trim();
    final next = value == null || value.isEmpty ? null : value;
    final changed = _scope != scope || _override != next;
    _scope = scope;
    _override = next;
    if (changed) _notify();
  }

  static Future<TmdbCredentialSnapshot> capture() async {
    await initialize();
    return _writes.synchronized(() async {
      final scope = ProfileRuntime.scope.value;
      final generation = _loadGeneration;
      final read = await _read();
      await read.authorize();
      if (scope != ProfileRuntime.scope.value ||
          generation != _loadGeneration) {
        throw StateError('TMDB configuration changed');
      }
      final value = read.value?.trim();
      final next = value == null || value.isEmpty ? null : value;
      if (_scope != scope || _override != next) {
        _scope = scope;
        _override = next;
        _notify();
      }
      final version = revision.value;
      return TmdbCredentialSnapshot(
        (next ?? buildToken).trim(),
        () => scope == ProfileRuntime.scope.value && version == revision.value,
        read.authorize,
      );
    });
  }

  static Future<({String? value, Future<void> Function() authorize})>
  _read() async {
    final scope = ProfileRuntime.scope.value;
    if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
      final registry = ProfileBootstrap.registry;
      final context = await ProfileAuthorizationContext.capture(registry);
      Future<void> validateProfile() async {
        final profile = await context.validate(registry);
        if (!profile.allows(ProfileFeature.trackersAndDiscovery)) {
          throw const ResourceAuthorizationException(
            'Profile cannot use TMDB discovery',
          );
        }
      }

      await validateProfile();
      final id = await registry.getBoundResourceId(context.profileId, slot);
      final service = ConnectionResourceService(
        registry: registry,
        cipher: DeviceKeyProvider.cipher,
      );
      final resource = id == null
          ? null
          : await service.authorize(
              context: context,
              resourceId: id,
              permission: ResourcePermission.use,
              feature: ProfileFeature.trackersAndDiscovery,
            );
      final secret = resource == null || resource.secretPending
          ? null
          : await service.resolveSecretForUse(
              context: context,
              resourceId: id!,
              feature: ProfileFeature.trackersAndDiscovery,
            );
      Future<void> authorize() async {
        await validateProfile();
        if (scope != ProfileRuntime.scope.value ||
            await registry.getBoundResourceId(context.profileId, slot) != id) {
          throw StateError('TMDB configuration changed');
        }
        if (resource != null) {
          final current = await service.authorize(
            context: context,
            resourceId: resource.id,
            permission: ResourcePermission.use,
            feature: ProfileFeature.trackersAndDiscovery,
          );
          if (current.authorizationRevision != resource.authorizationRevision) {
            throw StateError('TMDB configuration changed');
          }
        }
      }

      return (value: secret?['accessToken'] as String?, authorize: authorize);
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key);
    final value = await SecretVault.open(stored);
    return (
      value: value,
      authorize: () async {
        if (scope != ProfileRuntime.scope.value ||
            prefs.getString(key) != stored) {
          throw StateError('TMDB configuration changed');
        }
      },
    );
  }

  /// Empty input removes the override. Publish only after durable success.
  static Future<void> save(String input) async {
    final scope = ProfileRuntime.scope.value;
    final value = input.trim();
    if (value.length > 8192 || value.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Enter a valid TMDB API Read Access Token');
    }
    await initialize();
    await _writes.synchronized(() async {
      if (scope != ProfileRuntime.scope.value) {
        throw StateError('Profile changed while saving TMDB settings');
      }
      if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
        final registry = ProfileBootstrap.registry;
        final context = await ProfileAuthorizationContext.capture(registry);
        final service = ConnectionResourceService(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
        );
        final id = await registry.getBoundResourceId(context.profileId, slot);
        if (value.isEmpty) {
          if (id != null) {
            await service.disconnectBinding(
              context: context,
              slot: slot,
              resourceId: id,
            );
          }
        } else if (id == null) {
          await service.create(
            context: context,
            type: ConnectionResourceType.tmdb,
            label: 'TMDB',
            publicConfig: const {'accountLabel': 'TMDB'},
            secretConfig: {'accessToken': value},
            bindingSlot: slot,
          );
        } else {
          await service.updateSecret(
            context: context,
            resourceId: id,
            secretConfig: {'accessToken': value},
          );
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        final sealed = value.isEmpty ? null : await SecretVault.seal(value);
        if (scope != ProfileRuntime.scope.value) {
          throw StateError('Profile changed while saving TMDB settings');
        }
        try {
          final saved = sealed == null
              ? await prefs.remove(key)
              : await prefs.setString(key, sealed);
          if (!saved) throw StateError('Could not save TMDB settings');
        } catch (_) {
          // SharedPreferences may update its memory view even on failed writes.
          await prefs.reload();
          throw StateError('Could not save TMDB settings');
        }
      }
      if (scope != ProfileRuntime.scope.value) {
        throw StateError('Profile changed while saving TMDB settings');
      }
      await refresh();
    });
  }

  @visibleForTesting
  static void resetForTesting() {
    if (_listening) {
      ProfileRuntime.scope.removeListener(_scopeChanged);
      ProfileLockController.instance.lockedProfileId.removeListener(
        _scopeChanged,
      );
    }
    _listening = false;
    _loading = null;
    _override = null;
    _scope = null;
    _loadGeneration++;
    _writes = Lock();
    revision.value++;
  }
}
