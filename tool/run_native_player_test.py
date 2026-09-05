#!/usr/bin/env python3
"""Required origin/current native proof; generic suites exclude its native tag."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

import ci_test_allowlist as allowlist

ORIGIN = "bc46babab2e1f1b367c3e5d89505dee1d0b64b93"
TEST = Path("test/native/video_player_origin_behavior_test.dart")
CASE = "retrospective origin: host cancel and disposal checkpoint"


def generic_command(*, golden: bool, report: Path) -> list[str]:
    command = ["flutter", "test", "test", "--exclude-tags",
               "native" if golden else "golden || native"]
    if golden:
        command += ["--tags", "golden"]
    return command + ["--reporter", "compact", "--file-reporter", f"json:{report}"]


def native_command(sdk: Path, report: Path) -> list[str]:
    # Native Dart avoids Windows .bat shell quoting, including paths with spaces.
    dart = sdk / "bin/cache/dart-sdk/bin" / ("dart.exe" if os.name == "nt" else "dart")
    snapshot = sdk / "bin/cache/flutter_tools.snapshot"
    for path in (dart, snapshot):
        if not path.is_file():
            raise ValueError(f"Missing Flutter runtime: {path}")
    return [str(dart), str(snapshot), "test", str(TEST), "--no-pub",
            "--tags", "native", "--reporter", "expanded",
            "--file-reporter", f"json:{report}"]


def validate_report(text: str, returncode: int) -> None:
    if returncode != 0:
        raise ValueError(f"Native test process exited {returncode}")
    events = [json.loads(line) for line in text.splitlines() if line.strip()]
    if not events or events[-1].get("type") != "done" or events[-1].get("success") is not True:
        raise ValueError("Native report missing successful terminal event")
    tests = {}
    passed = []
    for event in events:
        kind = event.get("type")
        if kind == "error":
            raise ValueError("Native report contains an error")
        if kind == "testStart":
            test = event["test"]
            tests[test["id"]] = test["name"]
            if test.get("metadata", {}).get("skip"):
                raise ValueError("Native test metadata requests a skip")
        if kind == "testDone":
            if event.get("skipped") or event.get("result") != "success":
                raise ValueError("Native test skipped or failed")
            if not event.get("hidden"):
                passed.append(tests.get(event["testID"]))
    if passed != [CASE]:
        raise ValueError(f"Expected exactly the native behavioral case, got {passed!r}")


def git(root: Path, ref: str) -> str:
    return subprocess.check_output(["git", "rev-parse", ref], cwd=root, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_pair(current: Path, origin: Path, sdk: Path, library: Path, output: Path) -> int:
    if not library.is_file():
        raise ValueError(f"Missing native library: {library}")
    version = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
    if version.get("frameworkVersion") != "3.44.8":
        raise ValueError("Native gate requires Flutter 3.44.8")
    if git(origin, "HEAD") != ORIGIN:
        raise ValueError("Native origin checkout does not match the pinned origin")
    if (current / TEST).read_bytes() != (origin / TEST).read_bytes():
        raise ValueError("Origin/current native test bytes differ")
    output.mkdir(parents=True, exist_ok=True)
    evidence = {"flutter": version, "library": str(library), "library_sha256": sha(library),
                "test_sha256": sha(current / TEST), "runs": {}}
    failed = False
    for label, root in (("origin", origin), ("current", current)):
        report = output / f"{label}.jsonl"
        # A previous report must never stand in for this invocation.
        report.unlink(missing_ok=True)
        record = {"head": git(root, "HEAD"), "tree": git(root, "HEAD^{tree}")}
        evidence["runs"][label] = record
        command = native_command(sdk, report)
        record["command"] = command
        env = dict(os.environ, LIBMPV_LIBRARY_PATH=str(library))
        try:
            with (output / f"{label}.log").open("w", encoding="utf-8") as log:
                proc = subprocess.run(command, cwd=root, env=env, stdout=log,
                                      stderr=subprocess.STDOUT, timeout=600, check=False)
            record["exit"] = proc.returncode
            validate_report(report.read_text(encoding="utf-8"), proc.returncode)
            record["verdict"] = "passed"
        except (ValueError, OSError, subprocess.TimeoutExpired) as error:
            record["verdict"] = str(error)
            failed = True
        print(f"{label}: {record['verdict']}", flush=True)
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    return int(failed)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] == "generic":
        # Delegate the entire existing execution/retry/verdict path unchanged.
        # Only command tag selection differs; this module owns no allowlist.
        with patch.object(allowlist, "flutter_test_command", generic_command):
            return allowlist.main(args[1:])
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("current", "origin", "flutter-root", "library", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    options = parser.parse_args(args)
    try:
        return run_pair(options.current.resolve(), options.origin.resolve(),
                        options.flutter_root.resolve(), options.library.resolve(), options.output.resolve())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Native gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
