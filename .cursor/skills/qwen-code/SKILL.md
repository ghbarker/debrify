---
name: qwen-code
description: >-
  Delegate a bounded Debrify subtask to the local Qwen Code CLI when it is
  installed and authenticated. Use for grep/locate, second-opinion reviews,
  and mechanical extracts. Skip if `python3 tool/qwen_assist.py --probe`
  reports unavailable. Never block a task on Qwen.
---

# Qwen Code helper

Qwen Code is an optional extra pair of hands. Cursor remains the owner of
the change: Qwen may explore, draft, or review; you still pin tests, keep
quirks, and land the PR.

## Probe once per session

```
python3 tool/qwen_assist.py --probe
```

Exit `2` or `"available": false` means **skip Qwen and continue**. Do not
install packages, open a browser, or wait for secrets mid-task unless the
user asked to set Qwen up.

Auth is present when any of these are set in the environment (never print
their values): `BAILIAN_CODING_PLAN_API_KEY`, `DASHSCOPE_API_KEY`,
`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
or a local `~/.qwen/.env` / `.qwen/.env`.

## When to use it

Use Qwen for a **bounded** subtask with a written-down file list:

- Locate a symbol / call sites (grep; do not read god files end-to-end)
- Second-opinion review of a small diff you already produced
- Draft a pinning test or a mechanical extract **outside** god files
- Summarize a function after you have already grepped the ±40-line window

## When not to use it

Skip Qwen (do the work yourself) when:

- The CLI or auth is missing
- The work touches frozen compatibility surfaces (prefs keys, DB schema,
  backup payload keys, `ConfigCommand` strings, `MainTab` indices, sidebar
  destination ids, Home row id grammar, deep-link formats, provider ids)
- The work is a god-file rewrite or `dart format` of a god file
- You would need Qwen to `git push`, open a PR, or merge
- Another in-progress lane owns the file (`dev/design/REFACTOR_BOARD.md`)

## How to invoke

Default is **plan** (read-only). Pass the prompt after `--`:

```
python3 tool/qwen_assist.py --mode plan -- <<'EOF'
Locate every call site of CloudProviderRegistry.instance in lib/ and
test/. Return path:line and a one-line note. Do not edit files.
EOF
```

`--mode auto-edit` is allowed only when you have already listed the exact
files Qwen may touch, none of them are god files, and a pinning test exists
or is being added in the same change.

`--mode yolo` is forbidden unless the user explicitly asked for it on this
turn.

Always include in the prompt:

- Owned / forbidden file lists
- “Grep; do not read god files end-to-end”
- “Do not rename persisted strings”
- The pinning test path if one exists

## After Qwen returns

1. Treat the output as a draft. Re-read the cited hunks yourself.
2. If Qwen edited files, `git diff` them. Revert anything that touches a
   god file, a frozen string, or a file you do not own.
3. Run the lane’s tests / `flutter analyze` on touched files. Qwen passing
   its own checks is not enough.
4. Record in the PR that Qwen assisted, with the prompt summary and whether
   you kept or discarded its edits.

## God files (never let Qwen rewrite or format)

`lib/screens/search_screen.dart`, `lib/screens/settings_screen.dart`,
`lib/services/storage_service.dart`, `lib/screens/video_player_screen.dart`,
`lib/screens/magic_tv_screen.dart`, `lib/services/torrent_playback_service.dart`,
`lib/services/remote_control/remote_command_router.dart`,
`lib/services/video_player_launcher.dart`.
