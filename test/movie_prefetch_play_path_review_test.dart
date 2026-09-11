import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/movie_stream_prefetch.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _service = StremioService.instance;
final _cache = MovieStreamPrefetch.instance;
const _movie = StremioMeta(id: 'tmdb:42', type: 'movie', name: 'Review movie');

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

http.Response _streams(String title) => http.Response(
  jsonEncode({
    'streams': [
      {
        'infoHash': '0123456789012345678901234567890123456789',
        'title': title,
        'behaviorHints': {'filename': title, 'videoSize': 1024},
      },
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    final addon = StremioAddon(
      id: 'review',
      name: 'Review',
      version: '1',
      baseUrl: 'https://review.invalid',
      manifestUrl: 'https://review.invalid/manifest.json',
      resources: const ['stream'],
      types: const ['movie'],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
    });
    BrowsingCachePreferences.resetForTesting();
    _service.invalidateCache();
    _cache.resetForTesting();
  });
  tearDown(() {
    _service.debugStreamHttpClientFactory = null;
    _cache.resetForTesting();
    _service.invalidateCache();
    ProfileRuntime.debugReset();
  });

  testWidgets(
    'detail Play enters normal playback pipeline and joins pending discovery',
    (tester) async {
      final reply = Completer<http.Response>.sync();
      var requests = 0;
      _service.debugStreamHttpClientFactory = () => MockClient((request) async {
        requests++;
        expect(
          Uri.decodeComponent(request.url.path),
          '/stream/movie/tmdb:42.json',
        );
        return reply.future;
      });
      Future<void>? playing;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.legacy, child: child!),
          home: Builder(
            builder: (context) => CatalogItemDetailScreen(
              item: _movie,
              isTelevision: true,
              // This is the production entrypoint called by Search's _playSelection,
              // including its rules, overlays and stream search, not a cache lookup.
              onPlay: () => playing = TorrentPlaybackService.playFromSelection(
                context,
                imdbId: _movie.id,
                isMovie: true,
                meta: const PlaybackMeta.catalog(
                  imdbId: 'tmdb:42',
                  contentType: 'movie',
                  title: 'Review movie',
                ),
              ),
              onBrowse: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(requests, 1);
      expect(playing, isNull);
      await tester.tap(find.text('Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(playing, isNotNull);
      expect(requests, 1);
      // Complete at discovery's empty-result boundary, before any acquisition,
      // native player or media request can run.
      reply.complete(http.Response('{"streams":[]}', 200));
      await tester.pumpAndSettle();
      await playing;
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'same catalog ID with new IMDb metadata warms only the new Play identity',
    (tester) async {
      final pending = <String, Completer<http.Response>>{};
      _service.debugStreamHttpClientFactory = () => MockClient((request) {
        final id = request.url.pathSegments.last;
        final reply = Completer<http.Response>.sync();
        expect(
          pending.containsKey(id),
          isFalse,
          reason: 'Play should join, not repeat discovery.',
        );
        pending[id] = reply;
        return reply.future;
      });
      Future<Map<String, dynamic>>? playing;
      Widget page(String imdb) => MaterialApp(
        builder: (_, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: CatalogItemDetailScreen(
          key: const ValueKey('same-detail-state'),
          item: StremioMeta(
            id: 'tmdb:42',
            imdbId: imdb,
            type: 'movie',
            name: 'Review movie',
          ),
          isTelevision: true,
          onPlay: () =>
              playing = _service.searchStreams(type: 'movie', imdbId: imdb),
          onBrowse: () {},
        ),
      );
      await tester.pumpWidget(page('tt1234567'));
      await tester.pump();
      await tester.pump();
      final originalState = tester.state(find.byType(CatalogItemDetailScreen));
      await tester.pumpWidget(page('tt7654321'));
      await tester.pump();
      expect(
        tester.state(find.byType(CatalogItemDetailScreen)),
        same(originalState),
      );
      expect(pending.keys, containsAll(['tt1234567.json', 'tt7654321.json']));
      await tester.tap(find.text('Play'));
      await tester.pump();
      pending['tt1234567.json']!.complete(_streams('Wrong old metadata'));
      pending['tt7654321.json']!.complete(_streams('Correct current metadata'));
      await tester.pumpAndSettle();
      expect(
        ((await playing!)['torrents'] as List<Torrent>).single.name,
        'Correct current metadata',
      );
      expect(pending.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'normal consumers cannot mutate another search result or cached descriptors',
    () async {
      var requests = 0;
      _service.debugStreamHttpClientFactory = () => MockClient((_) async {
        requests++;
        return _streams('Original descriptor');
      });
      _service.prefetchMovieStreams(_movie);
      await _flush();
      final first = await _service.searchStreams(
        type: 'movie',
        imdbId: _movie.id,
      );
      final original = (first['torrents'] as List<Torrent>).single;
      (first['torrents'] as List<Torrent>).clear();
      (first['addonCounts'] as Map).clear();
      final second = await _service.searchStreams(
        type: 'movie',
        imdbId: _movie.id,
      );
      final next = (second['torrents'] as List<Torrent>).single;
      expect(next.name, 'Original descriptor');
      expect(next.sizeBytes, 1024);
      expect(next, isNot(same(original)));
      expect(second['addonCounts'], isNotEmpty);
      expect(requests, 1);
    },
  );

  for (final generationChange in [false, true]) {
    test(
      'same profile ID ${generationChange ? 'generation' : 'epoch'} replacement revokes completed movie reuse',
      () async {
        ProfileRuntime.initializeCommitted(
          ProfileScope(profileId: 'same', dataGeneration: 1, sessionEpoch: 1),
        );
        final stream = StremioStream(infoHash: 'abc', source: 'review');
        var loads = 0;
        Future<List<StremioStream>> lookup([MovieStreamPrefetchLease? lease]) =>
            _cache.lookup(
              contentId: 'movie',
              addonConfiguration: 'unchanged-addon',
              timeout: const Duration(seconds: 2),
              speculation: lease,
              load: () async {
                loads++;
                return [stream];
              },
            );
        final lease = _cache.open('movie', (lease) async {
          await lookup(lease);
        });
        await _flush();
        await lookup();
        expect(loads, 1);
        ProfileRuntime.publish(
          ProfileScope(
            profileId: 'same',
            dataGeneration: generationChange ? 2 : 1,
            sessionEpoch: 2,
          ),
        );
        expect(lease.isActive, isFalse);
        await lookup();
        expect(loads, 2);
      },
    );
  }
}
