import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _origin = '6d26d7a1a98c7ddd37b4a25815f74123c1e29126';
const _directory = 'test/fixtures/storage_origin_restore';
const _passphrase = 'SYNTHETIC fixture only - no account credentials';
const _generate = bool.fromEnvironment('STORAGE_ORIGIN_GENERATE');
const _mutation = String.fromEnvironment('STORAGE_FIXTURE_MUTATION');

// Independent reviewed values, not inferred from the candidate exporter.
// Existing setter pins remain; the recipe adds complete domains incrementally.
const _setterSettings = <String, Object>{
  'stremio_tv_rotation_minutes': 37,
  'stremio_tv_auto_refresh': false,
  'stremio_tv_debrid_provider': 'realdebrid',
  'stremio_tv_catalog_repo_urls_v1': <String>[
    'https://alpha.example.invalid/catalog.json',
    'https://beta.example.invalid/catalog.json',
  ],
  'reddit_recent_subreddits': <String>['synthetic_alpha', 'synthetic_beta'],
  'lemmy_favorite_communities': <String>['synthetic@example.invalid'],
  'youtube_max_height': 720,
  'debrify_tv_random_start_percent': 13,
  'debrify_tv_provider': 'real_debrid',
  'real_debrid_file_selection': 'all',
  'torbox_check_cache_before_search': true,
  'real_debrid_integration_enabled': false,
  'default_torrent_provider_v1': 'torbox',
  'post_torrent_action': 'delete',
  'player_default_aspect_index': 4,
  'ui_sounds': false,
  'player_default_subtitle_language': 'es',
  'network_buffer_size': 'huge',
  'iptv_decoder_mode': 'hardware',
  'iptv_track_continue_watching': false,
  'app_theme': 'spotlight',
  'theme_overrides': '{"synthetic":"fixture"}',
  'phone_nav_style': 'floating',
  'tv_ui_scale_percent': 80,
  'tracking_scrobble_targets': <String>['local', 'mdblist'],
  'watch_progress_source': 'simkl',
  'trakt_sync_catalog_items': true,
  'simkl_sync_catalog_items': false,
  'mdblist_sync_catalog_items': true,
};
final _recipe =
    jsonDecode(File('$_directory/recipe.json').readAsStringSync())
        as Map<String, dynamic>;
final _settings = Map<String, Object?>.from(_recipe['values'] as Map);
final _excludedInputs = Map<String, Object>.from(
  _recipe['excludedInputs'] as Map,
);

Future<void> _writeValues(Map<String, Object?> values) async {
  final prefs = await ProfilePreferences.instance();
  for (final entry in values.entries) {
    final value = entry.value;
    switch (value) {
      case bool():
        await prefs.setBool(entry.key, value);
      case int():
        await prefs.setInt(entry.key, value);
      case double():
        await prefs.setDouble(entry.key, value);
      case String():
        await prefs.setString(entry.key, value);
      case List():
        await prefs.setStringList(entry.key, value.cast<String>());
      default:
        throw StateError('Unsupported recipe value: ${entry.key}');
    }
  }
}

void _expectExclusions(Map<String, Object?> values) {
  for (final key in _excludedInputs.keys) {
    expect(values.containsKey(key), false, reason: 'Excluded by origin: $key');
  }
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Origin fixtures must never access the network');
}

String _type(Object? value) {
  if (value is bool) return 'bool';
  if (value is int) return 'int';
  if (value is double) return 'double';
  if (value is String) return 'String';
  if (value is List && value.every((item) => item is String)) {
    return 'List<String>';
  }
  throw StateError('Unexpected preference type: ${value.runtimeType}');
}

Future<String> _digest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void _expectSettings(Map<String, Object?> actual) {
  expect(
    actual,
    _settings,
    reason: 'Every represented key and value is preserved',
  );
  for (final entry in _settings.entries) {
    expect(_type(actual[entry.key]), _type(entry.value), reason: entry.key);
  }
}

Future<void> _seedThroughStorageService() async {
  await StorageService.setStremioTvRotationMinutes(37);
  await StorageService.setStremioTvAutoRefresh(false);
  await StorageService.setStremioTvDebridProvider('realdebrid');
  await StorageService.setStremioTvCatalogRepoUrls(
    _setterSettings['stremio_tv_catalog_repo_urls_v1']! as List<String>,
  );
  await StorageService.setRedditRecentSubreddits(
    _setterSettings['reddit_recent_subreddits']! as List<String>,
  );
  await StorageService.setLemmyFavoriteCommunities(
    _setterSettings['lemmy_favorite_communities']! as List<String>,
  );
  await StorageService.setYoutubeMaxHeight(720);
  await StorageService.saveDebrifyTvRandomStartPercent(13);
  await StorageService.saveDebrifyTvProvider('real_debrid');
  await StorageService.saveFileSelection('all');
  await StorageService.setTorboxCacheCheckEnabled(true);
  await StorageService.setRealDebridIntegrationEnabled(false);
  await StorageService.setDefaultTorrentProvider('torbox');
  await StorageService.savePostTorrentAction('delete');
  await StorageService.setPlayerDefaultAspectIndex(4);
  await StorageService.setUiSounds(false);
  await StorageService.setDefaultSubtitleLanguage('es');
  await StorageService.setNetworkBufferSize('huge');
  await StorageService.setIptvDecoderMode('hardware');
  await StorageService.setIptvTrackContinueWatching(false);
  await StorageService.setAppTheme('spotlight');
  await StorageService.setThemeOverrides('{"synthetic":"fixture"}');
  await StorageService.setPhoneNavStyle('floating');
  await StorageService.setTvUiScalePercent(80);
  await StorageService.setTrackingScrobbleTargets({
    TrackingSource.local,
    TrackingSource.mdblist,
  });
  await StorageService.setWatchProgressSource(WatchProgressSource.simkl);
  await StorageService.setTraktSyncCatalogItems(true);
  await StorageService.setSimklSyncCatalogItems(false);
  await StorageService.setMdblistSyncCatalogItems(true);
  // Additional domains share typed data and the actual profile preference API.
  // The independent recipe specifies physical encodings, not exporter output.
  await _writeValues({
    for (final e in _settings.entries)
      if (!_setterSettings.containsKey(e.key)) e.key: e.value,
  });
  await _writeValues(_excludedInputs);
  final seeded = await ProfilePreferences.instance();
  for (final entry in _excludedInputs.entries) {
    expect(
      seeded.get(entry.key),
      entry.value,
      reason: 'Exclusion input present',
    );
    expect(_type(seeded.get(entry.key)), _type(entry.value), reason: entry.key);
  }
  await StorageService.setCustomExternalPlayerCommand(
    'SYNTHETIC_DO_NOT_EXECUTE {url}',
  );
}

Future<Map<String, Object?>> _readThroughStorageService() async => {
  for (final key in _settings.keys)
    if (!_setterSettings.containsKey(key))
      key: (await ProfilePreferences.instance()).get(key),
  'stremio_tv_rotation_minutes':
      await StorageService.getStremioTvRotationMinutes(),
  'stremio_tv_auto_refresh': await StorageService.getStremioTvAutoRefresh(),
  'stremio_tv_debrid_provider':
      await StorageService.getStremioTvDebridProvider(),
  'stremio_tv_catalog_repo_urls_v1':
      await StorageService.getStremioTvCatalogRepoUrls(),
  'reddit_recent_subreddits': await StorageService.getRedditRecentSubreddits(),
  'lemmy_favorite_communities':
      await StorageService.getLemmyFavoriteCommunities(),
  'youtube_max_height': await StorageService.getYoutubeMaxHeight(),
  'debrify_tv_random_start_percent':
      await StorageService.getDebrifyTvRandomStartPercent(),
  'debrify_tv_provider': await StorageService.getDebrifyTvProvider(),
  'real_debrid_file_selection': await StorageService.getFileSelection(),
  'torbox_check_cache_before_search':
      await StorageService.getTorboxCacheCheckEnabled(),
  'real_debrid_integration_enabled':
      await StorageService.getRealDebridIntegrationEnabled(),
  'default_torrent_provider_v1':
      await StorageService.getDefaultTorrentProvider(),
  'post_torrent_action': await StorageService.getPostTorrentAction(),
  'player_default_aspect_index':
      await StorageService.getPlayerDefaultAspectIndex(),
  'ui_sounds': await StorageService.getUiSounds(),
  'player_default_subtitle_language':
      await StorageService.getDefaultSubtitleLanguage(),
  'network_buffer_size': await StorageService.getNetworkBufferSize(),
  'iptv_decoder_mode': await StorageService.getIptvDecoderMode(),
  'iptv_track_continue_watching':
      await StorageService.getIptvTrackContinueWatching(),
  'app_theme': await StorageService.getAppTheme(),
  'theme_overrides': await StorageService.getThemeOverrides(),
  'phone_nav_style': await StorageService.getPhoneNavStyle(),
  'tv_ui_scale_percent': await StorageService.getTvUiScalePercent(),
  'tracking_scrobble_targets':
      (await StorageService.getTrackingScrobbleTargets())
          .map((s) => s.name)
          .toList(),
  'watch_progress_source': (await StorageService.getWatchProgressSource()).name,
  'trakt_sync_catalog_items': await StorageService.getTraktSyncCatalogItems(),
  'simkl_sync_catalog_items': await StorageService.getSimklSyncCatalogItems(),
  'mdblist_sync_catalog_items':
      await StorageService.getMdblistSyncCatalogItems(),
};

Map<String, Object?> _values(PortableProfilePackage package) =>
    Map<String, Object?>.from(
      (package.sections[package.profiles.single['preferencesSection']]
              as Map)['values']
          as Map,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String profileId;
  late String otherProfileId;
  late HttpOverrides? previousHttp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    SecretVault.debugReset(deviceIdOverride: 'synthetic-origin-restore');
    StorageService.resetProfileCaches();
    temp = await Directory.systemTemp.createTemp('storage-origin-restore-');
    final documents = await Directory(p.join(temp.path, 'documents')).create();
    final support = await Directory(p.join(temp.path, 'support')).create();
    final cache = await Directory(p.join(temp.path, 'cache')).create();
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    profileId = (await registry.createProfile(
      name: 'Synthetic fixture admin',
      role: UserProfileRole.admin,
    )).id;
    otherProfileId = (await registry.createProfile(
      name: 'Synthetic untouched member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: profileId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (i) => _generate ? i : 255 - i),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 1),
    );
  });
  tearDown(() async {
    await DebrifyTvDatabase.instance.closeScope();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    StorageService.resetProfileCaches();
    SecretVault.debugReset();
    await registry.close();
    AppStorage.debugReset();
    HttpOverrides.global = previousHttp;
    // This path is allocated by this test, never an installed user profile.
    await temp.delete(recursive: true);
  });

  Future<PortableProfilePackage> export({bool includeSecrets = false}) async =>
      ProfilePackageService(
        registry: registry,
        resources: ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ),
      ).exportProfile(
        context: await ProfileAuthorizationContext.capture(registry),
        scope: ProfileRuntime.capture(),
        includeSecrets: includeSecrets,
        sanitized: false,
      );

  if (_generate) {
    test('generate only through the unchanged pre-S2 lib exporter', () async {
      final head = await Process.run('git', ['rev-parse', 'HEAD']);
      expect(head.exitCode, 0);
      expect(head.stdout.toString().trim(), _origin);
      final diff = await Process.run('git', [
        'diff',
        '--exit-code',
        _origin,
        '--',
        'lib',
      ]);
      expect(
        diff.exitCode,
        0,
        reason: 'Never generate from modified production',
      );
      final config = File('.dart_tool/package_config.json');
      final metadata = jsonDecode(await config.readAsString()) as Map;
      final app = (metadata['packages'] as List).cast<Map>().singleWhere(
        (entry) => entry['name'] == 'debrify',
      );
      final library = config.absolute.uri
          .resolve(app['rootUri'] as String)
          .resolve(app['packageUri'] as String)
          .resolve('services/storage_service.dart');
      expect(
        p.equals(
          library.toFilePath(),
          p.join(
            Directory.current.path,
            'lib',
            'services',
            'storage_service.dart',
          ),
        ),
        isTrue,
      );
      await _seedThroughStorageService();
      _expectSettings(await _readThroughStorageService());
      final package = await export();
      _expectSettings(_values(package));
      _expectExclusions(_values(package));
      expect(package.resources, isEmpty);
      final bytes = await PortableProfilePackage.encodeEncryptedBytes(
        package,
        _passphrase,
      );
      final directory = await Directory(_directory).create(recursive: true);
      await File(
        p.join(directory.path, 'profile.encrypted.json'),
      ).writeAsBytes(bytes);
      await File(p.join(directory.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'origin': _origin,
          'recipeVersion': 2,
          'syntheticOnly': true,
          'sha256': await _digest(bytes),
          'representedSettings': _settings,
          'keyTypes': _settings.map(
            (key, value) => MapEntry(key, _type(value)),
          ),
          'excludedKeys': _excludedInputs.keys.toList(),
          'omissions': package.omissions,
        }),
      );
    });
    return;
  }

  test(
    'current public setters export all represented origin settings and types',
    () async {
      await _seedThroughStorageService();
      _expectSettings(await _readThroughStorageService());
      final package = await export();
      _expectSettings(_values(package));
      _expectExclusions(_values(package));
      _expectSettings(_values(await export(includeSecrets: true)));
      _expectExclusions(_values(await export(includeSecrets: true)));
    },
  );

  test(
    'restore frozen pre-S2 export through real APIs without key or type drift',
    () async {
      expect([
        '',
        'key',
        'type',
        'tracking-key',
        'tracking-type',
      ], contains(_mutation));
      final manifest =
          jsonDecode(await File('$_directory/manifest.json').readAsString())
              as Map<String, dynamic>;
      expect(manifest['origin'], _origin);
      expect(manifest['syntheticOnly'], true);
      _expectSettings(
        Map<String, Object?>.from(manifest['representedSettings'] as Map),
      );
      expect(
        manifest['keyTypes'],
        _settings.map((key, value) => MapEntry(key, _type(value))),
      );
      final bytes = await File(
        '$_directory/profile.encrypted.json',
      ).readAsBytes();
      expect(await _digest(bytes), manifest['sha256']);
      var package = await PortableProfilePackage.decrypt(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        _passphrase,
      );
      _expectSettings(_values(package));
      _expectExclusions(_values(package));
      expect(manifest['excludedKeys'], unorderedEquals(_excludedInputs.keys));
      expect(package.omissions, manifest['omissions']);
      expect(package.resources, isEmpty);
      if (_mutation.isNotEmpty) {
        // Mutate a valid incoming package, then use the real section hashing and
        // codec. This probes semantic checks after restore, not hash rejection.
        final values = _values(package);
        if (_mutation == 'tracking-key') {
          values['mdblist_saved_clones_renamed'] = values.remove(
            'mdblist_saved_clones',
          );
        } else if (_mutation == 'tracking-type') {
          values['tracking_progress_fallback_notice'] = 'true';
        } else if (_mutation == 'key') {
          values['stremio_tv_rotation_minutes_renamed'] = values.remove(
            'stremio_tv_rotation_minutes',
          );
        } else {
          // Numerically equal on purpose: only an exact physical-type check
          // distinguishes this double from the required integer.
          values['stremio_tv_rotation_minutes'] = 37.0;
        }
        final mutated = PortableProfilePackage(
          mode: package.mode,
          createdAt: package.createdAt,
          profiles: package.profiles,
          resources: package.resources,
          sections: {
            ...package.sections,
            package.profiles.single['preferencesSection'] as String:
                await PortableProfilePackage.buildSection(values),
          },
          omissions: package.omissions,
        );
        package = await PortableProfilePackage.decrypt(
          await PortableProfilePackage.encrypt(mutated, _passphrase),
          _passphrase,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final other = otherProfileId;
      await prefs.setInt('p.$profileId.g.1.stremio_tv_rotation_minutes', 91);
      await prefs.setInt('p.$other.g.1.stremio_tv_rotation_minutes', 92);
      await prefs.setString('p.$other.g.1.fixture_sentinel', 'untouched');
      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restore(
            package: package,
            destinationProfileId: profileId,
            authorization: await ProfileAuthorizationContext.capture(registry),
          );
      expect(report.publishedGeneration, 2);
      expect(ProfileRuntime.capture().dataGeneration, 2);
      final prefix = ProfileRuntime.capture().preferencePrefix;
      // Inspect physical types before getters can default/coerce/cache them.
      _expectSettings({
        for (final key in _settings.keys) key: prefs.get('$prefix$key'),
      });
      for (final key in _excludedInputs.keys) {
        expect(prefs.containsKey('$prefix$key'), false, reason: key);
      }
      expect(prefs.getInt('p.$profileId.g.1.stremio_tv_rotation_minutes'), 91);
      expect(prefs.getInt('p.$other.g.1.stremio_tv_rotation_minutes'), 92);
      expect(prefs.getString('p.$other.g.1.fixture_sentinel'), 'untouched');
      StorageService.resetProfileCaches();
      _expectSettings(await _readThroughStorageService());
      _expectSettings(_values(await export()));
      expect(await StorageService.getMdblistSavedClones(), {
        101: 201,
        102: 202,
      });
      expect(
        await StorageService.getMdblistSyncCheckpoint(),
        jsonDecode(_settings['mdblist_sync_checkpoint_v1']! as String),
      );
      expect(await StorageService.takeTrackingProgressFallbackNotice(), true);
      expect(await StorageService.takeTrackingProgressFallbackNotice(), false);
    },
  );
}
