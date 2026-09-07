import 'dart:async';
import 'dart:io';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Origin pin for the launcher's URL-resolution layer in
/// `lib/services/video_player_launcher.dart`:
/// `_resolveEntryUrl` (4507–4521), `_resolveRedirectUrl` (249–355),
/// `_redirectCache` (240), and the resolved-stream cache trio
/// `_resolvedStreamCache` (239) / `_cacheResolvedStream` (242–247) /
/// `_clearResolvedStreams` (357–362).
///
/// All six are file-private, so the pin drives them through the public door
/// that reaches them — `VideoPlayerLauncher.push` down the native-TV branch,
/// where `_AndroidTvPlaybackPayloadBuilder._prepareEntries` resolves the start
/// entry and the playlist resolver's `handleRequest` resolves the rest — and
/// observes:
///
///   * the resolved URL, in the payload item / resolver reply;
///   * whether an outbound HEAD actually happened, counted at the
///     `HttpClient.openUrl` seam, which is what makes the redirect cache's
///     hit / miss / negative-cache behaviour observable at all.
///
/// Redirect answers come from a real loopback `HttpServer`, so the status
/// codes, the `location` header and the relative-URL resolution are the real
/// `dart:io` / `package:http` path rather than a hand-rolled response object.
/// Every non-loopback host is refused, so the pin never touches the network.
///
/// KNOWN COVERAGE LIMIT — the resolved-stream cache. `_cacheResolvedStream`'s
/// writes (3954, 4932, 5034) and `_clearResolvedStreams`' removals (4861,
/// 4945) are executed by this pin, but `_resolvedStreamCache` is only ever
/// READ at 4352 and 4382, inside `_handleProgressUpdate`, which the launcher
/// hands to `AndroidTvPlayerBridge.launchTorrentPlayback` as `onProgress`.
/// The `debugAndroidTvLaunch` seam stands in for that bridge call and receives
/// only the payload and the resolver, so no host test can reach the read side
/// and the cache's content is unobservable on the origin. What is pinned here
/// is that those paths run, and the launch outcome around them; the map's
/// contents are not, and a mutation that neuters `_cacheResolvedStream`
/// survives. Making that cache observable needs the bridge seam to forward
/// `onProgress` too — a production edit, out of scope for a pin-only commit.
///
/// Nothing here imports a launcher-internal file: if the resolver moves, this
/// test must keep passing unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String origin;
  late List<Map<String, dynamic>> launched;
  late List<Uri> opened;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? resolveStream;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/r/relative':
          response.statusCode = 302;
          response.headers.set('location', 'final/relative-target.mkv');
          break;
        case '/r/absolute':
          response.statusCode = 301;
          response.headers.set(
            'location',
            '$origin/media/absolute-target.mkv',
          );
          break;
        case '/r/chain-1':
          response.statusCode = 302;
          response.headers.set('location', '/r/chain-2');
          break;
        case '/r/chain-2':
          response.statusCode = 307;
          response.headers.set('location', '/media/chain-final.mkv');
          break;
        case '/r/no-location':
          response.statusCode = 302;
          break;
        case '/r/lazy-2':
          response.statusCode = 308;
          response.headers.set('location', '/media/lazy-two.mkv');
          break;
        default:
          // /r/plain and anything else: a normal 200, no redirect.
          response.statusCode = 200;
          break;
      }
      await response.close();
    });

    opened = <Uri>[];
    HttpOverrides.global = _CountingLoopbackOverrides(opened);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    launched = <Map<String, dynamic>>[];
    resolveStream = null;
    VideoPlayerLauncher.debugAndroidTvLaunch = (payload, resolver) async {
      launched.add(payload);
      resolveStream = resolver;
      return true;
    };
  });

  tearDown(() async {
    VideoPlayerLauncher.debugAndroidTvLaunch = null;
    VideoPlayerLauncher.debugPlayerWidgetBuilder = null;
    HttpOverrides.global = null;
    await server.close(force: true);
  });

  /// HEAD attempts the redirect resolver made for [url], counted at openUrl so
  /// a refused connection counts the same as an answered one.
  int attempts(String url) =>
      opened.where((u) => u.toString() == url).length;

  Future<Map<String, dynamic>> launch(
    WidgetTester tester,
    VideoPlayerLaunchArgs args, {
    bool awaitPush = true,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.runAsync(() async {
      // isTrailer skips the app-return observer so no 30s timer outlives the
      // test; URL resolution is unaffected by it.
      final pushed = VideoPlayerLauncher.push(captured, args, isTrailer: true);
      if (awaitPush) {
        // The native-TV branch returns before any route is pushed.
        await pushed;
      } else {
        // A declined native launch falls through to Navigator.push, whose
        // future only completes when the player route pops — never here.
        unawaited(pushed);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    });
    await tester.pump();
    if (awaitPush) {
      expect(launched, isNotEmpty, reason: 'native TV launch did not happen');
    }
    return launched.isEmpty ? <String, dynamic>{} : launched.last;
  }

  VideoPlayerLaunchArgs argsFor(
    List<PlaylistEntry> playlist, {
    String? videoUrl,
    int? startIndex,
  }) => VideoPlayerLaunchArgs(
    videoUrl: videoUrl ?? playlist.first.url,
    title: 'Redirect Pin',
    playlist: playlist,
    startIndex: startIndex,
    isAndroidTvOverride: () => true,
    disableExternalPlayer: true,
    suppressTraktAutoSync: true,
  );

  String startUrl(Map<String, dynamic> payload) {
    final items = (payload['items'] as List).cast<Map>();
    final index = payload['startIndex'] as int;
    return items[index]['url'] as String;
  }

  group('_resolveRedirectUrl — the skip guards (no HTTP at all)', () {
    testWidgets('a media extension short-circuits before any request', (
      tester,
    ) async {
      for (final ext in ['m3u8', 'mp4', 'mkv', 'ts', 'mpd']) {
        launched.clear();
        final url = '$origin/r/skip-guard.$ext';
        final payload = await launch(
          tester,
          argsFor([PlaylistEntry(url: url, title: 'Skip $ext')]),
        );

        expect(startUrl(payload), url, reason: ext);
        expect(attempts(url), 0, reason: ext);
      }
    });

    testWidgets('an upper-case media extension is NOT skipped', (tester) async {
      // The guard lower-cases the path first, so .MKV still short-circuits.
      final url = '$origin/r/case-guard.MKV';
      final payload = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Case guard')]),
      );

      expect(startUrl(payload), url);
      expect(attempts(url), 0);
    });

    testWidgets('a known debrid CDN host short-circuits before any request', (
      tester,
    ) async {
      const hosts = [
        'https://stream.real-debrid.com/d/pin-guard',
        'https://store-1.torbox.app/pin-guard',
        'https://dl.pikpak.com/pin-guard',
        'https://1fichier.com/pin-guard',
        'https://rapidgator.net/pin-guard',
      ];
      for (final url in hosts) {
        launched.clear();
        final payload = await launch(
          tester,
          argsFor([PlaylistEntry(url: url, title: 'CDN guard')]),
        );

        expect(startUrl(payload), url, reason: url);
        expect(attempts(url), 0, reason: url);
      }
    });
  });

  group('_resolveRedirectUrl — following one hop', () {
    testWidgets('a relative Location is resolved against the request URI', (
      tester,
    ) async {
      final url = '$origin/r/relative';
      final payload = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Relative')]),
      );

      expect(startUrl(payload), '$origin/r/final/relative-target.mkv');
      expect(attempts(url), 1);
    });

    testWidgets('an absolute Location is used verbatim', (tester) async {
      final url = '$origin/r/absolute';
      final payload = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Absolute')]),
      );

      expect(startUrl(payload), '$origin/media/absolute-target.mkv');
      expect(attempts(url), 1);
    });

    testWidgets('exactly one hop — a redirect chain is not followed', (
      tester,
    ) async {
      final url = '$origin/r/chain-1';
      final payload = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Chain')]),
      );

      // /r/chain-2 is itself a 307, but the resolver stops at the first
      // Location and never asks again.
      expect(startUrl(payload), '$origin/r/chain-2');
      expect(attempts(url), 1);
      expect(attempts('$origin/r/chain-2'), 0);
    });

    testWidgets('a non-redirect status keeps the original URL', (tester) async {
      final url = '$origin/r/plain';
      final payload = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Plain')]),
      );

      expect(startUrl(payload), url);
      expect(attempts(url), 1);
    });

    testWidgets('a redirect status with no Location keeps the original URL', (
      tester,
    ) async {
      final url = '$origin/r/no-location';
      final payload = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'No location')]),
      );

      expect(startUrl(payload), url);
      expect(attempts(url), 1);
    });
  });

  group('_redirectCache', () {
    testWidgets('a resolved redirect is answered from cache on the next hit', (
      tester,
    ) async {
      final url = '$origin/r/relative';
      final first = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Cached A')]),
      );
      expect(startUrl(first), '$origin/r/final/relative-target.mkv');
      expect(attempts(url), 1);

      launched.clear();
      final second = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Cached A again')]),
      );
      expect(startUrl(second), '$origin/r/final/relative-target.mkv');
      expect(attempts(url), 1, reason: 'second launch must be a cache HIT');
    });

    testWidgets('a non-redirect is cached too — the URL maps to itself', (
      tester,
    ) async {
      final url = '$origin/r/plain-negative';
      await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Negative A')]),
      );
      expect(attempts(url), 1);

      launched.clear();
      final second = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Negative B')]),
      );
      expect(startUrl(second), url);
      expect(attempts(url), 1, reason: 'the no-redirect answer is cached');
    });

    testWidgets('a FAILED request is cached as "no redirect" and never retried', (
      tester,
    ) async {
      // Quirk, preserved deliberately: the catch block only logs, then falls
      // through to the same unconditional `_redirectCache[url] = url` the
      // success path uses. So one transient socket failure poisons the entry
      // for the life of the process — the URL is never probed again, even
      // though it was never actually resolved. Pinned as-is; see the report.
      const url = 'http://unreachable.pin.invalid/r/unreachable';

      final first = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Dead A')]),
      );
      expect(startUrl(first), url);
      expect(attempts(url), 1);

      launched.clear();
      final second = await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Dead B')]),
      );
      expect(startUrl(second), url);
      expect(
        attempts(url),
        1,
        reason: 'the failed probe was cached, so there is no second attempt',
      );
    });
  });

  group('_resolveEntryUrl', () {
    testWidgets('an empty entry URL falls back to args.videoUrl, no HTTP', (
      tester,
    ) async {
      // The second branch: CloudProviderRegistry.unlockPlaybackEntry with no
      // provider metadata returns the launch fallbackUrl instead of resolving.
      final payload = await launch(
        tester,
        argsFor(
          [const PlaylistEntry(url: '', title: 'Empty URL entry')],
          videoUrl: '$origin/r/fallback-target.mkv',
        ),
      );

      expect(startUrl(payload), '$origin/r/fallback-target.mkv');
      expect(opened, isEmpty);
    });

    testWidgets('only the start entry is resolved eagerly', (tester) async {
      final lazy = '$origin/r/lazy-2';
      final payload = await launch(
        tester,
        argsFor([
          PlaylistEntry(url: '$origin/r/plain-eager', title: 'Pin Eager One'),
          PlaylistEntry(url: lazy, title: 'Pin Eager Two'),
        ], startIndex: 0),
      );

      expect(payload['startIndex'], 0);
      expect(attempts('$origin/r/plain-eager'), 1);
      expect(attempts(lazy), 0, reason: 'non-start entries stay unresolved');
      final items = (payload['items'] as List).cast<Map>();
      expect(items[1]['url'], lazy);
    });
  });

  group('the playlist resolver reaches the same resolver and cache', () {
    testWidgets('handleRequest resolves the requested entry and caches it', (
      tester,
    ) async {
      final lazy = '$origin/r/lazy-2';
      final payload = await launch(
        tester,
        argsFor([
          PlaylistEntry(url: '$origin/r/plain-lazy', title: 'Pin Lazy One'),
          PlaylistEntry(url: lazy, title: 'Pin Lazy Two'),
        ], startIndex: 0),
      );
      expect(attempts(lazy), 0);

      final items = (payload['items'] as List).cast<Map>();
      final targetResumeId = items[1]['resumeId'] as String;

      final resolver = resolveStream;
      expect(resolver, isNotNull);

      final reply = await tester.runAsync(() => resolver!({'index': 1}));
      expect(reply, isNotNull);
      expect(reply!['url'], '$origin/media/lazy-two.mkv');
      expect(reply['index'], 1);
      expect(reply['resumeId'], targetResumeId);
      expect(attempts(lazy), 1);

      // The second request is served from the redirect cache.
      final again = await tester.runAsync(
        () => resolver!({'resumeId': targetResumeId}),
      );
      expect(again!['url'], '$origin/media/lazy-two.mkv');
      expect(attempts(lazy), 1);
    });

    testWidgets('an unresolvable request yields null and issues no request', (
      tester,
    ) async {
      await launch(
        tester,
        argsFor([
          PlaylistEntry(url: '$origin/r/miss.mkv', title: 'Pin Miss'),
        ]),
      );

      final resolver = resolveStream;
      final before = opened.length;
      final reply = await tester.runAsync(
        () => resolver!({'resumeId': 'no-such-entry', 'index': 99}),
      );
      expect(reply, isNull);
      expect(opened.length, before);
    });
  });

  group('_clearResolvedStreams runs when the native launch is declined', () {
    testWidgets('a refused bridge launch disposes the resolver and falls back', (
      tester,
    ) async {
      // debugAndroidTvLaunch returning false is the launcher's "the bridge
      // would not take it" path: it disposes the playlist resolver — which is
      // the only reachable `_clearResolvedStreams` call — and lets `push`
      // continue to the Flutter player route.
      VideoPlayerLauncher.debugAndroidTvLaunch = (payload, resolver) async {
        launched.add(payload);
        resolveStream = resolver;
        return false;
      };
      final built = <VideoPlayerLaunchArgs>[];
      VideoPlayerLauncher.debugPlayerWidgetBuilder = (args) {
        built.add(args);
        return const SizedBox.shrink();
      };

      final url = '$origin/r/declined.mkv';
      await launch(
        tester,
        argsFor([PlaylistEntry(url: url, title: 'Declined')]),
        awaitPush: false,
      );
      await tester.pumpAndSettle();

      expect(launched, hasLength(1), reason: 'the payload was still built');
      expect(built, hasLength(1), reason: 'push fell through to the player');
      expect(built.single.videoUrl, url);
    });
  });
}

/// Answers loopback requests with the real client (so the pin exercises the
/// genuine `dart:io` redirect handling) and refuses every other host, while
/// recording each attempt — which is how the redirect cache's hit/miss
/// behaviour becomes observable from outside the launcher.
class _CountingLoopbackOverrides extends HttpOverrides {
  _CountingLoopbackOverrides(this.opened);

  final List<Uri> opened;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _CountingLoopbackClient(super.createHttpClient(context), opened);
}

class _CountingLoopbackClient implements HttpClient {
  _CountingLoopbackClient(this._inner, this._opened);

  final HttpClient _inner;
  final List<Uri> _opened;

  bool _isLoopback(Uri url) =>
      url.host == '127.0.0.1' || url.host == 'localhost';

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    _opened.add(url);
    if (_isLoopback(url)) return _inner.openUrl(method, url);
    throw const SocketException('offline pin test');
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, Uri.parse('http://$host:$port$path'));

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter || invocation.isGetter) return null;
    throw const SocketException('offline pin test');
  }
}
