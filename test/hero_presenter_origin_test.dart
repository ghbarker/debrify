import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search/continue_watching_row.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

// Transport only: the mounted SearchScreen owns the real debounce, enrichment,
// focus and shell publication. No presenter/State body is reproduced here.
class HeroOriginTransport {
  final requests = <String>[];
  final otherRequests = <Uri>[];
  final streamRequests = <Uri>[];
  Completer<http.Response> streams = Completer<http.Response>();
  final pending = <String, Completer<http.Response>>{};

  Future<http.Response> send(http.Request request) async {
    if (request.url.host == 'hero-meta.invalid') {
      if (request.url.pathSegments.first == 'stream') {
        streamRequests.add(request.url);
        return streams.future;
      }
      final id = request.url.pathSegments.last.replaceAll('.json', '');
      requests.add(id);
      return pending.putIfAbsent(id, Completer<http.Response>.new).future;
    }
    // No live provider/IMDb traffic or media decoder is required by this pin.
    otherRequests.add(request.url);
    return http.Response('{}', 404);
  }

  void complete(String id) => pending[id]!.complete(
    http.Response(
      jsonEncode({
        'meta': {
          'id': id,
          'type': 'movie',
          'name': 'Enriched $id',
          'description': 'Origin description $id',
          'imdbRating': '8.1',
          'background': 'https://hero-art.invalid/$id.jpg',
          'runtime': '101 min',
        },
      }),
      200,
    ),
  );
}

Future<void> prepareHero(
  WidgetTester tester,
  List<String> ids, {
  bool trailers = false,
}) async {
  await prepareFavourites(tester);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'stremio_addons_v1',
    jsonEncode([
      StremioAddon(
        id: 'com.linvo.cinemeta',
        name: 'Origin metadata',
        manifestUrl: 'https://hero-meta.invalid/manifest.json',
        baseUrl: 'https://hero-meta.invalid',
        resources: const ['meta', 'stream'],
        types: const ['movie', 'tv'],
      ).toJson(),
    ]),
  );
  StremioService.instance.invalidateCache();
  addTearDown(StremioService.instance.invalidateCache);
  await StorageService.setHomeContinueWatchingEnabled(true);
  await StorageService.setHomeHeroTrailerEnabled(trailers);
  for (final id in ids) {
    await StorageService.saveContinueWatchingItem(
      imdbId: id,
      title: 'Title $id',
      contentType: 'movie',
    );
  }
}

Future<void> mountHero(WidgetTester tester, {bool tv = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [appRouteObserver],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(0.8)),
        child: child!,
      ),
      home: SearchScreen(isTelevision: tv),
    ),
  );
  await pumpFavourites(tester);
  if (tv) {
    final row = tester
        .widgetList<ContinueWatchingRow>(find.byType(ContinueWatchingRow))
        .first
        .row;
    await focusHero(tester, row.items.first.id);
    await tester.pump(const Duration(milliseconds: 140));
  }
}

ValueListenable<StremioMeta?> heroItem(WidgetTester tester) => tester
    .widgetList<ValueListenableBuilder<StremioMeta?>>(
      find.byType(ValueListenableBuilder<StremioMeta?>),
    )
    .first
    .valueListenable;

Future<void> focusHero(WidgetTester tester, String id) async {
  final row = tester
      .widgetList<ContinueWatchingRow>(find.byType(ContinueWatchingRow))
      .firstWhere((w) => w.row.items.any((item) => item.id == id))
      .row;
  final node = row.nodes[row.items.indexWhere((item) => item.id == id)];
  node.requestFocus();
  await tester.pump();
  expect(node.hasFocus, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('origin actual host settles at 260ms and cancels A-B-A jiggle', (
    tester,
  ) async {
    final io = HeroOriginTransport();
    await http.runWithClient(() async {
      await prepareHero(tester, ['tt9910101', 'tt9910102']);
      await mountHero(tester);
      final selected = heroItem(tester);
      final a = selected.value!.id;
      final b = a == 'tt9910101' ? 'tt9910102' : 'tt9910101';
      await focusHero(tester, a);
      await focusHero(tester, b);
      await tester.pump(const Duration(milliseconds: 259));
      expect(selected.value!.id, a);
      await focusHero(tester, a);
      await tester.pump(const Duration(milliseconds: 300));
      expect(selected.value!.id, a);
      expect(io.requests, [a]);
      await focusHero(tester, b);
      await tester.pump(const Duration(milliseconds: 259));
      expect(selected.value!.id, a);
      await tester.pump(const Duration(milliseconds: 1));
      expect(selected.value!.id, b);
      await tester.pump(const Duration(milliseconds: 139));
      expect(io.requests, [a]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(io.requests, [a, b]);
      io.complete(b);
      await pumpFavourites(tester);
      expect(
        MainPageBridge.tvAmbientArt.value,
        'https://hero-art.invalid/$b.jpg',
      );
      expect(find.text('Origin description $b'), findsOneWidget);
      io.complete(a);
      await pumpFavourites(tester);
      expect(
        MainPageBridge.tvAmbientArt.value,
        'https://hero-art.invalid/$b.jpg',
      );
      expect(find.text('Origin description $a'), findsNothing);
      await closeFavourites(tester);
      expect(MainPageBridge.tvAmbientArt.value, isNull);
      expect(tester.takeException(), isNull);
    }, () => MockClient(io.send));
  });

  testWidgets(
    'origin pending enrichment cannot publish after actual host disposal',
    (tester) async {
      final io = HeroOriginTransport();
      await http.runWithClient(() async {
        await prepareHero(tester, ['tt9910201']);
        await mountHero(tester);
        expect(io.requests, ['tt9910201']);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final changes = <String?>[];
        void record() => changes.add(MainPageBridge.tvAmbientArt.value);
        MainPageBridge.tvAmbientArt.addListener(record);
        try {
          io.complete('tt9910201');
          await pumpFavourites(tester);
          expect(changes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          MainPageBridge.tvAmbientArt.removeListener(record);
        }
        await tester.pump(const Duration(seconds: 11));
      }, () => MockClient(io.send));
    },
  );
}
