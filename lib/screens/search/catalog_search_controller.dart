import 'package:flutter/foundation.dart';

import '../../models/stremio_addon.dart';
import '../../services/watched_filter.dart';
import '../../utils/concurrency.dart';

/// Injected per-catalog search. Production wraps
/// `StremioService.searchSingleCatalog`; tests stub pages.
typedef CatalogSearchFetch =
    Future<List<StremioMeta>> Function(
      StremioAddon addon,
      StremioAddonCatalog catalog,
      String query, {
      required bool throwOnError,
      void Function(int rawCount)? onRawCount,
    });

/// Catalog search data layer extracted from `search_screen.dart` (G1 step 2).
///
/// Owns the query / searching flags and the generation token so a newer
/// search or [_restoreHome] cancel still drops in-flight catalog fetches.
/// UI (FocusNodes, `_applySections` / `_appendSections`, TV submit-focus)
/// stays in the State, which [listen]s and rebuilds.
class CatalogSearchController extends ChangeNotifier {
  CatalogSearchController({
    required this.getDisabledAddons,
    required this.getSearchableAddons,
    required this.searchCatalog,
    this.onStarted,
    this.onClear,
    this.onApplyFirst,
    this.onAppend,
    this.onTelevisionApply,
    this.onTelevisionSettled,
    this.onAborted,
    bool Function()? isLive,
    bool Function()? isTelevision,
  }) : _isLive = isLive,
       _isTelevision = isTelevision;

  final Future<Set<String>> Function() getDisabledAddons;
  final Future<List<StremioAddon>> Function() getSearchableAddons;
  final CatalogSearchFetch searchCatalog;

  /// After query/searching flags flip, before the board is cleared.
  /// Production: pull TV focus off a previous-query card.
  final VoidCallback? onStarted;

  /// Clear the previous query's rows. Production: `_applySections(const [])`.
  final VoidCallback? onClear;

  /// Non-TV first arrival: full apply so the hero seeds from it.
  final void Function(CatalogSection section)? onApplyFirst;

  /// Non-TV later arrivals: append without disposing existing focus nodes.
  final void Function(CatalogSection section)? onAppend;

  /// TV: apply the whole result set at once after every catalog returns.
  final void Function(List<CatalogSection> sections)? onTelevisionApply;

  /// TV: after [searching] clears on success — complete or cancel submit-focus.
  final VoidCallback? onTelevisionSettled;

  /// Outer catch: cancel submit-focus, then [searching] clears.
  final VoidCallback? onAborted;

  final bool Function()? _isLive;
  final bool Function()? _isTelevision;

  bool _disposed = false;

  bool get _live => !_disposed && (_isLive?.call() ?? true);

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  String query = '';

  bool searching = false;

  /// Monotonic token so a slow earlier catalog search can't clobber a newer
  /// one, and [_restoreHome] can cancel in-flight work.
  int searchToken = 0;

  /// Catalogs that errored (timeout / HTTP / network) during the current
  /// catalog search — distinct from "returned no results".
  int failures = 0;

  /// True while a committed query is showing, or a search is still in flight.
  bool get active => query.isNotEmpty || searching;

  bool isCurrent(int token) => token == searchToken;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Cancel any pending search (bump the token, clear query/searching).
  ///
  /// Quirk: [failures] is **not** reset — `_restoreHome` left the last
  /// search's failure count in place.
  void cancel() {
    searchToken++;
    query = '';
    searching = false;
    notifyListeners();
  }

  /// Cross-addon catalog search, grouped as one horizontal row per addon so it
  /// matches the board (not a merged grid).
  ///
  /// Copied from `search_screen.dart` `_runCatalogSearch`.
  Future<void> run(String query) async {
    final token = ++searchToken;
    this.query = query;
    searching = true;
    failures = 0;
    notifyListeners();
    // If DPAD focus is sitting on a result card from the PREVIOUS query, pull it
    // back to the search field before we clear the board below — otherwise
    // disposing that card's FocusNode strands focus. Only reachable on TV, and
    // only when a keystroke's debounce fires after the user jumped down into the
    // old results; the soft keyboard was already up from that keystroke, so this
    // doesn't pop a new one.
    onStarted?.call();
    // Clear the previous query's rows + hero up front. On phone/desktop results
    // then STREAM into the fresh board as they arrive; on TV the board stays on
    // its spinner until every catalog is in and lands in one shot (see below).
    onClear?.call();
    try {
      // Honour the per-addon toggles from the catalog Sources dialog: skip
      // addons the user disabled for catalog search (empty set = all queried).
      final disabledAddons = await getDisabledAddons();
      final addons = (await getSearchableAddons())
          .where((a) => !disabledAddons.contains(a.id))
          .toList();
      // One row PER searchable catalog (so Movies and Series land in separate
      // categorised rows, like Stremio) instead of one merged row per addon.
      final catalogTasks =
          <({StremioAddon addon, StremioAddonCatalog catalog})>[];
      for (final addon in addons) {
        for (final catalog in addon.catalogs.where((c) => c.supportsSearch)) {
          catalogTasks.add((addon: addon, catalog: catalog));
        }
      }
      // On TV we deliberately DON'T lazy-stream rows in as they arrive: the
      // incremental appends caused focus/scroll churn while surfing, so TV
      // waits for every catalog and applies them in one shot below. Phone and
      // desktop keep streaming — each row is applied AS IT ARRIVES.
      // _appendSections grows the focus nodes without disposing existing ones,
      // so streamed rows never jump focus.
      //
      // Bound the fan-out either way: with many installed addons this could
      // otherwise fire hundreds of concurrent HTTP requests at once and exhaust
      // sockets/memory on weak hardware.
      final tv = _isTelevision?.call() ?? false;
      var appliedFirst = false;
      final raw = await mapWithConcurrency(catalogTasks, (entry) async {
        List<StremioMeta> items;
        var rawCount = 0;
        try {
          items = await searchCatalog(
            entry.addon,
            entry.catalog,
            query,
            throwOnError: true,
            onRawCount: (c) => rawCount = c,
          );
        } catch (_) {
          // Source failed (not "no results") — count it for the status note.
          if (_live && token == searchToken) {
            failures++;
            notifyListeners();
          }
          return null;
        }
        if (!_live || token != searchToken) return null;
        // Search rows are single-shot (no top-up): a match that's been
        // watched simply doesn't show.
        items = WatchedFilter.apply(items);
        if (items.isEmpty) return null;
        final section = CatalogSection(
          title: CatalogSection.rowTitle(entry.catalog),
          addon: entry.addon,
          catalog: entry.catalog,
          items: items,
          // Carry the query so "See all" keeps searching this catalog rather
          // than browsing it (which would muddy results with non-matches).
          query: query,
          // Seed the paging cursor with the RAW page-1 count (not the
          // invalid-id-filtered items.length), so See All's first search
          // load-more offsets correctly instead of re-fetching page 1.
          nextSkip: rawCount > 0 ? rawCount : items.length,
        );
        // TV: just collect it (applied together after the loop, in stable addon
        // order). Non-TV: stream it into the board now.
        if (!tv) {
          if (!appliedFirst) {
            // First arrival: full apply so the hero seeds from it (the board is
            // empty at this point, so nothing focused gets disposed).
            appliedFirst = true;
            onApplyFirst?.call(section);
          } else {
            onAppend?.call(section);
          }
        }
        return section;
      });
      if (!_live || token != searchToken) return;
      // TV: apply the whole result set at once (mapWithConcurrency preserves
      // input order, so rows land in addon order, not completion order).
      if (tv) {
        onTelevisionApply?.call(raw.whereType<CatalogSection>().toList());
      }
      searching = false;
      notifyListeners();
      if (tv) {
        onTelevisionSettled?.call();
      }
    } catch (_) {
      if (!_live || token != searchToken) return;
      onAborted?.call();
      searching = false;
      notifyListeners();
    }
  }
}
