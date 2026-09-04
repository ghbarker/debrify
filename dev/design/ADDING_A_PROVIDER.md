# Adding a New Debrid/Cloud Provider

The live playback/add/unlock seam is `CloudProviderPort` + `CloudProviderRegistry`
under `lib/services/cloud/`. This is a **half-migration**: adapters and the
registry exist, but several screens still string-match provider ids. Do not
reintroduce a five-way `switch` inside `TorrentPlaybackService._add`. Do not
“fix” remaining string-match sites here — that is lanes **P1** / **P2**.

Convention: providers are identified by lowercase playback ids
(`debrid`, `torbox`, `pikpak`, `premiumize`, `alldebrid`). Real-Debrid is stored
as `rd` on bound sources — map through `CloudProviderId` in
`lib/services/cloud/cloud_provider_id.dart`.

Reference implementations: **AllDebrid** (newest) and **Premiumize**, plus the
existing adapters in `lib/services/cloud/`.

---

## 0. Cloud port (required) — `CloudProviderPort` / registry / adapters

- **New adapter:** `lib/services/cloud/<id>_cloud_provider.dart` implementing
  `CloudProviderPort` (`lib/services/cloud/cloud_provider_port.dart`).
  Production adapters extend `CloudProviderAdapter` and inherit `supports`
  from `CloudPortFeature.forProvider` (`lib/services/cloud/cloud_port_feature.dart`).
  The port is one fat interface with `CloudUnsupported` throw-stubs for
  methods the adapter does not implement (**P1** splits this into
  `CloudUnlock` / `CloudMagnetAdd` / `CloudPlaylist` / `CloudMagicTv` /
  `CloudCachedHashes`).
- **Minimum playback surface today:** `isConfigured` + `addMagnet` +
  `resolveNativeBound` (hashless bound replay; RD/TorBox/AllDebrid
  web-downloads only; lookup is stored id `rd`, not playback `debrid`) +
  `resolvePlaylistEntry` (download-picker lazy URL; field presence, not
  `entry.provider`; TorBox web-download / PikPak / Premiumize stay on
  `unlockPlaybackEntry`) + `unlockPlaybackEntry` (adapter HTTP;
  launcher/TV registry dispatch throws; TorBox before RD; web-download
  counts).
- **Register** the adapter in `CloudProviderRegistry.production()`
  (`lib/services/cloud/cloud_provider_registry.dart`). Tests replace
  `CloudProviderRegistry.instance` with `FakeCloudProvider`s
  (`test/adversarial/provider_matrix_test.dart`).
- **Ids / credential keys / backup field names / display names / chip codes /
  overlay titles / playlist stored ids** go on `CloudProviderId` (keep Flutter
  out of the enum). `displayName` is `TorBox`; `overlayTitle` is `Torbox`.
- **Credential reads** go through `CloudCredentials`
  (`lib/services/cloud/cloud_credentials.dart`):
  `configured(id, CloudConfiguredCheck)` with dialects `playback` / `magnet` /
  `stremioPicker`. Magnets also require the integration-enabled toggle.
  `StremioTvResolveGate.canAttempt` is not a fourth `configured()` flavour.
- **Registry helpers already used by TPS / player / Stremio TV / Magic TV
  prepare:** `unlockPlayerScreenEntry` (wraps HTTP; incomplete Premiumize does
  not fall through to RD), `resolveStremioTorrent` (`realdebrid` via
  `tryParse`; auto order is PikPak before Premiumize; null on miss — do not
  reuse `addMagnet` or playback precedence), `prepareMagicTv` (`real_debrid`
  via `tryParse`; magnet has no `dn=`; random unseen file; RD/AllDebrid
  return null), `prepareMagicTvLockedLinks` (RD/AllDebrid locked URLs;
  TorBox/PikPak/Premiumize return null).
- **Downloads** bind with `DownloadService.enqueueCloudFile` /
  `credentialKeyForCloudProvider`.
- **Playlist items** go through `CloudPlaylistPayload` (`realdebrid` id, empty
  URL on RD singles).
- **Pipeline chrome** goes through `CloudProviderChrome`
  (`lib/widgets/cloud_provider_chrome.dart`): playback-id
  `label`/`code`/`gradient`/`icon` (no `rd`/`realdebrid` parse), plus
  `catalogChip` / `catalogTitle` which *do* parse Stremio's `realdebrid` /
  `auto`.
- **Bind-source cloud browsers** go through `CloudBrowseSelectSource`
  (`lib/screens/cloud/cloud_browse_select_source.dart`) — playback id only;
  `rd` does not open Real-Debrid. Catalog / Trakt / aggregated RD vs TorBox
  pickers use `pushRdOrTorbox`.
- **Backups** pick up API keys from `CloudCredentials.backupSecrets()`.
- HTTP clients still live in `lib/services/<provider>_service.dart` (Real-Debrid:
  `lib/services/debrid_service.dart`; PikPak: `lib/services/pikpak_api_service.dart`).
  Do not rewrite those to add a provider.

### Remaining string-match sites (do not “fix” in the adapter PR)

The port is not done until **P2**. At high level these still compare provider
strings outside `lib/services/cloud/`:

| Area | Files | Lane |
|---|---|---|
| Debrify TV | `lib/screens/magic_tv_screen.dart` | P2a |
| Stremio TV | `lib/screens/stremio_tv/` | P2b |
| Launcher + bulk-add | `lib/services/video_player_launcher.dart`, `lib/services/torrent_bulk_add_service.dart` | P2c |
| Playlist / cloud / default picker | `lib/screens/playlist_content_view_screen.dart`, `lib/services/playlist_player_service.dart`, `lib/screens/cloud_screen.dart`, `lib/screens/settings/provider_settings_page.dart` | P2d |
| Storage toggles / keys | `lib/services/storage_service.dart` | later G3 / P2d callers |
| Stremio TV settings picker | `lib/screens/settings/stremio_tv_settings_page.dart` (RD/TB/PikPak only) | P2 |
| Dead legacy search | `lib/screens/deprecated/torrent_search_screen.dart` (D0 deletes) | D0 |

A new provider that must work on those surfaces still has to be wired there
until P2 lands. Live search/play is `lib/screens/search_screen.dart` +
`lib/services/torrent_playback_service.dart` + the registry, not the
deprecated screen.

---

## Planned registries (do not invent them)

From `dev/design/REFACTOR_PLAN.md` §3 — **planned**, with lane ids:

| Registry | Lane | What it will replace |
|---|---|---|
| `CloudProviderRegistry` (exists) + capability interfaces | **P1** | remaining provider-string switches; `supports()` → `is`-checks |
| `HomeRowRegistry` | **H1** | Home row id grammar / manager / board |
| `TransferCategoryRegistry` | **T1** | backup + remote transfer categories (see checklist below) |
| `SettingsPageRegistry` | **S1** | settings tree, TV layout, search index |
| `TrackerRegistry` | **T2** | per-tracker switches in tick/scrobble/CW wiring |

---

## Remote transfer 11-site checklist (until **T1**)

The plan called this “until lane R1”; there is no R1 on the board — **T1** is
that lane. Until `TransferCategoryRegistry` exists, a new transfer category
(including a provider API-key category) still needs **11 registrations**:
backup `build` / `summarize` / `apply`, the `BackupSelection` /
`BackupSummary` / `RestoreReport` field triplets, and the remote router's
**five maps**.

Consumer files from the plan table (paths that exist):

| # | Site | File |
|---|---|---|
| 1 | `buildBackup` | `lib/services/backup_restore_service.dart` |
| 2 | `summarize` | `lib/services/backup_restore_service.dart` |
| 3 | `applyBackup` | `lib/services/backup_restore_service.dart` |
| 4 | `BackupSelection` field | `lib/services/backup_restore_service.dart` |
| 5 | `BackupSummary` field | `lib/services/backup_restore_service.dart` |
| 6 | `RestoreReport` field | `lib/services/backup_restore_service.dart` |
| 7–11 | remote router’s five maps | `lib/services/remote_control/remote_command_router.dart` |

Same plan table also lists these consumers (tiles / labels / restore
literals / settings summary):

- `lib/widgets/remote/remote_config_export.dart`
- `lib/widgets/remote/remote_transfer_all.dart`
- `lib/widgets/onboarding/onboarding_flow.dart` (`_configLabel`)
- `lib/services/profiles/profile_restore_coordinator.dart` (`BackupSelection` literals)
- `lib/screens/settings_screen.dart` (settings summary formatters — **S1**)

Wire `ConfigCommand` **strings** if a new credential travels over remote
(`lib/services/remote_control/remote_constants.dart`). Those strings are a
frozen compatibility surface: add a new constant; do not rename existing ones.

---

## 1. Account model

Parse the provider's account/user info.

- **New file:** `lib/models/<provider>_user.dart`
- Reference: `lib/models/torbox_user.dart`, `lib/models/premiumize_user.dart`
- Include helpers like `hasActivePremium`, `formattedPremiumExpiry`, `subscriptionStatus`.

## 2. API service

Network calls + validation against the provider API.

- **New file:** `lib/services/<provider>_service.dart`
- Reference: `lib/services/torbox_service.dart`, `lib/services/premiumize_service.dart`
- At minimum: `getUserInfo(apiKey)` that throws on bad key / error response.

## 3. Account service (session state)

Static holder + reactive `ValueNotifier`, validate/persist/refresh/clear.

- **New file:** `lib/services/<provider>_account_service.dart`
- Reference: `lib/services/torbox_account_service.dart`, `lib/services/premiumize_account_service.dart`
- Keep the validation-token guard and `persist` flag pattern.

## 4. Storage (SharedPreferences)

- **Edit:** `lib/services/storage_service.dart` (and `CloudSecretPrefs` /
  `CloudCredentials` so the port can read the key).
- Add key constants near the other provider keys.
- Add getters/setters: `get/save/delete<Provider>ApiKey`,
  `get/set<Provider>IntegrationEnabled`.
- Preference **key strings** are a frozen compatibility surface.

## 5. Account status widget

- **New file:** `lib/widgets/<provider>_account_status_widget.dart`
- Reference: `lib/widgets/torbox_account_status_widget.dart`, `lib/widgets/premiumize_account_status_widget.dart`

## 6. Provider settings page (API key entry)

- **New file:** `lib/screens/settings/<provider>_settings_page.dart`
- Reference: `lib/screens/settings/torbox_settings_page.dart`, `lib/screens/settings/premiumize_settings_page.dart`

## 7. Settings screen — Connections card

Until **S1**, adding a page still touches ~6 sites.

- **Edit:** `lib/screens/settings_screen.dart`
  - Import the account service + settings page.
  - Connections card + `_loadSummaries()` `Future.wait` index.
  - `_ConnectionInfo` entry + open handler.
  - In `_ConnectionsSummary`: field, focus node (init + dispose), and
    **re-wire the grid neighbors** for the new card count.
- TV layout: `lib/screens/settings/settings_tv_layout.dart`
- Search index `leaf()` tables: `lib/screens/settings/widgets/settings_widgets.dart`

## 8. Default provider picker

- **Edit:** `lib/screens/settings/provider_settings_page.dart` (still a
  string-match site, **P2d**). Gate on key + integration enabled, add the
  radio `_ProviderOption` (stores playback id e.g. `'premiumize'`).

---

## 9–14. Search, cache badges, Quick Play, bound sources, bulk add, post-torrent

These used to be documented against a 26k `torrent_search_screen.dart`. That
file is now `lib/screens/deprecated/torrent_search_screen.dart` (D0). Live
paths:

- Play/add/bind: `lib/services/torrent_playback_service.dart` → registry
  (`addMagnet`, `resolveNativeBound`, `queueUncachedMagnet`, …).
- Home/Search UI: `lib/screens/search_screen.dart` (+ `lib/screens/search/`
  parts).
- Cache badges: Home/Sources still call registry cache methods with their
  own key-null gates (`CloudPortFeature.cachedHashes` vs `checkCache`).
- Bulk add: `lib/services/torrent_bulk_add_service.dart` (**P2c**, still
  string-matches).
- Post-torrent action prefs: still per-provider keys on `StorageService`;
  helpers live with the search/settings UI.

Implement provider-specific HTTP in `lib/services/<provider>_service.dart`,
then expose it on the adapter. Loading overlay:
`DebridLoadingOverlay.showForPlaybackId`. Bind-source chip colours:
`CloudProviderChrome.sourceChip` (do not reuse playback `gradient`).

## 15–16. Backup / remote

Follow the **11-site checklist** above. Do not skip export/transfer-all tiles
or onboarding `_configLabel`. Receiver handlers still live as
`_handle<Provider>Config` on `lib/services/remote_control/remote_command_router.dart`
until T1 derives them from the registry. Validate keys on the wire (unlike
file restore).

## 17. Debrify TV / Magic TV

`prepareMagicTv` / `prepareMagicTvLockedLinks` on the adapter cover the
registry-owned prepare path. The screen
(`lib/screens/magic_tv_screen.dart`) still string-matches for chips,
availability, and `_watch*` dispatch (**P2a**). Overlay strings:
`lib/services/cloud/magic_tv_provider.dart`.

## 18. Stremio TV

Picker rows: `CloudCredentials.stremioPickerChoices`. Resolve:
`CloudProviderRegistry.resolveStremioTorrent`. Cache filter:
`StremioTvCacheFilter` / `StremioTvTorboxCache`. The screen
(`lib/screens/stremio_tv/stremio_tv_screen.dart`) and
`lib/screens/settings/stremio_tv_settings_page.dart` still string-match
(**P2b**). Settings picker is RD/TB/PikPak only today.

## 19. Playlists

`CloudPlaylistPayload` + `resolvePlaylistEntry` / `unlockPlaybackEntry` /
`unlockPlayerScreenEntry`. Remaining provider branches:
`lib/screens/playlist_content_view_screen.dart`,
`lib/services/playlist_player_service.dart`, player/launcher reconstruct
paths (**P2d**). Carry every lazy-resolution field through `_prepareEntries`
or TV/external replay silently drops refresh.

## 20. Cloud library tab

Per-provider files screens still exist (G4 will unify them):

- `lib/screens/debrid_downloads_screen.dart`
- `lib/screens/torbox/torbox_downloads_screen.dart`
- `lib/screens/pikpak/pikpak_files_screen.dart`
- `lib/screens/premiumize/premiumize_files_screen.dart`
- `lib/screens/alldebrid/alldebrid_files_screen.dart`

`MainTab` **indices** are a frozen compatibility surface. Hide-from-nav flags
stay on `StorageService`. `lib/main.dart` still lists sidebar labels.

## 21. Onboarding

`lib/widgets/initial_setup_flow.dart` re-exports
`lib/widgets/onboarding/onboarding_flow.dart`. Add the chip / controller /
validate path there. `_configLabel` is one of the T1 consumers.

## 22. Deeplink / share intent

`lib/services/deep_link_service.dart` (`ConfiguredServices`) and
`lib/services/magnet_link_handler.dart`. Magnet “configured” is
`CloudCredentials.isMagnetConfigured`, not playback `isConfigured`.

---

### Quick verify

```
flutter analyze lib/services/cloud/<id>_cloud_provider.dart \
  lib/services/cloud/cloud_provider_registry.dart \
  lib/services/cloud/cloud_provider_id.dart \
  lib/services/cloud/cloud_credentials.dart \
  lib/screens/settings/<provider>_settings_page.dart \
  lib/services/<provider>_service.dart \
  lib/services/<provider>_account_service.dart \
  lib/models/<provider>_user.dart \
  lib/widgets/<provider>_account_status_widget.dart
```

Do not rename prefs keys, backup payload keys, `ConfigCommand` strings,
`MainTab` indices, or Home row id grammar.
