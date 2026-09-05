# Refactor board

Edited by the orchestrator only. See `REFACTOR_PLAN.md` §6 for the protocol.
**Phase 2 binding plan:** `dev/design/REFACTOR_PLAN_PHASE2.md` (#72). It supersedes
§4 lanes G1–G5 / T2 and the §10 line targets. Ground rules and gates (a)–(e) still
apply; this phase also requires (f) Leaves, (g) no host-private members / no new
`part of` / `extension on` the host State, (h) pin commit predates the move.

Baseline: `main` @ #73–#91 · Phase: **2 correction** · Last gate: 1 (Linux + Windows build/smoke **pass**; Android not run)

Analyzer (`flutter analyze lib test`): **470** issues (0 error · 85 warning · 385 info), exit 0.

Full `flutter test` (Linux, Flutter 3.44.8, this environment): **4316** passed · **33** failed · 0 skipped. Failures are mostly goldens plus a few non-golden cases also listed in `test/BASELINE_ALLOWLIST.txt` / `test/BASELINE_FAILURES.md`. C0 must not "fix" these; pin CI against them.

| Lane | Status | Branch | Worker | Owns | Blocked on | Decisions |
|---|---|---|---|---|---|---|
| C0 · CI truth | merged | `refactor/c0-ci-truth` | — | `.github/workflows/test.yml`, `tool/ci_test_allowlist.py`, `tool/ci_test_allowlist_test.py`, `test/BASELINE_ALLOWLIST.txt`, `test/BASELINE_FAILURES.md`, `dart_test.yaml`, new `tool/check_layering.dart`, new `tool/analyze_baseline.json`, plus a new layering test file if needed | — | Analyze-all vs 470-issue baseline; goldens Linux tolerance; layering warn-only until Q1. |
| D0 · delete dead code | merged | `refactor/d0-delete-dead-code` | — | `lib/screens/deprecated/**`, `lib/widgets/catalog_browser.dart`, `lib/screens/search/search_sources.dart` (`_redesign == false` branch only) | — | Unused `search_screen.dart` import dropped. CODEMAP left to M0. |
| M0 · CODEMAP refresh | merged | `refactor/m0-codemap-refresh` | — | `CODEMAP.md`, `dev/design/ADDING_A_PROVIDER.md` | — | D0 merged; dropped `lib/screens/deprecated/` and `catalog_browser.dart`. |
| P1 · capability interfaces | merged | `refactor/p1-capabilities` | — | `lib/services/cloud/**`, `test/cloud_*` | — | Fat-port CloudUnsupported defaults kept until FakeCloudProvider moves. |
| P2a · Magic TV strings | merged | `refactor/p2a-magic-tv-strings` | — | `lib/screens/magic_tv_screen.dart` | — | Dispatch is a screen façade; next-channel allowlists are a moved table (see NOTES). |
| P2b · Stremio TV strings | merged | `refactor/p2b-stremio-tv-strings` | — | `lib/screens/stremio_tv/**` | — | Pin-before-move present; **fails tightened (c)** (no origin-diff table). Keep on main; not a template. `StremioTvCacheFilter` strings in cloud/ stay. |
| P2c · launcher + bulk-add | merged | `refactor/p2c-launcher-bulk-add` | — | `lib/services/video_player_launcher.dart`, `lib/services/torrent_bulk_add_service.dart` | — | Pin-before-move present; **fails tightened (c)** (no origin-diff table). Keep on main; not a template. |
| P2d · playlist/cloud/settings strings | merged | `refactor/p2d-playlist-cloud-settings` | — | `lib/screens/playlist_content_view_screen.dart`, `lib/services/playlist_player_service.dart`, `lib/screens/cloud_screen.dart`, `lib/screens/settings/provider_settings_page.dart` | — | Pin-before-move present; **fails tightened (c)** (no origin-diff table). Keep on main; not a template. |
| P2e · playback-service strings | merged | `refactor/p2e-playback-service-strings` | worker | `lib/services/torrent_playback_service.dart`, `test/torrent_playback_service_strings_test.dart`, `lib/services/playback_service_dispatch.dart` | — | `PlaybackServiceDispatch` façade; origin-diff table present. `PlaybackCacheFirst.reorder` in cloud/ still string-switches (out of lane). `lib/main.dart` sidebar exempt. |
| H1 · Home row registry | merged | `refactor/h1-home-row-registry` | — | new `lib/services/home/**`, `search_screen.dart` [row-id hunks only], `lib/screens/settings/home_sections_filter_page.dart`, `lib/services/home_list_rows.dart`, `lib/services/home_row_order.dart` | — | Frozen row-id grammar. Undeclared: rail de-dup, wider stray leaves, addon-group merge (NOTES). **Regression:** pinned collections must lead the board — follow-up `h1-fix`. |
| H1-fix · pinned collections lead | merged | `refactor/h1-pinned-collections-lead` | orchestrator | `lib/services/home/home_row_registry.dart`, `test/home_row_registry_test.dart` | — | Preserve `_sections` order in the section band so pinned collections lead tracker lists. CI green then `--no-ff` merge. |
| T1 · transfer category registry | merged | `refactor/t1-transfer-category-registry` | — | new `lib/services/transfer/**`, `lib/services/backup_restore_service.dart`, `remote_command_router.dart` [config hunks], `lib/widgets/remote/remote_config_export.dart`, `lib/widgets/remote/remote_transfer_all.dart`, `lib/widgets/onboarding/onboarding_flow.dart` [`_configLabel`], `lib/services/profiles/profile_restore_coordinator.dart` [selection literals] | — | Frozen: ConfigCommand, backup keys. Undeclared deltas in NOTES. **Regression:** empty PikPak password — follow-up `t1-fix`. |
| T1-fix · pikpak empty password | merged | `refactor/t1-pikpak-empty-password` | orchestrator | `lib/services/transfer/transfer_categories.dart`, `test/transfer_pikpak_wire_test.dart` | — | `_readPikpakWire` accepts empty password (email-only, matching both old senders). CI green then `--no-ff` merge. |
| S1 · settings registry | merged | `refactor/s1-settings-registry` | — | `settings_screen.dart` [nav tables, `_formatBackupSummary`/`_formatRestoreReport`], `lib/screens/settings/settings_tv_layout.dart`, `lib/screens/settings/widgets/settings_widgets.dart` | — | Pages registered once. **Regression:** extraPlayerKeywords unbound — follow-up `s1-fix`. |
| S1-fix · extraPlayerKeywords | merged | `refactor/s1-extra-player-keywords` | orchestrator | `lib/screens/settings_screen.dart` [binding site only], `lib/screens/settings/settings_search_leaves.dart` [leaf spread], `test/settings_page_registry_test.dart` | — | Pass extraPlayerKeywords at the settings_screen binding so external-player names are searchable. CI green then `--no-ff` merge. |
| G1 · step 1 HomeBoardController | merged | `refactor/g1-home-board-controller` | worker | `lib/screens/search/home_board_controller.dart`, `test/home_board_controller_test.dart`, `search_screen.dart` [board data layer] | — | **#61.** Pin + origin-diff. H1-fix section-band order preserved. `search_screen.dart` 19 089 → 18 890. |
| G1 · step 2 CatalogSearchController | merged | `refactor/g1-catalog-search-controller` | worker | `lib/screens/search_screen.dart` [catalog search hunks], `lib/screens/search/**`, new catalog search controller + tests | G1 step 1 | **#65.** Pin + origin-diff. `search_screen.dart` 18 890 → 18 814. `_restoreHome` does not zero catalog-search failures (NOTES). Steps 3–5 next. |
| G1 · step 3 TitleOpener | merged | `refactor/g1-title-opener` | worker | `lib/screens/search_screen.dart` [`_openItem` + menu building], `lib/screens/search/title_opener.dart`, tests | G1 step 2 | **#66.** Pin + origin-diff. `search_screen.dart` 18 814 → 18 528. Merged path sends movies to `MergedDetailScreen` when the flag is on (NOTES). Steps 4–5 next. |
| G1 · step 4 Search/Discover screens | merged | `refactor/g1-search-discover-screens` | worker | `lib/screens/search_screen.dart` [Search + Discover shells], new screens sharing HomeBoardController / CatalogSearchController / TitleOpener | G1 step 3 | **#69.** Pin + origin-diff. Wrapper keeps `SearchScreen` constructors. `search_screen.dart` 18 528 → 18 580. `searchMode` wins if both flags true (NOTES). |
| G1 · step 5 TV stages | merged | `refactor/g1-tv-stages` | worker | `lib/screens/search_screen.dart` [six TV stage layouts], `lib/screens/search/search_stage_widgets.dart`, new `lib/screens/search/stages/**` | G1 step 4 | **#71.** Pin + origin-diff. `search_screen.dart` 18 580 → 17 039. Empty Spotlight still `break`s to classic. `_buildDiscoverStage` left on host. Five `cacheExtent` baseline rows relocated to stage parts. |
| G2 · settings_screen split | merged | `refactor/g2-backup-restore-page` | worker | `settings_screen.dart` [backup/restore + profile-switch hunks], new `lib/screens/settings/backup_restore_page.dart`, `profiles_settings_page.dart` `ProfileSettingsRailActions`, tests | — | **#63.** Pin + origin-diff. `settings_screen.dart` 3 923 → 3 107. `extraPlayerKeywords` still bound. Restore-report omits `homeCollectionsFailed` / `streamBadgeSourcesFailed` from the snackbar list (NOTES). |
| G3 · storage split | merged | `refactor/g3-storage-split` | worker | `storage_service.dart`, `lib/services/storage/**`, storage key-sweep tests | — | **#67.** HomePrefs first slice. `storage_service.dart` 9 963 → 9 835. Remaining Home keys merged #70. PlayerPrefs next. `@Deprecated` in Q2. `clearAllHomePageSettings` skips Trakt default keys (NOTES). |
| G3 · step 2 remaining Home keys | merged | `refactor/g3-home-prefs-rest` | worker | `storage_service.dart`, `lib/services/storage/home_prefs.dart`, key-sweep tests | G3 slice 1 | **#70.** Pin + origin-diff. `storage_service.dart` 9 835 → 9 634. Callers stay on StorageService. Empty tick list, `'shelf'`→`'canvas'`, custom-hero-with-no-ids, façade `trackingSourceRevision++` (NOTES). PlayerPrefs next. `@Deprecated` in Q2. |
| G3 · step 3 PlayerPrefs | parked | `refactor/g3-player-prefs` | — | — | superseded | **Do not merge.** Phase 2 correction replaces G3 with **S2**. PlayerPrefs is S2-3 (with `iptv_prefs`), after S2-0…S2-2. Branch left on origin for later reference. |
| G4 · cloud file screens | merged | `refactor/g4-cloud-files-screen` | worker | `debrid_downloads_screen.dart`, `torbox/**`, `premiumize/**`, `alldebrid/**`, `pikpak/**` files screens | — | **#64.** RD + TorBox on shared `CloudFilesScreen`. PM/AD/PikPak follow-up. Selection bar stayed on hosts (shape-manifest floor; NOTES). Supersedes closed #36–#43. |
| G4 · step 2 remaining hosts | merged | `refactor/g4-cloud-files-rest` | worker | `premiumize/**`, `alldebrid/**`, `pikpak/**` files screens, `CloudFilesScreen` | — | **#80.** PM/AD/PikPak on shared `CloudFilesScreen`. Selection bars stayed on hosts. |
| G5 · scrobble coordinator | closed | `refactor/g5-scrobble-coordinator` | — | — | — | **#68** extracted scrobble. Remaining triplication is **V1-9**. Do not open a G5 follow-up. |
| T2 · tracker commons | merged | `refactor/t2-tracker-commons` | worker | `services/trakt/**`, `services/simkl/**`, `services/mdblist/**`, `tracking_source_policy.dart`, new `lib/services/tracking/**` | — | **#62.** Shared shapes only; HTTP unchanged. Local progress not dedicated; MDBList adapter ignores `inferredType` (NOTES). Out-of-lane callers not chased. |
| P1b · RD/AD Magic-TV port | merged | `refactor/p1b-magic-tv-unlock` | worker | `lib/services/cloud/**`, `test/cloud_*` | — | **#76.** Thin `CloudMagicTvRdUnlock` / `CloudMagicTvAdUnlock`. `magic_tv_screen.dart` untouched. Unblocks M1. |
| G1'-0 · public types | merged | `refactor/g1p-0-public-types` | worker | `search_screen.dart`, `lib/screens/search/**` (rename only) | — | **#74.** `_Mode`→`SearchBoardMode`; `_CwKind`→`CwKind`; `_CwRow`→`CwRow`; `_FavKind`→`FavKind`; `_FavRowRef`→`FavRowRef`; `_ArtPoster`→`ArtPoster`; `_FavArtCell`→`FavArtCell`. `_ArtPosterState` stays private. Leaves 0. |
| G1'-1 · catalog play resolver | merged | `refactor/g1p-1-catalog-play-resolver` | worker | `search_screen.dart` [play/resume hunks], `lib/services/playback/catalog_play_resolver.dart` | G1'-0 | **#78.** Leaves −1 069. No new `part`/`extension on` State. |
| G1'-2 · source edit/add dialogs | merged | `refactor/g1p-2-source-binding-dialogs` | worker | `search_screen.dart` [source dialog hunks], `lib/widgets/sources/source_binding_dialogs.dart`, pin + widget tests | G1'-1 | **#84.** Leaves −486. `onReorder` ignore (path-keyed baseline). Pin predates move. |
| G1'-3 · keyword search | merged | `refactor/g1p-3-keyword-search` | worker | `search_screen.dart` [keyword hunks], `lib/services/search/keyword_search_controller.dart`, `lib/screens/search/keyword_search_screen.dart`, pin | G1'-2 | **#90.** Leaves −2 379. Pin predates move. Host keeps thin `_switchMode` launcher + `_openKeywordBind`. |
| G1'-4 … G1'-9 | queued | — | — | `search_screen.dart` | G1'-3 | Sequential. Target ≤ 7 500; no `extension on _SearchScreenState`. |
| V1-0 · PlayerLaunchConfig | merged | `refactor/v1-0-launch-config` | worker | `video_player_screen.dart` [ctor + `widget.*` reads], `lib/screens/video_player/player_launch_config.dart` | — | **#75.** Value object. Leaves +3 ≈ 0. Unblocks V1-1…10. |
| V1-1 · resume controller | merged | `refactor/v1-1-resume-controller` | worker | `video_player_screen.dart` [resume hunks], `lib/services/playback/resume_controller.dart` | V1-0 | **#79.** Leaves 666. Pin predates move. Adapter still `widget.*`. |
| V1-2 · identify-title sheet | merged | `refactor/v1-2-identify-title-sheet` | worker | `video_player_screen.dart` [identify-title hunks], `lib/widgets/player/identify_title_sheet.dart` | V1-1 | **#83.** Leaves 527. Sheet + season dialog. Subtitle fetch stays for V1-3. Pin predates move. |
| V1-3 · subtitle track controller | merged | `refactor/v1-3-subtitle-track-controller` | worker | `video_player_screen.dart` [subtitle/track hunks], `lib/services/playback/subtitle_track_controller.dart` | V1-2 | **#88.** Leaves 943. Pin predates move. Identify sheet not re-extracted. |
| V1-4 · IPTV recording | merged | `refactor/v1-4-iptv-recording` | worker | `video_player_screen.dart` [recording hunks], `lib/services/playback/iptv_recording_controller.dart` | V1-3 | **#91.** Leaves 704. Pin predates move. Desktop capture `extension: 'ts'`; Android engine-first then tee. Overlay reads notifiers via host getters. |
| V1-5 … V1-10 | queued | — | — | `video_player_screen.dart` | V1-4 | Sequential. Target ≤ 9 500. V1-9 folds episode-progress into ScrobbleCoordinator. |
| M1-0 · WatchSession | merged | `refactor/m1-0-watch-session` | worker | `magic_tv_screen.dart` [WatchSession field/sink hunks], `lib/screens/debrify_tv/watch_session.dart`, tests | P1b merged (#76) | **#81.** Leaves +12 ≈ 0. `ProgressSink` seam. Pin predates move. |
| M1-1 · channel cache warmer | merged | `refactor/m1-1-channel-cache-warmer` | worker | `magic_tv_screen.dart` [warm/cache hunks], `lib/services/debrify_tv/channel_cache_warmer.dart` | M1-0 | **#87.** Leaves **856** (10 764 → 9 908). TorBox window, quality filter, RD size-filter compute moved. Create/update dialogs stay (M1-5). |
| M1-2 … M1-6 | queued | — | — | `magic_tv_screen.dart` | M1-1 | Sequential. Target ≤ 4 500. |
| S2-0 · key registry + façade | merged | `refactor/s2-0-key-registry` | worker | `storage_key_ownership.dart` | — | **#73.** `byKey` completed (274). Façade rule documented. Leaves 0. **Did not extract PlayerPrefs.** |
| S2-1 · stremio/social/TV prefs | merged | `refactor/s2-1-stremio-social-tv-prefs` | worker | `storage_service.dart`, `lib/services/storage/**` | S2-0 | **#77.** Leaves −531. Prefixes `engine_tv_` in `byKey`. |
| S2-2 · provider credential prefs | merged | `refactor/s2-2-provider-credential-prefs` | worker | `storage_service.dart`, `lib/services/storage/**` | S2-1 | **#82.** Leaves −575. Named store 971. CloudSecretPrefs/MDBList skipped. |
| S2-3 · player + IPTV prefs | merged | `refactor/s2-3-player-iptv-prefs` | worker | `storage_service.dart` [player/IPTV hunks], `lib/services/storage/player_prefs.dart`, `iptv_prefs.dart`, `storage_key_ownership.dart`, tests | S2-2 | **#86.** Leaves −1 067 (style/completion stayed for S2-4 / S2-6). Did not merge parked `refactor/g3-player-prefs`. |
| S2-4 … S2-7 | queued | — | — | `storage_service.dart`, `lib/services/storage/**` | S2-3 | Sequential. Target ≤ 2 800. S2-4 = `app_style_prefs`. |
| G2 · under 3 000 | merged | `refactor/g2-download-location` | worker | `settings_screen.dart` [download-location hunks], `download_location_controller.dart` | — | **#85.** 3 107 → 2 899 (−208). Target ≤ 3 000 met. |
| Q1 · layering enforcement | queued | — | — | `tool/check_layering.dart`, `test.yml` | gate 2 | — |
| Q2 · shim + comment sweep | queued | — | — | per area, assigned at gate 2 | gate 2 | — |
| Q3 · `.cursor` policy | queued | — | — | `.cursor/**`, `dev/design/ENGINEERING_RULES.md` | gate 2 | PR #56 (Qwen helper) held until Phase 3; it edits `.cursor/**`. |

## Gates

| Gate | Date | Analyzer (all lib+test) | Full test suite | Windows build | Android build | Manual smoke | Result |
|---|---|---|---|---|---|---|---|
| 0 | 2026-09-04 | 466 (0 error · 83 warning · 383 info); analyze_baseline.py exit 0 (4 unused from deleted catalog_browser) | 4320 passed · 33 failed (same 33 as Phase 0 baseline; +4 vs 4316 from D0 pin + C0 layering) | not run (Linux host) | not run (no Android SDK) | Linux desktop: Home, Search, Keyword/Sources UI, play attempt → no sources (no debrid), Settings → Data & Backup export wrote `~/Documents/downloads/debrify-profile-2026-09-04.json` | **partial** — smoke + analyzer/tests ok; Windows/Android builds still outstanding. Phase 1 not assigned. |
| 1 | 2026-09-04 | 466 issues (`flutter analyze lib test` exit 1; same count as gate 0) | 4405 passed · 33 failed (same 33 allowlisted failures; +85 vs gate 0 from Phase 1/2 pins) | **pass** — `flutter build windows` → `build\windows\x64\runner\Release\debrify.exe` (~206s) on `C:\Users\hunth\debrify` | not run (no Android SDK) | **Windows pass** — user: Home, Search, Sources, play attempt, Settings → Data & Backup export all worked. Linux smoke from gate 0. | **partial** — Windows build+smoke green; Android still not run. G1 step 1 assigned. P2e in flight. |

## Notes

God-file line counts at baseline `9326eb70` (`wc -l`):

| File | Lines |
|---|---:|
| `lib/screens/deprecated/torrent_search_screen.dart` | deleted (D0) |
| `lib/screens/search_screen.dart` | 19 070 |
| `lib/screens/search/` parts (4 files) | 8 321 |
| `lib/screens/video_player_screen.dart` | 16 278 |
| `lib/screens/magic_tv_screen.dart` | 10 716 |
| `lib/services/storage_service.dart` | 9 963 |
| `lib/screens/settings_screen.dart` | 7 905 |
| `lib/screens/torbox/torbox_downloads_screen.dart` | 7 069 |
| `lib/screens/debrid_downloads_screen.dart` | 6 444 |
| `lib/services/video_player_launcher.dart` | 5 769 |
| `lib/services/torrent_playback_service.dart` | 5 340 |
| `lib/services/remote_control/remote_command_router.dart` | 5 100 |
| `lib/widgets/catalog_browser.dart` | deleted (D0) |

Plan §0 numbers were from `92b41125` and are slightly stale (search_screen 19 073 → 19 071; magic_tv 10 712 → 10 716; torrent_playback 5 384 → 5 340).

Phase 1 merged. Old Phase 2 G1–G5/T2/G3-HomePrefs **closed as insufficient** (audit in PHASE2 §1). Binding is **#72** `REFACTOR_PLAN_PHASE2.md`. **G3 PlayerPrefs parked** (`refactor/g3-player-prefs` — do not merge; S2-3 later). **G5 closed** (remainder is V1-9). **#76–#83 merged.** Open: **#84 G1'-2**, **#85 G2**. Mini-gate after every three merged extractions per lane. PR #56 held for Q3. #36–#43 closed (G4).
