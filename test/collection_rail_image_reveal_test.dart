import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('controlled image reveal and warm remount, reduced=$reduced', (
      tester,
    ) async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SharedPreferences.setMockInitialValues({
        MetadataPreferencesService.key: jsonEncode(
          MetadataPreferences(features: {}).toJson(),
        ),
      });
      MetadataPreferencesService.revision.value++;
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 16, 9),
        Paint()..color = Colors.green,
      );
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() => picture.toImage(16, 9)))!;
      picture.dispose();
      const item = StremioMeta(
        id: 'tt100001',
        type: 'movie',
        name: 'Synthetic',
        background: 'https://synthetic.invalid/reveal.png',
      );
      final provider = ResizeImage.resizeIfNeeded(
        162,
        null,
        const CachedNetworkImageProvider(
          'https://synthetic.invalid/reveal.png',
        ),
      );
      final arrival = Completer<ImageInfo>();
      // A pending image stream gives precise control over the first decoded
      // frame, with no network, file cache timing, or production injection seam.
      cache.putIfAbsent(
        await provider.obtainKey(ImageConfiguration.empty),
        () => OneFrameImageStreamCompleter(arrival.future),
      );
      Widget screen() => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(960, 540),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: CollectionTvRails(
              rails: [
                CollectionTvRail(
                  id: 'one',
                  title: 'One',
                  items: [item],
                  loading: false,
                  onLoadMore: () {},
                ),
              ],
              landscapeCards: true,
              onOpen: (_) {},
              onExitTop: () {},
            ),
          ),
        ),
      );
      Finder withinImage(Finder finder) => find.descendant(
        of: find.byType(CachedNetworkImage),
        matching: finder,
      );
      double imageOpacity() {
        final fades = tester.widgetList<FadeTransition>(
          withinImage(find.byType(FadeTransition)),
        );
        expect(fades, hasLength(1));
        return fades.single.opacity.value;
      }

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(withinImage(find.byIcon(Icons.image_outlined)), findsOneWidget);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((i) => i.image != null),
        isFalse,
      );
      arrival.complete(ImageInfo(image: pixels.clone()));
      await tester.pump();
      await tester.pump();
      // There is one revealing image, no opaque placeholder over it, and no
      // second fading layer hiding the image after the short reveal completes.
      expect(withinImage(find.byIcon(Icons.image_outlined)), findsNothing);
      expect(imageOpacity(), reduced ? 1 : 0);
      await tester.pump(const Duration(milliseconds: 60));
      final middle = imageOpacity();
      if (reduced) {
        expect(middle, 1);
      } else {
        expect(middle, greaterThan(0));
        expect(middle, lessThan(1));
      }
      await tester.pump(const Duration(milliseconds: 60));
      expect(imageOpacity(), 1);
      expect(withinImage(find.byIcon(Icons.image_outlined)), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      // Same authorized source and synchronous decoded hit: no placeholder or
      // replayed fade even on the first frame of a new rail instance.
      expect(
        tester.widgetList<RawImage>(find.byType(RawImage)).single.image,
        isNotNull,
      );
      expect(withinImage(find.byIcon(Icons.image_outlined)), findsNothing);
      expect(withinImage(find.byType(FadeTransition)), findsNothing);
      await tester.pumpAndSettle();
      // Pixels remaining in memory do not authorize a catalog image after the
      // user selects a custom provider with fallback disabled.
      await MetadataPreferencesService.save(
        MetadataPreferences(
          features: {},
          providers: {MetadataCategory.backgrounds: 'addon:${'a' * 64}'},
          fallback: false,
        ),
      );
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      cache.clear();
      cache.clearLiveImages();
      pixels.dispose();
    });
  }
}
