import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart' hide HomeCardOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins Home page-default encodings on [StorageService] before the G3
/// HomePrefs move. Key names and values are a frozen compatibility surface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Home page defaults when no keys are stored', () async {
    expect(await StorageService.getHomeDefaultSourceType(), isNull);
    expect(await StorageService.getHomeDefaultAddonUrl(), isNull);
    expect(await StorageService.getHomeDefaultCatalogId(), isNull);
    expect(await StorageService.getHomeDefaultTraktListType(), isNull);
    expect(await StorageService.getHomeDefaultTraktContentType(), isNull);
    expect(await StorageService.getHomeHideProviderCards(), isTrue);
    expect(await StorageService.getHomeContinueWatchingEnabled(), isTrue);
    expect(await StorageService.getHomeCwHoldToQuickPlay(), isFalse);
    expect(await StorageService.getHomeCwMergedRows('local'), isFalse);
    expect(await StorageService.getHomeCwMergedRows('trakt'), isFalse);
    expect(await StorageService.getHomeCwMergedRows('simkl'), isFalse);
    expect(await StorageService.getHomeCwMergedRows('mdblist'), isFalse);
    expect(await StorageService.getHomeFavoritesTapAction(), 'choose');
    expect(
      await StorageService.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );
    expect(await StorageService.getHomeHideCardTitlesAndRatings(), isFalse);
    expect(await StorageService.getHomeHideCatalogAddonNames(), isFalse);
  });

  test('StorageService writes the historical Home page key bytes', () async {
    await StorageService.setHomeDefaultSourceType('addon');
    await StorageService.setHomeDefaultAddonUrl(
      'https://addon.example/manifest.json',
    );
    await StorageService.setHomeDefaultCatalogId('top');
    await StorageService.setHomeDefaultTraktListType('watchlist');
    await StorageService.setHomeDefaultTraktContentType('movies');
    await StorageService.setHomeHideProviderCards(false);
    await StorageService.setHomeContinueWatchingEnabled(false);
    await StorageService.setHomeCwHoldToQuickPlay(true);
    await StorageService.setHomeCwMergedRows('local', true);
    await StorageService.setHomeCwMergedRows('trakt', true);
    await StorageService.setHomeCwMergedRows('simkl', true);
    await StorageService.setHomeCwMergedRows('mdblist', true);
    await StorageService.setHomeFavoritesTapAction('open');
    await StorageService.setHomeCardOrientation(HomeCardOrientation.portrait);
    await StorageService.setHomeHideCardTitlesAndRatings(true);
    await StorageService.setHomeHideCatalogAddonNames(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_default_source_type'), 'addon');
    expect(
      prefs.getString('home_default_addon_url'),
      'https://addon.example/manifest.json',
    );
    expect(prefs.getString('home_default_catalog_id'), 'top');
    expect(prefs.getString('home_default_trakt_list_type'), 'watchlist');
    expect(prefs.getString('home_default_trakt_content_type'), 'movies');
    expect(prefs.getBool('home_hide_provider_cards'), isFalse);
    expect(prefs.getBool('home_continue_watching_enabled'), isFalse);
    expect(prefs.getBool('home_cw_hold_to_quick_play'), isTrue);
    expect(prefs.getBool('home_cw_merge_local'), isTrue);
    expect(prefs.getBool('home_cw_merge_trakt'), isTrue);
    expect(prefs.getBool('home_cw_merge_simkl'), isTrue);
    expect(prefs.getBool('home_cw_merge_mdblist'), isTrue);
    expect(prefs.getString('home_favorites_open_folder'), 'open');
    expect(prefs.getString('home_card_orientation'), 'portrait');
    expect(prefs.getBool('home_hide_card_titles_and_ratings'), isTrue);
    expect(prefs.getBool('home_hide_catalog_addon_names'), isTrue);
  });

  test(
    'raw Home page bytes round-trip through StorageService getters',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_default_source_type': 'trakt',
        'home_default_addon_url': 'https://x/manifest.json',
        'home_default_catalog_id': 'catalog',
        'home_default_trakt_list_type': 'collection',
        'home_default_trakt_content_type': 'shows',
        'home_hide_provider_cards': false,
        'home_continue_watching_enabled': false,
        'home_cw_hold_to_quick_play': true,
        'home_cw_merge_local': true,
        'home_favorites_open_folder': 'play',
        'home_card_orientation': 'portrait',
        'home_hide_card_titles_and_ratings': true,
        'home_hide_catalog_addon_names': true,
      });

      expect(await StorageService.getHomeDefaultSourceType(), 'trakt');
      expect(
        await StorageService.getHomeDefaultAddonUrl(),
        'https://x/manifest.json',
      );
      expect(await StorageService.getHomeDefaultCatalogId(), 'catalog');
      expect(await StorageService.getHomeDefaultTraktListType(), 'collection');
      expect(await StorageService.getHomeDefaultTraktContentType(), 'shows');
      expect(await StorageService.getHomeHideProviderCards(), isFalse);
      expect(await StorageService.getHomeContinueWatchingEnabled(), isFalse);
      expect(await StorageService.getHomeCwHoldToQuickPlay(), isTrue);
      expect(await StorageService.getHomeCwMergedRows('local'), isTrue);
      expect(await StorageService.getHomeFavoritesTapAction(), 'play');
      expect(
        await StorageService.getHomeCardOrientation(),
        HomeCardOrientation.portrait,
      );
      expect(await StorageService.getHomeHideCardTitlesAndRatings(), isTrue);
      expect(await StorageService.getHomeHideCatalogAddonNames(), isTrue);
    },
  );

  test('null Home default setters remove the key', () async {
    await StorageService.setHomeDefaultSourceType('addon');
    await StorageService.setHomeDefaultAddonUrl('https://a/manifest.json');
    await StorageService.setHomeDefaultCatalogId('top');
    await StorageService.setHomeDefaultTraktListType('watchlist');
    await StorageService.setHomeDefaultTraktContentType('movies');

    await StorageService.setHomeDefaultSourceType(null);
    await StorageService.setHomeDefaultAddonUrl(null);
    await StorageService.setHomeDefaultCatalogId(null);
    await StorageService.setHomeDefaultTraktListType(null);
    await StorageService.setHomeDefaultTraktContentType(null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('home_default_source_type'), isFalse);
    expect(prefs.containsKey('home_default_addon_url'), isFalse);
    expect(prefs.containsKey('home_default_catalog_id'), isFalse);
    expect(prefs.containsKey('home_default_trakt_list_type'), isFalse);
    expect(prefs.containsKey('home_default_trakt_content_type'), isFalse);
  });

  test(
    'HomeCardOrientation treats only the literal portrait as portrait',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_card_orientation': 'landscape',
      });
      expect(
        await StorageService.getHomeCardOrientation(),
        HomeCardOrientation.landscape,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_card_orientation': 'garbage',
      });
      expect(
        await StorageService.getHomeCardOrientation(),
        HomeCardOrientation.landscape,
      );

      await StorageService.setHomeCardOrientation(
        HomeCardOrientation.landscape,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_card_orientation'), 'landscape');
    },
  );

  test('clearAllHomePageSettings leaves Trakt default keys', () async {
    await StorageService.setHomeDefaultSourceType('addon');
    await StorageService.setHomeDefaultAddonUrl('https://a/manifest.json');
    await StorageService.setHomeDefaultCatalogId('top');
    await StorageService.setHomeDefaultTraktListType('watchlist');
    await StorageService.setHomeDefaultTraktContentType('movies');
    await StorageService.setHomeHideProviderCards(false);
    await StorageService.setHomeContinueWatchingEnabled(false);
    await StorageService.setHomeCwHoldToQuickPlay(true);
    await StorageService.setHomeCwMergedRows('local', true);
    await StorageService.setHomeCwMergedRows('trakt', true);
    await StorageService.setHomeCwMergedRows('simkl', true);
    await StorageService.setHomeCwMergedRows('mdblist', true);
    await StorageService.setHomeFavoritesTapAction('open');
    await StorageService.setHomeCardOrientation(HomeCardOrientation.portrait);
    await StorageService.setHomeHideCardTitlesAndRatings(true);
    await StorageService.setHomeHideCatalogAddonNames(true);

    await StorageService.clearAllHomePageSettings();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('home_default_source_type'), isFalse);
    expect(prefs.containsKey('home_default_addon_url'), isFalse);
    expect(prefs.containsKey('home_default_catalog_id'), isFalse);
    expect(prefs.containsKey('home_hide_provider_cards'), isFalse);
    expect(prefs.containsKey('home_continue_watching_enabled'), isFalse);
    expect(prefs.containsKey('home_cw_hold_to_quick_play'), isFalse);
    expect(prefs.containsKey('home_cw_merge_local'), isFalse);
    expect(prefs.containsKey('home_cw_merge_trakt'), isFalse);
    expect(prefs.containsKey('home_cw_merge_simkl'), isFalse);
    expect(prefs.containsKey('home_cw_merge_mdblist'), isFalse);
    expect(prefs.containsKey('home_favorites_open_folder'), isFalse);
    expect(prefs.containsKey('home_card_orientation'), isFalse);
    expect(prefs.containsKey('home_hide_card_titles_and_ratings'), isFalse);
    expect(prefs.containsKey('home_hide_catalog_addon_names'), isFalse);
    // Quirk: Trakt home-default keys are not part of the clear set.
    expect(prefs.getString('home_default_trakt_list_type'), 'watchlist');
    expect(prefs.getString('home_default_trakt_content_type'), 'movies');
  });

  test('StorageService writes are readable through HomePrefs', () async {
    await StorageService.setHomeDefaultSourceType('addon');
    await StorageService.setHomeHideProviderCards(false);
    await StorageService.setHomeCwHoldToQuickPlay(true);
    await StorageService.setHomeCwMergedRows('simkl', true);
    await StorageService.setHomeCardOrientation(HomeCardOrientation.portrait);
    await StorageService.setHomeHideCardTitlesAndRatings(true);

    expect(await HomePrefs.getHomeDefaultSourceType(), 'addon');
    expect(await HomePrefs.getHomeHideProviderCards(), isFalse);
    expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isTrue);
    expect(await HomePrefs.getHomeCwMergedRows('simkl'), isTrue);
    expect(
      await HomePrefs.getHomeCardOrientation(),
      HomeCardOrientation.portrait,
    );
    expect(await HomePrefs.getHomeHideCardTitlesAndRatings(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_default_source_type'), 'addon');
    expect(prefs.getBool('home_hide_provider_cards'), isFalse);
    expect(prefs.getBool('home_cw_hold_to_quick_play'), isTrue);
    expect(prefs.getBool('home_cw_merge_simkl'), isTrue);
    expect(prefs.getString('home_card_orientation'), 'portrait');
    expect(prefs.getBool('home_hide_card_titles_and_ratings'), isTrue);
  });

  test('HomePrefs writes are readable through StorageService', () async {
    await HomePrefs.setHomeDefaultCatalogId('top');
    await HomePrefs.setHomeContinueWatchingEnabled(false);
    await HomePrefs.setHomeFavoritesTapAction('open');
    await HomePrefs.setHomeHideCatalogAddonNames(true);
    await HomePrefs.setHomeDefaultTraktListType('watchlist');
    await HomePrefs.setHomeCardOrientation(HomeCardOrientation.landscape);

    expect(await StorageService.getHomeDefaultCatalogId(), 'top');
    expect(await StorageService.getHomeContinueWatchingEnabled(), isFalse);
    expect(await StorageService.getHomeFavoritesTapAction(), 'open');
    expect(await StorageService.getHomeHideCatalogAddonNames(), isTrue);
    expect(await StorageService.getHomeDefaultTraktListType(), 'watchlist');
    expect(
      await StorageService.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_default_catalog_id'), 'top');
    expect(prefs.getBool('home_continue_watching_enabled'), isFalse);
    expect(prefs.getString('home_favorites_open_folder'), 'open');
    expect(prefs.getBool('home_hide_catalog_addon_names'), isTrue);
    expect(prefs.getString('home_default_trakt_list_type'), 'watchlist');
    expect(prefs.getString('home_card_orientation'), 'landscape');
  });
}
