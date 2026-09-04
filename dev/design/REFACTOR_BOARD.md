# Refactor board

Edited by the orchestrator only. See `REFACTOR_PLAN.md` §6 for the protocol.

Baseline: `main` @ `d5111bb6` (Phase 0 merged; gate 0 partial) · Phase: **2** · Last gate: 0 (partial; human said proceed)

Analyzer (`flutter analyze lib test`): **470** issues (0 error · 85 warning · 385 info), exit 0.

Full `flutter test` (Linux, Flutter 3.44.8, this environment): **4316** passed · **33** failed · 0 skipped. Failures are mostly goldens plus a few non-golden cases also listed in `test/BASELINE_ALLOWLIST.txt` / `test/BASELINE_FAILURES.md`. C0 must not "fix" these; pin CI against them.

| Lane | Status | Branch | Worker | Owns | Blocked on | Decisions |
|---|---|---|---|---|---|---|
| C0 · CI truth | merged | `refactor/c0-ci-truth` | — | `.github/workflows/test.yml`, `tool/ci_test_allowlist.py`, `tool/ci_test_allowlist_test.py`, `test/BASELINE_ALLOWLIST.txt`, `test/BASELINE_FAILURES.md`, `dart_test.yaml`, new `tool/check_layering.dart`, new `tool/analyze_baseline.json`, plus a new layering test file if needed | — | Analyze-all vs 470-issue baseline; goldens Linux tolerance; layering warn-only until Q1. |
| D0 · delete dead code | merged | `refactor/d0-delete-dead-code` | — | `lib/screens/deprecated/**`, `lib/widgets/catalog_browser.dart`, `lib/screens/search/search_sources.dart` (`_redesign == false` branch only) | — | Unused `search_screen.dart` import dropped. CODEMAP left to M0. |
| M0 · CODEMAP refresh | merged | `refactor/m0-codemap-refresh` | — | `CODEMAP.md`, `dev/design/ADDING_A_PROVIDER.md` | — | D0 merged; dropped `lib/screens/deprecated/` and `catalog_browser.dart`. |
| P1 · capability interfaces | merged | `refactor/p1-capabilities` | — | `lib/services/cloud/**`, `test/cloud_*` | — | Fat-port CloudUnsupported defaults kept until FakeCloudProvider moves. |
| P2a · Magic TV strings | merged | `refactor/p2a-magic-tv-strings` | — | `lib/screens/magic_tv_screen.dart` | — | Dispatch via MagicTvDispatch; no `lib/services/cloud/**` edits; pin test subclasses FakeCloudProvider. |
| P2b · Stremio TV strings | merged | `refactor/p2b-stremio-tv-strings` | — | `lib/screens/stremio_tv/**` | — | `StremioTvDispatch` (`is` + FakeCloudProvider `supports` fallback). `StremioTvCacheFilter` strings in `lib/services/cloud/` stay (out of scope). Frozen: picker ids, `auto` sentinel. |
| P2c · launcher + bulk-add | merged | `refactor/p2c-launcher-bulk-add` | — | `lib/services/video_player_launcher.dart`, `lib/services/torrent_bulk_add_service.dart` | — | Registry dispatch; no dart format on launcher. Frozen: resume prefixes, analytics `real_debrid`, dialog `realdebrid`. |
| P2d · playlist/cloud/settings strings | assigned | `refactor/p2d-playlist-cloud-settings` | worker-p2d | `lib/screens/playlist_content_view_screen.dart`, `lib/services/playlist_player_service.dart`, `lib/screens/cloud_screen.dart`, `lib/screens/settings/provider_settings_page.dart` | — | Forbidden: `lib/services/cloud/**`. |
| H1 · Home row registry | merged | `refactor/h1-home-row-registry` | — | new `lib/services/home/**`, `search_screen.dart` [row-id hunks only], `lib/screens/settings/home_sections_filter_page.dart`, `lib/services/home_list_rows.dart`, `lib/services/home_row_order.dart` | — | Frozen row-id grammar; fake family appears in manager + board. |
| T1 · transfer category registry | merged | `refactor/t1-transfer-category-registry` | — | new `lib/services/transfer/**`, `lib/services/backup_restore_service.dart`, `remote_command_router.dart` [config hunks], `lib/widgets/remote/remote_config_export.dart`, `lib/widgets/remote/remote_transfer_all.dart`, `lib/widgets/onboarding/onboarding_flow.dart` [`_configLabel`], `lib/services/profiles/profile_restore_coordinator.dart` [selection literals] | — | Frozen: ConfigCommand strings, backup payload keys. |
| S1 · settings registry | merged | `refactor/s1-settings-registry` | — | `settings_screen.dart` [nav tables, `_formatBackupSummary`/`_formatRestoreReport`], `lib/screens/settings/settings_tv_layout.dart`, `lib/screens/settings/widgets/settings_widgets.dart` | — | Pages registered once; fake page in all layouts + search. |
| G1 · search_screen split | queued | — | — | `lib/screens/search_screen.dart`, `lib/screens/search/**` | H1, gate 1 | — |
| G2 · settings_screen split | queued | — | — | `settings_screen.dart` | S1, gate 1 | — |
| G3 · storage split | queued | — | — | `storage_service.dart`, `lib/services/storage/**` | P2d, gate 1 | — |
| G4 · cloud file screens | queued | — | — | `debrid_downloads_screen.dart`, `torbox/**`, `premiumize/**`, `alldebrid/**`, `pikpak/**` | P1, gate 1 | — |
| G5 · scrobble coordinator | queued | — | — | `video_player_screen.dart` [scrobble hunks], `services/*/*_scrobble_session.dart` | gate 1 | — |
| T2 · tracker commons | queued | — | — | `services/trakt/**`, `services/simkl/**`, `services/mdblist/**`, `tracking_source_policy.dart` | gate 1 | — |
| Q1 · layering enforcement | queued | — | — | `tool/check_layering.dart`, `test.yml` | gate 2 | — |
| Q2 · shim + comment sweep | queued | — | — | per area, assigned at gate 2 | gate 2 | — |
| Q3 · `.cursor` policy | queued | — | — | `.cursor/**`, `dev/design/ENGINEERING_RULES.md` | gate 2 | — |

## Gates

| Gate | Date | Analyzer (all lib+test) | Full test suite | Windows build | Android build | Manual smoke | Result |
|---|---|---|---|---|---|---|---|
| 0 | 2026-09-04 | 466 (0 error · 83 warning · 383 info); analyze_baseline.py exit 0 (4 unused from deleted catalog_browser) | 4320 passed · 33 failed (same 33 as Phase 0 baseline; +4 vs 4316 from D0 pin + C0 layering) | not run (Linux host) | not run (no Android SDK) | Linux desktop: Home, Search, Keyword/Sources UI, play attempt → no sources (no debrid), Settings → Data & Backup export wrote `~/Documents/downloads/debrify-profile-2026-09-04.json` | **partial** — smoke + analyzer/tests ok; Windows/Android builds still outstanding. Phase 1 not assigned. |

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

Phase 1 merged: P1, H1, T1, S1. Phase 2: P2a/P2b merged; P2c/P2d in review (CI). Do not assign G1–G5/T2 until gate 1.
