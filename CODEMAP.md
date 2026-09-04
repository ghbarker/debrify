# Debrify code map

An **area → owning-files** index so triage/estimate tooling (and humans) can jump straight to the
right code instead of re-discovering it. Flutter app; code under `lib/{screens,services,widgets,models,utils}`.

> ⚠️ **Grep, don't read whole.** The files flagged 🔴 are huge (8k–26k lines). Always `grep` for the
> symbol and Read only the surrounding ±40 lines — never read them end-to-end.
>
> 🔴 huge: `screens/deprecated/torrent_search_screen.dart` (26k, legacy — usually ignore) ·
> `screens/search_screen.dart` (16k) · `screens/magic_tv_screen.dart` (11k) ·
> `screens/video_player_screen.dart` (8k) · `screens/torbox/torbox_downloads_screen.dart` (6.8k) ·
> `screens/debrid_downloads_screen.dart` (6.2k) · `services/storage_service.dart` (5.8k) ·
> `services/torrent_playback_service.dart` (4.7k) · `services/video_player_launcher.dart` (4k) ·
> `widgets/initial_setup_flow.dart` (4.9k).

## Cross-cutting hubs (touched by many features)
- **`screens/search_screen.dart`** 🔴 — the Home/Discover board: continue-watching rows, catalog rows,
  favourites rows, the D-pad `_BoardCell` focus grid, poster sizing (`_railPosterW`), bind-sources entry.
- **`services/storage_service.dart`** 🔴 — all SharedPreferences/persisted state (settings, continue
  watching (cap 50), playback state, favourites, provider toggles, home disabled-sections).
- **`services/torrent_playback_service.dart`** 🔴 — provider-agnostic play/add/bind pipeline.
  Magnet add, hashless bound replay, download-picker lazy URLs, launcher/TV
  unlock, in-app player unlock, and Stremio TV torrent resolve go through
  `services/cloud/` (`CloudProviderPort` + `CloudProviderRegistry`).
  Stremio TV uses `resolveStremioTorrent` (`realdebrid` + auto order with
  PikPak before Premiumize; null on miss). Stremio TV *picker* rows are
  `CloudCredentials.stremioPickerChoices` (RD/TB key-only, PikPak
  enabled-only, PM/AD toggle+key — not `isConfigured()`). Settings page
  still lists RD/TB/PikPak only. Debrify TV file prepare is
  `prepareMagicTv` (`real_debrid`; infohash-only magnet; random unseen file;
  RD/AllDebrid `supports(magicTvPrepare)` is false). Locked-link queues are
  `prepareMagicTvLockedLinks` (still-locked URLs; RD re-queues the torrent,
  AllDebrid expands leftover files). Player-screen unlock is
  `unlockPlayerScreenEntry` (wraps HTTP as `Torbox link failed`; incomplete
  Premiumize throws). Playlist JSON, labels,
  and download credential keys live there too. Bind-source PM/AD/PP browsers:
  `screens/cloud/cloud_browse_select_source.dart`.
  Cloud credential keys live in `CloudSecretPrefs` (must match
  `CloudProviderId.credentialKey`); `StorageService` remains the public
  static API. Display names / chips / overlay titles live on
  `CloudProviderId`; `CloudProviderChrome` (`widgets/cloud_provider_chrome.dart`)
  is Flutter colors/icons plus non-cloud loader ids. Strangler policy is
  documented here; `.cursor/rules/debrify-refactor.mdc` is an editor
  mirror, not the source of truth.
- **`main.dart`** — app shell + nav branch (TV rail / desktop rail / `MobileFloatingNav`), tab indices.

## Search, sources & addons
- Aggregation/sort/dedup: `services/torrent_service.dart` (`searchAllEngines`, `_deduplicateAndSort`,
  keyword-search engines).
- Stremio addons: `services/stremio_service.dart` (`_fetchStreamsFromAddon`, `_convertToTorrents` —
  where addon order + labels get overwritten), `models/stremio_addon.dart` (`StremioStream.fromJson`,
  `sizeFromTitle`), `services/stremio_marketplace_service.dart`, `screens/addons/addon_hub_screen.dart`.
- Indexer managers (Prowlarr/Jackett): `services/indexer_manager_service.dart`
  (`_searchProwlarr*`, Torznab), `models/indexer_manager_config.dart`,
  `screens/settings/indexer_managers_settings_page.dart`.
- Scraper "engine" system (YAML-config, **not** a code-plugin runtime): `services/engine/*`.
- **Filters**: `models/torrent_filter_state.dart` (QualityTier/RipSource/AudioLanguage/SizeBucket dims),
  format/HDR tag detection already exists in `utils/format_tag_detector.dart` +
  `utils/torrent_coverage_detector.dart` + `utils/{movie,series}_parser.dart`. Result row UI:
  `widgets/torrent_result_row.dart`; source picker: `screens/video_player/widgets/source_sheet.dart`.

## Debrid providers & cloud
- Playback adapters: `services/cloud/cloud_provider_port.dart` (`CloudProviderPort`)
  plus `rd_cloud_provider.dart` / `torbox_cloud_provider.dart` /
  `premiumize_cloud_provider.dart` / `alldebrid_cloud_provider.dart` /
  `pikpak_cloud_provider.dart`, dispatched by `cloud_provider_registry.dart`.
  Lookup dialects stay split: `tryParse` vs `fromStoredId` vs `fromPlaybackId`.
  `CloudPortFeature.forProvider` / `CloudProviderPort.supports` is "this adapter
  implements that method"; a null return from a supported method is a miss.
  `CloudPortFeature.cachedHashes` is TorBox `checkcached` only — not Premiumize
  `checkCache` (positional bools). `CloudPortFeature.checkCache` is Premiumize
  only. Stremio auto-play (`StremioTvTorboxCache.load`) maps missing key to
  empty; explicit `torbox` / `premiumize` filtering is
  `StremioTvCacheFilter.apply` (skip the call when there is no key; keep
  directs). Playback cache-first is `PlaybackCacheFirst.reorder` (hits first,
  catch-all, empty key still reaches the adapter). Home/Sources search badges
  call the same registry methods but keep their own key-null gates, try/catch
  memoization, and cached-only TorBox narrowing. Chunk HTTP is swallowed by `TorboxService.checkCachedTorrents`
  (partial or empty set) and by `PremiumizeService.checkCache` (slots stay
  `false`); those calls do not throw.
  HTTP clients remain in
  `services/debrid_service.dart` (Real-Debrid), `services/torbox_service.dart`,
  `services/premiumize_service.dart`, `services/alldebrid_service.dart`,
  `services/pikpak_api_service.dart`.
  Playlist unlock classification is `CloudUnlockPlan` on `CloudProviderId`
  (`fromPlaybackId` for `entry.provider` — playlist `realdebrid` is not RD;
  RD is `restrictedLink`). Launcher vs player differ only at incomplete
  Premiumize and empty `restrictedLink`. Player wrap brand is
  `CloudProviderId.playerWrapBrand` (`Real Debrid` / `Torbox`). Registry
  unlock uses `requireId`, not `tryParse(plan.playbackId)`.
  Player-screen HTTP wrap is typed
  (`CloudMetadataMissing` / `CloudMissingApiKey` rethrow; other errors
  become `$brand link failed`) — not substring matching.
  Credential presence is `CloudCredentials.configured(id, CloudConfiguredCheck)`
  (`playback` / `magnet` / `stremioPicker`) — three credential dialects, one
  entry. `StremioTvResolveGate.canAttempt` is per-torrent skip, not a fourth
  `configured()` flavour.

  **Still on string switches** (not this extract): Stremio TV settings
  picker (RD/TB/PikPak only, `has*Credential`), Debrify TV RD/AllDebrid
  `downloadLink` PreferVideos on `magic_tv_screen`, launcher Real-Debrid
  spellings, bulk-add, `storage_service` provider toggles, magnet
  deep-link `isMagnetConfigured` vs playback `isConfigured`.
  Playback still exposes one-line delegates onto the registry so god-file
  call sites do not change.
- File-tree browse (per provider, post-add): `debrid_service.getTorrentFolderTree`,
  `utils/{rd,torbox}_folder_tree_builder.dart`, `screens/playlist_content_view_screen.dart`.
- Cloud/downloads screens: `screens/{debrid_downloads,torbox/torbox_downloads,pikpak/pikpak_files,`
  `premiumize/premiumize_files,alldebrid/alldebrid_files}_screen.dart`, `screens/cloud_screen.dart`.
- WebDAV: `services/webdav_service.dart` (read/browse only — no upload yet).

## Players
- In-app player: `screens/video_player_screen.dart` 🔴 (subtitles via media_kit
  `subtitleViewConfiguration`; `_restoreTrackPreferences`/`_applyDefault*Language`; per-key D-pad
  handlers arrowUp/Down/Left/Right; duplicated Trakt+Simkl scrobble state machines). Controls overlay:
  `screens/video_player/widgets/controls.dart`. Track/source sheets: `screens/video_player/widgets/*`.
- Launch + native TV: `services/video_player_launcher.dart` 🔴 (`_launchOnAndroidTv`, `_push`),
  `services/android_tv_player_bridge.dart`, native Kotlin
  `android/app/src/main/kotlin/com/debrify/app/{MainActivity.kt,tv/AndroidTvTorrentPlayerActivity.kt}`.
- External players: `services/external_player_service.dart`, `models/*_external_player.dart`.

## IPTV
- Playlist/M3U/Xtream: `services/iptv_service.dart` (`parseContent`), `utils/m3u_parser.dart`
  (tvg-id + EPG url), `services/xtream_codes_service.dart`, `models/iptv_playlist.dart`.
- EPG: `services/iptv_epg_service.dart`, `services/xmltv_epg_source.dart`.
- Stremio-addon-as-IPTV bridge: `services/stremio_iptv_service.dart` (treats each catalog meta as one
  channel). UI: `widgets/iptv/*`, `screens/settings/iptv_settings_page.dart`.

## Debrify TV (keyword channels)
- `screens/magic_tv_screen.dart` 🔴 (favourites are an unordered `Set`; literal keyword match
  `_parseKeywords`; per-provider native launch `_launch{RealDebrid,Torbox}OnAndroidTv`).
  Default pick / overlay strings: `services/cloud/magic_tv_provider.dart`
  (`playbackPrecedence` mapped to `real_debrid`; display stays `Torbox` / `Real Debrid`).
- Data: `models/debrify_tv/*`, `services/debrify_tv_{repository,database,cache_service,channel_add_service}.dart`,
  `services/debrify_tv_zip_importer.dart`. Dialogs: `screens/debrify_tv/*`.

## Stremio TV (random-play channels)
- `screens/stremio_tv/stremio_tv_screen.dart`, `stremio_tv/widgets/stremio_tv_tuner.dart` (dial,
  left/right surf), `screens/video_player/widgets/stremio_tv_guide_sheet.dart` (in-player channel list
  — `isCurrent` vs `isFocused` styling), `screens/stremio_tv/stremio_tv_filter_page.dart`.
  Picker availability: `CloudCredentials.stremioPickerChoices` / `isStremioAvailable`.
  Resolve skip: `StremioTvResolveGate.canAttempt` (blocked RD, auto TorBox
  cache, PM/AD toggle-only — not `isStremioAvailable`). Auto TorBox hashes
  go through `StremioTvTorboxCache` / `CloudPortFeature.cachedHashes`.

## Trackers & continue-watching
- Trakt: `services/trakt/*` (service, continue_watching, list_source, transformer, calendar).
  Simkl: `services/simkl/*` (incl. `simkl_menu_helpers.dart` remove/On-Hold, `simkl_continue_watching_service.dart`).
  MDBList: `services/mdblist/*`. **Trackers share no abstraction — fully parallel by design.**
- Settings: `screens/settings/{trakt,simkl}_settings_page.dart`. Home rows + scrobble wiring live in
  `search_screen.dart` + both players. Discover source dropdown: `widgets/search_source_dropdown.dart`,
  `widgets/trakt/trakt_results_view.dart`.

## Detail screens & trailers
- `screens/merged_series_detail_screen.dart` (default-on), legacy `screens/catalog_item_detail_screen.dart`
  (no trailer), `widgets/episodes_panel.dart`, `widgets/series_browser.dart`.
- Trailer: `widgets/hero_trailer_backdrop.dart` (`buildVideo(fit:)` — crop lives here),
  `widgets/trailer_engine.dart`.

## Other video sources
- YouTube: `services/youtube_service.dart`, `widgets/youtube/*`. Reddit: `services/reddit_service.dart`,
  `widgets/reddit/*`. Lemmy: `services/lemmy_service.dart`, `widgets/lemmy/*`.

## Settings · storage · misc infra
- Settings: `screens/settings/*` (+ `home_sections_filter_page.dart` = show/hide home rows,
  `home_page_settings_page.dart`). Metrics/format helpers: `utils/*`.
- Collections (imported Nuvio/Xperience-style folder groups → Home rows of folder tiles):
  `models/home_collection.dart` (schema + parser + `collection:<id>` row ids),
  `services/home_collections_store.dart` (`home_collections_v1`, file/URL/paste import, addon
  resolution), `services/collection_folder_loader.dart` (merged multi-catalog paging),
  `services/home_collection_rows.dart` (`HomeCollectionSection`), browser
  `screens/collections/collection_folder_screen.dart` (+ `widgets/collections/rail_see_all_pill.dart`),
  settings `screens/settings/collections_settings_page.dart` (+ `widgets/text_prompt_dialog.dart`).
  Board wiring lives in `search_screen.dart` (`_buildCollectionSections`, `_openCollectionFolder`,
  `_openCollectionScreen`). Docs: `docs/collections.md`.
- Hide watched (Settings › Tracking): `services/hide_watched_prefs.dart` (sync flag),
  `services/watched_filter.dart` (predicate over `WatchedStatusService`),
  `services/filtered_catalog_pager.dart` (`fetchFilteredPage` top-up paging). Wired in
  `search_screen.dart` (`_fetchBoardBatch`, `_loadMoreRow`, catalog search, hero source),
  `see_all/catalog_see_all_screen.dart`, `services/home_list_rows.dart`, Trakt/MDBList See-All.
- Stream badges (Nuvio `badges.json` rulesets → chips on source rows): `models/stream_badge_rules.dart`,
  `services/{stream_badge_matcher,stream_badges_service}.dart`, `widgets/stream_badge_strip.dart`,
  `screens/settings/stream_badges_settings_page.dart` (from the Play Loader page). Rendered by
  `widgets/source_row.dart` and the in-player `video_player/widgets/source_sheet.dart`; the addon's
  label/description ride `Torrent.streamLabel`/`streamDescription` (set in `stremio_service.dart`).
- Backup/transfer/sync: `services/backup_restore_service.dart` (full config snapshot),
  `widgets/remote/*` + `services/remote_control/*` (device-to-device over LAN, no server).
- Onboarding: `widgets/initial_setup_flow.dart` 🔴. Migration: `services/app_migration_service.dart`.

## Metadata
- `services/{tvmaze_service,movie_metadata_service,imdb_enrichment_service,episode_info_service}.dart`,
  `services/catalog_repo_service.dart`.

---
_Maintenance: this is a routing hint, not a spec — paths drift. If `/estimate` finds a file has moved,
update the line here. Regenerate the hub/line-count list when files grow past ~8k lines._
