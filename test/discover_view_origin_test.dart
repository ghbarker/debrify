import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/services/discover_prefs.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/discover_card_settings_scope.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'discover_screen_origin_test.dart' show discoverSource, mountDiscover;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

Future<void> _mountOrigin(WidgetTester tester, String layout) async {
  await prepareFavourites(tester);
  StremioService.instance.invalidateCache();
  addTearDown(StremioService.instance.invalidateCache);
  final previousTitles = DiscoverPrefs.showTitles;
  addTearDown(() => DiscoverPrefs.setShowTitles(previousTitles));
  await StorageService.setDiscoverDefaultSource('cw');
  await StorageService.setDiscoverLayout(layout);
  await StorageService.setHomeContinueWatchingEnabled(true);
  await StorageService.saveContinueWatchingItem(
    imdbId: 'view-origin',
    title: 'View origin',
    contentType: 'movie',
  );
  await mountDiscover(tester, tv: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'origin Discover card settings retain panel State and source focus',
    (tester) async {
      await _mountOrigin(tester, 'grid');
      final host = tester.state(find.byType(SearchScreenHost));
      final panel = tester.state(find.byType(ContinueWatchingSeeAllScreen));
      final node = discoverSource(tester).focusNode!;
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      final before = tester
          .widget<DiscoverCardSettingsScope>(
            find.byType(DiscoverCardSettingsScope),
          )
          .showTitles;
      await DiscoverPrefs.setShowTitles(!before);
      MainPageBridge.discoverCardSettingsChanged!();
      await tester.pump();
      expect(
        tester
            .widget<DiscoverCardSettingsScope>(
              find.byType(DiscoverCardSettingsScope),
            )
            .showTitles,
        !before,
      );
      expect(
        identical(tester.state(find.byType(SearchScreenHost)), host),
        isTrue,
      );
      expect(
        identical(
          tester.state(find.byType(ContinueWatchingSeeAllScreen)),
          panel,
        ),
        isTrue,
      );
      expect(identical(discoverSource(tester).focusNode, node), isTrue);
      expect(node.hasFocus, isTrue);
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'origin Discover layout and narrow canvas remount panel with same source node',
    (tester) async {
      await _mountOrigin(tester, 'grid');
      final host = tester.state(find.byType(SearchScreenHost));
      final node = discoverSource(tester).focusNode!;
      var panel = tester.state(find.byType(ContinueWatchingSeeAllScreen));
      node.requestFocus();
      await tester.pump();
      await StorageService.setDiscoverLayout('stage');
      MainPageBridge.discoverLayoutChanged!();
      await pumpFavourites(tester);
      expect(panel.mounted, isFalse);
      expect(
        identical(tester.state(find.byType(SearchScreenHost)), host),
        isTrue,
      );
      expect(identical(discoverSource(tester).focusNode, node), isTrue);
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.stage,
      );
      // Origin remounts the panel but retains the shared source node's focus.
      expect(node.hasFocus, isTrue);
      panel = tester.state(find.byType(ContinueWatchingSeeAllScreen));
      tester.view.physicalSize = const Size(640, 1080);
      await tester.pump();
      expect(panel.mounted, isFalse);
      expect(find.byType(DiscoverTrailerStage), findsNothing);
      expect(identical(discoverSource(tester).focusNode, node), isTrue);
      expect(node.hasFocus, isTrue);
      panel = tester.state(find.byType(ContinueWatchingSeeAllScreen));
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pump();
      expect(panel.mounted, isFalse);
      expect(find.byType(DiscoverTrailerStage), findsOneWidget);
      expect(identical(discoverSource(tester).focusNode, node), isTrue);
      expect(node.hasFocus, isTrue);
      expect(
        identical(tester.state(find.byType(SearchScreenHost)), host),
        isTrue,
      );
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'origin Discover stage backdrop adopts replacement without grid dwell',
    (tester) async {
      await _mountOrigin(tester, 'stage');
      final shown = tester
          .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
          .shownItem;
      const first = StremioMeta(
        id: 'stage-one',
        type: 'movie',
        name: 'One',
        background: 'https://discover-view.invalid/stage-one.jpg',
      );
      const second = StremioMeta(
        id: 'stage-two',
        type: 'movie',
        name: 'Two',
        background: 'https://discover-view.invalid/stage-two.jpg',
      );
      AnimatedSwitcher backdrop() => tester
          .widgetList<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
          .singleWhere(
            (w) =>
                w.child is CachedNetworkImage &&
                (w.child! as CachedNetworkImage).imageUrl.startsWith(
                  'https://discover-view.invalid/',
                ),
          );
      shown.value = first;
      await tester.pump();
      expect(
        (backdrop().child! as CachedNetworkImage).imageUrl,
        first.background,
      );
      shown.value = second;
      await tester.pump();
      // Inspect the current child, not outgoing crossfade children. No elapsed
      // fake time: the stage has no additional 380ms backdrop dwell.
      expect(
        (backdrop().child! as CachedNetworkImage).imageUrl,
        second.background,
      );
      expect(backdrop().duration, const Duration(milliseconds: 240));
      shown.value = null;
      await tester.pump();
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CachedNetworkImage &&
              w.imageUrl.startsWith('https://discover-view.invalid/'),
        ),
        findsNothing,
      );
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
      // Desktop widget configuration only; the Android-TV snap branch and
      // downloaded pixels/native media execution are not exercised.
    },
  );

  testWidgets(
    'origin Discover grid backdrop first art, 380ms dwell, replacement and clear',
    (tester) async {
      await _mountOrigin(tester, 'grid');
      final shown = tester
          .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
          .shownItem;
      const first = StremioMeta(
        id: 'art-one',
        type: 'movie',
        name: 'One',
        background: 'https://discover-view.invalid/one.jpg',
      );
      const second = StremioMeta(
        id: 'art-two',
        type: 'movie',
        name: 'Two',
        background: 'https://discover-view.invalid/two.jpg',
      );
      const third = StremioMeta(
        id: 'art-three',
        type: 'movie',
        name: 'Three',
        background: 'https://discover-view.invalid/three.jpg',
      );
      List<String> art() => tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((w) => w.imageUrl)
          .where((url) => url.startsWith('https://discover-view.invalid/'))
          .toList();
      expect(art(), isEmpty);
      // Actual public notifier supplied by the mounted host to the real rail and
      // backdrop. Assert chosen image widgets, not downloaded pixels/native video.
      shown.value = first;
      await tester.pump();
      expect(art(), [first.background]);
      shown.value = second;
      await tester.pump(const Duration(milliseconds: 379));
      expect(art(), [first.background]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(art(), [second.background]);
      shown.value = first;
      await tester.pump(const Duration(milliseconds: 200));
      shown.value = third;
      await tester.pump(const Duration(milliseconds: 379));
      expect(art(), [second.background]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(art(), [third.background]);
      shown.value = second;
      await tester.pump(const Duration(milliseconds: 200));
      shown.value = null;
      await tester.pump();
      expect(art(), isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(art(), isEmpty);
      shown.value = first;
      await tester.pump();
      expect(art(), [first.background]);
      shown.value = const StremioMeta(
        id: 'no-art',
        type: 'movie',
        name: 'No art',
        poster: 'https://discover-view.invalid/poster.jpg',
      );
      await tester.pump();
      expect(art(), isEmpty);
      // A pending dwell is also cancelled when the real host is unmounted.
      shown.value = first;
      await tester.pump();
      shown.value = second;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await closeFavourites(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
