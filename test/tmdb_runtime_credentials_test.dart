import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/collection_native_source_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/tmdb_credential_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingTokenStore extends InMemorySharedPreferencesStore {
  FailingTokenStore() : super.withData({});
  String failure = '';
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failure == 'throw') throw StateError('write failed');
    if (failure == 'false') return false;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async =>
      failure.isNotEmpty ? false : super.remove(key);
}

class TrackedTmdbClient extends MockClient {
  TrackedTmdbClient(super.fn, this.onClose);
  final void Function() onClose;
  @override
  void close() {
    onClose();
    super.close();
  }
}

CollectionCatalogSource runtimeSource() => CollectionCatalogSource.fromJson({
  'provider': 'tmdb',
  'tmdbSourceType': 'DISCOVER',
  'mediaType': 'MOVIE',
  'title': 'Runtime',
})!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late FailingTokenStore store;
  setUp(() async {
    TmdbCredentialService.resetForTesting();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'runtime-token-test');
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    store = FailingTokenStore();
    SharedPreferencesStorePlatform.instance = store;
    await TmdbCredentialService.initialize();
  });
  tearDown(() {
    TmdbCredentialService.resetForTesting();
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  test(
    'sealed override replaces and removes without restart; build fallback survives',
    () async {
      expect(
        (await TmdbCredentialService.capture()).token,
        TmdbCredentialService.buildToken.trim(),
      );
      await TmdbCredentialService.save('  first-token  ');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(TmdbCredentialService.key)!;
      expect(stored, startsWith(SecretVault.prefix));
      expect(stored, isNot(contains('first-token')));
      expect((await TmdbCredentialService.capture()).token, 'first-token');
      await TmdbCredentialService.save('second-token');
      expect((await TmdbCredentialService.capture()).token, 'second-token');
      await TmdbCredentialService.save('   ');
      expect(prefs.containsKey(TmdbCredentialService.key), isFalse);
      expect(
        (await TmdbCredentialService.capture()).token,
        TmdbCredentialService.buildToken.trim(),
      );
    },
  );

  for (final outcome in ['false', 'throw']) {
    test('failed $outcome write does not activate new token', () async {
      await TmdbCredentialService.save('old-token');
      final revision = TmdbCredentialService.revision.value;
      store.failure = outcome;
      await expectLater(
        TmdbCredentialService.save('new-token'),
        throwsStateError,
      );
      expect(TmdbCredentialService.revision.value, revision);
      expect(TmdbCredentialService.effectiveToken, 'old-token');
      expect((await TmdbCredentialService.capture()).token, 'old-token');
      await expectLater(TmdbCredentialService.save(''), throwsStateError);
      expect((await TmdbCredentialService.capture()).token, 'old-token');
    });
  }

  test(
    'both HTTP consumers change headers and invalidate completed caches',
    () async {
      final headers = <String>[];
      http.Client client() => MockClient((request) async {
        headers.add(request.headers['Authorization']!);
        return http.Response(
          jsonEncode({
            'id': 1,
            'results': [
              {'id': 1, 'title': headers.last},
            ],
            'total_pages': 1,
          }),
          200,
        );
      });
      final metadata = TmdbMetadataRepository(clientFactory: client);
      final native = CollectionNativeSourceService(
        tmdbClientFactory: client,
        resolveIds: false,
      );
      addTearDown(metadata.dispose);
      addTearDown(native.close);
      await TmdbCredentialService.save('alpha');
      await metadata.get('movie/1');
      await native.fetch(runtimeSource(), 1);
      await metadata.get('movie/1');
      await native.fetch(runtimeSource(), 1);
      expect(headers, ['Bearer alpha', 'Bearer alpha']);
      await TmdbCredentialService.save('beta');
      await metadata.get('movie/1');
      await native.fetch(runtimeSource(), 1);
      expect(headers, [
        'Bearer alpha',
        'Bearer alpha',
        'Bearer beta',
        'Bearer beta',
      ]);
    },
  );

  for (final nativeConsumer in [false, true]) {
    test(
      '${nativeConsumer ? 'native' : 'metadata'} rejects old response and closes owned client',
      () async {
        await TmdbCredentialService.save('old-token');
        final started = Completer<void>();
        final release = Completer<void>();
        var closes = 0;
        final headers = <String>[];
        http.Client client() => TrackedTmdbClient((request) async {
          final header = request.headers['Authorization']!;
          headers.add(header);
          if (header == 'Bearer old-token') {
            started.complete();
            await release.future;
          }
          return http.Response(
            jsonEncode({
              'id': 1,
              'results': [
                {'id': 1, 'title': header},
              ],
              'total_pages': 1,
            }),
            200,
          );
        }, () => closes++);
        final metadata = TmdbMetadataRepository(clientFactory: client);
        final native = CollectionNativeSourceService(
          tmdbClientFactory: client,
          resolveIds: false,
        );
        addTearDown(metadata.dispose);
        addTearDown(native.close);
        Future<Object> fetch() async => nativeConsumer
            ? await native.fetch(runtimeSource(), 1)
            : await metadata.get('movie/1');
        final old = fetch();
        final rejected = expectLater(old, throwsStateError);
        await started.future;
        await TmdbCredentialService.save('new-token');
        expect(closes, greaterThan(0));
        await fetch();
        release.complete();
        await rejected;
        await fetch();
        expect(headers, ['Bearer old-token', 'Bearer new-token']);
      },
    );
  }

  test(
    'explicit constructor token stays fixed despite runtime changes',
    () async {
      final headers = <String>[];
      http.Client client() => MockClient((request) async {
        headers.add(request.headers['Authorization']!);
        return http.Response('{"results":[],"total_pages":1}', 200);
      });
      final metadata = TmdbMetadataRepository(
        token: 'fixed',
        clientFactory: client,
      );
      final native = CollectionNativeSourceService(
        tmdbToken: 'fixed',
        tmdbClientFactory: client,
        resolveIds: false,
      );
      addTearDown(metadata.dispose);
      addTearDown(native.close);
      await TmdbCredentialService.save('runtime');
      await metadata.get('movie/1');
      await native.fetch(runtimeSource(), 1);
      expect(headers, ['Bearer fixed', 'Bearer fixed']);
    },
  );

  test('cold first identity lookup uses persisted runtime token', () async {
    await TmdbCredentialService.save('persisted');
    TmdbCredentialService.resetForTesting();
    final headers = <String?>[];
    final native = CollectionNativeSourceService(
      tmdbClientFactory: () => MockClient((request) async {
        headers.add(request.headers['Authorization']);
        return http.Response('{"imdb_id":"tt1234567"}', 200);
      }),
    );
    addTearDown(native.close);
    final result = await native.resolveIdentity(
      const StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Cold title'),
    );
    expect(result.id, 'tt1234567');
    expect(result.imdbId, 'tt1234567');
    expect(headers, ['Bearer persisted']);
  });
}
