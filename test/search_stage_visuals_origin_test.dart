import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart' show installCatalog;

// Real Home stages own the failed-backdrop memo. Public image cache eviction
// and an independent image request establish that a reused Flutter ImageCache
// entry cannot explain Canvas omitting the derived URL after Deck failed it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Deck failed backdrop survives Canvas remount beyond image caching',
      (tester) async {
    Future<void> phase(String name, Future<void> Function() action) async {
      debugPrint('VISUAL PHASE BEGIN $name');
      await action().timeout(const Duration(seconds: 25), onTimeout: () {
        throw TimeoutException('VISUAL PHASE TIMEOUT $name');
      });
      debugPrint('VISUAL PHASE END $name');
    }
    await phase('prepare', () => prepareFavourites(tester));
    await installCatalog();
    await HomePrefs.setHomeHeroSource((
      mode: HomeHeroSourceMode.auto,
      ids: const [],
    ));
    await StorageService.setTvHomeStyle('deck');
    await HomePrefs.setHomeCardOrientation(HomeCardOrientation.portrait);
    const id = 'tt9891891';
    const derived = 'https://images.metahub.space/background/medium/$id/img';
    const logo = 'https://images.metahub.space/logo/medium/$id/img';
    const poster = 'https://stage-visual-origin.invalid/poster.png';
    final unexpected = <String>[];
    var derivedRequests = 0;
    var posterRequests = 0;
    var catalogRequests = 0;

    Finder stageRail(String style) => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('$style-rail-');
    });
    Finder posterImages() => find.byWidgetPredicate((widget) =>
        widget is CachedNetworkImage && widget.imageUrl == poster);

    Future<void> evictImages() async {
      await tester.runAsync(() async {
        for (final url in [derived]) {
          debugPrint('VISUAL PHASE BEGIN evict $url');
          await CachedNetworkImage.evictFromCache(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('VISUAL EVICT TIMEOUT $url'),
          );
          debugPrint('VISUAL PHASE END evict $url');
        }
      });
      // Also discard size-specific ResizeImage keys and live cache entries.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      expect(PaintingBinding.instance.imageCache.currentSize, 0);
      expect(PaintingBinding.instance.imageCache.liveImageCount, 0);
    }

    await http.runWithClient(() async {
      try {
        await phase('mount Home', () => mountFavourites(tester));
        expect(stageRail('deck'), findsOneWidget);
        final deckCell = tester.widget<BoardCell>(find.byType(BoardCell));
        expect(deckCell.artUrl, isNull);
        expect(deckCell.aspectRatio, 2 / 3);
        expect(derivedRequests, 1);
        expect(posterRequests, greaterThan(0));
        expect(posterImages(), findsWidgets);
        // Unlike the shelf's poster, this descendant is built only after the
        // actual backdrop errorWidget has remembered its failed derived URL.
        final derivedBackdrop = find.byWidgetPredicate((widget) {
          final key = widget.key;
          return widget is CachedNetworkImage && widget.imageUrl == derived &&
              key is ValueKey<String> && key.value.startsWith('$derived-');
        });
        expect(derivedBackdrop, findsOneWidget);
        expect(find.descendant(of: derivedBackdrop, matching: posterImages()),
            findsOneWidget);
        expect(unexpected, isEmpty);
        await phase('close Home', () => closeFavourites(tester));
        await phase('evictImages', evictImages);

        // Positive control through the real public image widget/cache stack:
        // the SAME failed URL must perform HTTP again after public eviction.
        debugPrint('VISUAL PHASE BEGIN control mount');
        await tester.pumpWidget(MaterialApp(
          home: CachedNetworkImage(
            imageUrl: derived,
            errorWidget: (_, __, ___) => const Text('image control failed'),
          ),
        ));
        await pumpFavourites(tester);
        debugPrint('VISUAL PHASE END control mount');
        expect(derivedRequests, 2);
        expect(find.text('image control failed'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFavourites(tester);
        await phase('evictImages', evictImages);

        final posterBeforeCanvas = posterRequests;
        await StorageService.setTvHomeStyle('canvas');
        await phase('mount Home', () => mountFavourites(tester));
        expect(stageRail('canvas'), findsOneWidget);
        expect(stageRail('deck'), findsNothing);
        final canvasCell = tester.widget<BoardCell>(find.byType(BoardCell));
        expect(canvasCell.artUrl, isNull);
        expect(canvasCell.aspectRatio, 2 / 3);
        expect(derivedRequests, 2,
            reason: 'Canvas must reuse the production failed-derived memo');
        expect(posterRequests, greaterThan(posterBeforeCanvas),
            reason: 'The remount must still fetch its fallback after eviction');
        expect(posterImages(), findsWidgets);
        // The outer art widget itself now selects the poster. An old failed
        // ImageProvider could hide IO, but cannot choose this production key.
        expect(find.byWidgetPredicate((widget) {
          final key = widget.key;
          return widget is CachedNetworkImage && widget.imageUrl == poster &&
              key is ValueKey<String> && key.value.startsWith('$poster-');
        }), findsOneWidget);
        // Both mounts reuse StremioService's same-URL, five-minute page memo.
        expect(catalogRequests, 1);
        expect(unexpected, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await phase('close Home', () => closeFavourites(tester));
      }
    }, () => MockClient((request) async {
      final url = request.url.toString();
      if (request.method == 'GET' && url ==
          'https://board-origin.invalid/catalog/movie/rail.json') {
        catalogRequests++;
        return http.Response(jsonEncode({
          'metas': [{
            'id': id,
            'type': 'movie',
            'name': 'Shared visual origin',
            'poster': poster,
            'background': '',
          }],
        }), 200, headers: {'content-type': 'application/json'});
      }
      if (request.method == 'GET' && url == derived) {
        derivedRequests++;
        return http.Response('', 404);
      }
      if (request.method == 'GET' && url == poster) {
        posterRequests++;
        return http.Response('', 404);
      }
      if (request.method == 'GET' && url == logo) {
        return http.Response('', 404);
      }
      unexpected.add('${request.method} $url');
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

