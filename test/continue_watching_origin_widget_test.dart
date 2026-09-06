import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/continue_watching_origin_harness.dart';

// Retrospective #96 evidence: unchanged on move parent 874272265086c088a4b6cab6a6c14f23183a92a7
// and submitted head ec77a1ac16a7df233260403258dce80384e6cdb9.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpOverrides previousHttp;
  late List<String> unexpectedIo;

  setUp(() async {
    previousHttp = HttpOverrides.current!;
    unexpectedIo = [];
    HttpOverrides.global = CwOriginImageHttp(previousHttp, unexpectedIo);
    // Serve the loader's display-font variant from an existing bundled font;
    // this test checks row ownership, not typography or the font CDN.
    final manifestData = await rootBundle.load('AssetManifest.bin');
    final manifest = Map<Object?, Object?>.from(
      const StandardMessageCodec().decodeMessage(manifestData) as Map,
    );
    const fontAlias = 'assets/fonts/Poppins-SemiBold.ttf';
    final font = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
    manifest[fontAlias] = [
      {'asset': fontAlias},
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (key == fontAlias) return font;
      return messenger.delegate.send('flutter/assets', message);
    });
    rootBundle.evict('AssetManifest.bin');
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    SecretVault.debugReset(deviceIdOverride: 'cw-origin-test');
    root = await Directory.systemTemp.createTemp('cw-origin-');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if ({
          'getTemporaryDirectory',
          'getApplicationSupportDirectory',
        }.contains(call.method)) {
          return root.path;
        }
        throw StateError('Unexpected path_provider method: ${call.method}');
      },
    );
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await StorageService.setTvHomeStyle('classic');
    await HomePrefs.setHomeHeroTrailerEnabled(false);
  });

  tearDown(() async {
    HttpOverrides.global = previousHttp;
    expect(unexpectedIo, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    rootBundle.evict('AssetManifest.bin');
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    SecretVault.debugReset();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  testWidgets('late Trakt load A cannot replace the newer rendered B row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await StorageService.setTraktAccessToken('same-account-token');
      await StorageService.setTraktTokenExpiry(
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
    });

    final reachedA = Completer<void>();
    final releaseA = Completer<http.Response>();
    final returnedA = Completer<void>();
    final reachedB = Completer<void>();
    final unexpected = <String>[];
    var movieRequests = 0;
    final otherRequests = <String, int>{};

    Future<void> pumpUntil(bool Function() ready, String description) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        // Allow real credential crypto / local-file futures to finish, while
        // frame advancement and both HTTP releases remain explicitly bounded.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(ready(), isTrue, reason: description);
    }

    http.Response page(String body) => http.Response(
      body,
      200,
      headers: {
        'content-type': 'application/json',
        'x-pagination-page-count': '1',
      },
    );

    String movie(String title, String imdb) => jsonEncode([
      {
        'id': 1,
        'type': 'movie',
        'progress': 25,
        'paused_at': '2026-09-01T12:00:00Z',
        'movie': {
          'title': title,
          'year': 2025,
          'runtime': 100,
          'ids': {'imdb': imdb},
          'images': {
            'poster': ['https://cw-art.invalid/$imdb.png'],
            'fanart': ['https://cw-art.invalid/$imdb.png'],
          },
        },
      },
    ]);

    await http.runWithClient(
      () async {
        try {
          MainPageBridge.notifyIntegrationChanged();
          await pumpUntil(() => reachedA.isCompleted, 'A must reach HTTP');
          await reachedA.future;
          expect(find.text('New B Movie'), findsNothing);
          MainPageBridge.notifyIntegrationChanged();
          await pumpUntil(() => reachedB.isCompleted, 'B must reach HTTP');
          await reachedB.future;
          await pumpUntil(
            () => find.text('New B Movie').evaluate().isNotEmpty,
            'B must render before releasing A',
          );
          expect(find.text('New B Movie'), findsWidgets);
          expect(find.text('Stale A Movie'), findsNothing);

          releaseA.complete(page(movie('Stale A Movie', 'tt0000001')));
          await pumpUntil(
            () => returnedA.isCompleted,
            'A must return its payload',
          );
          await returnedA.future;
          await tester.pumpAndSettle();
          expect(find.text('New B Movie'), findsWidgets);
          expect(find.text('Stale A Movie'), findsNothing);
          expect(movieRequests, 2);
          expect(otherRequests, {
            '/sync/progress/up_next_nitro': 2,
            '/sync/playback/episodes': 2,
          });
          expect(unexpected, isEmpty);
          expect(
            await tester.runAsync(StorageService.getTraktAccessToken),
            'same-account-token',
          );
        } finally {
          if (!releaseA.isCompleted) releaseA.complete(page('[]'));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
      () => MockClient((request) async {
        final uri = request.url;
        if (request.method != 'GET' || uri.host != 'api.trakt.tv') {
          unexpected.add('${request.method} $uri');
          throw StateError('Unexpected request: ${request.method} $uri');
        }
        if (request.headers['authorization'] != 'Bearer same-account-token') {
          unexpected.add('Unexpected authorization at $uri');
          throw StateError('Unexpected authorization');
        }
        if (uri.path == '/sync/playback/movies') {
          movieRequests++;
          if (movieRequests == 1) {
            reachedA.complete();
            final response = await releaseA.future;
            returnedA.complete();
            return response;
          }
          if (movieRequests == 2) {
            reachedB.complete();
            return page(movie('New B Movie', 'tt0000002'));
          }
        } else if ({
          '/sync/progress/up_next_nitro',
          '/sync/playback/episodes',
        }.contains(uri.path)) {
          final count = otherRequests.update(
            uri.path,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
          if (count <= 2) return page('[]');
        }
        unexpected.add('${request.method} $uri');
        throw StateError('Unexpected request: ${request.method} $uri');
      }),
    );
  });
}
