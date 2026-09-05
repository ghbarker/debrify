import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/episodes_screen.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/video_player_launcher.dart';

import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'discover_screen_origin_test.dart' show mountDiscover;
import 'my_watchlist_loader_origin_test.dart' show HeldWatchlistPreferences;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

// Only media rendering and process IO are substituted. Discover, selection,
// source resolution, launcher persistence, routes and bridge observers are real.
class PlaybackTransport {
  late Future<void> Function() close;
  Completer<void>? streamHold;
  final process = Completer<ProcessResult>();
  final requests = <String>[];
  final commands = <List<String>>[];
  final launches = <VideoPlayerLaunchArgs>[];
  int external = 0;
  int returned = 0;
  void onExternal() => external++;
  void onReturned() => returned++;
  static const playerKey = ValueKey('terminal-player');
}

Future<PlaybackTransport> preparePlayback(
  WidgetTester tester, {
  bool external = false,
  bool legacyDetail = false,
  bool series = false,
}) async {
  await prepareFavourites(tester);
  final fixture = PlaybackTransport();
  final service = StremioService.instance;
  final previousStream = service.debugStreamHttpClientFactory;
  final previousValidator = StreamUrlValidator.clientFactory;
  final previousPlayer = VideoPlayerLauncher.debugPlayerWidgetBuilder;
  final previousProcess =
      WindowsExternalPlayerServiceExtension.debugWindowsProcessRun;
  // Register before installing anything. Drain real routes/held work and the
  // launcher's lifecycle timer before restoring hooks used by that work.
  var closed = false;
  fixture.close = () async {
    if (closed) return;
    closed = true;
    try {
      await closeFavourites(tester);
      final hold = fixture.streamHold;
      if (hold != null && !hold.isCompleted) hold.complete();
      if (!fixture.process.isCompleted) {
        fixture.process.complete(ProcessResult(0, 0, '', ''));
      }
      await pumpFavourites(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 30));
    } finally {
      // Even a failed drain must restore process-wide test dependencies. Let
      // the original cleanup exception propagate rather than hiding it.
      MainPageBridge.removeExternalPlayerLaunchListener(fixture.onExternal);
      MainPageBridge.removePlaybackReturnListener(fixture.onReturned);
      VideoPlayerLauncher.debugPlayerWidgetBuilder = previousPlayer;
      WindowsExternalPlayerServiceExtension.debugWindowsProcessRun =
          previousProcess;
      service.debugStreamHttpClientFactory = previousStream;
      StreamUrlValidator.clientFactory = previousValidator;
      service.invalidateCache();
    }
  };
  addTearDown(fixture.close);
  MainPageBridge.addExternalPlayerLaunchListener(fixture.onExternal);
  MainPageBridge.addPlaybackReturnListener(fixture.onReturned);
  VideoPlayerLauncher.debugPlayerWidgetBuilder = (args) {
    fixture.launches.add(args);
    return const Scaffold(body: SizedBox(key: PlaybackTransport.playerKey));
  };
  WindowsExternalPlayerServiceExtension.debugWindowsProcessRun = (exe, args) {
    fixture.commands.add([exe, ...args]);
    return fixture.process.future;
  };
  service.debugStreamHttpClientFactory = () => MockClient((request) async {
    fixture.requests.add(request.url.path);
    await fixture.streamHold?.future;
    return http.Response(
      jsonEncode({
        'streams': [
          {'name': 'Origin', 'url': 'https://video.invalid/movie.mp4'},
        ],
      }),
      200,
    );
  });
  StreamUrlValidator.clientFactory = () => MockClient((request) async {
    fixture.requests.add('${request.method} ${request.url}');
    return http.Response('', 200, headers: {'content-length': '100000000'});
  });
  service.invalidateCache();
  final addon = StremioAddon(
    id: 'playback.origin',
    name: 'Origin',
    manifestUrl: 'https://addon.invalid/manifest.json',
    baseUrl: 'https://addon.invalid',
    resources: ['stream'],
    types: ['movie', if (series) 'series'],
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('stremio_addons_v1', jsonEncode([addon.toJson()]));
  await StorageService.setDiscoverDefaultSource('cw');
  if (legacyDetail) await StorageService.setMergedSeriesPageEnabled(false);
  await StorageService.setHomeContinueWatchingEnabled(true);
  await StorageService.setPlayButtonMode('quick');
  await StorageService.setDefaultPlayerMode(external ? 'external' : 'internal');
  await StorageService.setPreferredWindowsExternalPlayer('system_default');
  final rules = await StorageService.getQuickPlayRules(isMovie: true);
  await StorageService.setQuickPlayRules(
    rules.copyWith(sourceMode: QuickPlaySourceMode.addonsOnly),
    isMovie: true,
  );
  if (series) {
    final seriesRules = await StorageService.getQuickPlayRules(isMovie: false);
    await StorageService.setQuickPlayRules(
      seriesRules.copyWith(
        sourceMode: QuickPlaySourceMode.addonsOnly,
        packPreference: QuickPlayPackPreference.exactEpisodeOnly,
      ),
      isMovie: false,
    );
  }
  await PlaybackProgressStore.saveContinueWatchingItem(
    imdbId: 'tt1234567',
    title: 'Transport origin',
    contentType: series ? 'series' : 'movie',
  );
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await mountDiscover(tester);
  return fixture;
}

ContinueWatchingSeeAllScreen playbackPanel(WidgetTester tester) =>
    tester.widget<ContinueWatchingSeeAllScreen>(
      find.byType(ContinueWatchingSeeAllScreen, skipOffstage: false),
    );

Future<void> saveReturnMarker() => PlaybackProgressStore.saveContinueWatchingItem(
  imdbId: 'tt7654321',
  title: 'Return marker',
  contentType: 'movie',
);

void main() {
  testWidgets(
    'origin same-ID art lookup and empty capture across mounted episode callback',
    (tester) async {
      final fixture = await preparePlayback(
        tester,
        legacyDetail: true,
        series: true,
      );
      final panel = playbackPanel(tester);
      panel.onOpen(panel.items.single);
      await pumpFavourites(tester);
      final detail = tester.widget<CatalogItemDetailScreen>(
        find.byType(CatalogItemDetailScreen),
      );
      detail.onLoaderArt!(const PlayLoaderArt(certificate: 'SERIES-ART'));
      detail.onBrowse();
      await pumpFavourites(tester);
      final episodes = tester.widget<EpisodesScreen>(
        find.byType(EpisodesScreen),
      );
      // This is an input to the actual mounted episode route's public callback.
      // It proves host forwarding, not that an episode tile/resume resolver
      // generated these coordinates or this deliberately different title.
      final selection = AdvancedSearchSelection(
        imdbId: episodes.show.imdbId!,
        isSeries: true,
        title: 'Different punctuation!',
        contentType: 'series',
        season: 2,
        episode: 3,
        year: '2024',
      );
      fixture.streamHold = Completer<void>();
      episodes.onQuickPlay!(selection);
      await pumpFavourites(tester);
      expect(find.text('SERIES-ART'), findsOneWidget);
      fixture.streamHold!.complete();
      await pumpFavourites(tester);
      final args = fixture.launches.last;
      expect(args.contentImdbId, episodes.show.imdbId);
      expect(args.contentTitle, 'Different punctuation!');
      expect(args.contentType, 'series');
      expect(args.contentSeason, 2);
      expect(args.contentEpisode, 3);
      expect(args.contentYear, '2024');
      expect(args.addonId, episodes.addon.id);
      expect(
        fixture.requests.any(
          (path) => Uri.decodeComponent(
            path,
          ).contains('/stream/series/tt1234567:2:3.json'),
        ),
        isTrue,
      );
      Navigator.of(
        tester.element(find.byKey(PlaybackTransport.playerKey)),
      ).pop();
      await pumpFavourites(tester);

      // A non-IMDb, artless catalog payload is supplied to the mounted public
      // callback: CW storage itself always supplies imdbId, so cannot represent
      // this input. No private host method or copied capture body is invoked.
      fixture.streamHold = Completer<void>();
      panel.onQuickPlay!(
        const StremioMeta(id: 'kitsu:42', type: 'movie', name: 'Artless'),
      );
      await pumpFavourites(tester);
      expect(find.text('Cancel'), findsOneWidget);
      expect(fixture.launches, hasLength(1));
      expect(find.text('SERIES-ART'), findsNothing);
      fixture.streamHold!.complete();
      await pumpFavourites(tester);
      expect(fixture.launches.last.contentImdbId, isNull);
      expect(fixture.launches.last.contentTitle, 'Artless');
      Navigator.of(
        tester.element(find.byKey(PlaybackTransport.playerKey)),
      ).pop();
      await pumpFavourites(tester);

      // Revisit the first identity without recapturing art: mere mismatch on the
      // artless play would leave the old art available here; actual clearing does not.
      StremioService.instance.invalidateCache();
      fixture.streamHold = Completer<void>();
      episodes.onQuickPlay!(selection);
      await pumpFavourites(tester);
      expect(find.text('SERIES-ART'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
      expect(fixture.launches, hasLength(2));
      fixture.streamHold!.complete();
      await pumpFavourites(tester);
      expect(fixture.launches.last.contentEpisode, 3);
      await fixture.close();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('origin detail rich loader art survives sparse catalog capture', (
    tester,
  ) async {
    final fixture = await preparePlayback(tester, legacyDetail: true);
    final panel = playbackPanel(tester);
    panel.onOpen(panel.items.single);
    await pumpFavourites(tester);
    final detail = tester.widget<CatalogItemDetailScreen>(
      find.byType(CatalogItemDetailScreen),
    );
    // Use the actual detail route's public enrichment sink. This characterizes
    // the host/art handoff, not the remote detail enrichment transport itself.
    detail.onLoaderArt!(
      const PlayLoaderArt(
        certificate: 'ORIGIN-CERT',
        runtimeLabel: 'ORIGIN-RUNTIME',
      ),
    );
    fixture.streamHold = Completer<void>();
    detail.onPlay();
    await pumpFavourites(tester);
    expect(fixture.requests, contains('/stream/movie/tt1234567.json'));
    expect(find.text('ORIGIN-CERT'), findsOneWidget);
    expect(find.text('ORIGIN-RUNTIME'), findsOneWidget);
    fixture.streamHold!.complete();
    await pumpFavourites(tester);
    expect(fixture.launches.single.contentImdbId, 'tt1234567');
    expect(fixture.launches.single.contentType, 'movie');
    expect(fixture.launches.single.contentTitle, 'Transport origin');
    // Loader art is not part of VideoPlayerLaunchArgs; the rendered loader
    // above, not these terminal metadata assertions, proves that handoff.
    await fixture.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'origin retained selection callbacks preserve disposed entry errors',
    (tester) async {
      final fixture = await preparePlayback(tester);
      final panel = playbackPanel(tester);
      panel.onOpen(panel.items.single);
      await pumpFavourites(tester);
      final detail = tester.widget<MergedDetailScreen>(
        find.byType(MergedDetailScreen),
      );
      final browse = detail.onItemSelected!;
      final play = detail.onQuickPlay!;
      await closeFavourites(tester);
      const empty = AdvancedSearchSelection(
        imdbId: '',
        isSeries: false,
        title: 'Disposed',
      );
      expect(() => browse(empty), returnsNormally);
      late Future<void> completion;
      expect(() => completion = play(empty), returnsNormally);
      await expectLater(completion, throwsA(isA<FlutterError>()));
      // Future error vs synchronous error is observable. Listener registration /
      // removal order is not exposed by this assertion and remains source proof.
      expect(fixture.requests, isEmpty);
      expect(fixture.launches, isEmpty);
      await fixture.close();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows transport disposed host ignores held launch completion',
    (tester) async {
      final fixture = await preparePlayback(tester, external: true);
      final panel = playbackPanel(tester);
      final item = panel.items.single;
      final isBound = panel.isBound!;
      expect(isBound(item), isFalse);
      panel.onQuickPlay!(item);
      await pumpFavourites(tester);
      expect(fixture.commands, hasLength(1));
      expect(fixture.external, 0);
      await closeFavourites(tester);
      // This is the actual host's retained live-map reader, not a snapshot of
      // its widget list. A late bound refresh would be visible after disposal.
      await SeriesSourceService.addSource(
        item.imdbId!,
        const SeriesSource(
          torrentHash: 'after-dispose',
          torrentName: 'Late binding',
          debridService: 'real_debrid',
          debridTorrentId: 'late',
          boundAt: 1,
        ),
      );
      fixture.process.complete(ProcessResult(0, 0, '', ''));
      await pumpFavourites(tester);
      expect(fixture.external, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFavourites(tester);
      expect(isBound(item), isFalse);
      expect(fixture.launches, isEmpty);
      // This proves observable suppression, not that the host's temporary
      // external listener was unregistered; its mounted guard can mask a leak.
      await fixture.close();
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  for (final result in [0, 1, 2, 'throw']) {
    testWidgets('Windows transport external result=$result', (tester) async {
      final fixture = await preparePlayback(tester, external: true);
      if (result == 1) {
        // The approved hook is at the explorer expression, also reached by
        // user custom commands; it is not gated to the systemDefault enum.
        await StorageService.setPreferredWindowsExternalPlayer(
          'custom_command',
        );
        await StorageService.setWindowsCustomCommand('explorer.exe {url}');
      }
      final panel = playbackPanel(tester);
      panel.onQuickPlay!(panel.items.single);
      await pumpFavourites(tester);
      expect(fixture.commands.single.first, 'explorer.exe');
      expect(
        fixture.commands.single,
        contains('https://video.invalid/movie.mp4'),
      );
      expect(fixture.external, 0);
      expect(fixture.launches, isEmpty);
      if (result == 'throw') {
        fixture.process.completeError(
          const ProcessException('explorer.exe', [], 'transport failure'),
        );
      } else {
        fixture.process.complete(
          ProcessResult(0, result as int, '', 'failure'),
        );
      }
      await pumpFavourites(tester);
      final success = result == 0 || result == 1;
      expect(fixture.external, success ? 1 : 0);
      expect(
        find.byKey(PlaybackTransport.playerKey),
        success ? findsNothing : findsOneWidget,
      );
      await saveReturnMarker();
      await pumpFavourites(tester);
      expect(
        playbackPanel(tester).items.map((m) => m.name),
        isNot(contains('Return marker')),
      );
      if (success) {
        // A resume without a cover must not count as playback returning.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFavourites(tester);
        expect(fixture.returned, 0);
        expect(
          playbackPanel(tester).items.map((m) => m.name),
          isNot(contains('Return marker')),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        // Failed process IO is caught by the real service; the launcher falls
        // through to its real in-app route, rather than throwing to the host.
        Navigator.of(
          tester.element(find.byKey(PlaybackTransport.playerKey)),
        ).pop();
      }
      await pumpFavourites(tester);
      expect(fixture.returned, success ? 1 : 0);
      expect(
        playbackPanel(tester).items.map((m) => m.name),
        contains('Return marker'),
      );
      await fixture.close();
      expect(tester.takeException(), isNull);
    }, skip: !Platform.isWindows);
  }

  testWidgets(
    'Windows transport external return defers to covering detail pop',
    (tester) async {
      final fixture = await preparePlayback(tester, external: true);
      final panel = playbackPanel(tester);
      panel.onQuickPlay!(panel.items.single);
      await pumpFavourites(tester);
      fixture.process.complete(ProcessResult(0, 0, '', ''));
      await pumpFavourites(tester);
      // Cover after handoff. A real detail route, not a fabricated isCurrent flag.
      panel.onOpen(panel.items.single);
      await pumpFavourites(tester);
      expect(find.byType(MergedDetailScreen), findsOneWidget);
      await saveReturnMarker();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFavourites(tester);
      expect(fixture.returned, 1);
      expect(
        playbackPanel(tester).items.map((m) => m.name),
        isNot(contains('Return marker')),
      );
      Navigator.of(tester.element(find.byType(MergedDetailScreen))).pop();
      await pumpFavourites(tester);
      expect(
        playbackPanel(tester).items.map((m) => m.name),
        contains('Return marker'),
      );
      await fixture.close();
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  testWidgets('transport actual player route holds refresh until pop', (
    tester,
  ) async {
    final fixture = await preparePlayback(tester);
    final panel = playbackPanel(tester);
    final item = panel.items.single;
    await PlaybackProgressStore.removeContinueWatchingItem(item.imdbId!);
    await StorageService.setMyWatchlistItem(item, true);
    expect(await StorageService.isInMyWatchlist(item), isTrue);
    panel.onQuickPlay!(panel.items.single);
    await pumpFavourites(tester);
    expect(find.byKey(PlaybackTransport.playerKey), findsOneWidget);
    expect(fixture.launches.single.contentImdbId, 'tt1234567');
    expect(fixture.requests, contains('/stream/movie/tt1234567.json'));
    expect(fixture.requests, contains('HEAD https://video.invalid/movie.mp4'));
    // The real launcher graduates watchlist content before the substituted
    // decoder route returns; the terminal widget does not perform these writes.
    expect(await StorageService.isInMyWatchlist(item), isFalse);
    await saveReturnMarker();
    await pumpFavourites(tester);
    expect(
      playbackPanel(tester).items.map((m) => m.name),
      isNot(contains('Return marker')),
    );
    Navigator.of(tester.element(find.byKey(PlaybackTransport.playerKey))).pop();
    await pumpFavourites(tester);
    expect(
      playbackPanel(tester).items.map((m) => m.name),
      contains('Return marker'),
    );
    expect(fixture.external, 0);
    await fixture.close();
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets('origin Discover held detail play cancel=$cancel', (
      tester,
    ) async {
      await prepareFavourites(tester);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.setPlayButtonMode('always');
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'tt1234567',
        title: 'Cancel origin',
        contentType: 'movie',
      );
      await mountDiscover(tester);
      final panel = tester.widget<ContinueWatchingSeeAllScreen>(
        find.byType(ContinueWatchingSeeAllScreen),
      );
      panel.onOpen(panel.items.single);
      await pumpFavourites(tester);
      final detail = tester.widget<MergedDetailScreen>(
        find.byType(MergedDetailScreen),
      );
      final prefs = await SharedPreferences.getInstance();
      final hold = HeldWatchlistPreferences({
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      });
      final previous = SharedPreferencesStorePlatform.instance;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = hold;
      addTearDown(() {
        if (!hold.release.isCompleted) hold.release.complete();
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = previous;
      });
      // This callback belongs to the detail route opened by actual Discover.
      // The existing preference transport holds all reads, not a synthetic host
      // method or a claimed independently isolated quick-play-rules read.
      final completion = detail.onResume(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hold.events, contains('read'));
      expect(find.text('Cancel'), findsOneWidget);
      if (cancel) {
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Cancel'), findsNothing);
      }
      hold.release.complete();
      await completion;
      await pumpFavourites(tester);
      expect(
        find.byType(TvHeldKeyGuard),
        cancel ? findsNothing : findsOneWidget,
      );
      if (!cancel) {
        Navigator.of(tester.element(find.byType(TvHeldKeyGuard))).pop();
        await pumpFavourites(tester);
      }
      expect(find.byType(MergedDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeFavourites(tester);
    });
  }

  testWidgets(
    'origin Discover quick-play opens actual sources and return reloads CW',
    (tester) async {
      await prepareFavourites(tester);
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setHomeContinueWatchingEnabled(true);
      await StorageService.setPlayButtonMode('always');
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'tt1234567',
        title: 'Playback origin',
        contentType: 'movie',
      );
      await mountDiscover(tester);
      final panel = tester.widget<ContinueWatchingSeeAllScreen>(
        find.byType(ContinueWatchingSeeAllScreen),
      );
      expect(panel.items.single.name, 'Playback origin');
      // Invoke the mounted public widget's real host callback, not a private
      // State method or a reproduction of the resolver/route implementation.
      panel.onQuickPlay!(panel.items.single);
      await pumpFavourites(tester);
      expect(find.byType(TvHeldKeyGuard), findsOneWidget);
      // The route widget's public constructor values are observed through its
      // public wrapper. Its private class/State is neither constructed nor called.
      final dynamic sources = tester
          .widget<TvHeldKeyGuard>(find.byType(TvHeldKeyGuard))
          .child;
      expect(sources.selection.imdbId, 'tt1234567');
      expect(sources.selection.isSeries, isFalse);
      expect(sources.selection.title, 'Playback origin');
      expect(sources.meta.imdbId, 'tt1234567');
      expect(sources.forcePlayOnTap, isTrue);
      expect(sources.bindMode, isFalse);
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'tt7654321',
        title: 'Saved while sources open',
        contentType: 'movie',
      );
      Navigator.of(tester.element(find.byType(TvHeldKeyGuard))).pop();
      await pumpFavourites(tester);
      expect(find.byType(TvHeldKeyGuard), findsNothing);
      final returned = tester.widget<ContinueWatchingSeeAllScreen>(
        find.byType(ContinueWatchingSeeAllScreen),
      );
      expect(
        returned.items.map((item) => item.name),
        contains('Saved while sources open'),
      );
      // This proves a sources-route return, not a native player launch/return.
      expect(tester.takeException(), isNull);
      await closeFavourites(tester);
    },
  );
}
