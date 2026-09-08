import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// The wide Showcase identity's metadata block.
///
/// The band used to render its metadata so faintly that a page with a full
/// IMDb enrichment read as having none: two genres, a 7.5pt rating box, the
/// certificate at 9.5pt in a tech line, three lines of 10.5pt plot. These pin
/// what the block must now SHOW — certificate badge, rating with vote count,
/// Metacritic, every genre, an expandable synopsis — and that it does so
/// without overflowing the screenful it is anchored to.
const _synopsis =
    'A high school chemistry teacher diagnosed with inoperable lung cancer '
    'turns to manufacturing and selling methamphetamine with a former student '
    'in order to secure his family\'s future. What begins as a desperate '
    'gamble becomes an empire, and the empire begins to consume everyone who '
    'stands near it — his family, his partner, and the man he used to be. '
    'Each season tightens the vice a little further until there is nowhere '
    'left to stand.';

DetailModel _model({
  bool isTelevision = false,
  bool withEnrichment = true,
  String? synopsis = _synopsis,
}) {
  final item = StremioMeta(
    id: 'tt0903747',
    imdbId: 'tt0903747',
    type: 'series',
    name: 'A Show',
    description: synopsis,
    year: '2008',
    genres: const ['Crime', 'Drama', 'Thriller', 'Mystery'],
  );
  return DetailModel(
    item: item,
    isMovie: false,
    isTelevision: isTelevision,
    accent: const Color(0xFFABA124),
    imdbExtra: withEnrichment
        ? const ImdbEnrichment(
            certificate: 'TV-MA',
            rating: 9.5,
            voteCount: 1834000,
            metacriticScore: 84,
            runtime: '49m',
          )
        : null,
    parentsGuide: null,
    recommendations: const [],
    primaryLabel: 'Resume',
    sourceCount: 0,
    hasTrailer: true,
    trailerBusy: false,
    trailerPlaying: false,
    hasTrakt: true,
    traktTracked: true,
    traktLabel: 'Watchlist',
    traktRating: 9,
    hasSimkl: false,
    simklTracked: false,
    simklLabel: 'Not tracked',
    simklRating: null,
    showPrimary: true,
    onPrimary: () {},
    onBrowse: null,
    onTrailer: () {},
    onSelectSource: () {},
    onAppMenu: () {},
    onTraktMenu: () {},
    onSimklMenu: () {},
    onTrackers: () {},
    onRecommendationTap: (_) {},
    onAmbientStill: (_) {},
    focus: DetailFocusCoordinator(
      backNode: FocusNode(debugLabel: 'test-back'),
      primaryEntry: FocusNode(debugLabel: 'test-primary'),
    ),
  );
}

/// The band as the Showcase page mounts it: inside a vertical list (unbounded
/// height), under the page's metrics scope, with a screenful height derived
/// from the viewport. [touch] false is the desktop/TV tier (k = 1).
Widget _host(
  DetailModel m,
  Size size, {
  bool touch = false,
  double textScale = 1.0,
}) {
  final actionNodes = [
    for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'act-$i'),
  ];
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: AppThemeScope(
        theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
        child: Scaffold(
          // Inside MaterialApp, which rebuilds MediaQuery from the view — an
          // outer wrapper's scaler would never reach the band.
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: ShowcaseMetricsScope(
                metrics: ShowcaseMetrics(size.width, touch: touch),
                child: ListView(
                  children: [
                    ShowcaseIdentity(
                      model: m,
                      primaryNode: m.focus.primaryEntry,
                      actionNodes: actionNodes,
                      onFocused: () {},
                      // What the layout hands it: the viewport less the peek.
                      height: size.height - 72,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _surface(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('the wide identity shows the metadata block at 1920×1080', (
    tester,
  ) async {
    const size = Size(1920, 1080);
    _surface(tester, size);
    await tester.pumpWidget(_host(_model(), size));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Certificate badge, rating with its vote count, Metacritic.
    expect(find.text('TV-MA'), findsOneWidget);
    expect(find.text('9.5'), findsOneWidget);
    expect(find.text('1.8M'), findsOneWidget);
    expect(find.text('84'), findsOneWidget);
    expect(find.text('METACRITIC '), findsOneWidget);

    // Year · runtime · EVERY genre, not the compact tier's two.
    expect(
      find.text('2008  ·  49m  ·  Crime  ·  Drama  ·  Thriller  ·  Mystery'),
      findsOneWidget,
    );

    // The synopsis is present, clamped, and expands in place.
    final synopsis = find.text(_synopsis);
    expect(synopsis, findsOneWidget);
    expect(tester.widget<Text>(synopsis).maxLines, 3);
    expect(find.text('MORE'), findsOneWidget);

    final before = tester.getSize(synopsis);
    await tester.tap(find.text('MORE'));
    await tester.pumpAndSettle();
    expect(find.text('LESS'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_synopsis)).maxLines, isNull);
    expect(
      tester.getSize(find.text(_synopsis)).height,
      greaterThan(before.height),
      reason: 'expanding must grow the text, not merely relabel the control',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'the band grows, never overflows',
    );

    await tester.tap(find.text('LESS'));
    await tester.pumpAndSettle();
    expect(find.text('MORE'), findsOneWidget);
  });

  testWidgets('the wide identity fits a 1280×720 window', (tester) async {
    const size = Size(1280, 720);
    _surface(tester, size);
    await tester.pumpWidget(_host(_model(), size));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TV-MA'), findsOneWidget);
    expect(find.text('MORE'), findsOneWidget);
  });

  testWidgets('the TV identity clamps the synopsis with no MORE affordance', (
    tester,
  ) async {
    const size = Size(960, 540);
    _surface(tester, size);
    await tester.pumpWidget(_host(_model(isTelevision: true), size));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TV-MA'), findsOneWidget);
    expect(find.text('9.5'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_synopsis)).maxLines, 3);
    // A GestureDetector is inert under a DPAD and the layout counts this
    // band's focus nodes; a MORE here would be a control nobody can reach.
    expect(find.text('MORE'), findsNothing);
  });

  testWidgets('the TV identity survives 1.8× text without overflowing', (
    tester,
  ) async {
    const size = Size(960, 540);
    _surface(tester, size);
    await tester.pumpWidget(
      _host(_model(isTelevision: true), size, textScale: 1.8),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The scale reached the band: the synopsis is taller than at 1×.
    final scaled = tester.getSize(find.text(_synopsis)).height;
    await tester.pumpWidget(_host(_model(isTelevision: true), size));
    await tester.pumpAndSettle();
    expect(scaled, greaterThan(tester.getSize(find.text(_synopsis)).height));
  });

  testWidgets('MORE is withheld when the synopsis already fits', (
    tester,
  ) async {
    const size = Size(1920, 1080);
    _surface(tester, size);
    await tester.pumpWidget(_host(_model(synopsis: 'A short plot.'), size));
    await tester.pumpAndSettle();
    expect(find.text('A short plot.'), findsOneWidget);
    expect(find.text('MORE'), findsNothing);
  });

  testWidgets('without enrichment the block degrades to what is known', (
    tester,
  ) async {
    const size = Size(1920, 1080);
    _surface(tester, size);
    await tester.pumpWidget(_host(_model(withEnrichment: false), size));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TV-MA'), findsNothing);
    expect(find.text('METACRITIC '), findsNothing);
    expect(
      find.text('2008  ·  Crime  ·  Drama  ·  Thriller  ·  Mystery'),
      findsOneWidget,
    );
  });
}
