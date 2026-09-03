---
name: debrify-break
description: >-
  Actively try to break Debrify changes. Use when refactoring, extracting
  providers, touching StorageService, playback, downloads, magnets, or tests.
  Write a failing characterization test first; mutation-test new guards.
---

# Debrify break agent

Debrify is a working product with god classes, string-keyed providers, and
special cases that exist because production required them. Your job is to
**keep behavior** and **hunt for breakage**, not to tidy comments.

## Before changing production code

1. Read `CODEMAP.md` for the area. Grep; do not read 8k-line files end-to-end.
2. Find existing tests under `test/` and `test/adversarial/`.
3. If coverage is missing, add a **failing** characterization test first
   (`test/cloud_playback_characterization_test.dart` or `test/adversarial/`).
4. Keep persisted ids: `debrid` / `rd`, `torbox`, `premiumize`, `alldebrid`,
   `pikpak`. Do not rename SharedPreferences keys in the same change as a
   behavior change.
5. Keep static facades (`TorrentPlaybackService`, `StorageService`,
   `DownloadService.instance`). New types sit behind them.

## After the change — try to break it

Actively attempt:

- Profile switch isolation (see `test/profiles/isolation_suite/README.md`)
- Concurrent preference writes
- Empty / malformed provider responses, HTTP 429
- Cancelled provider picker (`__cancelled__`) vs no provider configured
- RAR vs multi-file vs single-file playlists
- Playback `isConfigured` (key present) vs magnet `isMagnetConfigured`
  (also requires integration enabled)
- Pack-cache TTL and `failedPackCacheHours <= 0`
- Local bind disabled on Android/iOS
- Unknown provider strings passing through `storedProviderKey`

Reintroduce the old bug (mentally or with a five-line revert) and confirm the
new test would catch it. A guard that cannot fail is worse than no guard.

## Refuse

- Big-bang rewrites of `search_screen.dart` / `video_player_screen.dart`
- Deleting `lib/screens/deprecated/` while callers exist
- Native Kotlin/tvOS player refactors in the same slice as Dart ports
- Editing vendored `packages/` media_kit patches
- "Simplifying" special cases called out in comments without a test that
  documents the special case

## Commands

```
flutter test test/adversarial/
flutter test test/cloud_playback_characterization_test.dart
flutter test test --reporter compact
flutter analyze lib/services/cloud
```
