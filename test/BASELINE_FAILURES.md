# Baseline flutter test failures

Measured 2026-09-03 on Linux (`flutter test test --reporter compact`) with
Flutter 3.44.8 **before** `libsqlite3` was installed: 3689 passed / 500 failed.
Those failures were `libsqlite3.so` missing (`IptvCatalogDb` / profile sqlite),
not the cloud port.

After `apt-get install libsqlite3-dev`, previously failing `test/iptv_catalog_db_test.dart`
and `test/backup_encryption_test.dart` pass. CI installs the same library.

The PIN recovery-dialog test in `self_profile_settings_page_test.dart`
polls for the dialog (same pattern as identity save) because a fixed
settle loses under a busy GitHub ubuntu shard.

**New failures outside sqlite/golden environment issues are regressions.**

CI (`.github/workflows/test.yml`) installs `libsqlite3-dev`, runs the
allowlist matcher unit tests, the refactor contract tests, then
`flutter test test --exclude-tags golden` through `tool/ci_test_allowlist.py`.

That script fails the job when:

- a test fails whose **exact** `path :: name` is not in
  `test/BASELINE_ALLOWLIST.txt`, or
- an allowlist entry did not fail (the list cannot silently rot).

Name-only matching is forbidden: a new test that reuses an allowlisted
name is a regression.

Pixel goldens stay tagged `golden` because GitHub ubuntu rasterizes fonts
differently than the checked-in PNGs. Run them locally with
`flutter test test --tags golden`. `flutter analyze` is scoped to
`lib/services/cloud` plus chrome/browse widgets and the contract tests —
god files still carry pre-existing infos. The analyzer step is the
refactor surface, not the whole app.

Reproduced (not assumed) on 2026-09-04, Linux Flutter 3.44.8:

- `profile_source_guard_test` "Debrify TV access…" failed because
  `iptv_media_store` writes through `runScoped`; the guard now allows that
  path and is **not** allowlisted.
- `widget_test` smoke test failed on a leftover 4s init timer; the test
  now pumps that duration and is **not** allowlisted.

The safety-net slice itself is gated by:

```
flutter test test/adversarial test/cloud_playback_characterization_test.dart test/download_cloud_credential_key_test.dart
```

Those files passed 32/32 on this machine without sqlite.
