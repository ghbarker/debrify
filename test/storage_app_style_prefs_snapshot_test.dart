import 'dart:convert';

import 'package:debrify/models/sidebar_configuration.dart';
import 'package:debrify/models/tv_hero_artwork_quality.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins sync style-cache encodings on [StorageService] before the S2-4
/// extract. Key names and values are a frozen compatibility surface.
/// This file must not import the new store — that lands in the move commit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's24-pin-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
  });

  tearDown(ProfileRuntime.debugReset);

  group('style cache defaults', () {
    test('phone nav, debrify TV, detail page/theme, app theme', () async {
      expect(await StorageService.getPhoneNavStyle(), 'classic');
      expect(await StorageService.getPhoneNavBarIndices(), isNull);
      expect(await StorageService.getDebrifyTvStyle(), 'grid');
      expect(StorageService.debrifyTvStyleCached, 'grid');
      expect(StorageService.kDebrifyTvStyles, {'grid', 'spotlight'});
      expect(await StorageService.getDetailPageStyle(), 'console');
      expect(StorageService.detailPageStyleCached, 'console');
      expect(StorageService.kDetailPageStyleDefault, 'console');
      expect(await StorageService.getDetailTheme(), 'signal');
      expect(StorageService.detailThemeCached, 'signal');
      expect(await StorageService.getAppTheme(), 'legacy');
      expect(StorageService.appThemeCached, 'legacy');
      expect(await StorageService.getThemeOverrides(), '');
      expect(StorageService.themeOverridesCached, '');
    });

    test('parents guide, IPTV look, dock, loaders, TV player skins', () async {
      expect(await StorageService.getParentsGuideStyle(), 'compass');
      expect(StorageService.parentsGuideStyleCached, 'compass');
      expect(StorageService.kParentsGuideStyles, {'classic', 'compass'});
      expect(await StorageService.getIptvStyle(), 'command');
      expect(StorageService.iptvStyleCached, 'command');
      expect(await StorageService.getIptvChannelPreviewEnabled(), isTrue);
      expect(await StorageService.getPlayerDockStyle(), 'classic');
      expect(await StorageService.getPlayerDockPalette(), 'ultraviolet');
      expect(await StorageService.getPlayerDockSize(), 'auto');
      expect(await StorageService.getIptvPlayerGuideStyle(), 'classic');
      expect(await StorageService.getPlayLoaderStyle(), 'marquee');
      expect(await StorageService.getTvPlayerControlsStyle(), 'marquee');
      expect(await StorageService.getDebrifyTvPlayerStyle(), 'cinema');
    });

    test('discover, launch, text brightness, sidebars, TV chrome', () async {
      expect(
        await StorageService.getDiscoverDefaultSource(),
        StorageService.discoverDefaultRememberLast,
      );
      expect(StorageService.discoverDefaultRememberLast, 'remember');
      expect(await StorageService.getDiscoverLastSource(), 'cw');
      expect(await StorageService.getDiscoverLayout(), 'stage');
      expect(StorageService.discoverLayoutCached, 'stage');
      expect(await StorageService.getLaunchAnimation(), 'trace');
      expect(StorageService.launchAnimationCached, 'trace');
      expect(await StorageService.getLaunchIdentPalette(), 'ident');
      expect(StorageService.launchIdentPaletteCached, 'ident');
      expect(await StorageService.getTextBrightness(), 'bright');
      expect(await StorageService.getTvSidebarStyle(), 'ghost');
      expect(StorageService.tvSidebarStyleCached, 'ghost');
      expect(await StorageService.getDesktopSidebarStyle(), 'rail');
      expect(StorageService.desktopSidebarStyleCached, 'rail');
      expect(
        (await StorageService.getSidebarConfiguration()).isDefault,
        isTrue,
      );
      expect(await StorageService.getTvUiScalePercent(), 90);
      expect(StorageService.kTvUiScaleDefault, 90);
      expect(StorageService.kTvUiScaleOptions, [100, 90, 80]);
      expect(
        await StorageService.getTvHeroArtworkQuality(),
        TvHeroArtworkQuality.automatic,
      );
    });
  });

  test('StorageService writes the historical style key bytes', () async {
    await StorageService.setPhoneNavStyle('floating');
    await StorageService.setPhoneNavBarIndices([2, 4, 6]);
    await StorageService.setDebrifyTvStyle('spotlight');
    await StorageService.setDetailPageStyle('showcase');
    await StorageService.setDetailTheme('prestige');
    await StorageService.setAppTheme('spotlight');
    await StorageService.setThemeOverrides('{"accent":"#ff00aa"}');
    await StorageService.setParentsGuideStyle('classic');
    await StorageService.setIptvStyle('edition');
    await StorageService.setIptvChannelPreviewEnabled(false);
    await StorageService.setPlayerDockStyle('cinema');
    await StorageService.setPlayerDockPalette('ice');
    await StorageService.setPlayerDockSize('large');
    await StorageService.setIptvPlayerGuideStyle('glass');
    await StorageService.setPlayLoaderStyle('classic');
    await StorageService.setTvPlayerControlsStyle('ott');
    await StorageService.setDebrifyTvPlayerStyle('prestige');
    await StorageService.setDiscoverDefaultSource('trakt');
    await StorageService.setDiscoverLastSource('simkl');
    await StorageService.setDiscoverLayout('grid');
    await StorageService.setLaunchAnimation('horizon');
    await StorageService.setLaunchIdentPalette('theme');
    await StorageService.setTextBrightness('dim');
    await StorageService.setTvSidebarStyle('pill');
    await StorageService.setDesktopSidebarStyle('pill');
    await StorageService.setTvUiScalePercent(80);
    await StorageService.setTvHeroArtworkQuality(TvHeroArtworkQuality.fullHd);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('phone_nav_style'), 'floating');
    expect(prefs.getStringList('phone_nav_bar_indices'), ['2', '4', '6']);
    expect(prefs.getString('debrify_tv_style'), 'spotlight');
    expect(prefs.getString('detail_page_style'), 'showcase');
    expect(prefs.getString('detail_theme'), 'prestige');
    expect(prefs.getString('app_theme'), 'spotlight');
    expect(prefs.getString('theme_overrides'), '{"accent":"#ff00aa"}');
    expect(prefs.getString('parents_guide_style'), 'classic');
    expect(prefs.getString('iptv_style'), 'edition');
    expect(prefs.getBool('iptv_channel_preview_enabled'), isFalse);
    expect(prefs.getString('player_dock_style'), 'cinema');
    expect(prefs.getString('player_dock_palette'), 'ice');
    expect(prefs.getString('player_dock_size'), 'large');
    expect(prefs.getString('iptv_player_guide_style'), 'glass');
    expect(prefs.getString('play_loader_style'), 'classic');
    expect(prefs.getString('tv_player_controls_style'), 'ott');
    expect(prefs.getString('debrify_tv_player_style'), 'prestige');
    expect(prefs.getString('discover_default_source'), 'trakt');
    expect(prefs.getString('discover_last_source'), 'simkl');
    expect(prefs.getString('discover_layout'), 'grid');
    expect(prefs.getString('launch_animation'), 'horizon');
    expect(prefs.getString('launch_ident_palette'), 'theme');
    expect(prefs.getString('text_brightness'), 'dim');
    expect(prefs.getString('tv_sidebar_style'), 'pill');
    expect(prefs.getString('desktop_sidebar_style'), 'pill');
    expect(prefs.getInt('tv_ui_scale_percent'), 80);
    expect(prefs.getString('tv_hero_artwork_quality'), 'full_hd');
  });

  test('raw style bytes round-trip through StorageService getters', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'phone_nav_style': 'floating',
      'phone_nav_bar_indices': <String>['1', '3'],
      'debrify_tv_style': 'spotlight',
      'detail_page_style': 'marquee',
      'detail_theme': 'noir',
      'app_theme': 'velvet',
      'theme_overrides': '{"ok":true}',
      'parents_guide_style': 'classic',
      'iptv_style': 'console',
      'iptv_channel_preview_enabled': false,
      'player_dock_style': 'two_tier',
      'player_dock_palette': 'aurum',
      'player_dock_size': 'small',
      'iptv_player_guide_style': 'spotlight',
      'play_loader_style': 'classic',
      'tv_player_controls_style': 'frost',
      'debrify_tv_player_style': 'guide',
      'discover_default_source': 'a:addon-1',
      'discover_last_source': 'mdblist',
      'discover_layout': 'grid',
      'launch_animation': 'neon',
      'launch_ident_palette': 'theme',
      'text_brightness': 'soft',
      'tv_sidebar_style': 'island',
      'desktop_sidebar_style': 'pill',
      'tv_ui_scale_percent': 100,
      'tv_hero_artwork_quality': 'performance',
    });

    expect(await StorageService.getPhoneNavStyle(), 'floating');
    expect(await StorageService.getPhoneNavBarIndices(), [1, 3]);
    expect(await StorageService.getDebrifyTvStyle(), 'spotlight');
    expect(StorageService.debrifyTvStyleCached, 'spotlight');
    expect(await StorageService.getDetailPageStyle(), 'marquee');
    expect(await StorageService.getDetailTheme(), 'noir');
    expect(await StorageService.getAppTheme(), 'velvet');
    expect(await StorageService.getThemeOverrides(), '{"ok":true}');
    expect(await StorageService.getParentsGuideStyle(), 'classic');
    expect(await StorageService.getIptvStyle(), 'console');
    expect(await StorageService.getIptvChannelPreviewEnabled(), isFalse);
    // Quirk: pre-selectable dock value 'two_tier' is still accepted on read.
    expect(await StorageService.getPlayerDockStyle(), 'two_tier');
    expect(await StorageService.getPlayerDockPalette(), 'aurum');
    expect(await StorageService.getPlayerDockSize(), 'small');
    expect(await StorageService.getIptvPlayerGuideStyle(), 'spotlight');
    expect(await StorageService.getPlayLoaderStyle(), 'classic');
    expect(await StorageService.getTvPlayerControlsStyle(), 'frost');
    expect(await StorageService.getDebrifyTvPlayerStyle(), 'guide');
    expect(await StorageService.getDiscoverDefaultSource(), 'a:addon-1');
    expect(await StorageService.getDiscoverLastSource(), 'mdblist');
    expect(await StorageService.getDiscoverLayout(), 'grid');
    expect(await StorageService.getLaunchAnimation(), 'neon');
    expect(await StorageService.getLaunchIdentPalette(), 'theme');
    expect(await StorageService.getTextBrightness(), 'soft');
    expect(await StorageService.getTvSidebarStyle(), 'island');
    expect(await StorageService.getDesktopSidebarStyle(), 'pill');
    expect(await StorageService.getTvUiScalePercent(), 100);
    expect(
      await StorageService.getTvHeroArtworkQuality(),
      TvHeroArtworkQuality.performance,
    );
  });

  test(
    'unknown values coerce to the origin fallbacks on read and write',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'phone_nav_style': 'drawer',
        'debrify_tv_style': 'holodeck',
        'detail_page_style': 'future-look',
        'detail_theme': 'removed',
        'app_theme': 'removed',
        'parents_guide_style': 'cards',
        'iptv_style': 'neon',
        'player_dock_style': 'ribbon',
        'player_dock_palette': 'jade',
        'player_dock_size': 'huge',
        'iptv_player_guide_style': 'holo',
        'play_loader_style': 'orbit',
        'tv_player_controls_style': 'holodeck',
        'debrify_tv_player_style': 'holodeck',
        'discover_layout': 'mosaic',
        'discover_default_source': 'nope',
        'discover_last_source': 'nope',
        'launch_animation': 'not-an-ident',
        'launch_ident_palette': 'custom',
        'text_brightness': 'blinding',
        'tv_sidebar_style': 'holodeck',
        'desktop_sidebar_style': 'overlay',
        'tv_ui_scale_percent': 70,
        'tv_hero_artwork_quality': '4k',
      });

      expect(await StorageService.getPhoneNavStyle(), 'classic');
      expect(await StorageService.getDebrifyTvStyle(), 'grid');
      expect(await StorageService.getDetailPageStyle(), 'console');
      expect(await StorageService.getDetailTheme(), 'signal');
      expect(await StorageService.getAppTheme(), 'legacy');
      expect(await StorageService.getParentsGuideStyle(), 'compass');
      expect(await StorageService.getIptvStyle(), 'command');
      expect(await StorageService.getPlayerDockStyle(), 'classic');
      expect(await StorageService.getPlayerDockPalette(), 'ultraviolet');
      expect(await StorageService.getPlayerDockSize(), 'auto');
      // Unset/unknown guide is classic on non-tvOS (this host).
      expect(await StorageService.getIptvPlayerGuideStyle(), 'classic');
      expect(await StorageService.getPlayLoaderStyle(), 'marquee');
      expect(await StorageService.getTvPlayerControlsStyle(), 'marquee');
      expect(await StorageService.getDebrifyTvPlayerStyle(), 'cinema');
      expect(await StorageService.getDiscoverLayout(), 'stage');
      expect(
        await StorageService.getDiscoverDefaultSource(),
        StorageService.discoverDefaultRememberLast,
      );
      expect(await StorageService.getDiscoverLastSource(), 'cw');
      expect(await StorageService.getLaunchAnimation(), 'trace');
      expect(await StorageService.getLaunchIdentPalette(), 'ident');
      expect(await StorageService.getTextBrightness(), 'bright');
      expect(await StorageService.getTvSidebarStyle(), 'ghost');
      expect(await StorageService.getDesktopSidebarStyle(), 'rail');
      expect(await StorageService.getTvUiScalePercent(), 90);
      expect(
        await StorageService.getTvHeroArtworkQuality(),
        TvHeroArtworkQuality.automatic,
      );

      await StorageService.setPhoneNavStyle('drawer');
      await StorageService.setDebrifyTvStyle('holodeck');
      await StorageService.setDetailPageStyle('future-look');
      await StorageService.setDetailTheme('removed');
      await StorageService.setAppTheme('removed');
      await StorageService.setParentsGuideStyle('cards');
      await StorageService.setIptvStyle('neon');
      await StorageService.setPlayerDockStyle('ribbon');
      await StorageService.setPlayerDockPalette('jade');
      await StorageService.setPlayerDockSize('huge');
      await StorageService.setIptvPlayerGuideStyle('holo');
      await StorageService.setPlayLoaderStyle('orbit');
      await StorageService.setTvPlayerControlsStyle('holodeck');
      await StorageService.setDebrifyTvPlayerStyle('holodeck');
      await StorageService.setDiscoverLayout('mosaic');
      await StorageService.setDiscoverDefaultSource('nope');
      await StorageService.setLaunchAnimation('not-an-ident');
      await StorageService.setLaunchIdentPalette('custom');
      await StorageService.setTextBrightness('blinding');
      await StorageService.setTvSidebarStyle('holodeck');
      await StorageService.setDesktopSidebarStyle('overlay');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('phone_nav_style'), 'classic');
      expect(prefs.getString('debrify_tv_style'), 'grid');
      expect(prefs.getString('detail_page_style'), 'console');
      expect(prefs.getString('detail_theme'), 'signal');
      expect(prefs.getString('app_theme'), 'legacy');
      expect(prefs.getString('parents_guide_style'), 'compass');
      expect(prefs.getString('iptv_style'), 'command');
      expect(prefs.getString('player_dock_style'), 'classic');
      expect(prefs.getString('player_dock_palette'), 'ultraviolet');
      expect(prefs.getString('player_dock_size'), 'auto');
      expect(prefs.getString('iptv_player_guide_style'), 'classic');
      expect(prefs.getString('play_loader_style'), 'marquee');
      expect(prefs.getString('tv_player_controls_style'), 'marquee');
      expect(prefs.getString('debrify_tv_player_style'), 'cinema');
      expect(prefs.getString('discover_layout'), 'stage');
      expect(prefs.getString('discover_default_source'), 'remember');
      expect(prefs.getString('launch_animation'), 'trace');
      expect(prefs.getString('launch_ident_palette'), 'ident');
      expect(prefs.getString('text_brightness'), 'bright');
      expect(prefs.getString('tv_sidebar_style'), 'ghost');
      expect(prefs.getString('desktop_sidebar_style'), 'rail');
    },
  );

  test('debrifyTvStyleCached is published before the prefs write', () async {
    expect(StorageService.debrifyTvStyleCached, 'grid');
    final pending = StorageService.setDebrifyTvStyle('spotlight');
    expect(StorageService.debrifyTvStyleCached, 'spotlight');
    await pending;
    expect(await StorageService.getDebrifyTvStyle(), 'spotlight');
  });

  test(
    'themeOverridesCached updates after instance() and before the write',
    () async {
      // Origin awaits ProfilePreferences.instance() first, then publishes the
      // mirror, then writes. Unlike debrifyTvStyleCached, the cache does not
      // move before the first await.
      await StorageService.setThemeOverrides('{"x":1}');
      expect(StorageService.themeOverridesCached, '{"x":1}');
      expect(await StorageService.getThemeOverrides(), '{"x":1}');
    },
  );

  test('empty theme overrides remove the key', () async {
    await StorageService.setThemeOverrides('{"x":1}');
    await StorageService.setThemeOverrides('');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('theme_overrides'), isFalse);
    expect(await StorageService.getThemeOverrides(), '');
  });

  test('iptv / sidebar / discover caches publish before instance()', () async {
    final iptv = StorageService.setIptvStyle('console');
    expect(StorageService.iptvStyleCached, 'console');
    await iptv;

    final tv = StorageService.setTvSidebarStyle('pill');
    expect(StorageService.tvSidebarStyleCached, 'pill');
    await tv;

    final desk = StorageService.setDesktopSidebarStyle('pill');
    expect(StorageService.desktopSidebarStyleCached, 'pill');
    await desk;

    final disc = StorageService.setDiscoverLayout('grid');
    expect(StorageService.discoverLayoutCached, 'grid');
    await disc;
  });

  test('launchIdentPaletteCached updates after instance()', () async {
    // Origin awaits ProfilePreferences.instance() first, then mirrors.
    await StorageService.setLaunchIdentPalette('theme');
    expect(StorageService.launchIdentPaletteCached, 'theme');
  });

  test(
    'detail page / theme / app theme / launch caches update after write',
    () async {
      await StorageService.setDetailPageStyle('vista');
      expect(StorageService.detailPageStyleCached, 'vista');
      await StorageService.setDetailTheme('halo');
      expect(StorageService.detailThemeCached, 'halo');
      await StorageService.setAppTheme('console');
      expect(StorageService.appThemeCached, 'console');
      await StorageService.setLaunchAnimation('ember');
      expect(StorageService.launchAnimationCached, 'ember');
    },
  );

  test('app theme accepts legacy or any kDetailThemes id', () async {
    expect(StorageService.kDetailThemes.contains('spotlight'), isTrue);
    expect(StorageService.kDetailThemes.contains('legacy'), isFalse);
    await StorageService.setAppTheme('legacy');
    expect(await StorageService.getAppTheme(), 'legacy');
    await StorageService.setAppTheme('spotlight');
    expect(await StorageService.getAppTheme(), 'spotlight');
  });

  test('kDetailPageStyles contains every shipped and reserved look', () {
    expect(
      StorageService.kDetailPageStyles,
      containsAll([
        'classic',
        'marquee',
        'dossier',
        'broadsheet',
        'stage',
        'filmstrip',
        'console',
        'vista',
        'monolith',
        'mosaic',
        'halo',
        'premiere',
        'showcase',
      ]),
    );
  });

  test('phone nav bar drops non-integers; empty list is stored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'phone_nav_bar_indices': <String>['2', 'x', '5'],
    });
    expect(await StorageService.getPhoneNavBarIndices(), [2, 5]);

    await StorageService.setPhoneNavBarIndices([]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('phone_nav_bar_indices'), isEmpty);
  });

  test('discover last-source invalid write is a no-op', () async {
    await StorageService.setDiscoverLastSource('trakt');
    await StorageService.setDiscoverLastSource('nope');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('discover_last_source'), 'trakt');
    expect(await StorageService.getDiscoverLastSource(), 'trakt');
  });

  test('TV UI scale setter writes any int; getter coerces unknown', () async {
    await StorageService.setTvUiScalePercent(70);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('tv_ui_scale_percent'), 70);
    expect(await StorageService.getTvUiScalePercent(), 90);
  });

  test('sidebar configuration encode/decode and reset', () async {
    final custom = SidebarConfiguration(
      order: const ['home', 'search'],
      labels: const {'home': 'Start'},
    );
    expect(await StorageService.setSidebarConfiguration(custom), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('sidebar_configuration_v1'), isTrue);
    jsonDecode(prefs.getString('sidebar_configuration_v1')!);
    final stored = await StorageService.getSidebarConfiguration();
    expect(stored.labelForId('home'), 'Start');

    expect(await StorageService.resetSidebarConfiguration(), isTrue);
    expect(prefs.containsKey('sidebar_configuration_v1'), isFalse);
    expect((await StorageService.getSidebarConfiguration()).isDefault, isTrue);
  });

  test('resetProfileCaches restores style mirrors to defaults', () async {
    await StorageService.setDebrifyTvStyle('spotlight');
    await StorageService.setDetailPageStyle('showcase');
    await StorageService.setDetailTheme('prestige');
    await StorageService.setAppTheme('spotlight');
    await StorageService.setThemeOverrides('{"x":1}');
    await StorageService.setParentsGuideStyle('classic');
    await StorageService.setIptvStyle('console');
    await StorageService.setDiscoverLayout('grid');
    await StorageService.setLaunchAnimation('neon');
    await StorageService.setLaunchIdentPalette('theme');
    await StorageService.setTvSidebarStyle('pill');
    await StorageService.setDesktopSidebarStyle('pill');

    StorageService.resetProfileCaches();

    expect(StorageService.debrifyTvStyleCached, 'grid');
    expect(StorageService.detailPageStyleCached, 'console');
    expect(StorageService.detailThemeCached, 'signal');
    expect(StorageService.appThemeCached, 'legacy');
    expect(StorageService.themeOverridesCached, '');
    expect(StorageService.parentsGuideStyleCached, 'compass');
    expect(StorageService.iptvStyleCached, 'command');
    expect(StorageService.discoverLayoutCached, 'stage');
    expect(StorageService.launchAnimationCached, 'trace');
    expect(StorageService.launchIdentPaletteCached, 'ident');
    expect(StorageService.tvSidebarStyleCached, 'ghost');
    expect(StorageService.desktopSidebarStyleCached, 'rail');
    expect(StorageService.sidebarConfigurationCached.isDefault, isTrue);
  });
}
