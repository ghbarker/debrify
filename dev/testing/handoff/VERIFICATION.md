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
  This new worktree has no `.dart_tool/package_config.json`. No test assertion ran.
  This is a setup limitation, not a passing or failing profile behavior result.

The Flutter attempt inherited process-only TEMP/TMP=`E:/FlutterSdks/downloads`,
PUB_CACHE=`E:/FlutterSdks/pub-cache`, GRADLE_USER_HOME=`E:/Android/gradle`.
No SDK install, dependency preparation, app build, gate-workspace write or copied
package metadata was performed. No existing tracked source, root dependency,
workflow, baseline, plan, board or notes were changed. Full Flutter, analyzer,
Linux/macOS execution and historical parent-tree execution were not run.
The POSIX fixture launcher is provided but this host only verified Windows.

Next useful slice: in a prepared checkout, run `profile-path` and `keyword-state`
with the pinned SDK and record raw failures before broadening to `backup-export`.
Main's native-path pins may expose the pending fix; do not silently allowlist it.
After pending changes merge, inspect their new paths and evidence before adding
any bounded selectors. Native lifecycle and setting-attribute synchronization
remain coverage discussions, not implementations or coverage claims in this kit.
