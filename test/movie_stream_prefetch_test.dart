import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/movie_stream_prefetch.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const movie = StremioMeta(id: 'tmdb:42', type: 'movie', name: 'A movie');
final cache = MovieStreamPrefetch.instance;
final service = StremioService.instance;

// Exercise the real Play pipeline through its final player-route handoff.
// Inspect the unmounted player configuration, then remove the route before
// any decoder/platform state can mount or fetch media.
class PlayerHandoffObserver extends NavigatorObserver {
  final players = <VideoPlayerScreen>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! FrozenLegacyPageRoute) return;
    final boundary = route.builder(navigator!.context) as LegacyThemeBoundary;
    final player = (boundary.child as Builder).builder(navigator!.context);
    if (player is! VideoPlayerScreen) return;
    players.add(player);
    scheduleMicrotask(() => navigator!.removeRoute(route));
  }
}

StremioAddon addon(String id, {List<String>? prefixes}) => StremioAddon(
  id: id,
  name: id,
  version: '1',
  manifestUrl: 'https://$id.invalid/manifest.json',
  baseUrl: 'https://$id.invalid',
  resources: const ['stream'],
  types: const ['movie'],
  idPrefixes: prefixes,
);

http.Response torrents({
  String hash = '0123456789012345678901234567890123456789',
}) => http.Response(
  jsonEncode({
    'streams': [
      {'infoHash': hash, 'title': 'A movie 1080p', 'name': 'Source'},
    ],
  }),
  200,
);

Future<void> configure(List<StremioAddon> addons, {bool enabled = true}) async {
  SharedPreferences.setMockInitialValues({
    'stremio_addons_v1': jsonEncode(addons.map((a) => a.toJson()).toList()),
    BrowsingCachePreferences.key: jsonEncode({'prefetchMovieStreams': enabled}),
  });
  BrowsingCachePreferences.resetForTesting();
  service.invalidateCache();
  cache.resetForTesting();
  await BrowsingCachePreferences.initialize();
}

Future<void> flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<Map<String, dynamic>> playLookup([String id = 'tmdb:42']) =>
    TorrentService.searchStremioAddonsOnly(
      imdbId: id,
      isMovie: true,
      contentType: 'movie',
      preserveOrder: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(() {
    service.debugStreamHttpClientFactory = null;
    cache.resetForTesting();
    ProfileRuntime.debugReset();
    service.invalidateCache();
  });

  testWidgets(
    'open starts GET; early Play joins it; hot Play reuses descriptors',
    (tester) async {
      await configure([
        addon('one', prefixes: ['tmdb:']),
      ]);
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      service.debugStreamHttpClientFactory = () => MockClient((request) {
        requests.add(request);
        return response.future;
      });
      Future<Map<String, dynamic>>? chosen;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.legacy, child: child!),
          home: CatalogItemDetailScreen(
            item: movie,
            isTelevision: true,
            onPlay: () => chosen = playLookup(),
            onBrowse: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(requests, hasLength(1));
      expect(chosen, isNull, reason: 'Opening a detail does not press Play.');
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(chosen, isNotNull);
      expect(requests, hasLength(1));
      // Leaving while Play waits must not discard its chosen request.
      await tester.pumpWidget(const SizedBox());
      response.complete(torrents());
      await tester.pump();
      expect((await chosen!)['torrents'], hasLength(1));
      expect((await playLookup())['torrents'], hasLength(1));
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.host, 'one.invalid');
      expect(
        Uri.decodeComponent(requests.single.url.path),
        '/stream/movie/tmdb:42.json',
      );
    },
  );

  test(
    'expiry, addon reconfiguration, and disable force fresh lookups',
    () async {
      await configure([addon('one')]);
      var now = DateTime.utc(2026);
      cache.resetForTesting(now: () => now);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) async {
        calls++;
        return torrents();
      });
      service.prefetchMovieStreams(movie);
      await flush();
      await playLookup();
      expect(calls, 1);
      now = now.add(const Duration(seconds: 61));
      await playLookup();
      expect(calls, 2);
      service.refreshAfterExternalChange();
      await playLookup();
      expect(calls, 3);
      await BrowsingCachePreferences.update(
        const BrowsingCacheOptions(prefetchMovieStreams: false),
      );
      service.prefetchMovieStreams(movie);
      await flush();
      expect(calls, 3);
      await playLookup();
      expect(calls, 4);
    },
  );

  test('failed and empty discoveries retry on Play', () async {
    for (final failed in [true, false]) {
      await configure([addon('one')]);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response(
                failed ? 'unavailable' : '{"streams":[]}',
                failed ? 503 : 200,
              )
            : torrents();
      });
      service.prefetchMovieStreams(movie);
      await flush();
      expect((await playLookup())['torrents'], hasLength(1));
      expect(calls, 2);
    }
  });

  test(
    'direct discovery is retained but pinned resolver always fetches fresh',
    () async {
      final source = addon('one');
      await configure([source]);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.host,
          'one.invalid',
          reason: 'Never fetch the media URL.',
        );
        calls++;
        return http.Response(
          jsonEncode({
            'streams': [
              {
                'url': 'https://media.invalid/video?signature=$calls',
                'name': 'Direct',
                'title': '1080p',
              },
            ],
          }),
          200,
        );
      });
      service.prefetchMovieStreams(movie);
      await flush();
      final result = await playLookup();
      final direct = (result['torrents'] as List<Torrent>).single;
      expect(calls, 1);
      await service.resolvePinnedDirectStream(
        addonId: source.id,
        addonKey: source.sourceBindingKey,
        streamKey: direct.stremioStreamKey!,
        streamIndex: direct.stremioStreamIndex!,
        type: 'movie',
        contentId: movie.id,
      );
      expect(calls, 2);
    },
  );

  for (final scenario in ['early', 'delayed', 'expired', 'explicit expiry']) {
    testWidgets('real movie Play reuses direct discovery: $scenario', (
      tester,
    ) async {
      await configure([addon('direct')]);
      await StorageService.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(
          isMovie: true,
        ).copyWith(validateDirectLinks: false),
        isMovie: true,
      );
      var now = DateTime.utc(2026);
      cache.resetForTesting(now: () => now);
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      final expirySuffix = scenario == 'explicit expiry'
          ? '&Expires=${now.add(const Duration(seconds: 10)).millisecondsSinceEpoch ~/ 1000}'
          : '';
      http.Response directResponse(int revision) => http.Response(
        jsonEncode({
          'streams': [
            {
              'url':
                  'https://media.invalid/video.mp4?signature=$revision${revision == 1 ? expirySuffix : ''}',
              'name': 'Direct',
              'title': '1080p',
            },
          ],
        }),
        200,
      );
      service.debugStreamHttpClientFactory = () => MockClient((request) {
        requests.add(request);
        return requests.length == 1
            ? response.future
            : Future.value(directResponse(requests.length));
      });
      final observer = PlayerHandoffObserver();
      Future<void>? chosen;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.legacy, child: child!),
          home: Builder(
            builder: (context) => CatalogItemDetailScreen(
              item: movie,
              isTelevision: true,
              onPlay: () {
                chosen = TorrentPlaybackService.playFromSelection(
                  context,
                  imdbId: movie.effectiveImdbId ?? movie.id,
                  isMovie: true,
                  meta: PlaybackMeta.catalog(
                    imdbId: movie.id,
                    contentType: movie.type,
                    title: movie.name,
                  ),
                );
              },
              onBrowse: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(requests, hasLength(1));
      expect(observer.players, isEmpty);
      if (scenario != 'early') {
        response.complete(directResponse(1));
        await tester.pump();
        await tester.pump();
        now = now.add(Duration(seconds: scenario == 'expired' ? 21 : 12));
      }
      await tester.tap(find.text('Play'));
      await tester.pump();
      if (scenario == 'early') {
        expect(requests, hasLength(1));
        expect(observer.players, isEmpty);
        response.complete(directResponse(1));
      }
      for (var i = 0; i < 100 && observer.players.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(observer.players, hasLength(1));
      final expectedFetches =
          scenario == 'expired' || scenario == 'explicit expiry' ? 2 : 1;
      expect(requests, hasLength(expectedFetches));
      expect(
        observer.players.single.videoUrl,
        'https://media.invalid/video.mp4?signature=$expectedFetches',
      );
      expect(
        observer.players.single.stremioSources!.single.stremioAddonId,
        'direct',
      );
      expect(
        requests.every(
          (r) => r.method == 'GET' && r.url.host == 'direct.invalid',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await chosen;
    });
  }

  test(
    'mixed direct, external and torrent responses preserve whole order',
    () async {
      await configure([addon('mixed')]);
      var now = DateTime.utc(2026);
      cache.resetForTesting(now: () => now);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'streams': [
              {
                'url': 'https://media.invalid/video.mp4',
                'title': 'First 1080p',
              },
              {'externalUrl': 'https://media.invalid/watch', 'title': 'Second'},
              {
                'infoHash': '0123456789012345678901234567890123456789',
                'title': 'Third 720p',
              },
            ],
          }),
          200,
        );
      });
      service.prefetchMovieStreams(movie);
      await flush();
      now = now.add(const Duration(seconds: 12));
      final result = (await playLookup())['torrents'] as List<Torrent>;
      expect(calls, 1);
      expect(result.map((source) => source.streamType), [
        StreamType.directUrl,
        StreamType.externalUrl,
        StreamType.torrent,
      ]);
      expect(result.map((source) => source.stremioStreamIndex), [0, 1, 2]);
      now = now.add(const Duration(seconds: 9));
      expect((await playLookup())['torrents'], hasLength(3));
      expect(
        calls,
        2,
        reason: 'The entire mixed response uses the shortest TTL.',
      );
    },
  );

  test(
    'explicit expiry caps external discovery and malformed expiry is ignored',
    () async {
      for (final expiry in ['epoch', 'milliseconds', 'invalid']) {
        await configure([addon('expiry')]);
        var now = DateTime.utc(2026);
        cache.resetForTesting(now: () => now);
        final expires = now
            .add(const Duration(seconds: 9))
            .millisecondsSinceEpoch;
        final parameter = switch (expiry) {
          'epoch' => '${expires ~/ 1000}',
          'milliseconds' => '$expires',
          _ => 'opaque-not-an-epoch',
        };
        var calls = 0;
        service.debugStreamHttpClientFactory = () => MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'streams': [
                {'externalUrl': 'https://media.invalid/watch?exp=$parameter'},
              ],
            }),
            200,
          );
        });
        service.prefetchMovieStreams(movie);
        await flush();
        now = now.add(const Duration(seconds: 5));
        await playLookup();
        expect(calls, 1);
        now = now.add(const Duration(seconds: 3));
        await playLookup();
        expect(calls, expiry == 'invalid' ? 1 : 2);
      }
    },
  );

  test(
    'applicability and order survive warm discovery and conversion',
    () async {
      await configure([
        addon('second'),
        addon('first'),
        addon('imdb', prefixes: ['tt']),
      ]);
      final hosts = <String>[];
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        hosts.add(request.url.host);
        return torrents(
          hash: request.url.host == 'second.invalid'
              ? '2222222222222222222222222222222222222222'
              : '1111111111111111111111111111111111111111',
        );
      });
      service.prefetchMovieStreams(movie);
      await flush();
      final result = await playLookup();
      expect((result['torrents'] as List<Torrent>).map((t) => t.source), [
        'stremio:second',
        'stremio:first',
      ]);
      expect(hosts, ['second.invalid', 'first.invalid']);
    },
  );

  test('closing stops queued addon discovery', () async {
    await configure([for (var i = 0; i < 8; i++) addon('addon$i')]);
    final pending = <Completer<http.Response>>[];
    service.debugStreamHttpClientFactory = () => MockClient((_) {
      final response = Completer<http.Response>();
      pending.add(response);
      return response.future;
    });
    final lease = service.prefetchMovieStreams(movie)!;
    await flush();
    expect(pending, hasLength(3));
    lease.close();
    for (final response in pending) {
      response.complete(torrents());
    }
    await flush();
    expect(pending, hasLength(3));
  });

  test('disabling stops queued background launches without a Play', () async {
    await configure([for (var i = 0; i < 8; i++) addon('queued$i')]);
    final pending = <Completer<http.Response>>[];
    service.debugStreamHttpClientFactory = () => MockClient((_) {
      final response = Completer<http.Response>();
      pending.add(response);
      return response.future;
    });
    service.prefetchMovieStreams(movie);
    await flush();
    expect(pending, hasLength(3));
    await BrowsingCachePreferences.update(
      const BrowsingCacheOptions(prefetchMovieStreams: false),
    );
    for (final response in pending) {
      response.complete(torrents());
    }
    await flush();
    expect(pending, hasLength(3));
  });

  test(
    'disable stops queued speculation without failing joined Play',
    () async {
      await configure([for (var i = 0; i < 8; i++) addon('disable$i')]);
      final pending = <Completer<http.Response>>[];
      service.debugStreamHttpClientFactory = () => MockClient((_) {
        final response = Completer<http.Response>();
        pending.add(response);
        return response.future;
      });
      service.prefetchMovieStreams(movie);
      await flush();
      expect(pending, hasLength(3));
      final chosen = playLookup();
      await flush();
      expect(pending, hasLength(8));
      await BrowsingCachePreferences.update(
        const BrowsingCacheOptions(prefetchMovieStreams: false),
      );
      for (final response in pending) {
        response.complete(torrents());
      }
      expect((await chosen)['torrents'], isNotEmpty);
      await flush();
      expect(pending, hasLength(8));
    },
  );

  test('closing an unclaimed detail clears speculative results', () async {
    await configure([addon('one')]);
    var calls = 0;
    service.debugStreamHttpClientFactory = () => MockClient((_) async {
      calls++;
      return torrents();
    });
    final lease = service.prefetchMovieStreams(movie)!;
    await flush();
    expect(calls, 1);
    lease.close();
    await playLookup();
    expect(calls, 2);
  });

  test(
    'claim before asynchronous Play keeps hot results across route close',
    () async {
      await configure([addon('one')]);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) async {
        calls++;
        return torrents();
      });
      final lease = service.prefetchMovieStreams(movie)!;
      await flush();
      lease.claim();
      lease.close();
      expect((await playLookup())['torrents'], hasLength(1));
      expect(calls, 1);
    },
  );

  test(
    'old completion cannot evict a fresh same-key cache after invalidation',
    () async {
      await configure([addon('one')]);
      final old = Completer<http.Response>();
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) {
        calls++;
        return calls == 1 ? old.future : Future.value(torrents());
      });
      service.prefetchMovieStreams(movie);
      await flush();
      service.refreshAfterExternalChange();
      service.prefetchMovieStreams(movie);
      await flush();
      expect(calls, 2);
      old.complete(torrents());
      await flush();
      expect((await playLookup())['torrents'], hasLength(1));
      expect(calls, 2);
    },
  );

  test('recommendations and Play share the detail discovery GET', () async {
    await configure([addon('recommendations')]);
    const imdbMovie = StremioMeta(
      id: 'tt1234567',
      imdbId: 'tt1234567',
      type: 'movie',
      name: 'IMDb movie',
    );
    final response = Completer<http.Response>();
    var calls = 0;
    service.debugStreamHttpClientFactory = () => MockClient((_) {
      calls++;
      return response.future;
    });
    service.prefetchMovieStreams(imdbMovie);
    await flush();
    final recommendations = service.getRecommendations(
      imdbId: 'tt1234567',
      type: 'movie',
    );
    final chosen = playLookup('tt1234567');
    await flush();
    expect(calls, 1);
    response.complete(torrents());
    expect(await recommendations, isEmpty);
    expect((await chosen)['torrents'], hasLength(1));
    expect(calls, 1);
  });

  test('addon disable and re-enable invalidate completed discovery', () async {
    final source = addon('one');
    await configure([source]);
    var calls = 0;
    service.debugStreamHttpClientFactory = () => MockClient((_) async {
      calls++;
      return torrents();
    });
    service.prefetchMovieStreams(movie);
    await flush();
    expect(calls, 1);
    await service.setAddonEnabled(source.storageKey, false);
    expect((await playLookup())['torrents'], isEmpty);
    expect(calls, 1);
    await service.setAddonEnabled(source.storageKey, true);
    expect((await playLookup())['torrents'], hasLength(1));
    expect(calls, 2);
  });

  test('recommendations alone do not claim speculative results', () async {
    await configure([addon('one')]);
    const item = StremioMeta(id: 'tt1234567', type: 'movie', name: 'Movie');
    var calls = 0;
    service.debugStreamHttpClientFactory = () => MockClient((_) async {
      calls++;
      return torrents();
    });
    final lease = service.prefetchMovieStreams(item)!;
    await flush();
    await service.getRecommendations(imdbId: item.id, type: 'movie');
    expect(calls, 1);
    lease.close();
    await playLookup(item.id);
    expect(calls, 2);
  });

  test(
    'rapid opens cap active work; completed cache retains only three movies',
    () async {
      await configure([addon('one')]);
      final pending = <Completer<http.Response>>[];
      var hold = true;
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) {
        calls++;
        if (!hold) return Future.value(torrents());
        final response = Completer<http.Response>();
        pending.add(response);
        return response.future;
      });
      final leases = [
        for (var i = 0; i < 20; i++)
          service.prefetchMovieStreams(
            StremioMeta(id: 'tmdb:$i', type: 'movie', name: '$i'),
          )!,
      ];
      await flush();
      expect(calls, 2);
      for (final lease in leases) {
        lease.close();
      }
      service.prefetchMovieStreams(movie);
      await flush();
      expect(
        calls,
        2,
        reason: 'Closed in-flight work still occupies its slot.',
      );
      for (final response in pending) {
        response.complete(torrents());
      }
      await flush();
      hold = false;
      for (var i = 0; i < 4; i++) {
        service.prefetchMovieStreams(
          StremioMeta(id: 'tmdb:$i', type: 'movie', name: '$i'),
        );
        await flush();
      }
      final before = calls;
      await playLookup('tmdb:3');
      expect(calls, before);
      await playLookup('tmdb:0');
      expect(
        calls,
        before + 1,
        reason: 'The least recent of four movies is evicted.',
      );
    },
  );

  test(
    'disabled option and series never speculate; native IDs stay native',
    () async {
      await configure([addon('one')], enabled: false);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((_) async {
        calls++;
        return torrents();
      });
      service.prefetchMovieStreams(movie);
      expect(
        service.prefetchMovieStreams(
          const StremioMeta(id: 'tt123', type: 'series', name: 'Series'),
        ),
        isNull,
      );
      await flush();
      expect(calls, 0);
      expect(MovieStreamPrefetch.contentIdFor(movie), 'tmdb:42');
      expect(
        MovieStreamPrefetch.contentIdFor(
          const StremioMeta(
            id: 'tmdb:42',
            type: 'movie',
            name: 'Movie',
            imdbId: '42',
          ),
        ),
        '42',
        reason: 'Match callback identity exactly without inventing a tt prefix.',
      );
    },
  );

  test(
    'profile A to B to A epochs revoke old discovery before it completes',
    () async {
      await configure([]);
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'first', dataGeneration: 1, sessionEpoch: 1),
      );
      final stream = StremioStream(infoHash: 'abc', source: 'source');
      final gate = Completer<List<StremioStream>>();
      Future<List<StremioStream>>? pending;
      cache.open('movie', (lease) async {
        pending = cache.lookup(
          contentId: 'movie',
          addonConfiguration: 'one',
          timeout: const Duration(seconds: 15),
          load: () => gate.future,
          speculation: lease,
        );
        await pending;
      });
      await flush();
      final rejected = expectLater(pending!, throwsStateError);
      ProfileRuntime.publish(
        ProfileScope(profileId: 'other', dataGeneration: 1, sessionEpoch: 2),
      );
      ProfileRuntime.publish(
        ProfileScope(profileId: 'first', dataGeneration: 1, sessionEpoch: 3),
      );
      gate.complete([stream]);
      await rejected;
      var fresh = 0;
      await cache.lookup(
        contentId: 'movie',
        addonConfiguration: 'one',
        timeout: const Duration(seconds: 15),
        load: () async {
          fresh++;
          return [stream];
        },
      );
      expect(fresh, 1);
    },
  );
}
