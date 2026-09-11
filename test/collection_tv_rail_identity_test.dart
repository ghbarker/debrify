import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalHttp extends HttpOverrides {}

void main() {
  setUp(() {
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    StremioService.instance.invalidateCache();
  });

  Future<void> mount(
    WidgetTester tester,
    StremioMeta item, {
    bool hide = false,
  }) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionTvRails(
            rails: [
              CollectionTvRail(
                id: 'rail',
                title: 'Shelf',
                items: [item],
                loading: false,
                onLoadMore: () {},
              ),
            ],
            landscapeCards: true,
            showCardIdentity: !hide,
            onOpen: (_) {},
            onExitTop: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final hide in [false, true]) {
    for (final state in ['missing', 'loading', 'success', 'error']) {
      testWidgets('identity art=$state hide=$hide retains card bounds', (
        tester,
      ) async {
        final url = 'https://example.invalid/$state-$hide.png';
        final item = StremioMeta(
          id: '$state-$hide',
          type: 'movie',
          name: 'Readable title',
          imdbRating: 8.4,
          background: state == 'missing' ? null : url,
        );
        final pending = Completer<ImageInfo>();
        if (state != 'missing') {
          // Drive the real CachedNetworkImage/OctoImage image stream at its
          // decoded cache key. No widget builders or production hooks replaced.
          final card = const Size(92 * 1.6, 92 * 1.6 / (16 / 9));
          final provider = ResizeImage.resizeIfNeeded(
            (card.width * 1.1).ceil(),
            null,
            CachedNetworkImageProvider(
              url,
              cacheManager: DebrifyImageCache.manager,
            ),
          );
          final key = await provider.obtainKey(ImageConfiguration.empty);
          PaintingBinding.instance.imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(pending.future),
          );
        }
        await mount(tester, item, hide: hide);
        if (state == 'success') {
          late ui.Image decoded;
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            ui.Canvas(
              recorder,
            ).drawColor(const Color(0xFF345678), ui.BlendMode.src);
            final picture = recorder.endRecording();
            decoded = await picture.toImage(2, 2);
            picture.dispose();
          });
          pending.complete(ImageInfo(image: decoded));
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<RawImage>(find.byType(RawImage))
                .any((image) => image.image != null),
            isTrue,
          );
        } else if (state == 'error') {
          pending.completeError(StateError('synthetic image failure'));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.image_outlined), findsOneWidget);
        } else {
          expect(find.byIcon(Icons.image_outlined), findsOneWidget);
        }
        expect(
          find.text('Readable title'),
          hide ? findsNothing : findsOneWidget,
        );
        expect(find.text('\u2605 8.4'), hide ? findsNothing : findsOneWidget);
        expect(
          tester.getSize(
            find.byKey(ValueKey('collection_card_rail_${item.id}')),
          ),
          const Size(92 * 1.6, 92 * 1.6 / (16 / 9)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
    }
  }

  testWidgets(
    'selected metadata title and source rating survive policy changes',
    (tester) async {
      const item = StremioMeta(
        id: 'tt1234567',
        type: 'movie',
        name: 'Original title',
        imdbRating: 7.2,
        background: 'https://example.invalid/blocked.jpg',
      );
      late StremioAddon addon;
      // Warm the production metadata lookup through a local synthetic addon.
      // The mounted mixin must consume the selected presentation, not raw item.
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            request.response.write(
              jsonEncode({
                'meta': {
                  'id': item.id,
                  'type': 'movie',
                  'name': 'Selected title',
                  'description': 'Selected plot',
                  'imdbRating': 9.9,
                },
              }),
            );
            await request.response.close();
          });
          final base = 'http://127.0.0.1:${server.port}';
          addon = StremioAddon(
            id: 'identity',
            name: 'Synthetic metadata',
            baseUrl: base,
            manifestUrl: '$base/manifest.json',
            resources: const ['meta'],
            types: const ['movie'],
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'stremio_addons_v1',
            jsonEncode([addon.toJson()]),
          );
          try {
            final result = await StremioService.instance.fetchMetaDetails(
              imdbId: item.id,
              type: item.type,
              providerOverride: StremioService.metadataProviderValue(addon),
            );
            expect(result?.name, 'Selected title');
          } finally {
            await server.close(force: true);
          }
        }, _LocalHttp()),
      );
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {
            MetadataCategory.information:
                'addon:${StremioService.metadataProviderValue(addon)}',
            MetadataCategory.backgrounds:
                'addon:${StremioService.metadataProviderValue(addon)}',
          },
          fallback: false,
        ),
      );
      await mount(tester, item);
      await tester.pumpAndSettle();
      expect(find.text('Selected title'), findsOneWidget);
      expect(find.text('Original title'), findsNothing);
      expect(find.text('\u2605 7.2'), findsOneWidget);
      expect(find.text('\u2605 9.9'), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {
            MetadataCategory.backgrounds:
                'addon:${StremioService.metadataProviderValue(addon)}',
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original title'), findsOneWidget);
      expect(find.text('Selected title'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
