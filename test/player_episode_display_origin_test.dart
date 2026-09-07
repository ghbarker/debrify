import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Origin pin for the player's episode display projection: the dock title,
// subtitle and OTT metadata that the real VideoPlayerScreen hands to Controls
// (touch) and TvControls (television). Harness copied from
// test/player_presentation_controls_origin_test.dart; only external SDK state,
// terminal player operations and the TVMaze transport are scripted. Title,
// subtitle and metadata are computed by real lib code.
class _TerminalStreams extends mk.PlatformPlayer {
  _TerminalStreams(mk.PlayerConfiguration configuration)
    : super(configuration: configuration);
}

class _Properties implements mk.NativePlayer {
  _Properties(mk.PlayerConfiguration configuration, this.unexpected)
    : _streams = _TerminalStreams(configuration);

  final _TerminalStreams _streams;
  @override
  mk.PlayerConfiguration get configuration => _streams.configuration;
  @override
  mk.PlayerState get state => _streams.state;
  @override
  set state(mk.PlayerState value) => _streams.state = value;
  @override
  mk.PlayerStream get stream => _streams.stream;

  final List<String> unexpected;
  final reads = <String>[];
  final writes = <(String, String)>[];
  bool closed = false;
  Future<void>? disposal;

  // Terminal responses only: an unscripted read answers empty, a write is
  // recorded. No host policy is copied here.
  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    reads.add(property);
    return '';
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    writes.add((property, value));
  }

  bool readySent = false;
  void sendReady() {
    if (readySent) return;
    readySent = true;
    configuration.ready!();
  }

  // External backend events after an open (as in the navigation pin): the
  // startup probe listens on width/duration; no host admission is copied.
  void emitOpened(mk.Playable playable, {required bool play}) {
    if (playable is! mk.Media) throw StateError('Expected one external media');
    state = state.copyWith(
      playlist: mk.Playlist([playable]),
      playing: play,
      completed: false,
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 60),
      width: 1280,
      height: 720,
      tracks: const mk.Tracks(),
    );
    sendReady();
    _streams.playlistController.add(state.playlist);
    _streams.durationController.add(state.duration);
    _streams.tracksController.add(state.tracks);
    _streams.widthController.add(state.width);
    _streams.heightController.add(state.height);
    _streams.positionController.add(state.position);
    _streams.playingController.add(play);
  }

  // A seek lands where it was asked (as in the navigation pin's seekTo).
  void emitPosition(Duration position) {
    state = state.copyWith(position: position);
    _streams.positionController.add(position);
  }

  void emitPlayback(Duration position) {
    state = state.copyWith(
      playing: true,
      duration: const Duration(minutes: 10),
      position: position,
    );
    _streams.durationController.add(state.duration);
    _streams.positionController.add(position);
    _streams.playingController.add(true);
  }

  @override
  Future<void> dispose({bool synchronized = true}) =>
      disposal ??= closeStreams();
  Future<void> closeStreams() async {
    await _streams.dispose();
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('native:${invocation.memberName}');
    throw StateError('Unexpected native API ${invocation.memberName}');
  }
}

class _Player implements mk.Player {
  _Player(this.backend);
  final _Properties backend;

  @override
  mk.PlatformPlayer? get platform => backend;
  @override
  set platform(mk.PlatformPlayer? value) =>
      throw StateError('Unexpected platform replacement');
  @override
  mk.PlayerState get state => backend.state;
  @override
  mk.PlayerStream get stream => backend.stream;
  @override
  Future<void> dispose() => backend.dispose();

  // Recorded terminal operations; no admission or selection policy.
  final operations = <String>[];
  final opened = <String>[];

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    if (playable is mk.Media) opened.add(playable.uri);
    operations.add('open');
    backend.emitOpened(playable, play: play);
  }

  @override
  Future<void> play() async {
    operations.add('play');
  }

  @override
  Future<void> pause() async {
    operations.add('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    operations.add('seek:${position.inMilliseconds}');
    backend.emitPosition(position);
  }

  @override
  Future<void> setRate(double value) async {
    operations.add('rate:$value');
    backend.state = backend.state.copyWith(rate: value);
  }

  @override
  Future<void> setVolume(double value) async {
    operations.add('volume:$value');
  }

  @override
  Future<void> setAudioTrack(mk.AudioTrack track) async {
    operations.add('audio:${track.id}');
  }

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    operations.add('subtitle:${track.id}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    backend.unexpected.add('player:${invocation.memberName}');
    throw StateError('Unexpected player API ${invocation.memberName}');
  }
}

class _TexturelessVideo implements mkv.VideoController {
  _TexturelessVideo(this.player, this.unexpected);
  @override
  final mk.Player player;
  final List<String> unexpected;
  @override
  final platform = Completer<mkv.PlatformVideoController>();
  @override
  final notifier = ValueNotifier<mkv.PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);

  void close() {
    notifier.dispose();
    id.dispose();
    rect.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('video:${invocation.memberName}');
    throw StateError('Unexpected video API ${invocation.memberName}');
  }
}

class _Terminal extends PlayerTerminalBackend {
  final construction = <String>[];
  final unexpected = <String>[];
  _Properties? properties;
  _Player? player;
  _TexturelessVideo? video;

  @override
  void ensureInitialized() {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('bootstrap');
  }

  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('player');
    expect(configuration.logLevel, mk.MPVLogLevel.error);
    expect(configuration.ready, isNotNull);
    properties = _Properties(configuration, unexpected);
    return player = _Player(properties!);
  }

  @override
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('video');
    expect(player, same(this.player));
    return video = _TexturelessVideo(player, unexpected);
  }
}

// Canned package:http transport. Planned GETs answer in order; anything else
// is a recorded 400 so TVMaze stays "unavailable" for the no-TVMaze cases.
const _tv = 'https://api.tvmaze.com';

class _Http {
  final planned = <(String, Object)>[];
  final observed = <String>[];
  final unplanned = <String>[];
  int consumed = 0;

  void plan(String url, Object json) => planned.add((url, json));

  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final description = '${request.method} ${request.url}';
    observed.add(description);
    if (consumed < planned.length &&
        request.method == 'GET' &&
        request.url.toString() == planned[consumed].$1) {
      final body = utf8.encode(jsonEncode(planned[consumed++].$2));
      return http.StreamedResponse(
        Stream<List<int>>.value(body),
        200,
        headers: const {'content-type': 'application/json'},
        request: request,
      );
    }
    unplanned.add(description);
    return http.StreamedResponse(
      Stream<List<int>>.value(const <int>[]),
      400,
      request: request,
    );
  }
}

class _HttpClient extends http.BaseClient {
  _HttpClient(this.canned);
  final _Http canned;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      canned.send(request);
}

Map<String, dynamic> _show(int id, String name) => {
  'id': id,
  'name': name,
  'externals': {'imdb': 'tt9999999'},
  'image': {'original': 'https://images.invalid/show', 'medium': 'medium'},
  'genres': ['Drama'],
  'language': 'English',
  'network': {
    'name': 'Fixture',
    'country': {'name': 'Fixture Country'},
  },
};

Map<String, dynamic> _episode(int number, String name) => {
  'season': 1,
  'number': number,
  'name': name,
  'airdate': '2020-01-0$number',
  'summary': '<p>Plot $number</p>',
  'runtime': 42,
  'image': {'medium': 'https://images.invalid/$number'},
  'rating': {'average': 8.5},
};

const _release = 'Origin.Show.S01E02.1080p.WEB-DL.mkv';

List<PlaylistEntry> _pack() => const [
  PlaylistEntry(
    url: 'https://episode.invalid/e1.mkv',
    title: 'Origin.Show.S01E01.mkv',
  ),
  PlaylistEntry(
    url: 'https://episode.invalid/e2.mkv',
    title: 'Origin.Show.S01E02.mkv',
  ),
  PlaylistEntry(
    url: 'https://episode.invalid/e3.mkv',
    title: 'Origin.Show.S01E03.mkv',
  ),
];

List<IptvChannel> _channels() => [
  IptvChannel(
    channelNumber: 5,
    name: 'News',
    url: 'https://episode.invalid/news.m3u8',
    group: 'World',
  ),
  IptvChannel(name: 'Weather', url: 'https://episode.invalid/weather.m3u8'),
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late _Terminal terminal;
  late _Http canned;
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    canned = _Http();
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'decoder-terminal-origin');
    StorageService.resetProfileCaches();
    EpisodeInfoService.dispose();
    await TVMazeService.clearCache();
    // clearCache keeps the availability flag; a prior case's 400 would leak
    // "unavailable" into this one. Re-probe through a throwaway canned client
    // (as the metadata origin test does), then clear the probe timestamp so
    // the host performs its own probe exactly as in a fresh process.
    await http.runWithClient(
      () => TVMazeService.refreshAvailability(),
      () => _HttpClient(_Http()..plan('$_tv/shows/1', {'id': 1})),
    );
    expect(TVMazeService.currentAvailability, isTrue);
    await TVMazeService.clearCache();
    MovieMetadataService.clearCache();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('episode-display-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    IptvMediaStore.debugResetMigration();
    await DebrifyTvDatabase.instance.database;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (
      call,
    ) async {
      switch (call.method) {
        case 'setFullScreen':
        case 'setBounds':
          return null;
        case 'getBounds':
          return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 720.0};
        case 'isFullScreen':
          return false;
        default:
          terminal.unexpected.add('window:${call.method}');
          throw StateError('Unexpected window call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(
      wake,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, (
      call,
    ) async {
      if (call.method == 'resetApplicationScreenBrightness') return null;
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      if (terminal.properties != null && !terminal.properties!.closed) {
        await terminal.properties!.dispose();
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      IptvMediaStore.debugResetMigration();
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
    } catch (error, stack) {
      debugPrintSynchronously('EPISODE_DISPLAY_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
    } finally {
      PlatformUtil.debugSetAndroidTvCached(null);
      PlayerTerminalBackend.debugOverride = previous;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      EpisodeInfoService.dispose();
      await TVMazeService.clearCache();
      MovieMetadataService.clearCache();
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
    }
  });

  Future<void> withHost(
    WidgetTester tester,
    VideoPlayerScreen screen,
    Future<void> Function(_Properties) exercise, {
    bool television = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    primaryFailure = null;
    primaryStack = null;
    expect(PlatformUtil.isAndroidTvCached, isFalse);
    if (television) PlatformUtil.debugSetAndroidTvCached(true);
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) => AppThemeScope(
              theme: AppThemes.byId('spotlight'),
              child: child!,
            ),
            home: screen,
          ),
        );
        // Accepted fixture construction bound, not a behavior timing assertion.
        for (var i = 0; i < 20 && terminal.video == null; i++) {
          await tester.pump();
        }
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        final backend = terminal.properties!;
        backend.sendReady();
        backend.emitPlayback(const Duration(seconds: 1));
        await tester.pump();
        // Fixture settle bound (not a timing assertion): a playlist launch
        // mounts the dock only after the existing 50x100ms empty-track
        // restore frontier; launch-time metadata futures (TVMaze via the
        // canned transport) settle in the same window.
        // The resume lookup awaits real I/O, so each turn also runs a real
        // async gap, as the navigation pin's `reach` does.
        final dock = find.byType(television ? TvControls : Controls);
        for (var i = 0; i < 200 && dock.evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump(const Duration(milliseconds: 50));
        }
        // Planned TVMaze requests are paced by the service's 100ms rate
        // limiter; advance the clock until every planned reply was consumed.
        for (
          var i = 0;
          i < 100 && canned.consumed < canned.planned.length;
          i++
        ) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump(const Duration(milliseconds: 100));
        }
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump();
        }
        backend.emitPlayback(const Duration(seconds: 2));
        await tester.pump();
        expect(dock, findsOneWidget);
        await exercise(backend);
        expect(terminal.unexpected, isEmpty);
        expect(canned.consumed, canned.planned.length);
      } catch (error, stack) {
        primaryFailure = error;
        primaryStack = stack;
        debugPrintSynchronously(
          'EPISODE_DISPLAY_UNEXPECTED ${terminal.unexpected} '
          'http=${canned.observed}',
        );
        debugPrintSynchronously('EPISODE_DISPLAY_PRIMARY $error\n$stack');
        rethrow;
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
          // Join the host's dispose-time playback-state writes with real
          // async turns so the shared sqflite lock is not left held by this
          // test's zone (the next launch's first resume read would hang).
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          if (terminal.properties != null) {
            await terminal.properties!.dispose();
          }
          expect(VideoOutputLease.isHeld, isFalse);
          expect(terminal.unexpected, isEmpty);
        } catch (error, stack) {
          debugPrintSynchronously('EPISODE_DISPLAY_CLEANUP $error\n$stack');
          if (primaryFailure != null) {
            Error.throwWithStackTrace(primaryFailure!, primaryStack!);
          }
          rethrow;
        }
      }
    }, () => _HttpClient(canned));
  }

  Controls controls(WidgetTester tester) =>
      tester.widget<Controls>(find.byType(Controls));
  TvControls tvControls(WidgetTester tester) =>
      tester.widget<TvControls>(find.byType(TvControls));

  VideoPlayerScreen single() => const VideoPlayerScreen(
    videoUrl: '',
    title: _release,
    subtitle: '1080p WEB-DL',
    contentTitle: 'The Show',
    contentType: 'series',
    contentSeason: 1,
    contentEpisode: 2,
    disableAutoResume: true,
  );

  VideoPlayerScreen debrifyTv() => VideoPlayerScreen(
    videoUrl: '',
    title: 'Debrify TV fixture',
    subtitle: 'Channel line',
    requestMagicNext: () async => null,
    disableAutoResume: true,
  );

  VideoPlayerScreen iptv(int start) => VideoPlayerScreen(
    videoUrl: '',
    title: 'IPTV fixture',
    iptvChannels: _channels(),
    iptvStartIndex: start,
    disableAutoResume: true,
  );

  VideoPlayerScreen pack() => VideoPlayerScreen(
    videoUrl: _pack()[1].url,
    title: _pack()[1].title,
    playlist: _pack(),
    startIndex: 1,
    contentType: 'series',
    disableAutoResume: true,
  );

  testWidgets(
    'single stream shows the catalog title and season, episode with the release line',
    (tester) async {
      await withHost(tester, single(), (backend) async {
        final dock = controls(tester);
        expect(dock.title, 'The Show');
        expect(dock.subtitle, 'Season 1, Episode 2 • 1080p WEB-DL');
        expect(dock.enhancedMetadata, isEmpty);
        expect(canned.observed, isEmpty);
      });
    },
  );

  testWidgets(
    'SxxExx pack without TVMaze shows Episode N and the parsed series name',
    (tester) async {
      await withHost(tester, pack(), (backend) async {
        expect(terminal.player!.opened, [_pack()[1].url]);
        final dock = controls(tester);
        expect(dock.title, 'Episode 2');
        // The filename-parsed series name is lowercase; the origin shows it
        // as parsed (release strings only as a last resort).
        expect(dock.subtitle, 'origin show • Season 1, Episode 2');
        expect(dock.enhancedMetadata, isEmpty);
        // The availability probe is answered 400: no show name, no episodes.
        expect(canned.observed, ['GET $_tv/shows/1']);
      });
    },
  );

  testWidgets(
    'TVMaze show name joins the episode title and leaves the subtitle',
    (tester) async {
      canned.plan('$_tv/shows/1', {'id': 1});
      canned.plan('$_tv/search/shows?q=origin%20show', [
        {'score': 1, 'show': _show(4102, 'Origin Show (2020)')},
      ]);
      canned.plan('$_tv/shows/4102/episodes', [
        _episode(1, 'Pilot'),
        _episode(2, 'Second Contact'),
        _episode(3, 'Third Light'),
      ]);
      await withHost(tester, pack(), (backend) async {
        final dock = controls(tester);
        expect(dock.title, 'Origin Show (2020) — Second Contact');
        expect(dock.subtitle, 'Season 1, Episode 2');
        expect(dock.enhancedMetadata['rating'], 8.5);
        expect(dock.enhancedMetadata['runtime'], 42);
        expect(dock.enhancedMetadata['airDate'], '2020-01-02');
        expect(dock.enhancedMetadata['network'], 'Fixture');
        expect(dock.enhancedMetadata['language'], 'English');
        expect(dock.enhancedMetadata['genres'], ['Drama']);
        expect(dock.enhancedMetadata['country'], 'Fixture Country');
        expect(dock.enhancedMetadata['plot'], 'Plot 2');
        expect(dock.enhancedMetadata.keys, [
          'rating',
          'runtime',
          'year',
          'airDate',
          'language',
          'genres',
          'network',
          'country',
          'plot',
        ]);
        // Skip-segment providers fire once the IMDB id is known (answered
        // 400); TVMaze itself must not be asked anything unplanned.
        expect(
          canned.unplanned.where((r) => r.contains('api.tvmaze.com')),
          isEmpty,
        );
      });
    },
  );

  testWidgets('IPTV launch shows the numbered channel name and its group', (
    tester,
  ) async {
    await withHost(tester, iptv(0), (backend) async {
      final dock = controls(tester);
      expect(dock.title, 'CH 5  News');
      expect(dock.subtitle, 'World');
      expect(dock.enhancedMetadata, isEmpty);
    });
  });

  testWidgets('IPTV channel without a group falls back to IPTV', (
    tester,
  ) async {
    await withHost(tester, iptv(1), (backend) async {
      final dock = controls(tester);
      expect(dock.title, 'Weather');
      expect(dock.subtitle, 'IPTV');
      expect(dock.enhancedMetadata, isEmpty);
    });
  });

  testWidgets(
    'Debrify TV launch without a playlist shows the launch title and subtitle',
    (tester) async {
      await withHost(tester, debrifyTv(), (backend) async {
        final dock = controls(tester);
        expect(dock.title, 'Debrify TV fixture');
        expect(dock.subtitle, 'Channel line');
        expect(dock.enhancedMetadata, isEmpty);
      });
    },
  );

  testWidgets('television dock marks the catalog title as clean', (
    tester,
  ) async {
    await withHost(tester, single(), television: true, (backend) async {
      final dock = tvControls(tester);
      expect(dock.title, 'The Show');
      expect(dock.titleIsClean, isTrue);
      expect(dock.subtitle, 'Season 1, Episode 2 • 1080p WEB-DL');
    });
  });

  testWidgets('television dock keeps the cleaner on a Debrify TV title', (
    tester,
  ) async {
    await withHost(tester, debrifyTv(), television: true, (backend) async {
      final dock = tvControls(tester);
      expect(dock.title, 'Debrify TV fixture');
      expect(dock.titleIsClean, isFalse);
      expect(dock.subtitle, 'Channel line');
    });
  });
}
