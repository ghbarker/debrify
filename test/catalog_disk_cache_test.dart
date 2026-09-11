import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/catalog_disk_cache.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const catalog = StremioAddonCatalog(
  id: 'popular',
  type: 'movie',
  name: 'Popular',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late StremioAddon addon;
  var reads = 0;
  Future<void> Function(HttpRequest)? handler;
  final service = StremioService.instance;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    BrowsingCachePreferences.resetForTesting();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'alpha', dataGeneration: 1, sessionEpoch: 1),
    );
    root = await Directory.systemTemp.createTemp('catalog-disk-test-');
    AppStorage.debugOverride(cache: root, support: root, documents: root);
    CatalogDiskCache.instance.debugTemporaryDirectory = root;
    service.invalidateCache();
    reads = 0;
    handler = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      reads++;
      if (handler != null) {
        await handler!(request);
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'metas': [
            {'id': 'tt1234567', 'type': 'movie', 'name': 'Read $reads'},
            {'id': '', 'type': 'movie', 'name': 'Invalid'},
            {'id': 'tt7654321', 'type': 'movie', 'name': 'Second'},
          ],
        }),
      );
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/private-config';
    addon = StremioAddon(
      id: 'test',
      name: 'Test',
      baseUrl: base,
      manifestUrl: '$base/manifest.json',
      catalogs: [catalog],
    );
  });

  tearDown(() async {
    CatalogDiskCache.instance.debugWriteTemporary = null;
    CatalogDiskCache.instance.debugRead = null;
    await CatalogDiskCache.instance.clear();
    CatalogDiskCache.instance.debugTemporaryDirectory = null;
    await server.close(force: true);
    service.invalidateCache();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    BrowsingCachePreferences.resetForTesting();
    await root.delete(recursive: true);
  });

  Future<void> enable() => BrowsingCachePreferences.update(
    const BrowsingCacheOptions(rememberTitles: true, titleSizeMb: 10),
  );
  void profile(String id, {int generation = 1, int epoch = 3}) =>
      ProfileRuntime.publish(
        ProfileScope(
          profileId: id,
          dataGeneration: generation,
          sessionEpoch: epoch,
        ),
      );
  Future<List<File>> files() async => root
      .list(recursive: true)
      .where((f) => f is File && f.path.endsWith('.json'))
      .cast<File>()
      .toList();
  Future<void> reply(HttpRequest request, String title) async {
    request.response.write(
      jsonEncode({
        'metas': [
          {'id': 'tt1234567', 'type': 'movie', 'name': title},
        ],
      }),
    );
    await request.response.close();
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  test(
    'enabled catalog survives RAM reset and a new profile session',
    () async {
      await BrowsingCachePreferences.update(
        const BrowsingCacheOptions(rememberTitles: true),
      );
      await service.fetchCatalog(addon, catalog);
      service.invalidateCache();
      ProfileRuntime.publish(
        ProfileScope(profileId: 'alpha', dataGeneration: 1, sessionEpoch: 2),
      );
      var raw = 0;
      final restored = await service.fetchCatalog(
        addon,
        catalog,
        onRawCount: (value) => raw = value,
      );
      expect(restored.map((m) => m.name), ['Read 1', 'Second']);
      expect(raw, 3);
      expect(restored.first.sourceAddon, same(addon));
    },
  );

  test(
    'disabled keeps existing RAM caching but never persists pages',
    () async {
      await service.fetchCatalog(addon, catalog);
      await service.fetchCatalog(addon, catalog);
      expect(reads, 1);
      service.invalidateCache();
      final fresh = await service.fetchCatalog(addon, catalog);
      expect(fresh.first.name, 'Read 2');
      expect(
        await root.list(recursive: true).where((e) => e is File).isEmpty,
        isTrue,
      );
    },
  );

  test(
    'saved page returns before slow refresh and does not mutate returned list',
    () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      service.invalidateCache();
      final arrived = Completer<HttpRequest>();
      handler = (request) async {
        arrived.complete(request);
      };
      final restored = await service
          .fetchCatalog(addon, catalog)
          .timeout(const Duration(seconds: 2));
      expect(restored.first.name, 'Read 1');
      final pending = await arrived.future;
      await reply(pending, 'Quiet refresh');
      await waitFor(() => reads == 2);
      // Join the same in-flight refresh through the production path.
      service.invalidateCache();
      final ticket = await CatalogDiskCache.instance.request(
        '${addon.baseUrl}/catalog/movie/popular.json',
        addon,
        catalog,
      );
      for (var i = 0; i < 100; i++) {
        final page = await CatalogDiskCache.instance.read(ticket, addon);
        if (page?.items.first.name == 'Quiet refresh') break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        (await CatalogDiskCache.instance.read(ticket, addon))!.items.first.name,
        'Quiet refresh',
      );
      expect(restored.first.name, 'Read 1');
    },
  );

  test(
    'profile, generation, addon configuration, filters and skip never collide',
    () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      expect(
        (await service.fetchCatalog(addon, catalog, skip: 20)).first.name,
        'Read 2',
      );
      expect(
        (await service.fetchCatalog(addon, catalog, genre: 'Drama')).first.name,
        'Read 3',
      );
      expect(
        (await service.fetchCatalog(
          addon,
          catalog,
          extras: {'sort': 'new'},
        )).first.name,
        'Read 4',
      );
      final configured = addon.copyWith(version: '2');
      expect(
        (await service.fetchCatalog(configured, catalog)).first.name,
        'Read 5',
      );
      profile('beta');
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 6');
      profile('alpha', generation: 2, epoch: 4);
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 7');
      expect(await files(), hasLength(7));
    },
  );

  test(
    'force refresh bypasses both caches and supersedes an older refresh',
    () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      service.invalidateCache();
      final arrived = Completer<HttpRequest>();
      handler = (request) async {
        if (!arrived.isCompleted) {
          arrived.complete(request);
        } else {
          await reply(request, 'Forced');
        }
      };
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 1');
      final old = await arrived.future;
      expect(
        (await service.fetchCatalog(
          addon,
          catalog,
          forceRefresh: true,
        )).first.name,
        'Forced',
      );
      await reply(old, 'Too late');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Forced');
      expect(
        jsonDecode(
          await (await files()).single.readAsString(),
        )['items'][0]['name'],
        'Forced',
      );
    },
  );

  for (final change in ['clear', 'disable', 'profile', 'metadata', 'addon']) {
    test('late response after $change cannot repopulate disk or RAM', () async {
      await enable();
      final arrived = Completer<HttpRequest>();
      handler = (request) async {
        arrived.complete(request);
      };
      final pending = service.fetchCatalog(addon, catalog);
      final request = await arrived.future;
      switch (change) {
        case 'clear':
          await CatalogDiskCache.instance.clear();
        case 'disable':
          await BrowsingCachePreferences.update(const BrowsingCacheOptions());
        case 'profile':
          profile('beta');
        case 'metadata':
          MetadataPreferencesService.revision.value++;
        case 'addon':
          CatalogDiskCache.instance.invalidateRequests();
      }
      await reply(request, 'Too late');
      expect(await pending, isEmpty);
      expect(await CatalogDiskCache.instance.sizeBytes(), 0);
      handler = null;
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 2');
    });
  }

  test(
    'disable ignores existing files, then re-enable may reuse them',
    () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      await BrowsingCachePreferences.update(const BrowsingCacheOptions());
      service.invalidateCache();
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 2');
      expect(
        jsonDecode(
          await (await files()).single.readAsString(),
        )['items'][0]['name'],
        'Read 1',
      );
      await enable();
      service.invalidateCache();
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 1');
    },
  );

  for (final damage in [
    'json',
    'schema',
    'expired',
    'future',
    'raw',
    'source',
  ]) {
    test('$damage cache damage fails open to the network', () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      final file = (await files()).single;
      final data = jsonDecode(await file.readAsString());
      switch (damage) {
        case 'schema':
          data['version'] = 99;
        case 'expired':
          data['fetchedAt'] = DateTime.now()
              .subtract(const Duration(hours: 25))
              .millisecondsSinceEpoch;
        case 'future':
          data['fetchedAt'] = DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch;
        case 'raw':
          data['rawCount'] = -1;
        case 'source':
          data['items'][0]['source_addon'] = {
            'base_url': 'https://wrong.invalid',
          };
      }
      await file.writeAsString(damage == 'json' ? '{broken' : jsonEncode(data));
      service.invalidateCache();
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 2');
    });
  }

  test(
    'serialized pages omit addon manifests and playable stream fields',
    () async {
      await enable();
      handler = (request) async {
        request.response.write(
          jsonEncode({
            'metas': [
              {
                'id': 'tmdb:42',
                'imdb_id': 'tt1234567',
                'type': 'movie',
                'name': 'A',
                'poster': 'https://art.invalid/poster.jpg',
                'videos': [
                  {'url': 'https://secret.invalid/play'},
                ],
                'streams': [
                  {'url': 'https://secret.invalid/stream'},
                ],
              },
            ],
          }),
        );
        await request.response.close();
      };
      await service.fetchCatalog(addon, catalog);
      final file = (await files()).single;
      final body = await file.readAsString();
      expect(body, isNot(contains('private-config')));
      expect(file.path, isNot(contains('private-config')));
      expect(body, isNot(contains('source_addon')));
      expect(body, isNot(contains('secret.invalid')));
      service.invalidateCache();
      final restored = await service.fetchCatalog(addon, catalog);
      expect(restored.first.id, 'tmdb:42');
      expect(restored.first.imdbId, 'tt1234567');
      expect(restored.first.sourceAddon, same(addon));
    },
  );

  test('empty pages survive restart with rawCount zero', () async {
    await enable();
    handler = (request) async {
      request.response.write('{"metas":[]}');
      await request.response.close();
    };
    await service.fetchCatalog(addon, catalog);
    service.invalidateCache();
    var raw = -1;
    expect(
      await service.fetchCatalog(addon, catalog, onRawCount: (v) => raw = v),
      isEmpty,
    );
    expect(raw, 0);
    expect(await files(), hasLength(1));
  });

  test(
    'unavailable storage does not discard a successful network response',
    () async {
      await enable();
      await File(
        '${root.path}/catalog-titles-v1',
      ).writeAsString('not a directory');
      expect((await service.fetchCatalog(addon, catalog)).first.name, 'Read 1');
      expect(await CatalogDiskCache.instance.sizeBytes(), 0);
    },
  );

  test(
    'disk-full replacement keeps the old complete page and returns fresh network data',
    () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      final before = await (await files()).single.readAsString();
      CatalogDiskCache.instance.debugWriteTemporary = (file, bytes) async {
        await file.writeAsBytes(bytes.take(30).toList());
        throw FileSystemException(
          'No space left',
          file.path,
          const OSError('disk full', 28),
        );
      };
      expect(
        (await service.fetchCatalog(
          addon,
          catalog,
          forceRefresh: true,
        )).first.name,
        'Read 2',
      );
      expect(await (await files()).single.readAsString(), before);
      expect(
        await root
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'clear during atomic write waits for cleanup and retires the network result',
    () async {
      await enable();
      final writing = Completer<void>();
      final resume = Completer<void>();
      CatalogDiskCache.instance.debugWriteTemporary = (file, bytes) async {
        await file.writeAsBytes(bytes, flush: true);
        writing.complete();
        await resume.future;
      };
      final pending = service.fetchCatalog(addon, catalog);
      await writing.future;
      final clearing = CatalogDiskCache.instance.clear();
      resume.complete();
      expect(await pending, isEmpty);
      await clearing;
      expect(await CatalogDiskCache.instance.sizeBytes(), 0);
    },
  );

  test(
    'budget reduction trims measured bytes without needing another fetch',
    () async {
      await enable();
      await BrowsingCachePreferences.update(
        const BrowsingCacheOptions(rememberTitles: true, titleSizeMb: 25),
      );
      for (var i = 0; i < 4; i++) {
        final request = await CatalogDiskCache.instance.request(
          'page$i',
          addon,
          catalog,
        );
        await CatalogDiskCache.instance.write(request, addon, [
          StremioMeta(
            id: 'tt1234567',
            type: 'movie',
            name: '$i',
            addedAtMs: 42,
            description: List.filled(3 * 1024 * 1024, 'x').join(),
          ),
        ], 1);
      }
      expect(
        await CatalogDiskCache.instance.sizeBytes(),
        greaterThan(10 * 1024 * 1024),
      );
      await enable();
      expect(
        await CatalogDiskCache.instance.sizeBytes(),
        lessThanOrEqualTo(10 * 1024 * 1024),
      );
      final saved = jsonDecode(await (await files()).last.readAsString());
      expect(saved['items'][0]['addedAtMs'], 42);
    },
  );

  test(
    'measured global LRU evicts across profiles within the selected budget',
    () async {
      await enable();
      Future<void> save(String owner, String url) async {
        profile(owner, epoch: ProfileRuntime.nextEpoch);
        final request = await CatalogDiskCache.instance.request(
          url,
          addon,
          catalog,
        );
        await CatalogDiskCache.instance.write(request, addon, [
          StremioMeta(
            id: 'tt1234567',
            type: 'movie',
            name: url,
            description: List.filled(3 * 1024 * 1024, 'x').join(),
          ),
        ], 1);
      }

      await save('alpha', 'one');
      await save('beta', 'two');
      await save('gamma', 'three');
      // Filesystems may round timestamp writes; establish unambiguous old ages.
      for (final file in await files()) {
        final hours =
            file.path.contains(sha256.convert(utf8.encode('alpha')).toString())
            ? 3
            : file.path.contains(sha256.convert(utf8.encode('beta')).toString())
            ? 2
            : 1;
        await file.setLastModified(
          DateTime.now().subtract(Duration(hours: hours)),
        );
      }
      profile('alpha', epoch: ProfileRuntime.nextEpoch);
      expect(
        await CatalogDiskCache.instance.read(
          await CatalogDiskCache.instance.request('one', addon, catalog),
          addon,
        ),
        isNotNull,
      );
      await save('delta', 'four');
      final stored = await files();
      expect(stored, hasLength(3));
      expect(
        stored.any(
          (f) =>
              f.path.contains(sha256.convert(utf8.encode('beta')).toString()),
        ),
        isFalse,
        reason: stored.map((f) => f.path).join('\n'),
      );
      final measured = (await Future.wait(
        stored.map((f) => f.length()),
      )).fold(0, (int a, b) => a + b);
      expect(await CatalogDiskCache.instance.sizeBytes(), measured);
      expect(measured, lessThanOrEqualTo(10 * 1024 * 1024));
      await CatalogDiskCache.instance.clear();
      expect(await CatalogDiskCache.instance.sizeBytes(), 0);
    },
  );

  test(
    'disposable pages stay outside durable profile-generation roots',
    () async {
      await enable();
      await service.fetchCatalog(addon, catalog);
      expect(
        await ProfileRuntime.scope.value!.generationDirectory(root).exists(),
        isFalse,
      );
      final file = (await files()).single;
      expect(file.path, contains('catalog-titles-v1'));
      expect(
        file.path,
        contains(sha256.convert(utf8.encode('alpha')).toString()),
      );
      expect(file.path, isNot(contains('profiles')));
    },
  );

  for (final envelope in [
    '{"error":"unavailable"}',
    '{"metas":[],"error":"unavailable"}',
    '{"success":false,"metas":[]}',
    '{}',
    '{"metas":null}',
    '{"metas":"broken"}',
  ]) {
    test(
      'error or missing payload $envelope is never cached as exhaustion',
      () async {
        await enable();
        handler = (request) async {
          request.response.write(envelope);
          await request.response.close();
        };
        expect(await service.fetchCatalog(addon, catalog), isEmpty);
        expect(await CatalogDiskCache.instance.sizeBytes(), 0);
        handler = null;
        expect(
          (await service.fetchCatalog(addon, catalog)).first.name,
          'Read 2',
        );
      },
    );
  }

  for (final replacement in ['A-B-A', 'generation']) {
    test(
      'delayed read cannot publish after $replacement replacement',
      () async {
        await enable();
        await service.fetchCatalog(addon, catalog);
        service.invalidateCache();
        final reading = Completer<void>();
        final resume = Completer<void>();
        CatalogDiskCache.instance.debugRead = (file) async {
          final body = await file.readAsString();
          reading.complete();
          await resume.future;
          return body;
        };
        final pending = service.fetchCatalog(addon, catalog);
        await reading.future;
        if (replacement == 'A-B-A') {
          profile('beta', epoch: 2);
          profile('alpha', epoch: 3);
        } else {
          profile('alpha', generation: 2, epoch: 2);
        }
        resume.complete();
        expect(await pending, isEmpty);
        expect(reads, 1);
      },
    );

    test(
      'delayed write cannot publish after $replacement replacement',
      () async {
        await enable();
        final writing = Completer<void>();
        final resume = Completer<void>();
        CatalogDiskCache.instance.debugWriteTemporary = (file, bytes) async {
          await file.writeAsBytes(bytes);
          writing.complete();
          await resume.future;
        };
        final pending = service.fetchCatalog(addon, catalog);
        await writing.future;
        if (replacement == 'A-B-A') {
          profile('beta', epoch: 2);
          profile('alpha', epoch: 3);
        } else {
          profile('alpha', generation: 2, epoch: 2);
        }
        resume.complete();
        expect(await pending, isEmpty);
        expect(await CatalogDiskCache.instance.sizeBytes(), 0);
      },
    );
  }

  test('artwork and stream options do not retire a title fetch', () async {
    await enable();
    final arrived = Completer<HttpRequest>();
    handler = (request) async {
      arrived.complete(request);
    };
    final pending = service.fetchCatalog(addon, catalog);
    final request = await arrived.future;
    await BrowsingCachePreferences.update(
      BrowsingCachePreferences.current.copyWith(
        expandedArtwork: true,
        prefetchMovieStreams: false,
      ),
    );
    await reply(request, 'Unaffected');
    expect((await pending).first.name, 'Unaffected');
    expect(await CatalogDiskCache.instance.sizeBytes(), greaterThan(0));
  });

  for (final action in ['clear', 'disable-enable']) {
    test(
      '$action old completion cannot remove the new same-key pending fetch',
      () async {
        await enable();
        final first = Completer<HttpRequest>();
        final second = Completer<HttpRequest>();
        handler = (request) async {
          if (!first.isCompleted) {
            first.complete(request);
          } else if (!second.isCompleted) {
            second.complete(request);
          } else {
            await reply(request, 'Unexpected third request');
          }
        };
        final oldFetch = service.fetchCatalog(addon, catalog);
        final old = await first.future;
        if (action == 'clear') {
          await CatalogDiskCache.instance.clear();
        } else {
          await BrowsingCachePreferences.update(const BrowsingCacheOptions());
          await enable();
        }
        final newFetch = service.fetchCatalog(addon, catalog);
        final fresh = await second.future;
        await reply(old, 'Old');
        expect(await oldFetch, isEmpty);
        final joined = service.fetchCatalog(addon, catalog);
        await reply(fresh, 'New');
        expect((await newFetch).first.name, 'New');
        expect((await joined).first.name, 'New');
        expect(reads, 2);
      },
    );
  }

  test(
    'disk page preserves duplicate order and raw cursor before caller filtering',
    () async {
      await enable();
      handler = (request) async {
        request.response.write(
          jsonEncode({
            'metas': [
              {'id': 'b', 'type': 'movie', 'name': 'B'},
              {'id': '', 'type': 'movie', 'name': 'Invalid'},
              {'id': 'a', 'type': 'movie', 'name': 'A'},
              {'id': 'b', 'type': 'movie', 'name': 'B again'},
            ],
          }),
        );
        await request.response.close();
      };
      await service.fetchCatalog(addon, catalog, skip: 20);
      service.invalidateCache();
      var raw = 0;
      final page = await service.fetchCatalog(
        addon,
        catalog,
        skip: 20,
        onRawCount: (count) => raw = count,
      );
      expect(page.map((m) => m.id), ['b', 'a', 'b']);
      expect(page.map((m) => m.name), ['B', 'A', 'B again']);
      expect(20 + raw, 24);
      final seen = <String>{};
      final visible = page.where((m) => m.id != 'a' && seen.add(m.id)).toList();
      expect(visible, hasLength(1));
      expect(raw, 4);
    },
  );
}
