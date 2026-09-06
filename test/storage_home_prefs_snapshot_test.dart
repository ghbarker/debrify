import 'package:debrify/services/storage/ambient_trailer_prefs.dart' show AmbientTrailerPrefs;
import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart'
    hide HomeCardOrientation, HomeHeroSourceMode, HomeHeroSource, HomeExtraRow;
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
    expect(await HomePrefs.getHomeDefaultSourceType(), isNull);
    expect(await HomePrefs.getHomeDefaultAddonUrl(), isNull);
    expect(await HomePrefs.getHomeDefaultCatalogId(), isNull);
    expect(await HomePrefs.getHomeDefaultTraktListType(), isNull);
    expect(await HomePrefs.getHomeDefaultTraktContentType(), isNull);
    expect(await HomePrefs.getHomeHideProviderCards(), isTrue);
    expect(await HomePrefs.getHomeContinueWatchingEnabled(), isTrue);
    expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isFalse);
    expect(await HomePrefs.getHomeCwMergedRows('local'), isFalse);
    expect(await HomePrefs.getHomeCwMergedRows('trakt'), isFalse);
    expect(await HomePrefs.getHomeCwMergedRows('simkl'), isFalse);
    expect(await HomePrefs.getHomeCwMergedRows('mdblist'), isFalse);
    expect(await HomePrefs.getHomeFavoritesTapAction(), 'choose');
    expect(
      await HomePrefs.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );
    expect(await HomePrefs.getHomeHideCardTitlesAndRatings(), isFalse);
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isFalse);
  });

  test('StorageService writes the historical Home page key bytes', () async {
    await HomePrefs.setHomeDefaultSourceType('addon');
    await HomePrefs.setHomeDefaultAddonUrl(
      'https://addon.example/manifest.json',
    );
    await HomePrefs.setHomeDefaultCatalogId('top');
    await HomePrefs.setHomeDefaultTraktListType('watchlist');
    await HomePrefs.setHomeDefaultTraktContentType('movies');
    await HomePrefs.setHomeHideProviderCards(false);
    await HomePrefs.setHomeContinueWatchingEnabled(false);
    await HomePrefs.setHomeCwHoldToQuickPlay(true);
    await HomePrefs.setHomeCwMergedRows('local', true);
    await HomePrefs.setHomeCwMergedRows('trakt', true);
    await HomePrefs.setHomeCwMergedRows('simkl', true);
    await HomePrefs.setHomeCwMergedRows('mdblist', true);
    await HomePrefs.setHomeFavoritesTapAction('open');
    await HomePrefs.setHomeCardOrientation(HomeCardOrientation.portrait);
    await HomePrefs.setHomeHideCardTitlesAndRatings(true);
    await HomePrefs.setHomeHideCatalogAddonNames(true);

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

      expect(await HomePrefs.getHomeDefaultSourceType(), 'trakt');
      expect(
        await HomePrefs.getHomeDefaultAddonUrl(),
        'https://x/manifest.json',
      );
      expect(await HomePrefs.getHomeDefaultCatalogId(), 'catalog');
      expect(await HomePrefs.getHomeDefaultTraktListType(), 'collection');
      expect(await HomePrefs.getHomeDefaultTraktContentType(), 'shows');
      expect(await HomePrefs.getHomeHideProviderCards(), isFalse);
      expect(await HomePrefs.getHomeContinueWatchingEnabled(), isFalse);
      expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isTrue);
      expect(await HomePrefs.getHomeCwMergedRows('local'), isTrue);
      expect(await HomePrefs.getHomeFavoritesTapAction(), 'play');
      expect(
        await HomePrefs.getHomeCardOrientation(),
        HomeCardOrientation.portrait,
      );
      expect(await HomePrefs.getHomeHideCardTitlesAndRatings(), isTrue);
      expect(await HomePrefs.getHomeHideCatalogAddonNames(), isTrue);
    },
  );

  test('null Home default setters remove the key', () async {
    await HomePrefs.setHomeDefaultSourceType('addon');
    await HomePrefs.setHomeDefaultAddonUrl('https://a/manifest.json');
    await HomePrefs.setHomeDefaultCatalogId('top');
    await HomePrefs.setHomeDefaultTraktListType('watchlist');
    await HomePrefs.setHomeDefaultTraktContentType('movies');

    await HomePrefs.setHomeDefaultSourceType(null);
    await HomePrefs.setHomeDefaultAddonUrl(null);
    await HomePrefs.setHomeDefaultCatalogId(null);
    await HomePrefs.setHomeDefaultTraktListType(null);
    await HomePrefs.setHomeDefaultTraktContentType(null);

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
        await HomePrefs.getHomeCardOrientation(),
        HomeCardOrientation.landscape,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_card_orientation': 'garbage',
      });
      expect(
        await HomePrefs.getHomeCardOrientation(),
        HomeCardOrientation.landscape,
      );

      await HomePrefs.setHomeCardOrientation(
        HomeCardOrientation.landscape,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_card_orientation'), 'landscape');
    },
  );

  test('clearAllHomePageSettings leaves Trakt default keys', () async {
    await HomePrefs.setHomeDefaultSourceType('addon');
    await HomePrefs.setHomeDefaultAddonUrl('https://a/manifest.json');
    await HomePrefs.setHomeDefaultCatalogId('top');
    await HomePrefs.setHomeDefaultTraktListType('watchlist');
    await HomePrefs.setHomeDefaultTraktContentType('movies');
    await HomePrefs.setHomeHideProviderCards(false);
    await HomePrefs.setHomeContinueWatchingEnabled(false);
    await HomePrefs.setHomeCwHoldToQuickPlay(true);
    await HomePrefs.setHomeCwMergedRows('local', true);
    await HomePrefs.setHomeCwMergedRows('trakt', true);
    await HomePrefs.setHomeCwMergedRows('simkl', true);
    await HomePrefs.setHomeCwMergedRows('mdblist', true);
    await HomePrefs.setHomeFavoritesTapAction('open');
    await HomePrefs.setHomeCardOrientation(HomeCardOrientation.portrait);
    await HomePrefs.setHomeHideCardTitlesAndRatings(true);
    await HomePrefs.setHomeHideCatalogAddonNames(true);
    await HomePrefs.setHomeDisabledSections({'cw:movies'});
    await HomePrefs.setHomeExtraRows(const [
      (id: 'traktlist:watchlist', title: 'Watchlist'),
    ]);
    await HomePrefs.setHomeRowOrder(['cw:movies', 'fav:iptv']);
    await HomePrefs.setHomeHeroSource((
      mode: HomeHeroSourceMode.auto,
      ids: const [],
    ));
    await StorageService.setHomeTickSources({TrackingSource.trakt});
    await HomePrefs.setHomeHeroTrailerEnabled(false);
    await AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.homeHero,
      false,
    );
    await AmbientTrailerPrefs.setAmbientTrailerVolume(
      AmbientTrailerSurface.homeHero,
      40,
    );
    await StorageService.setTvHomeStyle('spotlight');

    await HomePrefs.clearAllHomePageSettings();

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
    await HomePrefs.setHomeDefaultSourceType('addon');
    await HomePrefs.setHomeHideProviderCards(false);
    await HomePrefs.setHomeCwHoldToQuickPlay(true);
    await HomePrefs.setHomeCwMergedRows('simkl', true);
    await HomePrefs.setHomeCardOrientation(HomeCardOrientation.portrait);
    await HomePrefs.setHomeHideCardTitlesAndRatings(true);

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

    expect(await HomePrefs.getHomeDefaultCatalogId(), 'top');
    expect(await HomePrefs.getHomeContinueWatchingEnabled(), isFalse);
    expect(await HomePrefs.getHomeFavoritesTapAction(), 'open');
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isTrue);
    expect(await HomePrefs.getHomeDefaultTraktListType(), 'watchlist');
    expect(
      await HomePrefs.getHomeCardOrientation(),
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
    expect(await HomePrefs.getHomeDisabledSections(), isEmpty);
    expect(await HomePrefs.getHomeExtraRows(), isEmpty);
    expect(await HomePrefs.getHomeRowOrder(), isEmpty);
    final hero = await HomePrefs.getHomeHeroSource();
    expect(hero.mode, HomeHeroSourceMode.random);
    expect(hero.ids, isEmpty);
    expect(
      await StorageService.getHomeTickSources(),
      Set<TrackingSource>.of(TrackingSource.values),
    );
    expect(await HomePrefs.getHomeHeroTrailerEnabled(), isTrue);
    expect(
      await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.homeHero,
      ),
      isTrue,
    );
    expect(
      await AmbientTrailerPrefs.getAmbientTrailerVolume(
        AmbientTrailerSurface.homeHero,
      ),
      70,
    );
    expect(await StorageService.getTvHomeStyle(), 'canvas');
    expect(StorageService.tvHomeStyleCached, 'canvas');
  });

  test(
    'StorageService writes the historical remaining Home key bytes',
    () async {
      await HomePrefs.setHomeDisabledSections({'cw:movies', 'fav:iptv'});
      await HomePrefs.setHomeExtraRows(const [
        (id: 'traktlist:watchlist', title: ''),
        (id: 'iptvlist:list_1', title: 'Sports'),
      ]);
      await HomePrefs.setHomeRowOrder(['fav:playlist', 'cw:movies']);
      await HomePrefs.setHomeHeroSource((
        mode: HomeHeroSourceMode.custom,
        ids: ['cinemeta:movie:top', 'cinemeta:series:top'],
      ));
      await StorageService.setHomeTickSources({
        TrackingSource.local,
        TrackingSource.simkl,
      });
      await HomePrefs.setHomeHeroTrailerEnabled(false);
      await AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.homeHero,
        false,
      );
      await AmbientTrailerPrefs.setAmbientTrailerVolume(
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
    },
  );

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

      expect(await HomePrefs.getHomeDisabledSections(), {'cw:series'});
      final extras = await HomePrefs.getHomeExtraRows();
      expect(extras, hasLength(1));
      expect(extras.single, (id: 'simkllist:trending', title: 'Trending'));
      expect(await HomePrefs.getHomeRowOrder(), ['cw:series', 'fav:iptv']);
      final hero = await HomePrefs.getHomeHeroSource();
      expect(hero.mode, HomeHeroSourceMode.auto);
      expect(hero.ids, ['kept']);
      expect(await StorageService.getHomeTickSources(), {
        TrackingSource.mdblist,
      });
      expect(await HomePrefs.getHomeHeroTrailerEnabled(), isFalse);
      expect(
        await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
        ),
        isFalse,
      );
      expect(
        await AmbientTrailerPrefs.getAmbientTrailerVolume(
          AmbientTrailerSurface.homeHero,
        ),
        15,
      );
      expect(await StorageService.getTvHomeStyle(), 'atrium');
      expect(StorageService.tvHomeStyleCached, 'atrium');
    },
  );

  test('empty remaining Home collections remove their keys', () async {
    await HomePrefs.setHomeDisabledSections({'cw:movies'});
    await HomePrefs.setHomeExtraRows(const [
      (id: 'traktlist:watchlist', title: ''),
    ]);
    await HomePrefs.setHomeRowOrder(['cw:movies']);
    await HomePrefs.setHomeHeroSource((
      mode: HomeHeroSourceMode.custom,
      ids: ['cinemeta:movie:top'],
    ));

    await HomePrefs.setHomeDisabledSections({});
    await HomePrefs.setHomeExtraRows(const []);
    await HomePrefs.setHomeRowOrder(const []);
    await HomePrefs.setHomeHeroSource((
      mode: HomeHeroSourceMode.random,
      ids: const [],
    ));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('home_disabled_sections_v1'), isFalse);
    expect(prefs.containsKey('home_extra_rows_v1'), isFalse);
    expect(prefs.containsKey('home_row_order_v1'), isFalse);
    expect(prefs.containsKey('home_hero_source_v1'), isFalse);
  });

  test(
    'home extra rows skip malformed entries and degrade non-string titles',
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
      final rows = await HomePrefs.getHomeExtraRows();
      expect(rows, hasLength(2));
      expect(rows[0], (id: 'simkllist:trending', title: 'Trending'));
      expect(rows[1], (id: 'traktlist:popular', title: ''));
    },
  );

  test(
    'home row order deduplicates and ignores empty or non-string ids',
    () async {
      await HomePrefs.setHomeRowOrder([
        'fav:playlist',
        'cw:movies',
        'fav:playlist',
        '',
      ]);
      expect(await HomePrefs.getHomeRowOrder(), [
        'fav:playlist',
        'cw:movies',
      ]);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_row_order_v1': jsonEncode([
          'cw:series',
          4,
          '',
          'cw:series',
          'fav:iptv',
        ]),
      });
      expect(await HomePrefs.getHomeRowOrder(), ['cw:series', 'fav:iptv']);
    },
  );

  test(
    'home hero source quirks: auto is stored; custom with no ids reads random',
    () async {
      await HomePrefs.setHomeHeroSource((
        mode: HomeHeroSourceMode.auto,
        ids: const [],
      ));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_hero_source_v1'), isNotNull);
      expect(
        (await HomePrefs.getHomeHeroSource()).mode,
        HomeHeroSourceMode.auto,
      );

      await HomePrefs.setHomeHeroSource((
        mode: HomeHeroSourceMode.random,
        ids: ['cinemeta:movie:top'],
      ));
      expect(prefs.getString('home_hero_source_v1'), isNotNull);
      final withIds = await HomePrefs.getHomeHeroSource();
      expect(withIds.mode, HomeHeroSourceMode.random);
      expect(withIds.ids, ['cinemeta:movie:top']);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_hero_source_v1': jsonEncode({
          'mode': 'custom',
          'ids': <String>[],
        }),
      });
      expect(
        (await HomePrefs.getHomeHeroSource()).mode,
        HomeHeroSourceMode.random,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_hero_source_v1': 'not-json{',
      });
      final corrupt = await HomePrefs.getHomeHeroSource();
      expect(corrupt.mode, HomeHeroSourceMode.random);
      expect(corrupt.ids, isEmpty);
    },
  );

  test(
    'home tick sources: absent is all, empty list is none, unknowns drop',
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
    },
  );

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

  test(
    'home hero trailer volume clamps to 10–100; detail keys stay separate',
    () async {
      await AmbientTrailerPrefs.setAmbientTrailerVolume(
        AmbientTrailerSurface.homeHero,
        1,
      );
      await AmbientTrailerPrefs.setAmbientTrailerVolume(
        AmbientTrailerSurface.detail,
        1000,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('home_hero_trailer_volume'), 10);
      expect(prefs.getInt('detail_trailer_volume'), 100);
      expect(
        await AmbientTrailerPrefs.getAmbientTrailerVolume(
          AmbientTrailerSurface.homeHero,
        ),
        10,
      );
      expect(
        await AmbientTrailerPrefs.getAmbientTrailerVolume(
          AmbientTrailerSurface.detail,
        ),
        100,
      );

      await AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.homeHero,
        false,
      );
      await AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.detail,
        true,
      );
      expect(prefs.getBool('home_hero_trailer_audio_enabled'), isFalse);
      expect(prefs.getBool('detail_trailer_audio_enabled'), isTrue);
    },
  );

  test(
    'corrupt remaining Home JSON reads as the empty/default fallback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'home_disabled_sections_v1': 'not-json{',
        'home_extra_rows_v1': 'not-json{',
        'home_row_order_v1': 'not-json{',
      });
      expect(await HomePrefs.getHomeDisabledSections(), isEmpty);
      expect(await HomePrefs.getHomeExtraRows(), isEmpty);
      expect(await HomePrefs.getHomeRowOrder(), isEmpty);
    },
  );

  test(
    'StorageService remaining Home writes are readable through HomePrefs',
    () async {
      await HomePrefs.setHomeDisabledSections({'cw:movies'});
      await HomePrefs.setHomeExtraRows(const [
        (id: 'iptvlist:list_1', title: 'Sports'),
      ]);
      await HomePrefs.setHomeRowOrder(['cw:movies', 'fav:iptv']);
      await HomePrefs.setHomeHeroSource((
        mode: HomeHeroSourceMode.custom,
        ids: ['cinemeta:movie:top'],
      ));
      await StorageService.setHomeTickSources({TrackingSource.simkl});
      await HomePrefs.setHomeHeroTrailerEnabled(false);
      await AmbientTrailerPrefs.setAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.homeHero,
        false,
      );
      await AmbientTrailerPrefs.setAmbientTrailerVolume(
        AmbientTrailerSurface.homeHero,
        40,
      );
      await StorageService.setTvHomeStyle('spotlight');

      expect(await HomePrefs.getHomeDisabledSections(), {'cw:movies'});
      expect(await HomePrefs.getHomeExtraRows(), [
        (id: 'iptvlist:list_1', title: 'Sports'),
      ]);
      expect(await HomePrefs.getHomeRowOrder(), ['cw:movies', 'fav:iptv']);
      final hero = await HomePrefs.getHomeHeroSource();
      expect(hero.mode, HomeHeroSourceMode.custom);
      expect(hero.ids, ['cinemeta:movie:top']);
      expect(await HomePrefs.getHomeTickSources(), {TrackingSource.simkl});
      expect(await HomePrefs.getHomeHeroTrailerEnabled(), isFalse);
      expect(await HomePrefs.getHomeHeroTrailerAudioEnabled(), isFalse);
      expect(await HomePrefs.getHomeHeroTrailerVolume(), 40);
      expect(await HomePrefs.getTvHomeStyle(), 'spotlight');
      expect(HomePrefs.tvHomeStyleCached, 'spotlight');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('home_disabled_sections_v1'),
        jsonEncode(['cw:movies']),
      );
      expect(prefs.getStringList('home_tick_sources'), ['simkl']);
      expect(prefs.getBool('home_hero_trailer_enabled'), isFalse);
      expect(prefs.getString('tv_home_style'), 'spotlight');
    },
  );

  test(
    'HomePrefs remaining Home writes are readable through StorageService',
    () async {
      await HomePrefs.setHomeDisabledSections({'fav:iptv'});
      await HomePrefs.setHomeExtraRows(const [
        (id: 'traktlist:watchlist', title: ''),
      ]);
      await HomePrefs.setHomeRowOrder(['fav:iptv']);
      await HomePrefs.setHomeHeroSource((
        mode: HomeHeroSourceMode.auto,
        ids: const [],
      ));
      await HomePrefs.setHomeTickSources({TrackingSource.mdblist});
      await HomePrefs.setHomeHeroTrailerEnabled(true);
      await HomePrefs.setHomeHeroTrailerAudioEnabled(true);
      await HomePrefs.setHomeHeroTrailerVolume(70);
      await HomePrefs.setTvHomeStyle('atrium');

      expect(await HomePrefs.getHomeDisabledSections(), {'fav:iptv'});
      expect(await HomePrefs.getHomeExtraRows(), [
        (id: 'traktlist:watchlist', title: ''),
      ]);
      expect(await HomePrefs.getHomeRowOrder(), ['fav:iptv']);
      final hero = await HomePrefs.getHomeHeroSource();
      expect(hero.mode, HomeHeroSourceMode.auto);
      expect(await StorageService.getHomeTickSources(), {
        TrackingSource.mdblist,
      });
      expect(await HomePrefs.getHomeHeroTrailerEnabled(), isTrue);
      expect(
        await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
        ),
        isTrue,
      );
      expect(
        await AmbientTrailerPrefs.getAmbientTrailerVolume(
          AmbientTrailerSurface.homeHero,
        ),
        70,
      );
      expect(await StorageService.getTvHomeStyle(), 'atrium');
      expect(StorageService.tvHomeStyleCached, 'atrium');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_row_order_v1'), jsonEncode(['fav:iptv']));
      expect(prefs.getStringList('home_tick_sources'), ['mdblist']);
      expect(prefs.getString('tv_home_style'), 'atrium');
    },
  );
}
