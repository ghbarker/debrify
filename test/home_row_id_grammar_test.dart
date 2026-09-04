import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/screens/settings/home_sections_filter_page.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/simkl/simkl_list_source.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';

/// Frozen Home row-id grammar. Prefixes are a compatibility surface — renaming
/// a persisted id is not allowed (REFACTOR_PLAN §2.4). This suite pins today's
/// strings before H1 moves them behind a registry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('persisted prefixes', () {
    test('fixed default-on leaves keep todays ids', () {
      const fixed = [
        'cw:movies',
        'cw:series',
        'trakt:movies',
        'trakt:shows',
        'simkl:movies',
        'simkl:shows',
        'mdblist:movies',
        'mdblist:shows',
        'iptv:movies',
        'iptv:series',
        'watchlist:movies',
        'watchlist:series',
        'fav:playlist',
        'fav:debrify',
        'fav:stremio',
        'fav:iptv',
      ];
      expect(fixed.map((id) => id.split(':').first).toSet(), {
        'cw',
        'trakt',
        'simkl',
        'mdblist',
        'iptv',
        'watchlist',
        'fav',
      });
      // `mdblist:` (CW) vs `mdblistlist:` (opt-in lists): the extra "list"
      // before the colon means a naive `startsWith('mdblist:')` does NOT
      // match list ids. Matching must stay prefix-exact.
      expect('mdblistlist:mine:1'.startsWith('mdblist:'), isFalse);
      expect('mdblist:movies'.startsWith('mdblistlist:'), isFalse);
    });

    test('opt-in extra-row builders keep todays prefixes', () {
      expect(
        HomeExtraRowIds.traktBuiltin(TraktSeeAllList.watchlist),
        'traktlist:watchlist',
      );
      expect(
        HomeExtraRowIds.traktBuiltin(TraktSeeAllList.anticipated),
        'traktlist:anticipated',
      );
      expect(
        HomeExtraRowIds.traktUserList(
          TraktListChoice.userList({
            'name': 'Mine',
            'ids': {'trakt': 7, 'slug': 'mine'},
          }, liked: false),
        ),
        'traktlist:custom:7',
      );
      expect(
        HomeExtraRowIds.traktUserList(
          TraktListChoice.userList({
            'name': 'Theirs',
            'ids': {'trakt': 9, 'slug': 'theirs'},
          }, liked: true),
        ),
        'traktlist:liked:9',
      );
      expect(
        HomeExtraRowIds.simkl(SimklSeeAllList.planToWatch),
        'simkllist:planToWatch',
      );
      expect(
        HomeExtraRowIds.mdblistMine(
          const MdblistListChoice(id: 1, name: 'Mine'),
        ),
        'mdblistlist:mine:1',
      );
      expect(
        HomeExtraRowIds.mdblistLiked(
          const MdblistListChoice(id: 2, name: 'Liked', liked: true),
        ),
        'mdblistlist:liked:2',
      );
      expect(
        HomeExtraRowIds.mdblistTop(const MdblistListChoice(id: 3, name: 'Top')),
        'mdblistlist:top:3',
      );
      expect(HomeExtraRowIds.iptvList('abc'), 'iptvlist:abc');
    });

    test(
      'collection and folder-list prefixes stay collection:/collectionlist:',
      () {
        expect(HomeCollectionRowIds.collection('x'), 'collection:x');
        expect(HomeCollectionRowIds.prefix, 'collection:');
        expect(HomeCollectionRowIds.folderListPrefix, 'collectionlist:');
        const source = CollectionCatalogSource(
          addonId: 'com.linvo.cinemeta',
          type: 'movie',
          catalogId: 'top',
          genre: 'Action',
        );
        expect(
          HomeCollectionRowIds.folderList('c', 'f', source),
          'collectionlist:c:f:com.linvo.cinemeta:movie:top:Action',
        );
      },
    );

    test('addon catalog leaves are addonId:type:catalogId', () {
      // search_screen._sectionRowId / _catalogRefRowId, copied verbatim.
      const addonId = 'com.linvo.cinemeta';
      const type = 'movie';
      const catalogId = 'top';
      expect('$addonId:$type:$catalogId', 'com.linvo.cinemeta:movie:top');
    });

    test('tracker vs IPTV classifiers keep today\'s prefixes', () {
      expect(HomeExtraRowIds.isTracker('traktlist:watchlist'), isTrue);
      expect(HomeExtraRowIds.isTracker('simkllist:trending'), isTrue);
      expect(HomeExtraRowIds.isTracker('mdblistlist:mine:7'), isTrue);
      expect(HomeExtraRowIds.isTracker('iptvlist:x'), isFalse);
      expect(HomeExtraRowIds.isTracker('cw:movies'), isFalse);
      expect(HomeExtraRowIds.isIptv('iptvlist:x'), isTrue);
      expect(HomeExtraRowIds.isIptv('iptv:movies'), isFalse);
      expect(HomeExtraRowIds.iptvListId('iptvlist:x'), 'x');
      expect(HomeExtraRowIds.traktPrefix, 'traktlist:');
      expect(HomeExtraRowIds.simklPrefix, 'simkllist:');
      expect(HomeExtraRowIds.mdblistPrefix, 'mdblistlist:');
      expect(HomeExtraRowIds.iptvPrefix, 'iptvlist:');
    });
  });

  group('manager canonical order', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets(
      'empty saved order persists the boards built-in leaf sequence',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: HomeSectionsFilterPage(
              catalogTree: [],
              disabled: {},
              isTelevision: false,
            ),
          ),
        );
        await tester.pump();
        // Persist without rearranging: toggle a default-on leaf off and on
        // so _changed is true and _orderIds (canonical) is written.
        await tester.tap(find.text('Movies').first);
        await tester.pump();
        await tester.tap(find.text('Movies').first);
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        // Quirk: canonical order reserves slots for default-OFF tracker
        // list leaves so enabling one later does not append at the end.
        expect(await StorageService.getHomeRowOrder(), const [
          'cw:movies',
          'cw:series',
          'trakt:movies',
          'trakt:shows',
          'simkl:movies',
          'simkl:shows',
          'mdblist:movies',
          'mdblist:shows',
          'iptv:movies',
          'iptv:series',
          'watchlist:movies',
          'watchlist:series',
          'fav:playlist',
          'fav:debrify',
          'fav:stremio',
          'fav:iptv',
          'traktlist:watchlist',
          'traktlist:history',
          'traktlist:collection',
          'traktlist:ratings',
          'traktlist:recommendations',
          'traktlist:trending',
          'traktlist:popular',
          'traktlist:anticipated',
          'simkllist:planToWatch',
          'simkllist:watching',
          'simkllist:onHold',
          'simkllist:completed',
          'simkllist:dropped',
          'simkllist:ratings',
          'simkllist:trending',
          'simkllist:topRated',
          'simkllist:newAndUpcoming',
        ]);
      },
    );

    testWidgets('manager groups match todays rail labels', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeSectionsFilterPage(
            catalogTree: [],
            disabled: {},
            isTelevision: false,
          ),
        ),
      );
      await tester.pump();
      for (final name in const [
        'Continue Watching',
        'Trakt',
        'Simkl',
        'MDBList',
        'IPTV Continue Watching',
        'My Watchlist',
        'Favorites',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });
  });
}
