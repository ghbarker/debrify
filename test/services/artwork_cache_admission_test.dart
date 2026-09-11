import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/artwork_cache_budget.dart';
import 'package:debrify/services/artwork_cache_file.dart';
import 'package:debrify/services/artwork_cache_manager.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'artwork_cache_public_test.dart' show Paths;
import 'artwork_cache_test.dart' show DiskFull;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ArtworkCacheBudget budget;
  late ArtworkCacheManager images, logos;
  final held = <ArtworkCacheFile>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('artwork-admission-');
  });
  tearDown(() async {
    for (final file in held) {
      file.release();
    }
    held.clear();
    await budget.dispose();
    await images.dispose();
    await logos.dispose();
    await root.delete(recursive: true);
  });
  void setup({Future<void> Function()? beforeInventory}) {
    budget = ArtworkCacheBudget(
      handoffGrace: Duration.zero,
      beforeInventory: beforeInventory,
    );
    ArtworkCacheManager manager(String name) => ArtworkCacheManager(
      cacheKey: name,
      budget: budget,
      standardCapacity: 1000,
      directory: Directory(p.join(root.path, name)),
      repository: JsonCacheInfoRepository(
        path: p.join(root.path, '$name.json'),
      ),
    );
    images = manager('images');
    logos = manager('logos');
  }

  Future<ArtworkCacheFile> put(
    ArtworkCacheManager manager,
    String key,
    int size,
  ) async {
    final file =
        await manager.putFile(
              'https://art.test/$key',
              Uint8List(size),
              key: key,
            )
            as ArtworkCacheFile;
    held.add(file);
    return file;
  }

  test(
    'snapshot uses ledger without rescanning; explicit actual-size query still reconciles',
    () async {
      setup();
      final original = await put(images, 'original', 4);
      await put(images, 'resized_w100_original', 2);
      await put(logos, 'logo', 3);
      expect(await budget.admissionSizeBytes(), 9);
      // An out-of-band change distinguishes a ledger read from the old stat-all
      // implementation without relying on machine-dependent timing thresholds.
      await File(original.path).writeAsBytes([1, 2, 3, 4, 5]);
      for (var i = 0; i < 20; i++) {
        expect(await budget.admissionSizeBytes(), 9);
      }
      expect(await budget.sizeBytes(), 10);
      expect(await budget.admissionSizeBytes(), 10);
      await File(original.path).delete();
      expect(
        await budget.admissionSizeBytes(),
        10,
        reason:
            'External deletion conservatively overcounts until reconciliation',
      );
      expect(await budget.sizeBytes(), 5);
      expect(await budget.admissionSizeBytes(), 5);
    },
  );

  test(
    'first admission awaits complete inventory rather than reporting empty',
    () async {
      final ready = Completer<void>();
      setup(beforeInventory: () => ready.future);
      final directory = Directory(p.join(root.path, 'images'));
      await directory.create();
      await File(
        p.join(directory.path, 'preexisting.bin'),
      ).writeAsBytes(Uint8List(7));
      var completed = false;
      final pending = budget.admissionSizeBytes().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      ready.complete();
      expect(await pending, 7);
    },
  );

  test(
    'partial writes and failed OS prefixes are counted before publication',
    () async {
      setup();
      await budget.initialize();
      final path = p.join(root.path, 'images', 'active.part');
      final handle = await File(path).open(mode: FileMode.write);
      final token = budget.token();
      try {
        await budget.begin(path, 'active', images.artworkStore, token);
        await budget.write(path, handle, [1, 2, 3], token);
        expect(await budget.admissionSizeBytes(), 3);
        await expectLater(
          budget.write(path, DiskFull(handle), [4, 5, 6], token),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          await budget.admissionSizeBytes(),
          4,
          reason: 'The failed write persisted one additional byte',
        );
        await budget.clear();
        expect(
          await budget.admissionSizeBytes(),
          4,
          reason: 'A cancelled writer retains its bytes until closed/abandoned',
        );
      } finally {
        await handle.close();
        await budget.abandon(path);
      }
      expect(await budget.admissionSizeBytes(), 0);
    },
  );

  test(
    'retained reader survives clear and decrease; write limit remains authoritative',
    () async {
      setup();
      await budget.apply(expanded: true, bytes: 16);
      final file = await put(images, 'reader', 12);
      await budget.apply(expanded: true, bytes: 4);
      expect(await budget.admissionSizeBytes(), 12);
      await expectLater(
        put(logos, 'blocked', 1),
        throwsA(isA<ArtworkCacheLimit>()),
      );
      expect(await budget.admissionSizeBytes(), 12);
      await budget.clear();
      expect(await budget.admissionSizeBytes(), 12);
      expect(await file.readAsBytes(), Uint8List(12));
      file.release();
      await budget.transaction(() async {}); // Drain release-triggered cleanup.
      expect(await budget.admissionSizeBytes(), 0);
    },
  );

  test(
    'singleton admission initializes policy and combines the production stores',
    () async {
      setup();
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = Paths(p.join(root.path, 'singleton'));
      SharedPreferences.setMockInitialValues({});
      BrowsingCachePreferences.resetForTesting();
      final productionImages = DebrifyImageCache.manager as ArtworkCacheManager;
      final productionLogos =
          DebrifyImageCache.iptvLogos as ArtworkCacheManager;
      try {
        expect(await DebrifyImageCache.admissionSizeBytes(), 0);
        final file = await put(productionImages, 'poster', 5);
        await put(productionLogos, 'logo', 3);
        expect(await DebrifyImageCache.admissionSizeBytes(), 8);
        await File(file.path).writeAsBytes(Uint8List(6));
        expect(await DebrifyImageCache.admissionSizeBytes(), 8);
        expect(await DebrifyImageCache.sizeBytes(), 9);
        expect(await DebrifyImageCache.admissionSizeBytes(), 9);
      } finally {
        for (final file in held) {
          file.release();
        }
        held.clear();
        await productionImages.budget.dispose();
        await productionImages.dispose();
        await productionLogos.dispose();
        PathProviderPlatform.instance = previous;
      }
    },
  );
}
