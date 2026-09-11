import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:debrify/widgets/scroll_deferred_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('nested shelf image scheduling observes the vertical owner', (
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
    final items = List.generate(
      12,
      (i) => StremioMeta(
        id: 'tt$i',
        type: 'movie',
        name: 'Synthetic $i',
        background: 'https://synthetic.invalid/vertical-$i.png',
      ),
    );
    for (final item in items) {
      final provider = ResizeImage.resizeIfNeeded(
        162,
        null,
        CachedNetworkImageProvider(item.background!),
      );
      cache.putIfAbsent(
        await provider.obtainKey(ImageConfiguration.empty),
        () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
      );
    }
    final key = GlobalKey<CollectionTvRailsState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionTvRails(
            key: key,
            landscapeCards: true,
            onOpen: (_) {},
            onExitTop: () {},
            rails: [
              for (var i = 0; i < items.length; i++)
                CollectionTvRail(
                  id: '$i',
                  title: 'Row $i',
                  items: [items[i]],
                  loading: false,
                  onLoadMore: () {},
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.focusFirst();
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final lists = tester.widgetList<ListView>(find.byType(ListView));
    final vertical = lists
        .singleWhere((list) => list.scrollDirection == Axis.vertical)
        .controller!
        .position;
    expect(vertical.isScrollingNotifier.value, isTrue);
    expect(
      lists
          .where((list) => list.scrollDirection == Axis.horizontal)
          .every(
            (list) => !list.controller!.position.isScrollingNotifier.value,
          ),
      isTrue,
    );
    final gates = tester.widgetList<ScrollDeferredImage>(
      find.byType(ScrollDeferredImage),
    );
    expect(gates, isNotEmpty);
    expect(
      gates.every(
        (gate) => identical(gate.scrolling, vertical.isScrollingNotifier),
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    cache.clear();
    cache.clearLiveImages();
  });
}
