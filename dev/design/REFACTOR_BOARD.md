# Refactor board

Edited by the orchestrator only. See `REFACTOR_PLAN.md` §6 for the protocol.

Baseline: `main` @ `9326eb70` (2026-09-04, after merge of #44) · Phase: **0** · Last gate: none yet

Analyzer (`flutter analyze lib test`): **470** issues (0 error · 85 warning · 385 info), exit 0.

Full `flutter test` (Linux, Flutter 3.44.8, this environment): **4316** passed · **33** failed · 0 skipped. Failures are mostly goldens plus a few non-golden cases also listed in `test/BASELINE_ALLOWLIST.txt` / `test/BASELINE_FAILURES.md`. C0 must not "fix" these; pin CI against them.

| Lane | Status | Branch | Worker | Owns | Blocked on | Decisions |
|---|---|---|---|---|---|---|
| C0 · CI truth | merged | `refactor/c0-ci-truth` | — | `.github/workflows/test.yml`, `tool/ci_test_allowlist.py`, `tool/ci_test_allowlist_test.py`, `test/BASELINE_ALLOWLIST.txt`, `test/BASELINE_FAILURES.md`, `dart_test.yaml`, new `tool/check_layering.dart`, new `tool/analyze_baseline.json`, plus a new layering test file if needed | — | Analyze-all vs 470-issue baseline; goldens Linux tolerance; layering warn-only until Q1. |
| D0 · delete dead code | merged | `refactor/d0-delete-dead-code` | — | `lib/screens/deprecated/**`, `lib/widgets/catalog_browser.dart`, `lib/screens/search/search_sources.dart` (`_redesign == false` branch only) | — | Unused `search_screen.dart` import dropped. CODEMAP left to M0. |
| M0 · CODEMAP refresh | review | `refactor/m0-codemap-refresh` | worker-m0 | `CODEMAP.md`, `dev/design/ADDING_A_PROVIDER.md` | — | D0 merged; dropped `lib/screens/deprecated/` and `catalog_browser.dart`. Accept: every remaining path exists. |
| P1 · capability interfaces | queued | — | — | `lib/services/cloud/**`, `test/cloud_*` | gate 0 | — |
| P2a · Magic TV strings | queued | — | — | `lib/screens/magic_tv_screen.dart` | P1 | — |
| P2b · Stremio TV strings | queued | — | — | `lib/screens/stremio_tv/**` | P1 | — |
| P2c · launcher + bulk-add | queued | — | — | `lib/services/video_player_launcher.dart`, `lib/services/torrent_bulk_add_service.dart` | P1 | — |
| P2d · playlist/cloud/settings strings | queued | — | — | `lib/screens/playlist_content_view_screen.dart`, `lib/services/playlist_player_service.dart`, `lib/screens/cloud_screen.dart`, `lib/screens/settings/provider_settings_page.dart` | P1 | — |
| H1 · Home row registry | queued | — | — | `lib/services/home/**`, `search_screen.dart` [row-id hunks], `home_sections_filter_page.dart`, `home_list_rows.dart`, `home_row_order.dart` | gate 0 | — |
| T1 · transfer category registry | queued | — | — | `lib/services/transfer/**`, `backup_restore_service.dart`, `remote_command_router.dart` [config hunks], `remote_config_export.dart`, `remote_transfer_all.dart`, `onboarding_flow.dart` [`_configLabel`], `profile_restore_coordinator.dart` [selection literals] | gate 0 | — |
| S1 · settings registry | queued | — | — | `settings_screen.dart` [nav tables, summary formatters], `settings_tv_layout.dart`, `settings/widgets/settings_widgets.dart` | gate 0 | — |
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
| 0 | — | — | — | — | — | — | — |

## Notes

God-file line counts at baseline `9326eb70` (`wc -l`):

| File | Lines |
|---|---:|
| `lib/screens/deprecated/torrent_search_screen.dart` | deleted (D0) |
| `lib/screens/search_screen.dart` | 19 070 |
| `lib/screens/search/` parts (4 files) | 8 364 |
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

Phase 1 is blocked on gate 0. Do not assign P1/H1/T1/S1 until C0, D0, and M0 merge and the gate 0 row is filled.
