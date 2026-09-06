import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search/stage_visuals.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;

const _art = 'https://stage-favourites.invalid';

Future<void> _prepare(WidgetTester tester) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('canvas');
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
  // The trailer preference does not disable live IPTV preview. The second
  // case focuses VOD only; live artwork is rendered without focusing it.
}

List<ArtPoster> _posters(WidgetTester tester) =>
    tester.widgetList<ArtPoster>(find.byType(ArtPoster)).toList();

void _identity(WidgetTester tester, String title, String subtitle, String art,
    {BoxFit fit = BoxFit.cover}) {
  final finder = find.byType(StageFavIdentity);
  expect(finder, findsOneWidget);
  final identity = tester.widget<StageFavIdentity>(finder);
  expect(identity.fav.title, title);
  expect(identity.fav.subtitle, subtitle);
  expect(identity.fav.art, art);
  expect(identity.fav.fit, fit);
  expect(find.descendant(of: finder, matching: find.text(title)), findsOneWidget);
  expect(find.descendant(of: finder, matching: find.text(subtitle)), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Canvas favourites keep watchlist and playlist values, focus and release menu',
      (tester) async {
    await _prepare(tester);
    await MyWatchlistStore.setMyWatchlistItem(const StremioMeta(
      id: 'stage-fav-movie', type: 'movie', name: 'Stage Saved Movie',
      poster: '$_art/movie-poster', background: '$_art/movie-wide',
    ), true);
    await PlaybackProgressStore.savePlaylistItemsRaw([
      {'title': 'Older Stage Playlist', 'kind': 'single', 'addedAt': 1,
        'id': 'stage-old', 'posterUrl': '$_art/old-poster'},
      {'title': 'Newer Stage Playlist', 'kind': 'single', 'addedAt': 2,
        'id': 'stage-new', 'posterUrl': '$_art/new-poster'},
    ]);
    final unexpected = <String>[];
    const images = {
      '$_art/movie-poster', '$_art/movie-wide',
      '$_art/old-poster', '$_art/new-poster',
      'https://images.metahub.space/logo/medium/stage-fav-movie/img',
      'https://images.metahub.space/background/medium/stage-fav-movie/img',
    };
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        final saved = _posters(tester).single;
        expect(saved.title, 'Stage Saved Movie');
        expect(saved.imageUrl, '$_art/movie-poster');
        expect(saved.imageFit, BoxFit.cover);
        expect(saved.ringColor, Colors.white);
        expect(saved.showTitle, isTrue);
        expect(saved.focusNode.debugLabel, 'search_watchlist_movie_0');
        saved.focusNode.requestFocus();
        await pumpFavourites(tester);
        _identity(tester, saved.title, 'MY WATCHLIST · MOVIE', '$_art/movie-wide');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        final playlist = _posters(tester);
        expect(playlist.map((p) => p.title),
            ['Newer Stage Playlist', 'Older Stage Playlist']);
        expect(playlist.map((p) => p.imageUrl),
            ['$_art/new-poster', '$_art/old-poster']);
        expect(playlist.map((p) => p.focusNode.debugLabel),
            ['search_playlistfav_0', 'search_playlistfav_1']);
        final first = playlist.first.focusNode;
        expect(FocusManager.instance.primaryFocus, same(first));
        _identity(tester, playlist.first.title, 'PLAYLIST · SAVED', '$_art/new-poster');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await pumpFavourites(tester);
        expect(_posters(tester).single.focusNode, same(saved.focusNode));
        expect(FocusManager.instance.primaryFocus, same(saved.focusNode));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFavourites(tester);
        expect(_posters(tester).first.focusNode, same(first));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Saved item. Choose your next step.'), findsNothing);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await pumpFavourites(tester);
        expect(find.text('Saved item. Choose your next step.'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Files'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        Navigator.of(tester.element(find.text('Play'))).pop();
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus, same(first));
        // The same public card path clears a pending Select on focus loss.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus, same(playlist.last.focusNode));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await pumpFavourites(tester);
        expect(find.text('Saved item. Choose your next step.'), findsNothing);
        _identity(tester, playlist.last.title, 'PLAYLIST · SAVED', '$_art/old-poster');
        expect(unexpected, isEmpty);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      if (request.method == 'GET' && images.contains(request.url.toString())) {
        return http.Response('', 404);
      }
      unexpected.add('${request.method} ${request.url}');
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Canvas custom IPTV renders VOD and live artwork with VOD-only focus identity',
      (tester) async {
    await _prepare(tester);
    await tester.runAsync(() async {
      final id = await IptvPrefs.createIptvList('Stage Mixed List');
      // VOD first also keeps the origin's initial focus seed off live preview.
      await StorageService.setIptvChannelInList(id, 'https://stage-vod.invalid/movie', true,
        channelName: 'Stage VOD', logoUrl: '$_art/vod-logo',
        contentType: 'vod', duration: 120);
      await StorageService.setIptvChannelInList(id, 'https://stage-live.invalid/feed', true,
        channelName: 'Stage Live', logoUrl: '$_art/live-logo',
        contentType: 'live', duration: -1);
      await StorageService.setHomeExtraRows([(id: 'iptvlist:$id', title: 'Stage Mixed List')]);
    });
    final unexpected = <String>[];
    await http.runWithClient(() async {
      try {
        await mountFavourites(tester);
        final cells = _posters(tester);
        expect(cells.map((p) => p.title), ['Stage VOD', 'Stage Live']);
        expect(cells.map((p) => p.imageUrl), ['$_art/vod-logo', '$_art/live-logo']);
        expect(cells.map((p) => p.imageFit), [BoxFit.contain, BoxFit.contain]);
        expect(cells.map((p) => p.ringColor), [Colors.white, Colors.white]);
        final nodes = cells.map((p) => p.focusNode).toList();
        nodes.first.requestFocus();
        await pumpFavourites(tester);
        expect(_posters(tester).map((p) => p.focusNode), nodes);
        expect(FocusManager.instance.primaryFocus, same(nodes.first));
        _identity(tester, 'Stage VOD', 'IPTV · STAGE MIXED LIST',
            '$_art/vod-logo', fit: BoxFit.contain);
        // No Right/live focus: that transition starts a native preview on
        // origin even with the trailer preference disabled, and is unproven.
        expect(unexpected, isEmpty);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      if (request.method == 'GET' && const {'$_art/live-logo', '$_art/vod-logo'}
          .contains(request.url.toString())) {
        return http.Response('', 404);
      }
      unexpected.add('${request.method} ${request.url}');
      return http.Response('{}', 404);
    }));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
