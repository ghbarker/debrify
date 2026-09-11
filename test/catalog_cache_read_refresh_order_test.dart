import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/catalog_disk_cache.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final damaged in [false, true]) {
    test(
      'a delayed disk ${damaged ? "miss" : "hit"} cannot replace a newer forced refresh in RAM',
      () async {
        HttpOverrides.global = null;
        SharedPreferences.setMockInitialValues({});
        BrowsingCachePreferences.resetForTesting();
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeCommitted(
          ProfileScope(profileId: 'review', dataGeneration: 1, sessionEpoch: 1),
        );
        final root = await Directory.systemTemp.createTemp(
          'catalog-read-order-',
        );
        final disk = CatalogDiskCache.instance;
        final service = StremioService.instance;
        disk.debugTemporaryDirectory = root;
        service.invalidateCache();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var calls = 0;
        server.listen((request) async {
          calls++;
          request.response.write(
            jsonEncode({
              'metas': [
                {
                  'id': 'tt1234567',
                  'type': 'movie',
                  'name': calls == 1 ? 'Saved old title' : 'Forced new title',
                },
              ],
            }),
          );
          await request.response.close();
        });
        final addon = StremioAddon(
          id: 'review',
          name: 'Review',
          baseUrl: 'http://127.0.0.1:${server.port}',
          manifestUrl: 'http://127.0.0.1:${server.port}/manifest.json',
        );
        const catalog = StremioAddonCatalog(
          id: 'popular',
          type: 'movie',
          name: 'Popular',
        );
        final reading = Completer<void>();
        final resume = Completer<void>();
        Future<List<StremioMeta>>? savedRead;
        Future<List<StremioMeta>>? forced;
        addTearDown(() async {
          if (!resume.isCompleted) resume.complete();
          if (savedRead != null) await savedRead;
          if (forced != null) await forced;
          disk.debugRead = null;
          await disk.clear();
          disk.debugTemporaryDirectory = null;
          await server.close(force: true);
          service.invalidateCache();
          ProfileRuntime.debugReset();
          BrowsingCachePreferences.resetForTesting();
          await root.delete(recursive: true);
        });
        await BrowsingCachePreferences.update(
          const BrowsingCacheOptions(rememberTitles: true),
        );
        expect(
          (await service.fetchCatalog(addon, catalog)).single.name,
          'Saved old title',
        );
        await disk.sizeBytes();
        service.invalidateCache();
        disk.debugRead = (file) async {
          final snapshot = await file.readAsString();
          if (!reading.isCompleted) {
            reading.complete();
            await resume.future;
          }
          return damaged ? '{broken' : snapshot;
        };
        savedRead = service.fetchCatalog(addon, catalog);
        await reading.future.timeout(const Duration(seconds: 3));
        forced = service.fetchCatalog(addon, catalog, forceRefresh: true);
        // The writer publishes RAM before acquiring the disk lock held by the
        // delayed read. Establish that newer result through the real public API.
        expect(
          (await forced.timeout(const Duration(seconds: 3))).single.name,
          'Forced new title',
        );
        expect(calls, 2);
        final beforeRelease = await service
            .fetchCatalog(addon, catalog)
            .timeout(const Duration(seconds: 3));
        expect(beforeRelease.single.name, 'Forced new title');
        resume.complete();
        expect((await savedRead).single.name, 'Forced new title');
        expect((await forced).single.name, 'Forced new title');
        final nextVisit = await service.fetchCatalog(addon, catalog);
        expect(nextVisit.single.name, 'Forced new title');
        expect(
          calls,
          2,
          reason:
              'The normal read must not schedule another refresh over the forced writer.',
        );
      },
    );
  }
}
