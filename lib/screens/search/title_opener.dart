import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/advanced_search_selection.dart';
import '../../models/play_loader_art.dart';
import '../../models/stremio_addon.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_continue_watching_service.dart';
import '../../services/mdblist/mdblist_menu_helpers.dart';
import '../../services/mdblist/mdblist_models.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/simkl/simkl_continue_watching_service.dart';
import '../../services/simkl/simkl_menu_helpers.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/trakt/trakt_continue_watching_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/trakt/trakt_menu_helpers.dart';
import '../catalog_item_detail_screen.dart';
import '../episodes_screen.dart' show kCatalogDetailRouteName;
import '../merged_series_detail_screen.dart';

/// Catalog Play = auto-best in-tab. Copied from `search_screen.dart`
/// `_onCatalogPlay` so the merged/legacy detail pages keep the same
/// named-arg contract after G1 step 3.
typedef TitleCatalogPlay =
    Future<void> Function(
      StremioMeta item,
      StremioAddon addon, {
      bool isTraktSource,
      bool isMdblistSource,
      bool skipEpisodeFallback,
      bool preferTraktResume,
      ({bool started, int season, int episode})? promisedTarget,
      bool browseSourcesOnly,
    });

typedef TitleCatalogBrowse =
    void Function(
      StremioMeta item,
      StremioAddon addon, {
      bool isTraktSource,
      bool isMdblistSource,
    });

typedef TitleResumeInfoLoader =
    Future<({bool started, int? season, int? episode})> Function(
      StremioMeta item,
      StremioAddon addon, {
      bool isTraktSource,
      bool isMdblistSource,
    });

typedef TitleDetailQuickAction =
    Future<void> Function(
      StremioMeta item,
      StremioAddon addon,
      TraktItemMenuAction action, {
      required bool inCw,
      String? imdb,
      int? presetRating,
    });

typedef TitleSimklQuickAction =
    Future<void> Function(
      StremioMeta item,
      SimklItemMenuAction action, {
      int? presetRating,
    });

typedef TitleMdblistQuickAction =
    Future<void> Function(
      StremioMeta item,
      MdblistItemMenuAction action, {
      int? presetRating,
    });

/// Detail opening extracted from `search_screen.dart` (G1 step 3).
///
/// Owns `_openItem` and its inner `buildMenuOptions` / Simkl / MDBList
/// builders. Quick-action handlers, bind dialogs, and play/browse stay on
/// the State and are injected as callbacks (same pattern as G1 step 2
/// `onStarted` / `onClear`).
class TitleOpener {
  TitleOpener({
    required this.getContext,
    required this.isTelevision,
    required this.mergedSeriesPage,
    required this.pikpakOnly,
    required this.cwIds,
    required this.traktByImdb,
    required this.mdblistByImdb,
    required this.simklByImdb,
    required this.isTraktAuthenticated,
    required this.isSimklAuthenticated,
    required this.isMdblistAuthenticated,
    required this.imdbOf,
    required this.isBound,
    required this.boundCountFor,
    required this.onActiveAddon,
    required this.resolveResumeInfo,
    required this.onCatalogPlay,
    required this.onCatalogBrowse,
    required this.onItemSelected,
    required this.onQuickPlay,
    required this.onSelectSource,
    required this.onDetailQuickAction,
    required this.onDetailSimklQuickAction,
    required this.onDetailMdblistQuickAction,
    required this.onLoaderArt,
    required this.getRecommendations,
    required this.fetchMetaDetails,
    required this.onAfterPlayback,
    required this.onRefreshTraktAuth,
    required this.onRefreshSimklAuth,
    required this.onRefreshMdblistAuth,
  });

  final BuildContext Function() getContext;
  final bool Function() isTelevision;
  final bool Function() mergedSeriesPage;
  final bool Function() pikpakOnly;
  final Set<String> cwIds;
  final Map<String, TraktContinueWatchingItem> traktByImdb;
  final Map<String, MdblistContinueWatchingItem> mdblistByImdb;
  final Map<String, SimklContinueWatchingItem> simklByImdb;
  final bool Function() isTraktAuthenticated;
  final bool Function() isSimklAuthenticated;
  final bool Function() isMdblistAuthenticated;
  final String? Function(StremioMeta item) imdbOf;
  final bool Function(StremioMeta item) isBound;
  final int Function(StremioMeta item) boundCountFor;
  final void Function(String addonId) onActiveAddon;
  final TitleResumeInfoLoader resolveResumeInfo;
  final TitleCatalogPlay onCatalogPlay;
  final TitleCatalogBrowse onCatalogBrowse;
  final void Function(AdvancedSearchSelection selection) onItemSelected;
  final Future<void> Function(AdvancedSearchSelection selection) onQuickPlay;
  final Future<void> Function(StremioMeta show) onSelectSource;
  final TitleDetailQuickAction onDetailQuickAction;
  final TitleSimklQuickAction onDetailSimklQuickAction;
  final TitleMdblistQuickAction onDetailMdblistQuickAction;
  final void Function(StremioMeta item, PlayLoaderArt art) onLoaderArt;
  final Future<List<StremioMeta>> Function({
    required String imdbId,
    required String type,
  })
  getRecommendations;
  final Future<StremioMeta?> Function({
    required String imdbId,
    required String type,
  })
  fetchMetaDetails;
  final Future<void> Function() onAfterPlayback;
  final VoidCallback onRefreshTraktAuth;
  final VoidCallback onRefreshSimklAuth;
  final VoidCallback onRefreshMdblistAuth;

  /// Copied from `search_screen.dart` `_openItem`.
  void open(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Shared-element tag from the tapped board cell: the poster flies into the
    // detail page's backdrop. Null (non-board callers) = regular transition.
    String? heroTag,
    // For a series opened at a specific episode (Trakt Calendar): scroll the
    // episodes panel to this season/episode. Ignored by the movie/legacy paths.
    int? initialSeason,
    int? initialEpisode,
    // When set, switch back to this tab once the detail route closes — lets a
    // cross-tab opener (the Calendar) return the user to where they came from.
    int? returnToTabOnClose,
  }) {
    final context = getContext();
    onActiveAddon(addon.id);
    final imdb = imdbOf(item);
    // Show a "Remove from Continue Watching" action when this title is on the
    // Continue Watching row (regardless of which row opened it).
    final inCw = imdb != null && cwIds.contains(imdb);
    // Same for the Trakt Continue Watching rows — removal goes through the
    // Trakt playback/history APIs rather than local storage.
    final inTraktCw = imdb != null && traktByImdb.containsKey(imdb);
    final inMdblistCw = imdb != null && mdblistByImdb[imdb]?.paused == true;

    // Full quick-actions menu, mirroring the catalog/aggregated detail screens:
    // app actions (Select Source, Add to Stremio TV, Search Packs, Random
    // Episode) always, Trakt-syncing actions only when connected — plus Remove
    // for Continue Watching titles.
    // Build the quick-actions strip against a (possibly still-unknown) Trakt
    // status. Called with null for the initial/legacy add-only strip, then
    // rebuilt by the merged page once `traktStatusLoader` resolves — so
    // watchlist/collection/rating entries flip to their Remove form when the
    // title is already there.
    final app = AppThemeScope.of(context);
    List<TraktMenuOption> buildMenuOptions(
      TraktTitleStatus? status,
    ) => <TraktMenuOption>[
      ...buildTraktAddOnlyMenuOptions(
        isSeries: item.type == 'series',
        isMovie: item.type == 'movie',
        hasBoundSource: isBound(item),
        // The Trakt-syncing actions key off the IMDb id, so only offer them
        // for titles that have one (else the sync call fails with an error).
        isTraktAuthenticated: isTraktAuthenticated() && imdb != null,
        status: status,
      ),
      if (inCw)
        TraktMenuOption(
          action: TraktItemMenuAction.removeFromPlayback,
          icon: Icons.delete_sweep_rounded,
          color: app.home.danger,
          label: 'Remove from Continue Watching',
          caption: 'Remove',
        ),
      if (inTraktCw)
        TraktMenuOption(
          action: TraktItemMenuAction.removeFromTraktPlayback,
          icon: Icons.remove_circle_outline_rounded,
          color: app.home.danger,
          label: 'Remove from Trakt Continue Watching',
          caption: 'Remove',
          isTrakt: true,
        ),
    ];
    // Static (status-unknown) strip — the fallback for the merged page until its
    // status loads, and the only strip the legacy CatalogItemDetailScreen uses.
    final options = buildMenuOptions(null);

    // Simkl's own strip — built and rendered entirely separately from Trakt's
    // above (see the Simkl integration plan: parallel, not merged). Gated on
    // connection state the same way the Trakt strip is (isTraktAuthenticated
    // above) — buildSimklMenuOptions itself returns empty when disconnected.
    List<SimklMenuOption> buildSimklOptions(SimklTitleStatus? status) =>
        buildSimklMenuOptions(
          isSeries: item.type == 'series',
          isSimklAuthenticated: isSimklAuthenticated() && imdb != null,
          // Offer "Remove from Continue Watching" for a paused entry (movie or
          // series) — it has a session to delete. Not for "up next" entries
          // (progress null, no session; they leave via a status change). For a
          // series the remove also moves it to On Hold so it doesn't re-surface
          // as an up-next card (see handleSimklMenuAction).
          inContinueWatching:
              imdb != null && (simklByImdb[imdb]?.progress != null),
          status: status,
        );
    final simklOptions = buildSimklOptions(null);

    List<MdblistMenuOption> buildMdblistOptions(MdblistTitleStatus? status) =>
        buildMdblistMenuOptions(
          authenticated: isMdblistAuthenticated() && imdb != null,
          isSeries: item.type == 'series',
          inContinueWatching: inMdblistCw,
          status: status,
        );
    final mdblistOptions = buildMdblistOptions(null);

    // Experimental: series route to the merged detail+episodes page. Movies and
    // the flag-off path fall through to the existing CatalogItemDetailScreen.
    if ((item.type == 'series' || item.type == 'movie') && mergedSeriesPage()) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              settings: const RouteSettings(name: kCatalogDetailRouteName),
              builder: (_) => MergedDetailScreen(
                item: item,
                addon: addon,
                isTelevision: isTelevision(),
                // PikPak quick-plays fine here: onResume → _onCatalogPlay →
                // _playSelection → TorrentPlaybackService.playFromSelection
                // already handles PikPak (same path the episode tiles use, which
                // stay quick-play-enabled for PikPak-only). It queues an offline
                // download and surfaces "still processing" if not ready — same
                // behaviour as the tiles, so the hero button matches them.
                showQuickPlay: true,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
                heroTag: heroTag,
                initialSeason: initialSeason,
                initialEpisode: initialEpisode,
                resumeInfoLoader: () => resolveResumeInfo(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                ),
                onResume: (promised) => onCatalogPlay(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                  skipEpisodeFallback: true,
                  // The merged page resolves its own episode target (it can see
                  // watched state the reconciler can't) — Play must land on the
                  // episode its label is showing.
                  promisedTarget: promised,
                  // Play the Trakt paused episode when the Trakt-first label
                  // shows one, so the button and the action agree.
                  preferTraktResume: true,
                ),
                // Movie only: the Sources (manual list) button.
                onBrowse: item.type == 'movie'
                    ? () => onCatalogBrowse(
                        item,
                        addon,
                        isTraktSource: isTraktSource,
                        isMdblistSource: isMdblistSource,
                      )
                    : null,
                onItemSelected: onItemSelected,
                onQuickPlay: onQuickPlay,
                onBrowsePrimaryEpisodeSources: (promised) => onCatalogPlay(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                  skipEpisodeFallback: true,
                  preferTraktResume: true,
                  promisedTarget: promised,
                  browseSourcesOnly: true,
                ),
                boundSourceCount: boundCountFor,
                onSelectSource: onSelectSource,
                traktMenuOptions: options,
                traktMenuBuilder: buildMenuOptions,
                // Live Trakt status (in watchlist / collection / watched /
                // rating) — only when connected and the title has an IMDb id.
                traktStatusLoader: (isTraktAuthenticated() && imdb != null)
                    ? () => TraktService.instance.fetchTitleStatus(
                        imdb,
                        item.type,
                      )
                    : null,
                onTraktAction: (a) =>
                    onDetailQuickAction(item, addon, a, inCw: inCw, imdb: imdb),
                // Inline 1–10 strips in the tracker sheets: same handler, with
                // the score already chosen so no dialog opens.
                onTraktRate: (r) => onDetailQuickAction(
                  item,
                  addon,
                  TraktItemMenuAction.rate,
                  inCw: inCw,
                  imdb: imdb,
                  presetRating: r,
                ),
                onSimklRate: (r) => onDetailSimklQuickAction(
                  item,
                  SimklItemMenuAction.rate,
                  presetRating: r,
                ),
                simklMenuOptions: simklOptions,
                simklMenuBuilder: buildSimklOptions,
                // Live Simkl status (current watchlist status + rating) —
                // only when connected and the title has an IMDb id.
                simklStatusLoader: (isSimklAuthenticated() && imdb != null)
                    ? () => SimklService.instance.fetchTitleStatus(imdb)
                    : null,
                onSimklAction: (a) => onDetailSimklQuickAction(item, a),
                mdblistMenuOptions: mdblistOptions,
                mdblistMenuBuilder: buildMdblistOptions,
                mdblistStatusLoader: (isMdblistAuthenticated() && imdb != null)
                    ? () => MdblistService.instance.fetchTitleStatus(
                        imdb,
                        item.type,
                      )
                    : null,
                onMdblistAction: (a) => onDetailMdblistQuickAction(item, a),
                onMdblistRate: (rating) => onDetailMdblistQuickAction(
                  item,
                  MdblistItemMenuAction.rate,
                  presetRating: rating,
                ),
                recommendationsLoader: imdb != null
                    ? () => getRecommendations(imdbId: imdb, type: item.type)
                    : null,
                onRecommendationTap: imdb != null
                    ? (rec) => open(rec, rec.sourceAddon ?? addon)
                    : null,
                metaEnricher: (id, type) =>
                    fetchMetaDetails(imdbId: id, type: type),
              ),
            ),
          )
          // Playback (or a bind/unbind) may have happened inside the detail
          // flow — _refreshAfterPlayback covers the tracker rows too, and
          // sequences the bound-source pass after the CW reloads.
          .then((_) {
            unawaited(onAfterPlayback());
            onRefreshTraktAuth();
            onRefreshSimklAuth();
            onRefreshMdblistAuth();
            if (returnToTabOnClose != null) {
              MainPageBridge.switchTab?.call(returnToTabOnClose);
            }
          });
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kCatalogDetailRouteName),
            builder: (_) => CatalogItemDetailScreen(
              // Keep the originating addon with the locally-saved My
              // Watchlist row so reopening it can route to the same source.
              item: MyWatchlistStore.withMyWatchlistSource(item, addon),
              isTelevision: isTelevision(),
              // Hide "Play" when PikPak is the only provider — no quick-play.
              showQuickPlay: !pikpakOnly(),
              // Gold-tint the Sources button when a source is already pinned.
              hasBoundSource: isBound(item),
              resumeInfoLoader: () => resolveResumeInfo(
                item,
                addon,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
              ),
              // preferTraktResume: this screen's resumeInfoLoader is the same
              // Trakt-authoritative _resolveResumeInfo the merged page uses, so
              // Play must honour the Trakt position too or the button label and
              // playback diverge (button "Resume · S3E4" vs local S01E01).
              onPlay: () => onCatalogPlay(
                item,
                addon,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
                preferTraktResume: true,
              ),
              // Enriched backdrop/logo/meta for the Marquee play loader —
              // the catalog row that opened this page rarely has any of it.
              onLoaderArt: (art) => onLoaderArt(item, art),
              onBrowse: () => onCatalogBrowse(
                item,
                addon,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
              ),
              onBrowsePrimaryEpisodeSources: item.type == 'series'
                  ? () => onCatalogPlay(
                      item,
                      addon,
                      isTraktSource: isTraktSource,
                      isMdblistSource: isMdblistSource,
                      skipEpisodeFallback: true,
                      preferTraktResume: true,
                      browseSourcesOnly: true,
                    )
                  : null,
              traktMenuOptions: options,
              onTraktAction: (a) =>
                  onDetailQuickAction(item, addon, a, inCw: inCw, imdb: imdb),
              simklMenuOptions: simklOptions,
              onSimklAction: (a) => onDetailSimklQuickAction(item, a),
              mdblistMenuOptions: mdblistOptions,
              onMdblistAction: (a) => onDetailMdblistQuickAction(item, a),
              // Live Simkl status — relabels Play → "Rewatch" for a completed
              // movie (matches the merged detail page's simklStatusLoader).
              simklStatusLoader: (isSimklAuthenticated() && imdb != null)
                  ? () => SimklService.instance.fetchTitleStatus(imdb)
                  : null,
              // "More Like This" rail + sparse-item meta backfill, matching the
              // catalog detail flow.
              recommendationsLoader: imdb != null
                  ? () => getRecommendations(imdbId: imdb, type: item.type)
                  : null,
              onRecommendationTap: imdb != null
                  ? (rec) => open(rec, rec.sourceAddon ?? addon)
                  : null,
              metaEnricher: (id, type) =>
                  fetchMetaDetails(imdbId: id, type: type),
            ),
          ),
        )
        // A bind/unbind may have happened inside the detail flow; playback may
        // also have changed Continue Watching progress (local AND tracker rows
        // — see _refreshAfterPlayback).
        .then((_) {
          unawaited(onAfterPlayback());
          onRefreshTraktAuth();
          onRefreshSimklAuth();
          onRefreshMdblistAuth();
          if (returnToTabOnClose != null) {
            MainPageBridge.switchTab?.call(returnToTabOnClose);
          }
        });
  }
}
