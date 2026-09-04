---
name: refactor-lane
description: Run one Debrify refactor lane as a worker. Use when assigned a lane id from REFACTOR_BOARD.md (C0, D0, M0, P1, …).
---

# Refactor lane worker

Read `dev/design/REFACTOR_PLAN.md`, `CODEMAP.md`, and **your row** in `dev/design/REFACTOR_BOARD.md` first. Confirm the branch is fresh from `main`.

## Prompt (fill from the board + plan §4)

You are worker `<n>` on lane `<ID>` of `dev/design/REFACTOR_PLAN.md`. Branch `refactor/<id>-<slug>` from `main`.

You may edit ONLY: `<owned file list>`. You may not edit: `<forbidden list>`. If you need a change elsewhere, write it under "Decisions needed" in the PR and stop at that boundary.

Compatibility surfaces are frozen (prefs keys, DB schema, backup keys, remote ConfigCommand strings, MainTab indices, Home row id grammar).

Procedure per moved function: write the pinning test, run it **green**, commit `test: pin <path> behaviour before move`, **then** move verbatim and commit naming the quirk and the test. The PR must include a diff of each moved body against its origin with every difference listed and justified. A pin that lands in the same commit as the move, or a rewrite without that table, fails gate (c). No dart format on the god files. Before pushing, run and paste the verification block.

Acceptance for this lane: `<acceptance criteria from §4>`.

## Worker loop (plan §6)

1. Confirm owned files overlap no other `in-progress` / `assigned` lane on the board.
2. For each function you will move: locate it, write the pinning test, run it green, commit `test: pin <path> behaviour before move`. Do not start the move until that commit is green on its own.
3. Move verbatim. Commit `<Area>: move <symbol> to <file>` with the quirk named in the body. Paste an origin-diff of the moved body in the PR and justify every remaining difference.
4. Run the verification block and paste it into the PR description. Include the origin-diff table.
5. Set the board status to `review` by editing **only your row** in the PR (the orchestrator merges the board row with the code). Do not edit other lanes' rows.
6. Stop. Do not start the next lane until assigned.

## PR title

`[<lane id>] <short description>`

## Verification (plan §8 — paste into every PR)

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

Also run `python3 tool/ci_test_allowlist.py` (or the CI unittest in `tool/`) so there are no new failures and no unused allowlist entries.

## Branch and PR

- Branch must be `refactor/<lane-id>-<slug>` (not `cursor/…`).
- One lane, one branch, one PR.
- If the forge tool requires a `cursor/` prefix, create the PR with skip-branch-prefix and keep the `refactor/` name.
