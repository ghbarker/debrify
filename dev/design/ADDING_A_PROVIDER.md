# Adding a New Debrid/Cloud Provider

The live playback/add/unlock seam is `CloudProviderPort` + `CloudProviderRegistry`
under `lib/services/cloud/`, with production capability interfaces already in
use. The fat port remains for compatibility; it is not the production capability
check. Do not reintroduce a five-way `switch` inside
`TorrentPlaybackService._add` or change consumer policy as part of an adapter PR.
The source paths below describe merged main `cb261b5b`; they do not claim that
every provider surface is autonomous or that remaining refactor lanes are closed.

Convention: providers are identified by lowercase playback ids
(`debrid`, `torbox`, `pikpak`, `premiumize`, `alldebrid`). Real-Debrid is stored
as `rd` on bound sources — map through `CloudProviderId` in
`lib/services/cloud/cloud_provider_id.dart`.

Reference implementations: **AllDebrid** and **Premiumize**, plus the
existing adapters in `lib/services/cloud/`.

---

## 0. Cloud port (required) — `CloudProviderPort` / registry / adapters

- **New adapter:** a provider-specific file under `lib/services/cloud/` extending
  `CloudProviderAdapter` (`lib/services/cloud/cloud_provider_port.dart`) and
  implementing the capabilities it actually supports. Production `supports`
  uses `CloudPortFeature.of(this)` (`lib/services/cloud/cloud_port_feature.dart`),
  which derives features from capability `is` checks. `CloudPortFeature.forProvider`
  remains the provider-ID matrix for fat-port `FakeCloudProvider` tests; the
  matrix must agree with the production adapter's capabilities.
- **Existing capabilities:** `CloudUnlock`, `CloudMagnetAdd`, `CloudPlaylist`,
  `CloudMagicTvPrepare`, `CloudMagicTvLockedLinks`, `CloudCachedHashes` and
  `CloudCheckCache` are in `lib/services/cloud/cloud_capabilities.dart`.
  `CloudPlaylist.resolvePlaylist` returns `CloudPlaylistResolve`, including
  `CloudPlaylistMiss`; unsupported capability and supported miss are distinct.
  The legacy `CloudProviderPort` and adapter throw-stubs remain compatibility
  surfaces, not instructions to implement unsupported operations. Live Magic TV
  unlock has separate interfaces in `lib/services/cloud/cloud_magic_tv_unlock.dart`.
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
- **Live versus captured Magic TV credentials:** registry live-unlock methods
  use `CloudMagicTvRdUnlock` / `CloudMagicTvAdUnlock`; their production methods
  read the current key through `CloudCredentials` and throw `CloudMissingApiKey`
  when absent. `CloudMagicTvCapturedRdUnlock.unrestrictLinkWithKey` /
  `addTorrentPreferVideosWithKey` and
  `CloudMagicTvCapturedAdUnlock.unlockLinkWithKey` instead take the caller's
  already-captured key. The RD/AD adapters delegate that exact key to the existing
  HTTP service without a key reread or an additional missing-key check.
  `WatchFlowBindings` carries these typed operations into `ProviderWatchFlow`
  and the leaf programmes; quick and cached callers
  keep their existing capture timing. Do not replace a captured call with the
  live registry route after an await or profile change. RD still returns its
  `Map<String, dynamic>` and AD its `String`; preserve the caller's catch,
  null/empty handling and ordering. See `lib/services/cloud/rd_cloud_provider.dart`,
  `lib/services/cloud/alldebrid_cloud_provider.dart` and
  `lib/screens/debrify_tv/watch/provider_watch_flow.dart`.
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

### Consumer boundaries (not an adapter-only feature switch)

P1/P2 registry routing is already present. Verify the particular consumer's
eligibility and ordering instead of following the old pending-lane checklist:

- Debrify TV: `lib/screens/magic_tv_screen.dart` and
  `lib/screens/debrify_tv/watch/provider_watch_flow.dart` retain admission and
  continuation policy around the cloud capabilities.
- Stremio TV: `lib/screens/stremio_tv/stremio_tv_screen.dart` uses the credential
  picker and registry resolver; `lib/screens/settings/stremio_tv_settings_page.dart`
  remains a separate picker policy (RD/TB/PikPak).
- Launcher and bulk add: `lib/services/video_player_launcher.dart` and
  `lib/services/torrent_bulk_add_service.dart` retain distinct chooser and
  playback precedence. Bulk chooser order is TB, RD, PP, PM, AD.
- Playlist/cloud/default picker: `lib/screens/playlist_content_view_screen.dart`,
  `lib/services/playlist_player_service.dart`, `lib/screens/cloud_screen.dart`
  and `lib/screens/settings/provider_settings_page.dart` retain their own UI
  and payload contracts. `DefaultProviderDispatch` uses typed provider IDs.
- Storage toggles and post-torrent keys are owned by
  `lib/services/storage/provider_credential_prefs.dart`; do not add another
  key owner or rewrite stored provider strings.

Live search/play remains `lib/screens/search_screen.dart` plus
`lib/services/torrent_playback_service.dart` and the registry.

## Existing registries (reuse their current contracts)

These registries exist; their presence does not mean every surrounding UI or
compatibility adapter has been removed:

- `CloudProviderRegistry`: `lib/services/cloud/cloud_provider_registry.dart`.
- `HomeRowRegistry`: `lib/services/home/home_row_registry.dart`; preserves Home
  row grammar and canonical ordering.
- `TransferCategoryRegistry`: `lib/services/transfer/transfer_category_registry.dart`.
- `SettingsPageRegistry`: `lib/screens/settings/settings_page_registry.dart`.
- `TrackerRegistry`: `lib/services/tracking/tracker_registry.dart`; do not unify
  distinct tracker HTTP/scrobble semantics when adding a cloud provider.

## Remote transfer compatibility checklist

`TransferCategoryRegistry.production()` uses `TransferCategories.builtins` in
`lib/services/transfer/transfer_categories.dart`. A category's payload/wire keys,
encoding, build/apply/count and remote flags are declared through
`lib/services/transfer/transfer_category.dart`. Backup build/apply and the remote
router already consume the registry, including its derived wire maps. The old
"11 registrations until T1" description is no longer the wiring model.

Still verify the same compatibility surfaces: backup build/summarize/apply;
`BackupSelection` in `lib/services/transfer/backup_selection.dart`,
`BackupSummary` and `RestoreReport` in `lib/services/transfer/backup_models.dart`;
and the remote router's derived
maps in `lib/services/remote_control/remote_command_router.dart`. Preserve
category order, raw-string versus JSON encoding, and the tracking-preferences
exceptions to batching and expected profile payloads.

The presentation/restore consumers still need verification:

- `lib/widgets/remote/remote_config_export.dart`
- `lib/widgets/remote/remote_transfer_all.dart`
- `lib/widgets/onboarding/onboarding_flow.dart` (`_configLabel`)
- `lib/services/profiles/profile_restore_coordinator.dart` (`BackupSelection` literals)
- `lib/screens/settings_screen.dart` (settings summary formatters)

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

- Credential persistence uses `lib/services/storage/cloud_secret_prefs.dart`;
  integration, hidden-from-nav and post-torrent policy uses
  `lib/services/storage/provider_credential_prefs.dart`. `CloudCredentials`
  provides the port-facing credential reads.
- Declare each new owned preference key in
  `lib/services/storage/storage_key_ownership.dart` with its actual store.
  `StorageService` retains compatibility facades; it is not a new key owner
  merely because a legacy caller imports it.
- Follow the existing provider getter/setter conventions in those owners.
  Preference **key strings** are a frozen compatibility surface.

## 5. Account status widget

- **New file:** `lib/widgets/<provider>_account_status_widget.dart`
- Reference: `lib/widgets/torbox_account_status_widget.dart`, `lib/widgets/premiumize_account_status_widget.dart`

## 6. Provider settings page (API key entry)

- **New file:** `lib/screens/settings/<provider>_settings_page.dart`
- Reference: `lib/screens/settings/torbox_settings_page.dart`, `lib/screens/settings/premiumize_settings_page.dart`

## 7. Settings screen — Connections card

The host builds page specifications for the existing `SettingsPageRegistry`.

- `lib/screens/settings_screen.dart`: account-service/page wiring, summary
  loading and `buildSettingsPages` inputs; preserve summary ordering and refresh.
- `lib/screens/settings/settings_catalog.dart`: `buildSettingsPages` declares
  the page specifications. `lib/screens/settings/settings_page_registry.dart`
  supplies category metadata and registry-derived search entries; do not
  recreate a second leaf table.
- `lib/screens/settings/settings_tv_layout.dart` and
  `lib/screens/settings/widgets/settings_widgets.dart`: verify TV navigation
  and shared presentation for the added page.

## 8. Default provider picker

- **Edit:** `lib/screens/settings/provider_settings_page.dart`
  (`DefaultProviderDispatch`). Gate on key + integration enabled, add the
  radio `_ProviderOption` (stores playback id e.g. `'premiumize'`).

---

## 9–14. Search, cache badges, Quick Play, bound sources, bulk add, post-torrent

Live search/play paths:

- Play/add/bind: `lib/services/torrent_playback_service.dart` → registry
  (`addMagnet`, `resolveNativeBound`, `queueUncachedMagnet`, …).
- Home/Search UI: `lib/screens/search_screen.dart` (+ `lib/screens/search/`
  parts).
- Cache badges: Home/Sources still call registry cache methods with their
  own key-null gates (`CloudPortFeature.cachedHashes` vs `checkCache`).
- Bulk add: `lib/services/torrent_bulk_add_service.dart`; preserve its typed
  dispatch and chooser order.
- Post-torrent action prefs: per-provider keys on `ProviderCredentialPrefs`;
  helpers live with the search/settings UI.

Implement provider-specific HTTP in `lib/services/<provider>_service.dart`,
then expose it on the adapter. Loading overlay:
`DebridLoadingOverlay.showForPlaybackId`. Bind-source chip colours:
`CloudProviderChrome.sourceChip` (do not reuse playback `gradient`).

## 15–16. Backup / remote

Follow the transfer compatibility checklist above. Do not skip export/transfer-all
tiles or onboarding `_configLabel`. The remote router already uses registry
metadata but retains provider-specific receive handlers. Preserve remote key
validation (unlike file restore); a category declaration does not authorize
changing receiver behavior.

## 17. Debrify TV / Magic TV

`prepareMagicTv` / `prepareMagicTvLockedLinks` on the adapter cover the
registry-owned prepare path. `lib/screens/magic_tv_screen.dart` and the watch
units under `lib/screens/debrify_tv/watch/` retain admission/UI/queue policy.
Use the captured RD/AD interfaces above when the caller already captured its key;
do not collapse quick, cached and locked-link algorithms. Overlay strings:
`lib/services/cloud/magic_tv_provider.dart`.

## 18. Stremio TV

Picker rows: `CloudCredentials.stremioPickerChoices`. Resolve:
`CloudProviderRegistry.resolveStremioTorrent`. Cache filter:
`StremioTvCacheFilter` / `StremioTvTorboxCache`. The screen
(`lib/screens/stremio_tv/stremio_tv_screen.dart`) and
`lib/screens/settings/stremio_tv_settings_page.dart` have distinct UI policy.
Settings picker is RD/TB/PikPak only today.

## 19. Playlists

`CloudPlaylistPayload` + `resolvePlaylistEntry` / `unlockPlaybackEntry` /
`unlockPlayerScreenEntry`. Consumer paths to verify:
`lib/screens/playlist_content_view_screen.dart`,
`lib/services/playlist_player_service.dart`, player/launcher reconstruct
paths. Carry every lazy-resolution field through `_prepareEntries` in
`lib/services/video_player_launcher.dart` or TV/external replay silently drops
refresh.

## 20. Cloud library tab

Public provider screens already route through
`lib/screens/cloud_files/cloud_files_screen.dart` (`CloudFilesScreen`) and the
provider sources under `lib/screens/cloud_files/`. Public wrappers and retained
provider hosts still exist; preserve their constructor/callback contracts:

- `lib/screens/debrid_downloads_screen.dart`
- `lib/screens/torbox/torbox_downloads_screen.dart`
- `lib/screens/pikpak/pikpak_files_screen.dart`
- `lib/screens/premiumize/premiumize_files_screen.dart`
- `lib/screens/alldebrid/alldebrid_files_screen.dart`

`MainTab` **indices** are a frozen compatibility surface. Hide-from-nav flags
are owned by `ProviderCredentialPrefs`. `lib/main.dart` still lists sidebar labels.

## 21. Onboarding

`lib/widgets/initial_setup_flow.dart` re-exports
`lib/widgets/onboarding/onboarding_flow.dart`. Add the chip / controller /
validate path there. `_configLabel` remains a transfer-label consumer.

## 22. Deeplink / share intent

`lib/services/deep_link_service.dart` (`ConfiguredServices`) and
`lib/services/magnet_link_handler.dart`. Magnet “configured” is
`CloudCredentials.isMagnetConfigured`, not playback `isConfigured`.

---

### Quick verify

Replace `<id>` / `<provider>` with the new provider's actual files before running:

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
