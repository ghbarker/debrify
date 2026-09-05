# Debrify code map

An **area → owning-files** index so triage/estimate tooling (and humans) can jump straight to the
right code instead of re-discovering it. Flutter app; code under `lib/{screens,services,widgets,models,utils}`.

> ⚠️ **Grep, don't read whole.** The files flagged 🔴 are huge. Always `grep` for the
> symbol and Read only the surrounding ±40 lines — never read them end-to-end.
>
> Line counts below are `wc -l` on this checkout (`main` after D0, `3c170323`).

## Line counts (`wc -l`)

| File | Lines |
|---|---:|
| `lib/screens/search_screen.dart` | 13 105 |
| `lib/screens/search/` parts (4 files) | 8 321 |
| `lib/screens/video_player_screen.dart` | 16 278 |
| `lib/screens/magic_tv_screen.dart` | 10 716 |
| `lib/services/storage_service.dart` | 8 528 |
| `lib/screens/settings_screen.dart` | 2 899 |
| `lib/screens/torbox/torbox_downloads_screen.dart` | 7 069 |
| `lib/screens/debrid_downloads_screen.dart` | 6 444 |
| `lib/services/video_player_launcher.dart` | 5 769 |
| `lib/services/torrent_playback_service.dart` | 5 340 |
| `lib/services/remote_control/remote_command_router.dart` | 5 100 |

Search `part` files: `lib/screens/search/search_sources.dart` (3 163),
`lib/screens/search/search_hero_widgets.dart` (2 261),
`lib/screens/search/search_stage_widgets.dart` (1 699),
`lib/screens/search/search_card_widgets.dart` (1 198).
TV Home stage parts (7 files, 1 661): `lib/screens/search/stages/*_board_stage.dart`.
Extracted (not parts): `home_board_controller.dart`, `catalog_search_controller.dart`,
`title_opener.dart` (`TitleOpener.open` — catalog detail from the board),
`catalog_search_screen.dart` (Search tab), `discover_screen.dart` (Discover tab),
`search_screen_shells.dart` (tab/variant/landing/dropdown contracts),
`keyword_search_controller.dart` + `keyword_search_screen.dart` (in-tab keyword
torrent search; G1'-3).
TV Home stages (parts of `search_screen.dart`, G1 step 5): `lib/screens/search/stages/`
— `_CanvasBoardStage`, `_AtriumBoardStage`, `_MosaicBoardStage`, `_PromenadeBoardStage`,
`_DeckBoardStage`, `_TonightBoardStage`, `_SpotlightBoardStage`. Dispatch helper:
`tv_home_stage_dispatch.dart` (`resolveTvHomeStageLayout`). Empty Spotlight shelves
fall through to classic. Discover grid/stage chrome is `search/discover_view.dart`
(`DiscoverView`); the host still supplies the actual source panel.

🔴 huge: `lib/screens/search_screen.dart` (13 105) · `lib/screens/video_player_screen.dart`
(16 278) · `lib/screens/magic_tv_screen.dart` (10 716) · `lib/services/storage_service.dart`
(8 528) · `lib/screens/settings_screen.dart` (2 899) ·
`lib/screens/torbox/torbox_downloads_screen.dart` (7 069) ·
`lib/screens/debrid_downloads_screen.dart` (6 444) ·
`lib/services/video_player_launcher.dart` (5 769) ·
`lib/services/torrent_playback_service.dart` (5 340) ·
`lib/services/remote_control/remote_command_router.dart` (5 100).

`lib/widgets/initial_setup_flow.dart` is a 4-line export of
`lib/widgets/onboarding/onboarding_flow.dart` (1 047), not a 4.9k dialog.

## Planned registries (refactor plan §3)

These replace hand-maintained switches. **None of the new registries exist yet**
except `CloudProviderRegistry` (half-migrated; capability split is **P1**).

| Registry | Lane | Replaces today |
|---|---|---|
| `CloudProviderRegistry` (exists) + capability interfaces | **P1** | remaining provider-string switches (playback, launcher, bulk-add, Magic TV, Stremio TV, storage, settings) |
| `HomeRowRegistry` | **H1** | `_sectionRowId`, `_canonicalOrderIds`, group builders, id-prefix checks in `lib/screens/search_screen.dart`, `lib/screens/settings/home_sections_filter_page.dart`, `lib/services/home_list_rows.dart` |
| `TransferCategoryRegistry` | **T1** | backup build/summarize/apply, `BackupSelection` / `BackupSummary` / `RestoreReport` field triplets, remote router's five maps, export/transfer-all tiles, onboarding labels |
| `SettingsPageRegistry` | **S1** | the 6-site registration in `lib/screens/settings_screen.dart` + `lib/screens/settings/settings_tv_layout.dart`, the search index `leaf()` tables |
| `TrackerRegistry` (exists) | **T2** | per-tracker `switch` in tick policy, scrobble targets, CW row wiring |

Until **T1** lands, adding a remote/backup transfer category still needs the
**11-site checklist** (plan §0: “11 registrations”; §3 maps that to the three
backup switches, the three Backup* field triplets, and the router’s five maps).
Consumer files from the plan table (paths that exist on this checkout):

1. `lib/services/backup_restore_service.dart` — `buildBackup` / `summarize` / `applyBackup`
2. `lib/services/backup_restore_service.dart` — `BackupSelection` field
3. `lib/services/backup_restore_service.dart` — `BackupSummary` field
4. `lib/services/backup_restore_service.dart` — `RestoreReport` field
5. `lib/services/remote_control/remote_command_router.dart` — map 1 of 5
6. `lib/services/remote_control/remote_command_router.dart` — map 2 of 5
7. `lib/services/remote_control/remote_command_router.dart` — map 3 of 5
8. `lib/services/remote_control/remote_command_router.dart` — map 4 of 5
9. `lib/services/remote_control/remote_command_router.dart` — map 5 of 5
10. `lib/widgets/remote/remote_config_export.dart` — Send Setup tiles (plan: export)
11. `lib/widgets/remote/remote_transfer_all.dart` — Transfer Everything tiles (plan: transfer-all)

Same plan table also lists (not extra “sites”, but still consumers until T1/S1):

- `lib/widgets/onboarding/onboarding_flow.dart` — `_configLabel`
- `lib/services/profiles/profile_restore_coordinator.dart` — `BackupSelection` literals
- `lib/screens/settings/backup_restore_page.dart` — backup/restore UI (`backupSummaryLines` / `formatRestoreReport`; G2, moved from `settings_screen.dart`)
- `lib/screens/settings/download_location_controller.dart` — download-location picker (`DownloadLocationController`; G2, moved from `settings_screen.dart`)

`ConfigCommand` **strings** are a frozen compatibility surface. Do not rename them.

## Cross-cutting hubs (touched by many features)
- **`lib/screens/search_screen.dart`** 🔴 — Home board host (`SearchScreenHost`): continue-watching rows, catalog rows,
  favourites rows, the D-pad `_BoardCell` focus grid, poster sizing (`_railPosterW`), bind-sources entry.
  Public `SearchScreen` is a G4-style wrapper (`main.dart` constructors unchanged). Search tab is
  `lib/screens/search/catalog_search_screen.dart` (`CatalogSearchScreen`, MainTab 17); Discover is
  `lib/screens/search/discover_screen.dart` (`DiscoverScreen`, MainTab 18). Both wrap the same host
  so they share `HomeBoardController`, `CatalogSearchController`, and `TitleOpener`. Shell contracts
  live in `lib/screens/search/search_screen_shells.dart`.
  Detail opening is `lib/screens/search/title_opener.dart` (`TitleOpener`; State `_openItem` is a forward).
  Catalog play/resume resolve is `lib/services/playback/catalog_play_resolver.dart`
  (`CatalogPlayResolver` — meta + tracker snapshots → `PlaySelection`/`ResumeInfo`;
  host `_onCatalogPlay` keeps the overlay and resolver orchestration).
  Selection metadata/art, addon identity, service launch and Sources navigation are
  `lib/screens/search/selection_playback_owner.dart` (`SelectionPlaybackOwner`,
  `SelectionPlaybackRoutes`: live TV read, bound refresh, full refresh).
  `buildSearchSources` in `lib/screens/search/search_sources.dart` forwards to the
  unchanged private Sources widget. Owner → legacy host library → owner remains
  a legal cycle, not independent Discover ownership. Host `_playSelection` (32
  lines) retains async entry/listener try/finally/State.mounted; `_browseSelection`
  (24 lines) retains logging and the empty-ID guard before State.context. Both
  adapters expire with real G17/Q2 migration. G17e: 93 net host Leaves, production
  +90 net lines before docs; **zero** credit against the 750 standalone target.
  Source edit/add dialogs are `lib/widgets/sources/source_binding_dialogs.dart`
  (`SourceBindingDialogs` — meta + configured cloud/local options → persist /
  torrent+keyword bind callbacks; host `_handleEditOrSelectSource` stays the entry).
  Cloud route callbacks: `lib/screens/search/source_binding_routes.dart`
  (`SourceBindingRoutes.cloud`).
  In-tab keyword torrent search is `lib/screens/search/keyword_search_controller.dart`
  (`KeywordSearchController`, `KwPreservedState`) +
  `lib/screens/search/keyword_search_screen.dart` (`KeywordSearchScreen`).
  Host `_switchMode` is the thin launcher (policy + query handoff);
  `_openKeywordBind` still pushes `_SourcesScreen` with `keywordSeed`.
  Tracker + local Continue Watching is `lib/screens/search/continue_watching_controller.dart`
  (`ContinueWatchingController`, `CwRow`, `CwKind`) +
  `lib/screens/search/continue_watching_row.dart` (`ContinueWatchingRow`,
  `CwFocusOwner`, `syncCwNodes`). Host keeps Home board chrome, Discover
  CW landing, `_addonForContinue`, and thin loader/open wrappers.
  Favourites state, loaders, action flows and deferred-down focus live in
  `lib/screens/search/fav_rows_controller.dart` (`FavRowsController`,
  `FavouritesIptvListRow`); classic rows render through
  `lib/screens/search/fav_row.dart` (`FavRow`). These retain screen/UI dependencies.
  Host supplies live State/context/update and cross-row callbacks, keeps stage
  composition, and disposes the favourites nodes in its existing disposal order.
  `FavRowsController.loadMyWatchlist` delegates read/partition to
  `lib/services/home/my_watchlist_loader.dart` (`MyWatchlistLoader.load`);
  the adapter retains mounted/commit, node synchronization and autofocus.
  Bound-source data and sequential reads live in
  `lib/screens/search/search_content_data.dart` (`SearchContentData`);
  the host retains snapshot capture, mounted checks and stable-map UI commits.
  Discover focus/trailer signals, layout cache, settings bridges and timer live in
  `lib/screens/search/discover_lifecycle.dart` (`DiscoverLifecycle`); eager host
  retains construction, preference listener and disposal. Three live aliases and
  focus forwarding expire with real G17 ownership / Q2; content/actions stay hosted.
  `lib/screens/search/discover_view.dart` (`DiscoverView`) borrows that lifecycle,
  TV flag and raw panel; owns grid/stage composition and private backdrop/veils/dim.
  Shared `HeroTrailerLoadingPill` / `HeroAmbientChip` and private States live in
  `lib/screens/search/trailer_status_chips.dart`, also used by existing Home consumers.
  No view/chip import of the legacy host. Fav/CW effects and init/dispose remain
  hosted: 419 physical host Leaves, production +37 net lines, UI relocation rather
  than pure logic. This is not standalone Discover or automatic 750-target closure.
  Hero state, focus-rest/enrichment timers, ambient trailers/live IPTV and shell
  art/tint/chrome relays live in `lib/screens/search/hero_presenter.dart`
  (`HeroPresenter`, `HeroEnvironment`). This remains screen/UI presentation,
  with typed environment/context/update callbacks; no pure-logic claim.
  Host keeps PageRoute subscription and focus recovery before trailer rearming.
  Its 15 property and 5 callback aliases (21 physical lines) serve existing
  host/stage consumers; removal with caller migration is G1'-8, not a new part.
  TV Home stage layouts are `lib/screens/search/stages/` (`_CanvasBoardStage` and friends);
  the host keeps `_homeStyleEffective`, rails, focus, and the classic `LayoutBuilder`.
- **`lib/services/storage_service.dart`** 🔴 — public static façade for SharedPreferences/persisted
  state (settings, continue watching (cap 50), playback state, favourites, provider toggles,
  home disabled-sections). **G3 slice 2:** remaining Home keys (`home_disabled_sections_v1`,
  extra rows, order, hero source, tick sources, Home hero-trailer, `tv_home_style`) also
  live in `lib/services/storage/home_prefs.dart` (`HomePrefs`); StorageService forwards
  and re-exports `HomeCardOrientation`, `HomeHeroSourceMode`, `HomeHeroSource`,
  `HomeExtraRow`. **S2-1:** Stremio TV, social (reddit/lemmy/youtube), and Debrify TV
  prefs live in `lib/services/storage/stremio_tv_prefs.dart` (`StremioTvPrefs`),
  `social_prefs.dart` (`SocialPrefs`), and `debrify_tv_prefs.dart` (`DebrifyTvPrefs`);
  StorageService forwards.   **S2-2:** provider-credential *settings* live in
  `lib/services/storage/provider_credential_prefs.dart` (`ProviderCredentialPrefs`);
  CloudSecretPrefs still owns RD/TB/PM/AD/PikPak secret keys.
  **S2-3:** player A/V / external-player / skip-segment / UI-feedback / network
  tuning live in `lib/services/storage/player_prefs.dart` (`PlayerPrefs`); IPTV
  playlist / decoder / last-live / startup / series-audio / CW-tracking live in
  `lib/services/storage/iptv_prefs.dart` (`IptvPrefs`).
  **S2-4:** sync style caches (looks, docks, chrome, launch ident, Discover
  layout, TV UI scale / hero artwork) live in
  `lib/services/storage/app_style_prefs.dart` (`AppStylePrefs`).
  **S2-5:** tracking source policy, catalog-sync switches, and Trakt / Simkl /
  MDBList credentials live in `lib/services/storage/tracking_prefs.dart`
  (`TrackingPrefs`, owns `trackingSourceRevision`). `home_tick_sources` stays
  on HomePrefs; TrackingPrefs bumps the revision after that write.
  **Residual filters:** `lib/services/storage/default_torrent_filter_prefs.dart`
  owns five default-filter JSON String keys and ten get/set bodies. Its
  `clearDefaults(ProfilePreferences)` removes five keys in order on captured
  preferences; StorageService retains capture and the separate provider reset
  phase (including the profile-switch quirk and accepted helper-await boundary).
  Ten public facades expire with Q2 caller migration; this slice removes44 host
  lines, adds57 production lines overall, and leaves783 explicit S2-6/S2-7 debt.
  Key ownership pin: `lib/services/storage/storage_key_ownership.dart`
  (`byKey` — every declared / inline / interpolated prefs name, one store).
  **Façade rule (S2-0):** `StorageService.x` stays a forwarding façade until callers
  move; `@Deprecated` waits for Q2; encodings and key **strings** are frozen.
  Remaining domains stay on StorageService until S2-6…S2-7.
- **`lib/services/torrent_playback_service.dart`** 🔴 — provider-agnostic play/add/bind pipeline.
  Magnet add, hashless bound replay, download-picker lazy URLs, launcher/TV
  unlock, in-app player unlock, and Stremio TV torrent resolve go through
  `lib/services/cloud/` (`CloudProviderPort` + `CloudProviderRegistry`).
  See **Debrid providers & cloud** below. Playback still exposes one-line
  delegates onto the registry so god-file call sites do not change.
- **`lib/main.dart`** — app shell + nav branch (TV rail / desktop rail / `MobileFloatingNav`), tab indices.

## Search, sources & addons
- Aggregation/sort/dedup: `lib/services/torrent_service.dart` (`searchAllEngines`, `_deduplicateAndSort`,
  keyword-search engines).
- Stremio addons: `lib/services/stremio_service.dart` (`_fetchStreamsFromAddon`, `_convertToTorrents` —
  where addon order + labels get overwritten), `lib/models/stremio_addon.dart` (`StremioStream.fromJson`,
  `sizeFromTitle`), `lib/services/stremio_marketplace_service.dart`, `lib/screens/addons/addon_hub_screen.dart`.
- Indexer managers (Prowlarr/Jackett): `lib/services/indexer_manager_service.dart`
  (`_searchProwlarr*`, Torznab), `lib/models/indexer_manager_config.dart`,
  `lib/screens/settings/indexer_managers_settings_page.dart`.
- Scraper "engine" system (YAML-config, **not** a code-plugin runtime): `lib/services/engine/`.
- **Filters**: `lib/models/torrent_filter_state.dart` (QualityTier/RipSource/AudioLanguage/SizeBucket dims),
  format/HDR tag detection already exists in `lib/utils/format_tag_detector.dart` +
  `lib/utils/torrent_coverage_detector.dart` + `lib/utils/{movie,series}_parser.dart`. Result row UI:
  `lib/widgets/torrent_result_row.dart`; source picker: `lib/screens/video_player/widgets/source_sheet.dart`.
  Home/catalog bound-source edit/add dialogs: `lib/widgets/sources/source_binding_dialogs.dart`
  (`SourceBindingDialogs`). In-tab keyword torrent search:
  `lib/screens/search/keyword_search_controller.dart` +
  `lib/screens/search/keyword_search_screen.dart`.

## Debrid providers & cloud

The cloud port is a **half-migration**. New playback/add/unlock work belongs on
`CloudProviderPort` adapters under `lib/services/cloud/`. Many feature screens
still string-match provider ids (P2). Do not “fix” those switches in a docs
lane; list them.

**Port, registry, adapters**

- Contract: `lib/services/cloud/cloud_provider_port.dart` (`CloudProviderPort`).
  One fat interface; unsupported methods throw `CloudUnsupported` (P1 splits
  this into capabilities).
- Features: `lib/services/cloud/cloud_port_feature.dart` —
  `CloudPortFeature.forProvider` / `supports`. False means do not call; a
  supported method may still return null on a miss.
- Registry: `lib/services/cloud/cloud_provider_registry.dart`
  (`CloudProviderRegistry.production()`). Lookup dialects stay split:
  `tryParse` vs `fromStoredId` vs `fromPlaybackId`. Magnets / TPS picker
  strings use `require` (`tryParse` so `realdebrid` still hits RD). Playlist
  unlock uses `requireId`, not `tryParse(plan.playbackId)`.
- Adapters: `lib/services/cloud/rd_cloud_provider.dart`,
  `lib/services/cloud/torbox_cloud_provider.dart`,
  `lib/services/cloud/premiumize_cloud_provider.dart`,
  `lib/services/cloud/alldebrid_cloud_provider.dart`,
  `lib/services/cloud/pikpak_cloud_provider.dart`.
- Ids / display names / chips / overlay titles / credential keys:
  `lib/services/cloud/cloud_provider_id.dart`. Flutter chrome:
  `lib/widgets/cloud_provider_chrome.dart`.
- Credentials: `lib/services/cloud/cloud_credentials.dart` —
  `configured(id, CloudConfiguredCheck)` with three dialects (`playback` /
  `magnet` / `stremioPicker`). P1 will add a fourth surface wrapper later;
  `StremioTvResolveGate.canAttempt` is per-torrent skip, not a fourth
  `configured()` flavour. Keys themselves live in
  `lib/services/storage/cloud_secret_prefs.dart` (`CloudSecretPrefs`, must
  match `CloudProviderId.credentialKey`); `StorageService` remains the public
  static API.
- Unlock plan: `lib/services/cloud/cloud_unlock_plan.dart` (`CloudUnlockPlan`
  on `CloudProviderId`; `fromPlaybackId` for `entry.provider` — playlist
  `realdebrid` is not RD; RD is `restrictedLink`). Launcher vs player differ
  only at incomplete Premiumize and empty `restrictedLink`. Player wrap brand
  is `CloudProviderId.playerWrapBrand`. Player-screen HTTP wrap is typed
  (`CloudMetadataMissing` / `CloudMissingApiKey` rethrow; other errors become
  `$brand link failed`).
- HTTP clients remain in `lib/services/debrid_service.dart` (Real-Debrid),
  `lib/services/torbox_service.dart`, `lib/services/premiumize_service.dart`,
  `lib/services/alldebrid_service.dart`, `lib/services/pikpak_api_service.dart`.

**What already goes through the registry** (do not reimplement as switches)

- TPS magnet add / bound replay / lazy playlist URL.
- Stremio TV `resolveStremioTorrent` (`realdebrid` + auto order with PikPak
  before Premiumize; null on miss). Stremio TV *picker* rows are
  `CloudCredentials.stremioPickerChoices` (RD/TB key-only, PikPak
  enabled-only, PM/AD toggle+key — not `isConfigured()`). Settings page
  still lists RD/TB/PikPak only (`lib/screens/settings/stremio_tv_settings_page.dart`).
- Debrify TV file prepare is `prepareMagicTv` (`real_debrid`; infohash-only
  magnet; random unseen file; RD/AllDebrid `supports(magicTvPrepare)` is
  false). Locked-link queues are `prepareMagicTvLockedLinks`.
  Live RD/AD unlock is `CloudMagicTvRdUnlock` / `CloudMagicTvAdUnlock`
  (`lib/services/cloud/cloud_magic_tv_unlock.dart`) — same Maps / String
  as `DebridService.unrestrictLink`, `addTorrentToDebridPreferVideos`,
  and `AllDebridService.unlockLink`. The port looks up the API key via
  `CloudCredentials`; Magic TV still passes `apiKey` until M1. Distinct
  from `CloudUnlock.unlockPlaybackEntry` (String URL), `CloudMagnetAdd`,
  and locked-link prepare. Capability `is` checks only — no fat-port
  throw-stubs. `CloudPortFeature.magicTvRdUnlock` / `magicTvAdUnlock`.
- Player-screen unlock is `unlockPlayerScreenEntry` (wraps HTTP as
  `Torbox link failed`; incomplete Premiumize throws).
- `CloudPortFeature.cachedHashes` is TorBox `checkcached` only — not
  Premiumize `checkCache` (positional bools). `CloudPortFeature.checkCache`
  is Premiumize only. Stremio auto-play (`StremioTvTorboxCache.load`) maps
  missing key to empty; explicit `torbox` / `premiumize` filtering is
  `StremioTvCacheFilter.apply`. Playback cache-first is
  `PlaybackCacheFirst.reorder`.
- TorBox whole-torrent ZIP permalink is `zipPermalink` (not web-download ZIP,
  not Premiumize transfer+zip). TorBox web-download ZIP is `webZipPermalink`
  (`web_id`, not `torrent_id`). Torrent file `requestdl` is `fileDownloadLink`.
- Premiumize transfer create is `createCloudTransfer`. Transfer+zip URL is
  `createTransferZip`. Not-cached keep-downloading is `queueUncachedMagnet`.
  Magnet share-sheet TorBox `createtorrent` is `createMagnetTorrent`.
- Bind-source PM/AD/PP browsers: `lib/screens/cloud/cloud_browse_select_source.dart`.

**Still on string matches** (high level; P2 owns the migration, not this lane)

- Magic TV / Debrify TV: `lib/screens/magic_tv_screen.dart` (**P2a**, **M1**) —
  provider constants/chips and thin `_watch*` entry wrappers. Provider watch
  orchestration lives in `lib/screens/debrify_tv/watch/*_watch_flow.dart`.
  Typed host bindings retain captured-key `DebridService.unrestrictLink` /
  `addTorrentToDebridPreferVideos` and `AllDebridService.unlockLink` calls;
  this is not a completed P1b port migration (its ports reread credentials).
- Stremio TV screen + picker: `lib/screens/stremio_tv/` (**P2b**).
- Launcher Real-Debrid spellings + bulk-add: `lib/services/video_player_launcher.dart`,
  `lib/services/torrent_bulk_add_service.dart` (**P2c**).
- Playlist / cloud / default-provider picker: `lib/screens/playlist_content_view_screen.dart`,
  `lib/services/playlist_player_service.dart`, `lib/screens/cloud_screen.dart`,
  `lib/screens/settings/provider_settings_page.dart` (**P2d**).
- Storage provider toggles: `lib/services/storage_service.dart` (still ~15
  provider-string sites). Magnet deep-link `isMagnetConfigured` vs playback
  `isConfigured` stay different dialects on `CloudCredentials`.

Strangler policy lives in `dev/design/REFACTOR_PLAN.md`; `.cursor/rules/debrify-refactor.mdc`
is an editor mirror, not the source of truth. How to add a provider:
`dev/design/ADDING_A_PROVIDER.md`.

- File-tree browse (per provider, post-add): `debrid_service.getTorrentFolderTree`,
  `lib/utils/{rd,torbox}_folder_tree_builder.dart`, `lib/screens/playlist_content_view_screen.dart`.
- Cloud/downloads screens: `lib/screens/cloud_files/cloud_files_screen.dart`
  (`CloudFilesScreen` + local `CloudFilesSource`; **RD + TorBox + Premiumize
  + AllDebrid + PikPak** routed — G4). Hosts: `lib/screens/debrid_downloads_screen.dart`,
  `lib/screens/torbox/torbox_downloads_screen.dart`,
  `lib/screens/premiumize/premiumize_files_screen.dart`,
  `lib/screens/alldebrid/alldebrid_files_screen.dart`,
  `lib/screens/pikpak/pikpak_files_screen.dart`. Selection bars stay on
  hosts (shape-manifest floor). Hub: `lib/screens/cloud_screen.dart`.
- WebDAV: `lib/services/webdav_service.dart` (read/browse only — no upload yet).

## Players
- In-app player: `lib/screens/video_player_screen.dart` 🔴 (subtitles via media_kit
  `subtitleViewConfiguration`; per-key D-pad handlers arrowUp/Down/Left/Right;
  scrobble via `ScrobbleCoordinator` + `ScrobbleTarget`s in
  `lib/services/scrobble/`). Launch ctor fields:
  `lib/screens/video_player/player_launch_config.dart` (`PlayerLaunchConfig`;
  `VideoPlayerScreen` public constructor stays). Resume:
  `lib/screens/video_player/resume_controller.dart` (`ResumeController` +
  `ResumeContext` / `ResumeSession`; host keeps `_ResumeSession` adapter).
  Shared player dialog: `lib/widgets/player/spotlight_dialog.dart`
  (`showSpotlightDialog`, `SpotlightDialogCard`).
  Identify-title sheet: `lib/widgets/player/identify_title_sheet.dart`
  (`showIdentifyTitleSearchSheet` → `StremioMeta?`). Subtitle/track restore,
  persist, diagnostics, and addon fetch:
  `lib/screens/video_player/subtitle_track_controller.dart`
  (`SubtitleTrackController` + `SubtitleTrackSession`; host keeps
  `_SubtitleTrackSession` adapter and title/season resolvers).
  IPTV recording (libmpv tee, Android engine, desktop capture):
  `lib/services/playback/iptv_recording_controller.dart`
  (`IptvRecordingController` + `IptvRecordingSession`; host keeps
  `_IptvRecordingSession` adapter; overlay reads `supported` / `active`
  notifiers).
  IPTV zap ring, page cache, prefetch, catch-up, and zap banner:
  `lib/screens/video_player/iptv_zap_controller.dart`
  (`IptvZapController` + `IptvZapSession`; host keeps `_IptvZapSession`
  adapter; `onSwitch(channel)` is the host `_switchToIptvChannel`; overlay
  reads banner `ValueNotifier`s via host getters).
  Controls overlay:
  `lib/screens/video_player/widgets/controls.dart`. Track/source sheets: `lib/screens/video_player/widgets/`.
- Launch + native TV: `lib/services/video_player_launcher.dart` 🔴 (`_launchOnAndroidTv`, `_push`),
  `lib/services/android_tv_player_bridge.dart`, native Kotlin
  `android/app/src/main/kotlin/com/debrify/app/MainActivity.kt`,
  `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`.
- External players: `lib/services/external_player_service.dart`, `lib/models/*_external_player.dart`.

## IPTV
- Playlist/M3U/Xtream: `lib/services/iptv_service.dart` (`parseContent`), `lib/utils/m3u_parser.dart`
  (tvg-id + EPG url), `lib/services/xtream_codes_service.dart`, `lib/models/iptv_playlist.dart`.
- EPG: `lib/services/iptv_epg_service.dart`, `lib/services/xmltv_epg_source.dart`.
- Stremio-addon-as-IPTV bridge: `lib/services/stremio_iptv_service.dart` (treats each catalog meta as one
  channel). UI: `lib/widgets/iptv/`, `lib/screens/settings/iptv_settings_page.dart`.

## Debrify TV (keyword channels)
- `lib/screens/magic_tv_screen.dart` 🔴 (favourites are an unordered `Set`; literal keyword match
  `_parseKeywords`; retained channel-routing/native-launch delegates).
  Watch session: `lib/screens/debrify_tv/watch_session.dart` (`WatchSession` +
  `ProgressSink`; screen keeps `_queue` / `_isBusy` accessors).
  Channel cache warmer: `lib/services/debrify_tv/channel_cache_warmer.dart`
  (`ChannelCacheWarmer` — keyword warm, cache read/filter, TorBox window,
  quality filter, playback select; snacks stay on the host).
  Channel import/export flow: `lib/screens/debrify_tv/channel_import_export_flow.dart`
  (`ChannelImportExport` + `ChannelImportExportHost` / `ProgressSink` owns
  zip/yaml/text/community/url/share/delete-all UI, I/O and persistence ordering).
  Parsing/serialization: `lib/services/debrify_tv/channel_import_export.dart`
  (`parseChannelText`, `serializeChannelYaml`, zip/yaml compute helpers and
  format/type/name helpers); no widget, screen, host or repository dependency.
  Dialogs and screen-facing flow export: `lib/screens/debrify_tv/import_export_dialogs.dart`.
  M1-fix live origin pin: `test/channel_import_export_layering_fix_test.dart`;
  the older `magic_tv_channel_import_export_pin_test.dart` is inventory only.
  Existing host seam adapters remain through M1-5/M1-6; review their removal
  after those callers migrate. The flow's YAML cache-read wrapper remains
  the I/O boundary and has no planned expiry. Channel editor and Add-keyword
  helper: `lib/screens/debrify_tv/dialogs/channel_editor_dialog.dart`
  (`ChannelEditorDialog.open`, live TV/profile/mounted reads; keyword limit 1000).
  Shared editor/settings chip: `lib/screens/debrify_tv/widgets/spotlight_choice_chip.dart`.
  Create/update persistence and load/provider-sync/quick/watch timing remain on the host.
  Playback settings owner: `lib/screens/debrify_tv/channel_playback_settings_state.dart`
  (`ChannelPlaybackSettingsState`, 18 values, no I/O/automatic notification).
  Settings renderer: `lib/screens/debrify_tv/dialogs/channel_playback_settings.dart`
  (`showChannelPlaybackSettings`, six explicit UI/runtime capabilities).
  The 18 temporary host aliases are removed; callers access the same settings owner.
  Editor/settings UI boundaries, including Reset completion, remain Q2 composition
  debt. Shared filter identity and serial persistence order are preserved. Origin UI/helper pins:
  `test/magic_tv_dialog_settings_origin_test.dart` (desktop; no TV-focus or dead
  quick-card coverage claim). M1-3 watch flows: `ProviderWatchFlow` owns Quick
  Play orchestration; `TorboxWatchFlow`, `PikpakWatchFlow`, `PremiumizeWatchFlow`,
  `AlldebridWatchFlow`, and `RealDebridWatchFlow` own per-provider/cached paths
  under `lib/screens/debrify_tv/watch/`. `QuickWatchSearchAccumulator` in
  `provider_watch_flow.dart` synchronously shares TorBox/PikPak result accumulation;
  each invocation keeps its own dedup map, while leaves retain awaits, cancellation
  and terminal fallback. Live pins: `test/magic_tv_watch_dedup_origin_test.dart`.
  This first phase does not complete the five-flow dedup target. `WatchFlowBindings` keeps live host
  state, navigation, existing preparation/prefetch/launcher callbacks and
  captured-key service calls. Six entry wrappers and five dead cached binding slots
  are removed. Four provider-specific quick-dispatch dependencies now belong to
  `ProviderWatchFlow`; their host forwarders and shared binding slots are removed,
  not the dependencies. The lazy owner evaluates bindings before cached leaf tearoffs.
  First owner access may allocate all four side-effect-free leaf objects earlier;
  construction invokes no playback, I/O or credential reads. No identical allocation
  timing or pure-port claim; captured-key and UI composition debt remains.
  Live origin/runtime orchestration pins: `test/magic_tv_provider_watch_origin_test.dart`
  (21 cases; actual route requests/next callbacks, not native video playback).
  `test/cloud_magic_tv_unlock_pin_test.dart` is supplemental inventory only.
  M1-4 channel routing/native handoff: `lib/screens/debrify_tv/channel_switch_flow.dart`
  (`ChannelSwitchFlow`: `switchToChannel`, `requestNextChannel`, `requestChannelById`,
  `resolveChannelNumber`, `androidTvChannelMetadata`, and the TorBox/RD/PikPak
  Android TV launchers). `WatchSession` remains a plain state object. Existing
  `WatchFlowBindings` adds live `isAndroidTv` / `getChannelKeywords` and write access
  to the existing current-channel field; cache access uses the same cache-warmer map.
  Seven live host delegates remain for provider-flow and initial-watch callers as
  Q2 composition debt. Host-true/bridge/native-positive
  launch/onFinished still needs device-runtime proof. `test/magic_tv_channel_switch_origin_test.dart`
  pins desktop switches, host early rejection, Flutter-route continuation and
  capture-before-held-prepare-completion behavior;
  exact cooldown/key-read order is body-diff evidence, not a timing-test claim.
  Queue preparation/lifecycle: `lib/services/debrify_tv/queue_prefetcher.dart`
  (`QueuePrefetcher`, shared `WatchAllDebridPrepared` interface and private AD result).
  It shares the existing queue/seen sets/settings instance and retains live mounted
  and request-builder inputs; watch flows keep captured-key calls and live bindings.
  `test/magic_tv_queue_prefetch_origin_test.dart` pins RD/AD preparation, held-stop
  completion, failure-tail rotation and channel restart. Preference-read epoch races,
  competing starts, lookahead edges and native-positive paths remain unproven.
  Seven shared routing callbacks and UI boundaries require Q2 composition review;
  this expiry slice does not close all M1 debt or claim a pure port.
  Default pick / overlay strings: `lib/services/cloud/magic_tv_provider.dart`
  (`playbackPrecedence` mapped to `real_debrid`; display stays `Torbox` / `Real Debrid`).
- Data: `lib/models/debrify_tv/`, `lib/services/debrify_tv_repository.dart`,
  `lib/services/debrify_tv_database.dart`, `lib/services/debrify_tv_cache_service.dart`,
  `lib/services/debrify_tv_channel_add_service.dart`,
  `lib/services/debrify_tv_zip_importer.dart`. Dialogs: `lib/screens/debrify_tv/`.

## Stremio TV (random-play channels)
- `lib/screens/stremio_tv/stremio_tv_screen.dart`, `lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart` (dial,
  left/right surf), `lib/screens/video_player/widgets/stremio_tv_guide_sheet.dart` (in-player channel list
  — `isCurrent` vs `isFocused` styling), `lib/screens/stremio_tv/stremio_tv_filter_page.dart`.
  Picker availability: `CloudCredentials.stremioPickerChoices` / `isStremioAvailable`.
  Resolve skip: `StremioTvResolveGate.canAttempt` (blocked RD, auto TorBox
  cache, PM/AD toggle-only — not `isStremioAvailable`). Auto TorBox hashes
  go through `StremioTvTorboxCache` / `CloudPortFeature.cachedHashes`.

## Trackers & continue-watching
- Trakt: `lib/services/trakt/` (service, continue_watching, list_source, transformer, calendar).
  Simkl: `lib/services/simkl/` (incl. `lib/services/simkl/simkl_menu_helpers.dart` remove/On-Hold, `lib/services/simkl/simkl_continue_watching_service.dart`).
  MDBList: `lib/services/mdblist/`. Shared shapes live in `lib/services/tracking/`
  (`TrackerListSource`, `TrackerCalendar`, `TrackerContinueWatching`,
  `TrackerItemTransformer`, `TrackerRegistry` keyed by `TrackingSource`). Each
  family implements those without sharing HTTP clients. `TrackingSourcePolicy`
  iterates the registry. Home CW rows (`search_screen.dart`, G1) and
  `trakt_calendar_screen.dart` still call family singletons.
- Settings: `lib/screens/settings/trakt_settings_page.dart`, `lib/screens/settings/simkl_settings_page.dart`.
  Home rows live in `lib/screens/search_screen.dart` (`SearchScreenHost`). In-app
  player scrobble machines live in `lib/services/scrobble/` (`ScrobbleCoordinator`,
  `TraktScrobbleTarget`, `SimklScrobbleTarget`, `MdblistScrobbleSessionTarget`
  wrapping `MdblistScrobbleSession`). Discover source dropdown:
  `lib/screens/search/discover_screen.dart` + `lib/screens/search/search_screen_shells.dart`
  (`discoverSourceDropdownOptions`), `lib/widgets/search_source_dropdown.dart`,
  `lib/widgets/trakt/trakt_results_view.dart`.

## Detail screens & trailers
- Search-tab opener: `lib/screens/search/title_opener.dart` (`TitleOpener.open`, from
  `search_screen.dart` `_openItem`). Merged vs legacy path, CW menu rows, hero/season
  args, `returnToTabOnClose` → `MainPageBridge.switchTab`.
- `lib/screens/merged_series_detail_screen.dart` (default-on), legacy `lib/screens/catalog_item_detail_screen.dart`
  (no trailer), `lib/widgets/episodes_panel.dart`, `lib/widgets/series_browser.dart`.
- Trailer: `lib/widgets/hero_trailer_backdrop.dart` (`buildVideo(fit:)` — crop lives here),
  `lib/widgets/trailer_engine.dart`.

## Other video sources
- YouTube: `lib/services/youtube_service.dart`, `lib/widgets/youtube/`. Reddit: `lib/services/reddit_service.dart`,
  `lib/widgets/reddit/`. Lemmy: `lib/services/lemmy_service.dart`, `lib/widgets/lemmy/`.

## Settings · storage · misc infra
- Settings: `lib/screens/settings/` (+ `lib/screens/settings/home_sections_filter_page.dart` = show/hide home rows,
  `lib/screens/settings/home_page_settings_page.dart`,
  `lib/screens/settings/backup_restore_page.dart` = Data & Backup create/restore UI,
  `lib/screens/settings/download_location_controller.dart` = download-location picker (SAF vs path),
  `lib/screens/settings/profiles_settings_page.dart` `ProfileSettingsRailActions` = Profiles card switch/add/edit). Metrics/format helpers: `lib/utils/`.
  Adding a settings page still touches ~6 sites until **S1**.
- Storage split (**S2**, replaces remaining G3): `lib/services/storage/home_prefs.dart`
  (`HomePrefs`, `HomeCardOrientation`, `HomeHeroSourceMode`, `HomeHeroSource`,
  `HomeExtraRow`) owns Home page-default keys plus remaining Home keys
  (`home_disabled_sections_v1`, extra rows, order, hero source, tick sources, Home
  hero-trailer, `tv_home_style`); `lib/services/storage/stremio_tv_prefs.dart`
  (`StremioTvPrefs`); `lib/services/storage/social_prefs.dart` (`SocialPrefs`);
  `lib/services/storage/debrify_tv_prefs.dart` (`DebrifyTvPrefs`, including
  `engine_tv_` / `debrify_tv_use_` prefix families); `lib/services/storage/provider_credential_prefs.dart`
  (`ProviderCredentialPrefs`) owns integration toggles, hidden-from-nav,
  post-torrent / file-selection precedence, RD endpoint, PikPak session/folder
  prefs, and WebDAV. `lib/services/storage/cloud_secret_prefs.dart` owns
  credential keys; `lib/services/storage/storage_key_ownership.dart` `byKey` asserts
  each declared / inline / interpolated prefs name has exactly one owner. Callers
  still import `StorageService` (façade until callers move; `@Deprecated` in Q2).
  `lib/services/storage/player_prefs.dart` (`PlayerPrefs`) and
  `lib/services/storage/iptv_prefs.dart` (`IptvPrefs`) own player + IPTV prefs
  (S2-3).   `lib/services/storage/app_style_prefs.dart` (`AppStylePrefs`) owns
  sync style caches (S2-4): `debrify_tv_style` / `debrify_tv_player_style` /
  dock / IPTV look / themes / sidebars / launch ident / Discover layout.
  `lib/services/storage/tracking_prefs.dart` (`TrackingPrefs`) owns tracking
  policy + Trakt/Simkl/MDBList credentials (S2-5).
- Collections (imported Nuvio/Xperience-style folder groups → Home rows of folder tiles):
  `lib/models/home_collection.dart` (schema + parser + `collection:<id>` row ids),
  `lib/services/home_collections_store.dart` (`home_collections_v1`, file/URL/paste import, addon
  resolution), `lib/services/collection_folder_loader.dart` (merged multi-catalog paging),
  `lib/services/home_collection_rows.dart` (`HomeCollectionSection`), browser
  `lib/screens/collections/collection_folder_screen.dart` (+ `lib/widgets/collections/rail_see_all_pill.dart`),
  settings `lib/screens/settings/collections_settings_page.dart` (+ `lib/widgets/text_prompt_dialog.dart`).
  Board wiring lives in `lib/screens/search_screen.dart` (`_openCollectionFolder`,
  `_openCollectionScreen`); collection row assembly is `HomeBoardController.buildCollectionSections`. Docs: `docs/collections.md`.
- Hide watched (Settings › Tracking): `lib/services/hide_watched_prefs.dart` (sync flag),
  `lib/services/watched_filter.dart` (predicate over `WatchedStatusService`),
  `lib/services/filtered_catalog_pager.dart` (`fetchFilteredPage` top-up paging). Wired in
  `lib/screens/search/home_board_controller.dart` (`fetchBoardBatch`, `loadMoreRow`, hero source)
  plus catalog search in `lib/screens/search/catalog_search_controller.dart`,
  `lib/screens/see_all/catalog_see_all_screen.dart`, `lib/services/home_list_rows.dart`, Trakt/MDBList See-All.
- Stream badges (Nuvio `badges.json` rulesets → chips on source rows): `lib/models/stream_badge_rules.dart`,
  `lib/services/stream_badge_matcher.dart`, `lib/services/stream_badges_service.dart`, `lib/widgets/stream_badge_strip.dart`,
  `lib/screens/settings/stream_badges_settings_page.dart` (from the Play Loader page). Rendered by
  `lib/widgets/source_row.dart` and the in-player `lib/screens/video_player/widgets/source_sheet.dart`; the addon's
  label/description ride `Torrent.streamLabel`/`streamDescription` (set in `lib/services/stremio_service.dart`).
- Backup/transfer/sync: `lib/services/backup_restore_service.dart` (full config snapshot),
  settings UI `lib/screens/settings/backup_restore_page.dart` (legacy create/restore; profile mode delegates to `profile_backup_flows.dart`),
  `lib/widgets/remote/` + `lib/services/remote_control/` (device-to-device over LAN, no server).
  See the 11-site checklist above until **T1**.
- Onboarding: `lib/widgets/initial_setup_flow.dart` (export) → `lib/widgets/onboarding/onboarding_flow.dart`.
  Migration: `lib/services/app_migration_service.dart`.

## Metadata
- `lib/services/tvmaze_service.dart`, `lib/services/movie_metadata_service.dart`,
  `lib/services/imdb_enrichment_service.dart`, `lib/services/episode_info_service.dart`,
  `lib/services/catalog_repo_service.dart`.

---
_Maintenance: this is a routing hint, not a spec. If a lane moves a path named here,
update this file in the same PR. Line counts come from `wc -l`, not estimates._

### Playback storage routing (S2-6)

- `lib/services/storage/playback_progress_store.dart` owns continue-watching, local completion and playback JSON, tracker snapshot writes, track preferences, playlist metadata and `buildPlaylistProgressMap` (title matching and derived progress); `StorageService.buildPlaylistProgressMap` retains a direct forwarding facade until Q2 caller migration. `localCompletionRevision` is one shared notifier; `readPlaybackStateMap` always reads fresh preferences.
- `StorageService` retains public forwarding APIs and private bridges for out-of-range progress/migration callers. The remote `movieFinishedRevision`, migration orchestration and `IptvMediaStore` SQLite resume backend retain their existing owners. Key strings remain frozen in `storage_key_ownership.dart`.
- Origin compatibility: `test/playback_progress_store_origin_compatibility_test.dart`; store/facade identity: `test/playback_progress_store_test.dart`.

### Defaults migration routing (S2-7)

- `StorageService.migrateDefaultsGeneration` captures preferences once and retains generation checks, the residual detail-trailer write and the final generation marker. Its phased calls preserve theme/detail -> Home -> sidebars -> Home trailer -> detail trailer -> TV style order.
- `AppStylePrefs.migrateDefaultsGeneration1Theme`, `migrateDefaultsGeneration1Sidebars` and `migrateDefaultsGeneration3TvStyle` own the style writes; `HomePrefs.migrateDefaultsGeneration1TvHome` and `migrateDefaultsGeneration2Trailers` own Home writes. All receive the same captured `ProfilePreferences`; they do not warm caches or advance generation.
- `test/migration_hooks_origin_test.dart` pins real persistence order, types, explicit choices, idempotence and failed-write retry before extraction.
