# Refactor board

Edited by the orchestrator only. See `REFACTOR_PLAN.md` §6 for the protocol.

Baseline: `main` @ H1/T1/S1-fix merged · Phase: **2** (P2e + G1 step 1) · Last gate: 1 (Linux + Windows build/smoke **pass**; Android not run)

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
| P2e · playback-service strings | review | `refactor/p2e-playback-service-strings` | worker | `lib/services/torrent_playback_service.dart`, `test/torrent_playback_service_strings_test.dart`, `lib/services/playback_service_dispatch.dart` | — | Route remaining provider-string sites through registry / `CloudProviderId`. Forbidden: `lib/services/cloud/**`. `lib/main.dart` sidebar/hub labels exempt. Gate (c): pin green before move + origin-diff table. |
| H1 · Home row registry | merged | `refactor/h1-home-row-registry` | — | new `lib/services/home/**`, `search_screen.dart` [row-id hunks only], `lib/screens/settings/home_sections_filter_page.dart`, `lib/services/home_list_rows.dart`, `lib/services/home_row_order.dart` | — | Frozen row-id grammar. Undeclared: rail de-dup, wider stray leaves, addon-group merge (NOTES). **Regression:** pinned collections must lead the board — follow-up `h1-fix`. |
| H1-fix · pinned collections lead | merged | `refactor/h1-pinned-collections-lead` | orchestrator | `lib/services/home/home_row_registry.dart`, `test/home_row_registry_test.dart` | — | Preserve `_sections` order in the section band so pinned collections lead tracker lists. CI green then `--no-ff` merge. |
| T1 · transfer category registry | merged | `refactor/t1-transfer-category-registry` | — | new `lib/services/transfer/**`, `lib/services/backup_restore_service.dart`, `remote_command_router.dart` [config hunks], `lib/widgets/remote/remote_config_export.dart`, `lib/widgets/remote/remote_transfer_all.dart`, `lib/widgets/onboarding/onboarding_flow.dart` [`_configLabel`], `lib/services/profiles/profile_restore_coordinator.dart` [selection literals] | — | Frozen: ConfigCommand, backup keys. Undeclared deltas in NOTES. **Regression:** empty PikPak password — follow-up `t1-fix`. |
| T1-fix · pikpak empty password | merged | `refactor/t1-pikpak-empty-password` | orchestrator | `lib/services/transfer/transfer_categories.dart`, `test/transfer_pikpak_wire_test.dart` | — | `_readPikpakWire` accepts empty password (email-only, matching both old senders). CI green then `--no-ff` merge. |
| S1 · settings registry | merged | `refactor/s1-settings-registry` | — | `settings_screen.dart` [nav tables, `_formatBackupSummary`/`_formatRestoreReport`], `lib/screens/settings/settings_tv_layout.dart`, `lib/screens/settings/widgets/settings_widgets.dart` | — | Pages registered once. **Regression:** extraPlayerKeywords unbound — follow-up `s1-fix`. |
| S1-fix · extraPlayerKeywords | merged | `refactor/s1-extra-player-keywords` | orchestrator | `lib/screens/settings_screen.dart` [binding site only], `lib/screens/settings/settings_search_leaves.dart` [leaf spread], `test/settings_page_registry_test.dart` | — | Pass extraPlayerKeywords at the settings_screen binding so external-player names are searchable. CI green then `--no-ff` merge. |
| G1 · search_screen split | assigned | `refactor/g1-home-board-controller` | worker | `lib/screens/search_screen.dart`, `lib/screens/search/**`, new `lib/screens/search/home_board_controller.dart`, `test/home_board_controller_test.dart` | — | **Step 1 only this PR:** extract Home board data layer into `HomeBoardController`. Later steps are separate PRs. Gate (c): pin green before move + origin-diff table. Preserve H1-fix section-band order. |
| G2 · settings_screen split | queued | — | — | `settings_screen.dart` | — | S1-fix and gate 1 Windows done. Assign after G1 step 1 is in flight if width allows. |
| G3 · storage split | queued | — | — | `storage_service.dart`, `lib/services/storage/**` | P2e | Gate 1 Windows done. Still wait for P2e merge. |
| G4 · cloud file screens | queued | — | — | `debrid_downloads_screen.dart`, `torbox/**`, `premiumize/**`, `alldebrid/**`, `pikpak/**` | — | P1 + gate 1 Windows done. Supersedes PRs #36–#43 (closed, do not rebase). |
| G5 · scrobble coordinator | queued | — | — | `video_player_screen.dart` [scrobble hunks], `services/*/*_scrobble_session.dart` | — | Gate 1 Windows done. |
| T2 · tracker commons | queued | — | — | `services/trakt/**`, `services/simkl/**`, `services/mdblist/**`, `tracking_source_policy.dart` | — | Gate 1 Windows done. |
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

Phase 1 merged. P2a–P2d merged. H1/T1/S1-fix merged (#57–#59). **P2e in flight. G1 step 1 assigned.** Gate 1 Windows build+smoke **pass**; Android not run. Gate (c) tightened. PR #56 held to Phase 3. PRs #36–#43 closed (G4).
