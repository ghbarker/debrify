# Refactor notes

Quirks discovered during lanes. **Keep them**; do not "fix" in a refactor commit.
The orchestrator (or a later dedicated bugfix) owns follow-up.

See `dev/design/REFACTOR_PLAN.md` §2 rule 1.
Phase 2 extractions also follow `dev/design/REFACTOR_PLAN_PHASE2.md` (binding as of #72).

## Phase 2 correction

- **Old G1 steps 1–5 / remaining G3 / G5 follow-ups are not the template.** Wrappers,
  `extension on _SearchScreenState` parts, and pins against the copy do not count.
  New units must compile without the god file's private members (gate g).
- **`refactor/g3-player-prefs` is parked.** Pin+move already exist on that branch
  under the old G3 contract. PlayerPrefs is **S2-3** (with `iptv_prefs`) after
  S2-0…S2-2. Do not merge the parked branch.

## Quirks kept, not fixed

### H1 · Home row registry

- **Rail de-dup.** `_canonicalCanvasRails` now keys rails by row id (`railsById`)
  instead of appending. Duplicate live ids collapse to one rail. Pre-H1 the list
  could theoretically carry two `_CanvasRail`s with the same `_sectionRowId`.
  Keep: a duplicated id is a data bug, not a feature.
- **Wider stray leaves.** `HomeRowRegistry.buildManagerModel` materializes
  enabled extra rows that no family resolved (outage / vanished list) as
  `unavailable` leaves, so a save cannot silently drop them. Pre-H1 only some
  prefixes got this treatment. Keep: it is strictly more conservative.
- **Addon-group merge by name.** Families that share `groupName` (Trakt CW +
  Trakt lists, Simkl CW + Simkl lists, MDBList CW + MDBList lists) merge into
  one manager group. Pre-H1 the manager had separate rails per builder. Keep:
  the manager was always grouped by provider label; the registry made that
  rule uniform.

### T1 · transfer category registry

- **Tracking-prefs apply/send order.** Apply/send now follows
  `TransferCategoryRegistry` iteration, not the old hand-written switch order.
  Payload keys and `ConfigCommand` strings are unchanged. Keep: order is not a
  compatibility surface.
- **Tile icon / colour.** Remote tiles take `TransferCategory.icon` / `.color`.
  A few categories do not match the pre-T1 `_iconFor` / `_colorFor` switch
  pixel-for-pixel. Keep: visual, not wire.
- **Label case.** Registry `label` / `summarizeLabel` is the display string
  (e.g. `PikPak`). Pre-T1 onboarding `_configLabel` had mixed case. Keep:
  not a persisted string.
- **JSON key order.** `jsonEncode` of registry-built maps may emit keys in a
  different order than the old literal maps. Keys themselves are frozen. Keep.
- **`BackupSelection.all()` is non-const.** It now derives from the registry
  (`Set<TransferCategory>`). Call sites that needed a const value still use
  the named constructor. Keep: required for fake-category tests.
- **Double-apply fix.** Profile restore used to apply default-on categories
  twice (named constructor defaults plus an explicit set). T1 made coordinator
  sets explicit so default-on categories are not applied twice. Keep: this was
  a latent bug; do not restore double-apply.

### P2a · Magic TV strings

- **`MagicTvDispatch` is a screen façade**, not a new cloud capability. It
  lives in `magic_tv_screen.dart` and routes string switches through
  `CloudProviderRegistry` / `is` checks. Follow-up should not move it into
  `lib/services/cloud/` from a P2 lane (cloud is P1-owned).
- **Next-channel allowlists are a moved table.** The Real-Debrid / TorBox / …
  allowlists that decide which providers may auto-advance were lifted into
  the dispatch table, not redesigned. Keep the membership identical.

### T2 · tracker commons

- **Local progress is not dedicated.** `WatchProgressSource.local` has
  `isDedicatedProgress: false`, so `TrackingSourcePolicy.load` still returns
  null for local (same as the old `_ => null` arm). Keep: local never had a
  dedicated tracker credential.
- **MDBList adapter ignores `inferredType`.** The new
  `TrackerItemTransformer` method on MDBList does not use `inferredType`.
  Keep: origin transformer behaviour; do not "fix" in a follow-up that is
  not a dedicated bugfix.
- **Out-of-lane callers not chased.** `search_screen.dart` still wires CW
  rows by family singleton; calendar / tracking settings / player scrobble
  still switch. G1 / G5 own those files.

### G5 · scrobble coordinator

- **Simkl is pause-centric.** No POST to `/scrobble/start`. `'start'` and
  `'pause'` both call `scrobblePause`. Heartbeat force-sends pause and leaves
  the local marker `'start'`. Keep: origin Simkl machine.
- **Incomplete series season/episode skips Simkl only.** Trakt still sends
  (latent gap). Keep: pinned in `test/scrobble_video_player_machines_pin_test.dart`.
- **`_traktSeasonEpisode` stays on the player** (skip-segments / resume /
  guide). No TrackerRegistry scrobble factory this phase. Native TV / launcher
  paths still call Trakt/Simkl/MDBList directly.

### G3 · storage split

- **`clearAllHomePageSettings` does not remove Trakt default keys**
  (`home_default_trakt_list_type` / `home_default_trakt_content_type`).
  Keep: origin clearer, pinned in `test/storage_home_prefs_snapshot_test.dart`.
- **Empty `home_tick_sources` writes an empty list**, it does not remove the
  key. Absent key still means all four `TrackingSource`s. Keep: origin setter,
  pinned in `test/storage_home_prefs_snapshot_test.dart`.
- **`'shelf'` (and any unknown `tv_home_style`) coerces to `'canvas'`** on
  both read and write. Keep: origin `kTvHomeStyles` table.
- **Hero `custom` with no ids reads `random`.** `auto` is stored; unknown
  modes and corrupt JSON also fall back to `random`. Keep: origin getter.
- **`trackingSourceRevision++` stays on the StorageService façade** of
  `setHomeTickSources` (HomePrefs cannot import StorageService). Callers
  still bump the notifier.
- **Callers still import `StorageService`.** HomePrefs is a forwarding façade
  only. Remaining Home keys are in HomePrefs (#70). Next: PlayerPrefs.
  `@Deprecated` on forwards waits for Q2.

### G4 · cloud file screens

- **Selection bar stays on both hosts.** Extracting `_buildSelectionBar` into
  the shared screen dropped two `app.shape.br` sites from `kShapeResidue` and
  failed `test/theme/shape_manifest_test.dart` (out of lane). Keep the bar on
  `RealDebridCloudFilesHost` / `TorboxCloudFilesHost` until that test lists
  the new file (and possibly lowers the 490 floor).
- **Premiumize / AllDebrid / PikPak routed** onto `CloudFilesScreen` (G4
  step 2). Selection bars stay on those hosts (PM/AD still use
  `BorderRadius.circular(12)`; PikPak already uses `app.shape.br(12)`).
  Public types and sidebar ids stay frozen. PikPak has no
  `initialSearchQuery` (bind drops the query). PM/AD/PikPak bind stays
  async (`Future<void> Function`); `CloudFilesSource.onSourceSelected`
  remains the RD/TorBox sync type.

### G1'-2 · source edit/add dialogs

- **Movie chrome is `item.type == 'movie'` only.** Any other type (series,
  tv, …) gets series chrome: reorder, "Add Source", "Series Sources (N)",
  Remove All when count > 1. Keep: origin predicate.
- **Empty `initial` or null IMDb returns** from the edit dialog without
  opening the add picker.
- **Reorder `setSources` is not awaited.** Same as origin
  `ReorderableListView.onReorder`. Keep `onReorder` + `newIndex--`
  (not `onReorderItem`); an `// ignore: deprecated_member_use` hides
  the relocated INFO so `analyze_baseline.json` is not grown.
- **Local pick uses `item.type == 'series'`** for folder vs file (not the
  movie-chrome predicate). A `tv` title would take the movie-file picker
  and then `setSources` replace. Keep: two different type checks.

### G1 · step 5 TV stages

- **Empty Spotlight still `break`s to classic.** If every spotlight shelf
  has empty `items`, the host switch falls through instead of rendering the
  Spotlight board. Keep: origin `switch`, pinned in
  `test/tv_home_stage_layouts_pin_test.dart`.
- **`_buildDiscoverStage` stays on the host.** Discover chrome, not a TV
  Home layout. Classic `LayoutBuilder` hero/rows also stay.
- **Library-private `part`s.** Stage widgets are `part of search_screen.dart`
  so they can read host fields. Analyzer diagnostics report the part path;
  C0 baseline identity is `path|code|message`, so moved `cacheExtent` infos
  were retargeted in `tool/analyze_baseline.json` (no new kinds).

### G1 · step 4 Search/Discover screens

- **`searchMode` wins if both flags are true.** Tab index, variant key, and
  analytics name all use `searchMode ? … : (discoverMode ? … : home)`.
  Keep: origin `?:` order, pinned in `test/search_discover_shells_test.dart`.
- **God file stayed in place.** `SearchScreenHost` is still the 18k State;
  this step only split public types and shell contracts. TV stages landed
  in step 5 (#71).

### G1 · step 3 TitleOpener

- **Merged path includes movies.** When `_mergedSeriesPage` is on, both
  `series` and `movie` go to `MergedDetailScreen`. The origin comment said
  movies fall through to `CatalogItemDetailScreen`; the code did not.
  Keep: pinned in `test/title_opener_test.dart`.
- **Merged `showQuickPlay` is always `true`**, including PikPak-only.
  Legacy `CatalogItemDetailScreen` still uses `showQuickPlay: !_pikpakOnly`.
  Keep: two different literals, not a unification.
- **Simkl CW membership is `progress != null`; MDBList is `paused == true`.**
  Local CW is `_cwIds.contains`; Trakt CW is `_traktByImdb.containsKey`.
  Keep: origin predicates.

### G1 · step 2 CatalogSearchController

- **`_restoreHome` does not zero failures.** `CatalogSearchController.cancel`
  clears query/searching and bumps the generation token, but leaves
  `failures` at the last search's count. Keep: origin `_restoreHome`
  behaviour, pinned in `test/catalog_search_controller_test.dart`.

### G2 · settings_screen split

- **Restore-report omitted keys.** `homeCollectionsFailed` and
  `streamBadgeSourcesFailed` feed `hasAnyFailure` but are omitted from the
  snackbar failed-list. Keep: origin formatter quirk, pinned in
  `test/backup_restore_page_test.dart`.
- **`extraPlayerKeywords` stays bound** at `settings_screen.dart` (S1-fix).
  Do not drop the argument when extracting further settings pages.
- **Linux default label is `App folder (default)`.** SAF and Windows share
  `Downloads/Debrify (default)`. Keep: origin
  `DownloadService._appDownloadsSubdir` fallback on Linux.
- **macOS is excluded** from custom download location (sandbox grants
  read-only user-selected access; writable folder needs security-scoped
  bookmarks). Keep: origin comment, not a missing-platform bug.
- **Host keeps a `DownloadLocationController` field** plus three binding
  reads (`supported` / `subtitle` / `openSettings`). Not a method
  forwarder; delete only if a later settings-shell lane owns the field.

### P2e · playback-service strings

- **`PlaybackServiceDispatch` is a service façade**, not a new cloud
  capability. Same pattern as P2a `MagicTvDispatch`. Do not move it into
  `lib/services/cloud/` from a later lane (cloud is P1-owned).
- **`PlaybackCacheFirst.reorder` still string-switches** in
  `lib/services/cloud/` (`torbox` / `premiumize`). Out of P2e (forbidden).
  Keep until a cloud-owned follow-up.

## Regressions (follow-up PRs; do not leave on `main`)

These were **not** declared in the lane PRs. They change user-visible or wire
behaviour and must be restored, not kept as quirks.

| Lane | Regression | Follow-up |
|---|---|---|
| H1 | Canonical board rails regroup section ids by family `canonicalIndex`, so pinned collections no longer lead the board (they sat first in `_sections`: pinned collections, tracker lists, unpinned collections, catalogs). | **merged** `refactor/h1-pinned-collections-lead` (#57) |
| T1 | `_readPikpakWire` returned null when `pikpakPassword` was empty. Both old senders (Send Setup to TV + Transfer Everything) encoded `{email}` (password omitted when empty). | **merged** `refactor/t1-pikpak-empty-password` (#58) |
| S1 | `settings_screen.dart` never passed `extraPlayerKeywords`, so VLC / mpv / Infuse / … names dropped out of Settings search. | **merged** `refactor/s1-extra-player-keywords` (#59) |

### S2-1 · Stremio / social / Debrify TV prefs

- **`debrify_tv_show_watermark` is the show-channel-name key.** The Dart
  symbol is `getDebrifyTvShowChannelName`. Keep: persisted name is frozen.
- **Debrify TV filter getters have no try/catch.** Corrupt JSON throws
  `FormatException`. Stremio catalogs / favorites catch and return empty.
  Keep: origin.
- **`clearAllDebrifyTvSettings` leaves provider, channels, favorites, and
  the external-player notice.** Only display/filter keys and the `engine_tv_`
  / `debrify_tv_use_` / channel-size / quick-play prefixes plus the two
  keyword literals. Keep: origin clearer.
- **YouTube setter writes any int;** only the getter coerces `<= 0` to 1080.
- **Empty Lemmy instance reads as `https://lemmy.world`.** Setter still
  stores the empty string.
- **Adult-content helper is copied** onto `SocialPrefs` and `DebrifyTvPrefs`
  (same body as `StorageService.profileAllowsAdultContent`) so the stores do
  not import the god file. Call sites use `_profileAllowsAdultContent()`.
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.
- **`debrify_tv_style` / `debrify_tv_player_style` stay on StorageService**
  (S2-4). Player/IPTV prefs are S2-3.

### S2-2 · Provider credential prefs

- **CloudSecretPrefs hunks skipped.** Origin ~516–529 / ~549–565 / PM+AD
  API-key helpers / PikPak email+password were already CloudSecretPrefs
  forwards. Not re-extracted. Secret key strings stay `real_debrid_api_key`,
  `torbox_api_key`, `premiumize_api_key`, `alldebrid_api_key`, `pikpak_email`,
  `pikpak_password`.
- **`clearAllIntegrationStates` does not touch PikPak.** It clears RD/TB/PM/AD
  integration+hidden and WebDAV enabled+hidden only. PikPak enabled/hidden
  survive. Keep: origin clearer.
- **`setPikPakRestrictedFolder(null)` leaves subfolder caches.** Only
  `clearPikPakRestrictedFolder` also wipes torrents/tv folder ids.
- **RD endpoint default** is `https://api.real-debrid.com/rest/1.0`. Delete
  restores that default by removing the key.
- **Integration enabled defaults true** (RD/TB/PM/AD). PikPak and WebDAV
  enabled default false.
- **Post-torrent actions default `choose`.** File selection defaults `smart`.
- **WebDAV legacy single-server keys promote** into `webdav_servers_v1` on
  first `getWebDavServers` and write through SecretVault.
- **`clearAllFilterSettings` still clears `default_torrent_provider_v1`**
  via the store's `clearDefaultTorrentProvider` (same key, same remove).
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.
- **PlayerPrefs / IptvPrefs** extracted in S2-3. Tracking stays S2-5.

### S2-3 · Player and IPTV prefs

- **Style keys stayed.** `player_dock_style` / `palette` / `size`,
  `play_loader_style`, `tv_player_controls_style`, `debrify_tv_player_style`,
  `iptv_style`, `iptv_channel_preview_enabled`, `iptv_player_guide_style`
  remain on StorageService for S2-4 (`app_style_prefs`).
- **Completion thresholds stayed.** `movie_completion_threshold`,
  `episode_completion_threshold`, purge/migrate hooks, and
  `_getPlaybackStateMap` stay for S2-6 / S2-7.
- **iOS external player defaults to `vlc`**, not `system_default`.
- **`clearExternalPlayerSettings` drops Android/generic keys only.**
  iOS / Linux / Windows preferred-player keys survive.
- **Empty path/name/command remove the key.** Empty subtitle/audio language
  codes persist (`''`); only `null` clears those two.
- **Unknown skip-segment provider reads and writes `auto`.**
- **`uiSoundsCached` is published before the prefs write.**
- **Android renderer first read migrates null/`direct_surface` to
  `direct_mediacodec` once** (`android_video_renderer_gpu_migration_v1`).
- **IPTV decoder / startup-mode coerce unknown values; network tuning does
  not.**
- **Virtual playlists are dropped on set.** Favorites / continue / list /
  stremio-addon URLs never reach `iptv_playlists`.
- **Last-live and pinned startup blobs are SecretVault-sealed** (Xtream URL
  embeds the password). Empty last-live URL is a no-op; malformed JSON
  reads as null.
- **`setStartupIptvEnabled(false)` removes `startup_mode`.** The comment
  says "leave the mode behind"; the body clears it. Shared keys
  `startup_auto_launch_enabled` / `startup_mode` stay owned by
  StorageService.
- **`warmStartupIptv` last-with-no-channel sets the `firstAvailable`
  sentinel; pinned-with-no-channel leaves the cache null.**
- **`recordIptvWatch` / `getIptvContinueWatching` no-op when tracking is
  off** without deleting stored history.
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.

### M1-1 · Channel cache warmer

- **No generation / warm-token.** `computeChannelCacheEntry` has no
  generation counter. Empty `keywordsToWarm` resets `anySuccess` to
  `accumulator.isNotEmpty`; a failed warm returns
  `torrents: const <CachedTorrent>[]` (drops leftover accumulator) and
  `'No torrents found for these keywords yet.'`. First `failureMessage`
  wins (`??=`). Keep.
- **Empty cache is a miss.** `ensureCacheEntry` is memory-first and does
  **not** write a storage miss back into the map (returns null). Keep.
- **Inclusion-only keyword filter.** `filterCachedTorrentsForKeywords`
  keeps a torrent if it has any allowed keyword. `merge(keywords: matching)`
  unions onto the existing list and does **not** strip the others. Keep.
- **Accumulate override is strict `>`.** Equal seeders keep the old torrent
  body; keywords/sources still union. Empty infohash is a no-op. Keep.
- **Quality filter at READ.** Empty match falls back to the unfiltered pool
  and notifies (snack stays on the host). Playback select filters first;
  `<= 1000` shuffles the whole pool; empty per-keyword pick takes the first
  1000 **unshuffled**. Keep.
- **Quick-play torrent filter is strict** unless `allowFallback` is true
  (partial rebuilds must not start an off-filter source). Keep.
- **TorBox window.** Empty API key returns no hits and keeps the start
  cursor; live walk is chunk 90 / max 2 calls / stop on first hit. Keep.
- **Edit-prune.** A torrent that carries **any** removed keyword is dropped
  entirely (even if it also has kept ones). Prune-to-empty marks `failed`
  and keeps the baseline error (`clearErrorMessage` only when torrents
  remain). Create/update **dialogs** stay on the host (M1-5). Keep.
- **RD size-filter session** lives on the warmer (`rdSizeRejections` /
  `sizeFilterRelaxed`); the relax snack stays injected. Trailer floor
  (`minVideoSizeBytes`) is passed in. Keep.
- **P1b unlock pin path identity.**
  `test/cloud_magic_tv_unlock_pin_test.dart` now scans host +
  `channel_cache_warmer.dart` for `unrestrict['download']` /
  `unrestrict['filesize']` so the filesize read is not a new allowlist
  miss. Same relocate pattern as G1 `cacheExtent` / M1-0 WatchSession.

### V1-3 · subtitle track controller

- **Stored `auto` is no-choice.** A persisted subtitle id of `auto` (audio-only
  persist) falls through to the default-language path so addon auto-select is
  not blocked by mpv's file-default track.
- **Stored `no` is always honored.** It never counts as a default-language
  conflict, including when the global default is `off`.
- **Conflicting bare mpv ordinals lose.** A stored embedded id whose language
  does not match the current default (or when default is `off`) takes the
  default-language path. Ids are file-local ordinals.
- **Addon auto-select defaults to English** when no subtitle-language
  preference is set (`defaultLang ?? 'en'`).
- **Temp-file cleanup stays on host dispose.** Controller owns the delete
  loop; `_VideoPlayerScreenState.dispose` still calls it.
- **Identify sheet was not re-extracted.** Controller calls
  `showIdentifyTitleSearchSheet` / `requestSeasonEpisodeForIdentity`. Host
  keeps `_currentPlaybackTitleForIdentity` and
  `_currentSeasonEpisodeForIdentity`.

### V1-4 · IPTV recording

- **Engine first on Android.** When the engine flag is on and the stream has
  a recordable URL, `LiveRecordingService.start` runs before the tee. Tee
  fallback is only `engine_unsupported` / `fgs_not_allowed` / `missing_plugin`
  on a non-committed profile.
- **Desktop never falls through to the tee.** `DesktopRecordingService.instance.isSupported`
  + `extension: 'ts'`. HLS / no record URL shows the desktop-HLS snack and
  returns; mpv muxers are absent on media_kit's stock libs.
- **Committed profile + no engine URL aborts.** "This stream cannot be
  recorded safely" — no tee fallback.
- **Dispose does not await stop.** `finalizeOnDispose` bumps the start-gen,
  clears tee state, and chains MediaStore publish after `stream-record` is
  cleared. Desktop captures are left running (hub / service owned).
- **Resource lookup prefers a fresh playlist read.** Launch-payload revision
  is fallback only (`source_playlist_id` → `series_playlist_id` →
  `widget.iptvSourceId`).
- **Zap / catch-up / overlay Stack stayed on the host.** Call sites still
  invoke `_stopRecording`; the body moved.

## Process

Gate check **(c)** is tightened (plan §6): the pinning test must be committed
and shown green **before** the move commit, and the PR must include an
origin-diff of each moved body with every difference listed and justified.

P2b / P2c / P2d had pin-before-move commits but **no origin-diff table**. They
stay on `main` (no revert without a behaviour audit); they are not the
template for later lanes. Reject any new review PR that omits the table.

## Out of plan

- **PR #56** (Qwen helper) edits `.cursor/**` (Q3) and is held until Phase 3.
- **PRs #36–#43** (stacked TorBox / web download port) are superseded by **G4**
  (cloud file screens). Close rather than rebase through the refactor.
