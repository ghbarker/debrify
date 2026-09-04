# Refactor — Phase 2 correction: decomposing the god files for real

Status: **binding from the moment it lands on `main`** · Supersedes §4 lanes G1–G5, T2 and
the §10 line targets of `REFACTOR_PLAN.md`. Everything else in that document still applies.
Baseline for this plan: `main` after G1 steps 1–5 (search_screen.dart 17 039 lines).

## 1. Why Phase 2 is off target

Phase 1 delivered its registries. Phase 2 has not delivered its decomposition, and the
audit of G1 shows the failure mode exactly:

| G1 step | What the plan asked | What merged |
|---|---|---|
| 1 HomeBoardController | move the board data layer out | 300 lines moved, 235 lines of new scaffolding, 115 lines of forwarders left behind; net −199 on the screen |
| 4 Search/Discover screens | separate screens sharing controllers | two 32-line shells around the same State, which still branches on `searchMode`/`discoverMode` in 66 places |
| 5 TV stage layouts | one widget each | seven `extension on _SearchScreenState` part files reaching into 19–38 private members each — relocated, not extracted |

Result: 19 073 → 17 039 lines (−10 %) for the whole lane. The same pattern will repeat on
the player, Magic TV and storage unless the lane contract changes. Three root causes:

1. **No line targets.** "Extract X" with no number lets a worker satisfy the letter by
   moving a slice and leaving wrappers. Every extraction below carries the number of
   lines that must leave the god file, and the gate fails a PR that misses it.
2. **Part files and extensions count as extraction.** They aren't: an
   `extension on _SearchScreenState` in another file is the same coupling with a longer
   import path. From now on only code that compiles without the god file's private
   members counts.
3. **Pins that pin the copy.** Tests written against the new controller in the same
   commit as the controller never ran against the origin. Pins must drive the *old* code
   path first (widget test through the State, or a pure test of the origin function),
   and only then does the move commit land.

The original targets were also wrong for two files. Realistic numbers, from region maps
of the current code:

| File | Now | Realistic floor | Target for this phase |
|---|---:|---:|---:|
| `lib/screens/search_screen.dart` (+ parts) | 17 039 (+8 300) | ~7 000 shell | **≤ 7 500**, no part file > 1 500, no `extension on _SearchScreenState` |
| `lib/screens/video_player_screen.dart` | 15 771 | ~9 300 | **≤ 9 500** |
| `lib/screens/magic_tv_screen.dart` | 10 752 | ~4 200 | **≤ 4 500** |
| `lib/services/storage_service.dart` | 9 634 | ~2 500 façade | **≤ 2 800** |
| `lib/screens/settings_screen.dart` | 3 923 | — | ≤ 3 000 after G2 |

## 2. Lane contract changes (apply to every Phase 2 lane)

1. **Every extraction PR names its target file, the origin line range, and the minimum
   net line reduction of the god file.** The PR body shows `wc -l` before and after. A PR
   under its target is rejected even if everything else passes.
2. **Forwarders and wrappers left in the god file are a debt line item** in the PR: list
   each one and the lane that deletes it. More than ~10 lines of forwarders per
   extraction needs a "Decisions needed" entry.
3. **Extension-on-State part files are not allowed.** Extract to a class or widget that
   takes what it needs through a constructor, a controller, or a small interface
   (`StageHost`, `WatchSession`, `PlayerLaunchConfig` below). If a unit needs more than
   ~8 private members from the host, the lane first introduces the value object or
   interface that carries them, as its own PR.
4. **Pin before move, against the origin.** The pin commit must (a) not import the new
   file and (b) pass on the parent commit. For UI regions the pin is a widget test that
   drives the State; for pure logic it's a test of the origin function. Then the move
   commit lands; the pin keeps passing without edits. If the pin has to change, the move
   changed behaviour — stop and write it up.
5. **Origin-diff table stays mandatory**, with the added rule that "scaffolding added"
   lines are listed separately from "moved" lines.
6. **One extraction per PR**, in the order given below; order exists to avoid rework
   (e.g. a value object before the controllers that need it).

## 3. Lanes

Sizes: S ≤ 1 day-agent, M ≤ 3, L ≤ 6. "Leaves" = minimum net lines removed from the god
file. Line numbers refer to `origin/main` at the time of writing; re-locate by symbol.

### G1' · search_screen (owner: one worker, sequential PRs; other lanes may not touch the file)

Prereq PR **G1'-0**: make `_Mode`, `_CwKind`, `_CwRow`, `_FavKind`, `_FavRowRef`,
`_ArtPoster`, `_FavArtCell` public (rename with no behaviour change) so units can leave
the part-file privacy scope. Leaves ≈ 0; unblocks everything below.

| # | Unit | Origin | Target | Leaves | Seam | Risk |
|---|---|---|---|---:|---|---|
| G1'-1 | Play/resume resolver (`_onCatalogPlay` resolve half, reconciled series resume, play/browse selection) | ~11 686–12 506 | `lib/services/playback/catalog_play_resolver.dart` (pure Dart) | 850 | inputs: meta, tracker snapshots, bound sources → `PlaySelection`/`ResumeInfo` | low; pin as a pure function test |
| G1'-2 | Source edit/add dialogs | ~10 681–11 185 | `lib/widgets/sources/source_binding_dialogs.dart` | 450 | `(meta, addons) → result` | low |
| G1'-3 | Keyword search (controller + screen) | ~9 382–10 491, ~13 567–14 655, fields ~652–724, `_KwPreservedState` | `lib/services/search/keyword_search_controller.dart` + `lib/screens/search/keyword_search_screen.dart` | 2 100 | controller: query, streamed batches, freeze/adopt, selection, filters; screen params: `isTelevision`, `onOpenStream`, `onBulkAdd` | DPAD tab focus (`_handleKwTabKey`); reachable from Home via `_switchMode`, so the host keeps a thin launcher |
| G1'-4 | Tracker + local continue-watching | ~2 984–3 301, ~4 466–5 439, fields ~872–1 374, row builders ~16 588–16 686 | `lib/services/home/continue_watching_controller.dart` + `lib/widgets/home/continue_watching_row.dart` | 1 700 | per-source loaders → public `CwRow`; node lists owned by the row widget | generation tokens (`_traktReserving`, mdblist revision); `_syncCwNodes` |
| G1'-5 | Favourites rows | ~3 301–4 333, ~16 686–17 006 | `lib/services/home/fav_rows_controller.dart` + `lib/widgets/home/fav_row.dart` | 1 200 | lists + FocusNode lists per `FavKind`; play/open callbacks | `_deferDownMove` deferral must move with the rows |
| G1'-6 | Hero presenter | ~8 585–9 139, flags ~1 542–1 583 | `lib/screens/search/hero_presenter.dart` | 550 | ValueNotifiers to the shell, route callbacks | route awareness via `MainPageBridge` |
| G1'-7 | Discover screen (real) | ~14 655–15 319, ~1 583–1 693, `_DiscoverStage*` in `search_sources.dart` | `lib/screens/discover/discover_screen.dart` | 750 | takes `HomeBoardController.boardRefs` and a `TitleOpener` | own focus tree; must delete the `discoverMode` branches from the host (count them: 66 → 0 for discover) |
| G1'-8 | TV stage layouts | seven `extension on _SearchScreenState` files + cell builders ~7 172–8 585 | `lib/screens/search/stages/<name>_stage.dart`, each a widget taking a `StageHost` interface | 1 400 from host, and the seven extension files become widgets | `StageHost` exposes: rails, hero item, fav focus, trailer flags, `onOpen/onQuickPlay`, deferral hooks | highest risk: `_deferStageRight`, `_seedStageFocusOnce`, hold-key; pin with the existing stage widget tests plus a DPAD walk per stage |
| G1'-9 | Shell cleanup | forwarders from G1 step 1, mode branches | — | 300 | — | delete every forwarder listed as debt |

Sum ≈ 9 300 → screen ≈ 7 700; G1'-9 and the part-file rewrites bring it under 7 500.

### V1 · video_player_screen (one worker, sequential)

| # | Unit | Origin | Target | Leaves | Seam | Risk |
|---|---|---|---|---:|---|---|
| V1-0 | `PlayerLaunchConfig` value object replacing direct `widget.*` reads (~60 ctor params) | 219–388 and the 64 `widget.*` reads in init/episode-nav | `lib/screens/video_player/player_launch_config.dart` | 0 | constructor param | prerequisite for everything below |
| V1-1 | Resume | ~10 281–10 961 | `lib/services/playback/resume_controller.dart` | 650 | `(entry, position, duration)` + `StorageService`; a `ResumeContext` value | 0 setState today; pure |
| V1-2 | Identify-title sheet | ~13 755–14 491 | `lib/widgets/player/identify_title_sheet.dart` | 700 | returns `StremioMeta?` | low |
| V1-3 | Subtitle/track preferences + addon subtitles | ~14 972–15 710, ~3 881–4 073 | `lib/services/playback/subtitle_track_controller.dart` | 900 | needs `mk.Player`, current entry identity, storage | temp-file cleanup stays bound to dispose |
| V1-4 | IPTV recording | ~6 375–6 945 | `lib/services/playback/iptv_recording_controller.dart` | 550 | `mk.Player`, current channel, mpv log tap; state via `ValueNotifier` | desktop capture path |
| V1-5 | IPTV zap ring + catch-up | ~5 382–6 110, ~641–1 046 | `lib/services/playback/iptv_zap_controller.dart` | 1 000 | controller over the channel list with `onSwitch(channel)`; owns page cache and prefetch timers | `_currentIptvChannel` shared 30× |
| V1-6 | Decoder probe / renderer fallback | ~3 159–3 645 | `lib/services/playback/decoder_diagnostics.dart` | 450 | `mk.Player` + diagnostics sink + `recreate()` callback | recreates the player instance |
| V1-7 | Sleep timer, speed, aspect cycle | ~11 852–12 069 | `lib/services/playback/sleep_timer.dart`, small | 200 | timer + `onFire` | trivial |
| V1-8 | Stremio TV guide / next-slot | ~8 366–8 877 | `lib/services/playback/stremio_tv_channel_controller.dart` | 480 | needs `switchToSourcePlaylist` callback | 22 setState → notifier |
| V1-9 | Per-tracker episode-progress lookups (three near-identical) | ~1 884–2 016, ~1 583–1 628 | fold into `ScrobbleCoordinator` (already extracted) as one `episodeProgress(source)` | 150 | — | pin each tracker's answer first |
| V1-10 | Overlay Stack (`build()`) | ~12 561–13 754 | `lib/widgets/player/player_overlay_stack.dart` driven by a `PlayerOverlayModel` notifier | 800 | last: depends on every controller's notifier | 46 `_controlsVisible` refs |

Sum ≈ 5 900 → ~9 800; V1-10's model absorbs remaining flags to reach ≤ 9 500.

### M1 · magic_tv_screen (one worker, sequential; prereq lane P1b)

**P1b (S, cloud layer, separate worker, first):** Real-Debrid and AllDebrid
`CloudProviderPort` adapters for the unlock/add calls Magic TV makes directly
(`DebridService.unrestrictLink`, `addTorrentToDebridPreferVideos`, `AllDebridService.unlockLink`),
as `CloudUnlock`/`CloudMagnetAdd` capabilities with the existing quirk pins. Without this,
M1 cannot leave the screen because two providers have no port.

| # | Unit | Origin | Target | Leaves | Seam | Risk |
|---|---|---|---|---:|---|---|
| M1-0 | `WatchSession` state object (`_queue`, `_isBusy`, `_status`, `_currentWatchingChannelId`, `_pikpakCandidatePool`, progress dialog + snack sinks) | fields 434–503 | `lib/screens/debrify_tv/watch_session.dart` | 0 | `ProgressSink` interface for snack/progress | prerequisite |
| M1-1 | Keyword warm / cache | ~954–1 854 | `lib/services/debrify_tv/channel_cache_warmer.dart` | 850 | `EngineRegistry` + storage; no UI | low |
| M1-2 | Import/export (zip, yaml, text, community, url, share, delete) | ~2 378–3 990 | `lib/services/debrify_tv/channel_import_export.dart` + `lib/screens/debrify_tv/import_export_dialogs.dart` | 1 500 | `ProgressSink`, `channels`, `channelCache` | 28 setState → sink |
| M1-3 | Per-provider watch flows (TorBox, PikPak, Premiumize, AllDebrid, RD path of `_watch`, cached-torrent variants) | ~4 377–6 407, ~7 165–7 600, ~9 485–10 423 | `lib/screens/debrify_tv/watch/<provider>_watch_flow.dart` sharing `WatchSession` | 3 000 | `WatchSession` + `CloudProviderPort` (after P1b) | `_queue` mutated 30× per flow; keep order of operations byte-for-byte |
| M1-4 | `_switchToChannel` + Android TV launchers | ~6 408–7 165 | joins `WatchSession` | 700 | — | reads storage + RD/AD directly today |
| M1-5 | Channel dialog + settings card | ~2 059–2 377, ~9 064–9 447 | `lib/screens/debrify_tv/dialogs/` (exists) | 650 | return values | low |
| M1-6 | Queue prefetcher | ~10 504–10 742 | `lib/services/debrify_tv/queue_prefetcher.dart` | 230 | queue + provider port | AllDebrid unlock inside |

Sum ≈ 6 900 → ~3 900.

### S2 · storage_service (one worker, sequential; replaces G3)

Pattern to copy: `lib/services/storage/home_prefs.dart`, `cloud_secret_prefs.dart`,
`storage_key_ownership.dart` (update the key registry in every PR). Keys and encodings
are frozen; every PR carries a prefs snapshot test (write through the old API, read
through the new, byte-equal) and keeps `StorageService.x` as a forwarding facade until
callers move.

| # | Store | Origin | Leaves |
|---|---|---|---:|
| S2-0 | key ownership registry completed + facade rule | `storage_key_ownership.dart` | 0 |
| S2-1 | `stremio_tv_prefs.dart`, `social_prefs.dart` (reddit/lemmy/youtube), `debrify_tv_prefs.dart` — no revision notifiers | ~9 233–9 617, ~5 942–6 400, ~4 000–4 400 + ~7 860–8 110 | 1 400 |
| S2-2 | `provider_credential_prefs.dart` | ~600–700, ~1 880–2 060, ~6 700–7 280 | 900 |
| S2-3 | `player_prefs.dart`, `iptv_prefs.dart` | ~1 341–1 420, ~8 211–8 880; ~5 175–5 600, ~8 640–9 142 | 1 600 |
| S2-4 | `app_style_prefs.dart` (sync style caches) | ~1 000–1 830 | 800 |
| S2-5 | `tracking_prefs.dart` (owns `trackingSourceRevision`) | ~5 900–6 250 | 350 |
| S2-6 | `playback_progress_store.dart` (owns `localCompletionRevision`, `_getPlaybackStateMap`) | ~2 383–4 823 | 2 300 |
| S2-7 | split `migrateDefaultsGeneration` into per-store `migrate()` hooks | ~137–599 | 400 |

Sum ≈ 7 750 → ~1 900 facade + consts.

### Unchanged from the original plan

G2 (settings_screen split, now target ≤ 3 000), G4 (cloud file screens; after P1b it can
also use the RD/AD ports), G5 is **closed** — scrobbling was already extracted into
`lib/services/scrobble/`; its remaining triplication is V1-9. T2 (tracker commons) stays.

## 4. Sequencing and parallel width

```
P1b (cloud, S)  ──► M1-0 … M1-6      (one worker)
G1'-0 … G1'-9                        (one worker, longest)
V1-0 … V1-10                         (one worker)
S2-0 … S2-7                          (one worker)
G2, G4 (after P1b), T2               (one worker each, when free)
```

Five workers at once is the ceiling: four god-file lanes plus one of G2/G4/T2. The
orchestrator runs a phase gate (full suite, analyzer over everything, Windows and
Android builds on the Windows host, manual smoke) after every **three** merged
extractions per lane, not only at the end, because these PRs are large.

## 5. Gate additions for this phase

To the five checks in `REFACTOR_PLAN.md` §6 add:

- (f) the god file's `wc -l` delta meets the PR's stated "Leaves" number;
- (g) the new unit compiles with the god file's private members removed (grep for `_`
  members of the host inside the new file: zero), and no new `part of` / `extension on`
  the host State;
- (h) the pin commit predates the move commit and passes on the parent of the move.

## 6. Definition of done (revised)

- The four files hit the targets in §1; `search_screen.dart` has no `extension on
  _SearchScreenState` and no part file over 1 500 lines.
- Zero provider-string comparisons outside `lib/services/cloud/` except `main.dart`
  sidebar labels and settings search keywords (declared exemptions).
- Every store in `lib/services/storage/` owns its keys in `storage_key_ownership.dart`;
  `StorageService` is a facade of forwarders plus constants.
- All Phase 1/2 debt lines (forwarders) deleted, or listed in `REFACTOR_NOTES.md` with the
  lane that deletes them.
- Gate 2 passes with the full suite, all-of-lib analyzer, both builds, and the manual
  smoke; a backup exported before Phase 0 restores cleanly.
