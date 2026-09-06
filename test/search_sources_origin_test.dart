import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart' show buildSearchSources;
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites;

// Real a94a5196 factory/UI/TPS/store. Only HTTP and the physical preference
// transport are held. No provider, player, caller-refresh or rollback proof.
const _id = 'tt1234567';
const _key = 'series_source_$_id';
const _physicalKey = 'flutter.$_key';
const _signedUrl =
    'https://video.invalid/movie.mp4?synthetic-signature=expired';
const _limit = Duration(seconds: 20);

class _HeldStore extends InMemorySharedPreferencesStore {
  _HeldStore(super.data) : super.withData();
  final entered = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();
  final writes = <(String, String, Object)>[];
  bool? result;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _physicalKey) return super.setValue(type, key, value);
    writes.add((type, key, value));
    if (!entered.isCompleted) entered.complete();
    await release.future.timeout(_limit);
    result = await super.setValue(type, key, value);
    if (!completed.isCompleted) completed.complete();
    return result!;
  }

  Future<Map<String, Object>> physical() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

class _Routes extends NavigatorObserver {
  final pops = <Route<dynamic>>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops.add(route);
    super.didPop(route, previousRoute);
  }
}

Future<void> _case(
  WidgetTester tester, {
  required bool holdHttp,
  required bool userPop,
}) async {
  await prepareFavourites(tester);
  final previousStore = SharedPreferencesStorePlatform.instance;
  final service = StremioService.instance;
  final previousClient = service.debugStreamHttpClientFactory;
  final requests = <Uri>[];
  final unexpected = <Uri>[];
  final httpEntered = Completer<void>();
  final httpRelease = Completer<void>();
  final httpCompleted = Completer<void>();
  final routes = _Routes();
  final navigator = GlobalKey<NavigatorState>();
  final addon = StremioAddon(
    id: 'sources.origin',
    name: 'Origin source',
    manifestUrl: 'https://sources.invalid/manifest.json',
    baseUrl: 'https://sources.invalid',
    resources: ['stream'],
    types: ['movie'],
  );
  final seeded = await SharedPreferences.getInstance();
  await seeded.setString('stremio_addons_v1', jsonEncode([addon.toJson()]));
  await seeded.setString('sources_origin_sentinel', 'unchanged');
  final backend = _HeldStore({
    for (final key in seeded.getKeys()) 'flutter.$key': seeded.get(key)!,
  });
  final initial = await backend.physical();
  var routeCompleted = 0;
  Map<String, Object>? finalPhysical;
  List<SeriesSource>? finalPublic;
  final client = MockClient((request) async {
    requests.add(request.url);
    if (request.method != 'GET' ||
        request.url.toString() !=
            'https://sources.invalid/stream/movie/$_id.json') {
      unexpected.add(request.url);
      throw StateError('Unexpected Sources fixture HTTP transport');
    }
    if (!httpEntered.isCompleted) httpEntered.complete();
    if (holdHttp) await httpRelease.future.timeout(_limit);
    if (!httpCompleted.isCompleted) httpCompleted.complete();
    return http.Response(
      jsonEncode({
        'streams': [
          {
            'name': 'Origin source',
            'description': 'Origin movie 1080p',
            'url': _signedUrl,
          },
        ],
      }),
      200,
    );
  });
  try {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    service.invalidateCache();
    service.debugStreamHttpClientFactory = () => client;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await tester.runAsync(() => EngineRegistry.instance.initialize());
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          home: const Scaffold(body: Text('Sources origin parent')),
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => buildSearchSources(
          selection: const AdvancedSearchSelection(
            imdbId: _id,
            isSeries: false,
            title: 'Origin movie',
            contentType: 'movie',
          ),
          meta: const PlaybackMeta(
            imdbId: _id,
            title: 'Origin movie',
            contentType: 'movie',
          ),
          isTelevision: false,
          bindMode: !holdHttp,
        ),
      );
      unawaited(
        navigator.currentState!.push(route).then((_) {
          routeCompleted++;
        }),
      );
      await pumpFavourites(tester);
      expect(httpEntered.isCompleted, isTrue);
      expect(unexpected, isEmpty);
      expect(requests, [
        Uri.parse('https://sources.invalid/stream/movie/$_id.json'),
      ]);
      if (holdHttp) {
        expect(find.byType(SourceRow), findsNothing);
        navigator.currentState!.pop();
        await pumpFavourites(tester);
        expect(routes.pops, [route]);
        expect(routeCompleted, 1);
        httpRelease.complete();
        await pumpFavourites(tester);
        expect(httpCompleted.isCompleted, isTrue);
        expect(find.byType(SourceRow), findsNothing);
        expect(backend.writes, isEmpty);
      } else {
        expect(find.byType(SourceRow), findsOneWidget);
        await tester.tap(find.byType(SourceRow));
        await tester.pump();
        await tester.tap(find.byType(SourceRow));
        await tester.pump();
        expect(backend.entered.isCompleted, isTrue);
        expect(backend.writes, hasLength(1));
        expect(backend.writes.single.$1, 'String');
        expect(backend.writes.single.$2, _physicalKey);
        expect(await backend.physical(), initial);
        // SDK cache is optimistic; it is not evidence of a durable write.
        final cached = await SharedPreferences.getInstance();
        expect(cached.getString(_key), backend.writes.single.$3);
        expect(routes.pops, isEmpty);
        expect(routeCompleted, 0);
        if (userPop) {
          navigator.currentState!.pop();
          await pumpFavourites(tester);
          expect(routes.pops, [route]);
          expect(routeCompleted, 1);
          expect(await backend.physical(), initial);
        }
        backend.release.complete();
        await pumpFavourites(tester);
        expect(backend.completed.isCompleted, isTrue);
        expect(backend.result, isTrue);
        finalPhysical = await backend.physical();
        finalPublic = await SeriesSourceService.getSources(_id);
        expect(routes.pops, [route]);
        expect(routeCompleted, 1);
        expect(find.byType(SourceRow), findsNothing);
      }
      expect(find.text('Sources origin parent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!httpRelease.isCompleted) httpRelease.complete();
      if (!backend.release.isCompleted) backend.release.complete();
      await pumpFavourites(tester);
    } finally {
      service.debugStreamHttpClientFactory = previousClient;
      service.invalidateCache();
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      EngineRegistry.instance.invalidateProfileScope();
      LocalEngineStorage.instance.resetProfileScope();
      client.close();
    }
  }
  // Global transport hooks are restored even if earlier assertions failed.
  expect(service.debugStreamHttpClientFactory, same(previousClient));
  expect(SharedPreferencesStorePlatform.instance, same(previousStore));
  expect(unexpected, isEmpty);
  expect(tester.takeException(), isNull);
  if (!holdHttp) {
    expect(backend.writes, hasLength(1));
    expect(finalPhysical![_physicalKey], backend.writes.single.$3);
    expect({...finalPhysical!}..remove(_physicalKey), initial);
    final raw = finalPhysical![_physicalKey] as String;
    expect(raw, isNot(contains(_signedUrl)));
    expect(raw, isNot(contains('synthetic-signature')));
    final descriptor = (jsonDecode(raw) as List).single as Map;
    expect(descriptor['debridService'], SeriesSource.addonDirectService);
    expect(descriptor['addonId'], addon.id);
    expect(descriptor['addonKey'], addon.sourceBindingKey);
    expect(descriptor['streamIndex'], 0);
    expect(
      descriptor['streamKey'],
      isA<String>().having((v) => v.isNotEmpty, 'nonempty', true),
    );
    expect(finalPublic, hasLength(1));
    expect(finalPublic!.single.toJson(), descriptor);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'origin Sources held addon completes after public route pop without late UI',
    (tester) => _case(tester, holdHttp: true, userPop: true),
  );
  testWidgets(
    'origin Sources double tap holds one physical movie bind before one pop',
    (tester) => _case(tester, holdHttp: false, userPop: false),
  );
  testWidgets(
    'origin Sources user pop while binding permits late persistence without another pop',
    (tester) => _case(tester, holdHttp: false, userPop: true),
  );
}
