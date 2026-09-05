import 'package:debrify/models/sidebar_configuration.dart';
import 'package:debrify/models/tv_hero_artwork_quality.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Write through [StorageService], read through [AppStylePrefs], byte-equal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's24-roundtrip-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
  });

  tearDown(ProfileRuntime.debugReset);

  test(
    'StorageService style writes are readable through AppStylePrefs',
    () async {
      await StorageService.setPhoneNavStyle('floating');
      await StorageService.setPhoneNavBarIndices([2, 4]);
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
      await StorageService.setSidebarConfiguration(
        SidebarConfiguration(
          order: const ['home', 'search'],
          labels: const {'home': 'Start'},
        ),
      );

      expect(await AppStylePrefs.getPhoneNavStyle(), 'floating');
      expect(await AppStylePrefs.getPhoneNavBarIndices(), [2, 4]);
      expect(await AppStylePrefs.getDebrifyTvStyle(), 'spotlight');
      expect(AppStylePrefs.debrifyTvStyleCached, 'spotlight');
      expect(await AppStylePrefs.getDetailPageStyle(), 'showcase');
      expect(await AppStylePrefs.getDetailTheme(), 'prestige');
      expect(await AppStylePrefs.getAppTheme(), 'spotlight');
      expect(await AppStylePrefs.getThemeOverrides(), '{"accent":"#ff00aa"}');
      expect(await AppStylePrefs.getParentsGuideStyle(), 'classic');
      expect(await AppStylePrefs.getIptvStyle(), 'edition');
      expect(await AppStylePrefs.getIptvChannelPreviewEnabled(), isFalse);
      expect(await AppStylePrefs.getPlayerDockStyle(), 'cinema');
      expect(await AppStylePrefs.getPlayerDockPalette(), 'ice');
      expect(await AppStylePrefs.getPlayerDockSize(), 'large');
      expect(await AppStylePrefs.getIptvPlayerGuideStyle(), 'glass');
      expect(await AppStylePrefs.getPlayLoaderStyle(), 'classic');
      expect(await AppStylePrefs.getTvPlayerControlsStyle(), 'ott');
      expect(await AppStylePrefs.getDebrifyTvPlayerStyle(), 'prestige');
      expect(await AppStylePrefs.getDiscoverDefaultSource(), 'trakt');
      expect(await AppStylePrefs.getDiscoverLastSource(), 'simkl');
      expect(await AppStylePrefs.getDiscoverLayout(), 'grid');
      expect(await AppStylePrefs.getLaunchAnimation(), 'horizon');
      expect(await AppStylePrefs.getLaunchIdentPalette(), 'theme');
      expect(await AppStylePrefs.getTextBrightness(), 'dim');
      expect(await AppStylePrefs.getTvSidebarStyle(), 'pill');
      expect(await AppStylePrefs.getDesktopSidebarStyle(), 'pill');
      expect(await AppStylePrefs.getTvUiScalePercent(), 80);
      expect(
        await AppStylePrefs.getTvHeroArtworkQuality(),
        TvHeroArtworkQuality.fullHd,
      );
      expect(
        (await AppStylePrefs.getSidebarConfiguration()).labelForId('home'),
        'Start',
      );
    },
  );

  test('unknown writes coerce the same on both APIs', () async {
    await StorageService.setPlayerDockStyle('ribbon');
    await StorageService.setPlayLoaderStyle('orbit');
    await StorageService.setTvPlayerControlsStyle('holodeck');
    await StorageService.setDebrifyTvPlayerStyle('holodeck');
    await StorageService.setAppTheme('removed');
    await StorageService.setDetailTheme('removed');
    await StorageService.setDetailPageStyle('future-look');

    expect(await AppStylePrefs.getPlayerDockStyle(), 'classic');
    expect(await AppStylePrefs.getPlayLoaderStyle(), 'marquee');
    expect(await AppStylePrefs.getTvPlayerControlsStyle(), 'marquee');
    expect(await AppStylePrefs.getDebrifyTvPlayerStyle(), 'cinema');
    expect(await AppStylePrefs.getAppTheme(), 'legacy');
    expect(await AppStylePrefs.getDetailTheme(), 'signal');
    expect(await AppStylePrefs.getDetailPageStyle(), 'console');
  });

  test('resetProfileCaches and AppStylePrefs.resetCaches stay aligned', () {
    StorageService.debrifyTvStyleCached = 'spotlight';
    StorageService.detailPageStyleCached = 'showcase';
    StorageService.appThemeCached = 'spotlight';
    StorageService.resetProfileCaches();
    expect(AppStylePrefs.debrifyTvStyleCached, 'grid');
    expect(AppStylePrefs.detailPageStyleCached, 'console');
    expect(AppStylePrefs.appThemeCached, 'legacy');
    expect(StorageService.debrifyTvStyleCached, 'grid');
  });
}
