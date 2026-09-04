# Debrify — Qwen Code briefing

Flutter client (`lib/{screens,services,widgets,models,utils}`). Behaviour
preservation is the bar. Grep huge files; never read them end-to-end.

See @CODEMAP.md and @.cursor/rules/refactor.mdc.

## Frozen — never rename

Prefs keys, DB schema, backup payload keys, remote `ConfigCommand` strings,
`MainTab` indices, sidebar destination ids, Home row id grammar, deep-link
formats.

Provider ids stay as they are: playback `debrid` / `torbox` / `premiumize` /
`alldebrid` / `pikpak`; bound/Home Real-Debrid is `rd`; playlist JSON RD is
`realdebrid`; Magic TV is `real_debrid`. Those dialects are not the same.

## God files — grep ±40 lines; do not rewrite or `dart format`

- `lib/screens/search_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/services/storage_service.dart`
- `lib/screens/video_player_screen.dart`
- `lib/screens/magic_tv_screen.dart`
- `lib/services/torrent_playback_service.dart`
- `lib/services/remote_control/remote_command_router.dart`
- `lib/services/video_player_launcher.dart`

## How to change code

- Pin current behaviour with a test before moving it, including quirks.
- Move, don't rewrite. Comments move with the code.
- Keep static facades: `TorrentPlaybackService`, `StorageService`,
  `DownloadService.instance`. New types sit behind `lib/services/cloud/`.
- Do not collapse provider dialects (`tryParse` vs `fromStoredId` vs
  `fromPlaybackId` vs `fromMagicTvId`).
- Do not edit a file another in-progress lane owns
  (`dev/design/REFACTOR_BOARD.md`).
- Do not `git push`, open PRs, or merge.

## Commands

```
flutter test test/adversarial/
flutter test test/cloud_playback_characterization_test.dart
flutter analyze lib/services/cloud
python3 tool/ci_test_allowlist.py
```
