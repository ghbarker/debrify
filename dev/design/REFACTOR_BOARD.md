# Refactor board

Edited by the orchestrator only. See `REFACTOR_PLAN.md` §6 for the protocol.

Baseline: `main` @ 92b41125 · Phase: **0** · Last gate: none yet

| Lane | Status | Branch | Worker | Owns | Blocked on | Decisions |
|---|---|---|---|---|---|---|
| C0 · CI truth | queued | — | — | `.github/workflows/test.yml`, `tool/ci_test_allowlist.py`, `test/BASELINE_*`, `dart_test.yaml`, `tool/check_layering.dart` | — | — |
| D0 · delete dead code | queued | — | — | `lib/screens/deprecated/**`, `lib/widgets/catalog_browser.dart`, `search_sources.dart` [`_redesign` branch] | — | — |
| M0 · CODEMAP refresh | queued | — | — | `CODEMAP.md`, `dev/design/ADDING_A_PROVIDER.md` | — | — |
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

- God-file line counts at baseline: search_screen 19 073 · video_player_screen 16 278 · magic_tv_screen 10 712 · storage_service 9 963 · settings_screen 7 905 · torbox_downloads 7 069 · debrid_downloads 6 444 · video_player_launcher 5 769 · torrent_playback_service 5 384 · remote_command_router 5 100.
