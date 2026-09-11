import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/main.dart'
    show debugCapImageCache, debugDisposeImageCachePolicy;
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tvos_device.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => _SourceFrameCache();
}

/// Real ImageCache admission, LRU and byte accounting; controlled source frames
/// replace the disk/network decoder only on misses. Clones deliberately share
/// pixels: this tests per-key decoded-cache accounting, not GPU/RSS usage.
class _SourceFrameCache extends ImageCache {
  ui.Image? source;
  final loads = <Object, int>{};
  final pending = <Completer<ImageInfo>>[];
  bool hold = false;

  @override
  ImageStreamCompleter? putIfAbsent(
    Object key,
    ImageStreamCompleter Function() loader, {
    ImageErrorListener? onError,
  }) => super.putIfAbsent(key, () {
    loads.update(key, (n) => n + 1, ifAbsent: () => 1);
    final frame = Completer<ImageInfo>();
    if (hold) {
      pending.add(frame);
    } else {
      frame.complete(ImageInfo(image: source!.clone()));
    }
    return OneFrameImageStreamCompleter(frame.future);
  }, onError: onError);

  void completeFrames() {
    for (final frame in pending) {
      frame.complete(ImageInfo(image: source!.clone()));
    }
    pending.clear();
  }
}

void main() {
  final binding = _Binding();
  final cache = binding.imageCache as _SourceFrameCache;

  setUp(() {
    ProfileRuntime.initializeLegacy();
    PlatformUtil.debugSetAndroidTvCached(true);
    PlatformUtil.debugSetTvOS(false);
    TvosDevice.debugOverride(false);
    cache.maximumSize = 1000;
    cache.maximumSizeBytes = 100 << 20;
    final prefs = jsonEncode(MetadataPreferences(features: {}).toJson());
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll'
          ? {'flutter.${MetadataPreferencesService.key}': prefs}
          : true,
    );
  });
  tearDown(() {
    debugDisposeImageCachePolicy();
    cache.completeFrames();
    cache.clear();
    cache.clearLiveImages();
    cache.source?.dispose();
    cache.source = null;
    cache.loads.clear();
    cache.hold = false;
    cache.maximumSize = 1000;
    cache.maximumSizeBytes = 100 << 20;
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    TvosDevice.debugOverride(false);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      null,
    );
  });

  testWidgets('TV and failed Android probe retain bounded TV policy', (
    tester,
  ) async {
    await debugCapImageCache();
    expect(cache.maximumSize, 256);
    expect(cache.maximumSizeBytes, 56 << 20);
    cache.maximumSize = 1000;
    cache.maximumSizeBytes = 100 << 20;
    // PlatformUtil returns false with lastProbeFailed=true after a channel
    // exception, rather than caching a successful non-TV verdict.
    PlatformUtil.debugSetAndroidTvCached(false);
    await debugCapImageCache(isAndroid: true, lastProbeFailed: true);
    expect(cache.maximumSize, 256);
    expect(cache.maximumSizeBytes, 56 << 20);
  });

  testWidgets(
    'successful non-TV and non-Android failure leave cache untouched',
    (tester) async {
      PlatformUtil.debugSetAndroidTvCached(false);
      for (final android in [true, false]) {
        await debugCapImageCache(isAndroid: android, lastProbeFailed: !android);
        expect(cache.maximumSize, 1000);
        expect(cache.maximumSizeBytes, 100 << 20);
      }
    },
  );

  testWidgets('tvOS retains its normal and low-memory limits', (tester) async {
    PlatformUtil.debugSetAndroidTvCached(false);
    PlatformUtil.debugSetTvOS(true);
    await debugCapImageCache();
    expect(cache.maximumSize, 256);
    expect(cache.maximumSizeBytes, 56 << 20);
    TvosDevice.debugOverride(true);
    await debugCapImageCache();
    expect(cache.maximumSize, 100);
    expect(cache.maximumSizeBytes, 36 << 20);
  });

  Future<void> sourceImage(WidgetTester tester, int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.green, BlendMode.src);
    final picture = recorder.endRecording();
    cache.source = await tester.runAsync(() => picture.toImage(width, height));
    picture.dispose();
  }

  void resolve(Object key) => cache.putIfAbsent(
    key,
    () => throw StateError('Source must be controlled by the probe'),
  );

  testWidgets('larger images still evict by bytes below the 256-entry limit', (
    tester,
  ) async {
    await debugCapImageCache();
    await sourceImage(tester, 1024, 1024); // 4 MiB per decoded key.
    for (var i = 0; i < 20; i++) {
      resolve('large-$i');
      await tester.pump();
    }
    expect(cache.currentSize, 14);
    expect(cache.currentSizeBytes, 56 << 20);
    resolve('large-19');
    await tester.pump();
    expect(cache.loads['large-19'], 1);
    resolve('large-0');
    await tester.pump();
    expect(cache.loads['large-0'], 2);
    expect(cache.currentSizeBytes, 56 << 20);
  });

  for (final oldCount in [false, true]) {
    testWidgets('19 rails revisit source frames: oldCount=$oldCount', (
      tester,
    ) async {
      await debugCapImageCache();
      if (oldCount) cache.maximumSize = 140; // Negative regression control.
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await sourceImage(tester, 324, 183);
      final key = GlobalKey<CollectionTvRailsState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectionTvRails(
              key: key,
              rails: List.generate(
                19,
                (r) => CollectionTvRail(
                  id: 'row$r',
                  title: 'Row $r',
                  loading: false,
                  onLoadMore: () {},
                  items: List.generate(
                    8,
                    (c) => StremioMeta(
                      id: 'tt${10000 + r * 8 + c}',
                      type: 'movie',
                      name: '$r/$c',
                      background: 'https://synthetic.invalid/$r/$c.png',
                    ),
                  ),
                ),
              ),
              landscapeCards: true,
              onOpen: (_) {},
              onExitTop: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.focusFirst();
      await tester.pumpAndSettle();
      Future<void> traverse(LogicalKeyboardKey direction) async {
        for (var r = 0; r < 18; r++) {
          await tester.sendKeyEvent(direction);
          await tester.pumpAndSettle();
        }
      }

      await traverse(LogicalKeyboardKey.arrowDown);
      expect(cache.loads.length, 152);
      expect(cache.loads.keys.whereType<ResizeImageKey>().length, 152);
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((image) => image.memCacheWidth),
        everyElement(324),
      );
      // Modest unrelated Home pressure with the same small decoded dimensions.
      for (var i = 0; i < 20; i++) {
        resolve('home-$i');
        await tester.pump();
      }
      expect(cache.currentSizeBytes, lessThan(56 << 20));
      final loadsBefore = cache.loads.values.fold<int>(0, (a, b) => a + b);
      cache.hold = true;
      await traverse(LogicalKeyboardKey.arrowUp);
      final revisits =
          cache.loads.values.fold<int>(0, (a, b) => a + b) - loadsBefore;
      int readyFrames() => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .where((w) => w.image != null)
          .length;
      final before = readyFrames();
      expect(cache.pending.length, revisits);
      expect(revisits, oldCount ? greaterThan(0) : 0);
      cache.completeFrames();
      await tester.pumpAndSettle();
      expect(readyFrames(), oldCount ? greaterThan(before) : before);
      expect(readyFrames(), greaterThan(0));
      // ignore: avoid_print
      print(
        '19_RAILS oldCount=$oldCount sourceRevisits=$revisits '
        'readyBefore=$before readyAfter=${readyFrames()} bytes=${cache.currentSizeBytes}',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
