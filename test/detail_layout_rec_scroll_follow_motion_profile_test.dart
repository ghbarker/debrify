import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// Pins the fix for `DetailMarquee`'s rec-rail scroll-follow (mirrored
/// identically in `DetailConsole`/`DetailDossier` — see
/// `detail_layout_rec_scroll_follow_test.dart` for the shared fixture that
/// proves the scroll itself still lands, unaffected by this change).
///
/// The rail's `onFocusChange` hardcoded `duration: Duration.zero` — a bare
/// jump — regardless of the TV motion profile. PR #281 (this scroll-follow)
/// landed at 2026-09-07 21:39 and PR #276 (the motion profile) landed six
/// minutes later at 21:44, so #281 simply predates the profile and was never
/// migrated to read it, unlike every other TV scroll-follow site added
/// before #276.
///
/// Before the fix, both profiles jump instantly (`Duration.zero`), settling
/// in the same one or two `pumpAndSettle` frames. After the fix, snappy
/// keeps the instant jump but smooth now animates over `AppMotion.tvScroll`
/// (260ms), needing measurably more frames to land.
const _tv = Size(960, 540);

List<StremioMeta> _recs(int count) => [
  for (var i = 0; i < count; i++)
    StremioMeta(
      id: 'tt300$i',
      imdbId: 'tt300$i',
      type: 'movie',
      name: 'Rec $i',
      poster: null,
      background: null,
      description: null,
      year: '2020',
      genres: const [],
    ),
];

DetailModel _movieModel({required List<StremioMeta> recs}) {
  final item = StremioMeta(
    id: 'tt0000002',
    imdbId: 'tt0000002',
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
    imdbExtra: null,
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

Future<void> _pump(WidgetTester tester, Widget child) async {
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

Future<int> _focusCardAndSettle(WidgetTester tester, Finder list, int index) async {
  final cards = find.descendant(of: list, matching: find.byType(InkWell));
  final leaf = find
      .descendant(of: cards.at(index), matching: find.byType(ColoredBox))
      .first;
  final node = Focus.of(tester.element(leaf), createDependency: false);
  node.requestFocus();
  return tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TvMotionController.debugReset();
    // The scroll-follow's own TV gate reads the global platform flag, not
    // the fixture's DetailModel.isTelevision — force it on so the fixed
    // branch (`tv ? motion.tvScroll : Duration.zero`) actually engages.
    PlatformUtil.debugSetAndroidTvCached(true);
  });

  tearDown(() {
    TvMotionController.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
  });

  // The snappy-profile ceiling: how many `pumpAndSettle` frames the
  // unchanged instant jump needs.
  const snappyCeilingPumps = 3;


  testWidgets(
    'Marquee snappy: the rec rail still jumps instantly, within a couple of '
    'frames',
    (tester) async {
      final model = _movieModel(recs: _recs(20));
      await _pump(tester, DetailMarquee(model: model, episodesHost: null));

      final list = find.byType(ListView);
      final pumps = await _focusCardAndSettle(tester, list, 8);

      expect(
        pumps,
        lessThanOrEqualTo(snappyCeilingPumps),
        reason: 'snappy keeps the shipped instant jump',
      );
    },
  );

  testWidgets(
    'Marquee smooth: the rec rail now glides on AppMotion.tvScroll instead '
    'of the old unconditional instant jump',
    (tester) async {
      TvMotionController.select(TvMotionProfile.smooth);
      final model = _movieModel(recs: _recs(20));
      await _pump(tester, DetailMarquee(model: model, episodesHost: null));

      final list = find.byType(ListView);
      final pumps = await _focusCardAndSettle(tester, list, 8);

      // A generous margin above snappyCeilingPumps rather than a bare
      // greaterThan: the unconditional pre-fix Duration.zero already varies
      // by a pump or two run to run (observed 3-4), so a one-pump margin is
      // not a reliable signal. The real 260ms glide this fix adds needs
      // several more settle iterations (observed 6) — comfortably clear of
      // that noise floor.
      expect(
        pumps,
        greaterThanOrEqualTo(snappyCeilingPumps + 2),
        reason:
            'the smooth profile should glide over AppMotion.tvScroll '
            '(260ms), needing measurably more frames than the snappy '
            'instant jump. A pump count within a pump or two of the snappy '
            'ceiling means the rail is still on the old unconditional '
            'Duration.zero.',
      );
    },
  );
}
