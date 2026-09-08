# Delivery verification

Base inspected: `843d631b780cf5c04f14e3f3e1070bb914e8e197` (fetched main).
Date: 2026-09-05. Host: Windows; branch: `codex/test-handoff-kit`.
Owned changes: only new files in `dev/testing/handoff/`.

Python executable used:
`C:/Users/hunth/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
In the commands below, `python` denotes that executable.

- `python -B -m unittest discover -s dev/testing/handoff/tests`: **10 passed**.
  Real child processes exercise success, exit 7, raw stdout/stderr, an executable
  and test path containing spaces, unknown suites, missing files/empty folders,
  path escape, SDK mismatch, SDK command exit 9, a missing executable and an actual
  failing Python unittest child. No sleeps or mocked subprocess success.
- Before implementation, the initial eight-test contract suite failed four tests
  because the runner did not exist. Negative rejection tests alone were not used
  as evidence of a working runner.
- Temporary runner-copy mutations: swallowing the child exit was caught by two
  tests; bypassing missing-file validation was caught by three subtests; accepting
  the wrong SDK was caught by one test. Production sources were never mutated.
- `python dev/testing/handoff/run.py --list`: every selected file/folder exists in
  the base checkout, including real keyword State tests. No pending PR paths.
- `python dev/testing/handoff/run.py ci-selftests`: **41 passed**, raw exit 0.
  Runs the existing three CI unittest modules in `tool/`, without baseline edits.
- `python dev/testing/handoff/run.py profile-path --flutter E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat`:
  SDK check accepted **3.44.8**, then Flutter exited **1 before loading tests**:
  `cannot run without a dependency on either "package:flutter_test" or "package:test"`.
  At that initial attempt the worktree had no `.dart_tool/package_config.json`.
  No test assertion ran. The authorized preparation and successful rerun below
  supersede this setup limitation.

## Authorized prepared-worktree verification

Tested commit: `3eec5e0f8c410d3ea820a3f76383ac54bd3286b3`, with production
code/tests unchanged from base `843d631b780cf5c04f14e3f3e1070bb914e8e197`.
Both suites ran through the committed kit runner on Windows, Flutter **3.44.8**.

Preparation: `E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat pub get` exited 0.
Process-only TEMP/TMP=`E:/FlutterSdks/downloads`, PUB_CACHE=`E:/FlutterSdks/pub-cache`,
GRADLE_USER_HOME=`E:/Android/gradle` were used for preparation and both runs.
No SDK installation or gate-workspace writes were performed.

Metadata checks:

- `.dart_tool/package_config.json` resolves `debrify.rootUri` to
  `file:///E:/DebrifyWorktrees/test-handoff-kit/`, this worker's own checkout.
- `flutter` and `flutter_test` resolve under
  `file:///E:/FlutterSdks/flutter-3.44.8/packages/`.
- The resolved `pubspec.lock` is unchanged from HEAD. All 172 dependency versions
  in `.dart_tool/package_graph.json` agree with the committed lockfile (excluding
  the root application, which is not a dependency lock entry).
- Only generated tracked plugin registrant noise from dependency preparation was
  restored to HEAD: the `.cc`, `.h` and `.cmake` files under `linux/flutter/` and
  `windows/flutter/`, plus `macos/Flutter/GeneratedPluginRegistrant.swift`.
  Ignored local package/build metadata remains in this worktree; no root edits
  are included in the verification commit.

Commands and raw outcomes:

```text
python dev/testing/handoff/run.py profile-path --flutter E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat
python dev/testing/handoff/run.py keyword-state --flutter E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat
```

- `profile-path`: **35 passed, 0 failed; exit 0**. Runs
  `test/profile_scope_test.dart` and `test/profiles/profile_scope_test.dart`.
  Actual native Windows path/traversal cases, valid relative representations,
  generation/preference identity and scope behavior executed.
- `keyword-state`: **8 passed, 0 failed; exit 0**. Runs
  `test/keyword_search_origin_widget_test.dart`,
  `test/keyword_search_screen_pin_test.dart`, and
  `test/keyword_search_controller_lib_test.dart`. Real SearchScreen submit/clear,
  imported results and Name-sort reset, extracted screen State notifications and
  actual controller helper tests executed. This run does not establish a separate
  real-State snapshot-restoration pin or historical pre-move execution.

No retries, allowlists, suppressed failures or test/source changes were applied.
These were Flutter test runs only, not duplicate application/platform builds.
Full Flutter, analyzer, Linux/macOS execution and historical parent-tree execution
were not run. The POSIX runner fixture is provided but only Windows was verified.

## Additional bounded runner validation

Tested checkout: `353201953f328afffa8bd83247656962c43a1059` plus the accompanying
README/manifest wording cleanup. Runner behavior, suite selectors and all
production code/tests were unchanged. The same Windows host, pinned Flutter
3.44.8, own-worktree metadata and process environment above were reused. No
additional dependency preparation, gate-workspace writes or application builds.

```text
python dev/testing/handoff/run.py backup-export --flutter E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat
python dev/testing/handoff/run.py profile-lifecycle --flutter E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat
```

- `backup-export`: **67 passed, 0 failed; raw exit 0** across the five existing
  files selected by the manifest. Encryption/package contracts, database snapshot
  behavior, audit privacy, and backup formatting/source guards ran. This does not
  validate a native file picker or an end-to-end device export.
- `profile-lifecycle`: **2 passed, 0 failed; raw exit 0** in
  `test/profiles/profile_lifecycle_test.dart`. Candidate publication ordering and
  roll-forward after post-commit failure ran against the local registry/runtime.
  This is VM service integration, not real device process-death coverage.

No retries, suppression or allowlists were used. The catalog cleanup removes
redundant invariant fields, calls source inspection `inspected_commit`, and
corrects keyword State evidence. Actual execution results remain canonical here.

Next useful slice: profile isolation or cloud provider behavior through the kit
when useful to upstream adoption. Inspect later merged paths and their evidence
before extending bounded selectors; the catalog remains based on the inspected
base rather than tracking moving PR status. Native lifecycle and setting-attribute
synchronization remain coverage discussions, not implementations or coverage claims.
