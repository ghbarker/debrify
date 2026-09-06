import '../profiles/profile_preferences.dart';
import 'home_prefs.dart';

enum AmbientTrailerSurface { homeHero, detail }

class AmbientTrailerPrefs {
  static const ownedKeys = <String>{
    'detail_trailer_audio_enabled',
    'detail_trailer_volume',
  };

  /// Pref key for the ambient-trailer sound pair, resolved per platform.
  /// Resolves to exactly four keys, spelled out here because the returns
  /// below are interpolated and a grep for a literal name would otherwise
  /// find nothing: `home_hero_trailer_audio_enabled`,
  /// `home_hero_trailer_volume`, `detail_trailer_audio_enabled`,
  /// `detail_trailer_volume`. Any future backup allowlist, reset sweep or
  /// migration has to name all four — enumerating one surface silently drops
  /// the other platform's settings.
  /// Each ambient surface owns its own key even though only one of them can
  /// be live on a device: the TV hero/Discover stage keeps the legacy
  /// `home_hero_` pair (renaming would reset every TV install), the non-TV
  /// detail backdrop gets its own. That separation matters because the old
  /// Settings page offered the hero sound rows on EVERY platform — a phone
  /// user could store "sound off" for a hero that never rendered there, and
  /// with one shared key that dead value would now silently mute their detail
  /// backdrop. Per-surface keys make such writes unreadable instead, so
  /// non-TV starts at the defaults its backdrop has always used.
  ///
  /// Now selected by SURFACE rather than by platform. Picking by platform was
  /// sound while a television could only ever have the Home hero; with the
  /// Showcase detail page also playing trailers, a platform pick would have the
  /// detail backdrop silently reading the Home hero's sound and volume.
  static String _ambientTrailerKeyFor(
    AmbientTrailerSurface surface,
    String suffix,
  ) => switch (surface) {
    AmbientTrailerSurface.homeHero => 'home_hero_trailer_$suffix',
    AmbientTrailerSurface.detail => 'detail_trailer_$suffix',
  };

  /// Whether this platform's ambient trailer plays sound (false = video only).
  /// See [_ambientTrailerKeyFor] for which surface that is. Note the IPTV live
  /// preview is a channel feed, not a trailer, and stays at full volume.
  static Future<bool> getAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      return HomePrefs.getHomeHeroTrailerAudioEnabled();
    }
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_ambientTrailerKeyFor(surface, 'audio_enabled')) ??
        true;
  }

  static Future<void> setAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
    bool enabled,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      await HomePrefs.setHomeHeroTrailerAudioEnabled(enabled);
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _ambientTrailerKeyFor(surface, 'audio_enabled'),
      enabled,
    );
  }

  /// Ambient trailer volume, percent 10–100. Default 70 — audible but under
  /// the UI, and the level the detail backdrop has always run at. Same
  /// one-surface-per-platform scope as [getAmbientTrailerAudioEnabled].
  static Future<int> getAmbientTrailerVolume(
    AmbientTrailerSurface surface,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      return HomePrefs.getHomeHeroTrailerVolume();
    }
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_ambientTrailerKeyFor(surface, 'volume')) ?? 70;
    return v.clamp(10, 100);
  }

  static Future<void> setAmbientTrailerVolume(
    AmbientTrailerSurface surface,
    int percent,
  ) async {
    if (surface == AmbientTrailerSurface.homeHero) {
      await HomePrefs.setHomeHeroTrailerVolume(percent);
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _ambientTrailerKeyFor(surface, 'volume'),
      percent.clamp(10, 100),
    );
  }

}
