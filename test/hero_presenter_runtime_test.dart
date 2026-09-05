import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart' show pumpFavourites, closeFavourites;
import 'hero_presenter_origin_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'origin live candidate ladder and same-title shell restore use mounted row callbacks',
    (tester) async {
      final io = HeroOriginTransport();
      await http.runWithClient(() async {
        await prepareHero(tester, ['tt9910501']);
        await tester.runAsync(
          () => StorageService.setIptvChannelFavorited(
            'stremio-tv://com.linvo.cinemeta/hero-live',
            true,
            channelName: 'Origin Live',
          ),
        );
        await mountHero(tester);
        io.complete('tt9910501');
        await pumpFavourites(tester);
        expect(
          MainPageBridge.tvAmbientArt.value,
          'https://hero-art.invalid/tt9910501.jpg',
        );
        final cell = tester
            .widgetList<ArtPoster>(find.byType(ArtPoster))
            .firstWhere((p) => p.title == 'Origin Live');
        cell.focusNode.requestFocus();
        await tester.pump();
        expect(cell.focusNode.hasFocus, isTrue);
        expect(MainPageBridge.tvAmbientArt.value, isNull);
        expect(MainPageBridge.tvHeroTint.value, isNull);
        expect(io.streamRequests, hasLength(1));
        io.streams.complete(
          http.Response(
            jsonEncode({
              'streams': [
                {'url': 'https://hero-live.invalid/first.m3u8'},
                {'url': 'https://hero-live.invalid/second.m3u8'},
              ],
            }),
            200,
          ),
        );
        await tester.pump();
        await tester.pump();
        HeroTrailerBackdrop live() => tester
            .widgetList<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop))
            .singleWhere((w) => w.live);
        expect(live().videoUrl, 'https://hero-live.invalid/first.m3u8');
        // Exercise the real widget->host callbacks; do not claim these callbacks
        // prove native decoding. Stay before the backdrop's 300ms engine start.
        live().onPlayingChanged!(true);
        await tester.pump();
        expect(MainPageBridge.tvStageLightsOff.value, isTrue);
        live().onPlaybackFailed!();
        await tester.pump();
        expect(live().videoUrl, 'https://hero-live.invalid/second.m3u8');
        live().onPlaybackFailed!();
        await tester.pump();
        expect(
          tester
              .widgetList<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop))
              .where((w) => w.live),
          isEmpty,
        );
        await focusHero(tester, 'tt9910501');
        expect(
          MainPageBridge.tvAmbientArt.value,
          'https://hero-art.invalid/tt9910501.jpg',
        );
        expect(MainPageBridge.tvStageLightsOff.value, isFalse);
        io.streams = Completer<http.Response>();
        cell.focusNode.requestFocus();
        await tester.pump();
        expect(
          io.streamRequests,
          hasLength(2),
          reason: 'Exhaustion invalidates the real service candidate cache.',
        );
        await focusHero(tester, 'tt9910501');
        io.streams.complete(
          http.Response(
            '{"streams":[{"url":"https://hero-live.invalid/stale.m3u8"}]}',
            200,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widgetList<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop))
              .where((w) => w.live),
          isEmpty,
        );
        expect(
          MainPageBridge.tvAmbientArt.value,
          'https://hero-art.invalid/tt9910501.jpg',
        );
        await closeFavourites(tester);
        expect(tester.takeException(), isNull);
      }, () => MockClient(io.send));
    },
  );

  testWidgets(
    'origin route/sidebar rearm and content launch suppress actual host trailer',
    (tester) async {
      final io = HeroOriginTransport();
      await http.runWithClient(() async {
        await prepareHero(tester, ['tt9910301', 'tt9910302'], trailers: true);
        await mountHero(tester);
        final a = heroItem(tester).value!.id;
        final b = a == 'tt9910301' ? 'tt9910302' : 'tt9910301';
        expect(
          io.requests,
          [a],
          reason: 'Enrichment has started; 2.4s trailer dwell has not.',
        );
        final navigator = Navigator.of(
          tester.element(find.byType(SearchScreen)),
        );
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(io.requests, [
          a,
        ], reason: 'A pushed page cancels the trailer dwell.');
        navigator.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2399));
        expect(io.requests, [a]);
        await tester.pump(const Duration(milliseconds: 1));
        expect(io.requests, [
          a,
          a,
        ], reason: 'Route return rearms the same title.');

        MainPageBridge.notifyPlayerLaunching();
        io.complete(a);
        await pumpFavourites(tester);
        expect(
          io.otherRequests.where((u) => u.host == 'graphql.imdb.com'),
          isEmpty,
          reason:
              'Cancelled in-flight metadata cannot continue into trailer resolution.',
        );
        MainPageBridge.notifyTvSidebarFocusChanged(true);
        MainPageBridge.notifyTvSidebarFocusChanged(false);
        await tester.pump(const Duration(seconds: 3));
        expect(
          io.otherRequests.where((u) => u.host == 'graphql.imdb.com'),
          isEmpty,
          reason: 'Sidebar return must not lift content-launch suppression.',
        );

        await focusHero(tester, b);
        await tester.pump(const Duration(milliseconds: 260));
        await tester.pump(const Duration(milliseconds: 140));
        expect(io.requests, [a, a, b]);
        MainPageBridge.notifyTvSidebarFocusChanged(true);
        await tester.pump(const Duration(seconds: 3));
        expect(io.requests, [a, a, b]);
        MainPageBridge.notifyTvSidebarFocusChanged(false);
        await tester.pump(const Duration(milliseconds: 2399));
        expect(io.requests, [a, a, b]);
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          io.requests,
          [a, a, b, b],
          reason: 'A new title lifts suppression; sidebar exit rearms it.',
        );
        MainPageBridge.notifyPlayerLaunching();
        io.complete(b);
        await pumpFavourites(tester);
        await closeFavourites(tester);
        expect(tester.takeException(), isNull);
      }, () => MockClient(io.send));
    },
  );

  testWidgets(
    'origin dialog cover blocks timed resolve without PageRoute notification',
    (tester) async {
      final io = HeroOriginTransport();
      await http.runWithClient(() async {
        await prepareHero(tester, ['tt9910401'], trailers: true);
        await mountHero(tester);
        final context = tester.element(find.byType(SearchScreen));
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Modal cover')),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(io.requests, ['tt9910401']);
        Navigator.of(context).pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        // The restored CW focus rearms the same title through _setHero even
        // though the PageRoute-only observer does not observe this dialog.
        expect(io.requests, ['tt9910401', 'tt9910401']);
        MainPageBridge.notifyPlayerLaunching();
        io.complete('tt9910401');
        await pumpFavourites(tester);
        await closeFavourites(tester);
        expect(tester.takeException(), isNull);
      }, () => MockClient(io.send));
    },
  );
}
