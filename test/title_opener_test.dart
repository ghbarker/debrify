import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/episodes_screen.dart'
    show kCatalogDetailRouteName;
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/search/title_opener.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_continue_watching_service.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/trakt/trakt_continue_watching_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

StremioAddon _addon(String id) => StremioAddon(
  id: id,
  name: 'Addon $id',
  manifestUrl: 'https://example/$id/manifest.json',
  baseUrl: 'https://example/$id',
);

StremioMeta _meta({
  required String id,
  required String type,
  String? imdbId,
  StremioAddon? sourceAddon,
  String name = 'Title',
}) => StremioMeta(
  id: id,
  imdbId: imdbId,
  type: type,
  name: name,
  sourceAddon: sourceAddon,
);

/// Same IMDb extraction `_imdbOf` uses on SearchScreenState.
String? _imdbOf(StremioMeta item) {
  final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return (id != null && id.isNotEmpty) ? id : null;
}

class _PushObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MainPageBridge.switchTab = null;
  });

  tearDown(() {
    MainPageBridge.switchTab = null;
  });

  testWidgets('merged flag sends series and movies to MergedDetailScreen', (
    tester,
  ) async {
    final observer = await _pumpHost(tester);
    final opener = _opener(tester, mergedSeriesPage: true);
    final ctx = tester.element(find.byType(Scaffold));

    opener.open(
      _meta(id: 'tt1', type: 'series', imdbId: 'tt1'),
      _addon('cine'),
    );
    final seriesRoute = observer.pushed.last as MaterialPageRoute;
    expect(seriesRoute.settings.name, kCatalogDetailRouteName);
    expect(seriesRoute.builder(ctx), isA<MergedDetailScreen>());

    opener.open(_meta(id: 'tt2', type: 'movie', imdbId: 'tt2'), _addon('cine'));
    expect(
      (observer.pushed.last as MaterialPageRoute).builder(ctx),
      isA<MergedDetailScreen>(),
      reason:
          'quirk: comment says movies fall through to CatalogItemDetailScreen, '
          'but the predicate is (series || movie) && merged flag',
    );
  });

  testWidgets(
    'flag off and non-movie/series types stay on CatalogItemDetailScreen',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));

      _opener(
        tester,
      ).open(_meta(id: 'tt1', type: 'series', imdbId: 'tt1'), _addon('cine'));
      expect(
        (observer.pushed.last as MaterialPageRoute).builder(ctx),
        isA<CatalogItemDetailScreen>(),
      );

      _opener(
        tester,
        mergedSeriesPage: true,
      ).open(_meta(id: 'ch1', type: 'tv', imdbId: 'tt9'), _addon('cine'));
      expect(
        (observer.pushed.last as MaterialPageRoute).builder(ctx),
        isA<CatalogItemDetailScreen>(),
        reason: 'tv/channel types never take the merged path',
      );
    },
  );

  testWidgets(
    'buildMenuOptions appends local CW and Trakt CW; MDBList CW stays off Trakt strip',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));
      final traktItem = TraktContinueWatchingItem(
        meta: _meta(id: 'tt1', type: 'series', imdbId: 'tt1'),
        traktContentType: 'episodes',
      );
      final mdblistItem = MdblistContinueWatchingItem(
        selection: const AdvancedSearchSelection(
          imdbId: 'tt1',
          isSeries: true,
          title: 'Title',
        ),
        paused: true,
      );
      _opener(
        tester,
        mergedSeriesPage: true,
        isTraktAuthenticated: true,
        isMdblistAuthenticated: true,
        cwIds: {'tt1'},
        traktByImdb: {'tt1': traktItem},
        mdblistByImdb: {'tt1': mdblistItem},
      ).open(_meta(id: 'tt1', type: 'series', imdbId: 'tt1'), _addon('cine'));

      final screen =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(
        screen.traktMenuOptions.map((o) => o.action),
        containsAll([
          TraktItemMenuAction.removeFromPlayback,
          TraktItemMenuAction.removeFromTraktPlayback,
        ]),
      );
      expect(
        screen.traktMenuOptions.any(
          (o) =>
              o.action == TraktItemMenuAction.removeFromPlayback && !o.isTrakt,
        ),
        isTrue,
      );
      expect(
        screen.traktMenuOptions.any(
          (o) =>
              o.action == TraktItemMenuAction.removeFromTraktPlayback &&
              o.isTrakt,
        ),
        isTrue,
      );
      expect(
        screen.mdblistMenuOptions.map((o) => o.action),
        contains(MdblistItemMenuAction.removeFromContinueWatching),
      );

      expect(
        screen.traktMenuOptions.map((o) => o.action),
        contains(TraktItemMenuAction.addToWatchlist),
        reason: 'status-null strip is add-only for Trakt library actions',
      );

      final rebuilt = screen.traktMenuBuilder!(
        const TraktTitleStatus(inWatchlist: true),
      );
      expect(
        rebuilt.map((o) => o.action),
        contains(TraktItemMenuAction.removeFromWatchlist),
      );
      expect(
        rebuilt.map((o) => o.action),
        containsAll([
          TraktItemMenuAction.removeFromPlayback,
          TraktItemMenuAction.removeFromTraktPlayback,
        ]),
      );
    },
  );

  testWidgets(
    'Simkl CW remove keys off progress != null; MDBList CW keys off paused == true',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));
      final show = _meta(id: 'tt1', type: 'series', imdbId: 'tt1');

      _opener(
        tester,
        mergedSeriesPage: true,
        isSimklAuthenticated: true,
        isMdblistAuthenticated: true,
        simklByImdb: {
          'tt1': SimklContinueWatchingItem(
            meta: show,
            progress: null,
            season: 1,
            episode: 2,
            pausedAtMs: 1,
            isMovie: false,
            isUpNext: true,
          ),
        },
        mdblistByImdb: {
          'tt1': MdblistContinueWatchingItem(
            selection: const AdvancedSearchSelection(
              imdbId: 'tt1',
              isSeries: true,
              title: 'Title',
            ),
            paused: false,
          ),
        },
      ).open(show, _addon('cine'));
      var screen =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(
        screen.simklMenuOptions.map((o) => o.action),
        isNot(contains(SimklItemMenuAction.removeFromContinueWatching)),
      );
      expect(
        screen.mdblistMenuOptions.map((o) => o.action),
        isNot(contains(MdblistItemMenuAction.removeFromContinueWatching)),
      );

      _opener(
        tester,
        mergedSeriesPage: true,
        isSimklAuthenticated: true,
        isMdblistAuthenticated: true,
        simklByImdb: {
          'tt1': SimklContinueWatchingItem(
            meta: show,
            progress: 12,
            season: 1,
            episode: 2,
            pausedAtMs: 1,
            isMovie: false,
          ),
        },
        mdblistByImdb: {
          'tt1': MdblistContinueWatchingItem(
            selection: const AdvancedSearchSelection(
              imdbId: 'tt1',
              isSeries: true,
              title: 'Title',
            ),
            paused: true,
          ),
        },
      ).open(show, _addon('cine'));
      screen =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(
        screen.simklMenuOptions.map((o) => o.action),
        contains(SimklItemMenuAction.removeFromContinueWatching),
      );
      expect(
        screen.mdblistMenuOptions.map((o) => o.action),
        contains(MdblistItemMenuAction.removeFromContinueWatching),
      );
    },
  );

  testWidgets(
    'heroTag / initialSeason / initialEpisode / source flags ride the merged page',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));
      _opener(tester, mergedSeriesPage: true).open(
        _meta(id: 'tt1', type: 'series', imdbId: 'tt1'),
        _addon('cine'),
        isTraktSource: true,
        isMdblistSource: true,
        heroTag: 'hero-board-3',
        initialSeason: 3,
        initialEpisode: 4,
      );
      final screen =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(screen.heroTag, 'hero-board-3');
      expect(screen.initialSeason, 3);
      expect(screen.initialEpisode, 4);
      expect(screen.isTraktSource, isTrue);
      expect(screen.isMdblistSource, isTrue);
      expect(screen.showQuickPlay, isTrue);
      expect(screen.isTelevision, isFalse);
    },
  );

  testWidgets(
    'merged showQuickPlay stays true when PikPak-only; legacy uses !_pikpakOnly',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));

      _opener(
        tester,
        mergedSeriesPage: true,
        pikpakOnly: true,
      ).open(_meta(id: 'tt1', type: 'movie', imdbId: 'tt1'), _addon('cine'));
      expect(
        ((observer.pushed.last as MaterialPageRoute).builder(ctx)
                as MergedDetailScreen)
            .showQuickPlay,
        isTrue,
        reason:
            'merged path hard-codes showQuickPlay: true even for PikPak-only',
      );

      _opener(
        tester,
        pikpakOnly: true,
      ).open(_meta(id: 'tt1', type: 'movie', imdbId: 'tt1'), _addon('cine'));
      expect(
        ((observer.pushed.last as MaterialPageRoute).builder(ctx)
                as CatalogItemDetailScreen)
            .showQuickPlay,
        isFalse,
      );

      _opener(
        tester,
      ).open(_meta(id: 'tt1', type: 'movie', imdbId: 'tt1'), _addon('cine'));
      expect(
        ((observer.pushed.last as MaterialPageRoute).builder(ctx)
                as CatalogItemDetailScreen)
            .showQuickPlay,
        isTrue,
      );
    },
  );

  testWidgets('legacy CatalogItemDetailScreen stamps withMyWatchlistSource', (
    tester,
  ) async {
    final observer = await _pumpHost(tester);
    final ctx = tester.element(find.byType(Scaffold));
    final cine = _addon('cine');
    final other = _addon('other');

    _opener(tester).open(_meta(id: 'tt1', type: 'movie', imdbId: 'tt1'), cine);
    expect(
      ((observer.pushed.last as MaterialPageRoute).builder(ctx)
              as CatalogItemDetailScreen)
          .item
          .sourceAddon
          ?.id,
      'cine',
      reason: 'source-less item takes the opener addon as fallback',
    );

    _opener(tester).open(
      _meta(id: 'tt1', type: 'movie', imdbId: 'tt1', sourceAddon: other),
      cine,
    );
    expect(
      ((observer.pushed.last as MaterialPageRoute).builder(ctx)
              as CatalogItemDetailScreen)
          .item
          .sourceAddon
          ?.id,
      'other',
      reason: 'existing sourceAddon is authoritative',
    );
  });

  testWidgets(
    'legacy play/browse closures forward trakt/mdblist source flags',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));
      var playTrakt = false;
      var playMdblist = false;
      var browseTrakt = false;
      var browseMdblist = false;
      var preferTrakt = false;
      _opener(
        tester,
        onCatalogPlay:
            (
              item,
              addon, {
              isTraktSource = false,
              isMdblistSource = false,
              skipEpisodeFallback = false,
              preferTraktResume = false,
              promisedTarget,
              browseSourcesOnly = false,
            }) async {
              playTrakt = isTraktSource;
              playMdblist = isMdblistSource;
              preferTrakt = preferTraktResume;
            },
        onCatalogBrowse:
            (item, addon, {isTraktSource = false, isMdblistSource = false}) {
              browseTrakt = isTraktSource;
              browseMdblist = isMdblistSource;
            },
      ).open(
        _meta(id: 'tt1', type: 'movie', imdbId: 'tt1'),
        _addon('cine'),
        isTraktSource: true,
        isMdblistSource: true,
      );
      final screen =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as CatalogItemDetailScreen;
      screen.onPlay();
      screen.onBrowse();
      expect(playTrakt, isTrue);
      expect(playMdblist, isTrue);
      expect(preferTrakt, isTrue);
      expect(browseTrakt, isTrue);
      expect(browseMdblist, isTrue);
    },
  );

  testWidgets(
    'returnToTabOnClose calls MainPageBridge.switchTab after pop (both paths)',
    (tester) async {
      await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));
      final switched = <int>[];
      MainPageBridge.switchTab = switched.add;

      _opener(tester, mergedSeriesPage: true).open(
        _meta(id: 'tt1', type: 'series', imdbId: 'tt1'),
        _addon('cine'),
        returnToTabOnClose: 19,
      );
      Navigator.of(ctx).pop();
      await tester.pump();
      expect(switched, [19]);

      _opener(tester).open(
        _meta(id: 'tt1', type: 'movie', imdbId: 'tt1'),
        _addon('cine'),
        returnToTabOnClose: 15,
      );
      Navigator.of(ctx).pop();
      await tester.pump();
      expect(switched, [19, 15]);
    },
  );

  testWidgets(
    'recommendations tap re-enters open with rec.sourceAddon ?? opener addon',
    (tester) async {
      final observer = await _pumpHost(tester);
      final ctx = tester.element(find.byType(Scaffold));
      final cine = _addon('cine');
      final recAddon = _addon('rec-src');
      final recWithSource = _meta(
        id: 'tt9',
        type: 'movie',
        imdbId: 'tt9',
        sourceAddon: recAddon,
        name: 'Rec sourced',
      );
      final recBare = _meta(
        id: 'tt8',
        type: 'movie',
        imdbId: 'tt8',
        name: 'Rec bare',
      );

      _opener(
        tester,
        mergedSeriesPage: true,
      ).open(_meta(id: 'tt1', type: 'series', imdbId: 'tt1'), cine);
      final first =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(first.onRecommendationTap, isNotNull);
      expect(first.recommendationsLoader, isNotNull);

      first.onRecommendationTap!(recBare);
      final barePage =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(barePage.addon.id, 'cine');
      expect(barePage.item.id, 'tt8');

      first.onRecommendationTap!(recWithSource);
      final sourcedPage =
          (observer.pushed.last as MaterialPageRoute).builder(ctx)
              as MergedDetailScreen;
      expect(sourcedPage.addon.id, 'rec-src');
      expect(sourcedPage.item.id, 'tt9');
    },
  );

  testWidgets('no-imdb title does not wire recommendations tap', (
    tester,
  ) async {
    final observer = await _pumpHost(tester);
    final ctx = tester.element(find.byType(Scaffold));
    _opener(
      tester,
      mergedSeriesPage: true,
    ).open(_meta(id: 'local-1', type: 'series'), _addon('cine'));
    final screen =
        (observer.pushed.last as MaterialPageRoute).builder(ctx)
            as MergedDetailScreen;
    expect(screen.onRecommendationTap, isNull);
    expect(screen.recommendationsLoader, isNull);
    expect(screen.traktStatusLoader, isNull);
  });

  testWidgets('onActiveAddon records the opener addon id', (tester) async {
    await _pumpHost(tester);
    String? active;
    _opener(
      tester,
      onActiveAddon: (id) => active = id,
    ).open(_meta(id: 'tt1', type: 'movie', imdbId: 'tt1'), _addon('cine'));
    expect(active, 'cine');
  });

  testWidgets('imdb-less id that starts with tt still counts as IMDb', (
    tester,
  ) async {
    final observer = await _pumpHost(tester);
    final ctx = tester.element(find.byType(Scaffold));
    _opener(
      tester,
      mergedSeriesPage: true,
      cwIds: {'tt123'},
    ).open(_meta(id: 'tt123', type: 'series'), _addon('cine'));
    final screen =
        (observer.pushed.last as MaterialPageRoute).builder(ctx)
            as MergedDetailScreen;
    expect(
      screen.traktMenuOptions.map((o) => o.action),
      contains(TraktItemMenuAction.removeFromPlayback),
    );
    expect(screen.onRecommendationTap, isNotNull);
  });
}

Future<_PushObserver> _pumpHost(WidgetTester tester) async {
  final observer = _PushObserver();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      builder: (context, child) =>
          AppThemeScope(theme: AppThemes.legacy, child: child!),
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );
  await tester.pump();
  return observer;
}

TitleOpener _opener(
  WidgetTester tester, {
  bool mergedSeriesPage = false,
  bool pikpakOnly = false,
  bool isTelevision = false,
  bool isTraktAuthenticated = false,
  bool isSimklAuthenticated = false,
  bool isMdblistAuthenticated = false,
  Set<String>? cwIds,
  Map<String, TraktContinueWatchingItem>? traktByImdb,
  Map<String, MdblistContinueWatchingItem>? mdblistByImdb,
  Map<String, SimklContinueWatchingItem>? simklByImdb,
  void Function(String addonId)? onActiveAddon,
  TitleCatalogPlay? onCatalogPlay,
  TitleCatalogBrowse? onCatalogBrowse,
}) {
  final context = tester.element(find.byType(Scaffold));
  return TitleOpener(
    getContext: () => context,
    isTelevision: () => isTelevision,
    mergedSeriesPage: () => mergedSeriesPage,
    pikpakOnly: () => pikpakOnly,
    cwIds: cwIds ?? <String>{},
    traktByImdb: traktByImdb ?? <String, TraktContinueWatchingItem>{},
    mdblistByImdb: mdblistByImdb ?? <String, MdblistContinueWatchingItem>{},
    simklByImdb: simklByImdb ?? <String, SimklContinueWatchingItem>{},
    isTraktAuthenticated: () => isTraktAuthenticated,
    isSimklAuthenticated: () => isSimklAuthenticated,
    isMdblistAuthenticated: () => isMdblistAuthenticated,
    imdbOf: _imdbOf,
    isBound: (_) => false,
    boundCountFor: (_) => 0,
    onActiveAddon: onActiveAddon ?? (_) {},
    resolveResumeInfo:
        (item, addon, {isTraktSource = false, isMdblistSource = false}) async =>
            (started: false, season: null, episode: null),
    onCatalogPlay:
        onCatalogPlay ??
        (
          item,
          addon, {
          isTraktSource = false,
          isMdblistSource = false,
          skipEpisodeFallback = false,
          preferTraktResume = false,
          promisedTarget,
          browseSourcesOnly = false,
        }) async {},
    onCatalogBrowse:
        onCatalogBrowse ??
        (item, addon, {isTraktSource = false, isMdblistSource = false}) {},
    onItemSelected: (_) {},
    onQuickPlay: (_) async {},
    onSelectSource: (_) async {},
    onDetailQuickAction:
        (item, addon, action, {required inCw, imdb, presetRating}) async {},
    onDetailSimklQuickAction: (item, action, {presetRating}) async {},
    onDetailMdblistQuickAction: (item, action, {presetRating}) async {},
    onLoaderArt: (item, PlayLoaderArt art) {},
    getRecommendations: ({required imdbId, required type}) async =>
        const <StremioMeta>[],
    fetchMetaDetails: ({required imdbId, required type}) async => null,
    onAfterPlayback: () async {},
    onRefreshTraktAuth: () {},
    onRefreshSimklAuth: () {},
    onRefreshMdblistAuth: () {},
  );
}
