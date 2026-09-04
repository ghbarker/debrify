import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/home/home_row_family.dart';
import 'package:debrify/services/home/home_row_ids.dart';
import 'package:debrify/services/home/home_row_registry.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';

HomeRowFamily _fakeFamily() => HomeRowFamily(
  id: 'fake',
  prefix: 'fake:',
  groupName: 'Fake Family',
  boardSlot: HomeBoardSlot.section,
  canonicalIndex: 99,
  resolve: (ctx) => [
    ctx.defaultOnLeaf('fake:row', 'Fake Row', groupName: 'Fake Family'),
  ],
  boardIds: (_) => const ['fake:row'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(HomeRowRegistry.debugReset);

  test('production canonical order matches the pinned leaf sequence', () {
    final registry = HomeRowRegistry.production();
    final groups = registry.buildManagerModel(
      HomeRowResolveContext(mdblistEnabled: kMdblistEnabled),
    );
    expect(registry.canonicalOrderIds(groups), const [
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
  });

  test('adding a fake family appears in the manager and the board', () {
    final registry = HomeRowRegistry([
      ...HomeRowRegistry.production().families,
      _fakeFamily(),
    ]);
    const ctx = HomeRowResolveContext();
    final groups = registry.buildManagerModel(ctx);
    expect(groups.map((g) => g.name), contains('Fake Family'));
    expect(
      groups.expand((g) => g.items).map((it) => it.id),
      contains('fake:row'),
    );

    // No other edits: the board assembly iterates the registry, so the fake
    // family's boardIds show up even with an empty live-id set.
    expect(registry.canonicalBoardRailIds(ctx: ctx), contains('fake:row'));
  });

  test('board rails follow family slots, not manager group order', () {
    final registry = HomeRowRegistry.production();
    expect(
      registry.canonicalBoardRailIds(
        visibleIds: const [
          'fav:iptv',
          'cw:movies',
          'traktlist:watchlist',
          'com.linvo.cinemeta:movie:top',
        ],
      ),
      [
        'cw:movies',
        'fav:iptv',
        'traktlist:watchlist',
        'com.linvo.cinemeta:movie:top',
      ],
    );
  });

  test('sectionRowId keeps list, collection, and catalog grammar', () {
    expect(
      HomeRowRegistry.sectionRowId(
        listRowId: 'traktlist:watchlist',
        collectionRowId: null,
        addonId: 'x',
        catalogType: 'movie',
        catalogId: 'top',
      ),
      'traktlist:watchlist',
    );
    expect(
      HomeRowRegistry.sectionRowId(
        listRowId: null,
        collectionRowId: 'collection:abc',
        addonId: 'x',
        catalogType: 'movie',
        catalogId: 'top',
      ),
      'collection:abc',
    );
    expect(
      HomeRowRegistry.sectionRowId(
        listRowId: null,
        collectionRowId: null,
        addonId: 'com.linvo.cinemeta',
        catalogType: 'movie',
        catalogId: 'top',
      ),
      'com.linvo.cinemeta:movie:top',
    );
    expect(
      HomeRowIds.catalog('com.linvo.cinemeta', 'movie', 'top'),
      'com.linvo.cinemeta:movie:top',
    );
  });

  test('familyFor prefers prefix families over the catalog triple matcher', () {
    final registry = HomeRowRegistry.production();
    expect(registry.familyFor('cw:movies')?.id, 'cw');
    expect(registry.familyFor('traktlist:custom:7')?.id, 'traktlist');
    expect(registry.familyFor('mdblistlist:mine:1')?.id, 'mdblistlist');
    expect(registry.familyFor('collection:x')?.id, 'collection');
    expect(registry.familyFor('com.linvo.cinemeta:movie:top')?.id, 'catalog');
    expect(registry.familyFor('unknown'), isNull);
  });
}
