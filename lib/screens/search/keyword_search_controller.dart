import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/torrent.dart';
import '../../models/torrent_filter_state.dart';
import '../../services/cloud/cloud_provider_registry.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/profiles/profile_session_memory.dart';
import '../../services/storage_service.dart';
import '../../services/torrent_service.dart';
import '../../utils/torrent_filter_matcher.dart';

/// Snapshot of a completed keyword search, kept alive across a same-profile
/// tab rebuild. Promoted from `_KwPreservedState` (G1'-3).
class KwPreservedState {
  final String variant;
  final String query;
  final List<Torrent> all;
  final List<Torrent> results;
  final TorrentFilterState filters;
  final String sort;
  final bool sortAsc;
  final Map<String, List<String>> cache;
  final bool cachedOnly;
  final Map<String, int> directCounts;
  final Map<String, int> torrentCounts;
  final Set<String> selectedDirect;
  final Set<String> selectedTorrent;
  final String? sourceTab;
  final double scrollOffset;
  const KwPreservedState({
    required this.variant,
    required this.query,
    required this.all,
    required this.results,
    required this.filters,
    required this.sort,
    required this.sortAsc,
    required this.cache,
    required this.cachedOnly,
    required this.directCounts,
    required this.torrentCounts,
    required this.selectedDirect,
    required this.selectedTorrent,
    required this.sourceTab,
    required this.scrollOffset,
  });
}

/// Keyword torrent-search data layer extracted from `search_screen.dart`
/// (G1'-3). Owns query, streamed batches, freeze/adopt, selection, filters.
class KeywordSearchController extends ChangeNotifier {
  KeywordSearchController({
    bool Function()? isLive,
    this.onCancelSubmitFocus,
    this.onCompleteSubmitFocus,
    this.onRestoreQuery,
  }) : _isLive = isLive;

  final bool Function()? _isLive;
  final VoidCallback? onCancelSubmitFocus;
  final void Function(FocusNode target)? onCompleteSubmitFocus;
  final void Function(String query)? onRestoreQuery;

  bool _disposed = false;

  bool get _live => !_disposed && (_isLive?.call() ?? true);

  void _emit([VoidCallback? fn]) {
    fn?.call();
    if (!_disposed) notifyListeners();
  }

  // Keyword torrent-search state (submit-based).
  bool kwLoading = false;
  String? kwError;
  String kwQuery = '';
  List<Torrent> kwAll = []; // unfiltered results from the last search
  List<Torrent> kwResults = []; // filtered + sorted view actually rendered
  final List<FocusNode> kwNodes = [];
  // Keyboard/DPAD focus targets for the keyword toolbar pills (Sort / Filters /
  // Providers / Sources / Select). A fixed pool of 5 covers the most pills ever
  // shown.
  final List<FocusNode> kwToolbarNodes = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'kw_tb_$i'),
  );
  TorrentFilterState kwFilters = const TorrentFilterState.empty();
  String kwSort = 'relevance';
  // Sort direction for kwSort (ignored for 'relevance', which is engine order).
  // Defaults follow each field's natural direction; the sort dialog can flip it.
  bool kwSortAsc = false;
  Map<String, List<String>> kwCache = {}; // infohash(lower) → ['TB','PM']

  // Provider (stream-type) multi-select filter, ported from the old search
  // screen: results are grouped into "Direct" (direct/external URL streams) and
  // "Torrent" providers by their [Torrent.source], each independently filterable
  // by which sources are ticked. Empty count maps mean "no such group".
  Map<String, int> kwDirectCounts = {}; // source → count (direct/external)
  Map<String, int> kwTorrentCounts = {}; // source → count (torrents)
  Set<String> kwSelectedDirect = {};
  Set<String> kwSelectedTorrent = {};

  /// True when the results list is being narrowed to TorBox-cached torrents
  /// only (TorBox is the sole usable debrid provider and its cache-check is on)
  /// — mirrors the old screen's `_showingTorboxCachedOnly`. Drives the banner.
  bool kwCachedOnly = false;

  // Bulk-selection state for keyword results (mirrors Home's multi-select).
  bool kwSelectionMode = false;
  final Set<String> kwSelected = {}; // selected torrent infohashes

  /// Monotonic token so a slow earlier keyword search can't clobber a newer one.
  int kwSearchToken = 0;

  /// Infohashes already dispatched to a provider cache-check for the current
  /// keyword search. Lets each streaming batch check only its fresh hashes.
  final Set<String> kwCacheChecked = {};

  /// Whether a TorBox cache-check has successfully run this keyword search —
  /// the precondition for cached-only mode (never hide rows on a thrown check).
  bool kwTbRan = false;

  /// In-flight per-batch cache-check futures for the current search. The
  /// completion sweep awaits these so cached-only mode is decided only once
  /// every batch's badges have landed.
  final List<Future<void>> kwPendingChecks = [];

  // Cache-check config, resolved ONCE per keyword search (freshly re-read each
  // search, then reused across its streaming batches — no per-batch storage
  // reads). Same gating as Home: pref on AND integration on AND key present.
  bool kwTbOn = false;
  bool kwPmOn = false;
  String? kwTbKey;
  String? kwPmKey;
  bool kwOtherProviderActive = false;

  /// Reads the cache-check gating and whether any usable non-TorBox provider
  /// is active. Awaited at the top of each search so streaming batch checks
  /// see up-to-date settings.
  Future<void> loadCacheConfig() async {
    final r = await Future.wait([
      StorageService.getTorboxCacheCheckEnabled(),
      StorageService.getTorboxIntegrationEnabled(),
      StorageService.getTorboxApiKey(),
      StorageService.getPremiumizeCacheCheckEnabled(),
      StorageService.getPremiumizeIntegrationEnabled(),
      StorageService.getPremiumizeApiKey(),
      StorageService.getApiKey(),
      StorageService.getRealDebridIntegrationEnabled(),
      StorageService.getAllDebridApiKey(),
      StorageService.getAllDebridIntegrationEnabled(),
      StorageService.getPikPakEnabled(),
    ]);
    final tbKey = r[2] as String?;
    final pmKey = r[5] as String?;
    final rdKey = r[6] as String?;
    final adKey = r[8] as String?;
    kwTbOn = (r[0] as bool) && (r[1] as bool) && (tbKey?.isNotEmpty ?? false);
    kwPmOn = (r[3] as bool) && (r[4] as bool) && (pmKey?.isNotEmpty ?? false);
    kwTbKey = tbKey;
    kwPmKey = pmKey;
    final rdActive = (r[7] as bool) && (rdKey?.isNotEmpty ?? false);
    final pmActive = (r[4] as bool) && (pmKey?.isNotEmpty ?? false);
    final adActive = (r[9] as bool) && (adKey?.isNotEmpty ?? false);
    final pikpakActive = r[10] as bool;
    kwOtherProviderActive = rdActive || pmActive || adActive || pikpakActive;
  }

  // ── Streaming keyword search (per-engine batches, Sources-list parity) ──
  /// Raw per-engine batches accumulated this search; merged provisionally so
  /// first rows paint as soon as the fastest engine answers.
  final List<List<Torrent>> kwBatches = [];

  /// True while the awaited search is still in flight (drives the "still
  /// searching" strip). Distinct from [kwLoading], which only covers the
  /// full-screen loader up to the FIRST batch.
  bool kwSearching = false;

  /// Set on the first real user interaction (scroll drag, row DPAD nav, row
  /// tap/long-press, toolbar use) — later arrivals then park in [kwPending]
  /// behind the "+N new results" pill instead of reshuffling the list.
  bool kwStreamFrozen = false;

  /// Full (unfiltered) result set parked while frozen; adopted by the pill,
  /// any toolbar action, or a source-tab tap.
  List<Torrent>? kwPending;

  /// DPAD focus for the "+N new results" pill.
  final FocusNode kwPillFocus = FocusNode(debugLabel: 'kw_pill');

  /// DPAD focus for the pre-search "Sources" button (shown in the empty
  /// keyword state before a query). Without its own node it's a bare InkWell
  /// unreachable by the remote — you couldn't pick sources before searching.
  final FocusNode kwSourcesBtnFocus = FocusNode(debugLabel: 'kw_sources_btn');

  /// Source tab strip (All / per-source), single-select on top of the
  /// Providers multi-select. Null = All.
  String? kwSourceTab;
  final List<FocusNode> kwTabNodes = [];

  /// Provider-group keys ('d:src' / 't:src') already offered this search — a
  /// NEW source auto-selects into the provider filter, but a source the user
  /// unticked stays unticked when a later batch re-reports it.
  final Set<String> kwProviderSeen = {};

  /// Scroll controller for the keyword results list, so we can preserve/restore
  /// the scroll position across a tab switch (see [KwPreservedState]).
  final ScrollController kwScroll = ScrollController();

  /// Last observed keyword-list scroll offset, captured live (the controller is
  /// detached by the time [dispose] runs, so we can't read it there).
  double kwLastScroll = 0;

  /// Set on restore; the keyword list jumps here once laid out, then clears.
  double? pendingKwScroll;

  /// Snapshot of the most recently disposed keyword search, kept alive across
  /// a same-profile tab rebuild. The holder rejects content from another
  /// profile/session and participates in profile lifecycle cleanup.
  static final ProfileSessionMemory<KwPreservedState> kwPreserved =
      ProfileSessionMemory<KwPreservedState>();

  /// Whether the keyword results toolbar (Sort/Filters/Sources/…) is on-screen.
  bool get kwToolbarVisible =>
      !kwLoading && kwError == null && kwQuery.isNotEmpty;

  /// Whether the pre-search "Sources" button is on-screen.
  bool get kwSourcesButtonVisible =>
      !kwLoading && kwError == null && kwQuery.isEmpty;

  /// Restore a preserved keyword search into this instance if one exists for
  /// this variant. Returns true when a restore happened. Called from initState
  /// (pre-first-build) so direct field assignment — not setState — is correct.
  bool restore(ProfileSessionOwner owner, String variant) {
    final snap = kwPreserved.take(
      owner,
      where: (value) => value.variant == variant && value.query.isNotEmpty,
    );
    if (snap == null) {
      return false;
    }
    // The keyword surface is per-profile; a snapshot saved under a profile
    // that had it must not restore into one that doesn't.
    if (!ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)) {
      return false;
    }
    kwQuery = snap.query;
    kwAll = snap.all;
    kwResults = snap.results;
    kwFilters = snap.filters;
    kwSort = snap.sort;
    kwSortAsc = snap.sortAsc;
    kwCache = snap.cache;
    kwCachedOnly = snap.cachedOnly;
    kwDirectCounts = snap.directCounts;
    kwTorrentCounts = snap.torrentCounts;
    kwSelectedDirect = snap.selectedDirect;
    kwSelectedTorrent = snap.selectedTorrent;
    kwSourceTab = snap.sourceTab;
    onRestoreQuery?.call(snap.query);
    disposeNodes();
    for (var i = 0; i < snap.results.length; i++) {
      kwNodes.add(FocusNode(debugLabel: 'kw_$i'));
    }
    syncTabNodes();
    pendingKwScroll = snap.scrollOffset;
    return true;
  }

  void preserve(
    ProfileSessionOwner owner,
    String variant, {
    required bool modeIsKeyword,
  }) {
    if (!modeIsKeyword) return;
    if (kwQuery.isNotEmpty && kwResults.isNotEmpty && !kwSearching) {
      // A still-streaming search is NOT preserved — only a completed
      // query + its final result list. Mid-stream state would restore
      // as a frozen prefix without the engine still running.
      //
      // Fold a parked (pill) final set into the snapshot — pure field updates,
      // safe in dispose — so restore doesn't resurrect a stale subset while
      // silently dropping the authoritative result.
      final pending = kwPending;
      if (pending != null) {
        kwPending = null;
        kwAll = pending;
        if (kwSourceTab != null &&
            !pending.any((t) => kwSourceOf(t) == kwSourceTab)) {
          kwSourceTab = null;
        }
        computeProviders(pending);
      }
      kwPreserved.store(
        owner,
        KwPreservedState(
          variant: variant,
          query: kwQuery,
          all: kwAll,
          results: kwResults,
          filters: kwFilters,
          sort: kwSort,
          sortAsc: kwSortAsc,
          cache: kwCache,
          cachedOnly: kwCachedOnly,
          directCounts: kwDirectCounts,
          torrentCounts: kwTorrentCounts,
          selectedDirect: kwSelectedDirect,
          selectedTorrent: kwSelectedTorrent,
          sourceTab: kwSourceTab,
          scrollOffset: kwLastScroll,
        ),
      );
    }
  }

  /// Empty the field-driven keyword surface (token bump + drop results).
  void clear() {
    kwSearchToken++;
    disposeNodes();
    kwSearching = false;
    kwLoading = false;
    kwQuery = '';
    kwAll = [];
    kwResults = [];
    kwCache = {};
    kwError = null;
    kwPending = null;
    kwSelectionMode = false;
    kwSelected.clear();
    _emit();
  }

  /// Invalidate an in-flight search without clearing the field (sheet close).
  void invalidate() {
    kwSearchToken++;
    kwSearching = false;
    kwLoading = false;
  }

  /// Seed the keyword filter set from the user's saved defaults (Settings →
  /// default quality/rip-source/language filters), matching the old search
  /// screen's `_loadDefaultFilters`. Runs once at init; only applies when at
  /// least one default is configured so an empty default keeps filters off.
  Future<void> loadDefaultFilters() async {
    try {
      final qualities = await StorageService.getDefaultFilterQualities();
      final sources = await StorageService.getDefaultFilterRipSources();
      final languages = await StorageService.getDefaultFilterLanguages();
      final sizes = await StorageService.getDefaultFilterSizes();
      final ranges = await StorageService.getDefaultFilterDynamicRanges();
      if (!_live) return;

      final qualitySet = <QualityTier>{};
      final sourceSet = <RipSourceCategory>{};
      final languageSet = <AudioLanguage>{};
      final sizeSet = <SizeBucket>{};
      final rangeSet = <DynamicRange>{};
      for (final q in qualities) {
        for (final e in QualityTier.values) {
          if (e.name == q) qualitySet.add(e);
        }
      }
      for (final s in sources) {
        for (final e in RipSourceCategory.values) {
          if (e.name == s) sourceSet.add(e);
        }
      }
      for (final l in languages) {
        for (final e in AudioLanguage.values) {
          if (e.name == l) languageSet.add(e);
        }
      }
      for (final s in sizes) {
        for (final e in SizeBucket.values) {
          if (e.name == s) sizeSet.add(e);
        }
      }
      for (final r in ranges) {
        for (final e in DynamicRange.values) {
          if (e.name == r) rangeSet.add(e);
        }
      }

      if (qualitySet.isEmpty &&
          sourceSet.isEmpty &&
          languageSet.isEmpty &&
          sizeSet.isEmpty &&
          rangeSet.isEmpty) {
        return;
      }
      // If the user already picked filters while these async reads were in
      // flight, don't clobber their choice with the saved defaults.
      if (kwFilters.qualities.isNotEmpty ||
          kwFilters.ripSources.isNotEmpty ||
          kwFilters.languages.isNotEmpty ||
          kwFilters.sizes.isNotEmpty ||
          kwFilters.dynamicRanges.isNotEmpty) {
        return;
      }
      kwFilters = TorrentFilterState(
        qualities: qualitySet,
        ripSources: sourceSet,
        languages: languageSet,
        sizes: sizeSet,
        dynamicRanges: rangeSet,
      );
      _emit();
      // If results are already on screen (defaults resolved after a fast
      // search), re-apply so the seeded filters take effect immediately.
      if (kwAll.isNotEmpty) recompute();
    } catch (_) {
      // Non-fatal: fall back to no default filters.
    }
  }

  /// One-shot: restore DPAD focus to the toolbar at the FIRST streamed paint
  /// (set by _openKeywordSources, whose re-search unmounts the focused pill).
  /// Consumed/cleared on present so a completion refocus can never yank the
  /// remote off a row the user reached mid-stream.
  bool kwRefocusToolbar = false;

  Future<void> run(String query, {bool refocusToolbar = false}) async {
    if (query.isEmpty) return;
    final token = ++kwSearchToken;
    kwBatches.clear();
    kwSearching = true;
    kwStreamFrozen = false;
    kwPending = null;
    kwProviderSeen.clear();
    kwCacheChecked.clear();
    kwPendingChecks.clear();
    kwTbRan = false;
    kwRefocusToolbar = refocusToolbar;
    _emit(() {
      kwLoading = true;
      kwError = null;
      kwQuery = query;
      kwCache = {};
      kwCachedOnly = false;
      kwDirectCounts = {};
      kwTorrentCounts = {};
      kwSelectedDirect = {};
      kwSelectedTorrent = {};
      kwSelectionMode = false;
      kwSelected.clear();
      kwSourceTab = null;
    });
    try {
      // Streaming: each engine's batch lands as soon as THAT engine finishes,
      // so first rows show in seconds instead of after the slowest engine's
      // timeout. Provisional merges use the same mergeSearchResults as the
      // final result, so the list can never drift from what completion shows.
      void onBatch(String source, List<Torrent> batch) {
        if (!_live || token != kwSearchToken || batch.isEmpty) return;
        // A timed-out engine's original future keeps running after the
        // timeout fires — its late batch must not mutate the list after the
        // awaited result already snapped it to the authoritative set.
        if (!kwSearching) return;
        kwBatches.add(batch);
        presentStreaming(TorrentService.mergeSearchResults(kwBatches), token);
        // Stamp TB/PM badges on this engine's rows as they land, and record the
        // future so the completion sweep can await it before deciding cached-
        // only mode (settling it mid-stream would flicker rows in/out).
        kwPendingChecks.add(checkCache(batch, token));
      }

      // Resolve cache-check gating BEFORE the search starts so streaming
      // batches badge against fresh settings (a superseded search's config
      // load is harmless — its batches fail the token guard anyway).
      await loadCacheConfig();
      if (!_live || token != kwSearchToken) return;
      final result = await TorrentService.searchAllEngines(
        query,
        onBatch: onBatch,
      );
      // Drop stale results if a newer search started while this was in flight.
      if (!_live || token != kwSearchToken) return;
      kwSearching = false;
      final torrents = (result['torrents'] as List).cast<Torrent>();
      final engineErrors = result['engineErrors'];
      final engineCounts = result['engineCounts'];
      // No engine ran at all (empty counts AND errors) → the user has disabled
      // every source. Point them at Sources instead of a bare "No results".
      // (Both empty-result checks below can only fire when no batch arrived,
      // so the full-screen loader is still up — never an error over rows.)
      final noEngineRan =
          (engineCounts is! Map || engineCounts.isEmpty) &&
          (engineErrors is! Map || engineErrors.isEmpty);
      if (torrents.isEmpty && noEngineRan) {
        onCancelSubmitFocus?.call();
        _emit(() {
          kwError =
              'No sources enabled. Turn on at least one source in '
              'Sources, then try again.';
          kwLoading = false;
        });
        return;
      }
      // Every source errored and nothing came back → surface the failure
      // instead of a misleading "No results" (searchAllEngines fails soft).
      if (torrents.isEmpty && engineErrors is Map && engineErrors.isNotEmpty) {
        onCancelSubmitFocus?.call();
        _emit(() {
          kwError =
              'Search failed on all sources. Check your connection or '
              'enabled sources and try again.';
          kwLoading = false;
        });
        return;
      }
      // The awaited result is authoritative — snap to it (or park it).
      presentStreaming(torrents, token);
      finish(token);
    } catch (e) {
      if (!_live || token != kwSearchToken) return;
      kwSearching = false;
      onCancelSubmitFocus?.call();
      _emit(() {
        kwError = friendlyKeywordError(e);
        kwLoading = false;
      });
    }
  }

  /// Applies a (provisional or final) raw result set: recompute providers and
  /// the filtered view, or — once the user has interacted ([kwStreamFrozen])
  /// — park it behind the "+N new results" pill so rows never reshuffle
  /// mid-read.
  void presentStreaming(List<Torrent> raw, int token) {
    if (!_live || token != kwSearchToken) return;
    // The strip live-updates on every present (frozen or not), so if the
    // remote is ON a tab, capture its source before indices shift.
    final tabAnchor = focusedKwTabSource();
    if (kwStreamFrozen) {
      // The user has taken over focus — drop the pending toolbar refocus.
      kwRefocusToolbar = false;
      kwPending = raw;
      syncTabNodes(); // live tabs: nodes track the parked set's sources
      _emit(() {}); // pill count + tab strip update
      reanchorKwTab(tabAnchor);
      return;
    }
    kwAll = raw;
    computeProviders(raw);
    kwLoading = false; // first batch replaces the full-screen loader
    recompute();
    reanchorKwTab(tabAnchor);
    if (kwToolbarVisible) {
      onCompleteSubmitFocus?.call(kwToolbarNodes.first);
    }
    if (kwRefocusToolbar) {
      // The Sources-dialog re-search unmounted the focused toolbar; the
      // toolbar just remounted with this first paint — put the remote back
      // NOW, not at completion (rows are interactive from the first batch).
      kwRefocusToolbar = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_live && kwToolbarVisible) kwToolbarNodes.first.requestFocus();
      });
    }
  }

  /// Completion-only steps: validate the source tab against the final set,
  /// hide the searching strip, and run the cache-badge check.
  void finish(int token) {
    if (!_live || token != kwSearchToken) return;
    // Validate against the authoritative FULL set (pending included) — an
    // early batch that merely hasn't delivered a source yet must not clear
    // the user's tab mid-stream, so this check only runs here.
    final full = kwPending ?? kwAll;
    if (kwSourceTab != null && !full.any((t) => kwSourceOf(t) == kwSourceTab)) {
      kwSourceTab = null;
      // Recompute over the DISPLAYED set even when arrivals are parked, so
      // the strip ("All" active) and the visible list can't disagree.
      recompute();
    }
    _emit(() {}); // searching strip off
    // Completion: await in-flight batch checks, sweep stragglers, then settle
    // cached-only mode over the authoritative full set.
    unawaited(finalizeCache(full, token));
  }

  /// First real user interaction → stop live-reshuffling; buffer new arrivals
  /// behind the pill instead.
  void freeze() {
    kwStreamFrozen = true;
    onCancelSubmitFocus?.call();
  }

  /// Freeze AND fold any parked arrivals in — used by toolbar/dialog/tab
  /// actions, so the user always sorts/filters/selects over the complete set.
  void freezeAndAdopt() {
    freeze();
    adoptPending();
  }

  /// Folds the parked result set into the list (pill tap / toolbar use) and
  /// refreshes cache badges for the fresh rows.
  void adoptPending() {
    final p = kwPending;
    if (p == null) return;
    kwPending = null;
    // Identity-preserving refocus (Sources-list parity): folding arrivals in
    // can insert rows above the DPAD focus — keep the remote on the SAME
    // torrent, not the same index. This also keeps a long-pressed row under
    // its checkmark when enterSelection adopts before toggling.
    Torrent? focusedTorrent;
    for (var i = 0; i < kwNodes.length && i < kwResults.length; i++) {
      if (kwNodes[i].hasFocus) {
        focusedTorrent = kwResults[i];
        break;
      }
    }
    kwAll = p;
    // A tab whose source lost every row to dedupe in the adopted set would
    // otherwise stay "active" over an empty list with no highlighted pill.
    if (kwSourceTab != null && !p.any((t) => kwSourceOf(t) == kwSourceTab)) {
      kwSourceTab = null;
    }
    computeProviders(p);
    recompute();
    if (focusedTorrent != null) {
      final key = kwRowKey(focusedTorrent);
      final idx = kwResults.indexWhere((t) => kwRowKey(t) == key);
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_live && idx < kwNodes.length) kwNodes[idx].requestFocus();
        });
      }
    }
    unawaited(checkCache(kwAll, kwSearchToken));
  }

  /// Identity key for pending-row diffing (infohash when real, else the
  /// name+URL pair direct streams are distinguished by).
  static String kwRowKey(Torrent t) =>
      t.hasRealInfoHash && t.infohash.isNotEmpty
      ? 'h:${t.infohash.toLowerCase()}'
      : 'n:${t.name}|${t.directUrl ?? ''}';

  /// Rows waiting behind the pill (0 hides it) — a SET difference, not a
  /// length delta, so dedupe-shrunk pending sets still count their new rows.
  int get kwPendingNewCount {
    final p = kwPending;
    if (p == null) return 0;
    final shown = {for (final t in kwAll) kwRowKey(t)};
    var count = 0;
    for (final t in p) {
      if (!shown.contains(kwRowKey(t))) count++;
    }
    return count;
  }

  /// A torrent's source-tab bucket ('unknown' for empty sources, matching the
  /// provider-filter grouping).
  static String kwSourceOf(Torrent t) =>
      t.source.isNotEmpty ? t.source : 'unknown';

  /// The fullest known result set: parked arrivals when frozen, else the
  /// displayed set. The tab strip derives from THIS so it live-updates
  /// (counts tick, new source pills appear) even while the rows are frozen —
  /// the strip sits above the list, so it never shifts what's being read.
  List<Torrent> get kwFullSet => kwPending ?? kwAll;

  /// Distinct sources in [kwFullSet], sorted — drives the tab strip.
  List<String> get kwSourceList {
    final s = <String>{for (final t in kwFullSet) kwSourceOf(t)};
    final l = s.toList()..sort();
    return l;
  }

  /// The tab strip only earns its row when there's a real choice.
  bool get kwTabsVisible => kwSourceList.length > 1;

  /// Which SOURCE the focused tab points at ('' = the All tab, null = the
  /// strip isn't focused). Captured BEFORE a strip rebuild so focus can be
  /// re-anchored by identity — new sources insert alphabetically and shift
  /// positional node indices under the remote.
  String? focusedKwTabSource() {
    for (var i = 0; i < kwTabNodes.length; i++) {
      if (kwTabNodes[i].hasFocus) {
        if (i == 0) return '';
        final sources = kwSourceList;
        return i - 1 < sources.length ? sources[i - 1] : '';
      }
    }
    return null;
  }

  /// Post-frame twin of [focusedKwTabSource]: refocus the tab that
  /// carries [source] at its NEW index (All when it vanished).
  void reanchorKwTab(String? source) {
    if (source == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_live) return;
      final idx = source.isEmpty ? 0 : kwSourceList.indexOf(source) + 1;
      focusTab(idx > 0 && idx < kwTabNodes.length ? idx : 0);
    });
  }

  /// Turn a raw search exception into a short, human-readable message — matches
  /// the old screen's network/timeout/generic buckets.
  String friendlyKeywordError(Object e) {
    final msg = e.toString().replaceAll('Exception: ', '');
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
      return 'Network error. Please check your connection.';
    }
    if (msg.contains('TimeoutException')) {
      return 'Search timed out. Please try again.';
    }
    if (msg.length > 100) return 'Search failed. Please try again.';
    return msg;
  }

  // ── Bulk selection (keyword results) ──────────────────────────────────────
  /// Torrents eligible for bulk actions (excludes direct/external streams).
  List<Torrent> get kwSelectableResults =>
      kwResults.where((t) => !t.isDirectStream && !t.isExternalStream).toList();

  void enterSelection() {
    // Multi-select over a live-shifting list would let rows move under the
    // checkmarks — freeze and fold parked arrivals in first.
    freezeAndAdopt();
    // Entering selection swaps the toolbar to 3 pills; if DPAD focus was on the
    // now-gone "Select" pill (index 3), pull it back to the new first pill so
    // the remote doesn't lose focus.
    final refocusToolbar = kwToolbarNodes.any((n) => n.hasFocus);
    _emit(() {
      kwSelectionMode = true;
      kwSelected.clear();
    });
    if (refocusToolbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_live) kwToolbarNodes.first.requestFocus();
      });
    }
  }

  void exitSelection() {
    _emit(() {
      kwSelectionMode = false;
      kwSelected.clear();
    });
  }

  void toggleSelection(Torrent t) {
    _emit(() {
      if (kwSelected.contains(t.infohash)) {
        kwSelected.remove(t.infohash);
      } else {
        kwSelected.add(t.infohash);
      }
    });
  }

  void selectAll() {
    _emit(() {
      kwSelected
        ..clear()
        ..addAll(kwSelectableResults.map((t) => t.infohash));
    });
  }

  /// Clear the selection but stay in selection mode (matches Home's "None").
  void deselectAll() {
    _emit(() => kwSelected.clear());
  }

  bool kwBulkBusy = false;

  /// True when [t] is (or is treated as) a direct/external URL stream rather
  /// than an addable torrent — used to bucket results into the provider groups.
  bool kwIsDirect(Torrent t) => t.isDirectStream || t.isExternalStream;

  /// Action menu for a keyword-result direct/external stream row (parity with
  /// the old direct-stream action dialog): Play/Open, Copy URL, Download.
  /// Tally result counts per source, split into Direct vs Torrent groups, and
  /// default every source to selected. Mirrors the old `_calculateStreamTypeCounts`.
  void computeProviders(List<Torrent> torrents) {
    final direct = <String, int>{};
    final torrent = <String, int>{};
    for (final t in torrents) {
      final src = kwSourceOf(t);
      final bucket = kwIsDirect(t) ? direct : torrent;
      bucket[src] = (bucket[src] ?? 0) + 1;
    }
    kwDirectCounts = direct;
    kwTorrentCounts = torrent;
    // Additive selection: a source never seen this search starts ticked, but
    // one the user unticked stays unticked when a later engine's batch
    // re-reports it — streaming recomputes must not wipe mid-search choices.
    // ([kwProviderSeen] resets per search, so the first call ticks all.)
    for (final s in direct.keys) {
      if (kwProviderSeen.add('d:$s')) kwSelectedDirect.add(s);
    }
    for (final s in torrent.keys) {
      if (kwProviderSeen.add('t:$s')) kwSelectedTorrent.add(s);
    }
    // Prune sources that vanished from the merge (dedupe can reattribute a
    // source's only row to a higher-seeded copy) — stale selections corrupt
    // the Providers badge arithmetic and the dialog's All/None check. The
    // seen-key goes too, so a source that REAPPEARS auto-ticks like new.
    kwSelectedDirect.removeWhere((s) => !direct.containsKey(s));
    kwSelectedTorrent.removeWhere((s) => !torrent.containsKey(s));
    kwProviderSeen.removeWhere(
      (k) => k.startsWith('d:')
          ? !direct.containsKey(k.substring(2))
          : !torrent.containsKey(k.substring(2)),
    );
  }

  /// TorBox-cached test used by the cached-only prefilter. Entries without a
  /// real infohash but with a torrent URL (direct links) are always kept, since
  /// they can't be cache-checked — matching the old screen.
  bool kwIsTorboxCached(Torrent t) {
    if (!t.hasRealInfoHash && t.torrentUrl != null) return true;
    // Key exactly as the cache map is built and as rows render badges
    // (`infohash.toLowerCase()`, no trim) so the filter can't drop a torrent
    // that still shows a TB badge.
    final labels = kwCache[t.infohash.toLowerCase()];
    return labels != null && labels.contains('TB');
  }

  /// Re-apply cached-only + provider + tab + attribute filters and sort to the
  /// last search's results, then sync focus nodes to the new length.
  void recompute() {
    Iterable<Torrent> base = kwAll;
    // 1) TorBox cached-only prefilter (when active).
    if (kwCachedOnly) {
      base = base.where(kwIsTorboxCached);
    }
    // 2) Provider (stream-type) multi-select. An empty group map means that
    //    group has no providers, so it imposes no constraint on its members.
    if (kwDirectCounts.isNotEmpty || kwTorrentCounts.isNotEmpty) {
      base = base.where((t) {
        final src = kwSourceOf(t);
        if (kwIsDirect(t)) {
          return kwDirectCounts.isEmpty || kwSelectedDirect.contains(src);
        }
        return kwTorrentCounts.isEmpty || kwSelectedTorrent.contains(src);
      });
    }
    // 3) Source tab (single-select) narrows on top of the multi-select.
    final tab = kwSourceTab;
    if (tab != null) {
      base = base.where((t) => kwSourceOf(t) == tab);
    }
    // 4) Quality / rip-source / language attribute filters.
    final filtered = TorrentFilterMatcher.apply(base.toList(), kwFilters);
    final sorted = sortKeyword(filtered);
    syncNodes(sorted.length);
    syncTabNodes();
    _emit(() => kwResults = sorted);
  }

  /// Grows/shrinks [kwNodes] to the target length without ever disposing the
  /// focused node unanchored. Removed nodes are disposed POST-FRAME — their
  /// row widgets are still mounted this frame, and unmounting a Focus widget
  /// whose node is already disposed asserts (same rule as the Sources list).
  void syncNodes(int length) {
    while (kwNodes.length < length) {
      kwNodes.add(FocusNode(debugLabel: 'kw_${kwNodes.length}'));
    }
    if (kwNodes.length > length) {
      final removed = <FocusNode>[];
      while (kwNodes.length > length) {
        final node = kwNodes.removeLast();
        if (node.hasFocus && kwNodes.isNotEmpty) kwNodes.last.requestFocus();
        removed.add(node);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
  }

  /// Same grow/shrink discipline for the source-tab pills ("All" + one per
  /// source in [kwSourceList]).
  void syncTabNodes() {
    final want = kwSourceList.length + 1;
    while (kwTabNodes.length < want) {
      kwTabNodes.add(FocusNode(debugLabel: 'kw_tab_${kwTabNodes.length}'));
    }
    if (kwTabNodes.length > want) {
      final removed = <FocusNode>[];
      while (kwTabNodes.length > want) {
        final node = kwTabNodes.removeLast();
        if (node.hasFocus && kwTabNodes.isNotEmpty) {
          kwTabNodes.last.requestFocus();
        }
        removed.add(node);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
  }

  List<Torrent> sortKeyword(List<Torrent> list) {
    final l = [...list];
    // Direction multiplier: descending by default (asc flips it). 'name' compares
    // case-insensitively; the rest are numeric.
    final int dir = kwSortAsc ? 1 : -1;
    switch (kwSort) {
      case 'seeders':
        l.sort((a, b) => dir * a.seeders.compareTo(b.seeders));
        break;
      case 'size':
        l.sort((a, b) => dir * a.sizeBytes.compareTo(b.sizeBytes));
        break;
      case 'date':
        l.sort((a, b) => dir * a.createdUnix.compareTo(b.createdUnix));
        break;
      case 'name':
        l.sort(
          (a, b) =>
              dir *
              a.displayTitle.toLowerCase().compareTo(
                b.displayTitle.toLowerCase(),
              ),
        );
        break;
      default: // 'relevance' — keep the engine (seeder-deduped) order
        break;
    }
    return l;
  }

  /// Natural default direction for a sort field: names read A→Z (ascending);
  /// seeders/size/date read most/largest/newest first (descending).
  bool naturalAscFor(String field) => field == 'name';

  /// Additive cache-check against TorBox/Premiumize (the only providers that
  /// support it), stamping TB/PM badges onto [torrents]' rows. Called per
  /// streaming batch and once as a completion sweep (via [finalizeCache]).
  ///
  /// Results MERGE into [kwCache] so earlier batches' badges survive. A hash is
  /// added to [kwCacheChecked] ONLY after every enabled provider resolved for
  /// it — a thrown check leaves it un-memoized so a later batch or the finalize
  /// sweep re-queries it (a transient failure must not permanently drop rows).
  /// Cached-only mode is NOT decided here — see [finalizeCache].
  Future<void> checkCache(List<Torrent> torrents, int token) async {
    final hashes = <String>[];
    for (final t in torrents) {
      final h = t.infohash.toLowerCase();
      // contains (not add): dispatch every not-yet-confirmed hash; memoization
      // happens post-success below, so a failed hash stays retryable.
      if (h.isEmpty || kwCacheChecked.contains(h)) continue;
      hashes.add(h);
    }
    if (hashes.isEmpty) return;
    final add = <String, List<String>>{};
    // A provider is "done" for these hashes when it's not enabled (nothing to
    // do) OR its check succeeded. Only when BOTH are done do we memoize.
    bool tbDone = !(kwTbOn && kwTbKey != null);
    bool pmDone = !(kwPmOn && kwPmKey != null);
    bool tbOk = false;
    if (kwTbOn && kwTbKey != null) {
      try {
        final cached = await CloudProviderRegistry.instance.checkCachedHashes(
          hashes,
        );
        tbDone = true;
        tbOk = true;
        for (final h in cached) {
          (add[h] ??= <String>[]).add('TB');
        }
      } catch (_) {}
    }
    if (kwPmOn && kwPmKey != null) {
      try {
        final res = await CloudProviderRegistry.instance.checkCache(hashes);
        pmDone = true;
        for (var i = 0; i < hashes.length && i < res.length; i++) {
          if (res[i]) (add[hashes[i]] ??= <String>[]).add('PM');
        }
      } catch (_) {}
    }
    // Guard BEFORE mutating any shared state so a superseded search's late
    // batch can't stamp badges, flip kwTbRan, or memoize hashes for the new one.
    if (!_live || token != kwSearchToken) return;
    // A successful TorBox check is the precondition for cached-only mode (a
    // thrown check must NOT hide every result).
    if (tbOk) kwTbRan = true;
    kwCache.addAll(add);
    if (tbDone && pmDone) kwCacheChecked.addAll(hashes);
    _emit(() {});
  }

  /// Completion: wait for every in-flight batch check so [kwCache] and
  /// [kwTbRan] reflect the whole result set, sweep any hash a batch missed or
  /// whose check failed, THEN settle cached-only mode. Deferring the decision
  /// until the checks resolve is what prevents cached rows from being hidden by
  /// a not-yet-returned batch — the failure mode of settling it mid-flight.
  Future<void> finalizeCache(List<Torrent> full, int token) async {
    try {
      await Future.wait(List<Future<void>>.from(kwPendingChecks));
    } catch (_) {}
    if (!_live || token != kwSearchToken) return;
    // Retry any hash still un-memoized (never dispatched, or a failed check).
    await checkCache(full, token);
    if (!_live || token != kwSearchToken) return;
    // Narrow to TorBox-cached torrents only when TorBox is the sole usable
    // provider. Any other active provider may be able to handle a result that
    // TorBox does not cache, so its rows must remain visible.
    final cachedOnly = kwTbRan && !kwOtherProviderActive;
    if (cachedOnly != kwCachedOnly) {
      // Cached-only mode toggles the visible set → full recompute.
      kwCachedOnly = cachedOnly;
      recompute();
    } else {
      // Badges-only update: the result list is unchanged, so just repaint the
      // cache labels. Rebuilding kwNodes here (as a full recompute would) drops
      // TV DPAD focus off whatever row the user navigated to while the async
      // cache check was still in flight.
      _emit(() {});
    }
  }

  /// True when the provider (stream-type) filter is worth surfacing: at least
  /// two distinct sources exist across both groups, so filtering can change the
  /// result set. A single source imposes no meaningful choice.
  bool get kwHasProviderFilter =>
      (kwDirectCounts.length + kwTorrentCounts.length) >= 2;

  /// Count of source groups the user has narrowed away from "all selected" —
  /// drives the active state / badge on the Providers pill.
  int get kwProviderFilterActive {
    var n = 0;
    if (kwDirectCounts.isNotEmpty &&
        kwSelectedDirect.length != kwDirectCounts.length) {
      n += kwDirectCounts.length - kwSelectedDirect.length;
    }
    if (kwTorrentCounts.isNotEmpty &&
        kwSelectedTorrent.length != kwTorrentCounts.length) {
      n += kwTorrentCounts.length - kwSelectedTorrent.length;
    }
    return n;
  }

  /// Multi-select dialog to filter keyword results by their source, grouped into
  /// Direct and Torrent providers. Ported from the old screen's stream-type
  /// dropdowns, adapted to the new toolbar/dialog idiom.
  void disposeNodes() {
    for (final n in kwNodes) {
      n.dispose();
    }
    kwNodes.clear();
  }

  /// Focus a source tab AND scroll the strip to reveal it — a bare
  /// requestFocus doesn't scroll, so an off-screen tab would take focus
  /// invisibly.
  void focusTab(int index) {
    if (index < 0 || index >= kwTabNodes.length) return;
    final node = kwTabNodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (_live && ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  void setSourceTab(String? source) {
    final tabHadFocus = kwTabNodes.any((n) => n.hasFocus);
    // A deliberate reshuffle: fold parked arrivals in so the tab filters the
    // complete set (also freezes further live updates).
    freezeAndAdopt();
    // The tapped source can vanish in the adopt (dedupe reattribution) — an
    // active tab no longer in the strip would strand an empty list.
    if (source != null && !kwAll.any((t) => kwSourceOf(t) == source)) {
      source = null;
    }
    if (kwSourceTab != source) {
      kwSourceTab = source;
      recompute();
    }
    // Tab nodes are positional and the adopt can re-sort kwSourceList —
    // re-anchor DPAD focus onto the tab that was actually chosen.
    if (tabHadFocus) {
      final s = source;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_live) return;
        final idx = s == null ? 0 : kwSourceList.indexOf(s) + 1;
        focusTab(idx > 0 && idx < kwTabNodes.length ? idx : 0);
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    kwScroll.dispose();
    kwPillFocus.dispose();
    kwSourcesBtnFocus.dispose();
    for (final n in kwTabNodes) {
      n.dispose();
    }
    kwTabNodes.clear();
    disposeNodes();
    for (final n in kwToolbarNodes) {
      n.dispose();
    }
    super.dispose();
  }
}
