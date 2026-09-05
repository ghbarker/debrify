# Refactor board

Updated 2026-09-05 after main `d5f8dc4b` (CW merge `e478635e`). Orchestrator owns this board and NOTES. Binding contracts: [original plan](REFACTOR_PLAN.md), [Phase 2 correction](REFACTOR_PLAN_PHASE2.md), and latest explicit user decisions below. Historical snapshots remain in Git history; they are not current assignments.

## Live roadmap

### Working now
- User authorized continued extraction without manual smoke. Temporary automatic-sleep prevention verified: helper PID3412, expires 2026-09-05 16:43 UTC; permanent power settings unchanged.
- [ ] **Cicero — native CI plan:** CW automated mini-gate complete; final114 independent19case verification complete. Planning mandatory native runtime CI for draft116, no workflow edits yet.
- [ ] **Wegener — keyword update audit:** keyword pin complete ee9de82b; opening corrective PR, then G1'-5 favourites rows assigned on refactor/g1-5-favourites-rows. Ampere independently reviews pin.
- [ ] **Ampere — player origin proof:** native audio mount/dispose, identify cancel and disposal checkpoint write proven oldest/current with mutation. Draft116 open; native CI/analyzer dependency unresolved. keyword independent review assigned, then M1-3 assigned on refactor/m1-3-provider-watch-flows; exact file locks due before edits. No full V1 closure.
- [ ] **Locke — storage fixtures (#114):** 141/141 admitted keys and28/28 exclusions complete; all5 dynamic families finitely sampled (21keys). Exact final `3e30de17` independent19case review passed; merged c5f022de; final CI passed. S2-6 origin characterization assigned on refactor/s2-6-playback-progress-store; 114 merged; extraction authorized after green origin pins. Forecast1750–1950 net vs2300 target; no padding, deficit recorded below.

### Next, in order
- [x] Finish current merged-code automated mini-gate.
- [ ] Manual smoke explicitly deferred by user at 09:44 UTC September 5: proceed with eligible lanes without it. Automated gates remain mandatory; no manual pass claimed (SHIELD unavailable).
- [x] #114 merged c5f022de: independent19 tests and exact-head test/goldens passed. Dynamic families are finite samples, never exhaustive suffix coverage.
- [ ] Resolve remaining origin-test debt and keyword audit without speculative fixes or expanding native scope.
- [x] Map upstream strategy before more divergence: upstream `db440a8d`, fork at `0d4ca1a2` was 385 ahead/0 behind. Existing upstream PRs #55 then #54 then #56 must refresh/test sequentially; pairwise conflicts identified. No bulk fork submission or upstream messages sent.
- [ ] Resume eligible sequential slices only after their gates: Search G1'-5..9, Player V1-6..10, Magic TV M1-3..6, Storage S2-6..7.
- [ ] Q1 layering enforcement; Q2 remove expired forwarders and migrate callers; Q3 engineering-rule consolidation.

### Completed this correction round
- [x] #108 Windows source guards: 21 independently reproduced tests, clean analysis.
- [x] #111 M1 dependency correction: seven invalid imports removed; 65 targeted and 40 pre-move tests independently reproduced.
- [x] #110 Windows analyzer launcher + upstream Flutter pin + restored layering ceiling 77. Full corrective suite and both native builds passed.
- [x] #113 roadmap/decisions merged; board updates now committed directly to main, docs only.
- [x] #115 M1 retrospective proof: nine live origin/current tests, mutation-sensitive. Does not retroactively satisfy pin-before-move chronology.
- [x] #96 CW integration: independent disposal/rebuild tests, compatible merged-main layering, exact-head test/goldens green. #104/#105/#107 closed as duplicates; their patches are preserved in #96.
- [x] SDK/JDK installed outside repository; Android license explicitly accepted. No persistent global PATH changes.

### Blocked or parked
- [ ] SHIELD smoke: hardware unavailable. Phone testing is not a substitute pass.
- [ ] Current merged-build manual smoke deferred by explicit user decision; no longer blocks extraction. No manual pass claimed.
- [ ] Remaining V1 origin behavior coverage: real player test feasibility underway; source scans/copied bodies do not clear it.
- [x] #114 coverage review and CI complete; merged.
- **Parked:** #112 backup decoder (feature scope creep), #109 test kit (outside assigned lane), #56 Qwen helper (Phase 3). No product work on #112.

## Exclusive active ownership

| Work | Status | Branch / checkout | Owner | Writable scope | Next dependency |
|---|---|---|---|---|---|
| Current G1 mini-gate | automated complete; manual deferred | detached `e478635e`, `debrify-c0-g1-main-gate` | Cicero | no tracked edits; verification/artifacts only | tests/builds, then device smoke |
| Keyword duplicate-update audit | in-progress | current main / read-only | Wegener | no edits assigned | evidence before any correction |
| V1 origin-host proof | in-progress | `refactor/v1-origin-host-pin` | Ampere | new `test/video_player_origin_behavior_test.dart` only | bounded native-audio feasibility, no production seams |
| S2 origin restore fixtures | in-progress | `codex/storage-origin-restore-fixture` | Locke | `test/storage_origin_restore_fixture_test.dart`, `test/fixtures/storage_origin_restore/**` | final domain, independent review and CI |
| Orchestration | in-progress | `codex/orchestrator-gate3` synced to main | parent | BOARD + NOTES only | respond to worker events; merge verified results |

No worker starts another lane independently. Workers report completion/blockers directly; parent handles review, decisions and reassignment. Hourly fallback only; no worker polling timers. Corrective wave width: four workers.

## Gate evidence

| Gate | Exact source | Analyzer / layering | Full suite | Windows / Android | Status |
|---|---|---|---|---|---|
| Gate 3 user audit | `843d631b`, Windows Flutter 3.47.2 | 471 issues, zero errors; layering 84 unique | 5143 pass / 37 fail (33 baseline + 4 Windows guards) | user reported both pass | accepted with notes, historical report |
| Corrective integration | `0abc4c8`, tree identical to #110 `8bd40543`; Flutter 3.44.8 | 454 issues, zero new against unchanged 470-entry baseline; layering 77, delta zero vs #72 | 5168 pass / 33 exact allowlisted / 2 skip; zero unexpected or unused | Windows pass 127.4s; ARM64 APK pass 384.8s | automated gate passed; not current CW/manual proof |
| CW merge check | #96 `3961eee5`; merged tree `fd9b5b6` | 77/ceiling77; no added analyzer allowance, one location relocation | independent 3 disposal/rebuild tests pass; targeted worker evidence + exact-head CI test/goldens pass | prior builds do not cover this new tree | merge conditions passed |
| Current CW mini-gate | actual merged main `e478635e`, tree `fd9b5b6` |454/no new;77layering,no delta |5199pass/33exactallowlisted/2skip,zero unexpected/unused |Windows pass130.4s;Android ARM64 pass97.5s | manual smoke pending |

Flutter follows upstream: **3.44.8**, verified upstream workflow blob `2a48503bcf470fef4affcc606182c90444855511`. Separate local SDK used; no automatic golden regeneration or diagnostic rebaseline. Layering ceiling is **77** from #72, not historical 90. Current analyzer baseline has 470 entries; historical 466 diagnostic count is not its replacement.

## Size and debt accounting

| God file | Original board baseline | Phase 2 baseline | Current after #96 | Phase 2 target |
|---|---:|---:|---:|---:|
| search_screen.dart | 19070 | 17039 | 11376 | 7500 |
| video_player_screen.dart | 16278 | 15771 | 11926 | 9500 |
| magic_tv_screen.dart | 10716 | 10752 | 8369 | 4500 |
| storage_service.dart | 9963 | 9634 | 6282 | 2800 |
| settings_screen.dart | 7905 | 3107 | 2899 | 3000 |

Host Leaves are not repository shrinkage. #96 Leaves 1732; production/test/scaffold accounting belongs in its PR. #100/#102 screen-layer relocations earn no second extraction credit: V1-1 666, V1-2 527, V1-3 943, V1-4 704, V1-5 1008 are historical host reductions, not proof of pure logic separation.

Shortfalls: S2-1 869, S2-2 325, S2-3 533 assigned S2-7; avoid counting later slices twice. V1-2 shortfall173 remains subject to explicit accounting; a later lane exceeding its own target by43 does not alone prove173 cleared. Temporary forwarders: G1'-9, S2-7, and final Q2 caller migration/removal before Phase3 completion. M1 inherited63physical/34nonblank adapter lines retained for correction: dialog hooks M1-5; full seam review/removal M1-6. #96 duplicate-listener allegation disproven; required host listener retained. #90 keyword allegation is a separate live audit.

## Budget

- **16 extraction slices remain:** Search5, Player5, MagicTV4, Storage2; plus **3 Phase3 lane groups**. Q2 can require several area PRs.
- Additional work: current mini-gate, S2 fixture completion, bounded V1/M1 evidence and upstream/device validation. Planning range roughly **4–7 corrective/validation work packages**, not guaranteed PR or time counts.
- Account snapshot 2026-09-05: **26% used /74% remaining weekly quota**. Account-wide, not project-only. No measured per-task tokens or reliable quota-per-lane estimate; refresh after three-slice gates. No credit redemption authorized.
- Fixture estimate initially8–14focused hours; completed-domain checkpoints roughly4–9minutes each, not linear estimates for conditional/family work. Track actual checkpoints rather than invent a completion date.
- #96 disposal cap completed: deterministic guard mutation plus one final SDK verification passed. No further pin-design attempts authorized.
- V1 probes hard-capped by assignment; stop on unavailable seams rather than widen. Every PR retains **Did we make a difference?** and **Is there more we could do?**.

## Decisions and history

Aim to contribute upstream, not a permanent fork. Upstream refresh ordering precedes further contribution publication. Scope exclusions and preserved quirks are in [REFACTOR_NOTES.md](REFACTOR_NOTES.md). Historical lane rows and old gate snapshots are available in Git history; they must not override this current board. Phase0/Phase1 registries and corrective follow-ups merged; old G1/G3/G5 work was superseded by the binding Phase2 plan. New lane assignments must use its exact owned files and gates.

## Latest assignment decisions — 2026-09-05 09:44 UTC

Manual smoke is deferred by explicit user instruction; continue eligible work. C0 owns native CI116; Wegener owns G1'-5 host/favourites files after corrective pin PR; Ampere reviews keyword pin then owns M1-3 watch-flow files; Locke owns S2-6 storage files;114 merged. Workers must confirm exact paths before edits. Shared CODEMAP edits require serialized ownership. No ownership of each other's host files.

S2-6 functional scope retained, forecast1750–1950 net against original2300:350–550 potential deficit is outstanding debt pending exact overlap accounting and clearing slice S2-7/Q2; no automatic target waiver or double credit for already-extracted TV/reset code. Origin pins proceed now. Manual testing remains unproven.

### Merge114 — 2026-09-05
Exact head3e30de17 verified CI test/goldens SUCCESS; independent19case reproduction passed. Merged c5f022de. Difference: real pre-refactor export/current restore compatibility pins for141 named keys,28 exclusions and finite5family samples. More: conditional/dynamic domains remain finite and each new storage slice must pin its own behavior. S2-6 unblocked; other active lanes share no changed production files with114. God counts unchanged from current table (test/fixture-only merge).

S2-6 ownership extension: Locke exclusively owns test/storage_key_sweep_test.dart import/store-discovery/exact-alias additions; assertions must not weaken. CODEMAP storage-routing rows exclusively locked to Locke until commit/release. Current extraction reports1867 net Leaves,433 uncredited deficit. Independent review still required. C0 authorized fast-forward PR116 to24dc0dcb; native Linux execution required before merge.


G1'-5 destination decision approved: lib/screens/search/fav_rows_controller.dart and fav_row.dart retain Flutter/focus ownership in screen layer; no new service-layer UI dependency. Wegener starts real-origin pins now; CODEMAP waits only at completion (Locke owns current lock). C0 independent S2-6 checkpoint review assigned while native CI116 executes. PR117 test passed, goldens pending; independent keyword review complete. Awake helper3412 verified running.


S2-6 draft PR118 published, frozen609b823550034d58b58dc00127be2067c4ee50e7. C0 independent review active; Locke holding branch stable. Worker reports104core+120consumer+9sweep+12allowlist passes,cleananalysis,77layering; not parent gate credit until reproduced.1867Leaves/433uncredited debt. All67bodydiffs and70method inventory included in PR. CODEMAP lock released. M1-3 quickwatch835line mapping accepted in scope; origin21cases green, sensitivity/pincommit precede move.

