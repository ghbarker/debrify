import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/search/catalog_search_screen.dart';
import 'package:debrify/screens/search/discover_screen.dart';
import 'package:debrify/screens/search/search_screen_shells.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'discover_screen_origin_test.dart' show mountDiscover, discoverSource;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, closeFavourites;

Widget _shell({
  bool isTelevision = false,
  bool searchMode = false,
  bool discoverMode = false,
}) => SearchScreen.forFlags(
  isTelevision: isTelevision,
  searchMode: searchMode,
  discoverMode: discoverMode,
);

void main() {
  testWidgets('Discover dispatch mounts its composition without legacy host',
      (tester) async {
    final previousTab = MainPageBridge.activeTvTabIndex;
    addTearDown(() => MainPageBridge.setActiveTvTab(previousTab));
    await prepareFavourites(tester);
    await mountDiscover(tester);
    expect(find.byType(SearchScreenHost), findsNothing);
    expect(tester.state(find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_DiscoverComposition')).mounted, isTrue);
    // The public bridge is not platform-gated: the actual non-TV Source node
    // must remain reachable even though the API retains its TV-oriented name.
    final source = discoverSource(tester);
    expect(source.isTelevision, isFalse);
    final sourceNode = source.focusNode!;
    sourceNode.unfocus();
    await tester.pump();
    expect(sourceNode.hasFocus, isFalse);
    MainPageBridge.setActiveTvTab(18);
    expect(MainPageBridge.requestTvContentFocus(), isTrue);
    await tester.pump();
    expect(sourceNode.hasFocus, isTrue);
    await closeFavourites(tester);
    expect(MainPageBridge.requestTvContentFocus(), isFalse);
  });

  group('searchMode vs discoverMode vs Home tab / variant', () {
    test('Home is tab 15 / variant board / analytics home', () {
      expect(searchScreenTabIndex(searchMode: false, discoverMode: false), 15);
      expect(
        searchScreenVariantKey(searchMode: false, discoverMode: false),
        'board',
      );
      expect(
        searchScreenAnalyticsName(searchMode: false, discoverMode: false),
        'home',
      );
    });

    test('Search is tab 17 / variant search / analytics search', () {
      expect(searchScreenTabIndex(searchMode: true, discoverMode: false), 17);
      expect(
        searchScreenVariantKey(searchMode: true, discoverMode: false),
        'search',
      );
      expect(
        searchScreenAnalyticsName(searchMode: true, discoverMode: false),
        'search',
      );
    });

    test('Discover is tab 18 / variant discover / analytics discover', () {
      expect(searchScreenTabIndex(searchMode: false, discoverMode: true), 18);
      expect(
        searchScreenVariantKey(searchMode: false, discoverMode: true),
        'discover',
      );
      expect(
        searchScreenAnalyticsName(searchMode: false, discoverMode: true),
        'discover',
      );
    });

    test('searchMode wins when both flags are true', () {
      expect(
        searchScreenTabIndex(searchMode: true, discoverMode: true),
        17,
        reason: 'quirk: `searchMode ? 17 : (discoverMode ? 18 : 15)`',
      );
      expect(
        searchScreenVariantKey(searchMode: true, discoverMode: true),
        'search',
      );
      expect(
        searchScreenAnalyticsName(searchMode: true, discoverMode: true),
        'search',
      );
      expect(
        searchScreenPrimesDiscoverRows(searchMode: true, discoverMode: true),
        isFalse,
        reason:
            'quirk: init `if (searchMode)` wins over `else if (discoverMode)`',
      );
    });

    test('main.dart constructors still exist on SearchScreen', () {
      const home = SearchScreen();
      const search = SearchScreen(searchMode: true);
      const discover = SearchScreen(discoverMode: true);
      const tv = SearchScreen(isTelevision: true);
      expect(home.searchMode, isFalse);
      expect(home.discoverMode, isFalse);
      expect(search.searchMode, isTrue);
      expect(search.discoverMode, isFalse);
      expect(discover.searchMode, isFalse);
      expect(discover.discoverMode, isTrue);
      expect(tv.isTelevision, isTrue);
    });

    test('dispatcher: Search/Discover shells, Home stays SearchScreenHost', () {
      expect(_shell(searchMode: true), isA<CatalogSearchScreen>());
      expect(_shell(discoverMode: true), isA<DiscoverScreen>());
      expect(_shell(), isA<SearchScreenHost>());
      expect(
        _shell(searchMode: true, discoverMode: true),
        isA<CatalogSearchScreen>(),
        reason: 'quirk: searchMode wins',
      );
      final search = _shell(searchMode: true) as CatalogSearchScreen;
      expect(search.host, isA<SearchScreenHost>());
      expect((search.host as SearchScreenHost).searchMode, isTrue);
      expect((search.host as SearchScreenHost).discoverMode, isFalse);
      final discover = _shell(discoverMode: true) as DiscoverScreen;
      expect(discover.host, isNull,
          reason: 'intentional cutover: Discover composes without legacy State');
      expect((_shell() as SearchScreenHost).searchMode, isFalse);
      expect((_shell() as SearchScreenHost).discoverMode, isFalse);
    });

    test('CatalogSearchScreen / DiscoverScreen expose frozen tabs', () {
      const search = CatalogSearchScreen();
      const discover = DiscoverScreen();
      expect(search.tabIndex, 17);
      expect(search.variantKey, 'search');
      expect(search.analyticsName, 'search');
      expect(discover.tabIndex, 18);
      expect(discover.variantKey, 'discover');
      expect(discover.analyticsName, 'discover');
    });
  });

  group('shared controllers', () {
    test('every variant lists HomeBoard + CatalogSearch + TitleOpener', () {
      const expected = [
        'HomeBoardController',
        'CatalogSearchController',
        'TitleOpener',
      ];
      expect(kSearchScreenSharedControllerNames, expected);
      expect(const CatalogSearchScreen().sharedControllers, expected);
      expect(const DiscoverScreen().sharedControllers, expected);
    });

    test('Search still constructs HomeBoardController (skips _load)', () {
      expect(
        searchScreenLoadsHomeBoard(searchMode: true, discoverMode: false),
        isFalse,
      );
      expect(
        kSearchScreenSharedControllerNames,
        contains('HomeBoardController'),
      );
    });

    test(
      'Discover still constructs CatalogSearchController (skips catalog search)',
      () {
        expect(
          searchScreenPrimesDiscoverRows(searchMode: false, discoverMode: true),
          isTrue,
        );
        expect(
          kSearchScreenSharedControllerNames,
          contains('CatalogSearchController'),
        );
      },
    );

    test('item open is TitleOpener, not a State field', () {
      expect(kSearchScreenSharedControllerNames, contains('TitleOpener'));
    });
  });

  group('Discover source dropdown + landing', () {
    test('remember-last uses lastSource; fixed default uses defaultSource', () {
      expect(
        resolveDiscoverLandingSource(
          defaultSource: StorageService.discoverDefaultRememberLast,
          lastSource: kDiscoverSourceTrakt,
          mdblistEnabled: true,
          browsableAddonIds: const [],
        ),
        kDiscoverSourceTrakt,
      );
      expect(
        resolveDiscoverLandingSource(
          defaultSource: kDiscoverSourceSimkl,
          lastSource: kDiscoverSourceTrakt,
          mdblistEnabled: true,
          browsableAddonIds: const [],
        ),
        kDiscoverSourceSimkl,
      );
    });

    test('fixed CW / Trakt / Simkl / MDBList stay even with no addons', () {
      for (final source in [
        kDiscoverSourceCw,
        kDiscoverSourceTrakt,
        kDiscoverSourceSimkl,
        kDiscoverSourceMdblist,
      ]) {
        expect(
          resolveDiscoverLandingSource(
            defaultSource: source,
            lastSource: kDiscoverSourceCw,
            mdblistEnabled: true,
            browsableAddonIds: const [],
          ),
          source,
        );
      }
    });

    test('MDBList landing falls back to CW when the compile flag is off', () {
      expect(
        resolveDiscoverLandingSource(
          defaultSource: kDiscoverSourceMdblist,
          lastSource: kDiscoverSourceCw,
          mdblistEnabled: false,
          browsableAddonIds: const [],
        ),
        kDiscoverSourceCw,
        reason: 'fixedSource requires kMdblistEnabled for mdblist',
      );
    });

    test('installed addon landing is kept; missing addon falls back to CW', () {
      expect(
        resolveDiscoverLandingSource(
          defaultSource: '${kDiscoverSourceAddonPrefix}cine',
          lastSource: kDiscoverSourceCw,
          mdblistEnabled: true,
          browsableAddonIds: const ['cine', 'tv'],
        ),
        '${kDiscoverSourceAddonPrefix}cine',
      );
      expect(
        resolveDiscoverLandingSource(
          defaultSource: '${kDiscoverSourceAddonPrefix}gone',
          lastSource: kDiscoverSourceTrakt,
          mdblistEnabled: true,
          browsableAddonIds: const ['cine'],
        ),
        kDiscoverSourceCw,
        reason: '!fixedSource && !addonAvailable → cw (not lastSource)',
      );
    });

    test('unknown garbage landing falls back to CW', () {
      expect(
        resolveDiscoverLandingSource(
          defaultSource: 'nope',
          lastSource: kDiscoverSourceTrakt,
          mdblistEnabled: true,
          browsableAddonIds: const ['cine'],
        ),
        kDiscoverSourceCw,
      );
    });

    test('dropdown always has CW / Trakt / Simkl', () {
      final options = discoverSourceDropdownOptions(
        mdblistEnabled: false,
        mdblistAuthenticated: false,
        currentSource: kDiscoverSourceCw,
        addons: const [],
      );
      expect(options.map((o) => o.value).toList(), [
        kDiscoverSourceCw,
        kDiscoverSourceTrakt,
        kDiscoverSourceSimkl,
      ]);
      expect(options.first.label, 'Continue Watching');
    });

    test(
      'MDBList is hidden unless enabled and (authed or already selected)',
      () {
        expect(
          discoverSourceDropdownOptions(
            mdblistEnabled: true,
            mdblistAuthenticated: false,
            currentSource: kDiscoverSourceCw,
            addons: const [],
          ).any((o) => o.value == kDiscoverSourceMdblist),
          isFalse,
        );
        expect(
          discoverSourceDropdownOptions(
            mdblistEnabled: true,
            mdblistAuthenticated: true,
            currentSource: kDiscoverSourceCw,
            addons: const [],
          ).any((o) => o.value == kDiscoverSourceMdblist),
          isTrue,
        );
        expect(
          discoverSourceDropdownOptions(
            mdblistEnabled: true,
            mdblistAuthenticated: false,
            currentSource: kDiscoverSourceMdblist,
            addons: const [],
          ).any((o) => o.value == kDiscoverSourceMdblist),
          isTrue,
          reason: 'kept if it is somehow already the active source',
        );
        expect(
          discoverSourceDropdownOptions(
            mdblistEnabled: false,
            mdblistAuthenticated: true,
            currentSource: kDiscoverSourceMdblist,
            addons: const [],
          ).any((o) => o.value == kDiscoverSourceMdblist),
          isFalse,
          reason: 'compile flag off hides it even when selected',
        );
      },
    );

    test('browsable addons append as a:{id}', () {
      final options = discoverSourceDropdownOptions(
        mdblistEnabled: false,
        mdblistAuthenticated: false,
        currentSource: kDiscoverSourceCw,
        addons: const [(id: 'cine', name: 'Cinematic'), (id: 'tv', name: 'TV')],
      );
      expect(options.sublist(3), [
        const DiscoverSourceOption(
          '${kDiscoverSourceAddonPrefix}cine',
          'Cinematic',
        ),
        const DiscoverSourceOption('${kDiscoverSourceAddonPrefix}tv', 'TV'),
      ]);
    });

    test(
      'existing discoverLandingLoadIsCurrent still gates late hydration',
      () {
        expect(
          discoverLandingLoadIsCurrent(
            capturedRevision: 0,
            currentRevision: 1,
            hasPendingHandoff: false,
          ),
          isFalse,
        );
        expect(
          discoverLandingLoadIsCurrent(
            capturedRevision: 0,
            currentRevision: 0,
            hasPendingHandoff: true,
          ),
          isFalse,
        );
        expect(
          discoverLandingLoadIsCurrent(
            capturedRevision: 0,
            currentRevision: 0,
            hasPendingHandoff: false,
          ),
          isTrue,
        );
      },
    );
  });

  group('TV vs phone shells (not the six stage layouts)', () {
    test('keyword restore skipped only on Home TV', () {
      expect(
        searchScreenRestoresKeyword(
          isTelevision: true,
          searchMode: false,
          discoverMode: false,
        ),
        isFalse,
      );
      expect(
        searchScreenRestoresKeyword(
          isTelevision: false,
          searchMode: false,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenRestoresKeyword(
          isTelevision: true,
          searchMode: true,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenRestoresKeyword(
          isTelevision: true,
          searchMode: false,
          discoverMode: true,
        ),
        isTrue,
      );
    });

    test('Home loads the board; Search/Discover clear loading instead', () {
      expect(
        searchScreenLoadsHomeBoard(searchMode: false, discoverMode: false),
        isTrue,
      );
      expect(
        searchScreenClearsLoadingWithoutBoard(
          searchMode: true,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenClearsLoadingWithoutBoard(
          searchMode: false,
          discoverMode: true,
        ),
        isTrue,
      );
      expect(
        searchScreenClaimsPendingCatalogDetail(
          searchMode: false,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenClaimsPendingCatalogDetail(
          searchMode: true,
          discoverMode: false,
        ),
        isFalse,
      );
      expect(searchScreenRegistersSearchBackHandler(searchMode: true), isTrue);
      expect(
        searchScreenRegistersSearchBackHandler(searchMode: false),
        isFalse,
      );
    });

    test(
      'unified Sources bar is non-TV and non-Search (Discover phone quirk)',
      () {
        expect(
          searchScreenShowsUnifiedCatalogSourcesBar(
            isTelevision: false,
            searchMode: false,
          ),
          isTrue,
          reason: 'Home phone and Discover phone share this predicate',
        );
        expect(
          searchScreenShowsUnifiedCatalogSourcesBar(
            isTelevision: true,
            searchMode: false,
          ),
          isFalse,
        );
        expect(
          searchScreenShowsUnifiedCatalogSourcesBar(
            isTelevision: false,
            searchMode: true,
          ),
          isFalse,
        );
        expect(
          searchScreenListensForCatalogSourcesFocus(
            isTelevision: false,
            searchMode: false,
          ),
          isTrue,
          reason: 'quirk: Discover phone registers the listener too',
        );
      },
    );

    test('Spotlight latch and hero trailer shells are Home-only', () {
      expect(
        searchScreenLatchesSpotlightSearchSheet(
          isTelevision: false,
          searchMode: false,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenLatchesSpotlightSearchSheet(
          isTelevision: false,
          searchMode: true,
          discoverMode: false,
        ),
        isFalse,
      );
      expect(
        searchScreenHeroTrailerActive(
          isTelevision: true,
          searchMode: false,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenHeroTrailerActive(
          isTelevision: true,
          searchMode: true,
          discoverMode: false,
        ),
        isFalse,
      );
      expect(
        searchScreenHeroTrailerOffTvEligible(
          isTelevision: false,
          searchMode: false,
          discoverMode: false,
        ),
        isTrue,
      );
      expect(
        searchScreenHeroTrailerOffTvEligible(
          isTelevision: true,
          searchMode: false,
          discoverMode: false,
        ),
        isFalse,
      );
    });

    test('TV hero is live on Home always and on Search only with results', () {
      expect(
        searchScreenHeroActive(
          isTelevision: true,
          searchMode: false,
          catalogQueryNonEmpty: false,
        ),
        isTrue,
      );
      expect(
        searchScreenHeroActive(
          isTelevision: true,
          searchMode: true,
          catalogQueryNonEmpty: false,
        ),
        isFalse,
      );
      expect(
        searchScreenHeroActive(
          isTelevision: true,
          searchMode: true,
          catalogQueryNonEmpty: true,
        ),
        isTrue,
      );
      expect(
        searchScreenHeroActive(
          isTelevision: false,
          searchMode: false,
          catalogQueryNonEmpty: true,
        ),
        isFalse,
      );
    });

    test(
      'Discover phone is always full-width; TV two-pane has a 720×420 floor',
      () {
        expect(
          discoverUsesFullWidthPanel(
            isTelevision: false,
            maxWidth: 1920,
            maxHeight: 1080,
          ),
          isTrue,
        );
        expect(
          discoverUsesFullWidthPanel(
            isTelevision: true,
            maxWidth: 1920,
            maxHeight: 1080,
          ),
          isFalse,
        );
        expect(
          discoverUsesFullWidthPanel(
            isTelevision: true,
            maxWidth: 719,
            maxHeight: 800,
          ),
          isTrue,
        );
        expect(
          discoverUsesFullWidthPanel(
            isTelevision: true,
            maxWidth: 800,
            maxHeight: 419,
          ),
          isTrue,
        );
        expect(
          discoverUsesFullWidthPanel(
            isTelevision: true,
            maxWidth: 720,
            maxHeight: 420,
          ),
          isFalse,
        );
      },
    );

    test('Search leave-top focuses the field; Discover focuses Source', () {
      expect(searchScreenLeaveBoardTopFocusesField(searchMode: true), isTrue);
      expect(searchScreenLeaveBoardTopFocusesField(searchMode: false), isFalse);
      expect(searchScreenFocusesDiscoverSource(discoverMode: true), isTrue);
      expect(searchScreenFocusesDiscoverSource(discoverMode: false), isFalse);
    });

    test(
      'rail header and Search hero clamp differ TV vs phone / Search vs Home',
      () {
        expect(searchScreenRailHeaderHeight(isTelevision: true), 44.0);
        expect(searchScreenRailHeaderHeight(isTelevision: false), 52.0);
        expect(searchScreenTvHeroBudgetMax(searchMode: true), 180.0);
        expect(searchScreenTvHeroBudgetMax(searchMode: false), 440.0);
      },
    );

    test(
      'Home expanded See-All walls wrap Discover card settings; Search does not',
      () {
        expect(
          searchScreenAppliesHomeExpandedCardSettings(
            searchMode: false,
            discoverMode: false,
          ),
          isTrue,
        );
        expect(
          searchScreenAppliesHomeExpandedCardSettings(
            searchMode: true,
            discoverMode: false,
          ),
          isFalse,
        );
        expect(
          searchScreenAppliesHomeExpandedCardSettings(
            searchMode: false,
            discoverMode: true,
          ),
          isFalse,
        );
      },
    );
  });
}
