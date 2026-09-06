# Existing-test handoff kit

Keep tests beside the code in this repository. This catalog points to their real
paths; it contains no copied Dart tests, baselines or app dependencies. Adopt one
suite locally first. Upstream CI does not need to change.

## Start

Use Python 3.9+ (standard library only), Git, and **Flutter 3.44.8 stable**, the pin
in `.github/workflows/test.yml`. Put that SDK's `bin` on PATH; on Windows use
`python` (or your Python executable), and on Unix use `python3` if needed.

From a clone of `ghbarker/debrify`, prepare dependencies once using that SDK:

```text
flutter --version
flutter pub get
python dev/testing/handoff/run.py --list
python dev/testing/handoff/run.py profile-path --dry-run
python dev/testing/handoff/run.py profile-path
python dev/testing/handoff/run.py keyword-state
python dev/testing/handoff/run.py ci-selftests
python dev/testing/handoff/run.py full
```

For an SDK path containing spaces, quote the whole executable argument:

```text
python dev/testing/handoff/run.py cloud-core --flutter "E:/FlutterSdks/flutter-3.44.8/bin/flutter.bat"
python -B -m unittest discover -s dev/testing/handoff/tests
```

The runner resolves the repository from its own location, so it also works from
another working directory. `--root` and `--manifest` are for isolated fixtures or
an intentional alternate checkout. `--flutter` accepts one executable, not shell
commands. It checks the SDK version before Flutter tests and uses `--no-pub` so
it never installs dependencies implicitly. Flutter itself creates ordinary build
outputs; prepare a normal development checkout before running. Linux CI installs
`libsqlite3-dev` and `libsqlite3-0`; database suites need a working native SQLite
runtime on the host. These are VM/widget tests, not Android/tvOS device tests.

Set TEMP, TMP, PUB_CACHE and GRADLE_USER_HOME in the current process if desired;
the kit inherits them and never changes global settings. Do not share a writable
build directory between simultaneous workers. No Gradle build is part of this kit.

## What runs

`suites.json` is the catalog: purpose, owning module, selectors, command,
evidence limitations, failure triage and last inspected commit. `--list` verifies
all selectors. `--dry-run` prints the resolved file inventory and command argument
array without claiming execution. A folder selector discovers `*_test.dart`
recursively; a narrow suite uses explicit files to avoid unrelated growth. Full
uses `test/`, so adding a normal Flutter test does not require catalog maintenance.
The Flutter command receives the folder, avoiding Windows command-length limits.

Start with `profile-path`, `profile-lifecycle`, `cloud-core`, `cloud-provider`,
`keyword-state`, or `backup-export`. `profile-isolation` reuses its existing folder.
`keyword-source` is deliberately separate from functional State pins.

Results are **raw pass/fail**: child output is inherited, nonzero status is
propagated, missing files/empty folders/unknown suites are errors, and there are
no implicit retries, exclusions or allowlists. Version/setup failures are failures,
not skipped tests. Full includes goldens and can fail on platform raster differences.
The printed inventory describes selected test files, not a promise that every
case inside them executes (existing test-level skips still belong to those files).
A successful dry run is not a successful test run.

## Evidence boundaries

- Behavioral tests execute assertions against production code; a `behavioral-model`
  label means examples implemented inside the test, weaker evidence of the app.
- Widget tests drive Flutter widget/State behavior. `keyword-state` includes real
  `SearchScreen` submit/clear, imported results and Name-sort reset, the extracted
  widget's controller notifications, and actual controller helpers. It does not
  establish a separate real-State snapshot-restoration pin.
- Integration here means multiple services or local SQLite on the Dart VM. It
  does not mean a real device, live provider account, native preference reader,
  OS file picker or process-death exercise.
- Source guards inspect text. `keyword_search_pin_test.dart` also reproduces
  helpers locally; neither proves real State behavior. `backup_restore_page_test`
  tests formatting helpers plus source contracts, despite its page name.
- Golden tests compare rendered pixels. They are included by `full`; use the
  existing `flutter test --tags golden` directly for a golden-only run.

Original-path evidence and test authorship are separate. The keyword
`origin_widget` follow-up states it ran unchanged on the pre-move commit
`ee33b3cba678ab914ed242e484cc9e5aed15e3c0` and main, but it was authored after the
move. The extracted-screen widget pin is also retrospective and depends on moved
classes. This kit records those source statements, not an independent historical
rerun or proof that a test was committed before extraction. For new regression
work, retain the failing reproduction, fix, exact tested commit, platform and
mutation result in its review. Do not relabel a text guard as functional coverage.

Each suite's `inspected_commit` identifies source/path inspection only. The
catalog uses paths from that fetched-main base; it does not track subsequent
merges or changing PR status. `VERIFICATION.md` is the canonical record of actual
run results and tested commits, including profile-path results. No pass/fail
results are stored in the manifest. New setting/attribute auto-sync coverage remains
a discussion-only gap: this kit neither implements a policy nor claims automatic
coverage when a field is added.

## Add a test or adopt incrementally

1. Add the test to the existing owning `test/` directory with a descriptive
   `*_test.dart` name. Reuse production seams/fixtures; do not duplicate logic here.
2. Run it directly with pinned Flutter. Demonstrate that the regression or a
   targeted mutation makes it fail, then that the intended code passes.
3. Folder suites pick it up automatically. Add an explicit path to a bounded
   suite only when it shares that suite's purpose; update classification and
   evidence if needed. Verify `--list` and `--dry-run`, then run the suite.
4. In review record the tested commit, command, environment and result. Update
   `inspected_commit` only after inspecting the selected paths at that commit;
   keep actual run results and tested commits in `VERIFICATION.md`.

Use the smallest relevant suite during work, broader existing tests before merge,
and CI's own workflow as the integration gate. Optional later CI adoption can run
this kit's Python self-tests or one suite; no workflow rewrite is required.

## Existing CI modes (explicit, different semantics)

These commands are documentation, not hidden runner steps:

```text
python tool/analyze_baseline.py
python tool/ci_test_allowlist.py
python tool/ci_test_allowlist.py --tags golden --retries 2
```

The analyzer uses its existing diagnostic baseline. App CI uses the existing
exact test allowlist with unused-entry checks; the golden job uses tagged entries
and retries. A green baseline comparison can include raw failures. See the tools
and `.github/workflows/test.yml` for authoritative matching semantics. Layering CI
also compares the parent checkout: a local suite pass cannot substitute for that
delta check. Never copy baselines into this kit or silently absorb known failures.

See `VERIFICATION.md` for this delivery's actual checks and limitations.
