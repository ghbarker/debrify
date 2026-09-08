import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_focus_scroll_wrapper.dart';

/// Pins the fix for `TvFocusScrollWrapper` — the shared scroll-follow site
/// behind every YouTube/Reddit/Lemmy/IPTV results row, the episode list, and
/// the cloud/PikPak/Premiumize file browsers. Unlike the row-widget scroll
/// sites `tv_motion_profile_scroll_sites_test.dart` already pins, this one
/// hardcoded a flat 200ms glide with no profile branch at all, so switching
/// Appearance's Smooth/Snappy toggle never touched any list that goes
/// through it.
///
/// Before the fix both profiles glide at the identical, unconditional 200ms
/// literal, so the animation is always finished by 220ms in. After the fix,
/// snappy keeps that shipped 200ms figure (still finished by 220ms), but
/// smooth resolves to `AppMotion.tvScroll` (260ms) — still animating at
/// 220ms, and not settled until past 260ms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TvMotionController.debugReset();
    PlatformUtil.debugSetAndroidTvCached(true);
  });

  tearDown(() {
    TvMotionController.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
  });

  Future<(List<FocusNode>, ScrollController)> pumpList(
    WidgetTester tester,
  ) async {
    final nodes = List.generate(20, (i) => FocusNode(debugLabel: 'row-$i'));
    final scroll = ScrollController();
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
      scroll.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView.builder(
              controller: scroll,
              itemCount: nodes.length,
              itemBuilder: (context, i) => TvFocusScrollWrapper(
                child: SizedBox(
                  height: 80,
                  child: Focus(focusNode: nodes[i], child: Text('row $i')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (nodes, scroll);
  }

  testWidgets(
    'snappy: keeps the shipped 200ms glide — settled by 220ms',
    (tester) async {
      final (nodes, scroll) = await pumpList(tester);
      nodes[5].requestFocus();
      await tester.pump();
      await tester.pump(); // Start the animation clock without advancing time.
      expect(scroll.offset, 0);
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        scroll.position.isScrollingNotifier.value,
        isFalse,
        reason: 'the snappy profile keeps its shipped 200ms glide, so the '
            'scroll should already be settled 220ms after focus',
      );
      expect(scroll.offset, isNot(0.0));
    },
  );

  testWidgets(
    'smooth: the glide is the profile figure (260ms), not the old flat '
    '200ms — still animating at 220ms',
    (tester) async {
      TvMotionController.select(TvMotionProfile.smooth);
      final (nodes, scroll) = await pumpList(tester);
      nodes[5].requestFocus();
      await tester.pump();
      await tester.pump();
      expect(scroll.offset, 0);
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        scroll.position.isScrollingNotifier.value,
        isTrue,
        reason:
            'the smooth profile (260ms) should still be animating 220ms '
            'after focus. A flat, profile-blind 200ms (the pre-fix '
            'behaviour) would already be settled by then, same as snappy.',
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(microseconds: 1));
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      expect(scroll.offset, isNot(0.0));
    },
  );
}
