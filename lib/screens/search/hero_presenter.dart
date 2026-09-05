import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../models/stremio_addon.dart';
import '../../services/imdb_trailer_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/stremio_service.dart';
import '../../services/youtube_service.dart';
import '../../theme/artwork_accent.dart';
import '../../utils/tvos_device.dart';

/// Screen-owned presentation inputs, sampled at the same points as the host's
/// original getters. Stage types and private State members never cross this API.
class HeroEnvironment {
  const HeroEnvironment({
    required this.isTelevision,
    required this.searchMode,
    required this.discoverMode,
    required this.catalogQuery,
    required this.stageActive,
    required this.stagePublishesShellArt,
    required this.stageWantsAmbient,
    required this.homeStyle,
    required this.hasFavouriteFocus,
  });
  final bool isTelevision, searchMode, discoverMode;
  final String catalogQuery;
  final bool stageActive, stagePublishesShellArt, stageWantsAmbient;
  final String homeStyle;
  final bool hasFavouriteFocus;
}

/// Home hero presentation and shell relays. Retains Flutter, artwork and player
/// service dependencies intentionally; this is not a pure-logic controller.
class HeroPresenter {
  HeroPresenter({
    required this.environment,
    required this.isMounted,
    required this.hostContext,
    required this.updateHost,
    required this.clearFavouriteFocus,
    required this.showingHeroId,
  });
  final HeroEnvironment Function() environment;
  final bool Function() isMounted;
  final BuildContext Function() hostContext;
  final void Function(VoidCallback) updateHost;
  final VoidCallback clearFavouriteFocus;
  final String? Function() showingHeroId;
  final StremioService _stremio = StremioService.instance;

  void cancelPendingSwap() => _heroSwapTimer?.cancel();
  void resetAmbientArtIdentity() => _ambientArtItemId = null;

  // Hero state. Driven by ValueNotifiers so focus-driven hero swaps rebuild
  // only the spotlight, never the whole board (important on low-power TVs).
  final ValueNotifier<StremioMeta?> heroItem = ValueNotifier<StremioMeta?>(null);
  final ValueNotifier<StremioMeta?> heroEnriched = ValueNotifier<StremioMeta?>(
    null,
  );
  int _heroReqId = 0;
  Timer? _heroTimer;

  /// Settle debounce for the hero SWAP itself (260ms): while DPAD focus flies
  /// across cards only the card visuals update; the spotlight (backdrop
  /// decode, logo, meta, tint cascade) follows once focus rests.
  Timer? _heroSwapTimer;

  // Hero ambient trailer (Home board, TV only): once DPAD focus RESTS on a
  // card, its trailer crossfades into the hero backdrop — same living-backdrop
  // treatment (and the same HeroTrailerBackdrop machinery: single decoder,
  // route/background pausing) as the detail page. Notifier-driven so a trailer
  // arriving rebuilds only the hero's video layer, never the board.
  final ValueNotifier<YoutubeResolvedStreams?> trailer =
      ValueNotifier<YoutubeResolvedStreams?>(null);
  Timer? _heroTrailerTimer;
  int _heroTrailerReq = 0;

  /// True from the moment the rest-debounce commits to loading a trailer until
  /// either frames are on screen or the attempt dies (no trailer / resolve
  /// failed / hero moved on) — drives the hero's little "Trailer" pill.
  final ValueNotifier<bool> trailerLoading = ValueNotifier<bool>(false);

  /// True while trailer frames are actually on screen. The spotlight fades its
  /// static backdrop image out on this signal (the video plays in the board
  /// layer BENEATH the spotlight, so the image must yield to reveal it — the
  /// crossfade the video's own opacity used to provide when it sat on top).
  final ValueNotifier<bool> trailerShowing = ValueNotifier<bool>(false);

  /// Takeover progress (0 ambient → 1 full-board), published by
  /// [_HeroTrailerLayer] as its promote animation runs. The board content and
  /// the sidebar rail fade fully OUT on it while the compact info overlay
  /// fades in — the film takes the room.
  final ValueNotifier<double> trailerTakeover = ValueNotifier<double>(0);

  // Live IPTV favourite hero preview: when DPAD focus rests on an "IPTV" row
  // card, its stream plays in the SAME boxed video region as the catalog
  // trailer above — reusing HeroTrailerBackdrop's `live: true` mode, exactly
  // like the IPTV page's own inline channel preview
  // (IptvResultsView._buildPreviewStage). Painted as a layer above
  // [_HeroTrailerLayer] so the two never need to swap types; whichever one
  // actually has a URL to show wins (see [setLiveIptv]).
  final ValueNotifier<String?> liveUrl = ValueNotifier<String?>(null);

  /// Set the INSTANT an IPTV favourite gains focus — well before its stream
  /// (if a Stremio-addon channel) finishes resolving. [_HeroLiveLayer] uses
  /// this to occlude the region with the channel's OWN art immediately, so
  /// the previously-focused catalog title's Cinemeta poster never shows
  /// through the resolve/buffer gap underneath.
  final ValueNotifier<IptvChannel?> liveChannel = ValueNotifier<IptvChannel?>(
    null,
  );

  /// Boolean mirror of [liveChannel] for [_HeroSpotlight.liveTakeover] —
  /// the spotlight fades its (now-stale) colour field and identity text on
  /// this, and has no other reason to know the IPTV-specific channel type.
  final ValueNotifier<bool> liveTakeover = ValueNotifier<bool>(false);
  int _heroLiveReq = 0;

  /// Candidate ladder for the live IPTV favourite when it's a Stremio-addon
  /// channel (several upstream links to try in order) — mirrors the IPTV
  /// page's own ladder (IptvResultsView._onPreviewPlaybackFailed). Null for a
  /// plain M3U/Xtream favourite, which has just the one URL.
  List<String>? _heroLiveCandidates;

  /// Set when real content playback launches (any path — in-app route,
  /// native TV activity, external app): the ambient trailer must not resume
  /// behind or after the feature (the behavior ef5f555 shipped; the
  /// backdrop's own per-instance latch dies with the widget when the route
  /// cover kills the trailer, so the host has to remember). Cleared when a
  /// NEW title takes the spotlight or the board reloads.
  bool trailerSuppressed = false;

  /// The item the last hero-trailer schedule was for — what the suppression
  /// lift above compares against.
  String? _heroTrailerScheduledItemId;

  /// Settings → Home Page toggles, read once per screen life (on TV a tab
  /// switch rebuilds the screen, so Settings changes are picked up on return).
  bool trailerEnabled = false;

  /// Ambient volume (0–100) for the hero trailer; 0 when the sound toggle is
  /// off. Applied at engine open, so it's also read once per screen life.
  double trailerVolume = 0;

  /// Trailers only on the TV Home board's full spotlight — never the Search
  /// tab's compact strip (too small, and results should dominate) or off-TV
  /// (the hero itself isn't rendered there). Low-memory Apple TV generations
  /// are excluded outright: an mpv trailer engine alongside the board's
  /// artwork is exactly the load that jetsam-kills a 3 GB first-gen 4K, and
  /// the probe is warmed pre-runApp so this getter stays constant for the
  /// State's lifetime (the init/dispose registrations must agree).
  bool get trailerActive =>
      environment().isTelevision &&
      !environment().searchMode &&
      !environment().discoverMode &&
      !TvosDevice.isLowMemoryCached;

  /// The hero trailer off-TV: the Spotlight home board's reel, rendered on
  /// phones/tablets/desktop. Deliberately SEPARATE from [trailerActive]
  /// — that getter is the whole TV shell lifecycle (glass scaffold, sidebar
  /// relays, hardware-key takeover, ambient publish), none of which belongs
  /// on a phone. This one means exactly "this instance may resolve and paint
  /// a hero trailer"; the enabled pref (platform-defaulted: TV/desktop on,
  /// phone/tablet off) gates it at schedule time.
  bool get trailerOffTvEligible =>
      !environment().isTelevision &&
      !environment().searchMode &&
      !environment().discoverMode;

  /// May THIS instance resolve/render a hero trailer at all.
  bool get trailerRenderable => trailerActive || trailerOffTvEligible;

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Whether the hero spotlight is live for the current tab/state: TV-only, on
  /// the board always and on the dedicated Search tab once there are results
  /// (hidden on the blank "type to search" prompt). Single source of truth for
  /// seeding ([_applySections]), focus tracking ([setHero]) and rendering
  /// ([_buildBoard]) so they can't drift.
  bool get active =>
      environment().isTelevision &&
      (!environment().searchMode || environment().catalogQuery.isNotEmpty);

  void setHero(StremioMeta item) {
    // Off-TV / blank search prompt the hero isn't rendered, so don't track focus
    // or fire the per-item backdrop-enrichment /meta fetch behind it.
    if (!active) return;
    // A folder tile has no /meta, trailer or playback, so the hero keeps
    // showing the last real title.
    if (item.type == 'folder') return;
    // A catalog/CW card owns the stage again — drop any Canvas favourites
    // override so its art/identity yield to the hero pipeline.
    clearFavouriteFocus();
    // A catalog/CW card just took focus (possibly straight from the IPTV
    // favourites row, which has no row in between) — drop any live IPTV feed
    // so the boxed video region falls back to this item's own trailer.
    clearLiveIptv();
    if (heroItem.value?.id == item.id) {
      // Back on the current hero (a vertical move within the column, or an
      // A→B→A jiggle inside the swap debounce): drop any pending swap to a
      // neighbour focus merely passed through — and RE-ARM the trailer when
      // the move away already tore it down and nothing is resolving. Without
      // the re-arm, a quick jiggle left the hero permanently trailer-less
      // (cleared on the first keypress, never rescheduled — "some cards
      // never even show the loading pill"). A trailer that's already playing
      // or resolving is left completely alone.
      _heroSwapTimer?.cancel();
      if (trailer.value == null && !trailerLoading.value) {
        scheduleTrailer(item);
      }
      return;
    }
    // Instant + cheap on EVERY move: kill any trailer (timer cancels and
    // notifier flips) so the lights-off veils start lifting with the
    // keypress, even though the hero swap itself waits for the rest below.
    clearTrailer();
    // First hero (board just landed) shows instantly. After that, the swap
    // waits for a short DPAD rest — holding a direction across a row costs
    // only the card focus visuals (ring + scale), never a spotlight rebuild
    // plus a backdrop decode per step. This is the Nuvio/Netflix billboard
    // settle debounce from the approved Concept-5 foundations, and the
    // second half of the "navigation feels heavy" fix (the first was the
    // tint cache publishing synchronously).
    if (heroItem.value == null) {
      _applyHero(item);
      return;
    }
    _heroSwapTimer?.cancel();
    _heroSwapTimer = Timer(const Duration(milliseconds: 260), () {
      if (isMounted()) _applyHero(item);
    });
  }

  /// The real hero swap — everything downstream of "focus has RESTED here".
  void _applyHero(StremioMeta item) {
    heroItem.value = item;
    heroEnriched.value = null;
    publishAmbientArt(item, null);
    enrich(item);
    updateTint(item);
    // A NEW title in the spotlight lifts the after-the-feature suppression —
    // fresh context, fresh trailer.
    trailerSuppressed = false;
    scheduleTrailer(item);
  }

  /// The hero id the shell stage's current art belongs to — lets a re-seed of
  /// the SAME title (board reloads: See-All return, Home Rows change,
  /// integrations refresh) keep the enriched backdrop on screen instead of
  /// downgrading to the poster for the ~300ms until enrichment re-lands
  /// (which was a prominent full-screen double-crossfade).
  String? _ambientArtItemId;

  /// Publish the focused title's key art to the app shell's glass stage
  /// (TvAmbientArtStage — the blurred backdrop BEHIND the sidebar and this
  /// board's transparent scaffold). Rest-cadence only: called from
  /// [_applyHero] (260ms settle) and the enrichment landing, never per
  /// keypress. TV Home board only; other modes leave the shell alone.
  void publishAmbientArt(StremioMeta? item, StremioMeta? enriched) {
    if (!trailerActive) return;
    // Layouts whose own ground is INK (Atrium's panel, Deck's and Tonight's
    // fields, Mosaic's veiled wash) must not light the shell: the shell art
    // only shows in the 64px strip behind the ghost rail, so a bright blurred
    // sliver would butt straight into the board's flat ground and read as a
    // seam. Publishing null leaves the shell on its flat page ink, which is
    // exactly what those boards continue.
    if (environment().stageActive && !environment().stagePublishesShellArt) {
      _ambientArtItemId = null;
      if (MainPageBridge.tvAmbientArt.value != null) {
        MainPageBridge.tvAmbientArt.value = null;
      }
      return;
    }
    final backdrop = item?.background?.isNotEmpty == true
        ? item!.background
        : (enriched?.background?.isNotEmpty == true
              ? enriched!.background
              : null);
    // Same title, no backdrop in hand (only the poster fallback), and the
    // stage already shows SOMETHING for it → keep what's showing; the
    // enrichment landing republishes the real backdrop moments later.
    if (backdrop == null &&
        item?.id != null &&
        item!.id == _ambientArtItemId &&
        MainPageBridge.tvAmbientArt.value != null) {
      return;
    }
    final art = backdrop ?? item?.poster;
    _ambientArtItemId = item?.id;
    MainPageBridge.tvAmbientArt.value = (art == null || art.isEmpty)
        ? null
        : art;
  }

  /// Debounced ambient-trailer load for the spotlighted title. The previous
  /// trailer is torn down IMMEDIATELY on any hero change (a playing trailer
  /// under the wrong title is worse than the static backdrop), then a new one
  /// only starts once focus has RESTED on the card — flying across a row costs
  /// nothing but a timer reset, never a resolve or a decoder spin-up. Both
  /// lookups (Cinemeta /meta for the YouTube id, then the stream resolve) are
  /// cached in their services, so re-resting on a recent card starts fast.
  void scheduleTrailer(StremioMeta item, {bool fromSpotlight = false}) {
    // Off-TV nothing ever calls _applyHero (the TV paths that lift the
    // after-playback suppression), so a NEW title arriving through the
    // spotlight dwell lifts it here — fresh context, fresh trailer, the same
    // rule _applyHero implements for TV.
    if (trailerSuppressed &&
        fromSpotlight &&
        item.id != _heroTrailerScheduledItemId) {
      trailerSuppressed = false;
    }
    if (!trailerRenderable || !trailerEnabled || trailerSuppressed) {
      return;
    }
    _heroTrailerScheduledItemId = item.id;
    // Spotlight owns its own hero cadence, so the shared scheduler must not
    // also drive it — two systems interleaving on one hero is how a trailer
    // starts under the wrong title.
    //
    // The guard lives HERE rather than at the call sites: scheduling reaches
    // this method from init, section loads, focus changes, `_applyHero`,
    // route return and sidebar return, and a per-site exclusion would miss
    // one. `trailerActive` is deliberately left style-blind — it governs
    // listener registration across an asynchronously loaded style, and gating
    // it leaks or double-registers listeners.
    if (environment().homeStyle == 'spotlight' && !fromSpotlight) return;
    // A layout with no place to put moving picture (Mosaic) never resolves a
    // trailer at all — the resolve is a network + engine cost for something
    // that would be invisible under its veil.
    if (environment().stageActive && !environment().stageWantsAmbient) return;
    // A Canvas favourite owns the stage (or its live feed does): a catalog
    // trailer must never start beneath it. The next catalog/CW focus goes
    // through setHero, which clears both and reschedules. Safe to skip the
    // reset lines below: every fav-focus path already ran clearTrailer.
    if (environment().hasFavouriteFocus || liveChannel.value != null) {
      return;
    }
    _heroTrailerTimer?.cancel();
    final req = ++_heroTrailerReq;
    if (trailer.value != null) trailer.value = null;
    if (trailerLoading.value) trailerLoading.value = false;
    if (trailerShowing.value) trailerShowing.value = false;
    // Spotlight has already decided that this hero owns the stage. Begin the
    // useful network/decoder work immediately there; other layouts keep the
    // shared 2.4s focus-rest debounce so flying across their rows stays cheap.
    final resolveDelay = fromSpotlight
        ? Duration.zero
        : const Duration(milliseconds: 2400);
    _heroTrailerTimer = Timer(resolveDelay, () async {
      if (!isMounted() || req != _heroTrailerReq) return;
      // The layout may have changed during the dwell — a stage with nowhere
      // to put moving picture must not spin up an engine.
      if (environment().stageActive && !environment().stageWantsAmbient) return;
      // Covered by ANY modal (bottom sheet, dialog — which never reach the
      // PageRoute-only route observer) or a pushed page: a trailer must not
      // start under it. The cover's dismissal path re-arms where relevant
      // (didPopNext for pages); sheets simply wait for the next hero rest.
      if (ModalRoute.of(hostContext())?.isCurrent != true) return;
      // From here the attempt is committed — surface the pill. Every exit
      // below (no trailer, failed resolve, hero moved on) clears it; success
      // keeps it up until the backdrop reports frames (onTrailerPlaying).
      trailerLoading.value = true;
      void fail() {
        if (isMounted() && req == _heroTrailerReq) {
          trailerLoading.value = false;
        }
      }

      // YouTube id: catalog rows rarely carry it, so fall back to the /meta
      // details (the same fetch — and cache — the hero enrichment uses).
      final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
      String? ytId = item.trailerYtId;
      if (ytId == null || ytId.isEmpty) {
        if (imdb == null) return fail();
        try {
          final full = await _stremio.fetchMetaDetails(
            imdbId: imdb,
            type: item.type,
          );
          ytId = full?.trailerYtId;
        } catch (_) {
          // Meta fetch failed — the IMDb backup below may still carry it.
        }
      }
      if (!isMounted() || req != _heroTrailerReq) return;
      // Ambient hero backdrop: resolve at a low cap (small region, weak TV).
      var streams = (ytId != null && ytId.isNotEmpty)
          ? await YoutubeService.resolveStreams(
              ytId,
              maxHeightOverride: YoutubeService.ambientTrailerMaxHeight,
              preferVp9: true,
            )
          : null;
      // Backup source: IMDb hosts its own trailer MP4s, so a YouTube block
      // (or a title with no YouTube id at all) still gets a moving hero.
      if ((streams == null || !streams.hasPlayable) && imdb != null) {
        if (!isMounted() || req != _heroTrailerReq) return;
        streams = await ImdbTrailerService.resolveTrailer(
          imdb,
          maxHeight: YoutubeService.ambientTrailerMaxHeight,
        );
      }
      if (!isMounted() || req != _heroTrailerReq) return;
      if (streams == null || !streams.hasPlayable) return fail();
      trailer.value = streams;
      // Failsafe: a dead/bot-blocked stream can error inside the engine
      // before ever producing a frame, in which case onPlayingChanged never
      // fires (it only reports real transitions) — don't let the pill spin
      // forever on a trailer that will never come.
      Timer(const Duration(seconds: 15), fail);
    });
  }

  /// The hero backdrop's playing signal: frames on screen (true) or engine
  /// teardown/error (false). Ends the loading pill either way, and drives the
  /// spotlight's image-yield crossfade.
  void onTrailerPlaying(bool playing) {
    if (trailerLoading.value) trailerLoading.value = false;
    if (trailerShowing.value != playing) {
      trailerShowing.value = playing;
    }
  }

  /// Kill any pending/playing hero trailer (hero cleared, board reloading).
  void clearTrailer() {
    _heroTrailerTimer?.cancel();
    _heroTrailerReq++;
    if (trailer.value != null) trailer.value = null;
    if (trailerLoading.value) trailerLoading.value = false;
    if (trailerShowing.value) trailerShowing.value = false;
  }

  /// DPAD focus rested on an IPTV favourite card — retune the boxed hero video
  /// region to that channel's live stream. A plain M3U/Xtream favourite's URL
  /// is already playable; a Stremio-addon favourite resolves candidates first
  /// (same async ladder [IptvResultsView] uses for its own inline preview),
  /// guarded by [_heroLiveReq] so a fast DPAD move past it can't land a stale
  /// resolve on top of whatever channel focus has since moved to.
  void setLiveIptv(IptvChannel channel) {
    if (!trailerActive) return;
    if (liveChannel.value?.url == channel.url) return;
    liveChannel.value = channel;
    if (!liveTakeover.value) liveTakeover.value = true;
    _heroLiveCandidates = null;
    final req = ++_heroLiveReq;
    // A live feed pre-empts whatever catalog trailer is mid-flight/playing —
    // instant teardown, same as any other hero change.
    clearTrailer();
    liveUrl.value = null;
    // The shell's glass-stage backdrop and sidebar tint are ALSO the stale
    // catalog title's art (published by [publishAmbientArt]/
    // [publishTintToShell], neither of which this focus path runs) —
    // blank them too rather than leaving that art behind everything,
    // including the sidebar, while an unrelated channel plays.
    MainPageBridge.tvAmbientArt.value = null;
    MainPageBridge.tvHeroTint.value = null;
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      liveUrl.value = channel.url;
      return;
    }
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!isMounted() || req != _heroLiveReq || found.isEmpty) return;
      _heroLiveCandidates = [for (final c in found) c.url];
      liveUrl.value = _heroLiveCandidates!.first;
    });
  }

  /// DPAD focus left the IPTV favourites row (another favourites row, or a
  /// catalog/CW card) — drop the live feed so the boxed region falls back to
  /// whatever catalog trailer [item] owns.
  void clearLiveIptv() {
    _heroLiveReq++;
    final wasLive = liveChannel.value != null;
    if (wasLive) liveChannel.value = null;
    if (liveTakeover.value) liveTakeover.value = false;
    _heroLiveCandidates = null;
    if (liveUrl.value != null) liveUrl.value = null;
    // The unmounting live backdrop can never report playing:false (its
    // dispose doesn't notify), and when the trailer path declines to re-arm
    // (trailers off / suppressed) nothing else resets these — a stuck
    // showing=true kept canvas theater re-firing over a static stage and
    // held the shell's lights off.
    if (wasLive) {
      if (trailerShowing.value) trailerShowing.value = false;
      if (trailerLoading.value) trailerLoading.value = false;
    }
    // Restore the shell's glass-stage backdrop/tint for whatever catalog
    // title the hero already holds. Needed even when DPAD focus returns to
    // the SAME card it was on before IPTV took over: setHero's "back on the
    // current hero" branch doesn't re-run publishAmbientArt/
    // publishTintToShell (no item change to react to), so without this
    // the shell would stay on the blank/neutral state setLiveIptv left
    // it in.
    if (wasLive && trailerActive) {
      publishAmbientArt(heroItem.value, heroEnriched.value);
      // Through the GATE, not straight at the bridge: the ink-ground layouts
      // publish no shell tint, and restoring one here would leave a coloured
      // sidebar sitting on a flat board until something else cleared it.
      publishTintToShell(tint.value);
    }
  }

  /// The boxed hero region's live IPTV feed genuinely failed (refused to
  /// open, errored, or stalled past the first-frame timeout) — step down its
  /// candidate ladder, mirroring the IPTV page's own inline preview
  /// (IptvResultsView._onPreviewPlaybackFailed). No-op for a plain M3U/Xtream
  /// favourite (single URL, no ladder) or once every candidate is exhausted.
  void onLivePlaybackFailed() {
    final candidates = _heroLiveCandidates;
    final current = liveUrl.value;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0 || next >= candidates.length) {
      // Every candidate is dead: forget the cached list so a later attempt
      // re-resolves fresh links instead of replaying the same dead ones for
      // the rest of the 5-minute cache window.
      final channel = liveChannel.value;
      if (channel != null) StremioIptvService.instance.invalidate(channel.url);
      liveUrl.value = null;
      return;
    }
    liveUrl.value = candidates[next];
  }

  /// Mirror the takeover arc onto the app-shell notifier (sidebar rail hide).
  void _relayChromeDim() {
    MainPageBridge.tvChromeDim.value = trailerTakeover.value;
  }

  /// Mirror the ambient trailer's lights-off state onto the app-shell
  /// notifier — the shell veils the sidebar rail in lock-step with the
  /// board's own row/hero veils, so the whole room goes dark together.
  void _relayLightsOff() {
    MainPageBridge.tvStageLightsOff.value = trailerShowing.value;
  }

  // ── Route awareness (Home board trailer only) ────────────────────────────
  // The trailer schedule is time-driven, so without this a pushed route
  // (detail page, player) would let the 2.4s debounce fire UNDER the cover
  // and start a trailer behind it — the backdrop's own RouteAware pause can't
  // help because it mounts after the cover was already pushed and never sees
  // a didPushNext. Kill everything when covered; re-arm the spotlight when
  // the cover pops so browsing resumes its normal rest-to-play.

  void didPushNext() {
    if (!trailerActive) return;
    clearTrailer();
  }

  void didPopNext() {
    if (!trailerActive || !trailerEnabled) return;
    final item = heroItem.value;
    if (item != null) scheduleTrailer(item);
  }

  /// Content playback launched (see the listener registration in
  /// [initState]): kill the trailer NOW (native activity launches never push
  /// a Flutter route, so RouteAware alone can't catch them all) and keep it
  /// off for this spotlight — it must not resume behind or after the feature.
  void onContentPlayerLaunch() {
    if (!trailerRenderable || !isMounted()) return;
    trailerSuppressed = true;
    // The suppression baseline is the hero SHOWING at launch, not the last
    // dwell's item — playback can start before the first dwell (cold open →
    // open a card immediately), or after paging A→B with B's dwell still
    // pending. Without this snapshot the stored id is stale/null and the
    // just-watched title's own dwell would read as "new" and lift the
    // suppression it was meant to hold.
    final showing = showingHeroId();
    if (showing != null) _heroTrailerScheduledItemId = showing;
    clearTrailer();
  }

  /// Any key while the takeover owns the screen restores the board — the UI
  /// is at opacity 0, so this can't be left to hero-change detection alone
  /// (fav-row tiles and same-title cards never change the hero). Observe-only
  /// (always returns false): the key still does its normal job, so SELECT
  /// both restores the board and opens the showcased title.
  bool _onTakeoverKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (trailerTakeover.value <= 0.02) return false;
    clearTrailer();
    return false;
  }

  /// Sidebar focus enter/exit (see the listener registration in [initState]).
  void _onTvSidebarFocusChanged(bool focused) {
    if (!trailerActive || !trailerEnabled || !isMounted()) return;
    if (focused) {
      clearTrailer();
    } else {
      final item = heroItem.value;
      if (item != null) scheduleTrailer(item);
    }
  }

  // ── Dynamic per-title tint ────────────────────────────────────────────────
  // The hero scrim takes on the focused title's dominant poster color, so the
  // screen shifts mood as you browse. Extraction is debounced (only after
  // focus SETTLES — never per card while flying across a row), cached per
  // title, and decodes a 32px thumbnail — negligible on the TV chip.
  final ValueNotifier<Color?> tint = ValueNotifier<Color?>(null);
  final Map<String, Color?> _tintCache = {};
  Timer? _tintTimer;
  int _tintReq = 0;

  void updateTint(StremioMeta item) {
    _tintTimer?.cancel();
    final req = ++_tintReq;
    // ALWAYS defer — cache hits and empty posters included. Publishing a
    // cached tint synchronously here meant every DPAD step over already-
    // visited cards re-rastered every tint consumer (the full-screen mood
    // field, the hero stage, the 450ms scrim tween, the art feathers) — the
    // "navigation feels heavy" regression. The tint is scenery: it only
    // needs to land once focus RESTS, never while scrubbing a row. (Short
    // now that the 260ms hero-swap settle already ran before this fires.)
    _tintTimer = Timer(const Duration(milliseconds: 120), () async {
      final poster = item.poster;
      if (poster == null || poster.isEmpty) {
        tint.value = null;
        publishTintToShell(null);
        return;
      }
      if (_tintCache.containsKey(item.id)) {
        tint.value = _tintCache[item.id];
        publishTintToShell(_tintCache[item.id]);
        return;
      }
      // Via the shared cache: the Home hero re-extracts on every focus rest,
      // and the same posters come back constantly as the user arrows around.
      final color = await DominantColorCache.of(
        poster,
        CachedNetworkImageProvider(poster),
      );
      if (!isMounted() || req != _tintReq) return; // focus moved on — stale
      // Unbounded growth guard; a full clear is fine, extraction is cheap.
      if (_tintCache.length > 300) _tintCache.clear();
      _tintCache[item.id] = color;
      tint.value = color;
      publishTintToShell(color);
    });
  }

  /// Relay the settled tint to the app shell — the sidebar's glass blends it
  /// in and the shell's art stage tints its washes with it. Rest-cadence and
  /// CONSTANT across trailer start/stop, so there's no colour flooding in or
  /// out at playback edges (the old complaint); the room simply wears the
  /// focused film's hue while browsing. TV Home board only.
  void publishTintToShell(Color? color) {
    if (!trailerActive) return;
    // The tint exists to make the sidebar read as glass over the SHELL ART.
    // Layouts that publish no art (ink grounds — see [publishAmbientArt])
    // would just get a coloured rail floating on flat ink, so they stay
    // neutral.
    MainPageBridge.tvHeroTint.value =
        (environment().stageActive && !environment().stagePublishesShellArt)
        ? null
        : color;
  }

  /// Title-treatment art URL derivable SYNCHRONOUSLY from an IMDb id — the
  /// same metahub image Cinemeta's /meta `logo` field points at. Lets the
  /// hero start fetching the logo the moment focus settles instead of after
  /// the /meta roundtrip — the roundtrip gap is what flashed the text title
  /// for a beat before the art swapped in over it (the "title comes as text
  /// then updates to image" complaint). A dead URL (title has no logo art)
  /// falls back to the text title inside [_HeroTitleArt].
  String? derivedLogo(StremioMeta item) {
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return null;
    return 'https://images.metahub.space/logo/medium/$imdb/img';
  }

  /// Debounced backdrop/description enrichment. Catalog list items usually
  /// omit `background`/`description` (they come from the /meta endpoint), so
  /// fetch them lazily — cached in [StremioService], and guarded against the
  /// focus moving on (req id) so a slow fetch never clobbers a newer hero.
  void enrich(StremioMeta item) {
    _heroTimer?.cancel();
    final needsBg = item.background == null || item.background!.isEmpty;
    final needsDesc = item.description == null || item.description!.isEmpty;
    final needsRating = item.imdbRating == null;
    // Catalog list items almost never carry runtime, so without this the /meta
    // fetch (its only source) would be skipped whenever bg+desc+rating are
    // already present — and the hero/takeover runtime would stay blank.
    final needsRuntime = item.runtime == null;
    // Same for the logo title-treatment: catalog items basically never carry
    // it, and without this an item that happens to have bg+desc+rating+runtime
    // (e.g. Continue Watching) would skip the fetch and stay text-titled.
    final needsLogo = item.logo == null || item.logo!.isEmpty;
    if (!needsBg && !needsDesc && !needsRating && !needsRuntime && !needsLogo) {
      return;
    }
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return;
    final reqId = ++_heroReqId;
    // Short: on the board this only fires after the 260ms hero-swap settle.
    _heroTimer = Timer(const Duration(milliseconds: 140), () async {
      final details = await _stremio.fetchMetaDetails(
        imdbId: imdb,
        type: item.type,
      );
      if (!isMounted() || reqId != _heroReqId || details == null) return;
      heroEnriched.value = details;
      // The enrichment usually carries the real backdrop a catalog item
      // lacked — upgrade the shell stage from the poster-blur to it.
      publishAmbientArt(item, details);
    });
  }

  /// Off-TV hero trailer prefs — read at init and RE-read whenever Settings
  /// fires the home-settings bridge, because off-TV Settings is a pushed
  /// route over a surviving Home: without the re-read, flipping the toggle
  /// would do nothing until the tab was recreated. setState because the
  /// board's `trailersEnabled` is a constructor param — its dwell clock only
  /// learns the pref through a rebuild.
  ///
  /// Sound/volume read the DETAIL surface keys off-TV: that is the pair the
  /// settings page has always shown on these platforms, so a stored "sound
  /// off" keeps meaning what it meant. Writes go to both surfaces now, so
  /// the pairs converge on first change.
  Future<void> reloadOffTvTrailerPrefs() async {
    final values = await Future.wait([
      StorageService.getHomeHeroTrailerEnabled(),
      StorageService.getAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.detail,
      ),
      StorageService.getAmbientTrailerVolume(AmbientTrailerSurface.detail),
    ]);
    if (!isMounted()) return;
    final enabled = values[0] as bool;
    updateHost(() {
      trailerEnabled = enabled;
      trailerVolume = (values[1] as bool) ? (values[2] as int).toDouble() : 0;
    });
    if (!enabled) clearTrailer();
  }

  void registerTv() {
    // Ambient hero trailer gates (Home board TV only) — read before the board
    // loads so the seeded first spotlight can already schedule its trailer.
    if (trailerActive) {
      // The hero doesn't change when the user steps out to the SIDEBAR, so
      // the rest-debounce (or a playing trailer) would happily continue under
      // the expanded rail. Kill it on sidebar enter; re-arm the current
      // spotlight on exit so browsing resumes its normal rest-to-play.
      MainPageBridge.addTvSidebarFocusListener(_onTvSidebarFocusChanged);
      // Relay the takeover arc to the app shell so the sidebar rail hides in
      // lock-step with the board.
      trailerTakeover.addListener(_relayChromeDim);
      // Relay the ambient lights-off state too: the rail dims with the rows
      // while a trailer plays instead of glowing beside the darkened stage.
      trailerShowing.addListener(_relayLightsOff);
      // Deliberately NO sidebar tint relay any more: the "colour floods the
      // chrome while the trailer plays" move read as noise, not mood (user
      // call). Playback now dims the stage neutrally instead ("lights down");
      // the rail just stays its quiet dark self. (dispose() already resets
      // the shell's tvHeroTint post-frame, so no stale colour can survive.)
      // Real content playback (from a detail page, Quick Play, anywhere)
      // suppresses the trailer for this spotlight — see trailerSuppressed.
      MainPageBridge.addPlayerLaunchListener(onContentPlayerLaunch);
      // While the takeover owns the screen the board is invisible — ANY key
      // must bring it back, even ones that don't change the hero (fav-row
      // tiles, a same-title card in another row). Observe-only: the key still
      // performs its normal action (SELECT opens the showcased title).
      HardwareKeyboard.instance.addHandler(_onTakeoverKey);
      Future.wait([
        StorageService.getHomeHeroTrailerEnabled(),
        StorageService.getAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
        ),
        StorageService.getAmbientTrailerVolume(AmbientTrailerSurface.homeHero),
      ]).then((values) {
        if (!isMounted()) return;
        final enabled = values[0] as bool;
        updateHost(() {
          trailerEnabled = enabled;
          trailerVolume = (values[1] as bool)
              ? (values[2] as int).toDouble()
              : 0;
        });
        if (!enabled) return;
        // The board usually seeds the hero before this read lands — kick the
        // current spotlight so the billboard still starts on cold open.
        final current = heroItem.value;
        if (current != null) scheduleTrailer(current);
      });
    }
  }

  /// Called at the original shell-detach point, before notifier disposal.
  void detachShell({required VoidCallback unsubscribeRoute}) {
    MainPageBridge.removeTvSidebarFocusListener(_onTvSidebarFocusChanged);
    if (trailerActive) {
      trailerTakeover.removeListener(_relayChromeDim);
      trailerShowing.removeListener(_relayLightsOff);
      MainPageBridge.removePlayerLaunchListener(onContentPlayerLaunch);
      HardwareKeyboard.instance.removeHandler(_onTakeoverKey);
      unsubscribeRoute();
      // Reset the shell notifiers AFTER this frame: dispose can run inside
      // finalizeTree (tab switch mid-takeover) while the tree is locked, and
      // a synchronous write would markNeedsBuild the sidebar's listener
      // mid-unmount.
      if (MainPageBridge.tvChromeDim.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvChromeDim.value = 0;
        });
      }
      if (MainPageBridge.tvHeroTint.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvHeroTint.value = null;
        });
      }
      if (MainPageBridge.tvAmbientArt.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvAmbientArt.value = null;
        });
      }
      if (MainPageBridge.tvStageLightsOff.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvStageLightsOff.value = false;
        });
      }
    }
  }

  void dispose() {
    _heroTimer?.cancel();
    _heroSwapTimer?.cancel();
    _heroTrailerTimer?.cancel();
    _tintTimer?.cancel();
    heroItem.dispose();
    heroEnriched.dispose();
    trailer.dispose();
    trailerLoading.dispose();
    trailerShowing.dispose();
    trailerTakeover.dispose();
    liveUrl.dispose();
    liveChannel.dispose();
    liveTakeover.dispose();
    tint.dispose();
  }
}
