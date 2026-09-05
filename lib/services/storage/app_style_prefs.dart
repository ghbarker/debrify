import '../../models/sidebar_configuration.dart';
import '../../models/tv_hero_artwork_quality.dart';
import '../../utils/platform_util.dart';
import '../profiles/profile_preferences.dart';

/// Sync style caches (looks, docks, chrome, launch ident). [StorageService]
/// forwards to this store.
///
/// Key names and encodings are frozen; do not rename a persisted string.
/// Comments that name native `ProfilePreferenceProjection` readers are a
/// compatibility surface — keep them next to the getter they document.
class AppStylePrefs {
  AppStylePrefs._();

  static const Set<String> ownedKeys = {
    _phoneNavStyleKey,
    _phoneNavBarIndicesKey,
    debrifyTvStyleKey,
    detailPageStyleKey,
    detailThemeKey,
    appThemeKey,
    _themeOverridesKey,
    _parentsGuideStyleKey,
    _iptvStyleKey,
    _iptvChannelPreviewEnabledKey,
    _playerDockStyleKey,
    _playerDockPaletteKey,
    _playerDockSizeKey,
    _iptvPlayerGuideStyleKey,
    _playLoaderStyleKey,
    _tvPlayerControlsStyleKey,
    _debrifyTvPlayerStyleKey,
    _discoverLayoutKey,
    _discoverDefaultSourceKey,
    _discoverLastSourceKey,
    _launchAnimationKey,
    _launchIdentPaletteKey,
    _textBrightnessKey,
    tvSidebarStyleKey,
    desktopSidebarStyleKey,
    _sidebarConfigurationKey,
    _tvUiScalePercentKey,
    _tvHeroArtworkQualityKey,
  };

  /// Resets synchronous mirrors before a profile activation is published.
  static void resetCaches() {
    debrifyTvStyleCached = 'grid';
    detailPageStyleCached = kDetailPageStyleDefault;
    detailThemeCached = 'signal';
    appThemeCached = 'legacy';
    themeOverridesCached = '';
    parentsGuideStyleCached = 'compass';
    iptvStyleCached = 'command';
    discoverLayoutCached = 'stage';
    launchAnimationCached = 'trace';
    launchIdentPaletteCached = 'ident';
    tvSidebarStyleCached = 'ghost';
    desktopSidebarStyleCached = 'rail';
    sidebarConfigurationCached = SidebarConfiguration.defaults();
  }

  /// Android TV screen size, as a percentage of the panel's native density.
  ///
  /// A 1080p TV at density 320 gives Flutter a 960x540 logical canvas, so
  /// every screen is drawn 2x and reads as "zoomed in" across a big panel.
  /// A value below 100 makes MainActivity report a proportionally smaller
  /// devicePixelRatio to the engine, which widens the logical canvas (80% ->
  /// 1200x675) so the same layouts fit more and draw smaller — no per-screen
  /// changes involved.
  ///
  /// Read natively from `flutter.tv_ui_scale_percent` BEFORE the Flutter
  /// engine is built, so a change only takes effect on the next cold start.
  /// Android TV only; ignored everywhere else.
  ///
  /// [kTvUiScaleDefault] is 90: at 100 the app reads noticeably larger than
  /// the TV apps people compare it to (Stremio's web-rendered UI lays out
  /// against a canvas far closer to 1920 than to 960), while 80 ran a touch
  /// small for the Canvas-era layouts — Medium is the out-of-the-box balance
  /// and both neighbours are one tap away. MUST stay in step with
  /// MainActivity's `computeUiScale` fallback.
  static const String _tvUiScalePercentKey = 'tv_ui_scale_percent';

  static const List<int> kTvUiScaleOptions = [100, 90, 80];
  static const int kTvUiScaleDefault = 90;

  static Future<int> getTvUiScalePercent() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getInt(_tvUiScalePercentKey);
    return kTvUiScaleOptions.contains(stored) ? stored! : kTvUiScaleDefault;
  }

  static Future<void> setTvUiScalePercent(int percent) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_tvUiScalePercentKey, percent);
  }

  static const String _tvHeroArtworkQualityKey = 'tv_hero_artwork_quality';

  /// Maximum decode quality for Home hero/stage artwork on Android TV and
  /// tvOS. Unknown values coerce to Automatic so a removed experimental mode
  /// can never strand an installation on an unsupported policy.
  static Future<TvHeroArtworkQuality> getTvHeroArtworkQuality() async {
    final prefs = await ProfilePreferences.instance();
    return TvHeroArtworkQuality.fromStorage(
      prefs.getString(_tvHeroArtworkQualityKey),
    );
  }

  static Future<void> setTvHeroArtworkQuality(
    TvHeroArtworkQuality quality,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_tvHeroArtworkQualityKey, quality.storageValue);
  }

  static const String _phoneNavStyleKey = 'phone_nav_style';
  static const String _phoneNavBarIndicesKey = 'phone_nav_bar_indices';

  /// Phone navigation chrome: 'classic' (bottom bar, the default) or
  /// 'floating' (the glass button menu). TV and wide-desktop never read it.
  static Future<String> getPhoneNavStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_phoneNavStyleKey);
    return raw == 'floating' ? 'floating' : 'classic';
  }

  static Future<void> setPhoneNavStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _phoneNavStyleKey,
      style == 'floating' ? 'floating' : 'classic',
    );
  }

  static const String debrifyTvStyleKey = 'debrify_tv_style';

  /// Every shipping Debrify TV layout. 'grid' is the historical default — the
  /// channel wall `build()` has always drawn; 'spotlight' is the standing
  /// rail + stage (list + sheet on phone). One key covers every device class:
  /// the style resolves its own layout per device, like `detail_page_style`.
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one lands on 'grid' rather than rendering nothing.
  static const Set<String> kDebrifyTvStyles = {'grid', 'spotlight'};

  /// Synchronous mirror of `debrify_tv_style`, kept so a Look can read the
  /// current value without an await. Every existing caller still goes through
  /// the async getter, which also refreshes this.
  static String debrifyTvStyleCached = 'grid';

  static Future<String> getDebrifyTvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(debrifyTvStyleKey);
    return debrifyTvStyleCached = kDebrifyTvStyles.contains(raw)
        ? raw!
        : 'grid';
  }

  static Future<void> setDebrifyTvStyle(String style) async {
    final normalized = kDebrifyTvStyles.contains(style) ? style : 'grid';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    debrifyTvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(debrifyTvStyleKey, normalized);
  }

  static const String detailPageStyleKey = 'detail_page_style';

  /// Every value storage will persist for the merged details page look
  /// (Appearance → Details Page). Every known layout is accepted — a
  /// choice written by a newer build has to survive a downgrade rather than be
  /// silently rewritten to the default the first time an older build reads it.
  ///
  /// What a given BUILD can actually draw is a narrower set —
  /// `kDetailPageStylesShipped` in `screens/settings/detail_page_style_page.dart`
  /// — and dispatch/labels/picker all go through `effectiveDetailPageStyle`.
  static const Set<String> kDetailPageStyles = {
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
  };

  /// The layout a fresh install — and anyone who has never opened the picker —
  /// gets.
  ///
  /// **Console rather than Classic, and that is a deliberate change to what
  /// the app looks like out of the box.** Classic is the one layout that is
  /// deliberately unthemed: it paints its own literals and ignores the app
  /// theme entirely. With Classic as the default, picking an App Theme
  /// appeared to do nothing on the page most people judge the app by — the
  /// setting looked broken when it was working. A themed layout as the default
  /// is what makes it honest.
  ///
  /// This is the FALLBACK, so it moves everyone with no stored value — not
  /// just new installs, but every user who never opened the picker. That
  /// breadth is the point rather than a side effect; Classic is still one row
  /// away for anyone who wants it back.
  static const String kDetailPageStyleDefault = 'console';

  /// Synchronous mirror, warmed in main() before runApp: `MergedDetailScreen`
  /// picks its body in the first build, so an async-only read would paint the
  /// default for a frame and then re-lay-out the whole page.
  ///
  /// Normalizes toward [kDetailPageStyleDefault] on BOTH sides — an
  /// unrecognized value has to mean the default for the reader and the writer
  /// alike.
  static String detailPageStyleCached = kDetailPageStyleDefault;

  static Future<String> getDetailPageStyle() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(detailPageStyleKey);
    detailPageStyleCached = kDetailPageStyles.contains(value)
        ? value!
        : kDetailPageStyleDefault;
    return detailPageStyleCached;
  }

  static Future<void> setDetailPageStyle(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kDetailPageStyles.contains(value)
        ? value
        : kDetailPageStyleDefault;
    await prefs.setString(detailPageStyleKey, normalized);
    detailPageStyleCached = normalized;
  }

  static const String detailThemeKey = 'detail_theme';

  /// Every look the details page can wear (Appearance → Details Theme).
  ///
  /// Same contract as [kDetailPageStyles]: all values are accepted from day
  /// one so a theme written by a newer build survives a downgrade, and what a
  /// given BUILD can draw is the narrower `kDetailThemesShipped` in
  /// `screens/settings/detail_theme_page.dart`.
  ///
  /// The layout and the theme are orthogonal — one says where things are, the
  /// other what they look like.
  static const Set<String> kDetailThemes = {
    'signal',
    'noir',
    'broadsheet',
    'phosphor',
    'aurora',
    'concrete',
    'velvet',
    'blueprint',
    'broadcast',
    'sepia',
    'obsidian',
    'halo',
    'prestige',
    'deep_field',
    'graphite',
    'vault',
    'spectrum',
    'verdant',
    'frost',
    'cinemascope',
    // The five premium looks. Accepted here from the build that introduces
    // them, for the same downgrade reason as everything above: a value a newer
    // build wrote must survive being read by an older one, which normalizes it
    // to 'signal' rather than losing the key.
    'glass',
    'field',
    'hearth',
    'console',
    'reel',

    'spotlight',
  };

  /// Synchronous mirror, warmed in main() before runApp — the details page
  /// picks its theme in the first build, so an async-only read would paint
  /// Signal for a frame and then repaint the whole page.
  static String detailThemeCached = 'signal';

  static Future<String> getDetailTheme() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(detailThemeKey);
    detailThemeCached = kDetailThemes.contains(value) ? value! : 'signal';
    return detailThemeCached;
  }

  static Future<void> setDetailTheme(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kDetailThemes.contains(value) ? value : 'signal';
    await prefs.setString(detailThemeKey, normalized);
    detailThemeCached = normalized;
  }

  static const String appThemeKey = 'app_theme';
  static const String _themeOverridesKey = 'theme_overrides';

  /// The app-wide theme (Appearance → App Theme). `'legacy'` is the sentinel
  /// meaning "render today's app exactly" and is the default; any other
  /// accepted value is a [kDetailThemes] id applied app-wide.
  ///
  /// Unknown/removed ids normalize to `'legacy'` on BOTH sides — never to a
  /// random theme — so a value written by a newer build downgrades safely.
  ///
  /// Write-through contract (owned by `AppThemeController.select`): choosing a
  /// real app theme also mirrors the id into [detailThemeKey], and the mirror
  /// is written FIRST — a crash between the two writes must leave an
  /// older-build-consistent view, and old builds only read `detail_theme`.
  static String appThemeCached = 'legacy';

  static Future<String> getAppTheme() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(appThemeKey);
    appThemeCached = (value == 'legacy' || kDetailThemes.contains(value))
        ? value!
        : 'legacy';
    return appThemeCached;
  }

  static Future<void> setAppTheme(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = (value == 'legacy' || kDetailThemes.contains(value))
        ? value
        : 'legacy';
    await prefs.setString(appThemeKey, normalized);
    appThemeCached = normalized;
  }

  /// The user's per-token edits, as the raw JSON `ThemeOverrides` encodes.
  ///
  /// Kept as a string here rather than a parsed object so this layer stays free
  /// of the theme package — and because the only consumer that matters resolves
  /// it once, on the controller, and memoizes the result.
  ///
  /// Empty string means "no overrides", which is both the default and the fast
  /// path every theme resolution checks first.
  static String themeOverridesCached = '';

  static Future<String> getThemeOverrides() async {
    final prefs = await ProfilePreferences.instance();
    themeOverridesCached = prefs.getString(_themeOverridesKey) ?? '';
    return themeOverridesCached;
  }

  static Future<void> setThemeOverrides(String raw) async {
    final prefs = await ProfilePreferences.instance();
    // Publish the mirror BEFORE the await, like every other live-applied
    // preference here: the controller has already recomputed and notified off
    // this value, and a rebuild that raced the write must not read the old one.
    themeOverridesCached = raw;
    if (raw.isEmpty) {
      await prefs.remove(_themeOverridesKey);
    } else {
      await prefs.setString(_themeOverridesKey, raw);
    }
  }

  static const String _parentsGuideStyleKey = 'parents_guide_style';
  static const Set<String> kParentsGuideStyles = {'classic', 'compass'};

  /// Synchronous mirror used by the Parents Guide widget. Compass is the new
  /// default; Classic remains available as a zero-risk fallback in Appearance.
  static String parentsGuideStyleCached = 'compass';

  static Future<String> getParentsGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_parentsGuideStyleKey);
    parentsGuideStyleCached = kParentsGuideStyles.contains(value)
        ? value!
        : 'compass';
    return parentsGuideStyleCached;
  }

  static Future<void> setParentsGuideStyle(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kParentsGuideStyles.contains(value) ? value : 'compass';
    await prefs.setString(_parentsGuideStyleKey, normalized);
    parentsGuideStyleCached = normalized;
  }

  static const String _iptvStyleKey = 'iptv_style';
  static const Set<String> _iptvStyles = {'command', 'edition', 'console'};

  /// Whether browsing IPTV channels may open the focused channel in the
  /// embedded side preview. This is on by default to preserve the shipped
  /// experience; users whose provider enforces a small connection limit can
  /// turn it off without affecting explicit fullscreen playback.
  static const String _iptvChannelPreviewEnabledKey =
      'iptv_channel_preview_enabled';

  static Future<bool> getIptvChannelPreviewEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvChannelPreviewEnabledKey) ?? true;
  }

  static Future<void> setIptvChannelPreviewEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvChannelPreviewEnabledKey, enabled);
  }

  /// IPTV cockpit look: 'command' (the shipped Command Center, the default),
  /// 'edition' (First Edition — editorial ink/serif) or 'console' (Master
  /// Control — black instrument). Only the TV/desktop cockpit reads it; the
  /// phone classic layout and the touch-tablet two-pane never do. Unknown or
  /// unset coerces to 'command' on BOTH read and write, so an old build
  /// downgrading past a newer value can never pin a look the reader treats
  /// as the exception.
  /// Synchronous mirror of `iptvStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String iptvStyleCached = 'command';

  static Future<String> getIptvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvStyleKey);
    return iptvStyleCached = _iptvStyles.contains(raw) ? raw! : 'command';
  }

  static Future<void> setIptvStyle(String style) async {
    final normalized = _iptvStyles.contains(style) ? style : 'command';
    iptvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iptvStyleKey, normalized);
  }

  // ── Player dock (touch/desktop transport controls) ──────────────────────
  //
  // Three independent prefs so any style works in any palette at any size;
  // bundling them into one "look" would only remove combinations. Palette and
  // size are inert under `classic`, whose values are still preserved so
  // switching to a styled dock restores the user's choices.
  //
  // Read once at player launch. Televisions never consult these — they build
  // `TvControls`, not `Controls`.
  static const String _playerDockStyleKey = 'player_dock_style';
  static const Set<String> _playerDockStyles = {
    'classic',
    'auto',
    'compact',
    'tiers',
    'cinema',
    // The value shipped before the arrangements became selectable. Still
    // accepted on read so existing installs keep the dock they chose; it
    // means the same thing 'auto' does.
    'two_tier',
  };

  static Future<String> getPlayerDockStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockStyleKey);
    return _playerDockStyles.contains(raw) ? raw! : 'classic';
  }

  static Future<void> setPlayerDockStyle(String style) async {
    final normalized = _playerDockStyles.contains(style) ? style : 'classic';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockStyleKey, normalized);
  }

  static const String _playerDockPaletteKey = 'player_dock_palette';
  static const Set<String> _playerDockPalettes = {
    'ultraviolet',
    'crimson',
    'aurum',
    'ice',
  };

  static Future<String> getPlayerDockPalette() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockPaletteKey);
    return _playerDockPalettes.contains(raw) ? raw! : 'ultraviolet';
  }

  static Future<void> setPlayerDockPalette(String palette) async {
    final normalized = _playerDockPalettes.contains(palette)
        ? palette
        : 'ultraviolet';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockPaletteKey, normalized);
  }

  static const String _playerDockSizeKey = 'player_dock_size';
  static const Set<String> _playerDockSizes = {
    'auto',
    'small',
    'medium',
    'large',
  };

  static Future<String> getPlayerDockSize() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockSizeKey);
    return _playerDockSizes.contains(raw) ? raw! : 'auto';
  }

  static Future<void> setPlayerDockSize(String size) async {
    final normalized = _playerDockSizes.contains(size) ? size : 'auto';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockSizeKey, normalized);
  }

  static const String _iptvPlayerGuideStyleKey = 'iptv_player_guide_style';
  static const Set<String> _iptvPlayerGuideStyles = {
    'classic',
    'glass',
    'edition',
    'console',
    'spotlight',
  };

  /// In-player IPTV guide look (zap banner, channel sheet, native guide
  /// overlay + dock): 'classic' (today's look, the default), 'glass'
  /// (Cinema Glass), 'edition' (Midnight Edition) or 'console' (Master
  /// Control). Both players read it once at launch — the Dart player via
  /// this getter, the native TV player via `flutter.iptv_player_guide_style`
  /// in FlutterSharedPreferences. Unknown or unset coerces to 'classic' on
  /// BOTH read and write, so an old build downgrading past a newer value can
  /// never pin a look the reader treats as the exception.
  static Future<String> getIptvPlayerGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvPlayerGuideStyleKey);
    if (_iptvPlayerGuideStyles.contains(raw)) return raw!;
    // Never chosen: Apple TV gets its native idiom, everything else keeps
    // the shipped look. An explicit pick (either way) is stored and wins.
    return PlatformUtil.isTvOS ? 'spotlight' : 'classic';
  }

  static Future<void> setIptvPlayerGuideStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvPlayerGuideStyleKey,
      _iptvPlayerGuideStyles.contains(style) ? style : 'classic',
    );
  }

  static const String _playLoaderStyleKey = 'play_loader_style';
  static const Set<String> _playLoaderStyles = {'marquee', 'classic'};

  /// The look of the play → resolve loader: 'marquee' (the default — backdrop,
  /// logo art and a segmented stage rail) or 'classic' (the poster-and-
  /// checklist card this overlay shipped with). Unknown or unset coerces to
  /// 'marquee' on BOTH read and write, so a value written by a newer build can
  /// never pin a look this one cannot render.
  ///
  /// The play path reads it synchronously through
  /// [PlayLoaderStyleController.cached]; this getter is the warm source.
  static Future<String> getPlayLoaderStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playLoaderStyleKey);
    return _playLoaderStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setPlayLoaderStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _playLoaderStyleKey,
      _playLoaderStyles.contains(style) ? style : 'marquee',
    );
  }

  static const String _tvPlayerControlsStyleKey = 'tv_player_controls_style';
  static const Set<String> _tvPlayerControlsStyles = {
    'classic',
    'ott',
    'frost',
    'marquee',
    'broadcast',
    'pulse',
    'ticket',
  };

  /// Control skin for the NATIVE Android TV player: 'marquee' (editorial
  /// serif — the default), 'ott' (the Apple TV dock ported to Kotlin),
  /// 'classic' (the legacy Cinema Mode controls), or one of the other
  /// premium dock skins ('frost', 'broadcast', 'pulse', 'ticket'). Android TV only; tvOS runs the
  /// Flutter player and has nothing to choose. Read once per player launch — the native side via
  /// `ProfilePreferenceProjection.getString("tv_player_controls_style")`
  /// (falling back to `flutter.tv_player_controls_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'marquee' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getTvPlayerControlsStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_tvPlayerControlsStyleKey);
    return _tvPlayerControlsStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setTvPlayerControlsStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _tvPlayerControlsStyleKey,
      _tvPlayerControlsStyles.contains(style) ? style : 'marquee',
    );
  }

  static const String _debrifyTvPlayerStyleKey = 'debrify_tv_player_style';
  static const Set<String> _debrifyTvPlayerStyles = {
    'classic',
    'network',
    'cinema',
    'guide',
    'spotlight',
    'prestige',
  };

  /// Playback-screen style for the NATIVE Debrify TV player
  /// (TorboxTvPlayerActivity): 'cinema' (poster + gilded spec line — the
  /// default), 'network' (broadcast lower-third), 'guide' (opaque
  /// broadcast band), 'spotlight' (frosted glass panel), 'prestige'
  /// (quiet serif identity), or 'classic' (the legacy ESPN-style bar +
  /// top marquee). Android TV only. Read once per player launch — the
  /// native side via
  /// `ProfilePreferenceProjection.getString("debrify_tv_player_style")`
  /// (falling back to `flutter.debrify_tv_player_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'cinema' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getDebrifyTvPlayerStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvPlayerStyleKey);
    return _debrifyTvPlayerStyles.contains(raw) ? raw! : 'cinema';
  }

  static Future<void> setDebrifyTvPlayerStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _debrifyTvPlayerStyleKey,
      _debrifyTvPlayerStyles.contains(style) ? style : 'cinema',
    );
  }

  static const String _discoverLayoutKey = 'discover_layout';
  static const String _discoverDefaultSourceKey = 'discover_default_source';
  static const String _discoverLastSourceKey = 'discover_last_source';

  /// Special value for the Discover default-source setting. When selected,
  /// [getDiscoverLastSource] decides which source opens on the next visit.
  static const String discoverDefaultRememberLast = 'remember';

  static bool _isDiscoverSourceValue(String value) =>
      value == 'cw' ||
      value == 'trakt' ||
      value == 'simkl' ||
      value == 'mdblist' ||
      (value.startsWith('a:') && value.length > 2 && value.length <= 514);

  /// What Discover should show when opened. Unset defaults to remembering the
  /// last source, preserving the most useful behavior for existing installs.
  static Future<String> getDiscoverDefaultSource() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_discoverDefaultSourceKey);
    return value == discoverDefaultRememberLast ||
            (value != null && _isDiscoverSourceValue(value))
        ? value!
        : discoverDefaultRememberLast;
  }

  static Future<void> setDiscoverDefaultSource(String value) async {
    final normalized =
        value == discoverDefaultRememberLast || _isDiscoverSourceValue(value)
        ? value
        : discoverDefaultRememberLast;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverDefaultSourceKey, normalized);
  }

  /// The last source explicitly opened from Discover. A missing or malformed
  /// value safely falls back to Continue Watching.
  static Future<String> getDiscoverLastSource() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_discoverLastSourceKey);
    return value != null && _isDiscoverSourceValue(value) ? value : 'cw';
  }

  static Future<void> setDiscoverLastSource(String value) async {
    if (!_isDiscoverSourceValue(value)) return;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverLastSourceKey, value);
  }

  /// TV Discover layout: 'stage' (the focused title full-bleed with one bottom
  /// shelf, the default) or 'grid' (the detail rail beside a poster wall). Its
  /// own key, deliberately NOT shared with [getTvHomeStyle]: Home's Canvas
  /// switches rails with UP/DOWN and Discover's Stage owns a filter line —
  /// neither layout has the other's axis, so one pref governing both would
  /// promise a symmetry they can't keep. Phone/desktop never read it.
  ///
  /// Unset reads as 'stage', so users who never opened the picker move to it.
  /// Everything else that holds a pre-load placeholder for this pref must
  /// agree, or the UI paints one layout and then swaps: SearchScreen's
  /// `_discLayoutCached`, DiscoverLayoutPage, SettingsScreen.
  /// Synchronous mirror of `discoverLayout`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String discoverLayoutCached = 'stage';

  static Future<String> getDiscoverLayout() async {
    final prefs = await ProfilePreferences.instance();
    return discoverLayoutCached = prefs.getString(_discoverLayoutKey) == 'grid'
        ? 'grid'
        : 'stage';
  }

  /// Normalizes toward 'stage' on the same terms [getDiscoverLayout] does —
  /// an unrecognized value has to mean the default on BOTH sides, or writing
  /// one would silently pin the layout the reader treats as the exception.
  static Future<void> setDiscoverLayout(String layout) async {
    final normalized = layout == 'grid' ? 'grid' : 'stage';
    discoverLayoutCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverLayoutKey, normalized);
  }

  static const String _launchAnimationKey = 'launch_animation';
  // MUST stay in step with kLaunchIdents — an id missing here is silently
  // normalized back to the default, so the picker would appear not to save.
  static const Set<String> _launchAnimationValues = {
    'drop',
    'marquee',
    'prism',
    'horizon',
    'collider',
    'neon',
    'chrome',
    'monogram',
    'aperture',
    'blueprint',
    'ripple',
    'ember',
    'swiss',
    'origami',
    'anamorphic',
    'constellation',
    'silk',
    'rackfocus',
    'imprint',
    'frost',
    'trace',
  };

  /// Exposed so a test can assert this set and `kLaunchIdents` agree in BOTH
  /// directions — drift either way silently strands the pref on the default.
  /// The StorageService façade keeps `@visibleForTesting`; this store getter
  /// is the implementation the façade forwards to.
  static Set<String> get launchAnimationValues => _launchAnimationValues;

  /// Which launch ident the splash plays (Appearance → Launch Animation).
  /// Values are the ids in `widgets/launch/launch_ident.dart`; 'trace' (Trace)
  /// is the default, 'collider' and before it 'horizon' are the idents it
  /// replaced as such, and 'drop' is the original splash.
  ///
  /// [launchAnimationCached] mirrors it for SYNCHRONOUS reads: AppInitializer
  /// builds its splash in initState, before any async pref read could land.
  /// Warmed in main() before runApp and kept in sync by the setter.
  ///
  /// Normalizes toward the default on BOTH sides — an unrecognized value has
  /// to mean the default for the reader and the writer alike. Only installs
  /// that never CHOSE move when this changes: an explicit 'collider' is a
  /// stored value and keeps playing Collider.
  static String launchAnimationCached = 'trace';

  static Future<String> getLaunchAnimation() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_launchAnimationKey);
    launchAnimationCached = _launchAnimationValues.contains(value)
        ? value!
        : 'trace';
    return launchAnimationCached;
  }

  static Future<void> setLaunchAnimation(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _launchAnimationValues.contains(value) ? value : 'trace';
    await prefs.setString(_launchAnimationKey, normalized);
    launchAnimationCached = normalized;
  }

  static const String _launchIdentPaletteKey = 'launch_ident_palette';
  static const Set<String> _launchIdentPalettes = {'ident', 'theme'};

  /// Whether the launch ident wears its OWN colours or the app theme's
  /// (Appearance → Launch Animation).
  ///
  /// Defaults to `'ident'`, so nobody's splash changes until they ask. The
  /// ident's art direction — its geometry, its motion, its mark — is the same
  /// either way; only the room's colours move, and only where they stay
  /// legible (see `IdentPalette.fromTheme`).
  ///
  /// Mirrored synchronously for the same reason [launchAnimationCached] is:
  /// AppInitializer builds the splash in `initState`, before any async read
  /// could land.
  static String launchIdentPaletteCached = 'ident';

  static Future<String> getLaunchIdentPalette() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_launchIdentPaletteKey);
    launchIdentPaletteCached = _launchIdentPalettes.contains(value)
        ? value!
        : 'ident';
    return launchIdentPaletteCached;
  }

  static Future<void> setLaunchIdentPalette(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _launchIdentPalettes.contains(value) ? value : 'ident';
    // Mirror BEFORE the await: the picker rebuilds on the next frame and the
    // splash reads the mirror synchronously.
    launchIdentPaletteCached = normalized;
    await prefs.setString(_launchIdentPaletteKey, normalized);
  }

  static const String _textBrightnessKey = 'text_brightness';
  static const Set<String> _textBrightnessValues = {'bright', 'soft', 'dim'};

  /// App-wide text brightness (Appearance → Text Brightness): 'bright' (pure
  /// white, the default and the app's historical look), 'soft', or 'dim'.
  /// Consumed as a [TextBrightness] preset by the root theme — see
  /// `services/text_brightness.dart` for the actual colors. The synchronous
  /// mirror for first-frame reads is TextBrightnessController's notifier,
  /// warmed in main() before runApp — no cached copy lives here.
  ///
  /// Normalizes toward 'bright' on BOTH sides — an unrecognized value has to
  /// mean the default for the reader and the writer alike, or writing one
  /// would silently pin a preset the reader treats as the exception.
  static Future<String> getTextBrightness() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_textBrightnessKey);
    return _textBrightnessValues.contains(value) ? value! : 'bright';
  }

  static Future<void> setTextBrightness(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _textBrightnessKey,
      _textBrightnessValues.contains(value) ? value : 'bright',
    );
  }

  static const String tvSidebarStyleKey = 'tv_sidebar_style';
  static const Set<String> _tvSidebarStyles = {
    'classic',
    'ghost',
    'island',
    'marquee',
    'badge',
    'pill',
  };

  /// TV sidebar chrome: 'ghost' (chromeless, the default), 'classic' (the
  /// original liquid glass), 'island', 'marquee', 'badge' or 'pill'.
  ///
  /// The LEFT-only focus model is shared by every style. Chrome-only for the
  /// first five; **'pill' is the one that also changes LAYOUT** — it shows no
  /// rail at rest, so content runs full-bleed and gains 64px. Read the inset
  /// through `TvSidebarNav.contentInsetFor` rather than assuming the constant.
  /// Phone/desktop never read any of it.
  /// Synchronous mirror of `tvSidebarStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String tvSidebarStyleCached = 'ghost';

  static Future<String> getTvSidebarStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(tvSidebarStyleKey);
    return tvSidebarStyleCached =
        (raw != null && _tvSidebarStyles.contains(raw)) ? raw : 'ghost';
  }

  static Future<void> setTvSidebarStyle(String style) async {
    final normalized = _tvSidebarStyles.contains(style) ? style : 'ghost';
    tvSidebarStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(tvSidebarStyleKey, normalized);
  }

  static const String desktopSidebarStyleKey = 'desktop_sidebar_style';
  static const Set<String> _desktopSidebarStyles = {'rail', 'pill'};

  /// Desktop/tablet sidebar chrome, read only at the wide (≥600) non-TV
  /// layout: 'rail' (the fixed icon rail, the default) or 'pill' (no rail —
  /// content runs full-bleed and a floating capsule shows the current tab;
  /// clicking it opens the menu as an overlay). The TV rail has its own key
  /// above and never reads this; phones never reach the wide layout.
  /// Warmed in `main()` before the first frame — the shell's field
  /// initializer reads it so a migrated/pill user never flashes the rail.
  static String desktopSidebarStyleCached = 'rail';

  static Future<String> getDesktopSidebarStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(desktopSidebarStyleKey);
    return desktopSidebarStyleCached =
        (raw != null && _desktopSidebarStyles.contains(raw)) ? raw : 'rail';
  }

  static Future<void> setDesktopSidebarStyle(String style) async {
    desktopSidebarStyleCached = _desktopSidebarStyles.contains(style)
        ? style
        : 'rail';
    final normalized = _desktopSidebarStyles.contains(style) ? style : 'rail';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(desktopSidebarStyleKey, normalized);
  }

  static const String _sidebarConfigurationKey = 'sidebar_configuration_v1';

  /// Profile-scoped order and label overrides shared by the Android TV and
  /// desktop/tablet sidebars. The cached mirror is warmed before runApp so a
  /// customized profile never flashes the default order on frame one.
  static SidebarConfiguration sidebarConfigurationCached =
      SidebarConfiguration.defaults();

  static Future<SidebarConfiguration> getSidebarConfiguration() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_sidebarConfigurationKey);
    return sidebarConfigurationCached =
        (raw == null ? null : SidebarConfiguration.tryDecode(raw)) ??
        SidebarConfiguration.defaults();
  }

  static Future<bool> setSidebarConfiguration(
    SidebarConfiguration configuration,
  ) async {
    final normalized = SidebarConfiguration(
      order: configuration.order,
      labels: configuration.labels,
    );
    final prefs = await ProfilePreferences.instance();
    final saved = await prefs.setString(
      _sidebarConfigurationKey,
      normalized.encode(),
    );
    if (saved) sidebarConfigurationCached = normalized;
    return saved;
  }

  static Future<bool> resetSidebarConfiguration() async {
    final prefs = await ProfilePreferences.instance();
    final removed = await prefs.remove(_sidebarConfigurationKey);
    if (removed || !prefs.containsKey(_sidebarConfigurationKey)) {
      sidebarConfigurationCached = SidebarConfiguration.defaults();
      return true;
    }
    return false;
  }

  /// The classic bar's user-chosen middle slots, as REAL tab indices (Home)
  /// and More are fixed anchors and never stored). Null = never customized
  /// (defaults apply); an explicit short list is a deliberate choice and the
  /// bar respects its length.
  static Future<List<int>?> getPhoneNavBarIndices() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getStringList(_phoneNavBarIndicesKey);
    if (raw == null) return null;
    return [
      for (final s in raw)
        if (int.tryParse(s) != null) int.parse(s),
    ];
  }

  static Future<void> setPhoneNavBarIndices(List<int> indices) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_phoneNavBarIndicesKey, [
      for (final i in indices) '$i',
    ]);
  }
  /// Generation 1 theme/detail phase; the coordinator supplies captured prefs.
  static Future<void> migrateDefaultsGeneration1Theme(
    ProfilePreferences prefs,
  ) async {
    // Dormant prefs are written too (desktop pill on a phone, TV home
    // style off-TV): harmless where they don't apply, correct if the
    // device class — or a window size — ever changes.
    //
    // The theme and its `detail_theme` mirror move as a PAIR, in the
    // controller's write-through order (mirror first — old builds read
    // only the mirror, and Showcase resolves its palette from it). The
    // pairing also means an explicit legacy pick (app_theme stored, no
    // mirror by design) keeps its details page untouched.
    if (!prefs.containsKey(appThemeKey)) {
      if (!prefs.containsKey(detailThemeKey)) {
        await prefs.setString(detailThemeKey, 'spotlight');
      }
      await prefs.setString(appThemeKey, 'spotlight');
    }
    if (!prefs.containsKey(detailPageStyleKey)) {
      await prefs.setString(detailPageStyleKey, 'showcase');
    }
  }

  /// Runs after the generation 1 Home phase, preserving the original sequence.
  static Future<void> migrateDefaultsGeneration1Sidebars(
    ProfilePreferences prefs,
  ) async {
    const bundle = <String, String>{
      tvSidebarStyleKey: 'pill',
      desktopSidebarStyleKey: 'pill',
    };
    for (final entry in bundle.entries) {
      if (!prefs.containsKey(entry.key)) {
        await prefs.setString(entry.key, entry.value);
      }
    }
  }

  /// Generation 3 reads the raw theme adopted by earlier phases.
  static Future<void> migrateDefaultsGeneration3TvStyle(
    ProfilePreferences prefs,
  ) async {
    // Debrify TV joins the flagship bundle. Raw prefs only — this runs
    // before any mirror is warmed, so `app_theme` is read directly rather
    // than through `appThemeCached`. The gen<1 block above has already
    // written `app_theme` for anyone who never chose, including a fresh
    // install, so this read is never against an absent key on a migrated
    // install.
    //
    // NOT unconditional the way generation 1 was: this key has never
    // existed, so `!containsKey` is true for every install on earth, and a
    // blanket 'spotlight' would restyle every Classic user AND flip their
    // Presets picker to Custom (Classic pins this key). The proxy is the
    // THEME, not Look activity — a Custom mix that kept the Spotlight
    // theme adopts the layout the theme implies; everyone else keeps grid.
    if (!prefs.containsKey(debrifyTvStyleKey)) {
      final theme = prefs.getString(appThemeKey);
      await prefs.setString(
        debrifyTvStyleKey,
        theme == 'spotlight' ? 'spotlight' : 'grid',
      );
    }
  }

}
