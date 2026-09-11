import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/artwork_cache_file.dart';
import 'package:debrify/services/artwork_cache_manager.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Paths extends PathProviderPlatform {
  Paths(this.directory);
  final String directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production singleton API bootstraps preferences, applies all choices live and clears both stores',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'artwork-public-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = Paths(directory.path);
      SharedPreferences.setMockInitialValues({});
      BrowsingCachePreferences.resetForTesting();
      await BrowsingCachePreferences.initialize();
      final images = DebrifyImageCache.manager as ArtworkCacheManager;
      final logos = DebrifyImageCache.iptvLogos as ArtworkCacheManager;
      try {
        await DebrifyImageCache.applyPolicy();
        expect(images.config.cacheKey, 'debrifyImageCache');
        expect(logos.config.cacheKey, 'debrifyIptvLogoCache');
        expect(images.config.maxNrOfCacheObjects, 1000);
        expect(logos.config.maxNrOfCacheObjects, 2000);
        expect(images.budget.expanded, isFalse);
        final poster =
            await images.putFile('poster', Uint8List(7)) as ArtworkCacheFile;
        final logo =
            await logos.putFile('logo', Uint8List(3)) as ArtworkCacheFile;
        expect(await DebrifyImageCache.sizeBytes(), 10);
        for (final mb in BrowsingCacheOptions.artworkSizesMb) {
          await BrowsingCachePreferences.update(
            BrowsingCachePreferences.current.copyWith(
              expandedArtwork: true,
              artworkSizeMb: mb,
            ),
          );
          // The registered listener applies preferences without rebuilding managers.
          await Future<void>.delayed(Duration.zero);
          expect(images.budget.expanded, isTrue);
          expect(images.budget.budgetBytes, mb * 1024 * 1024);
          expect(identical(DebrifyImageCache.manager, images), isTrue);
          expect(identical(DebrifyImageCache.iptvLogos, logos), isTrue);
        }
        await DebrifyImageCache.clear();
        expect(await images.getFileFromCache('poster'), isNull);
        expect(await logos.getFileFromCache('logo'), isNull);
        expect(await poster.readAsBytes(), Uint8List(7));
        expect(await logo.readAsBytes(), Uint8List(3));
        poster.release();
        logo.release();
        // Production handoff window is bounded; deterministic readers released.
        await Future<void>.delayed(const Duration(milliseconds: 5100));
        expect(await DebrifyImageCache.sizeBytes(), 0);
        await BrowsingCachePreferences.update(
          BrowsingCachePreferences.current.copyWith(expandedArtwork: false),
        );
        await DebrifyImageCache.applyPolicy();
        expect(images.budget.expanded, isFalse);
      } finally {
        await images.budget.dispose();
        await images.dispose();
        await logos.dispose();
        PathProviderPlatform.instance = previous;
        await directory.delete(recursive: true);
      }
    },
  );
}
