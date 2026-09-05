import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/transfer/transfer_categories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Real unchanged origin: 1b5eeb83be007615bcfbda48e616f186910504d7.
// Supplemental Q2 pins, not exhaustive coverage of every retiring API.
// AndroidTvPlayerBridge's dart:io Android gate cannot be entered on this host:
// no native-handler/decoder/launch proof is claimed. Its eight affected facades,
// their callers, and getVideoPlaybackState remain outside retirement.
class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences(super.data) : super.withData();
  final events = <String>[];
  String? failWrite;
  String? holdWrite;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    events.add('write:$valueType:$key');
    if (key == failWrite) throw StateError('synthetic write failure');
    if (key == holdWrite) {
      entered.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    events.add('remove:$key');
    return super.remove(key);
  }

  Future<Map<String, Object>> snapshot() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Preferences backend;
  final notifier = StorageService.localCompletionRevision;
  final originalRevision = notifier.value;
  final originalStartup = StorageService.startupIptvChannelCached;

  void install([Map<String, Object> values = const {}]) {
    SharedPreferences.resetStatic();
    backend = _Preferences({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.q2_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'synthetic-q2-origin');
    install();
  });

  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    StorageService.startupIptvChannelCached = originalStartup;
    notifier.value = originalRevision;
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  test('season reader keeps exact season and title canonicalization', () async {
    final raw = jsonEncode({
      'series_a_b': {
        'type': 'series',
        'finishedEpisodes': {
          '2': {'3': 100, '5': 200},
          '02': {'8': 300},
        },
      },
    });
    install({'playback_state_v1': raw});
    expect(
      await PlaybackProgressStore.getFinishedEpisodesForSeason(
        seriesTitle: 'A-B',
        season: 2,
      ),
      {3, 5},
    );
    expect(
      await PlaybackProgressStore.getFinishedEpisodesForSeason(
        seriesTitle: 'A B',
        season: 9,
      ),
      isEmpty,
    );
    expect((await backend.snapshot())['flutter.playback_state_v1'], raw);
    expect(backend.events, isEmpty);
  });

  test('season reader still parses malformed unrequested seasons', () async {
    install({
      'playback_state_v1': jsonEncode({
        'series_show': {
          'type': 'series',
          'finishedEpisodes': {
            '1': {'1': 10},
            '9': {'not-an-integer': 20},
          },
        },
      }),
    });
    await expectLater(
      PlaybackProgressStore.getFinishedEpisodesForSeason(
        seriesTitle: 'Show',
        season: 1,
      ),
      throwsFormatException,
    );
    expect(backend.events, isEmpty);
  });

  test('canonical channel keeps synthetic case and meaningful URL parts', () {
    expect(
      IptvPrefs.canonicalIptvChannelKey('stremio-tv://UP/A%2FB'),
      'stremio-tv://UP/A%2FB',
    );
    expect(
      IptvPrefs.canonicalIptvChannelKey(
        'https://EXAMPLE.invalid/live/u/p/12.m3u8?token=x',
      ),
      'https://example.invalid/u/p/12?token=x',
    );
    expect(IptvPrefs.canonicalIptvChannelKey('not a URL'), 'not a URL');
    expect(
      IptvPrefs.canonicalIptvChannelKey(
        'https://x.invalid/movie/u/p/12.ts',
      ),
      'https://x.invalid/movie/u/p/12.ts',
    );
  });

  test(
    'clear startup removes only persisted choice, not synchronous cache',
    () async {
      install({
        'startup_iptv_channel': 'synthetic',
        'startup_iptv_mode': 'last',
      });
      final cached = <String, dynamic>{'url': 'https://example.invalid/live'};
      StorageService.startupIptvChannelCached = cached;
      await IptvPrefs.clearStartupIptvChannel();
      expect(backend.events, ['remove:flutter.startup_iptv_channel']);
      expect(await backend.snapshot(), {
        'flutter.startup_iptv_mode': 'last',
        'flutter.q2_sentinel': 'untouched',
      });
      expect(
        identical(StorageService.startupIptvChannelCached, cached),
        isTrue,
      );
      expect(identical(IptvPrefs.startupIptvChannelCached, cached), isTrue);
    },
  );

  test(
    'reset preserves notifier identity but clears the single startup field',
    () async {
      StorageService.startupIptvChannelCached = {'synthetic': true};
      final before = notifier.value;
      StorageService.resetProfileCaches();
      expect(
        identical(StorageService.localCompletionRevision, notifier),
        isTrue,
      );
      expect(
        identical(PlaybackProgressStore.localCompletionRevision, notifier),
        isTrue,
      );
      expect(notifier.value, before);
      expect(StorageService.startupIptvChannelCached, isNull);
      expect(IptvPrefs.startupIptvChannelCached, isNull);
      expect(backend.events, isEmpty);
    },
  );

  test(
    'movie save retains defaults, raw values and retained reader route',
    () async {
      await PlaybackProgressStore.saveVideoPlaybackState(
        videoTitle: 'A-B',
        videoUrl: 'https://example.invalid/movie',
        positionMs: -7,
        durationMs: 10,
      );
      final state = (await StorageService.getVideoPlaybackState(
        videoTitle: 'A B',
      ))!;
      expect(state['updatedAt'], isA<int>());
      expect({...state}..remove('updatedAt'), {
        'type': 'video',
        'title': 'A-B',
        'url': 'https://example.invalid/movie',
        'positionMs': -7,
        'durationMs': 10,
        'speed': 1.0,
        'aspect': 'contain',
      });
      final stored = (await backend.snapshot())['flutter.playback_state_v1'];
      expect(stored, isA<String>());
      expect((jsonDecode(stored as String) as Map)['video_a_b'], state);
    },
  );

  for (final fail in [false, true]) {
    test(
      'revision follows durable write, not cached mutation; failure=$fail',
      () async {
        const key = 'flutter.explicitly_watched_series_v1';
        final before = notifier.value;
        void changed() => backend.events.add('revision');
        notifier.addListener(changed);
        try {
          if (fail) {
            backend.failWrite = key;
            await expectLater(
              PlaybackProgressStore.setSeriesExplicitlyWatched(
                ' TT-Q2 ',
                watched: true,
              ),
              throwsStateError,
            );
            expect(notifier.value, before);
            expect((await backend.snapshot()).containsKey(key), isFalse);
          } else {
            backend.holdWrite = key;
            final pending = PlaybackProgressStore.setSeriesExplicitlyWatched(
              ' TT-Q2 ',
              watched: true,
            );
            await backend.entered.future;
            expect(notifier.value, before);
            expect((await backend.snapshot()).containsKey(key), isFalse);
            backend.release.complete();
            await pending;
            expect(notifier.value, before + 1);
            expect((await backend.snapshot())[key], ['tt-q2']);
          }
          expect(backend.events, [
            'write:StringList:$key',
            if (!fail) 'revision',
          ]);
          expect(await PlaybackProgressStore.getExplicitlyWatchedSeriesIds(), {
            'tt-q2',
          });
        } finally {
          if (!backend.release.isCompleted) backend.release.complete();
          notifier.removeListener(changed);
        }
      },
    );
  }

  for (final entry in [
    (
      TransferCategories.realDebrid,
      StorageService.saveApiKey,
      ProviderCredentialPrefs.setRealDebridIntegrationEnabled,
    ),
    (
      TransferCategories.torbox,
      StorageService.saveTorboxApiKey,
      ProviderCredentialPrefs.setTorboxIntegrationEnabled,
    ),
    (
      TransferCategories.premiumize,
      StorageService.savePremiumizeApiKey,
      ProviderCredentialPrefs.setPremiumizeIntegrationEnabled,
    ),
    (
      TransferCategories.allDebrid,
      StorageService.saveAllDebridApiKey,
      ProviderCredentialPrefs.setAllDebridIntegrationEnabled,
    ),
  ]) {
    test(
      '${entry.$1.key}: real transfer inspector invokes live toggle callback',
      () async {
        final inspect = entry.$1.inspect!;
        expect((await inspect()).isConfigured, isFalse);
        await entry.$2('synthetic-q2-credential');
        await entry.$3(false);
        final off = await inspect();
        expect([off.isConfigured, off.defaultSelected], [false, false]);
        await entry.$3(true);
        final on = await inspect();
        expect([on.isConfigured, on.defaultSelected], [true, true]);
        expect((await backend.snapshot())['flutter.q2_sentinel'], 'untouched');
      },
    );
  }

  for (final folder in [
    (
      'debrify-torrents',
      'pikpak_torrents_folder_id',
      ProviderCredentialPrefs.getPikPakTorrentsFolderId,
      ProviderCredentialPrefs.setPikPakTorrentsFolderId,
    ),
    (
      'debrify-tv',
      'pikpak_tv_folder_id',
      ProviderCredentialPrefs.getPikPakTvFolderId,
      ProviderCredentialPrefs.setPikPakTvFolderId,
    ),
  ]) {
    test(
      '${folder.$1}: malformed getter falls back before any transport',
      () async {
        install({folder.$2: 7});
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          throw StateError('must not reach transport');
        });
        try {
          final result = await http.runWithClient(
            () => PikPakApiService.instance.findOrCreateSubfolder(
              folderName: folder.$1,
              parentFolderId: 'synthetic-parent',
              getCachedId: folder.$3,
              setCachedId: folder.$4,
            ),
            () => client,
          );
          expect(result, 'synthetic-parent');
          expect(requests, 0);
          expect(backend.events, isEmpty);
          expect((await backend.snapshot())['flutter.${folder.$2}'], 7);
        } finally {
          client.close();
        }
      },
    );
    for (final fail in [false, true]) {
      test(
        '${folder.$1}: real folder consumer awaits setter; failure=$fail',
        () async {
          await ProviderCredentialPrefs.setPikPakAccessToken('synthetic-access');
          await ProviderCredentialPrefs.setPikPakRefreshToken('synthetic-refresh');
          backend.events.clear();
          final key = 'flutter.${folder.$2}';
          if (fail) {
            backend.failWrite = key;
          } else {
            backend.holdWrite = key;
          }
          final client = MockClient((request) async {
            backend.events.add('http:${request.method}:${request.url.path}');
            expect(request.method, 'GET');
            expect(request.url.path, '/drive/v1/files');
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'found-id', 'name': folder.$1, 'kind': 'drive#folder'},
                ],
              }),
              200,
            );
          });
          try {
            var finished = false;
            final pending = http.runWithClient(
              () => PikPakApiService.instance
                  .findOrCreateSubfolder(
                    folderName: folder.$1,
                    parentFolderId: 'synthetic-parent',
                    getCachedId: folder.$3,
                    setCachedId: folder.$4,
                  )
                  .then((value) {
                    finished = true;
                    return value;
                  }),
              () => client,
            );
            if (!fail) {
              await backend.entered.future;
              expect(finished, isFalse);
              expect((await backend.snapshot()).containsKey(key), isFalse);
              backend.release.complete();
            }
            expect(await pending, 'found-id');
            expect(backend.events, [
              'http:GET:/drive/v1/files',
              'write:String:$key',
            ]);
            expect((await backend.snapshot())[key], fail ? isNull : 'found-id');
            // SharedPreferences mutates its cache before the backend failure.
            expect(await folder.$3(), 'found-id');
          } finally {
            if (!backend.release.isCompleted) backend.release.complete();
            client.close();
          }
        },
      );
    }
  }
}
