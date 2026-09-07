import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

/// "Hide watched titles" reaches the detail page's More Like This rail.
///
/// The home rows and search already run their items through `WatchedFilter`;
/// the recommendation loaders did not, so a title you had finished kept
/// coming back as a suggestion under every related page. Both detail
/// screens now apply the same decider at load — single-shot, like the rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const watched = StremioMeta(
    id: 'tt0000001',
    imdbId: 'tt0000001',
    type: 'movie',
    name: 'Watched One',
  );
  const fresh = StremioMeta(
    id: 'tt0000002',
    imdbId: 'tt0000002',
    type: 'movie',
    name: 'Fresh Two',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    HideWatchedPrefs.debugReset();
    WatchedStatusService.instance.debugResetSnapshot();
  });

  tearDown(() {
    HideWatchedPrefs.debugReset();
    WatchedStatusService.instance.debugResetSnapshot();
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: CatalogItemDetailScreen(
          item: const StremioMeta(
            id: 'tt0903747',
            imdbId: 'tt0903747',
            type: 'movie',
            name: 'The Movie',
          ),
          isTelevision: true,
          onPlay: () {},
          onBrowse: () {},
          recommendationsLoader: () async => const [watched, fresh],
          onRecommendationTap: (_) {},
        ),
      ),
    );
    // Let the post-paint loaders resolve and the rail reveal.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('with hide-watched ON a watched recommendation is dropped', (
    tester,
  ) async {
    await HideWatchedPrefs.setEnabled(true);
    WatchedStatusService.instance.debugPublishSnapshot(
      movies: {watched.imdbId!},
    );

    await pumpDetail(tester);

    expect(find.text('More Like This', skipOffstage: false), findsOneWidget);
    expect(find.text('Fresh Two', skipOffstage: false), findsWidgets);
    expect(find.text('Watched One', skipOffstage: false), findsNothing);
  });

  testWidgets('with hide-watched OFF the same recommendation still shows', (
    tester,
  ) async {
    WatchedStatusService.instance.debugPublishSnapshot(
      movies: {watched.imdbId!},
    );
    expect(HideWatchedPrefs.enabled, isFalse);

    await pumpDetail(tester);

    expect(find.text('More Like This', skipOffstage: false), findsOneWidget);
    expect(find.text('Fresh Two', skipOffstage: false), findsWidgets);
    expect(find.text('Watched One', skipOffstage: false), findsWidgets);
  });
}
