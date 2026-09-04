# Debrify refactor and cleanup — multi-agent plan

Status: **proposed** · Baseline: `main` @ 92b41125 (2026-09-04) · Owner: Ghbarker

This document is the working contract for a multi-agent refactor of Debrify. It is
written to be handed to AI coding agents (Cursor) as-is: one **orchestrator** that
owns decisions, sequencing and merges, and several **worker** agents that each own
one lane at a time. Every rule here exists because the codebase already bit
someone. Read it whole before touching code.

---

## 0. Where the codebase is today

Numbers are from `main` @ 92b41125. The CODEMAP's figures are stale; these are current.

| File | Lines | Problem |
|---|---:|---|
| `lib/screens/deprecated/torrent_search_screen.dart` | 26 413 | Dead legacy screen; 142 provider-string sites; only reachable behind a hard-coded flag |
| `lib/screens/search_screen.dart` (+4 `part` files) | 19 073 (+8 400) | Home, Search and Discover in one State; board, hero, six TV stage layouts, catalog search, detail opening, Trakt/Simkl/MDBList CW rows |
| `lib/screens/video_player_screen.dart` | 16 278 | Player, subtitles, tracks, two duplicated scrobble state machines |
| `lib/screens/magic_tv_screen.dart` | 10 712 | Debrify TV; still calls `DebridService`/`AllDebridService` directly for unlocks |
| `lib/services/storage_service.dart` | 9 963 | Every persisted key; 15 provider-string sites; no module boundaries |
| `lib/screens/settings_screen.dart` | 7 905 | Settings tree, search index, backup UI; adding a page touches 6 sites |
| `lib/screens/torbox/torbox_downloads_screen.dart` / `debrid_downloads_screen.dart` | 7 069 / 6 444 | Two near-copies of one cloud-files screen |
| `lib/services/video_player_launcher.dart` | 5 769 | Launch pipeline; hand-maps three spellings of Real-Debrid |
| `lib/services/torrent_playback_service.dart` | 5 384 | Now delegates to `CloudProviderRegistry` but keeps 28 provider-string sites and shims |
| `lib/services/remote_control/remote_command_router.dart` | 5 100 | A new transfer category needs 11 registrations; strings, not an enum |
| `lib/widgets/catalog_browser.dart` | 2 062 | Dead (only referenced from the deprecated screen) |

Cross-cutting facts that shape the plan:

- **Providers**: the `CloudProviderPort` refactor (fork PRs #3–#17) is a sound seam but a
  half-migration. The port is one fat interface with throw-stubs; the registry has one
  unlock plan; `CloudCredentials` carries four "configured" dialects; Magic TV, Stremio
  TV, the launcher, bulk-add, playlist content view and storage still string-match.
- **Trackers**: Trakt, Simkl and MDBList are three parallel service families
  (calendar, continue-watching, list source, item transformer, menu helpers, service)
  with no shared abstraction. CODEMAP says this is by design; it is also why every
  Home-row feature is implemented three times.
- **Registries that don't exist**: Home row ids (`cw:`, `fav:`, `traktlist:`,
  `collection:` …), backup categories, remote transfer categories, settings pages and
  the settings search index are each a set of hand-maintained switch statements spread
  over 4–11 files. Every recent feature (collections, hide-watched, stream badges) paid
  that tax.
- **CI**: the test allowlist is now exact-match with a self-test, but `flutter analyze`
  runs on a hand-list of ~12 paths and goldens are excluded wholesale. The biggest files
  are not analyzed in CI at all.
- **Docs**: `CODEMAP.md` is the routing map agents rely on; it is partly stale.
  `dev/design/ADDING_A_PROVIDER.md` predates the port.

## 1. Goals and non-goals

**Goals**

1. No behaviour change visible to users. Every lane is a strangler-fig move: code moves
   near-verbatim, quirks are pinned by a test *before* the move, and the commit message
   names the quirk.
2. Shrink the god files by extraction into cohesive units with one reason to change.
3. Replace hand-maintained switch tables with registries so that adding a provider,
   tracker, Home row family, backup category or settings page is one registration.
4. Finish the provider port: capability interfaces, one credentials API, no
   provider-string comparisons outside `lib/services/cloud/`.
5. Make CI honest: analyze all of `lib/` and `test/`, fail on new issues, run goldens.
6. Keep `CODEMAP.md` true at the end of every lane.

**Non-goals**

- New features. Feature branches (`feature/*`, upstream PRs #54/#55/#56) stay separate
  and are rebased on top when they land.
- Rewriting the six TV stage layouts, the player controls or the theme system.
- Changing persisted keys, wire formats (remote protocol v5 / transfer v4), backup
  payload keys, or `MainTab` indices. These are compatibility surfaces.
- Unifying the three tracker families into one abstraction in this round (see lane T:
  extract the *common* pieces only).

## 2. Ground rules for every agent

1. **Behaviour preservation is the bar.** Before moving code, write or point to a test
   that pins the current behaviour of that path, including its quirks. If a quirk looks
   like a bug, keep it and file a note in `dev/design/REFACTOR_NOTES.md`; do not fix it
   in a refactor commit.
2. **Move, don't rewrite.** A moved function should diff cleanly against its origin.
   Comments move with the code. Improve only after the move lands, in a separate commit.
3. **One lane, one branch, one PR.** Branch name `refactor/<lane-id>-<slug>`. Small
   commits, each self-describing, message format:
   `<Area>: <what moved/changed>` + a body naming the preserved quirk and the pinning
   test.
4. **Compatibility surfaces are frozen**: prefs keys, DB schema, backup payload keys,
   remote `ConfigCommand` strings, `MainTab` indices, sidebar destination ids, Home row
   id grammar, deep-link formats. Renaming a Dart symbol is fine; renaming a persisted
   string is not.
5. **File ownership is exclusive.** The orchestrator's board (section 6) says which lane
   owns which files. A worker never edits a file another active lane owns. If you need
   a change in a file you don't own, write the request in your PR description and stop
   at that boundary.
6. **The god files are edited by hunk, never reformatted.** No `dart format` on
   `search_screen.dart`, `settings_screen.dart`, `storage_service.dart`,
   `video_player_screen.dart`, `magic_tv_screen.dart`, `torrent_playback_service.dart`,
   `remote_command_router.dart`, `video_player_launcher.dart`. Format new files only.
7. **Verification before every push**:
   `flutter analyze` on every file you touched (zero new issues of any severity),
   `flutter test` on the suites listed in your lane plus every test file you touched,
   and `tool/ci_test_allowlist.py` semantics (no new failures, no unused allowlist
   entries). Record the exact commands and results in the PR.
8. **Never commit tooling noise**: `pubspec.lock`, `analysis_options.yaml`, the
   generated plugin registrants under `linux/`, `macos/`, `windows/`, and
   `android/app/build.gradle.kts` package tweaks. Revert them before committing.
9. **CODEMAP is part of the change.** If a lane moves a symbol CODEMAP names, update
   CODEMAP in the same PR.
10. **Ask by writing, not by guessing.** When a decision is above your lane (a new
    abstraction, a compatibility question, a conflict with another lane), write it into
    the PR under "Decisions needed" and stop. The orchestrator answers in the board.

## 3. Target architecture

Layering, enforced by imports (a lint or a test that greps imports; lane C0 adds it):

```
models/            pure data, no Flutter, no services
services/          logic; may import models and other services; no Flutter widgets
  cloud/           provider port + adapters + registry + credentials
  home/            row registry, row ids, row families
  transfer/        backup categories registry (used by backup, remote, profile restore)
widgets/           reusable UI; may import models/services; never screens
screens/           feature screens; may import everything above; never another screen's
                   private parts (extract to widgets/ instead)
```

Key registries to create (each replaces a set of switches):

| Registry | Replaces | Consumers |
|---|---|---|
| `CloudProviderRegistry` (exists) + capability interfaces | remaining provider-string switches | playback, launcher, bulk-add, Magic TV, Stremio TV, storage, settings |
| `HomeRowRegistry` | `_sectionRowId`, `_canonicalOrderIds`, group builders, id-prefix checks across `search_screen.dart`, `home_sections_filter_page.dart`, `home_list_rows.dart` | Home board, Home Rows manager, hero source picker |
| `TransferCategoryRegistry` | backup build/summarize/apply switches, `BackupSelection`/`BackupSummary`/`RestoreReport` field triplets, remote router's 5 maps, export/transfer-all tiles, onboarding labels | backup, remote, profile restore, settings summary |
| `SettingsPageRegistry` | the 6-site registration in `settings_screen.dart` + `settings_tv_layout.dart`, the search index `leaf()` tables | settings tree, TV layout, settings search |
| `TrackerRegistry` (light) | per-tracker `switch` in tick policy, scrobble targets, CW row wiring | tracking settings, Home CW rows, watched status |

## 4. Lanes

Each lane is independently mergeable and lists: owned files, forbidden files, steps,
acceptance criteria, pinning tests, size. Sizes: S ≤ 1 day-agent, M ≤ 3, L ≤ 6.

### Phase 0 — make the ground safe (run first, in parallel)

**C0 · CI truth** (S). Owns `.github/workflows/test.yml`, `tool/ci_test_allowlist.py`,
`test/BASELINE_*`, `dart_test.yaml`, new `tool/check_layering.dart`.
Steps: analyze all of `lib/` and `test/`, fail on *new* diagnostics against a committed
baseline (`tool/analyze_baseline.json`, generated at `main`); run goldens on Linux with a
tolerance job rather than excluding the tag; add the import-layering check as a test;
make unused allowlist entries fail (already) and print the regression list first.
Accept: CI red on a deliberately introduced analyzer error in `search_screen.dart`;
green on `main`. Pinning: `tool/ci_test_allowlist_test.py`.

**D0 · delete dead code** (S). Owns `lib/screens/deprecated/`, `lib/widgets/catalog_browser.dart`,
and the `_redesign = false` branch in `search_sources.dart`.
Steps: confirm zero live references (`grep`, analyzer), delete, remove the flag, update
CODEMAP. Accept: app builds; `test/` green; ~28 000 lines gone. This lane alone removes
142 of the provider-string sites.

**M0 · CODEMAP refresh** (S). Owns `CODEMAP.md`, `dev/design/ADDING_A_PROVIDER.md`.
Steps: regenerate the line-count table; rewrite the provider section around the port;
list the registries from section 3 as "planned" with their lane ids; add the remote
transfer 11-site checklist until lane R1 lands. Accept: every path in CODEMAP exists.

### Phase 1 — registries and the provider port

**P1 · capability interfaces** (M). Owns `lib/services/cloud/**`, `test/cloud_*`.
Steps: split `CloudProviderPort` into `CloudUnlock`, `CloudMagnetAdd`, `CloudPlaylist`,
`CloudMagicTv`, `CloudCachedHashes`; adapters implement only what they support;
`supports()` becomes `is`-checks; delete `CloudUnsupported` throw-stubs; the feature
table moves out of the enum and is derived from the adapter. Collapse
`CloudCredentials` to `configured(id, CloudSurface)` backed by one `(needsKey, needsToggle)`
table per surface (`playback`, `magnet`, `stremioPicker`, `stremioResolve`); keep the
old wrappers one release as `@Deprecated` forwarders. Fix the `resolvePlaylistEntry`
null ambiguity with a sealed result. Accept: no `throw CloudUnsupported` anywhere; the
four wrappers have zero non-deprecated callers; `cloud_stremio_*` and
`cloud_unlock_plan_test` pass unchanged.

**P2 · finish the provider migration** (L, splittable into P2a–P2d by file). Owns, one
sub-lane each: `magic_tv_screen.dart` (P2a), `stremio_tv_screen.dart` (P2b),
`video_player_launcher.dart` + `torrent_bulk_add_service.dart` (P2c),
`playlist_content_view_screen.dart` + `playlist_player_service.dart` + `cloud_screen.dart`
+ `provider_settings_page.dart` (P2d). Forbidden: `lib/services/cloud/**` (request via P1).
Steps per file: pin each string-switch path with a test using `FakeCloudProvider`; route
through the registry; delete the switch. Accept: `grep -rE "'(realdebrid|real_debrid|torbox|premiumize|alldebrid|pikpak)'" lib` returns hits only under `lib/services/cloud/`
and `lib/main.dart` sidebar labels. Each sub-lane merges on its own.

**H1 · Home row registry** (M). Owns new `lib/services/home/**`, the row-id hunks of
`search_screen.dart` (`_sectionRowId`, `_canonicalCanvasRails`, `_buildRow` dispatch),
`home_sections_filter_page.dart`, `home_list_rows.dart`, `home_row_order.dart`.
Steps: one `HomeRowFamily` per id prefix (cw, trakt/simkl/mdblist CW, fav, watchlist,
tracker lists, iptv lists, collection, addon catalog) declaring id grammar, label,
default-on, arrangeable, group name, resolver; the manager's `_buildModel` and the
board's rail assembly iterate the registry. Accept: adding a fake family in a test
makes it appear in the manager and the board with no other edits; the existing
`home_sections_filter_page_test`, `home_extra_rows_test`, `home_layout_policy_test` pass.

**T1 · transfer category registry** (M). Owns `lib/services/transfer/**`,
`backup_restore_service.dart`, `remote_command_router.dart` config hunks,
`remote_config_export.dart`, `remote_transfer_all.dart`, `onboarding_flow.dart`
`_configLabel`, `profile_restore_coordinator.dart` selection literals.
Steps: `TransferCategory { key, wireCommand, label, icon, color, build(), apply(), count(),
summarizeLabel }`; `BackupSelection` becomes a `Set<TransferCategory>`; the router's five
maps derive from the registry; the two `BackupSelection` literals in the restore
coordinator become explicit sets (fixes the double-apply latent bug for any category
that defaults on). Accept: adding a category in a test registers it end-to-end;
`backup_encryption_test`, `remote_chunked_send_test`, `profile_remote_*` pass;
`homeCollections` and `streamBadges` behave as today.

**S1 · settings registry** (M). Owns `settings_screen.dart` nav tables and
`_formatBackupSummary`/`_formatRestoreReport`, `settings_tv_layout.dart`,
`settings/widgets/settings_widgets.dart` `SettingsRows`.
Steps: `SettingsPageSpec { row, category, opener, keywords, leaves }` registered once;
phone, desktop and TV layouts render from it; the search index is derived. Accept: a new
page in a test appears in all three layouts and search with one registration; TV pane
focus nodes remain contiguous (the existing DPAD comment); `settings_search_test` passes.

### Phase 2 — decompose the god screens (after Phase 1, each independent)

**G1 · search_screen split** (L, sequential sub-steps, one worker). Owns
`lib/screens/search_screen.dart` and `lib/screens/search/**`.
Order: (1) extract the Home *board data layer* (`_load`, `_fetchBoardBatch`,
`_loadMoreRow`, hero source, reload diffing) into `HomeBoardController`
(`ChangeNotifier`, pure Dart, testable) — pin with `home_board_controller_test`;
(2) extract catalog search into `CatalogSearchController`; (3) extract detail opening
(`_openItem` and menu building) into `TitleOpener`; (4) split Search and Discover into
their own screens sharing the controllers; (5) the six TV stage layouts become one
widget each under `search/stages/`. Accept after each step: no new analyzer issues,
`test/search_*`, `discover_*`, `home_*` green, line count reported in the PR.

**G2 · settings_screen split** (M, after S1). Owns `settings_screen.dart`.
Extract backup/restore UI into `settings/backup_restore_page.dart`, profile switching
into its page, leaving a shell that renders the registry.

**G3 · storage_service split** (L). Owns `storage_service.dart`, new `lib/services/storage/**`.
Steps: group keys by domain into stores (`HomePrefs`, `PlayerPrefs`, `IptvStore`,
`TrackingPrefs`, `ProviderCredentials`…) that each own their keys; `StorageService`
becomes forwarding facades marked `@Deprecated` per domain as callers move; a
`storage_key_sweep_test` extension asserts every key is owned by exactly one store.
Compatibility: keys and encodings unchanged, byte-for-byte (pin with a prefs snapshot
test that writes through the old API and reads through the new).

**G4 · cloud file screens** (M, after P1). Owns `debrid_downloads_screen.dart`,
`torbox/torbox_downloads_screen.dart`, `premiumize/*`, `alldebrid/*`, `pikpak/*` files
screens. Steps: one `CloudFilesScreen` parameterised by a `CloudFilesSource` capability
on the adapter; per-provider quirks (RD folder tree, TorBox web downloads) become
adapter-provided sections. Pin with widget tests per provider first.

**G5 · player scrobble state** (M). Owns the scrobble hunks of
`video_player_screen.dart` and `services/trakt|simkl|mdblist/*_scrobble_session.dart`.
Steps: one `ScrobbleCoordinator` driving N `ScrobbleTarget`s; the two duplicated state
machines become one. Pin with `scrobble_*` tests using fake targets.

**T2 · tracker commons** (M). Owns `services/trakt/**`, `services/simkl/**`,
`services/mdblist/**`, `tracking_source_policy.dart`.
Steps: extract the shared shapes only — `TrackerListSource`, `TrackerCalendar`,
`TrackerContinueWatching`, `TrackerItemTransformer` interfaces, plus a `TrackerRegistry`
keyed by `TrackingSource`; each family implements them without changing its HTTP code.
Consumers that `switch (source)` iterate the registry instead. Accept: `trakt_*`,
`simkl_*`, `mdblist_*` tests unchanged and green.

### Phase 3 — polish

**Q1 · layering lint enforcement** (S): turn C0's import check from warning to failure
once Phase 2 lanes land.
**Q2 · comment and dead-shim sweep** (S per area): remove forwarding shims left by
P1/G3, tighten docs to house style (`lib/services/discover_prefs.dart` is the model).
**Q3 · `.cursor/` policy** (S): move rule content into `dev/design/ENGINEERING_RULES.md`;
keep `.cursor/rules` as a two-line pointer.

## 5. Sequencing

```
Phase 0:  C0 ─┐   D0 ─┐   M0 ─┐        (parallel, ~1 day)
              └───────┴──────┴─► merge gate 0
Phase 1:  P1 ──► P2a P2b P2c P2d   (P2x parallel after P1)
          H1  T1  S1               (parallel with P1; touch disjoint files)
                                   ─► merge gate 1
Phase 2:  G1 (long, single worker)  G3 (single worker)
          G2 (after S1)  G4 (after P1)  G5  T2     (parallel, disjoint files)
                                   ─► merge gate 2
Phase 3:  Q1 Q2 Q3
```

Rule: at most one active lane per god file. `search_screen.dart` is touched by H1 (row-id
hunks only) and G1; H1 merges first, G1 rebases. `settings_screen.dart` by S1 then G2.
`storage_service.dart` by P2d (string sites) then G3.

## 6. Orchestration protocol

Agents cannot message each other. Coordination happens through **git** and one shared
file, `dev/design/REFACTOR_BOARD.md`, which the orchestrator alone edits on `main`.

### The board

```
| Lane | Status | Branch | Worker | Owns | Blocked on | Decisions |
| C0 | merged | refactor/c0-ci-truth | — | .github/…, tool/… | — | — |
| P1 | in-progress | refactor/p1-capabilities | worker-2 | lib/services/cloud/** | — | Q3: keep wrappers one release → yes |
| H1 | queued | — | — | lib/services/home/**, search_screen.dart[rowid hunks] | P1? no | — |
```

Statuses: `queued` → `assigned` → `in-progress` → `review` → `merged` / `parked`.

### Orchestrator loop

1. **Assign**: pick the next `queued` lane whose owned files overlap no `in-progress`
   lane; write the worker prompt (template in §7) with the exact file list; set
   `assigned`.
2. **Gate**: when a worker sets `review`, check the PR: (a) the verification block is
   present and reproduces; (b) diff touches only owned files; (c) every moved function
   has a pinning test named in a commit body; (d) CODEMAP updated if it names a moved
   symbol; (e) no compatibility surface changed (grep the frozen lists). Reject with
   specific lines, or merge with squash if the lane's commits aren't individually
   valuable, merge-commit if they are.
3. **Answer decisions**: anything under "Decisions needed" gets a one-line answer in the
   board's Decisions column and a comment on the PR. Decisions are final for the phase.
4. **Rebase fan-out**: after each merge, tell every `in-progress` lane touching a
   neighbouring file to rebase (a board note is enough; workers check the board on
   start and before push).
5. **Phase gate**: at the end of each phase run the full suite, the analyzer over all of
   `lib/` and `test/`, a Windows build and an Android build, and a manual smoke
   (Home, Search, Sources, playback start, Settings > Backup export). Record results
   in the board. Nothing from the next phase starts before the gate passes.
6. **Scope police**: a worker that starts a feature, a rename of a persisted key, or a
   cross-lane edit gets the PR sent back, no discussion.

### Worker loop

1. Read this document, `CODEMAP.md`, and the board row for your lane. Confirm your
   branch is fresh from `main`.
2. For each function you will move: locate it, write the pinning test, run it green,
   commit `test: pin <path> behaviour before move`.
3. Move. Commit `<Area>: move <symbol> to <file>` with the quirk named in the body.
4. Run the verification block (§7) and paste it into the PR description.
5. Set the board status to `review` by editing only your row in the PR (the orchestrator
   merges the board row with the code).
6. Stop. Do not start the next lane until assigned.

### Running several workers at once (Cursor specifics)

- Use one **Background Agent** per lane, each on its own branch from `main`; Cursor
  gives each an isolated checkout, which is what the file-ownership rule assumes.
- The orchestrator is a separate agent session whose only writable files are
  `REFACTOR_BOARD.md`, `REFACTOR_NOTES.md` and PR reviews; it never edits lane files.
  If you prefer a human orchestrator, the loop above is the checklist.
- Put §2 (ground rules) into `.cursor/rules/refactor.mdc` with `alwaysApply: true` so
  every worker gets them without being told. Put the worker template (§7) in
  `.cursor/skills/refactor-lane/SKILL.md`.
- Safe parallel width: Phase 0 three agents; Phase 1 up to five (P1, H1, T1, S1 plus
  one P2 sub-lane once P1 merges); Phase 2 up to four. Beyond that, merge conflicts on
  shared test lists in `test.yml` outrun the gain until C0's "analyze everything"
  removes those lists.

## 7. Prompt templates

### Orchestrator

```
You are the orchestrator for the Debrify refactor described in dev/design/REFACTOR_PLAN.md.
You own dev/design/REFACTOR_BOARD.md and dev/design/REFACTOR_NOTES.md and nothing else;
you never edit lane files. Loop: assign the next queued lane whose owned files overlap no
in-progress lane; write its worker prompt from the template with the exact file list;
gate PRs on the five checks in §6 (verification block reproduces, diff within owned
files, pinning test per moved function, CODEMAP updated, no compatibility surface
changed); answer "Decisions needed" in one line each; after every merge note which lanes
must rebase; at phase end run the phase gate and record it. Reject scope creep without
discussion. Report to the human after every merge and at every phase gate with: merged
lanes, open decisions, blocked lanes, line-count deltas of the god files.
```

### Worker

```
You are worker <n> on lane <ID> of dev/design/REFACTOR_PLAN.md (read it, CODEMAP.md,
and your row in REFACTOR_BOARD.md first). Branch refactor/<id>-<slug> from main.
You may edit ONLY: <owned file list>. You may not edit: <forbidden list>. If you need a
change elsewhere, write it under "Decisions needed" in the PR and stop at that boundary.
Compatibility surfaces are frozen (prefs keys, DB schema, backup keys, remote
ConfigCommand strings, MainTab indices, Home row id grammar).
Procedure per moved function: pin with a test → commit → move verbatim → commit naming
the quirk and the test. No dart format on the god files. Before pushing, run and paste:
  flutter analyze <every touched file>        (zero new issues, any severity)
  flutter test <lane suites> <touched tests>  (all pass)
  python tool/ci_test_allowlist.py … (no new failures, no unused entries)
Then update CODEMAP.md for any symbol you moved, set your board row to review, and stop.
Acceptance for this lane: <acceptance criteria from §4>.
```

## 8. Verification standard (copied into every PR)

```
### Verification
- Touched files: …
- flutter analyze <files>: 0 new issues (baseline diff attached)
- flutter test: <n> passed, 0 failed — suites: …
- Pinning tests added: … (one per moved function)
- Compatibility surfaces: unchanged (checked: prefs keys, backup keys, ConfigCommand, MainTab, row ids)
- CODEMAP: updated / not needed (why)
- Manual: <platform> smoke of <paths>
```

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Two lanes edit `search_screen.dart` | Board rule: one active lane per god file; H1 limited to named hunks and merges before G1 |
| A "verbatim move" silently drops a comment or a branch | Diff the moved body against its origin in the PR; reviewer checks the pinning test covers the dropped branch |
| Registry refactors change ordering (rows, transfer apply order, settings order) | Order is data in the registry; pin it with a test that asserts today's order |
| Storage split changes an encoding | Prefs snapshot test: write through old API, read through new, byte-equal |
| CI baseline hides real regressions | Baseline is generated at a named commit and shrinks only; new diagnostics fail |
| Agents "fix" quirks in passing | Ground rule 1 + notes file; reviewer rejects behaviour changes in refactor commits |
| Long-running G1 diverges from main | G1 rebases after every merge gate; its sub-steps are separate PRs |

## 10. Definition of done

- Every file in §0 either deleted or under 3 000 lines, with `search_screen.dart` under
  4 000 and no `part` files over 1 500.
- No provider-string comparison outside `lib/services/cloud/` (grep is the test).
- Adding a provider, tracker, Home row family, transfer category or settings page is
  one registration each, demonstrated by a test that adds a fake one.
- CI analyzes all of `lib/` and `test/`, runs goldens, and has an allowlist of zero.
- CODEMAP accurate; `ADDING_A_PROVIDER.md` rewritten against the registries.
- The app behaves identically: the phase-3 gate's manual smoke plus the full suite are
  green on Windows and Android, and Backup export from before Phase 0 restores cleanly
  after Phase 3.
