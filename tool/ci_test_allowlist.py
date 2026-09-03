#!/usr/bin/env python3
"""Run flutter tests and fail only on regressions vs test/BASELINE_ALLOWLIST.txt."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWLIST = ROOT / "test" / "BASELINE_ALLOWLIST.txt"


def load_allowlist() -> set[tuple[str, str]]:
    out: set[tuple[str, str]] = set()
    for raw in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if " :: " not in line:
            raise SystemExit(f"bad allowlist line: {raw!r}")
        path, name = line.split(" :: ", 1)
        out.add((path.strip(), name.strip()))
    return out


def repo_test_path(url: str | None) -> str:
    if not url:
        return ""
    marker = "/test/"
    idx = url.find(marker)
    if idx >= 0:
        return "test/" + url[idx + len(marker) :]
    if url.startswith("file://"):
        url = url[len("file://") :]
    return url


def main() -> int:
    allow = load_allowlist()
    cmd = [
        "flutter",
        "test",
        "test",
        "--exclude-tags",
        "golden",
        "--reporter",
        "json",
    ]
    proc = subprocess.run(
        cmd,
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    sys.stderr.write(proc.stderr)
    tests: dict[int, tuple[str, str]] = {}
    failed: list[tuple[str, str]] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get("type")
        if kind == "testStart":
            test = event.get("test") or {}
            tests[int(test["id"])] = (
                repo_test_path(test.get("url") or test.get("root_url")),
                test.get("name") or "",
            )
        elif kind == "testDone":
            if event.get("hidden") or event.get("skipped"):
                continue
            result = event.get("result")
            if result not in ("failure", "error"):
                continue
            failed.append(tests.get(int(event["testID"]), ("?", "?")))

def is_allowlisted(path: str, name: str, allow: set[tuple[str, str]]) -> bool:
    for allowed_path, allowed_name in allow:
        if name != allowed_name:
            continue
        if path == allowed_path:
            return True
        if path.endswith(allowed_path) or allowed_path.endswith(path):
            return True
        if path.endswith(allowed_path.split("/")[-1]):
            return True
    return False


def main() -> int:

    print(f"Allowlisted failures: {len(failed) - len(unexpected)}/{len(allow)}")
    if unused:
        print("Allowlist entries that did not fail (safe to delete later):")
        for path, name in unused:
            print(f"  {path} :: {name}")
    if unexpected:
        print("NEW failures (not in test/BASELINE_ALLOWLIST.txt):")
        for path, name in unexpected:
            print(f"  {path} :: {name}")
        return 1
    if proc.returncode not in (0, 1):
        print(f"flutter test exited {proc.returncode} without parseable failures")
        return proc.returncode
    print("No new test failures beyond the baseline allowlist.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
