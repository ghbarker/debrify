import '../../services/storage_service.dart';

/// Shell contracts for the three [SearchScreen] variants (Home / Search /
/// Discover). Copied from `search_screen.dart` getters and init/build
/// branches so G1 step 4 can pin them before the screens split.
///
/// Frozen MainTab indices: Home 15, Search 17, Discover 18.

/// Which nav tab this instance backs, for the TV content-focus handler.
/// Copied from `_SearchScreenState._tabIndex`.
///
/// Quirk: [searchMode] wins when both flags are true (same `?:` order).
int searchScreenTabIndex({
  required bool searchMode,
  required bool discoverMode,
}) => searchMode ? 17 : (discoverMode ? 18 : 15);

/// Discriminates the three variants so a preserved keyword search only
/// restores into the same kind of tab it came from.
/// Copied from `_SearchScreenState._variantKey`.
///
/// Quirk: [searchMode] wins when both flags are true.
String searchScreenVariantKey({
  required bool searchMode,
  required bool discoverMode,
}) => searchMode
    ? 'search'
    : discoverMode
    ? 'discover'
    : 'board';

/// Analytics screen-view name. Copied from `initState`'s
/// `AnalyticsService.screenView(...)`.
///
/// Quirk: [searchMode] wins when both flags are true.
String searchScreenAnalyticsName({
  required bool searchMode,
  required bool discoverMode,
}) => searchMode
    ? 'search'
    : discoverMode
    ? 'discover'
    : 'home';

/// Keyword restore is skipped only on Home TV (chrome-free board).
/// Copied from `initState`:
/// `widget.isTelevision && !searchMode && !discoverMode ? false : _restoreKeywordState()`.
bool searchScreenRestoresKeyword({
  required bool isTelevision,
  required bool searchMode,
  required bool discoverMode,
}) => !(isTelevision && !searchMode && !discoverMode);

/// Home only runs the board pipeline (`_load` + CW / tracker / favs).
/// Search and Discover set `_loading = false` and skip it.
/// Copied from the `if (searchMode) / else if (discoverMode) / else` init tail.
bool searchScreenLoadsHomeBoard({
  required bool searchMode,
  required bool discoverMode,
}) => !searchMode && !discoverMode;

/// Search and Discover skip `_load()`, which is what clears `_loading`.
/// Copied from the same init tail (`_loading = false` in both branches).
bool searchScreenClearsLoadingWithoutBoard({
  required bool searchMode,
  required bool discoverMode,
}) => searchMode || discoverMode;

/// Discover primes CW / Trakt / Simkl / MDBList rows and loads addons.
/// Copied from the `else if (discoverMode)` init tail.
///
/// Quirk: [searchMode] wins when both flags are true, so Discover priming
/// does not run.
bool searchScreenPrimesDiscoverRows({
  required bool searchMode,
  required bool discoverMode,
}) => !searchMode && discoverMode;

/// Catalog-detail handoff from another tab (Calendar). Home only.
/// Copied from `initState`'s `registerCatalogDetailOpenHandler` guard.
bool searchScreenClaimsPendingCatalogDetail({
  required bool searchMode,
  required bool discoverMode,
}) => !searchMode && !discoverMode;

/// Dedicated Search tab Back handler (`MainPageBridge` key `'search'`).
bool searchScreenRegistersSearchBackHandler({required bool searchMode}) =>
    searchMode;

/// Unified (non-TV) catalog Sources bar under the field.
/// Copied from `_buildUnifiedCatalogSourcesBar`'s early return
/// (`isTelevision || searchMode` → shrink).
///
/// Discover phone is `!tv && !searchMode`, so the *predicate* is true even
/// though Discover's build never mounts the bar.
bool searchScreenShowsUnifiedCatalogSourcesBar({
  required bool isTelevision,
  required bool searchMode,
}) => !isTelevision && !searchMode;

/// Focus listener that drives the unified Sources bar.
/// Copied from `initState`: `!isTelevision && !searchMode`.
///
/// Quirk: Discover phone registers this listener even though it never
/// builds `_buildUnifiedCatalogSourcesBar`.
bool searchScreenListensForCatalogSourcesFocus({
  required bool isTelevision,
  required bool searchMode,
}) => !isTelevision && !searchMode;

/// Spotlight search-field latch. Home phone only.
/// Copied from `initState`: `!isTelevision && !searchMode && !discoverMode`.
bool searchScreenLatchesSpotlightSearchSheet({
  required bool isTelevision,
  required bool searchMode,
  required bool discoverMode,
}) => !isTelevision && !searchMode && !discoverMode;

/// TV hero trailer shell (glass scaffold, sidebar relays, takeover keys).
/// Copied from `_heroTrailerActive` minus the low-memory TVOS gate (that
/// stays on the host — not a Search-vs-Discover shell difference).
bool searchScreenHeroTrailerActive({
  required bool isTelevision,
  required bool searchMode,
  required bool discoverMode,
}) => isTelevision && !searchMode && !discoverMode;

/// Off-TV Spotlight hero trailer eligibility. Home phone/desktop only.
/// Copied from `_heroTrailerOffTvEligible`.
bool searchScreenHeroTrailerOffTvEligible({
  required bool isTelevision,
  required bool searchMode,
  required bool discoverMode,
}) => !isTelevision && !searchMode && !discoverMode;

/// Whether the hero spotlight is live. TV-only; Search only once there
/// are results. Copied from `_heroActive`.
bool searchScreenHeroActive({
  required bool isTelevision,
  required bool searchMode,
  required bool catalogQueryNonEmpty,
}) => isTelevision && (!searchMode || catalogQueryNonEmpty);

/// DPAD-up from the top row focuses the search field only on Search.
/// Copied from `_leaveBoardTop`.
bool searchScreenLeaveBoardTopFocusesField({required bool searchMode}) =>
    searchMode;

/// Discover content focus lands on the Source dropdown.
/// Copied from `_focusContent`'s leading `if (discoverMode)` branch.
bool searchScreenFocusesDiscoverSource({required bool discoverMode}) =>
    discoverMode;

/// Home expanded See-All walls share Discover card-detail prefs.
/// Search and Discover skip the wrap. Copied from
/// `_withHomeExpandedCardSettings`.
bool searchScreenAppliesHomeExpandedCardSettings({
  required bool searchMode,
  required bool discoverMode,
}) => !searchMode && !discoverMode;

/// Rail header height. Copied from `_railHeaderH`.
double searchScreenRailHeaderHeight({required bool isTelevision}) =>
    isTelevision ? 44.0 : 52.0;

/// TV hero band upper clamp. Search keeps a compact strip.
/// Copied from `_tvHeroBudget`.
double searchScreenTvHeroBudgetMax({required bool searchMode}) =>
    searchMode ? 180.0 : 440.0;

/// Discover phone: always the full-width panel. TV: two-pane unless the
/// canvas is too narrow (<720) or too short (<420).
/// Copied from `_buildDiscover`. Stage layouts (`_discStage`) stay on the
/// host for G1 step 5.
bool discoverUsesFullWidthPanel({
  required bool isTelevision,
  required double maxWidth,
  required double maxHeight,
}) => !isTelevision || maxWidth < 720 || maxHeight < 420;

/// Fixed Discover sources; installed addons are appended dynamically
/// (key `'a:{addonId}'`). Copied from `_discCw` / `_discTrakt` /
/// `_discSimkl` / `_discMdblist` / `_discAddonPrefix`.
const String kDiscoverSourceCw = 'cw';
const String kDiscoverSourceTrakt = 'trakt';
const String kDiscoverSourceSimkl = 'simkl';
const String kDiscoverSourceMdblist = 'mdblist';
const String kDiscoverSourceAddonPrefix = 'a:';

/// Resolve the Discover landing source after prefs + addon inventory.
/// Copied from `_loadDiscoverAddons` (the value, not the apply-timing).
/// Apply-timing stays [discoverLandingLoadIsCurrent] on the host.
String resolveDiscoverLandingSource({
  required String defaultSource,
  required String lastSource,
  required bool mdblistEnabled,
  required Iterable<String> browsableAddonIds,
}) {
  var landing = defaultSource == StorageService.discoverDefaultRememberLast
      ? lastSource
      : defaultSource;
  final fixedSource =
      landing == kDiscoverSourceCw ||
      landing == kDiscoverSourceTrakt ||
      landing == kDiscoverSourceSimkl ||
      (mdblistEnabled && landing == kDiscoverSourceMdblist);
  final addonAvailable =
      landing.startsWith(kDiscoverSourceAddonPrefix) &&
      browsableAddonIds.any(
        (id) => '$kDiscoverSourceAddonPrefix$id' == landing,
      );
  if (!fixedSource && !addonAvailable) landing = kDiscoverSourceCw;
  return landing;
}

/// One Source-dropdown entry. Copied from `StremioDropdownOption` pairs
/// in `_buildDiscoverPanel`.
class DiscoverSourceOption {
  const DiscoverSourceOption(this.value, this.label);
  final String value;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is DiscoverSourceOption &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// Discover Source dropdown options.
/// Copied from `_buildDiscoverPanel`: CW / Trakt / Simkl always; MDBList
/// only when the compile flag is on AND (connected OR already the active
/// source); then one entry per browsable addon (`a:{id}`).
List<DiscoverSourceOption> discoverSourceDropdownOptions({
  required bool mdblistEnabled,
  required bool mdblistAuthenticated,
  required String currentSource,
  required List<({String id, String name})> addons,
}) {
  return [
    const DiscoverSourceOption(kDiscoverSourceCw, 'Continue Watching'),
    const DiscoverSourceOption(kDiscoverSourceTrakt, 'Trakt'),
    const DiscoverSourceOption(kDiscoverSourceSimkl, 'Simkl'),
    if (mdblistEnabled &&
        (mdblistAuthenticated || currentSource == kDiscoverSourceMdblist))
      const DiscoverSourceOption(kDiscoverSourceMdblist, 'MDBList'),
    for (final a in addons)
      DiscoverSourceOption('$kDiscoverSourceAddonPrefix${a.id}', a.name),
  ];
}

/// Controllers the shared host constructs for every variant.
///
/// Discover still constructs [CatalogSearchController] even though it
/// skips catalog search. Search still constructs [HomeBoardController]
/// even though it skips `_load()`. Item open is [TitleOpener.open]
/// constructed inside `_openItem` (not a State field) — G1 step 3.
const List<String> kSearchScreenSharedControllerNames = <String>[
  'HomeBoardController',
  'CatalogSearchController',
  'TitleOpener',
];
