import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart' show installCatalog, page;

/// Pins the fix for the Canvas Home stage's rail-switch transition — the
/// DEFAULT TV Home layout (`StorageService.tvHomeStyleCached == 'canvas'`,
/// pinned by `tv_home_stage_layouts_pin_test.dart`). DPAD up/down between
/// catalog rows swaps the bottom shelf via an `AnimatedSwitcher` that
/// hardcoded a flat 200ms crossfade with no profile branch at all — a
/// completely separate mechanism from the row-widget scroll-follow sites
/// #283/#285 already fixed, so on the shipped default layout the Smooth/
/// Snappy toggle changed nothing for the one interaction most easily read as
/// "scrolling through catalogues".
///
/// Before the fix both profiles finish the crossfade by 220ms. After the
/// fix, snappy still finishes by 220ms (its shipped 200ms is unchanged), but
/// smooth resolves through `AppMotion.tvScroll` (260ms) and is still
/// mid-transition (both the outgoing and incoming rail's ListView present)
/// at that point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder strip() => find.byWidgetPredicate(
    (widget) =>
        widget is ListView &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('canvas-rail-'),
  );

  List<FocusNode> cwNodes(WidgetTester tester) => tester
      .widgetList<BoardCell>(find.byType(BoardCell))
      .map((cell) => cell.focusNode)
      .whereType<FocusNode>()
      .where((node) => node.debugLabel?.startsWith('search_cw_') ?? false)
      .toList();

  Future<void> prepare(WidgetTester tester) async {
    await prepareFavourites(tester);
    await StorageService.setTvHomeStyle('canvas');
    await HomePrefs.setHomeHeroSource(
      (mode: HomeHeroSourceMode.auto, ids: const []),
    );
    await HomePrefs.setHomeContinueWatchingEnabled(true);
    await HomePrefs.setHomeCwHoldToQuickPlay(false);
    for (var i = 0; i < 2; i++) {
      await PlaybackProgressStore.saveContinueWatchingItem(
        imdbId: 'canvas-motion-$i',
        title: 'Canvas motion $i',
        contentType: 'movie',
      );
    }
  }

  final expectedImages = {
    for (var i = 0; i < 2; i++) ...[
      'https://images.metahub.space/background/medium/canvas-motion-$i/img',
      'https://images.metahub.space/logo/medium/canvas-motion-$i/img',
    ],
  };

  Future<void> runInCanvas(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final unexpected = <String>[];
    await http.runWithClient(() async {
      try {
        await prepare(tester);
        await installCatalog();
        await mountFavourites(tester);
        await body();
        expect(unexpected, isEmpty);
      } finally {
        await closeFavourites(tester);
      }
    }, () => MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://board-origin.invalid/catalog/movie/rail.json') {
        return page(0, 12);
      }
      if (request.method == 'GET' && expectedImages.contains(url)) {
        return http.Response('', 404);
      }
      unexpected.add(url);
      return http.Response('{}', 404);
    }));
  }

  setUp(() {
    TvMotionController.debugReset();
    PlatformUtil.debugSetAndroidTvCached(true);
  });

  tearDown(() {
    TvMotionController.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
  });

  testWidgets(
    'snappy: rail-switch crossfade keeps its shipped 200ms — settled by '
    '220ms',
    (tester) async {
      await runInCanvas(tester, () async {
        final cw = cwNodes(tester);
        expect(cw, hasLength(2));
        cw.first.requestFocus();
        await pumpFavourites(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(
          strip(),
          findsOneWidget,
          reason: 'the snappy profile keeps its shipped 200ms crossfade, so '
              'only one rail strip should remain 220ms after the switch',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'smooth: rail-switch crossfade is the profile figure (260ms), not the '
    'old flat 200ms — still mid-transition at 220ms',
    (tester) async {
      TvMotionController.select(TvMotionProfile.smooth);
      await runInCanvas(tester, () async {
        final cw = cwNodes(tester);
        expect(cw, hasLength(2));
        cw.first.requestFocus();
        await pumpFavourites(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(
          strip(),
          findsNWidgets(2),
          reason:
              'the smooth profile (260ms) should still be crossfading the '
              'outgoing and incoming rail strips 220ms after the switch. A '
              'flat, profile-blind 200ms (the pre-fix behaviour) would '
              'already have settled to one strip by then, same as snappy.',
        );
        await tester.pump(const Duration(milliseconds: 60));
        expect(strip(), findsOneWidget);
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
