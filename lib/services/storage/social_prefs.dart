import '../profiles/profile_policy_guard.dart';
import '../profiles/profile_credential_facade.dart';
import '../profiles/profile_preferences.dart';
import '../secret_vault.dart';

/// Reddit, Lemmy, and YouTube prefs.
///
/// [StorageService] forwards to this store. Key names and encodings are
/// frozen; do not rename a persisted string.
class SocialPrefs {
  SocialPrefs._();

  // Reddit settings
  static const String _redditAccessTokenKey = 'reddit_access_token';
  static const String _redditRefreshTokenKey = 'reddit_refresh_token';
  static const String _redditUsernameKey = 'reddit_username';
  static const String _redditEnabledKey = 'reddit_enabled';
  static const String _redditHiddenFromNavKey = 'reddit_hidden_from_nav';
  static const String _redditLastSubredditKey = 'reddit_last_subreddit';
  static const String _redditRecentSubredditsKey = 'reddit_recent_subreddits';
  static const String _redditAllowNsfwKey = 'reddit_allow_nsfw';
  static const String _redditFavoriteSubredditsKey =
      'reddit_favorite_subreddits';
  static const String _redditDefaultSubredditKey = 'reddit_default_subreddit';
  // Lemmy settings
  static const String _lemmyInstanceKey = 'lemmy_instance';
  static const String _lemmyAllowNsfwKey = 'lemmy_allow_nsfw';
  static const String _lemmyFavoriteCommunitiesKey =
      'lemmy_favorite_communities';
  static const String _lemmyDefaultCommunityKey = 'lemmy_default_community';
  // YouTube settings
  static const String _youtubeMaxHeightKey = 'youtube_max_height';

  /// Declared persisted names.
  static const Set<String> ownedKeys = {
    _redditAccessTokenKey,
    _redditRefreshTokenKey,
    _redditUsernameKey,
    _redditEnabledKey,
    _redditHiddenFromNavKey,
    _redditLastSubredditKey,
    _redditRecentSubredditsKey,
    _redditAllowNsfwKey,
    _redditFavoriteSubredditsKey,
    _redditDefaultSubredditKey,
    _lemmyInstanceKey,
    _lemmyAllowNsfwKey,
    _lemmyFavoriteCommunitiesKey,
    _lemmyDefaultCommunityKey,
    _youtubeMaxHeightKey,
  };

  static Future<bool> _profileAllowsAdultContent() =>
      ProfilePolicyGuard.allowsAdultContentForPreferences();

  // Reddit Settings
  static Future<String?> getRedditAccessToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _redditAccessTokenKey);
  }

  static Future<void> setRedditAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _redditAccessTokenKey, token);
  }

  static Future<String?> getRedditRefreshToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _redditRefreshTokenKey);
  }

  static Future<void> setRedditRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _redditRefreshTokenKey, token);
  }

  static Future<String?> getRedditUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditUsernameKey);
  }

  static Future<void> setRedditUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_redditUsernameKey, username);
  }

  static Future<bool> getRedditEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditEnabledKey) ?? true; // Default enabled
  }

  static Future<void> setRedditEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_redditEnabledKey, value);
  }

  static Future<bool> getRedditHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditHiddenFromNavKey) ?? false;
  }

  static Future<void> setRedditHiddenFromNav(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_redditHiddenFromNavKey, value);
  }

  static Future<String?> getRedditLastSubreddit() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditLastSubredditKey);
  }

  static Future<void> setRedditLastSubreddit(String subreddit) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_redditLastSubredditKey, subreddit);
  }

  static Future<void> clearRedditAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_redditAccessTokenKey)) {
      await prefs.remove(_redditAccessTokenKey);
      await prefs.remove(_redditRefreshTokenKey);
    }
    await prefs.remove(_redditUsernameKey);
  }

  static Future<List<String>> getRedditRecentSubreddits() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_redditRecentSubredditsKey) ?? [];
  }

  static Future<void> setRedditRecentSubreddits(List<String> subreddits) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_redditRecentSubredditsKey, subreddits);
  }

  static Future<bool> getRedditAllowNsfw() async {
    if (!await _profileAllowsAdultContent()) return false;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditAllowNsfwKey) ?? false;
  }

  static Future<void> setRedditAllowNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _redditAllowNsfwKey,
      await _profileAllowsAdultContent() && value,
    );
  }

  static Future<List<String>> getRedditFavoriteSubreddits() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_redditFavoriteSubredditsKey) ?? [];
  }

  static Future<void> setRedditFavoriteSubreddits(
    List<String> subreddits,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_redditFavoriteSubredditsKey, subreddits);
  }

  static Future<String?> getRedditDefaultSubreddit() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditDefaultSubredditKey);
  }

  static Future<void> setRedditDefaultSubreddit(String? subreddit) async {
    final prefs = await ProfilePreferences.instance();
    if (subreddit == null || subreddit.isEmpty) {
      await prefs.remove(_redditDefaultSubredditKey);
    } else {
      await prefs.setString(_redditDefaultSubredditKey, subreddit);
    }
  }

  // Lemmy Settings
  static Future<String> getLemmyInstance() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_lemmyInstanceKey);
    return (value != null && value.isNotEmpty) ? value : 'https://lemmy.world';
  }

  static Future<void> setLemmyInstance(String instance) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_lemmyInstanceKey, instance);
  }

  static Future<bool> getLemmyAllowNsfw() async {
    if (!await _profileAllowsAdultContent()) return false;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_lemmyAllowNsfwKey) ?? false;
  }

  static Future<void> setLemmyAllowNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _lemmyAllowNsfwKey,
      await _profileAllowsAdultContent() && value,
    );
  }

  static Future<List<String>> getLemmyFavoriteCommunities() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_lemmyFavoriteCommunitiesKey) ?? [];
  }

  static Future<void> setLemmyFavoriteCommunities(
    List<String> communities,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_lemmyFavoriteCommunitiesKey, communities);
  }

  static Future<String?> getLemmyDefaultCommunity() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_lemmyDefaultCommunityKey);
  }

  static Future<void> setLemmyDefaultCommunity(String? community) async {
    final prefs = await ProfilePreferences.instance();
    if (community == null || community.isEmpty) {
      await prefs.remove(_lemmyDefaultCommunityKey);
    } else {
      await prefs.setString(_lemmyDefaultCommunityKey, community);
    }
  }

  // YouTube Settings
  /// Preferred max playback height for YouTube (1080/720/480/360). Default 1080.
  static Future<int> getYoutubeMaxHeight() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_youtubeMaxHeightKey);
    return (v != null && v > 0) ? v : 1080;
  }

  static Future<void> setYoutubeMaxHeight(int height) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_youtubeMaxHeightKey, height);
  }
}
