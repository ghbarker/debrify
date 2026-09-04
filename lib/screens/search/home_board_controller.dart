import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/filtered_catalog_pager.dart';
import '../../services/home_collection_rows.dart';
import '../../services/home_collections_store.dart';
import '../../services/home/home_row_ids.dart';
import '../../services/home_row_order.dart';
import '../../services/storage_service.dart';

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch.
/// Copied from `search_screen.dart` `_kBoardBatchSize`.
const int kHomeBoardBatchSize = 8;

/// Live catalog types excluded from `random` hero draws. Copied from
/// `_resolveSpotlightHeroSource`: `'tv'` is what the Stremio-IPTV service
/// keys on; `'channel'`/`'radio'` are the spec's other live-ish types.
const Set<String> kHomeHeroLiveTypes = {'tv', 'channel', 'radio'};

/// Attempts cap so a wall of dead catalogs can't fan out unbounded hero
/// fetches. Copied from `_resolveSpotlightHeroSource`.
const int kHomeHeroMaxAttempts = 8;

/// Injected catalog page fetch. Production wraps [fetchFilteredPage] +
/// Stremio; tests stub pages. [minItems] is 8 for the hero reel and the
/// pager default (12) for board rows.
typedef HomeBoardCatalogFetch =
    Future<FilteredPage> Function(
      StremioAddon addon,
      StremioAddonCatalog catalog, {
      required int skip,
      Set<String>? seenIds,
      int minItems,
    });

/// Snapshot of Home-row prefs the board reload diffs against.
class HomeBoardSettingsSnapshot {
  const HomeBoardSettingsSnapshot({
    required this.disabled,
    required this.extras,
    required this.rowOrder,
    required this.heroSource,
    required this.collections,
    required this.hideWatched,
  });

  final Set<String> disabled;
  final List<HomeExtraRow> extras;
  final List<String> rowOrder;
  final HomeHeroSource heroSource;
  final List<HomeCollection> collections;
  final bool hideWatched;
}

/// What `_reloadForHomeSettings` does after the equality guards.
///
/// Card-orientation, merged-CW node sync, off-TV trailer prefs and the
/// default-view switch stay in the State — they are UI, not board data.
class HomeBoardReloadAction {
  const HomeBoardReloadAction({
    required this.nothingChanged,
    required this.requestBoardReload,
    required this.rerollHero,
    required this.reloadIptvLists,
  });

  final bool nothingChanged;
  final bool requestBoardReload;
  final bool rerollHero;
  final bool reloadIptvLists;
}

/// Result of [HomeBoardController.loadMoreRow].
class HomeBoardRowLoad {
  const HomeBoardRowLoad({
    this.skipped = false,
    this.section,
    this.fresh = const [],
  });

  /// True when the call no-op'd (search active, out of range, already
  /// loading/exhausted) before any fetch.
  final bool skipped;
  final CatalogSection? section;
  final List<StremioMeta> fresh;
}

/// Home board data layer extracted from `search_screen.dart` (G1 step 1).
///
/// Owns generation/cancel tokens so a reload still drops in-flight batches.
/// UI (trailers, TV stages, catalog search, `_openItem`, FocusNodes) stays
/// in the State, which [listen]s and rebuilds.
class HomeBoardController extends ChangeNotifier {
  HomeBoardController({
    required this.fetchCatalog,
    Random? random,
    bool Function()? isLive,
  }) : _random = random ?? Random(),
       _isLive = isLive;

  final HomeBoardCatalogFetch fetchCatalog;
  final Random _random;
  final bool Function()? _isLive;

  bool _disposed = false;

  bool get _live => !_disposed && (_isLive?.call() ?? true);

  /// Board load generation. [_load] is re-entrant (Home Rows save,
  /// integration connect/disconnect) and mutates shared state
  /// ([boardRefs]/[boardCursor]/[homeSections]); every await inside the
  /// load pipeline re-checks this so a superseded load can neither apply its
  /// stale sections nor advance the new load's cursor.
  int boardLoadGen = 0;

  /// Enumerated (addon, catalog) pairs. Cheap — manifest metadata, no network.
  final List<(StremioAddon, StremioAddonCatalog)> boardRefs = [];
  int boardCursor = 0;

  /// Homepage cache of catalog + list + collection rows.
  List<CatalogSection> homeSections = [];

  Set<String> homeDisabled = {};
  List<HomeExtraRow> homeExtras = const [];
  List<String> homeRowOrder = const [];
  List<HomeCollection> homeCollections = const [];
  String homeCollectionsSig = '';
  bool hideWatched = false;

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Not the trailer overlay widgets.
  HomeHeroSource heroSource = (mode: HomeHeroSourceMode.random, ids: const []);

  /// The hero reel fetched from the user's chosen source (`random`/`custom`
  /// modes). Null in `auto` mode, while the fetch is in flight, and when every
  /// candidate came up dead — all of which fall back to the first non-empty
  /// board row.
  CatalogSection? spotlightHeroOverride;

  /// Guards [resolveSpotlightHeroSource] against overlapping runs (a Home
  /// Rows save landing mid-load): only the newest run may commit.
  int heroSourceResolveGen = 0;

  /// Bump the load generation so in-flight batches no-op. Returns the new gen.
  int beginLoad() => ++boardLoadGen;

  bool isCurrent(int gen) => gen == boardLoadGen;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// `addonId:type:catalogId`. Same grammar as search_screen `_catalogRefRowId`.
  static String catalogRefRowId((StremioAddon, StremioAddonCatalog) ref) =>
      HomeRowIds.catalog(ref.$1.id, ref.$2.type, ref.$2.id);

  /// Enumerate browsable, un-hidden, un-claimed catalogs. Copied from `_load`.
  static List<(StremioAddon, StremioAddonCatalog)> enumerateBoardRefs({
    required List<StremioAddon> addons,
    required Set<String> disabled,
    required List<HomeCollection> collections,
  }) {
    final claimed = HomeCollectionsStore.claimedCatalogKeys(
      collections,
      addons,
    );
    return [
      for (final a in addons)
        for (final c in a.catalogs)
          if (c.isBrowsable &&
              !disabled.contains(HomeRowIds.catalog(a.id, c.type, c.id)) &&
              !claimed.contains(HomeRowIds.catalog(a.id, c.type, c.id)))
            (a, c),
    ];
  }

  /// Replace [boardRefs] and reset the cursor. When [applySavedOrder] is
  /// true, the saved Home order is applied (Home board only).
  void replaceBoardRefs(
    List<(StremioAddon, StremioAddonCatalog)> refs, {
    required bool applySavedOrder,
  }) {
    boardRefs
      ..clear()
      ..addAll(
        applySavedOrder
            ? HomeRowOrder.apply(refs, homeRowOrder, catalogRefRowId)
            : refs,
      );
    boardCursor = 0;
  }

  /// Every enabled imported collection as a board row (hidden rows skipped).
  /// Copied from `_buildCollectionSections`.
  static List<HomeCollectionSection> buildCollectionSections({
    required List<HomeCollection> collections,
    required Set<String> disabled,
  }) => [
    for (final c in collections)
      if (c.enabled && c.folders.isNotEmpty && !disabled.contains(c.rowId))
        HomeCollectionSection(collection: c),
  ];

  /// Assemble the first paint of Home `_sections`. Copied from `_load`.
  ///
  /// Imported collections follow Nuvio's order: pinned ones lead the board,
  /// the rest sit after the tracker list rows and before every addon catalog
  /// row. Do not regroup by family — H1-fix: pinned collections must lead
  /// tracker lists in the section band.
  static List<CatalogSection> assembleHomeSections({
    required List<HomeCollectionSection> collectionRows,
    required List<CatalogSection> listRows,
    required List<CatalogSection> firstBatch,
  }) => [
    for (final s in collectionRows)
      if (s.collection.pinToTop) s,
    ...listRows,
    for (final s in collectionRows)
      if (!s.collection.pinToTop) s,
    ...firstBatch,
  ];

  /// Fetch the next batch of catalog rows from [boardCursor], skipping over any
  /// runs of empty catalogs, and return the non-empty sections (advancing the
  /// cursor as it goes). Empty result ⇒ the board is exhausted — or [gen] went
  /// stale (a newer load owns the cursor now; stop without touching it).
  ///
  /// Quirk: a batch that was already in flight when [gen] went stale is still
  /// returned if non-empty; callers must re-check [isCurrent] before applying.
  Future<List<CatalogSection>> fetchBoardBatchUntilNonEmpty(int gen) async {
    while (gen == boardLoadGen && boardCursor < boardRefs.length) {
      final batch = await fetchBoardBatch(kHomeBoardBatchSize, gen);
      if (batch.isNotEmpty) return batch;
    }
    return const [];
  }

  /// Fetch exactly one batch of up to [n] catalog rows in parallel, advancing
  /// [boardCursor], and return the non-empty ones (order preserved). No-ops
  /// when [gen] is stale so a superseded load can't advance the fresh load's
  /// cursor.
  ///
  /// Quirk: [gen] is checked only at the start. The cursor advances *before*
  /// the fetches; a stale [gen] after that still returns the pages (callers
  /// drop them). Empty / throwing catalogs are omitted, not placeholders.
  Future<List<CatalogSection>> fetchBoardBatch(int n, int gen) async {
    if (gen != boardLoadGen) return const [];
    final end = (boardCursor + n).clamp(0, boardRefs.length);
    final slice = boardRefs.sublist(boardCursor, end);
    boardCursor = end;
    final results = await Future.wait(
      slice.map((ref) async {
        final (addon, catalog) = ref;
        try {
          // With hide-watched on, the pager tops the row up across windows so
          // an all-watched first page doesn't read as an empty catalog.
          final page = await fetchCatalog(
            addon,
            catalog,
            skip: 0,
            minItems: 12,
          );
          if (page.items.isEmpty) return null;
          return CatalogSection(
            title: CatalogSection.rowTitle(catalog),
            addon: addon,
            catalog: catalog,
            // Keep the whole first page; more pages stream in on horizontal scroll.
            items: page.items.toList(),
            // Past the addon's raw window(s), not the post-filter count, so
            // paging is aligned from the very first fetch.
            nextSkip: page.nextSkip,
            exhausted: page.exhausted,
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<CatalogSection>().toList();
  }

  /// Fetch the next page for a single catalog row and append it in place, so
  /// rows grow without bound as the user scrolls right (Stremio-style). Only
  /// board rows paginate; search-result rows are single-shot. Safe to call
  /// repeatedly — [CatalogSection.loadingMore]/[CatalogSection.exhausted] guard
  /// re-entrancy and the end of the catalog.
  ///
  /// FocusNodes, stage-right completion and bound-source refresh stay in the
  /// State. [notifyLoadingGuard] is false on Android TV so the tail spinner
  /// doesn't rebuild on the keypress that crossed the row-end threshold.
  Future<HomeBoardRowLoad> loadMoreRow({
    required List<CatalogSection> sections,
    required int rowIndex,
    required bool catalogSearchActive,
    bool notifyLoadingGuard = true,
  }) async {
    // While a catalog search is active, `sections` holds search results, which
    // don't paginate — leave them alone.
    if (catalogSearchActive) return const HomeBoardRowLoad(skipped: true);
    if (rowIndex < 0 || rowIndex >= sections.length) {
      return const HomeBoardRowLoad(skipped: true);
    }
    final section = sections[rowIndex];
    if (section.loadingMore || section.exhausted) {
      return const HomeBoardRowLoad(skipped: true);
    }
    // Android TV: flip the guard silently. The setState exists to show the
    // classic row's tail spinner, but it fires on the exact keypress that
    // crossed the row-end threshold — a full-screen rebuild landing on the
    // input frame, which an Amlogic box renders as the cursor hitching every
    // time a row pages. The spinner is a nicety; the page landing repaints
    // either way.
    section.loadingMore = true;
    if (notifyLoadingGuard) notifyListeners();
    try {
      // Dedup against what we already have: some addons return valid ids but
      // repeat entries, and some ignore `skip` entirely. The pager advances
      // `skip` by the addon's RAW counts so paging never under-advances into a
      // false "exhausted", and with hide-watched on it tops the window up so a
      // page of watched titles doesn't end the row early.
      final seen = section.items.map((m) => m.id).toSet();
      final page = await fetchCatalog(
        section.addon,
        section.catalog,
        skip: section.nextSkip,
        seenIds: seen,
        minItems: 12,
      );
      if (!_live) return HomeBoardRowLoad(section: section);
      // The row may have been swapped out (a search started) while in flight.
      if (rowIndex >= sections.length ||
          !identical(sections[rowIndex], section)) {
        return HomeBoardRowLoad(section: section);
      }
      section.nextSkip = page.nextSkip;
      if (page.exhausted) section.exhausted = true;
      final fresh = page.items;
      if (fresh.isEmpty) {
        // Only duplicates, or the addon ignores skip — end of the row.
        section.exhausted = true;
        return HomeBoardRowLoad(section: section);
      }
      section.items.addAll(fresh);
      notifyListeners();
      return HomeBoardRowLoad(section: section, fresh: fresh);
    } catch (_) {
      // Transient fetch failure — leave the row as-is so a later scroll retries.
      return HomeBoardRowLoad(section: section);
    } finally {
      section.loadingMore = false;
      if (_live) notifyListeners();
    }
  }

  /// Candidates for the Spotlight hero reel. Copied from
  /// `_resolveSpotlightHeroSource`.
  ///
  /// Candidates come from the FULL browsable set, not [boardRefs] — hiding a
  /// catalog's row on the board must not blank a hero pinned to that same
  /// catalog. `random` drops live types; an EXPLICIT custom pick of such a
  /// catalog is left alone. Stored picks that no longer resolve simply drop
  /// out; they are NOT removed from the pref.
  ///
  /// `auto` returns an empty list so the caller clears the override (the
  /// auto fallback).
  static List<(StremioAddon, StremioAddonCatalog)> heroCandidates({
    required HomeHeroSource source,
    required List<StremioAddon> addons,
  }) {
    if (source.mode == HomeHeroSourceMode.auto) return const [];
    final all = [
      for (final a in addons)
        for (final c in a.catalogs)
          if (c.isBrowsable) (a, c),
    ];
    if (source.mode == HomeHeroSourceMode.random) {
      // Random draws TITLES only. Live catalogs — 'tv' is what the
      // Stremio-IPTV service itself keys on, 'channel'/'radio' are the
      // spec's other live-ish types — serve channel logos as their art, so
      // the reel cover-crops a wordmark to a full screen (TvVoo's logo,
      // full-bleed, was the report). An EXPLICIT custom pick of such a
      // catalog is left alone: choosing it by name is a deliberate act.
      return [
        for (final ref in all)
          if (!kHomeHeroLiveTypes.contains(ref.$2.type.toLowerCase())) ref,
      ];
    }
    // Stored picks that no longer resolve (addon uninstalled, catalog
    // gone from its manifest) simply drop out; they are NOT removed from
    // the pref, so reinstalling the addon brings the pick back.
    final byId = {
      for (final (a, c) in all) HomeRowIds.catalog(a.id, c.type, c.id): (a, c),
    };
    return [
      for (final id in source.ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  /// Fetch the hero reel for the current [heroSource] pref.
  ///
  /// Candidates are shuffled so `random` mode and a multi-pick `custom`
  /// re-roll on every board load; the first candidate that returns items
  /// wins. Attempts are capped so a wall of dead catalogs can't fan out
  /// unbounded fetches; exhausting the cap (or the candidates) clears the
  /// override, which IS the auto fallback.
  Future<void> resolveSpotlightHeroSource(List<StremioAddon> addons) async {
    final gen = ++heroSourceResolveGen;
    final source = heroSource;
    if (source.mode != HomeHeroSourceMode.auto) {
      final candidates = heroCandidates(source: source, addons: addons);
      candidates.shuffle(_random);
      var attempts = 0;
      for (final (addon, catalog) in candidates) {
        if (attempts++ >= kHomeHeroMaxAttempts) break;
        if (!_live || gen != heroSourceResolveGen) return;
        try {
          final page = await fetchCatalog(addon, catalog, skip: 0, minItems: 8);
          if (!_live || gen != heroSourceResolveGen) return;
          if (page.items.isEmpty) continue;
          spotlightHeroOverride = CatalogSection(
            title: CatalogSection.rowTitle(catalog),
            addon: addon,
            catalog: catalog,
            items: page.items.toList(),
            nextSkip: page.nextSkip,
          );
          notifyListeners();
          return;
        } catch (_) {
          // Dead addon or catalog — try the next candidate.
        }
      }
    }
    // Auto mode, no usable candidate, or every attempt failed — drop any
    // stale override so the reel falls back rather than pinning old prefs.
    if (!_live || gen != heroSourceResolveGen) return;
    if (spotlightHeroOverride != null) {
      spotlightHeroOverride = null;
      notifyListeners();
    }
  }

  /// Diff incoming Home-row prefs against the last applied snapshot.
  /// Copied from `_reloadForHomeSettings` (the board-data half).
  ///
  /// Titles participate too: a stored rename must re-render the row header.
  /// Diffed per family: `iptvlist:` extras feed the favourites-family rows,
  /// everything else feeds the board pipeline — so toggling an IPTV list
  /// row must not refetch every addon catalog, and vice versa.
  ///
  /// [isHomeBoard] is `!searchMode && !discoverMode`. Row-order and hero
  /// changes only reload/reroll on the Home board.
  HomeBoardReloadAction diffAndApplySettings(
    HomeBoardSettingsSnapshot incoming, {
    required bool isHomeBoard,
  }) {
    final collectionsSig = HomeCollectionsStore.signatureOf(
      incoming.collections,
    );
    final collectionsUnchanged = collectionsSig == homeCollectionsSig;
    final hideWatchedUnchanged = incoming.hideWatched == hideWatched;
    final disabledUnchanged =
        incoming.disabled.length == homeDisabled.length &&
        incoming.disabled.containsAll(homeDisabled);
    final heroSourceUnchanged =
        incoming.heroSource.mode == heroSource.mode &&
        listEquals(incoming.heroSource.ids, heroSource.ids);
    final rowOrderUnchanged = HomeRowOrder.equals(
      incoming.rowOrder,
      homeRowOrder,
    );
    List<HomeExtraRow> family(List<HomeExtraRow> rows, {required bool iptv}) =>
        [
          for (final r in rows)
            if (HomeExtraRowIds.isIptv(r.id) == iptv) r,
        ];
    bool sameRows(List<HomeExtraRow> a, List<HomeExtraRow> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => a[i].id == b[i].id && a[i].title == b[i].title,
        ).every((same) => same);
    final boardExtrasUnchanged = sameRows(
      family(incoming.extras, iptv: false),
      family(homeExtras, iptv: false),
    );
    final iptvExtrasUnchanged = sameRows(
      family(incoming.extras, iptv: true),
      family(homeExtras, iptv: true),
    );
    if (disabledUnchanged &&
        boardExtrasUnchanged &&
        iptvExtrasUnchanged &&
        rowOrderUnchanged &&
        heroSourceUnchanged &&
        collectionsUnchanged &&
        hideWatchedUnchanged) {
      return const HomeBoardReloadAction(
        nothingChanged: true,
        requestBoardReload: false,
        rerollHero: false,
        reloadIptvLists: false,
      );
    }
    homeDisabled = incoming.disabled;
    homeExtras = incoming.extras;
    homeRowOrder = incoming.rowOrder;
    heroSource = incoming.heroSource;
    homeCollections = incoming.collections;
    homeCollectionsSig = collectionsSig;
    hideWatched = incoming.hideWatched;
    notifyListeners();
    final requestBoardReload =
        !disabledUnchanged ||
        !boardExtrasUnchanged ||
        !collectionsUnchanged ||
        !hideWatchedUnchanged ||
        (!rowOrderUnchanged && isHomeBoard);
    final rerollHero =
        !requestBoardReload && !heroSourceUnchanged && isHomeBoard;
    return HomeBoardReloadAction(
      nothingChanged: false,
      requestBoardReload: requestBoardReload,
      rerollHero: rerollHero,
      reloadIptvLists: !iptvExtrasUnchanged,
    );
  }
}
