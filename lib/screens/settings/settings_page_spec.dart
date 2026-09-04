import 'package:flutter/material.dart';

import 'settings_search.dart';
import 'settings_spotlight_shell.dart';
import 'widgets/settings_widgets.dart';

/// Which settings chrome a page is listed on.
///
/// Phone is the single-column list, desktop is the Spotlight category
/// shell, TV is the two-pane rail. Search is derived from the same spec
/// (a page can be search-only, e.g. Addons).
enum SettingsLayoutSurface { phone, desktop, tv }

/// How the row is drawn. Info tiles take no TV pane focus node (the
/// About version chip is the existing case).
enum SettingsRowKind { tile, toggle, info, lookHero, url }

/// Sub-setting that lives inside a page and deep-links to that page.
class SettingsLeafSpec {
  final String title;
  final String subtitle;
  final List<String> keywords;
  final Future<void> Function()? onTap;
  final bool Function()? visible;

  const SettingsLeafSpec({
    required this.title,
    required this.subtitle,
    this.keywords = const [],
    this.onTap,
    this.visible,
  });
}

/// One settings destination, registered once.
///
/// [row], [category], [opener], [keywords] and [leaves] are the fields the
/// plan names. Surface flags and [kind]/[group] tell the three layouts
/// how to place it without a second table.
class SettingsPageSpec {
  /// Stable id (also the leaf-table page name when [leafPageName] is null).
  final String id;
  final SettingsRowContent row;
  final String category;
  final Future<void> Function()? opener;
  final List<String> keywords;
  final List<SettingsLeafSpec> leaves;

  final bool phone;
  final bool desktop;
  final bool tv;
  final bool search;

  /// Sort keys. Lower first. Defaults keep a newly-registered page at the
  /// end of its category on every surface.
  final int phoneOrder;
  final int desktopOrder;
  final int tvOrder;

  /// Group header within the category. Null = the ungrouped bucket
  /// (phone uses the category name as the section title).
  final String? phoneGroup;
  final String? desktopGroup;
  final String? tvGroup;

  final SettingsRowKind kind;
  final SettingsRowKind? phoneKind;
  final SettingsRowKind? desktopKind;
  final SettingsRowKind? tvKind;
  final bool destructive;
  final bool Function()? visible;

  /// Per-surface gate. When set, wins over [visible] for layout placement.
  final bool Function(SettingsLayoutSurface surface)? visibleOn;
  final bool Function()? searchVisible;
  final String Function()? titleOf;
  final String Function()? subtitleOf;
  final Widget? Function()? trailingOf;
  final String? tag;
  final bool Function()? toggleValue;
  final ValueChanged<bool>? onToggle;

  /// Leaf-index category override (in-page options group under the page
  /// name, not the rail category).
  final String? leafPageName;

  const SettingsPageSpec({
    required this.id,
    required this.row,
    required this.category,
    this.opener,
    this.keywords = const [],
    this.leaves = const [],
    this.phone = true,
    this.desktop = true,
    this.tv = true,
    this.search = true,
    this.phoneOrder = 100,
    this.desktopOrder = 100,
    this.tvOrder = 100,
    this.phoneGroup,
    this.desktopGroup,
    this.tvGroup,
    this.kind = SettingsRowKind.tile,
    this.phoneKind,
    this.desktopKind,
    this.tvKind,
    this.destructive = false,
    this.visible,
    this.visibleOn,
    this.searchVisible,
    this.titleOf,
    this.subtitleOf,
    this.trailingOf,
    this.tag,
    this.toggleValue,
    this.onToggle,
    this.leafPageName,
  });

  String get title => titleOf?.call() ?? row.title;

  String get resolvedSubtitle => subtitleOf?.call() ?? row.subtitle;

  String get searchLeafPage => leafPageName ?? row.title;

  bool get isVisible => visible?.call() ?? true;

  bool isVisibleOn(SettingsLayoutSurface surface) {
    if (visibleOn != null) return visibleOn!(surface);
    return isVisible;
  }

  bool get isSearchVisible =>
      searchVisible?.call() ??
      (visibleOn?.call(SettingsLayoutSurface.phone) ?? isVisible);

  bool showsOn(SettingsLayoutSurface surface) {
    if (!isVisibleOn(surface)) return false;
    switch (surface) {
      case SettingsLayoutSurface.phone:
        return phone;
      case SettingsLayoutSurface.desktop:
        return desktop;
      case SettingsLayoutSurface.tv:
        return tv;
    }
  }

  int orderOn(SettingsLayoutSurface surface) {
    switch (surface) {
      case SettingsLayoutSurface.phone:
        return phoneOrder;
      case SettingsLayoutSurface.desktop:
        return desktopOrder;
      case SettingsLayoutSurface.tv:
        return tvOrder;
    }
  }

  SettingsRowKind kindOn(SettingsLayoutSurface surface) {
    switch (surface) {
      case SettingsLayoutSurface.phone:
        return phoneKind ?? kind;
      case SettingsLayoutSurface.desktop:
        return desktopKind ?? kind;
      case SettingsLayoutSurface.tv:
        return tvKind ?? kind;
    }
  }

  String? groupOn(SettingsLayoutSurface surface) {
    switch (surface) {
      case SettingsLayoutSurface.phone:
        return phoneGroup;
      case SettingsLayoutSurface.desktop:
        return desktopGroup;
      case SettingsLayoutSurface.tv:
        return tvGroup;
    }
  }

  SettingsSearchEntry toSearchEntry() {
    if (kind == SettingsRowKind.toggle ||
        phoneKind == SettingsRowKind.toggle ||
        desktopKind == SettingsRowKind.toggle ||
        tvKind == SettingsRowKind.toggle) {
      return SettingsSearchEntry(
        icon: row.icon,
        title: title,
        subtitle: resolvedSubtitle,
        category: category,
        keywords: keywords,
        toggleValue: toggleValue,
        onToggle: onToggle,
      );
    }
    return SettingsSearchEntry(
      icon: row.icon,
      title: title,
      subtitle: resolvedSubtitle,
      category: category,
      keywords: keywords,
      destructive: destructive,
      onTap: opener ?? () async {},
    );
  }
}

/// Rail / spotlight category. Copy differs slightly between TV and desktop
/// (a quirk the pin test covers at the label level, not the blurb level).
class SettingsCategorySpec {
  final String id;
  final IconData icon;
  final String label;
  final String tvSubtitle;
  final String tvTitle;
  final String tvDescription;
  final String desktopSubtitle;
  final String desktopEyebrow;
  final String desktopTitle;
  final String desktopDescription;
  final bool destructive;

  const SettingsCategorySpec({
    required this.id,
    required this.icon,
    required this.label,
    required this.tvSubtitle,
    required this.tvTitle,
    required this.tvDescription,
    required this.desktopSubtitle,
    required this.desktopEyebrow,
    required this.desktopTitle,
    required this.desktopDescription,
    this.destructive = false,
  });

  SettingsCategoryDefinition toDesktop() => SettingsCategoryDefinition(
    icon: icon,
    label: label,
    subtitle: desktopSubtitle,
    eyebrow: desktopEyebrow,
    title: desktopTitle,
    description: desktopDescription,
    destructive: destructive,
  );
}

/// Live openers, labels and gates. Built in [SettingsScreen] each rebuild
/// so dynamic copy (download folder, update status) stays current.
class SettingsPageBindings {
  final Future<void> Function() openHomePage;
  final Future<void> Function() openCollections;
  final Future<void> Function() openExternalPlayer;
  final Future<void> Function() openRemote;
  final Future<void> Function() openSwitchProfile;
  final Future<void> Function() openAddProfile;
  final Future<void> Function() openEditProfile;
  final Future<void> Function() openNavigation;
  final Future<void> Function() openTorrentSettings;
  final Future<void> Function() openFilterSettings;
  final Future<void> Function() openProviderSettings;
  final Future<void> Function() openQuickPlay;
  final Future<void> Function() openDiscover;
  final Future<void> Function() openDebrifyTv;
  final Future<void> Function() openRecordings;
  final Future<void> Function() openIptv;
  final Future<void> Function()? openDownloadLocation;
  final Future<void> Function() clearDownloads;
  final Future<void> Function() clearPlayback;
  final Future<void> Function() createBackup;
  final Future<void> Function() restoreBackup;
  final Future<void> Function()? exportDiagnosticLogs;
  final Future<void> Function() resetApp;
  final Future<void> Function() checkUpdates;
  final Future<void> Function() openSupportDonation;
  final Future<void> Function() openTextBrightness;
  final Future<void> Function() openLaunchAnimation;
  final Future<void> Function() openTvScreenSize;
  final Future<void> Function() openTvRenderQuality;
  final Future<void> Function() openTvHeroArtworkQuality;
  final Future<void> Function() openTvHomeStyle;
  final Future<void> Function() openDiscoverLayout;
  final Future<void> Function() openTvSidebarStyle;
  final Future<void> Function() openDesktopSidebarStyle;
  final Future<void> Function() openIptvStyle;
  final Future<void> Function() openDebrifyTvStyle;
  final Future<void> Function() openPlayerGuideStyle;
  final Future<void> Function() openPlayLoaderStyle;
  final Future<void> Function() openTvPlayerControlsStyle;
  final Future<void> Function() openDebrifyTvPlayerStyle;
  final Future<void> Function() openPlayerDock;
  final Future<void> Function() openThemeTokens;
  final Future<void> Function() openLooks;
  final Future<void> Function() openThemeLab;
  final Future<void> Function() openAppTheme;
  final Future<void> Function() openDetailTheme;
  final Future<void> Function() openSidebarCustomization;
  final Future<void> Function() openParentsGuideStyle;
  final Future<void> Function() openDetailPageStyle;
  final Future<void> Function() openProfileAppearance;
  final Future<void> Function() openStremioTv;
  final Future<void> Function() openAddons;
  final Future<void> Function()? openIptvAddSource;
  final Future<void> Function()? openIptvChannelOrder;
  final Future<void> Function() openTorbox;
  final Future<void> Function() openPremiumize;
  final Future<void> Function() openRealDebrid;
  final Future<void> Function() openAllDebrid;
  final Future<void> Function() openPikPak;
  final Future<void> Function() openWebDav;
  final Future<void> Function() openIndexerManagers;
  final Future<void> Function() openTrakt;
  final Future<void> Function() openTracking;
  final Future<void> Function() openSimkl;
  final Future<void> Function() openMdblist;

  final String textBrightnessLabel;
  final String launchAnimationLabel;
  final String tvUiScaleLabel;
  final String tvRenderQualityLabel;
  final String tvHeroArtworkQualityLabel;
  final String tvHomeStyleLabel;
  final String discoverLayoutLabel;
  final String tvSidebarStyleLabel;
  final String desktopSidebarStyleLabel;
  final String iptvStyleLabel;
  final String debrifyTvStyleLabel;
  final String playerGuideStyleLabel;
  final String playLoaderStyleLabel;
  final String tvPlayerControlsStyleLabel;
  final String debrifyTvPlayerStyleLabel;
  final String playerDockLabel;
  final String themeTokensLabel;
  final String looksLabel;
  final String detailThemeLabel;
  final String parentsGuideStyleLabel;
  final String detailPageStyleLabel;
  final String profileAppearanceLabel;
  final String phoneNavStyleLabel;
  final String downloadLocationSubtitle;
  final String updateSubtitle;
  final String supportDonationLabel;
  final String supportDonationSubtitle;
  final String appVersion;
  final bool checkingUpdates;
  final bool autoUpdateChecksEnabled;
  final ValueChanged<bool> onToggleAutoUpdateChecks;
  final bool tvKeyboardEnabled;
  final ValueChanged<bool> onToggleTvKeyboard;

  final bool isAndroidTv;
  final bool isTelevision;
  final bool isAndroid;
  final bool isPhone;
  final bool showSwitchProfile;
  final bool downloadLocationSupported;
  final bool diagnosticExportVisible;
  final bool showSupportDonation;
  final bool iptvAppearanceSearchable;
  final bool recordingSearchable;
  final bool recordingSupported;
  final bool preferredExternalPlayerSupported;
  final bool customPlayerCommandSupported;
  final bool mdblistEnabled;
  final bool profileCommitted;
  final bool supportsSubtitleAutoSync;
  final bool isTvOS;
  final bool isIosMobile;

  final List<String> Function() extraTextBrightnessKeywords;
  final List<String> Function() extraLaunchAnimationKeywords;
  final List<String> Function() extraTvScreenSizeKeywords;
  final List<String> Function() extraTvRenderQualityKeywords;
  final List<String> Function() extraTvHeroArtworkKeywords;
  final List<String> Function() extraTvHomeStyleKeywords;
  final List<String> Function() extraDiscoverLayoutKeywords;
  final List<String> Function() extraTvSidebarKeywords;
  final List<String> Function() extraDesktopSidebarKeywords;
  final List<String> Function() extraIptvStyleKeywords;
  final List<String> Function() extraDebrifyTvStyleKeywords;
  final List<String> Function() extraPlayerGuideKeywords;
  final List<String> Function() extraPlayLoaderKeywords;
  final List<String> Function() extraTvPlayerControlsKeywords;
  final List<String> Function() extraDebrifyTvPlayerKeywords;
  final List<String> Function() extraPlayerDockKeywords;
  final List<String> Function() extraLooksKeywords;
  final List<String> Function() extraParentsGuideKeywords;
  final List<String> Function() extraDetailPageKeywords;
  final List<String> Function() extraProfileAppearanceKeywords;
  final List<String> Function() extraPlayerKeywords;

  const SettingsPageBindings({
    required this.openHomePage,
    required this.openCollections,
    required this.openExternalPlayer,
    required this.openRemote,
    required this.openSwitchProfile,
    required this.openAddProfile,
    required this.openEditProfile,
    required this.openNavigation,
    required this.openTorrentSettings,
    required this.openFilterSettings,
    required this.openProviderSettings,
    required this.openQuickPlay,
    required this.openDiscover,
    required this.openDebrifyTv,
    required this.openRecordings,
    required this.openIptv,
    this.openDownloadLocation,
    required this.clearDownloads,
    required this.clearPlayback,
    required this.createBackup,
    required this.restoreBackup,
    this.exportDiagnosticLogs,
    required this.resetApp,
    required this.checkUpdates,
    required this.openSupportDonation,
    required this.openTextBrightness,
    required this.openLaunchAnimation,
    required this.openTvScreenSize,
    required this.openTvRenderQuality,
    required this.openTvHeroArtworkQuality,
    required this.openTvHomeStyle,
    required this.openDiscoverLayout,
    required this.openTvSidebarStyle,
    required this.openDesktopSidebarStyle,
    required this.openIptvStyle,
    required this.openDebrifyTvStyle,
    required this.openPlayerGuideStyle,
    required this.openPlayLoaderStyle,
    required this.openTvPlayerControlsStyle,
    required this.openDebrifyTvPlayerStyle,
    required this.openPlayerDock,
    required this.openThemeTokens,
    required this.openLooks,
    this.openThemeLab = SettingsPageBindings._noop,
    this.openAppTheme = SettingsPageBindings._noop,
    this.openDetailTheme = SettingsPageBindings._noop,
    this.openSidebarCustomization = SettingsPageBindings._noop,
    required this.openParentsGuideStyle,
    required this.openDetailPageStyle,
    required this.openProfileAppearance,
    required this.openStremioTv,
    required this.openAddons,
    this.openIptvAddSource,
    this.openIptvChannelOrder,
    this.openTorbox = SettingsPageBindings._noop,
    this.openPremiumize = SettingsPageBindings._noop,
    this.openRealDebrid = SettingsPageBindings._noop,
    this.openAllDebrid = SettingsPageBindings._noop,
    this.openPikPak = SettingsPageBindings._noop,
    this.openWebDav = SettingsPageBindings._noop,
    this.openIndexerManagers = SettingsPageBindings._noop,
    this.openTrakt = SettingsPageBindings._noop,
    this.openTracking = SettingsPageBindings._noop,
    this.openSimkl = SettingsPageBindings._noop,
    this.openMdblist = SettingsPageBindings._noop,
    this.textBrightnessLabel = '',
    this.launchAnimationLabel = '',
    this.tvUiScaleLabel = '',
    this.tvRenderQualityLabel = '',
    this.tvHeroArtworkQualityLabel = '',
    this.tvHomeStyleLabel = '',
    this.discoverLayoutLabel = '',
    this.tvSidebarStyleLabel = '',
    this.desktopSidebarStyleLabel = '',
    this.iptvStyleLabel = '',
    this.debrifyTvStyleLabel = '',
    this.playerGuideStyleLabel = '',
    this.playLoaderStyleLabel = '',
    this.tvPlayerControlsStyleLabel = '',
    this.debrifyTvPlayerStyleLabel = '',
    this.playerDockLabel = '',
    this.themeTokensLabel = '',
    this.looksLabel = 'Custom',
    this.detailThemeLabel = '',
    this.parentsGuideStyleLabel = '',
    this.detailPageStyleLabel = '',
    this.profileAppearanceLabel = '',
    this.phoneNavStyleLabel = '',
    this.downloadLocationSubtitle = '',
    this.updateSubtitle = '',
    this.supportDonationLabel = 'Support Debrify',
    this.supportDonationSubtitle = '',
    this.appVersion = '',
    this.checkingUpdates = false,
    this.autoUpdateChecksEnabled = true,
    this.onToggleAutoUpdateChecks = _ignoreToggle,
    this.tvKeyboardEnabled = true,
    this.onToggleTvKeyboard = _ignoreToggle,
    this.isAndroidTv = false,
    this.isTelevision = false,
    this.isAndroid = false,
    this.isPhone = false,
    this.showSwitchProfile = false,
    this.downloadLocationSupported = false,
    this.diagnosticExportVisible = false,
    this.showSupportDonation = false,
    this.iptvAppearanceSearchable = true,
    this.recordingSearchable = false,
    this.recordingSupported = false,
    this.preferredExternalPlayerSupported = false,
    this.customPlayerCommandSupported = false,
    this.mdblistEnabled = false,
    this.profileCommitted = false,
    this.supportsSubtitleAutoSync = false,
    this.isTvOS = false,
    this.isIosMobile = false,
    this.extraTextBrightnessKeywords = _emptyKeywords,
    this.extraLaunchAnimationKeywords = _emptyKeywords,
    this.extraTvScreenSizeKeywords = _emptyKeywords,
    this.extraTvRenderQualityKeywords = _emptyKeywords,
    this.extraTvHeroArtworkKeywords = _emptyKeywords,
    this.extraTvHomeStyleKeywords = _emptyKeywords,
    this.extraDiscoverLayoutKeywords = _emptyKeywords,
    this.extraTvSidebarKeywords = _emptyKeywords,
    this.extraDesktopSidebarKeywords = _emptyKeywords,
    this.extraIptvStyleKeywords = _emptyKeywords,
    this.extraDebrifyTvStyleKeywords = _emptyKeywords,
    this.extraPlayerGuideKeywords = _emptyKeywords,
    this.extraPlayLoaderKeywords = _emptyKeywords,
    this.extraTvPlayerControlsKeywords = _emptyKeywords,
    this.extraDebrifyTvPlayerKeywords = _emptyKeywords,
    this.extraPlayerDockKeywords = _emptyKeywords,
    this.extraLooksKeywords = _emptyKeywords,
    this.extraParentsGuideKeywords = _emptyKeywords,
    this.extraDetailPageKeywords = _emptyKeywords,
    this.extraProfileAppearanceKeywords = _emptyKeywords,
    this.extraPlayerKeywords = _emptyKeywords,
  });

  static Future<void> _noop() async {}
  static void _ignoreToggle(bool _) {}
  static List<String> _emptyKeywords() => const [];

  /// Bindings that open nothing — widget tests and the fake-page test.
  static SettingsPageBindings noop({
    bool isAndroidTv = false,
    bool isTelevision = false,
    bool showSwitchProfile = true,
    bool downloadLocationSupported = true,
    bool diagnosticExportVisible = true,
    bool showSupportDonation = false,
    bool iptvAppearanceSearchable = true,
    bool profileCommitted = true,
  }) {
    return SettingsPageBindings(
      openHomePage: _noop,
      openCollections: _noop,
      openExternalPlayer: _noop,
      openRemote: _noop,
      openSwitchProfile: _noop,
      openAddProfile: _noop,
      openEditProfile: _noop,
      openNavigation: _noop,
      openTorrentSettings: _noop,
      openFilterSettings: _noop,
      openProviderSettings: _noop,
      openQuickPlay: _noop,
      openDiscover: _noop,
      openDebrifyTv: _noop,
      openRecordings: _noop,
      openIptv: _noop,
      openDownloadLocation: _noop,
      clearDownloads: _noop,
      clearPlayback: _noop,
      createBackup: _noop,
      restoreBackup: _noop,
      exportDiagnosticLogs: _noop,
      resetApp: _noop,
      checkUpdates: _noop,
      openSupportDonation: _noop,
      openTextBrightness: _noop,
      openLaunchAnimation: _noop,
      openTvScreenSize: _noop,
      openTvRenderQuality: _noop,
      openTvHeroArtworkQuality: _noop,
      openTvHomeStyle: _noop,
      openDiscoverLayout: _noop,
      openTvSidebarStyle: _noop,
      openDesktopSidebarStyle: _noop,
      openIptvStyle: _noop,
      openDebrifyTvStyle: _noop,
      openPlayerGuideStyle: _noop,
      openPlayLoaderStyle: _noop,
      openTvPlayerControlsStyle: _noop,
      openDebrifyTvPlayerStyle: _noop,
      openPlayerDock: _noop,
      openThemeTokens: _noop,
      openLooks: _noop,
      openParentsGuideStyle: _noop,
      openDetailPageStyle: _noop,
      openProfileAppearance: _noop,
      openStremioTv: _noop,
      openAddons: _noop,
      isAndroidTv: isAndroidTv,
      isTelevision: isTelevision,
      showSwitchProfile: showSwitchProfile,
      downloadLocationSupported: downloadLocationSupported,
      diagnosticExportVisible: diagnosticExportVisible,
      showSupportDonation: showSupportDonation,
      iptvAppearanceSearchable: iptvAppearanceSearchable,
      profileCommitted: profileCommitted,
    );
  }
}
