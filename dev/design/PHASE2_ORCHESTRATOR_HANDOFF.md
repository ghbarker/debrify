# Phase 2 orchestrator handoff

Archived from cloud agent `bc-ff736eb6-fb92-4da7-a7a6-9b194e70ec33`
(https://cursor.com/agents/bc-ff736eb6-fb92-4da7-a7a6-9b194e70ec33)
2026-09-05 (post #99+#100). Binding plan: `REFACTOR_PLAN_PHASE2.md` (#72).

Worktree for merges/docs: `/tmp/debrify-c0`. Co-authored-by:
`ghbarker <ghbarker@users.noreply.github.com>`. Merge with
`git merge --no-ff` on `main` and push. Open PRs with ManagePullRequest +
`skip_branch_prefix_check`. Lane branches: `refactor/<lane-id>-<slug>`.

## Main

`fcfd00c2` and follow-up docs — #73–#100. Do **not** revert #95.

| Merge | SHA |
|---|---|
| Before this wave | `22c40dd4` (#73–#95 + #98) |
| #99 C0-gate2 | `e86b0123` |
| #100 V1-fix | `d5d0af0f` |
| Ceiling 90 + board | `fcfd00c2` |

God files after #95 (unchanged by #99/#100 except import paths): search 13 105 ·
player 11 926 · magic_tv 8 369 · storage 6 282 · settings 2 899 (≤ 3 000 met).

## Binding holds

1. **#96 HOLD** until `continue_watching_controller.dart` leaves `lib/services/`
   (it imports `package:flutter/widgets.dart`). Same seam as #100:
   `lib/screens/search/` or `lib/widgets/home/`. Do **not** merge as-is —
   it fails gate (i) against ceiling 90.
2. **#98 does not clear G1'-3 gate (h).** Post-move `KeywordSearchScreen` pin.
   Parent-path (h) still unpaid.
3. **#97 closed.** Gate-(h) / Leaves tables landed on main.
4. **Do not start G1'-5 / V1-6 / S2-6 / M1-3.**
5. **#56** held until Phase 3 / Q3. Parked: `refactor/g3-player-prefs`.

## Layering

| When | Count |
|---|---:|
| #72 (`48db8f1e`) | 77 |
| Pre-#95 | 99 (+22) |
| After #95/#98 | 106 |
| After #100 | **90** (ceiling) |

Remaining service offender in the six-file class: `channel_import_export.dart`
(M1-2, 7). #96 would re-grow the count if the CW controller stays in services.

## Open PRs

| PR | Branch | Action |
|---|---|---|
| **#96** | `refactor/g1p-4-continue-watching` | HOLD. Leaves −1 738. Move controller out of `lib/services/`, rebase onto current main, wait CI, then `--no-ff`. Do not start G1'-5 until it merges. |
| **#56** | Qwen | Held for Q3. |

## Next actions

1. Path-move CW controller on #96 (or resume worker `bc-db4ab579`). Rebase onto main.
2. When #96 test+goldens green **and** layering ≤ 90 with no new ids: `--no-ff`.
3. Do not assign G1'-5 / V1-6 / S2-6 / M1-3.

## Workers (idle)

- C0-gate2: `bc-7ca1f850-c64c-59f8-b9f1-b55cae4c0e88`
- V1-fix: `bc-2b7adebf-6a01-5c4b-85cb-2756c8505b42`
- G1'-4: `bc-db4ab579-4126-52d0-9629-c41e4e190725`

## Decisions already answered (do not reopen)

Old-plan NOTES items stand. S2-4 extra keys stay in `AppStylePrefs`.
`migrateDefaultsGeneration` stays until S2-7. G1 step 5 `extension on
_SearchScreenState` stays until **G1'-8**. #90 / #96 double-listen is **G1'-9**.
