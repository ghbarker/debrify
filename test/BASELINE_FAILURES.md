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

CI (`.github/workflows/test.yml`):

- installs `libsqlite3-dev`
- runs the allowlist and analyze-baseline matcher unit tests
- analyzes **all** of `lib/` and `test/` via `tool/analyze_baseline.py`
  (`dart analyze --format=machine`). New diagnostics vs
  `tool/analyze_baseline.json` fail; the JSON may only shrink. Recorded at
  C0 against `main` (470 issues: 0 error, 85 warning, 385 info).
- runs `dart run tool/check_layering.dart` and fails if the count exceeds
  `tool/layering_baseline.txt` (gate i). On pull requests, also dumps
  `--all --json` vs the PR parent and fails on **new** violation ids
  (`tool/ci_layering_delta.py`). Lane Q1 turns `--strict` on after Phase 2.
- runs the refactor contract tests
- runs `flutter test test --exclude-tags golden` through
  `tool/ci_test_allowlist.py` (unused allowlist entries still fail)
- a separate **goldens** job runs `flutter test --tags golden` with retries
  and `[golden]` allowlist lines. Pixel diffs on ubuntu are expected; PNG
  files are not deleted.

That allowlist script fails the job when:

- a test fails whose **exact** `path :: name` is not in
  `test/BASELINE_ALLOWLIST.txt` (or `[golden]` lines for the goldens job), or
- an allowlist entry for that job did not fail (the list cannot silently rot).

Name-only matching is forbidden: a new test that reuses an allowlisted
name is a regression.

The regression list (unused entries + new failures) is printed first.

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
