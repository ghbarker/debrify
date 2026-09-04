import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
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
    await StorageService.setHomeDisabledSections({'cw:movies'});
    await StorageService.setHomeExtraRows(const [
      (id: 'traktlist:watchlist', title: 'Watchlist'),
    ]);
    await StorageService.setHomeRowOrder(['cw:movies', 'fav:iptv']);
    await StorageService.setHomeHeroSource((
      mode: HomeHeroSourceMode.auto,
      ids: const [],
    ));
    await StorageService.setHomeTickSources({TrackingSource.trakt});
    await StorageService.setHomeHeroTrailerEnabled(false);
    await StorageService.setAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.homeHero,
      false,
    );
    await StorageService.setAmbientTrailerVolume(
      AmbientTrailerSurface.homeHero,
      40,
    );
    await StorageService.setTvHomeStyle('spotlight');

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
    // Remaining Home keys (this slice) are also outside the clearer.
    expect(
      prefs.getString('home_disabled_sections_v1'),
      jsonEncode(['cw:movies']),
    );
    expect(
      prefs.getString('home_extra_rows_v1'),
      jsonEncode([
        {'id': 'traktlist:watchlist', 'title': 'Watchlist'},
      ]),
    );
    expect(
      prefs.getString('home_row_order_v1'),
      jsonEncode(['cw:movies', 'fav:iptv']),
    );
    expect(
      prefs.getString('home_hero_source_v1'),
      jsonEncode({'mode': 'auto', 'ids': <String>[]}),
    );
    expect(prefs.getStringList('home_tick_sources'), ['trakt']);
    expect(prefs.getBool('home_hero_trailer_enabled'), isFalse);
    expect(prefs.getBool('home_hero_trailer_audio_enabled'), isFalse);
    expect(prefs.getInt('home_hero_trailer_volume'), 40);
    expect(prefs.getString('tv_home_style'), 'spotlight');
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

  test('remaining Home keys default when no keys are stored', () async {
    expect(await StorageService.getHomeDisabledSections(), isEmpty);
    expect(await StorageService.getHomeExtraRows(), isEmpty);
    expect(await StorageService.getHomeRowOrder(), isEmpty);
    final hero = await StorageService.getHomeHeroSource();
    expect(hero.mode, HomeHeroSourceMode.random);
    expect(hero.ids, isEmpty);
    expect(
      await StorageService.getHomeTickSources(),
      Set<TrackingSource>.of(TrackingSource.values),
    );
    expect(await StorageService.getHomeHeroTrailerEnabled(), isTrue);
    expect(
      await StorageService.getAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.homeHero,
      ),
      isTrue,
    );
    expect(
      await StorageService.getAmbientTrailerVolume(
        AmbientTrailerSurface.homeHero,
      ),
      70,
    );
    expect(await StorageService.getTvHomeStyle(), 'canvas');
    expect(StorageService.tvHomeStyleCached, 'canvas');
  });

  test('StorageService writes the historical remaining Home key bytes', () async {
    await StorageService.setHomeDisabledSections({'cw:movies', 'fav:iptv'});
    await StorageService.setHomeExtraRows(const [
      (id: 'traktlist:watchlist', title: ''),
      (id: 'iptvlist:list_1', title: 'Sports'),
    ]);
    await StorageService.setHomeRowOrder(['fav:playlist', 'cw:movies']);
    await StorageService.setHomeHeroSource((
      mode: HomeHeroSourceMode.custom,
      ids: ['cinemeta:movie:top', 'cinemeta:series:top'],
    ));
    await StorageService.setHomeTickSources({
      TrackingSource.local,
      TrackingSource.simkl,
    });
    await StorageService.setHomeHeroTrailerEnabled(false);
    await StorageService.setAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.homeHero,
      false,
    );
    await StorageService.setAmbientTrailerVolume(
      AmbientTrailerSurface.homeHero,
      40,
    );
    await StorageService.setTvHomeStyle('spotlight');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('home_disabled_sections_v1'),
      jsonEncode(['cw:movies', 'fav:iptv']),
    );
    expect(
      prefs.getString('home_extra_rows_v1'),
      jsonEncode([
        {'id': 'traktlist:watchlist', 'title': ''},
        {'id': 'iptvlist:list_1', 'title': 'Sports'},
      ]),
    );
    expect(
      prefs.getString('home_row_order_v1'),
      jsonEncode(['fav:playlist', 'cw:movies']),
    );
    expect(
      prefs.getString('home_hero_source_v1'),
      jsonEncode({
        'mode': 'custom',
        'ids': ['cinemeta:movie:top', 'cinemeta:series:top'],
      }),
    );
    expect(prefs.getStringList('home_tick_sources'), ['local', 'simkl']);
    expect(prefs.getBool('home_hero_trailer_enabled'), isFalse);
    expect(prefs.getBool('home_hero_trailer_audio_enabled'), isFalse);
    expect(prefs.getInt('home_hero_trailer_volume'), 40);
    expect(prefs.getString('tv_home_style'), 'spotlight');
    expect(StorageService.tvHomeStyleCached, 'spotlight');
  });

  test(
    'raw remaining Home bytes round-trip through StorageService getters',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_disabled_sections_v1': jsonEncode(['cw:series']),
        'home_extra_rows_v1': jsonEncode([
          {'id': 'simkllist:trending', 'title': 'Trending'},
        ]),
        'home_row_order_v1': jsonEncode(['cw:series', 'fav:iptv']),
        'home_hero_source_v1': jsonEncode({
          'mode': 'auto',
          'ids': ['kept'],
        }),
        'home_tick_sources': <String>['mdblist'],
        'home_hero_trailer_enabled': false,
        'home_hero_trailer_audio_enabled': false,
        'home_hero_trailer_volume': 15,
        'tv_home_style': 'atrium',
      });

      expect(await StorageService.getHomeDisabledSections(), {'cw:series'});
      final extras = await StorageService.getHomeExtraRows();
      expect(extras, hasLength(1));
      expect(extras.single, (id: 'simkllist:trending', title: 'Trending'));
      expect(await StorageService.getHomeRowOrder(), ['cw:series', 'fav:iptv']);
      final hero = await StorageService.getHomeHeroSource();
      expect(hero.mode, HomeHeroSourceMode.auto);
      expect(hero.ids, ['kept']);
      expect(await StorageService.getHomeTickSources(), {TrackingSource.mdblist});
      expect(await StorageService.getHomeHeroTrailerEnabled(), isFalse);
      expect(
        await StorageService.getAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
        ),
        isFalse,
      );
      expect(
        await StorageService.getAmbientTrailerVolume(
          AmbientTrailerSurface.homeHero,
        ),
        15,
      );
      expect(await StorageService.getTvHomeStyle(), 'atrium');
      expect(StorageService.tvHomeStyleCached, 'atrium');
    },
  );

  test('empty remaining Home collections remove their keys', () async {
    await StorageService.setHomeDisabledSections({'cw:movies'});
    await StorageService.setHomeExtraRows(const [
      (id: 'traktlist:watchlist', title: ''),
    ]);
    await StorageService.setHomeRowOrder(['cw:movies']);
    await StorageService.setHomeHeroSource((
      mode: HomeHeroSourceMode.custom,
      ids: ['cinemeta:movie:top'],
    ));

    await StorageService.setHomeDisabledSections({});
    await StorageService.setHomeExtraRows(const []);
    await StorageService.setHomeRowOrder(const []);
    await StorageService.setHomeHeroSource((
      mode: HomeHeroSourceMode.random,
      ids: const [],
    ));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('home_disabled_sections_v1'), isFalse);
    expect(prefs.containsKey('home_extra_rows_v1'), isFalse);
    expect(prefs.containsKey('home_row_order_v1'), isFalse);
    expect(prefs.containsKey('home_hero_source_v1'), isFalse);
  });

  test('home extra rows skip malformed entries and degrade non-string titles',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_extra_rows_v1': jsonEncode([
        {'id': 'simkllist:trending', 'title': 'Trending'},
        {'title': 'no id'},
        'bare string',
        {'id': '', 'title': 'empty id'},
        {'id': 'simkllist:trending', 'title': 'duplicate'},
        {'id': 'traktlist:popular', 'title': 42},
      ]),
    });
    final rows = await StorageService.getHomeExtraRows();
    expect(rows, hasLength(2));
    expect(rows[0], (id: 'simkllist:trending', title: 'Trending'));
    expect(rows[1], (id: 'traktlist:popular', title: ''));
  });

  test('home row order deduplicates and ignores empty or non-string ids',
      () async {
    await StorageService.setHomeRowOrder([
      'fav:playlist',
      'cw:movies',
      'fav:playlist',
      '',
    ]);
    expect(await StorageService.getHomeRowOrder(), [
      'fav:playlist',
      'cw:movies',
    ]);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_row_order_v1': jsonEncode(['cw:series', 4, '', 'cw:series', 'fav:iptv']),
    });
    expect(await StorageService.getHomeRowOrder(), ['cw:series', 'fav:iptv']);
  });

  test('home hero source quirks: auto is stored; custom with no ids reads random',
      () async {
    await StorageService.setHomeHeroSource((
      mode: HomeHeroSourceMode.auto,
      ids: const [],
    ));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_hero_source_v1'), isNotNull);
    expect(
      (await StorageService.getHomeHeroSource()).mode,
      HomeHeroSourceMode.auto,
    );

    await StorageService.setHomeHeroSource((
      mode: HomeHeroSourceMode.random,
      ids: ['cinemeta:movie:top'],
    ));
    expect(prefs.getString('home_hero_source_v1'), isNotNull);
    final withIds = await StorageService.getHomeHeroSource();
    expect(withIds.mode, HomeHeroSourceMode.random);
    expect(withIds.ids, ['cinemeta:movie:top']);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_hero_source_v1': jsonEncode({'mode': 'custom', 'ids': <String>[]}),
    });
    expect(
      (await StorageService.getHomeHeroSource()).mode,
      HomeHeroSourceMode.random,
    );

    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_hero_source_v1': 'not-json{',
    });
    final corrupt = await StorageService.getHomeHeroSource();
    expect(corrupt.mode, HomeHeroSourceMode.random);
    expect(corrupt.ids, isEmpty);
  });

  test('home tick sources: absent is all, empty list is none, unknowns drop',
      () async {
    expect(
      await StorageService.getHomeTickSources(),
      Set<TrackingSource>.of(TrackingSource.values),
    );

    await StorageService.setHomeTickSources(<TrackingSource>{});
    final prefs = await SharedPreferences.getInstance();
    // Quirk: empty set writes an empty list; it does not remove the key.
    expect(prefs.getStringList('home_tick_sources'), isEmpty);
    expect(await StorageService.getHomeTickSources(), isEmpty);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_tick_sources': <String>['local', 'nope', 'simkl', 'local'],
    });
    expect(await StorageService.getHomeTickSources(), {
      TrackingSource.local,
      TrackingSource.simkl,
    });

    final before = StorageService.trackingSourceRevision.value;
    await StorageService.setHomeTickSources({TrackingSource.trakt});
    expect(StorageService.trackingSourceRevision.value, before + 1);
    final after = await SharedPreferences.getInstance();
    expect(after.getStringList('home_tick_sources'), ['trakt']);
  });

  test('tv home style coerces unknown values to canvas both ways', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tv_home_style': 'shelf',
    });
    expect(await StorageService.getTvHomeStyle(), 'canvas');
    expect(StorageService.tvHomeStyleCached, 'canvas');

    await StorageService.setTvHomeStyle('not-a-layout');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tv_home_style'), 'canvas');
    expect(StorageService.tvHomeStyleCached, 'canvas');

    for (final style in StorageService.kTvHomeStyles) {
      await StorageService.setTvHomeStyle(style);
      expect(await StorageService.getTvHomeStyle(), style);
      expect(prefs.getString('tv_home_style'), style);
    }
  });

  test('home hero trailer volume clamps to 10–100; detail keys stay separate',
      () async {
    await StorageService.setAmbientTrailerVolume(
      AmbientTrailerSurface.homeHero,
      1,
    );
    await StorageService.setAmbientTrailerVolume(
      AmbientTrailerSurface.detail,
      1000,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('home_hero_trailer_volume'), 10);
    expect(prefs.getInt('detail_trailer_volume'), 100);
    expect(
      await StorageService.getAmbientTrailerVolume(
        AmbientTrailerSurface.homeHero,
      ),
      10,
    );
    expect(
      await StorageService.getAmbientTrailerVolume(
        AmbientTrailerSurface.detail,
      ),
      100,
    );

    await StorageService.setAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.homeHero,
      false,
    );
    await StorageService.setAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.detail,
      true,
    );
    expect(prefs.getBool('home_hero_trailer_audio_enabled'), isFalse);
    expect(prefs.getBool('detail_trailer_audio_enabled'), isTrue);
  });

  test('corrupt remaining Home JSON reads as the empty/default fallback',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_disabled_sections_v1': 'not-json{',
      'home_extra_rows_v1': 'not-json{',
      'home_row_order_v1': 'not-json{',
    });
    expect(await StorageService.getHomeDisabledSections(), isEmpty);
    expect(await StorageService.getHomeExtraRows(), isEmpty);
    expect(await StorageService.getHomeRowOrder(), isEmpty);
  });
}
