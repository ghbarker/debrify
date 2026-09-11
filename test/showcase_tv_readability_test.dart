import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _story =
    'A family of four are suddenly sealed inside their home with no '
    'way out, and must work together to survive against both their dwindling '
    'resources and the mysterious, looming threat that is keeping them trapped.';
const _longTitle = 'The Last House Beyond the Mountains and the Distant Sea';
const _capture = bool.fromEnvironment('READABILITY_CAPTURE');
const _baseline = bool.fromEnvironment('READABILITY_BASELINE');

DetailModel _model(
  DetailFocusCoordinator focus, {
  required bool tv,
  bool playing = false,
  bool series = false,
  bool logo = false,
  VoidCallback? play,
  VoidCallback? trailer,
}) => DetailModel(
  item: StremioMeta(
    id: 'readability-fixture',
    type: series ? 'series' : 'movie',
    name: _longTitle,
    description: _story,
    year: '2026',
    genres: const ['Action', 'Horror'],
    logo: logo ? 'https://readability.invalid/logo.png' : null,
  ),
  metadataPreferences: MetadataPreferences(features: {}),
  isMovie: !series,
  isTelevision: tv,
  accent: Colors.white,
  imdbExtra: const ImdbEnrichment(
    rating: 5.5,
    top250Rank: 2,
    meterRank: 38,
    certificate: 'PG-13',
  ),
  parentsGuide: null,
  recommendations: const [],
  primaryLabel: 'Play',
  sourceCount: 0,
  hasTrailer: true,
  trailerBusy: false,
  trailerPlaying: playing,
  hasTrakt: false,
  traktTracked: false,
  traktLabel: '',
  traktRating: null,
  hasSimkl: false,
  simklTracked: false,
  simklLabel: '',
  simklRating: null,
  showPrimary: true,
  onPrimary: play ?? () {},
  onBrowse: () {},
  onTrailer: trailer ?? () {},
  onSelectSource: () {},
  onAppMenu: () {},
  onTraktMenu: () {},
  onSimklMenu: () {},
  onTrackers: () {},
  onToggleMyWatchlist: () {},
  onMetadataExplore: () {},
  onRecommendationTap: (_) {},
  onAmbientStill: (_) {},
  focus: focus,
);

EpisodesPanelView _episodes(VoidCallback play) {
  final eps = [
    for (var i = 1; i <= 3; i++)
      TraktEpisode(
        season: 1,
        number: i,
        title: 'Episode $i with a long title',
        overview: _story,
      ),
  ];
  return EpisodesPanelView(
    seasons: [TraktSeason(number: 1, episodeCount: 3, episodes: eps)],
    selectedSeasonNumber: 1,
    episodes: eps,
    loading: false,
    unavailable: false,
    showImageUrl: null,
    generation: 1,
    landing: eps.first,
    focusIntent: EpisodeFocusIntent.none,
    progressOf: (_) => null,
    isNext: (e) => e.number == 1,
    play: (_) => play(),
    options: (_) {},
    stepSeason: (_) {},
    selectSeason: (_) {},
    onLeftEdge: null,
    onRetry: () {},
    onSearchForSources: () {},
  );
}

Future<void> _mount(
  WidgetTester tester,
  DetailModel model,
  Size logical, {
  double dpr = 1,
  bool series = false,
  VoidCallback? episodePlay,
}) async {
  tester.view.physicalSize = logical * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  // Use a bundled real font for screenshots and overflow checks, rather than
  // Ahem test blocks. This fixture does not change the app's production fonts.
  await tester.runAsync(() async {
    for (final (family, asset) in [
      ('Inter', 'assets/fonts/Inter-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Inter'),
      home: AppThemeScope(
        theme: AppThemes.byId('spotlight'),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: RepaintBoundary(
            key: const ValueKey('readability-capture'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Native underlay is outside Flutter; this is its actual foreground
                // layout and trailer-playing model, without a fake decoder/player.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Focus(
                    focusNode: model.focus.backNode,
                    child: const SizedBox.square(dimension: 1),
                  ),
                ),
                DetailShowcase(
                  model: model,
                  dpad: model.isTelevision,
                  episodesHost: series
                      ? (builder) => Builder(
                          builder: (context) =>
                              builder(context, _episodes(episodePlay ?? () {})),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _identity => find.byType(ShowcaseIdentity);
Finder _inIdentity(Finder child) =>
    find.descendant(of: _identity, matching: child);

Future<void> _dispose(WidgetTester tester, DetailFocusCoordinator focus) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  focus.backNode.dispose();
  focus.primaryEntry.dispose();
}

void main() {
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (final playing in [false, true]) {
      testWidgets(
        'TV $size trailer=$playing has larger real text and reachable controls',
        (tester) async {
          final focus = DetailFocusCoordinator(
            backNode: FocusNode(),
            primaryEntry: FocusNode(),
          );
          var plays = 0;
          var trailers = 0;
          await _mount(
            tester,
            _model(
              focus,
              tv: true,
              playing: playing,
              play: () => plays++,
              trailer: () => trailers++,
            ),
            size,
            dpr: 1.5,
          );
          final synopsis = tester.widget<Text>(_inIdentity(find.text(_story)));
          final title = tester.widget<Text>(_inIdentity(find.text(_longTitle)));
          final play = tester.widget<Text>(_inIdentity(find.text('Play')));
          final paragraph = tester.renderObject<RenderParagraph>(
            _inIdentity(find.text(_story)),
          );
          // Observe actual Text/RenderParagraph, never a parallel sizing formula.
          final target = _baseline ? 10.5 : 14.7;
          expect(synopsis.style!.fontSize, closeTo(target, .001));
          expect(
            paragraph.textScaler.scale(synopsis.style!.fontSize!),
            closeTo(target, .001),
          );
          expect(title.style!.fontSize, closeTo(_baseline ? 39 : 54.6, .001));
          expect(play.style!.fontSize, closeTo(target, .001));
          final button = find
              .ancestor(
                of: _inIdentity(find.text('Play')),
                matching: find.byType(AnimatedContainer),
              )
              .first;
          expect(
            tester.getSize(button).height,
            closeTo(_baseline ? 30 : 42, .001),
          );
          expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
          expect(
            tester.getSize(button).width,
            lessThan(200),
            reason: 'Play stays a compact pill rather than filling the Wrap',
          );
          expect(focus.primaryEntry.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(plays, 1);
          // Watchlist, tracker, then Trailer: focus expands each real action pill.
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(trailers, 1);
          expect(tester.takeException(), isNull);
          if (_capture && size.width == 1280 && playing) {
            focus.primaryEntry.requestFocus();
            await tester.pumpAndSettle();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('readability-capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('.dart_tool/readability').create(recursive: true);
              await File(
                '.dart_tool/readability/${_baseline ? 'before' : 'after'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pump();
          }
          await _dispose(tester, focus);
        },
      );
    }
  }

  testWidgets('TV logo has a larger proportional viewport', (tester) async {
    final focus = DetailFocusCoordinator(
      backNode: FocusNode(),
      primaryEntry: FocusNode(),
    );
    await _mount(
      tester,
      _model(focus, tv: true, logo: true),
      const Size(1280, 720),
    );
    final logo = tester.widget<CachedNetworkImage>(
      _inIdentity(find.byType(CachedNetworkImage)).first,
    );
    expect(logo.width, closeTo(_baseline ? 235 : 574, .001));
    expect(logo.height, closeTo(_baseline ? 60 : 109.2, .001));
    expect(tester.takeException(), isNull);
    await _dispose(tester, focus);
    if (!_baseline) {
      // Exercise the selected production image callbacks in the same tight
      // constraints as CachedNetworkImage, including a failed logo download.
      // A network transport is unnecessary to test these rendering branches.
      final provider = MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
      Widget frame(WidgetBuilder builder) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: logo.width,
            height: logo.height,
            child: Builder(builder: builder),
          ),
        ),
      );
      await tester.pumpWidget(
        frame((context) => logo.imageBuilder!(context, provider)),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Image)), const Size(329, 84));
      await tester.pumpWidget(
        frame(
          (context) => logo.errorWidget!(
            context,
            'https://readability.invalid/logo.png',
            const HttpException('fixture'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(find.text(_longTitle));
      expect(title.style!.fontSize, closeTo(54.6, .001));
      expect(find.byType(FittedBox), findsNothing);
      expect(
        tester.getSize(find.text(_longTitle)).height,
        lessThanOrEqualTo(109.2),
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('TV $size episode DPAD survives the enlarged identity', (
      tester,
    ) async {
      final focus = DetailFocusCoordinator(
        backNode: FocusNode(),
        primaryEntry: FocusNode(),
      );
      var played = 0;
      await _mount(
        tester,
        _model(focus, tv: true, series: true),
        size,
        series: true,
        episodePlay: () => played++,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(played, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(played, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focus.primaryEntry.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await _dispose(tester, focus);
    });
  }

  testWidgets('wide touch identity keeps its existing typography', (
    tester,
  ) async {
    final focus = DetailFocusCoordinator(
      backNode: FocusNode(),
      primaryEntry: FocusNode(),
    );
    await _mount(tester, _model(focus, tv: false), const Size(960, 720));
    expect(
      tester.widget<Text>(_inIdentity(find.text(_story))).style!.fontSize,
      10.5,
    );
    expect(
      tester.widget<Text>(_inIdentity(find.text(_longTitle))).style!.fontSize,
      39,
    );
    expect(tester.takeException(), isNull);
    await _dispose(tester, focus);
  });
}
