import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'warm decoded rails: reopen, equivalent replacement, and focus frames',
    (tester) async {
      ProfileRuntime.initializeLegacy();
      // All preference storage stays inside the in-memory test platform.
      final prefs = jsonEncode(MetadataPreferences(features: {}).toJson());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (call) async => call.method == 'getAll'
            ? {'flutter.${MetadataPreferencesService.key}': prefs}
            : true,
      );
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSize = 140;
      cache.maximumSizeBytes = 56 * 1024 * 1024;
      cache.clear();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 16, 9),
        Paint()..color = Colors.green,
      );
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(16, 9));
      picture.dispose();
      final items = List.generate(
        72,
        (i) => StremioMeta(
          id: 'tt${1000 + i}',
          type: 'movie',
          name: 'Synthetic $i',
          background: 'https://synthetic.invalid/$i.png',
        ),
      );
      // Exactly the installed rail's 540px/DPR1 landscape decode key: ceil(92*1.6*1.1).
      for (final item in items) {
        final provider = ResizeImage.resizeIfNeeded(
          162,
          null,
          CachedNetworkImageProvider(item.background!),
        );
        final key = await provider.obtainKey(ImageConfiguration.empty);
        cache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image!.clone())),
          ),
        );
      }
      await tester.pump();
      final key = GlobalKey<CollectionTvRailsState>();
      Widget rails(List<StremioMeta> data) => MaterialApp(
        home: Scaffold(
          body: CollectionTvRails(
            key: key,
            rails: [
              CollectionTvRail(
                id: 'one',
                title: 'One',
                items: data,
                loading: false,
                onLoadMore: () {},
              ),
            ],
            landscapeCards: true,
            onOpen: (_) {},
            onExitTop: () {},
          ),
        ),
      );
      int frames() => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .where((i) => i.image != null)
          .length;
      final records = <String, int>{};
      await tester.pumpWidget(rails(items));
      records['first_mount_frame'] = frames();
      await tester.pumpAndSettle();
      records['settled'] = frames();
      expect(records['settled'], greaterThan(0));
      final artworkFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_RailArtwork',
      );
      final firstState = tester.state(artworkFinder.first);
      final beforeKeys = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .toList();
      key.currentState!.focusFirst();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      records['focus_step_frame'] = frames();
      expect(identical(firstState, tester.state(artworkFinder.first)), isTrue);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((i) => i.image)
            .toList(),
        beforeKeys,
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(rails(items));
      records['same_object_rebuild_frame'] = frames();
      await tester.pumpWidget(
        rails(items.map((i) => StremioMeta.fromJson(i.toJson())).toList()),
      );
      records['equivalent_object_rebuild_frame'] = frames();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        rails(
          items
              .map(
                (i) => StremioMeta.fromJson({...i.toJson(), 'imdb_id': i.id}),
              )
              .toList(),
        ),
      );
      records['late_identity_same_artwork_frame'] = frames();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(rails(items));
      records['warm_reopen_first_frame'] = frames();
      await tester.pumpAndSettle();
      records['warm_reopen_settled'] = frames();
      expect(records['warm_reopen_first_frame'], records['settled']);
      expect(records['warm_reopen_settled'], greaterThan(0));
      expect(records['equivalent_object_rebuild_frame'], records['settled']);
      expect(records['late_identity_same_artwork_frame'], records['settled']);
      final images = tester.widgetList<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(images.first.fadeOutDuration, const Duration(seconds: 1));
      // A synchronous decoded hit bypasses Octo's fade despite the configured duration.
      expect(
        find.descendant(
          of: find.byType(CachedNetworkImage),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      // ignore: avoid_print
      print('FRAME_RECEIPT ${jsonEncode(records)}');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectionTvRails(
              key: key,
              rails: List.generate(
                12,
                (r) => CollectionTvRail(
                  id: 'row$r',
                  title: 'Row $r',
                  items: items.skip(r * 6).take(6).toList(),
                  loading: false,
                  onLoadMore: () {},
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
      int visibleBlanks() {
        var blanks = 0;
        for (final element in artworkFinder.evaluate()) {
          final box = element.renderObject as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (!rect.overlaps(const Rect.fromLTWH(0, 0, 960, 540))) continue;
          final raw = find.descendant(
            of: find.byElementPredicate((e) => e == element),
            matching: find.byType(RawImage),
          );
          if (!tester.widgetList<RawImage>(raw).any((i) => i.image != null)) {
            blanks++;
          }
        }
        return blanks;
      }

      final vertical = <int>[];
      for (final direction in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
      ]) {
        for (var step = 0; step < 10; step++) {
          await tester.sendKeyEvent(direction);
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 33));
            vertical.add(visibleBlanks());
          }
        }
      }
      // ignore: avoid_print
      print(
        'VERTICAL_RECEIPT frames=${vertical.length} blankFrames=${vertical.where((n) => n > 0).length} maxBlanks=${vertical.reduce((a, b) => a > b ? a : b)} cache=${cache.currentSize}',
      );
      expect(vertical, everyElement(0));
      await tester.pumpWidget(const SizedBox());
      cache.clear();
      cache.clearLiveImages();
      // Clearing decoded images must still reach the image loader. A warm
      // presentation retains URLs/policy only; it cannot resurrect old pixels.
      final reads = <Completer<ImageInfo>>[];
      for (final item in items) {
        final provider = ResizeImage.resizeIfNeeded(
          162,
          null,
          CachedNetworkImageProvider(item.background!),
        );
        final read = Completer<ImageInfo>();
        reads.add(read);
        cache.putIfAbsent(
          await provider.obtainKey(ImageConfiguration.empty),
          () => OneFrameImageStreamCompleter(read.future),
        );
      }
      await tester.pumpWidget(rails(items));
      expect(find.byType(CachedNetworkImage), findsWidgets);
      expect(frames(), 0);
      for (final read in reads) {
        read.complete(ImageInfo(image: image!.clone()));
      }
      await tester.pumpAndSettle();
      expect(frames(), records['settled']);
      await tester.pumpWidget(const SizedBox());
      cache.clear();
      cache.clearLiveImages();
      image!.dispose();
    },
  );
}
