import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// Proves the "More like this" rail/grid in Marquee, Dossier and Console
/// scrolls to follow a card that gains focus, so the DPAD cursor is never
/// left on a card sitting outside the visible viewport.
///
/// The three layouts hand focus to a rec card two ways: arrow-key traversal
/// (which Flutter's own `FocusTraversalPolicy.inDirection` already reveals),
/// and a direct `FocusNode.requestFocus()` jump — `_focusCollection` /
/// `_focusFirstCell` (Marquee, Console) and `_focusRightPane` (Dossier) all
/// hand off this way when DOWN/RIGHT crosses in from the action row. A plain
/// `requestFocus()` does NOT go through the traversal policy, so it never
/// scrolls on its own — that gap is exactly the bug being fixed.
///
/// Each test reproduces it directly: build enough recommendations that a
/// lazily-built list constructs a handful past the visible edge (Flutter's
/// default ~250px cache extent) without scrolling to them, grab one of those
/// built-but-off-screen cards' FocusNode from the live tree, call
/// `requestFocus()` on it exactly as the layout's own jump helpers do, and
/// assert the card's rect ends up inside the scrollable's viewport.

const _tv = Size(960, 540);

List<StremioMeta> _recs(int count) => [
  for (var i = 0; i < count; i++)
    StremioMeta(
      id: 'tt100$i',
      imdbId: 'tt100$i',
      type: 'movie',
      name: 'Rec $i',
      poster: null,
      background: null,
      description: null,
      year: '2020',
      genres: const [],
    ),
];

DetailModel _movieModel({
  required List<StremioMeta> recs,
  ImdbEnrichment? imdbExtra,
}) {
  final item = StremioMeta(
    id: 'tt0000001',
    imdbId: 'tt0000001',
    type: 'movie',
    name: 'A Movie',
    poster: null,
    background: null,
    description: null,
    year: '2020',
    genres: const [],
  );
  return DetailModel(
    item: item,
    isMovie: true,
    isTelevision: true,
    accent: const Color(0xFFABA124),
    imdbExtra: imdbExtra,
    parentsGuide: null,
    recommendations: recs,
    primaryLabel: 'Play',
    sourceCount: 2,
    hasTrailer: false,
    trailerBusy: false,
    trailerPlaying: false,
    hasTrakt: false,
    traktTracked: false,
    traktLabel: 'Watchlist',
    traktRating: null,
    hasSimkl: false,
    simklTracked: false,
    simklLabel: 'Watching',
    simklRating: null,
    showPrimary: true,
    onPrimary: () {},
    onBrowse: null,
    onTrailer: () {},
    onSelectSource: () {},
    onAppMenu: () {},
    onTraktMenu: () {},
    onSimklMenu: () {},
    onRecommendationTap: (_) {},
    onAmbientStill: (_) {},
    focus: DetailFocusCoordinator(
      backNode: FocusNode(debugLabel: 'test-back'),
      primaryEntry: FocusNode(debugLabel: 'test-primary'),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required List<StremioMeta> recs,
  ImdbEnrichment? imdbExtra,
}) async {
  tester.view.physicalSize = _tv;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: DetailThemes.signal.ground,
          body: DetailThemeScope(theme: DetailThemes.signal, child: child),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

/// Grabs the [index]th rec card's own FocusNode from inside [scrollable] —
/// whether or not the card wires one in explicitly (Marquee/Console pass one
/// in; Dossier's `_RecPoster` lets `InkWell` create its own) — and hands
/// focus to it directly, exactly as `_focusCollection` / `_focusFirstCell` /
/// `_focusRightPane` do in production.
Future<Rect?> _requestFocusOnCard(
  WidgetTester tester,
  Finder scrollable,
  int index,
) async {
  final cards = find.descendant(
    of: scrollable,
    matching: find.byType(InkWell),
  );
  final built = cards.evaluate().length;
  expect(
    index,
    lessThan(built),
    reason: 'fixture did not lazily-build a card at index $index '
        '(only $built built) — widen the recommendation list',
  );
  // Any descendant of the InkWell finds the same governing FocusNode,
  // regardless of whether the card supplied its own.
  final leaf = find
      .descendant(of: cards.at(index), matching: find.byType(ColoredBox))
      .first;
  final node = Focus.of(tester.element(leaf), createDependency: false);
  node.requestFocus();
  await tester.pump();
  // The fix's ensureVisible runs in a post-frame callback.
  await tester.pump();
  await tester.pump();

  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null || !ctx.mounted) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  testWidgets(
    'Marquee: jumping focus onto an off-screen rec card scrolls it into view',
    (tester) async {
      final model = _movieModel(recs: _recs(20));
      await _pump(
        tester,
        DetailMarquee(model: model, episodesHost: null),
        recs: _recs(20),
      );

      final list = find.byType(ListView);
      final rect = await _requestFocusOnCard(tester, list, 8);
      expect(rect, isNotNull, reason: 'requestFocus did not take');

      final viewport = tester.getRect(list.first);
      expect(
        viewport.left <= rect!.left + 0.5 && rect.right <= viewport.right + 0.5,
        isTrue,
        reason: 'focused card $rect is outside viewport $viewport',
      );
    },
  );

  testWidgets(
    'Dossier: jumping focus onto an off-screen rec card scrolls it into view',
    (tester) async {
      final model = _movieModel(recs: _recs(20));
      await _pump(
        tester,
        DetailDossier(model: model, episodesHost: null),
        recs: _recs(20),
      );

      // Cast/details/guide are all empty in this fixture, so the reference
      // pane's only content is the horizontal "More like this" list.
      final list = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      );
      final rect = await _requestFocusOnCard(tester, list, 5);
      expect(rect, isNotNull, reason: 'requestFocus did not take');

      final viewport = tester.getRect(list.first);
      expect(
        viewport.left <= rect!.left + 0.5 && rect.right <= viewport.right + 0.5,
        isTrue,
        reason: 'focused card $rect is outside viewport $viewport',
      );
    },
  );

  testWidgets(
    'Console: jumping focus onto an off-screen grid cell scrolls it into view',
    (tester) async {
      final model = _movieModel(
        recs: _recs(30),
        // Non-empty cast puts the reference rail beside the grid (wide/TV
        // side-by-side layout), so the grid gets its own bounded,
        // independently-scrolling viewport instead of the shrink-wrapped,
        // whole-page-scrolls stacked one.
        imdbExtra: const ImdbEnrichment(cast: [CastMember(name: 'Someone')]),
      );
      await _pump(
        tester,
        DetailConsole(model: model, episodesHost: null),
        recs: _recs(30),
        imdbExtra: const ImdbEnrichment(cast: [CastMember(name: 'Someone')]),
      );

      final grid = find.byType(GridView);
      final rect = await _requestFocusOnCard(tester, grid, 4);
      expect(rect, isNotNull, reason: 'requestFocus did not take');

      final viewport = tester.getRect(grid.first);
      expect(
        viewport.top <= rect!.top + 0.5 && rect.bottom <= viewport.bottom + 0.5,
        isTrue,
        reason: 'focused cell $rect is outside viewport $viewport',
      );
    },
  );
}
