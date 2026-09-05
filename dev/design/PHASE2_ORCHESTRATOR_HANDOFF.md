# Phase 2 orchestrator handoff

Archived from cloud agent `bc-ff736eb6-fb92-4da7-a7a6-9b194e70ec33`
(https://cursor.com/agents/bc-ff736eb6-fb92-4da7-a7a6-9b194e70ec33)
2026-09-05. Binding plan: `REFACTOR_PLAN_PHASE2.md` (#72).

Worktree for merges/docs: `/tmp/debrify-c0`. Co-authored-by:
`ghbarker <ghbarker@users.noreply.github.com>`. Merge with
`git merge --no-ff` on `main` and push. Open PRs with ManagePullRequest +
`skip_branch_prefix_check`. Lane branches: `refactor/<lane-id>-<slug>`.

## Main

`22c40dd4` — #73–#95 + **#98**. Do **not** revert #95.

God files after #95: search 13 105 · player 11 926 · magic_tv 8 369 ·
storage 6 282 · settings 2 899 (≤ 3 000 met).

## Binding holds (user comments)

1. **Do not merge any further G1' / V1 extract** until **#99** then **#100**.
   Includes **#96**. Do not start G1'-5 / V1-6.
2. **#98 does not clear G1'-3 gate (h).** It is a post-move
   `KeywordSearchScreen` pin and cannot pass on the parent of the #90 move.
3. **#97 overlaps #99.** Rebase onto #99 or close as superseded once #99 merges.
   This branch was rebased onto `30cef221` (#99 head at archive).
4. Do not start S2-6 / M1-3. M1-3 also needs a real origin-path pin for
   M1-0/M1-1. V1-6 needs a real lib pin for V1-1…5.
5. **#56** held until Phase 3 / Q3. Parked: `refactor/g3-player-prefs`.

## Open PRs (archive-time)

| PR | Branch | Head (approx) | Action |
|---|---|---|---|
| **#99** | `refactor/c0-gate2-layering` | `30cef221` | **Merge first** when test+goldens green. Ceiling 106; `--all --json`; identity delta vs parent; Windows `ProfileScope.fileIn` rejects `..\\escape`. GitHub PR **body is stale** (older identity-delta text); cannot update via ManagePullRequest. |
| **#100** | `refactor/v1-fix-ui-services` | `d571c534` | **After #99.** Four controllers moved to `lib/screens/**`. Layering 106 → 90. Catalog play + recording stay (foundation-only). Pin `673af47d` then move `10f10a61`. |
| **#97** | `docs/phase2-gate-h-audit` | rebased onto #99 | Gate (h) tightening + Leaves/pin-audit tables. Merge after #99 or close as superseded if #99 already has the tables. |
| **#96** | `refactor/g1p-4-continue-watching` | `771c1dd2` | **HOLD.** Leaves −1 738. §2.2 listed. CI green on `771c1dd2` — **do not merge.** After #99 this fails gate (i) unless `continue_watching_controller.dart` leaves `lib/services/` (it imports `package:flutter/widgets.dart`). |

## Layering

| When | Count |
|---|---:|
| #72 (`48db8f1e`) | 77 |
| Pre-#95 | 99 (+22) |
| Current `main` | **106** (#95 +7 via `channel_import_export`) |
| #100 (V1-fix) | **90** |

Six UI-in-services files (V1-fix): `catalog_play_resolver` (stay),
`resume_controller` (→ screens/video_player), `subtitle_track_controller` (→),
`iptv_recording_controller` (stay), `iptv_zap_controller` (→),
`keyword_search_controller` (→ screens/search). Not in V1-fix:
`channel_import_export` (M1), `continue_watching_controller` (#96).

## Merge order for the next orchestrator

1. Wait CI on **#99**. `--no-ff` merge. Rebase #97/#100 if BOARD/NOTES conflict.
2. Wait CI on **#100**. `--no-ff` merge. Optionally lower `layering_baseline.txt`
   from 106 to 90.
3. **#97**: merge leftover gate-h tables if still unique, else close.
4. **#96**: only after CW controller is out of `lib/services/` and gate (i)
   does not grow. Do not start G1'-5 until #96 merges.
5. Do not assign G1'-5 / V1-6 / S2-6 / M1-3 until the holds above clear.

## Workers (idle, can resume)

- C0-gate2: `bc-7ca1f850-c64c-59f8-b9f1-b55cae4c0e88`
- V1-fix: `bc-2b7adebf-6a01-5c4b-85cb-2756c8505b42`

## Decisions already answered (do not reopen)

Old-plan NOTES items stand (H1 rail de-dup, T1 apply-order, P2 façades,
G1 s2–s4 quirks, G2 restore-report keys, G3 HomePrefs, G4 selection bar,
G5 Simkl pause-centric, T2 local progress / MDBList `inferredType`).

S2-4 extra keys stay in `AppStylePrefs` unless a later slice wants Discover
layout back. `migrateDefaultsGeneration` stays until S2-7.

G1 step 5 `extension on _SearchScreenState` stage parts stay until **G1'-8**.

#90 / #96 double-listen (`_emit`/`notifyListeners` → host `setState` +
extracted widget listener) is **G1'-9** debt. Do not “fix” in an extract.

#95 §2.2 host block (recorded after merge): M1-5 owns `showImportProgress`,
`createImportedTextChannel`; M1-3 owns `importExportMounted`/`Context`,
`isAndroidTv`, `isBusy`/`status`, `channels`/`channelCache`, `applyImportState`,
`reloadImportedChannels`, `confirmDeleteAll`, `showSnack`.

## CI tripwires

1. `stale_runtime_guard_test`: façade `static String get fooCached` still
   counts; `resetProfileCaches()` must **name** each mirror.
2. `shape_manifest_test`: `kShapeResidue` must include new files that hold
   `app.shape.br`; do not raise residue; floor 490.
3. `analyze_baseline.json`: relocate path/line only; identity is
   `path|code|message`. Do not `--record` growth.
4. Pin-test files must be analyzer-clean. Do not grow `BASELINE_ALLOWLIST.txt`.
5. After #99: layering count ≤ ceiling; no new violation ids vs parent.

## In-flight local dirty at archive

`docs/phase2-gate-h-audit` may have an uncommitted BOARD hunk listing #99/#100
rows. Commit that onto #97 if still dirty.
