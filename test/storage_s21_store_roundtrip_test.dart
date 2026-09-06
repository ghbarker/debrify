import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import 'package:debrify/services/storage/social_prefs.dart';
import 'package:debrify/services/storage/stremio_tv_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Write through [StorageService], read through the S2-1 stores, byte-equal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's21-roundtrip-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  test(
    'Stremio TV StorageService writes are readable through StremioTvPrefs',
    () async {
      await StorageService.setStremioTvRotationMinutes(30);
      await StorageService.setStremioTvSeriesRotationMinutes(15);
      await StorageService.setStremioTvRandomEpisodes(true);
      await StorageService.setStremioTvAutoRefresh(false);
      await StorageService.setStremioTvHideNowPlaying(true);
      await StorageService.setStremioTvTorrentsFirst(false);
      await StorageService.setStremioTvPreferredQuality('1080p');
      await StorageService.setStremioTvDebridProvider('realdebrid');
      await StorageService.setStremioTvMaxStartPercent(25);
      await StorageService.setStremioTvChannelFavorited('alpha', true);
      await StorageService.setStremioTvLocalCatalogs(const [
        {'id': 'cat-1', 'name': 'Local'},
      ]);
      await StorageService.setStremioTvCatalogRepoUrls(const ['https://r/1']);
      await StorageService.setStremioTvDisabledFilters({'addon:x'});

      expect(await StremioTvPrefs.getStremioTvRotationMinutes(), 30);
      expect(await StremioTvPrefs.getStremioTvSeriesRotationMinutes(), 15);
      expect(await StremioTvPrefs.getStremioTvRandomEpisodes(), isTrue);
      expect(await StremioTvPrefs.getStremioTvAutoRefresh(), isFalse);
      expect(await StremioTvPrefs.getStremioTvHideNowPlaying(), isTrue);
      expect(await StremioTvPrefs.getStremioTvTorrentsFirst(), isFalse);
      expect(await StremioTvPrefs.getStremioTvPreferredQuality(), '1080p');
      expect(await StremioTvPrefs.getStremioTvDebridProvider(), 'realdebrid');
      expect(await StremioTvPrefs.getStremioTvMaxStartPercent(), 25);
      expect(await StremioTvPrefs.isStremioTvChannelFavorited('alpha'), isTrue);
      expect(await StremioTvPrefs.getStremioTvFavoriteChannelIds(), {'alpha'});
      expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), [
        {'id': 'cat-1', 'name': 'Local'},
      ]);
      expect(await StremioTvPrefs.getStremioTvCatalogRepoUrls(), [
        'https://r/1',
      ]);
      expect(await StremioTvPrefs.getStremioTvDisabledFilters(), {'addon:x'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('stremio_tv_rotation_minutes'), 30);
      expect(prefs.getString('stremio_tv_preferred_quality'), '1080p');
      expect(
        prefs.getString('stremio_tv_favorite_channels_v1'),
        jsonEncode({'alpha': true}),
      );
    },
  );

  test(
    'social owner writes preserve the characterized values',
    () async {
      await SocialPrefs.setRedditAccessToken('access-token');
      await SocialPrefs.setRedditRefreshToken('refresh-token');
      await SocialPrefs.setRedditUsername('alice');
      await SocialPrefs.setRedditEnabled(false);
      await SocialPrefs.setRedditHiddenFromNav(true);
      await SocialPrefs.setRedditLastSubreddit('movies');
      await SocialPrefs.setRedditRecentSubreddits(const ['a']);
      await SocialPrefs.setRedditAllowNsfw(true);
      await SocialPrefs.setRedditFavoriteSubreddits(const ['fav']);
      await SocialPrefs.setRedditDefaultSubreddit('all');
      await SocialPrefs.setLemmyInstance('https://lemmy.example');
      await SocialPrefs.setLemmyAllowNsfw(true);
      await SocialPrefs.setLemmyFavoriteCommunities(const ['c/one']);
      await SocialPrefs.setLemmyDefaultCommunity('c/two');
      await SocialPrefs.setYoutubeMaxHeight(720);

      expect(await SocialPrefs.getRedditAccessToken(), 'access-token');
      expect(await SocialPrefs.getRedditRefreshToken(), 'refresh-token');
      expect(await SocialPrefs.getRedditUsername(), 'alice');
      expect(await SocialPrefs.getRedditEnabled(), isFalse);
      expect(await SocialPrefs.getRedditHiddenFromNav(), isTrue);
      expect(await SocialPrefs.getRedditLastSubreddit(), 'movies');
      expect(await SocialPrefs.getRedditRecentSubreddits(), ['a']);
      expect(await SocialPrefs.getRedditAllowNsfw(), isTrue);
      expect(await SocialPrefs.getRedditFavoriteSubreddits(), ['fav']);
      expect(await SocialPrefs.getRedditDefaultSubreddit(), 'all');
      expect(await SocialPrefs.getLemmyInstance(), 'https://lemmy.example');
      expect(await SocialPrefs.getLemmyAllowNsfw(), isTrue);
      expect(await SocialPrefs.getLemmyFavoriteCommunities(), ['c/one']);
      expect(await SocialPrefs.getLemmyDefaultCommunity(), 'c/two');
      expect(await SocialPrefs.getYoutubeMaxHeight(), 720);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('reddit_access_token'),
        startsWith(SecretVault.prefix),
      );
      expect(prefs.getString('reddit_username'), 'alice');
      expect(prefs.getString('lemmy_instance'), 'https://lemmy.example');
      expect(prefs.getInt('youtube_max_height'), 720);
    },
  );

  test(
    'Debrify TV StorageService writes are readable through DebrifyTvPrefs',
    () async {
      await StorageService.saveDebrifyTvProvider('torbox');
      await StorageService.saveDebrifyTvStartRandom(false);
      await StorageService.saveDebrifyTvRandomStartPercent(40);
      await StorageService.saveDebrifyTvHideSeekbar(false);
      await StorageService.saveDebrifyTvShowChannelName(false);
      await StorageService.saveDebrifyTvShowVideoTitle(false);
      await StorageService.saveDebrifyTvHideOptions(false);
      await StorageService.saveDebrifyTvHideBackButton(false);
      await StorageService.saveDebrifyTvAvoidNsfw(false);
      await StorageService.saveDebrifyTvChannels(const [
        {'id': 'ch1', 'name': 'One'},
      ]);
      await StorageService.setDebrifyTvFilterQualities(const ['1080p']);
      await StorageService.setDebrifyTvFilterSizes(const ['2GB-5GB']);
      await StorageService.setDebrifyTvExternalNoticeDismissed(true);
      await StorageService.setDebrifyTvChannelFavorited('fav', true);

      expect(await DebrifyTvPrefs.getDebrifyTvProvider(), 'torbox');
      expect(await DebrifyTvPrefs.hasDebrifyTvProvider(), isTrue);
      expect(await DebrifyTvPrefs.getDebrifyTvStartRandom(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvRandomStartPercent(), 40);
      expect(await DebrifyTvPrefs.getDebrifyTvHideSeekbar(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvShowChannelName(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvShowVideoTitle(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvHideOptions(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvHideBackButton(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvAvoidNsfw(), isFalse);
      expect(await DebrifyTvPrefs.getDebrifyTvChannels(), [
        {'id': 'ch1', 'name': 'One'},
      ]);
      expect(await DebrifyTvPrefs.getDebrifyTvFilterQualities(), ['1080p']);
      expect(await DebrifyTvPrefs.getDebrifyTvFilterSizes(), ['2GB-5GB']);
      expect(
        await DebrifyTvPrefs.getDebrifyTvExternalNoticeDismissed(),
        isTrue,
      );
      expect(await DebrifyTvPrefs.isDebrifyTvChannelFavorited('fav'), isTrue);
      expect(await DebrifyTvPrefs.getDebrifyTvFavoriteChannelIds(), {'fav'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debrify_tv_provider'), 'torbox');
      expect(prefs.getBool('debrify_tv_show_watermark'), isFalse);
      expect(prefs.getInt('debrify_tv_random_start_percent'), 40);
      expect(
        prefs.getString('debrify_tv_favorite_channels_v1'),
        jsonEncode({'fav': true}),
      );
    },
  );
}
