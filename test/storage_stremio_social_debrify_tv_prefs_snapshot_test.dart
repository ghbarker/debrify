import 'package:debrify/services/storage/stremio_tv_prefs.dart';
import 'package:debrify/services/storage/social_prefs.dart';
import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins Stremio TV, social (reddit/lemmy/youtube), and Debrify TV encodings
/// on [StorageService] before the S2-1 store extract. Key names and values
/// are a frozen compatibility surface. This file must not import the new
/// stores — those land in the move commit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's21-pin-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  group('Stremio TV prefs', () {
    test('defaults when no keys are stored', () async {
      expect(await StremioTvPrefs.getStremioTvRotationMinutes(), 90);
      expect(await StremioTvPrefs.getStremioTvSeriesRotationMinutes(), 45);
      expect(await StremioTvPrefs.getStremioTvRandomEpisodes(), isFalse);
      expect(await StremioTvPrefs.getStremioTvAutoRefresh(), isTrue);
      expect(await StremioTvPrefs.getStremioTvHideNowPlaying(), isFalse);
      expect(await StremioTvPrefs.getStremioTvTorrentsFirst(), isTrue);
      expect(await StremioTvPrefs.getStremioTvPreferredQuality(), 'auto');
      expect(await StremioTvPrefs.getStremioTvDebridProvider(), 'auto');
      expect(await StremioTvPrefs.getStremioTvMaxStartPercent(), -1);
      expect(await StremioTvPrefs.isStremioTvChannelFavorited('ch1'), isFalse);
      expect(await StremioTvPrefs.getStremioTvFavoriteChannelIds(), isEmpty);
      expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), isEmpty);
      expect(await StremioTvPrefs.getStremioTvCatalogRepoUrls(), isEmpty);
      expect(await StremioTvPrefs.getStremioTvDisabledFilters(), isEmpty);
    });

    test('StorageService writes the historical Stremio TV key bytes', () async {
      await StremioTvPrefs.setStremioTvRotationMinutes(30);
      await StremioTvPrefs.setStremioTvSeriesRotationMinutes(15);
      await StremioTvPrefs.setStremioTvRandomEpisodes(true);
      await StremioTvPrefs.setStremioTvAutoRefresh(false);
      await StremioTvPrefs.setStremioTvHideNowPlaying(true);
      await StremioTvPrefs.setStremioTvTorrentsFirst(false);
      await StremioTvPrefs.setStremioTvPreferredQuality('1080p');
      await StremioTvPrefs.setStremioTvDebridProvider('realdebrid');
      await StremioTvPrefs.setStremioTvMaxStartPercent(25);
      await StremioTvPrefs.setStremioTvChannelFavorited('alpha', true);
      await StremioTvPrefs.setStremioTvChannelFavorited('beta', true);
      await StremioTvPrefs.setStremioTvLocalCatalogs(const [
        {'id': 'cat-1', 'name': 'Local'},
      ]);
      await StremioTvPrefs.setStremioTvCatalogRepoUrls(const [
        'https://repo.example/catalogs.json',
      ]);
      await StremioTvPrefs.setStremioTvDisabledFilters({'addon:x', 'genre:y'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('stremio_tv_rotation_minutes'), 30);
      expect(prefs.getInt('stremio_tv_series_rotation_minutes'), 15);
      expect(prefs.getBool('stremio_tv_random_episodes'), isTrue);
      expect(prefs.getBool('stremio_tv_auto_refresh'), isFalse);
      expect(prefs.getBool('stremio_tv_hide_now_playing'), isTrue);
      expect(prefs.getBool('stremio_tv_torrents_first'), isFalse);
      expect(prefs.getString('stremio_tv_preferred_quality'), '1080p');
      expect(prefs.getString('stremio_tv_debrid_provider'), 'realdebrid');
      expect(prefs.getInt('stremio_tv_max_start_percent'), 25);
      expect(
        prefs.getString('stremio_tv_favorite_channels_v1'),
        jsonEncode({'alpha': true, 'beta': true}),
      );
      expect(
        prefs.getString('stremio_tv_local_catalogs_v1'),
        jsonEncode([
          {'id': 'cat-1', 'name': 'Local'},
        ]),
      );
      expect(prefs.getStringList('stremio_tv_catalog_repo_urls_v1'), [
        'https://repo.example/catalogs.json',
      ]);
      expect(
        prefs.getString('stremio_tv_disabled_channel_filters_v1'),
        jsonEncode(['addon:x', 'genre:y']),
      );
    });

    test(
      'raw Stremio TV bytes round-trip through StorageService getters',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'stremio_tv_rotation_minutes': 12,
          'stremio_tv_series_rotation_minutes': 8,
          'stremio_tv_random_episodes': true,
          'stremio_tv_auto_refresh': false,
          'stremio_tv_hide_now_playing': true,
          'stremio_tv_torrents_first': false,
          'stremio_tv_preferred_quality': '2160p',
          'stremio_tv_debrid_provider': 'torbox',
          'stremio_tv_max_start_percent': 0,
          'stremio_tv_favorite_channels_v1': jsonEncode({'fav': true}),
          'stremio_tv_local_catalogs_v1': jsonEncode([
            {'id': 'c', 'title': 'T'},
          ]),
          'stremio_tv_catalog_repo_urls_v1': <String>['https://a/b'],
          'stremio_tv_disabled_channel_filters_v1': jsonEncode(['addon:z']),
        });

        expect(await StremioTvPrefs.getStremioTvRotationMinutes(), 12);
        expect(await StremioTvPrefs.getStremioTvSeriesRotationMinutes(), 8);
        expect(await StremioTvPrefs.getStremioTvRandomEpisodes(), isTrue);
        expect(await StremioTvPrefs.getStremioTvAutoRefresh(), isFalse);
        expect(await StremioTvPrefs.getStremioTvHideNowPlaying(), isTrue);
        expect(await StremioTvPrefs.getStremioTvTorrentsFirst(), isFalse);
        expect(await StremioTvPrefs.getStremioTvPreferredQuality(), '2160p');
        expect(await StremioTvPrefs.getStremioTvDebridProvider(), 'torbox');
        expect(await StremioTvPrefs.getStremioTvMaxStartPercent(), 0);
        expect(await StremioTvPrefs.isStremioTvChannelFavorited('fav'), isTrue);
        expect(await StremioTvPrefs.getStremioTvFavoriteChannelIds(), {'fav'});
        expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), [
          {'id': 'c', 'title': 'T'},
        ]);
        expect(await StremioTvPrefs.getStremioTvCatalogRepoUrls(), [
          'https://a/b',
        ]);
        expect(await StremioTvPrefs.getStremioTvDisabledFilters(), {'addon:z'});
      },
    );

    test(
      'empty local catalogs and disabled filters remove their keys',
      () async {
        await StremioTvPrefs.setStremioTvLocalCatalogs(const [
          {'id': 'keep', 'name': 'K'},
        ]);
        await StremioTvPrefs.setStremioTvDisabledFilters({'addon:x'});

        await StremioTvPrefs.setStremioTvLocalCatalogs(const []);
        await StremioTvPrefs.setStremioTvDisabledFilters({});

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('stremio_tv_local_catalogs_v1'), isFalse);
        expect(
          prefs.containsKey('stremio_tv_disabled_channel_filters_v1'),
          isFalse,
        );
      },
    );

    test('local catalog add/update/remove quirks', () async {
      expect(
        await StremioTvPrefs.addStremioTvLocalCatalog({'name': 'no id'}),
        isFalse,
      );
      expect(
        await StremioTvPrefs.addStremioTvLocalCatalog({
          'id': 'a',
          'name': 'One',
        }),
        isTrue,
      );
      expect(
        await StremioTvPrefs.addStremioTvLocalCatalog({
          'id': 'a',
          'name': 'Dup',
        }),
        isFalse,
      );
      expect(
        await StremioTvPrefs.updateStremioTvLocalCatalog({'name': 'no id'}),
        isFalse,
      );
      expect(
        await StremioTvPrefs.updateStremioTvLocalCatalog({
          'id': 'missing',
          'name': 'Nope',
        }),
        isFalse,
      );
      expect(
        await StremioTvPrefs.updateStremioTvLocalCatalog({
          'id': 'a',
          'name': 'Renamed',
        }),
        isTrue,
      );
      expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), [
        {'id': 'a', 'name': 'Renamed'},
      ]);
      await StremioTvPrefs.removeStremioTvLocalCatalog('a');
      expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), isEmpty);
    });

    test('catalog repo URL add is idempotent; remove is silent', () async {
      expect(
        await StremioTvPrefs.addStremioTvCatalogRepoUrl('https://r/1'),
        isTrue,
      );
      expect(
        await StremioTvPrefs.addStremioTvCatalogRepoUrl('https://r/1'),
        isFalse,
      );
      await StremioTvPrefs.removeStremioTvCatalogRepoUrl('https://r/missing');
      expect(await StremioTvPrefs.getStremioTvCatalogRepoUrls(), [
        'https://r/1',
      ]);
      await StremioTvPrefs.removeStremioTvCatalogRepoUrl('https://r/1');
      expect(await StremioTvPrefs.getStremioTvCatalogRepoUrls(), isEmpty);
    });

    test(
      'unfavorite removes the id; corrupt favorites read as empty',
      () async {
        await StremioTvPrefs.setStremioTvChannelFavorited('keep', true);
        await StremioTvPrefs.setStremioTvChannelFavorited('drop', true);
        await StremioTvPrefs.setStremioTvChannelFavorited('drop', false);
        expect(await StremioTvPrefs.getStremioTvFavoriteChannelIds(), {'keep'});

        SharedPreferences.setMockInitialValues(<String, Object>{
          'stremio_tv_favorite_channels_v1': 'not-json{',
          'stremio_tv_local_catalogs_v1': 'not-json{',
          'stremio_tv_disabled_channel_filters_v1': 'not-json{',
        });
        expect(
          await StremioTvPrefs.isStremioTvChannelFavorited('keep'),
          isFalse,
        );
        expect(await StremioTvPrefs.getStremioTvFavoriteChannelIds(), isEmpty);
        expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), isEmpty);
        expect(await StremioTvPrefs.getStremioTvDisabledFilters(), isEmpty);
      },
    );

    test(
      'local catalogs drop entries that are not Map<String, dynamic>',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'stremio_tv_local_catalogs_v1': jsonEncode([
            {'id': 'ok', 'name': 'Keep'},
            'bare',
            4,
          ]),
        });
        expect(await StremioTvPrefs.getStremioTvLocalCatalogs(), [
          {'id': 'ok', 'name': 'Keep'},
        ]);
      },
    );
  });

  group('Social prefs (reddit / lemmy / youtube)', () {
    test('defaults when no keys are stored', () async {
      expect(await SocialPrefs.getRedditAccessToken(), isNull);
      expect(await SocialPrefs.getRedditRefreshToken(), isNull);
      expect(await SocialPrefs.getRedditUsername(), isNull);
      expect(await SocialPrefs.getRedditEnabled(), isTrue);
      expect(await SocialPrefs.getRedditHiddenFromNav(), isFalse);
      expect(await SocialPrefs.getRedditLastSubreddit(), isNull);
      expect(await SocialPrefs.getRedditRecentSubreddits(), isEmpty);
      expect(await SocialPrefs.getRedditAllowNsfw(), isFalse);
      expect(await SocialPrefs.getRedditFavoriteSubreddits(), isEmpty);
      expect(await SocialPrefs.getRedditDefaultSubreddit(), isNull);
      expect(await SocialPrefs.getLemmyInstance(), 'https://lemmy.world');
      expect(await SocialPrefs.getLemmyAllowNsfw(), isFalse);
      expect(await SocialPrefs.getLemmyFavoriteCommunities(), isEmpty);
      expect(await SocialPrefs.getLemmyDefaultCommunity(), isNull);
      expect(await SocialPrefs.getYoutubeMaxHeight(), 1080);
    });

    test('StorageService writes the historical social key bytes', () async {
      await SocialPrefs.setRedditAccessToken('access-token');
      await SocialPrefs.setRedditRefreshToken('refresh-token');
      await SocialPrefs.setRedditUsername('alice');
      await SocialPrefs.setRedditEnabled(false);
      await SocialPrefs.setRedditHiddenFromNav(true);
      await SocialPrefs.setRedditLastSubreddit('movies');
      await SocialPrefs.setRedditRecentSubreddits(const ['a', 'b']);
      await SocialPrefs.setRedditAllowNsfw(true);
      await SocialPrefs.setRedditFavoriteSubreddits(const ['fav']);
      await SocialPrefs.setRedditDefaultSubreddit('all');
      await SocialPrefs.setLemmyInstance('https://lemmy.example');
      await SocialPrefs.setLemmyAllowNsfw(true);
      await SocialPrefs.setLemmyFavoriteCommunities(const ['c/one']);
      await SocialPrefs.setLemmyDefaultCommunity('c/two');
      await SocialPrefs.setYoutubeMaxHeight(720);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('reddit_access_token'),
        startsWith(SecretVault.prefix),
      );
      expect(
        prefs.getString('reddit_refresh_token'),
        startsWith(SecretVault.prefix),
      );
      expect(prefs.getString('reddit_username'), 'alice');
      expect(prefs.getBool('reddit_enabled'), isFalse);
      expect(prefs.getBool('reddit_hidden_from_nav'), isTrue);
      expect(prefs.getString('reddit_last_subreddit'), 'movies');
      expect(prefs.getStringList('reddit_recent_subreddits'), ['a', 'b']);
      expect(prefs.getBool('reddit_allow_nsfw'), isTrue);
      expect(prefs.getStringList('reddit_favorite_subreddits'), ['fav']);
      expect(prefs.getString('reddit_default_subreddit'), 'all');
      expect(prefs.getString('lemmy_instance'), 'https://lemmy.example');
      expect(prefs.getBool('lemmy_allow_nsfw'), isTrue);
      expect(prefs.getStringList('lemmy_favorite_communities'), ['c/one']);
      expect(prefs.getString('lemmy_default_community'), 'c/two');
      expect(prefs.getInt('youtube_max_height'), 720);

      expect(await SocialPrefs.getRedditAccessToken(), 'access-token');
      expect(await SocialPrefs.getRedditRefreshToken(), 'refresh-token');
    });

    test('null/empty default community and subreddit remove the key', () async {
      await SocialPrefs.setRedditDefaultSubreddit('all');
      await SocialPrefs.setLemmyDefaultCommunity('c/one');
      await SocialPrefs.setRedditDefaultSubreddit(null);
      await SocialPrefs.setRedditDefaultSubreddit('');
      await SocialPrefs.setLemmyDefaultCommunity(null);
      await SocialPrefs.setLemmyDefaultCommunity('');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('reddit_default_subreddit'), isFalse);
      expect(prefs.containsKey('lemmy_default_community'), isFalse);
    });

    test(
      'empty lemmy instance reads as lemmy.world; youtube <=0 reads 1080',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'lemmy_instance': '',
          'youtube_max_height': 0,
        });
        expect(await SocialPrefs.getLemmyInstance(), 'https://lemmy.world');
        expect(await SocialPrefs.getYoutubeMaxHeight(), 1080);

        SharedPreferences.setMockInitialValues(<String, Object>{
          'youtube_max_height': -4,
        });
        expect(await SocialPrefs.getYoutubeMaxHeight(), 1080);

        await SocialPrefs.setYoutubeMaxHeight(0);
        final prefs = await SharedPreferences.getInstance();
        // Quirk: setter writes any int; only the getter coerces.
        expect(prefs.getInt('youtube_max_height'), 0);
      },
    );

    test('clearRedditAuth drops username and vault tokens', () async {
      await SocialPrefs.setRedditAccessToken('access-token');
      await SocialPrefs.setRedditRefreshToken('refresh-token');
      await SocialPrefs.setRedditUsername('alice');
      await SocialPrefs.clearRedditAuth();

      expect(await SocialPrefs.getRedditAccessToken(), isNull);
      expect(await SocialPrefs.getRedditRefreshToken(), isNull);
      expect(await SocialPrefs.getRedditUsername(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('reddit_username'), isFalse);
    });

    test('NSFW setters write the requested bool in legacy mode', () async {
      await SocialPrefs.setRedditAllowNsfw(true);
      await SocialPrefs.setLemmyAllowNsfw(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reddit_allow_nsfw'), isTrue);
      expect(prefs.getBool('lemmy_allow_nsfw'), isTrue);
      expect(await SocialPrefs.getRedditAllowNsfw(), isTrue);
      expect(await SocialPrefs.getLemmyAllowNsfw(), isTrue);
    });
  });

  group('Debrify TV prefs', () {
    test('defaults when no keys are stored', () async {
      expect(await StorageService.getDebrifyTvProvider(), 'real_debrid');
      expect(await StorageService.hasDebrifyTvProvider(), isFalse);
      expect(await StorageService.getDebrifyTvStartRandom(), isTrue);
      expect(await StorageService.getDebrifyTvRandomStartPercent(), 20);
      expect(await StorageService.getDebrifyTvHideSeekbar(), isTrue);
      expect(await StorageService.getDebrifyTvShowChannelName(), isTrue);
      expect(await StorageService.getDebrifyTvShowVideoTitle(), isTrue);
      expect(await StorageService.getDebrifyTvHideOptions(), isTrue);
      expect(await StorageService.getDebrifyTvHideBackButton(), isTrue);
      expect(await StorageService.getDebrifyTvAvoidNsfw(), isTrue);
      expect(await StorageService.getDebrifyTvChannels(), isEmpty);
      expect(await StorageService.getDebrifyTvFilterQualities(), isEmpty);
      expect(await StorageService.getDebrifyTvFilterSizes(), isEmpty);
      expect(
        await StorageService.getDebrifyTvExternalNoticeDismissed(),
        isFalse,
      );
      expect(await StorageService.isDebrifyTvChannelFavorited('ch1'), isFalse);
      expect(await StorageService.getDebrifyTvFavoriteChannelIds(), isEmpty);
    });

    test('StorageService writes the historical Debrify TV key bytes', () async {
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

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debrify_tv_provider'), 'torbox');
      expect(prefs.getBool('debrify_tv_start_random'), isFalse);
      expect(prefs.getInt('debrify_tv_random_start_percent'), 40);
      expect(prefs.getBool('debrify_tv_hide_seekbar'), isFalse);
      // Quirk: show-channel-name is persisted as debrify_tv_show_watermark.
      expect(prefs.getBool('debrify_tv_show_watermark'), isFalse);
      expect(prefs.getBool('debrify_tv_show_video_title'), isFalse);
      expect(prefs.getBool('debrify_tv_hide_options'), isFalse);
      expect(prefs.getBool('debrify_tv_hide_back_button'), isFalse);
      expect(prefs.getBool('debrify_tv_avoid_nsfw'), isFalse);
      expect(
        prefs.getString('debrify_tv_channels'),
        jsonEncode([
          {'id': 'ch1', 'name': 'One'},
        ]),
      );
      expect(
        prefs.getString('debrify_tv_filter_qualities'),
        jsonEncode(['1080p']),
      );
      expect(
        prefs.getString('debrify_tv_filter_sizes'),
        jsonEncode(['2GB-5GB']),
      );
      expect(prefs.getBool('debrify_tv_external_notice_dismissed'), isTrue);
      expect(
        prefs.getString('debrify_tv_favorite_channels_v1'),
        jsonEncode({'fav': true}),
      );
      expect(await StorageService.hasDebrifyTvProvider(), isTrue);
    });

    test(
      'random start percent clamps to 10–90; null stored reads 20',
      () async {
        await StorageService.saveDebrifyTvRandomStartPercent(1);
        expect(await StorageService.getDebrifyTvRandomStartPercent(), 10);
        await StorageService.saveDebrifyTvRandomStartPercent(99);
        expect(await StorageService.getDebrifyTvRandomStartPercent(), 90);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('debrify_tv_random_start_percent'), 90);
      },
    );

    test('channels skip non-maps; corrupt JSON reads as empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'debrify_tv_channels': jsonEncode([
          {'id': 'ok'},
          'bare',
          3,
          {'id': 'two'},
        ]),
      });
      expect(await StorageService.getDebrifyTvChannels(), [
        {'id': 'ok'},
        {'id': 'two'},
      ]);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'debrify_tv_channels': 'not-json{',
        'debrify_tv_favorite_channels_v1': 'not-json{',
      });
      expect(await StorageService.getDebrifyTvChannels(), isEmpty);
      expect(await StorageService.isDebrifyTvChannelFavorited('x'), isFalse);
      expect(await StorageService.getDebrifyTvFavoriteChannelIds(), isEmpty);
    });

    test('filter getters throw on corrupt JSON (no try/catch)', () async {
      await StorageService.setDebrifyTvFilterQualities(const ['1080p']);
      await StorageService.setDebrifyTvFilterSizes(const ['1GB']);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('debrify_tv_filter_qualities', 'not-json{');
      await prefs.setString('debrify_tv_filter_sizes', 'not-json{');
      expect(
        StorageService.getDebrifyTvFilterQualities(),
        throwsFormatException,
      );
      expect(StorageService.getDebrifyTvFilterSizes(), throwsFormatException);
    });

    test(
      'clearDebrifyTvProviderAndLegacy only drops provider + channels',
      () async {
        await StorageService.saveDebrifyTvProvider('torbox');
        await StorageService.saveDebrifyTvChannels(const [
          {'id': 'ch1'},
        ]);
        await StorageService.saveDebrifyTvStartRandom(false);
        await StorageService.setDebrifyTvChannelFavorited('fav', true);

        await StorageService.clearDebrifyTvProviderAndLegacy();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('debrify_tv_provider'), isFalse);
        expect(prefs.containsKey('debrify_tv_channels'), isFalse);
        expect(prefs.getBool('debrify_tv_start_random'), isFalse);
        expect(prefs.getString('debrify_tv_favorite_channels_v1'), isNotNull);
      },
    );

    test(
      'clearAllDebrifyTvSettings wipes display/filters/prefixes, not provider',
      () async {
        await StorageService.saveDebrifyTvProvider('torbox');
        await StorageService.saveDebrifyTvStartRandom(false);
        await StorageService.saveDebrifyTvHideSeekbar(false);
        await StorageService.saveDebrifyTvShowChannelName(false);
        await StorageService.saveDebrifyTvShowVideoTitle(false);
        await StorageService.saveDebrifyTvHideOptions(false);
        await StorageService.saveDebrifyTvHideBackButton(false);
        await StorageService.saveDebrifyTvAvoidNsfw(false);
        await StorageService.saveDebrifyTvRandomStartPercent(40);
        await StorageService.setDebrifyTvFilterQualities(const ['720p']);
        await StorageService.setDebrifyTvFilterSizes(const ['1GB']);
        await StorageService.setDebrifyTvExternalNoticeDismissed(true);
        await StorageService.setDebrifyTvChannelFavorited('fav', true);
        await StorageService.saveDebrifyTvChannels(const [
          {'id': 'ch1'},
        ]);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('engine_tv_foo_bar', true);
        await prefs.setBool('debrify_tv_use_torbox', true);
        await prefs.setInt('debrify_tv_channel_small_x', 1);
        await prefs.setInt('debrify_tv_channel_large_x', 2);
        await prefs.setBool('debrify_tv_quick_play_x', true);
        await prefs.setInt('debrify_tv_keyword_threshold', 3);
        await prefs.setInt('debrify_tv_min_torrents_per_keyword', 4);
        await prefs.setBool('engine_yts_enabled', true);

        await StorageService.clearAllDebrifyTvSettings();

        expect(prefs.containsKey('debrify_tv_start_random'), isFalse);
        expect(prefs.containsKey('debrify_tv_hide_seekbar'), isFalse);
        expect(prefs.containsKey('debrify_tv_show_watermark'), isFalse);
        expect(prefs.containsKey('debrify_tv_show_video_title'), isFalse);
        expect(prefs.containsKey('debrify_tv_hide_options'), isFalse);
        expect(prefs.containsKey('debrify_tv_hide_back_button'), isFalse);
        expect(prefs.containsKey('debrify_tv_avoid_nsfw'), isFalse);
        expect(prefs.containsKey('debrify_tv_random_start_percent'), isFalse);
        expect(prefs.containsKey('debrify_tv_filter_qualities'), isFalse);
        expect(prefs.containsKey('debrify_tv_filter_sizes'), isFalse);
        expect(prefs.containsKey('engine_tv_foo_bar'), isFalse);
        expect(prefs.containsKey('debrify_tv_use_torbox'), isFalse);
        expect(prefs.containsKey('debrify_tv_channel_small_x'), isFalse);
        expect(prefs.containsKey('debrify_tv_channel_large_x'), isFalse);
        expect(prefs.containsKey('debrify_tv_quick_play_x'), isFalse);
        expect(prefs.containsKey('debrify_tv_keyword_threshold'), isFalse);
        expect(
          prefs.containsKey('debrify_tv_min_torrents_per_keyword'),
          isFalse,
        );
        // Quirk: provider, channels, favorites, external notice stay.
        expect(prefs.getString('debrify_tv_provider'), 'torbox');
        expect(prefs.getString('debrify_tv_channels'), isNotNull);
        expect(prefs.getString('debrify_tv_favorite_channels_v1'), isNotNull);
        expect(prefs.getBool('debrify_tv_external_notice_dismissed'), isTrue);
        // Non-TV engine_* keys are a different clearer.
        expect(prefs.getBool('engine_yts_enabled'), isTrue);
      },
    );

    test(
      'avoid-NSFW setter writes the requested bool in legacy mode',
      () async {
        await StorageService.saveDebrifyTvAvoidNsfw(false);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('debrify_tv_avoid_nsfw'), isFalse);
        expect(await StorageService.getDebrifyTvAvoidNsfw(), isFalse);
      },
    );
  });
}
