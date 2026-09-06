import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
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

import 'default_torrent_filter_prefs_origin_test.dart'
    show filterDefaultCases, seedFilterDefaults, expectFilterDefaultReaders;

import 'playlist_progress_map_origin_test.dart'
    show seedPlaylistProgress, expectPlaylistProgressBuilder, playlistProgressKey;

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
final _settings = <String, Object?>{
  ...Map<String, Object?>.from(_recipe['values'] as Map),
  ...Map<String, Object?>.from(_recipe['familyValues'] as Map),
};
final _credentialEngineValues = Map<String, Object?>.from(
  _recipe['credentialEngineValues'] as Map,
);
final _excludedInputs = <String, Object>{
  ...Map<String, Object>.from(_recipe['excludedInputs'] as Map),
  ...Map<String, Object>.from(_recipe['familyExcludedInputs'] as Map),
};

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

void _expectExclusions(
  Map<String, Object?> values, {
  bool includeSecrets = false,
}) {
  for (final key in [
    ..._excludedInputs.keys,
    if (!includeSecrets) ..._credentialEngineValues.keys,
  ]) {
    expect(values.containsKey(key), false, reason: 'Excluded by origin: $key');
  }
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Origin fixtures must never access the network');
}

String _type(Object? value) {
  if (value == null) return 'null';
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

void _expectSettings(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  expect(
    actual,
    expected,
    reason: 'Every represented key and value is preserved',
  );
  for (final entry in expected.entries) {
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
  await ProviderCredentialPrefs.saveFileSelection('all');
  await ProviderCredentialPrefs.setTorboxCacheCheckEnabled(true);
  await ProviderCredentialPrefs.setRealDebridIntegrationEnabled(false);
  await ProviderCredentialPrefs.setDefaultTorrentProvider('torbox');
  await ProviderCredentialPrefs.savePostTorrentAction('delete');
  await StorageService.setPlayerDefaultAspectIndex(4);
  await StorageService.setUiSounds(false);
  await StorageService.setDefaultSubtitleLanguage('es');
  await StorageService.setNetworkBufferSize('huge');
  await IptvPrefs.setIptvDecoderMode('hardware');
  await IptvPrefs.setIptvTrackContinueWatching(false);
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
      if (!_setterSettings.containsKey(e.key))
        e.key: (_recipe['inputOverrides'] as Map)[e.key] ?? e.value,
  });
  await _writeValues(_credentialEngineValues);
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

Future<Map<String, Object?>> _readThroughStorageService(
  Map<String, Object?> expected,
) async => {
  for (final key in expected.keys)
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
  'real_debrid_file_selection': await ProviderCredentialPrefs.getFileSelection(),
  'torbox_check_cache_before_search':
      await ProviderCredentialPrefs.getTorboxCacheCheckEnabled(),
  'real_debrid_integration_enabled':
      await ProviderCredentialPrefs.getRealDebridIntegrationEnabled(),
  'default_torrent_provider_v1':
      await ProviderCredentialPrefs.getDefaultTorrentProvider(),
  'post_torrent_action': await ProviderCredentialPrefs.getPostTorrentAction(),
  'player_default_aspect_index':
      await StorageService.getPlayerDefaultAspectIndex(),
  'ui_sounds': await StorageService.getUiSounds(),
  'player_default_subtitle_language':
      await StorageService.getDefaultSubtitleLanguage(),
  'network_buffer_size': await StorageService.getNetworkBufferSize(),
  'iptv_decoder_mode': await StorageService.getIptvDecoderMode(),
  'iptv_track_continue_watching':
      await IptvPrefs.getIptvTrackContinueWatching(),
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
    expect(_recipe['origin'], _origin);
    final named = (_recipe['values'] as Map).keys.toSet();
    final excluded = (_recipe['excludedInputs'] as Map).keys.toSet();
    expect(named.length, 141);
    expect(excluded.length, 28);
    expect(named.intersection(excluded), isEmpty);
    final declared = (_recipe['completeDomains'] as Map).values
        .expand((keys) => keys as List)
        .toList();
    expect(declared, unorderedEquals({...named, ...excluded}));
    expect(_recipe['partialDomains'], isEmpty);
    final families = _recipe['families'] as Map;
    expect(families.length, 5);
    final sampled = <Object?>[];
    for (final entry in families.entries) {
      expect(entry.value['finiteSampleOnly'], true);
      final keys = [
        ...entry.value['ordinaryKeys'] as List,
        ...entry.value['credentialShapedKeys'] as List,
      ];
      expect(
        keys.every((key) => (key as String).startsWith(entry.key as String)),
        true,
      );
      sampled.addAll(keys);
    }
    expect(
      sampled,
      unorderedEquals({
        ...(_recipe['familyValues'] as Map).keys,
        ...(_recipe['familyExcludedInputs'] as Map).keys,
        ..._credentialEngineValues.keys,
      }),
    );
    expect(sampled.length, 21);
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

  final residual = _recipe['residualDomains']['filter-defaults'] as Map;
  setUpAll(() {
    expect(residual['namedKeyCount'], 5);
    expect(residual['origin'], _origin);
    expect(residual['physicalType'], 'String');
    expect(residual['excludedKeys'], isEmpty);
    expect(
      (residual['values'] as Map).values.every((v) => v is String),
      isTrue,
    );
    expect(
      (residual['values'] as Map).keys,
      unorderedEquals(filterDefaultCases.map((e) => e.key)),
    );
    expect(
      (residual['values'] as Map).keys.toSet().intersection(
        _settings.keys.toSet(),
      ),
      isEmpty,
    );
  });
  setUpAll(() {
    final playlist = _recipe['residualDomains']['playlist-progress'] as Map;
    expect(playlist['origin'], _origin);
    expect(playlist['namedKeyCount'], 1);
    expect(playlist['physicalType'], 'String');
    expect((playlist['values'] as Map).keys, [playlistProgressKey]);
    expect(playlist['excludedKeys'], isEmpty);
    expect(_settings.containsKey(playlistProgressKey), isFalse);
  });
  final scenarios = {
    ..._recipe['scenarios'] as Map,
    'filter-defaults': {'absentKeys': <String>[]},
    'playlist-progress': {'absentKeys': <String>[]},
    'playlist-metadata': {'absentKeys': <String>[]},
    'my-watchlist': {'absentKeys': <String>[]},
    'quick-play-policy': {'absentKeys': <String>[]},
    'quick-play-policy-legacy': {'absentKeys': ['quick_play_movie_rules_v2', 'quick_play_series_rules_v2']},
    'repair': {'absentKeys': ['playback_completion_migration_generation', 'resume_ghost_purge_generation']},
    'repair-markers-zero': {'absentKeys': <String>[]},
    'repair-markers-one': {'absentKeys': <String>[]},
  };
  for (final entry in scenarios.entries) {
    final scenario = entry.key as String;
    final isFilter = scenario == 'filter-defaults';
    final isPlaylist = scenario == 'playlist-progress';
    final isRepair = scenario == 'repair' || scenario.startsWith('repair-markers-');
    final isMetadata = scenario == 'playlist-metadata';
    final isWatchlist = scenario == 'my-watchlist';
    final isQuickPolicy = scenario == 'quick-play-policy' || scenario == 'quick-play-policy-legacy';
    final isResidual = isQuickPolicy || isFilter || isPlaylist || isRepair || isMetadata || isWatchlist;
    final domain = isQuickPolicy
        ? _recipe['residualDomains']['quick-play-policy'] as Map
        : isWatchlist
        ? _recipe['residualDomains']['my-watchlist'] as Map
        : isMetadata
        ? _recipe['residualDomains']['playlist-metadata'] as Map
        : isRepair
        ? _recipe['residualDomains']['repair'] as Map
        : isPlaylist
        ? _recipe['residualDomains']['playlist-progress'] as Map
        : residual;
    final scenarioSettings = isResidual
        ? Map<String, Object?>.from(domain['values'] as Map)
        : _settings;
    if (scenario == 'repair-markers-one') {
      for (final key in (domain['markerKeys'] as List).cast<String>()) {
        scenarioSettings[key] = 1;
      }
    }
    final credentialValues = isResidual
        ? <String, Object?>{}
        : _credentialEngineValues;
    final excludedKeys = isResidual ? <String>[] : _excludedInputs.keys.toList();
    void expectExclusions(
      Map<String, Object?> values, {
      bool includeSecrets = false,
    }) {
      if (!isResidual) _expectExclusions(values, includeSecrets: includeSecrets);
    }

    Future<Map<String, Object?>> readScenario(
      Map<String, Object?> values,
    ) async {
      if (!isResidual) return _readThroughStorageService(values);
      final prefs = await ProfilePreferences.instance();
      return {for (final key in values.keys) key: prefs.get(key)};
    }

    final includeSecrets = entry.value['includeSecrets'] == true;
    final absent = (entry.value['absentKeys'] as List).cast<String>();
    final omitted = (entry.value['omitKeys'] as List? ?? []).cast<String>();
    final inputOverrides = Map<String, Object?>.from(
      entry.value['inputOverrides'] as Map? ?? {},
    );
    final inputExpected = <String, Object?>{
      ...scenarioSettings,
      ...credentialValues,
      if (!isResidual)
        ...Map<String, Object?>.from(_recipe['inputOverrides'] as Map),
      ...inputOverrides,
      if (isPlaylist || isRepair) ...Map<String, Object?>.from(domain['inputValues'] as Map),
    }..removeWhere((key, value) => absent.contains(key));
    final missing = [...absent, ...omitted];
    final expected = <String, Object?>{
      for (final entry in scenarioSettings.entries)
        if (!missing.contains(entry.key)) entry.key: entry.value,
      if (includeSecrets) ...credentialValues,
    };
    final manifestName = scenario == 'profile'
        ? 'manifest.json'
        : '$scenario.manifest.json';

    Future<void> seedScenario() async {
      if (isQuickPolicy) {
        expect(domain['origin'], _origin);
        expect(domain['namedKeyCount'], 7);
        expect(domain['excludedKeys'], isEmpty);
        expect(scenarioSettings.keys, unorderedEquals([
          'quick_play_honors_filters_v1', 'quick_play_try_multiple_torrents',
          'quick_play_max_retries', 'play_button_mode', 'auto_bind_series_packs_on_play',
          'quick_play_movie_rules_v2', 'quick_play_series_rules_v2',
        ]));
        expect(scenarioSettings.keys.toSet().intersection(_settings.keys.toSet()), isEmpty);
        await _writeValues(inputExpected);
        return;
      }
      if (isWatchlist) {
        expect(domain['origin'], _origin);
        expect(domain['namedKeyCount'], 1);
        expect(domain['physicalType'], 'String');
        expect(domain['excludedKeys'], isEmpty);
        expect(scenarioSettings.keys, ['my_watchlist_v1']);
        await _writeValues(inputExpected);
        return;
      }
      if (isMetadata) {
        expect(domain['origin'], _origin);
        expect(domain['namedKeyCount'], 2);
        expect(domain['physicalType'], 'String');
        expect(domain['excludedKeys'], isEmpty);
        expect(scenarioSettings.keys, unorderedEquals([
          'tvmaze_series_mappings', 'playlist_poster_overrides_v1',
        ]));
        // Synthetic fixed timestamps/raw JSON, exported by the actual origin.
        await _writeValues(inputExpected);
        return;
      }
      if (isRepair) {
        await _writeValues(inputExpected);
        final prefs = await ProfilePreferences.instance();
        for (final key in absent) {
          expect(prefs.containsKey(key), isFalse, reason: 'Origin absence: $key');
        }
        return;
      }
      if (isPlaylist) {
        await seedPlaylistProgress();
        return;
      }
      if (isFilter) {
        await seedFilterDefaults(scenarioSettings);
        return;
      }
      await _seedThroughStorageService();
      await _writeValues(inputOverrides);
      if (scenario == 'provider-null-folder') {
        await ProviderCredentialPrefs.setPikPakRestrictedFolder(null, null);
        await ProviderCredentialPrefs.setSelectedWebDavServerId(null);
      } else if (scenario == 'provider-cleared-cache') {
        await ProviderCredentialPrefs.clearPikPakRestrictedFolder();
        await ProviderCredentialPrefs.setSelectedWebDavServerId('');
      }
      final prefs = await ProfilePreferences.instance();
      for (final key in absent) {
        expect(
          prefs.containsKey(key),
          false,
          reason: 'Origin input absence: $key',
        );
      }
    }

    Future<void> expectProviderReaders([Map<String, Object?>? restored]) async {
      final readerExpected = restored ?? expected;
      if (isQuickPolicy) {
        final prefs = await ProfilePreferences.instance();
        final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        final reads = domain[scenario == 'quick-play-policy-legacy'
            ? 'legacyExpectedReads' : 'expectedReads'] as Map;
        expect((await StorageService.getQuickPlayRules(isMovie: true)).toJson(), reads['movie']);
        expect((await StorageService.getQuickPlayRules(isMovie: false)).toJson(), reads['series']);
        expect(await StorageService.getQuickPlayHonorsFilters(), false);
        expect(await StorageService.getQuickPlayTryMultipleTorrents(), false);
        expect(await StorageService.getQuickPlayMaxRetries(), 3);
        expect(await StorageService.getPlayButtonMode(), 'smart');
        expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before,
            reason: 'Public reads must not persist migrated/normalized rules');
        return;
      }
      if (isWatchlist) {
        final prefs = await ProfilePreferences.instance();
        final before = prefs.get('my_watchlist_v1');
        expect(before, isA<String>());
        expect(before, expected['my_watchlist_v1']);
        final items = await StorageService.getMyWatchlistItems();
        expect([
          for (final item in items) {
            'id': item.id, 'imdbId': item.imdbId, 'type': item.type,
            'name': item.name, 'poster': item.poster,
            'background': item.background, 'year': item.year,
            'sourceId': item.sourceAddon?.id, 'sourceName': item.sourceAddon?.name,
            'key': StorageService.myWatchlistItemKey(item),
          },
        ], domain['expectedReads']);
        for (final item in items) {
          expect(await StorageService.isInMyWatchlist(item), isTrue);
        }
        // Reading canonical identities must not persist over legacy row keys.
        expect(prefs.get('my_watchlist_v1'), before);
        final raw = await SharedPreferences.getInstance();
        expect(raw.get('${ProfileRuntime.capture().preferencePrefix}my_watchlist_v1'), before);
        return;
      }
      if (isMetadata) {
        for (final lookup in domain['lookups'] as List) {
          final item = Map<String, dynamic>.from(lookup['item'] as Map);
          expect(PlaybackProgressStore.getPlaylistItemUniqueKey(item), lookup['key']);
          expect(await PlaybackProgressStore.getTVMazeSeriesMapping(item), lookup['mapping']);
          expect(await PlaybackProgressStore.getPlaylistPosterOverride(item), lookup['poster']);
        }
        final batch = await PlaybackProgressStore.getAllPlaylistPosterOverrides();
        expect(batch, domain['expectedBatch']);
        expect(batch.keys.toList(), (domain['expectedBatch'] as Map).keys.toList());
        expect(await PlaybackProgressStore.getTVMazeSeriesMapping({'title': 'missing'}), isNull);
        expect(await PlaybackProgressStore.getPlaylistPosterOverride({'title': 'missing'}), isNull);
        return;
      }
      if (isRepair) {
        expect(await PlaybackProgressStore.getMovieCompletionThreshold(), 90);
        expect(await PlaybackProgressStore.getEpisodeCompletionThreshold(), 75);
        return;
      }
      if (isPlaylist) {
        await expectPlaylistProgressBuilder();
        return;
      }
      if (isFilter) {
        await expectFilterDefaultReaders(readerExpected);
        return;
      }
      expect(
        await ProviderCredentialPrefs.getPikPakRestrictedFolderId(),
        readerExpected['pikpak_restricted_folder_id'],
      );
      expect(
        await ProviderCredentialPrefs.getPikPakRestrictedFolderName(),
        readerExpected['pikpak_restricted_folder_name'],
      );
      expect(
        await ProviderCredentialPrefs.getPikPakTorrentsFolderId(),
        readerExpected['pikpak_torrents_folder_id'],
      );
      expect(
        await ProviderCredentialPrefs.getPikPakTvFolderId(),
        readerExpected['pikpak_tv_folder_id'],
      );
      expect(
        await ProviderCredentialPrefs.getSelectedWebDavServerId(),
        readerExpected['webdav_selected_server_id_v1'],
      );
    }

    if (_generate) {
      test(
        '$scenario: generate only through the unchanged pre-S2 lib exporter',
        () async {
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
          await seedScenario();
          await expectProviderReaders();
          _expectSettings(await readScenario(inputExpected), inputExpected);
          final package = await export(includeSecrets: includeSecrets);
          _expectSettings(_values(package), expected);
          expectExclusions(_values(package), includeSecrets: includeSecrets);
          expect(package.resources, isEmpty);
          final bytes = await PortableProfilePackage.encodeEncryptedBytes(
            package,
            _passphrase,
          );
          final directory = await Directory(_directory).create(recursive: true);
          await File(
            p.join(directory.path, '$scenario.encrypted.json'),
          ).writeAsBytes(bytes);
          await File(p.join(directory.path, manifestName)).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'origin': _origin,
              'recipeVersion': 5,
              'includeSecrets': includeSecrets,
              'scenario': scenario,
              'absentKeys': absent,
              'omittedKeys': omitted,
              'syntheticOnly': true,
              'sha256': await _digest(bytes),
              'representedSettings': expected,
              'keyTypes': expected.map(
                (key, value) => MapEntry(key, _type(value)),
              ),
              'excludedKeys': excludedKeys,
              'omissions': package.omissions,
            }),
          );
        },
      );
      continue;
    }

    test(
      '$scenario: current storage and profile APIs export all represented keys and types',
      () async {
        await seedScenario();
        await expectProviderReaders();
        _expectSettings(await readScenario(inputExpected), inputExpected);
        final package = await export(includeSecrets: includeSecrets);
        _expectSettings(_values(package), expected);
        expectExclusions(_values(package), includeSecrets: includeSecrets);
        _expectSettings(_values(await export(includeSecrets: true)), {
          ...expected,
          ...credentialValues,
        });
        expectExclusions(
          _values(await export(includeSecrets: true)),
          includeSecrets: true,
        );
      },
    );

    for (final repairFailure in ['none', if (scenario == 'repair') ...['marker-type', 'episode-type']]) {
    for (final keepDestination in [false, if (missing.isNotEmpty && !isRepair && !isQuickPolicy) true]) {
      final destinationValues = <String, Object?>{
        if (isPlaylist) 'playlist_restore_sentinel': 'untouched',
        if (isRepair) 'repair_restore_sentinel': 'untouched',
        if (isMetadata) 'metadata_restore_sentinel': 'untouched',
        if (isWatchlist) 'watchlist_restore_sentinel': 'untouched',
        if (isQuickPolicy) ...{
          'quick_policy_restore_sentinel': 'untouched',
          'series_auto_pin_on_play': false,
          'quick_play_vr_mode': 'auto',
          'quick_play_search_timeout': 42,
        },
        if (isFilter) ...{
          'quick_play_honors_filters_v1': false,
          'quick_play_movie_rules_v2': '{"fixture":"movie"}',
          'quick_play_series_rules_v2': '{"fixture":"series"}',
          'filter_restore_sentinel': 'untouched',
        },
        if (keepDestination)
          for (final key in missing) key: 'SYNTHETIC_DESTINATION_$key',
      };
      final restoredExpected = {
        ...expected, ...destinationValues,
        // Real restore rearms imported playback when the old package has no marker.
        if (isPlaylist || scenario == 'repair') 'resume_ghost_purge_generation': 0,
        if (isRepair && repairFailure != 'none')
          ...Map<String, Object?>.from(domain['negativeInputs'][repairFailure] as Map),
      };
      test(
        '$scenario: restore frozen pre-S2 export through real APIs without key or type drift (retain destination: $keepDestination)${repairFailure == 'none' ? '' : ' repair failure: $repairFailure'}',
        () async {
          final mutations = isFilter
              ? <String, Object>{
                  'filter-key': {
                    'key': 'default_filter_qualities_v1',
                    'operation': 'rename',
                  },
                  'filter-type': {
                    'key': 'default_filter_qualities_v1',
                    'operation': 'replace',
                    'value': ['fullHd', 'unknown quality', 'fullHd'],
                  },
                }
              : isPlaylist || isRepair || isMetadata || isWatchlist || isQuickPolicy
                  ? domain['mutations'] as Map
                  : _recipe['mutations'] as Map;
          expect(['', ...mutations.keys], contains(_mutation));
          final manifest =
              jsonDecode(await File('$_directory/$manifestName').readAsString())
                  as Map<String, dynamic>;
          expect(manifest['origin'], _origin);
          expect(manifest['syntheticOnly'], true);
          expect(manifest['scenario'], scenario);
          expect(manifest['absentKeys'], absent);
          _expectSettings(
            Map<String, Object?>.from(manifest['representedSettings'] as Map),
            expected,
          );
          expect(
            manifest['keyTypes'],
            expected.map((key, value) => MapEntry(key, _type(value))),
          );
          final bytes = await File(
            '$_directory/$scenario.encrypted.json',
          ).readAsBytes();
          expect(await _digest(bytes), manifest['sha256']);
          var package = await PortableProfilePackage.decrypt(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
            _passphrase,
          );
          _expectSettings(_values(package), expected);
          expectExclusions(_values(package), includeSecrets: includeSecrets);
          expect(manifest['excludedKeys'], unorderedEquals(excludedKeys));
          expect(package.omissions, manifest['omissions']);
          expect(manifest['omittedKeys'], omitted);
          expect(manifest['includeSecrets'], includeSecrets);
          expect(package.resources, isEmpty);
          if (_mutation.isNotEmpty) {
            // Mutate a valid incoming package, then use the real section hashing and
            // codec. This probes semantic checks after restore, not hash rejection.
            final values = _values(package);
            final mutation = mutations[_mutation] as Map;
            final key = mutation['key'] as String;
            expect(values.containsKey(key), mutation['operation'] != 'insert');
            if (mutation['operation'] == 'rename') {
              values['${key}_renamed'] = values.remove(key);
            } else if (mutation['operation'] == 'remove') {
              values.remove(key);
            } else {
              values[key] = mutation['value'];
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
          if (isRepair && repairFailure != 'none') {
            // Separate incoming negative package, derived from the real origin
            // export through actual section hashing/encryption. Never mix its
            // expected exception into the normal three-package success paths.
            final invalid = PortableProfilePackage(
              mode: package.mode, createdAt: package.createdAt,
              profiles: package.profiles, resources: package.resources,
              sections: {
                ...package.sections,
                package.profiles.single['preferencesSection'] as String:
                    await PortableProfilePackage.buildSection({
                      ..._values(package),
                      ...Map<String, Object?>.from(domain['negativeInputs'][repairFailure] as Map),
                    }),
              }, omissions: package.omissions,
            );
            package = await PortableProfilePackage.decrypt(
              await PortableProfilePackage.encrypt(invalid, _passphrase), _passphrase);
          }
          final prefs = await SharedPreferences.getInstance();
          final other = otherProfileId;
          if (!isResidual) {
            await prefs.setInt(
              'p.$profileId.g.1.stremio_tv_rotation_minutes',
              91,
            );
          } else {
            for (final key in expected.keys) {
              await prefs.setString(
                'p.$profileId.g.1.$key',
                '["old generation"]',
              );
              await prefs.setString('p.$other.g.1.$key', '["other profile"]');
            }
          }
          if (isPlaylist) {
            await prefs.setInt('p.$profileId.g.1.resume_ghost_purge_generation', 1);
            await prefs.setInt('p.$other.g.1.resume_ghost_purge_generation', 1);
          }
          await prefs.setInt('p.$other.g.1.stremio_tv_rotation_minutes', 92);
          await prefs.setString('p.$other.g.1.fixture_sentinel', 'untouched');
          for (final entry in expected.entries.where((e) => e.value == null)) {
            await prefs.setString(
              'p.$profileId.g.1.${entry.key}',
              'SYNTHETIC_STALE_EXECUTION',
            );
          }
          for (final entry in destinationValues.entries) {
            final key = 'p.$profileId.g.1.${entry.key}';
            if (entry.value is bool) {
              await prefs.setBool(key, entry.value! as bool);
            } else if (isQuickPolicy && entry.value is int) {
              await prefs.setInt(key, entry.value! as int);
            } else {
              await prefs.setString(key, entry.value! as String);
            }
          }
          final report =
              await ProfileRestoreCoordinator(
                registry: registry,
                cipher: cipher,
              ).restore(
                package: package,
                destinationProfileId: profileId,
                authorization: await ProfileAuthorizationContext.capture(
                  registry,
                ),
              );
          expect(report.publishedGeneration, 2);
          expect(ProfileRuntime.capture().dataGeneration, 2);
          final prefix = ProfileRuntime.capture().preferencePrefix;
          // Inspect physical types before getters can default/coerce/cache them.
          _expectSettings({
            for (final key in restoredExpected.keys)
              key: prefs.get('$prefix$key'),
          }, restoredExpected);
          for (final key in missing.where((key) => !keepDestination &&
              !(isRepair && key == 'resume_ghost_purge_generation'))) {
            expect(prefs.containsKey('$prefix$key'), false, reason: key);
          }
          for (final entry in expected.entries.where((e) => e.value == null)) {
            expect(
              prefs.containsKey('$prefix${entry.key}'),
              false,
              reason: 'Explicit null clears ${entry.key}',
            );
            expect(
              prefs.getString('p.$profileId.g.1.${entry.key}'),
              'SYNTHETIC_STALE_EXECUTION',
            );
          }
          await expectProviderReaders(restoredExpected);
          for (final key in [
            ...excludedKeys,
            if (!includeSecrets) ...credentialValues.keys,
          ]) {
            expect(prefs.containsKey('$prefix$key'), false, reason: key);
          }
          if (!isResidual) {
            expect(
              prefs.getInt('p.$profileId.g.1.stremio_tv_rotation_minutes'),
              91,
            );
          } else {
            for (final key in expected.keys) {
              expect(
                prefs.getString('p.$profileId.g.1.$key'),
                '["old generation"]',
              );
              expect(prefs.getString('p.$other.g.1.$key'), '["other profile"]');
            }
          }
          if (isPlaylist) {
            expect(prefs.getInt('p.$profileId.g.1.resume_ghost_purge_generation'), 1);
            expect(prefs.getInt('p.$other.g.1.resume_ghost_purge_generation'), 1);
          }
          expect(prefs.getInt('p.$other.g.1.stremio_tv_rotation_minutes'), 92);
          expect(prefs.getString('p.$other.g.1.fixture_sentinel'), 'untouched');
          StorageService.resetProfileCaches();
          _expectSettings(
            await readScenario(restoredExpected),
            restoredExpected,
          );
          _expectSettings(
            _values(await export(includeSecrets: includeSecrets)),
            {
              for (final e in restoredExpected.entries)
                if (e.value != null) e.key: e.value,
            },
          );
          for (final entry in destinationValues.entries) {
            expect(prefs.get('p.$profileId.g.1.${entry.key}'), entry.value);
          }
          if (isRepair && repairFailure != 'none') {
            var revisionCount = 0;
            void onInvalidRevision() => revisionCount++;
            StorageService.localCompletionRevision.addListener(onInvalidRevision);
            try {
              await expectLater(repairFailure == 'marker-type'
                  ? PlaybackProgressStore.purgeUnwatchedResumeGhosts()
                  : PlaybackProgressStore.migrateExistingPlaybackCompletionThresholds(),
                  throwsA(isA<TypeError>()));
              expect(revisionCount, 0);
              _expectSettings(_values(await export()), restoredExpected);
            } finally {
              StorageService.localCompletionRevision.removeListener(onInvalidRevision);
            }
            return;
          }
          if (isRepair) {
            // SQLite is populated only AFTER real restore and sanitize-stage
            // checks. These resume rows are not exported profile settings.
            final beforeSqlite = _values(await export());
            for (final key in (domain['sqliteResumeKeys'] as List).cast<String>()) {
              await StorageService.upsertVideoResume(key, {
                'positionMs': 90, 'durationMs': 100, 'updatedAt': 3,
              });
              expect(await StorageService.getVideoResume(key), isNotNull);
            }
            _expectSettings(_values(await export()), beforeSqlite);
            final unchangedOther = {
              for (final key in prefs.getKeys())
                if (key.startsWith('p.$other.g.1.') ||
                    key.startsWith('p.$profileId.g.1.')) key: prefs.get(key),
            };
            final noRepair = scenario == 'repair-markers-one';
            final afterMigration = noRepair ? restoredExpected : <String, Object?>{
              ...Map<String, Object?>.from(domain['afterMigration'] as Map),
              ...destinationValues,
            };
            final afterPurge = noRepair ? restoredExpected : <String, Object?>{
              ...Map<String, Object?>.from(domain['afterPurge'] as Map),
              ...destinationValues,
            };
            final revisions = <Map<String, Object?>>[];
            void onRevision() {
              // Capture the actual public notification boundary, not a model
              // of the repair loop. CW/playback and final marker must lag it.
              revisions.add({
                for (final key in [
                  'playback_state_v1', 'finished_movies_v1',
                  'continue_watching_v1', 'playback_completion_migration_generation',
                  'resume_ghost_purge_generation',
                ]) key: prefs.get('$prefix$key'),
              });
            }
            StorageService.localCompletionRevision.addListener(onRevision);
            try {
              await PlaybackProgressStore.migrateExistingPlaybackCompletionThresholds();
              _expectSettings(_values(await export()), afterMigration);
              for (final key in ['Done', 'Done Alias']) {
                expect(await StorageService.getVideoResume(key), noRepair ? isNotNull : isNull);
              }
              expect(await StorageService.getVideoResume('Partial'), isNotNull);
              if (!noRepair) {
                expect(revisions, [{
                  'playback_state_v1': restoredExpected['playback_state_v1'],
                  'finished_movies_v1': ['tt-done', 'tt-existing'],
                  'continue_watching_v1': restoredExpected['continue_watching_v1'],
                  'playback_completion_migration_generation': restoredExpected['playback_completion_migration_generation'],
                  'resume_ghost_purge_generation': 0,
                }]);
              } else {
                expect(revisions, isEmpty);
              }
              await PlaybackProgressStore.purgeUnwatchedResumeGhosts();
              _expectSettings(_values(await export()), afterPurge);
              if (!noRepair) {
                expect(revisions.length, 2);
                expect(revisions.last, {
                  'playback_state_v1': afterPurge['playback_state_v1'],
                  'finished_movies_v1': afterPurge['finished_movies_v1'],
                  'continue_watching_v1': afterPurge['continue_watching_v1'],
                  'playback_completion_migration_generation': 1,
                  'resume_ghost_purge_generation': 0,
                });
              }
              final count = revisions.length;
              await PlaybackProgressStore.migrateExistingPlaybackCompletionThresholds();
              await PlaybackProgressStore.purgeUnwatchedResumeGhosts();
              _expectSettings(_values(await export()), afterPurge);
              expect(revisions.length, count, reason: 'Second run is idempotent');
            } finally {
              StorageService.localCompletionRevision.removeListener(onRevision);
            }
            _expectSettings({
              for (final key in unchangedOther.keys) key: prefs.get(key),
            }, unchangedOther);
          }
          if (!isResidual) {
            expect(await StorageService.getMdblistSavedClones(), {
              101: 201,
              102: 202,
            });
            expect(
              await StorageService.getMdblistSyncCheckpoint(),
              jsonDecode(_settings['mdblist_sync_checkpoint_v1']! as String),
            );
            expect(
              await StorageService.takeTrackingProgressFallbackNotice(),
              true,
            );
            expect(
              await StorageService.takeTrackingProgressFallbackNotice(),
              false,
            );
          }
        },
      );
    }
    }
  }
}
