#!/usr/bin/env python3
"""Run flutter tests and fail only on regressions vs test/BASELINE_ALLOWLIST.txt."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWLIST = ROOT / "test" / "BASELINE_ALLOWLIST.txt"
REPORT = ROOT / "build" / "ci_test_report.json"
GOLDEN_MARKER = "[golden]"


def load_allowlist(kind: str = "default") -> set[tuple[str, str]]:
    """Load exact path :: name pairs.

    ``kind="default"`` skips ``[golden]`` lines (used by the non-golden suite).
    ``kind="golden"`` loads only ``[golden]`` lines (Linux pixel-tolerance job).
    """
    if kind not in ("default", "golden"):
        raise SystemExit(f"bad allowlist kind: {kind!r}")
    out: set[tuple[str, str]] = set()
    for raw in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        is_golden = False
        if line.startswith(GOLDEN_MARKER):
            is_golden = True
            line = line[len(GOLDEN_MARKER) :].strip()
        if kind == "golden" and not is_golden:
            continue
        if kind == "default" and is_golden:
            continue
        if " :: " not in line:
            raise SystemExit(f"bad allowlist line: {raw!r}")
        path, name = line.split(" :: ", 1)
        out.add((path.strip(), name.strip()))
    return out


def _test_file_url(test: dict) -> str:
    """Widget tests report url as flutter_test's matcher file; prefer /test/."""
    candidates = [test.get("root_url"), test.get("url"), test.get("suite_url")]
    for url in candidates:
        if isinstance(url, str) and "/test/" in url.replace("\\", "/"):
            return url
    for url in candidates:
        if isinstance(url, str) and url:
            return url
    return ""


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


def is_allowlisted(path: str, name: str, allow: set[tuple[str, str]]) -> bool:
    """Exact path + name only. A matching name in another file is a NEW failure."""
    return (path, name) in allow


def unused_allowlist(
    allow: set[tuple[str, str]], failed: list[tuple[str, str]]
) -> list[tuple[str, str]]:
    return sorted(allow - set(failed))


def format_allowlist_verdict(
    unused: list[tuple[str, str]], unexpected: list[tuple[str, str]]
) -> list[str]:
    """Report unused entries and new failures together; caller decides exit.

    The regression list is always unused-then-new so a shrinking allowlist and
    a new failure are equally loud and appear before any summary counts.
    """
    lines: list[str] = []
    if unused or unexpected:
        lines.append("REGRESSION LIST (unused allowlist + new failures):")
    if unused:
        lines.append("UNUSED allowlist entries (must still fail, or delete them):")
        lines.extend(f"  {path} :: {name}" for path, name in unused)
    if unexpected:
        lines.append("NEW failures (not in test/BASELINE_ALLOWLIST.txt):")
        lines.extend(f"  {path} :: {name}" for path, name in unexpected)
    return lines


def parse_report(text: str) -> list[tuple[str, str]]:
    tests: dict[int, tuple[str, str]] = {}
    failed: list[tuple[str, str]] = []
    for line in text.splitlines():
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
                repo_test_path(_test_file_url(test)),
                test.get("name") or "",
            )
        elif kind == "testDone":
            if event.get("hidden") or event.get("skipped"):
                continue
            if event.get("result") not in ("failure", "error"):
                continue
            failed.append(tests.get(int(event["testID"]), ("?", "?")))
    return failed


def flutter_test_command(*, golden: bool, report: Path) -> list[str]:
    cmd = [
        "flutter",
        "test",
        "test",
        "--reporter",
        "compact",
        "--file-reporter",
        f"json:{report}",
    ]
    if golden:
        cmd[3:3] = ["--tags", "golden"]
    else:
        cmd[3:3] = ["--exclude-tags", "golden"]
    return cmd


def run_flutter_test(cmd: list[str], retries: int) -> subprocess.CompletedProcess[bytes]:
    """Run flutter test; retry the whole command on failure (Linux goldens flake)."""
    proc = subprocess.run(cmd, cwd=ROOT, check=False)
    attempt = 0
    while proc.returncode not in (0,) and attempt < retries:
        attempt += 1
        print(f"flutter test exited {proc.returncode}; retry {attempt}/{retries}")
        proc = subprocess.run(cmd, cwd=ROOT, check=False)
    return proc


def evaluate_failures(
    failed: list[tuple[str, str]], allow: set[tuple[str, str]]
) -> tuple[list[tuple[str, str]], list[tuple[str, str]], list[tuple[str, str]]]:
    unexpected = [item for item in failed if not is_allowlisted(*item, allow)]
    matched = [item for item in failed if is_allowlisted(*item, allow)]
    unused = unused_allowlist(allow, failed)
    return unexpected, matched, unused


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    golden = "--tags" in args and "golden" in args
    retries = 0
    if "--retries" in args:
        i = args.index("--retries")
        retries = int(args[i + 1])
    kind = "golden" if golden else "default"
    allow = load_allowlist(kind)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    cmd = flutter_test_command(golden=golden, report=REPORT)
    proc = run_flutter_test(cmd, retries)
    if not REPORT.is_file():
        print(f"missing JSON report at {REPORT}", file=sys.stderr)
        return proc.returncode or 1

    failed = parse_report(REPORT.read_text(encoding="utf-8"))
    unexpected, matched, unused = evaluate_failures(failed, allow)

    verdict = format_allowlist_verdict(unused, unexpected)
    for line in verdict:
        print(line)
    print(f"Allowlisted failures: {len(matched)}/{len(allow)}")
    if unused or unexpected:
        return 1
    if proc.returncode not in (0, 1):
        print(f"flutter test exited {proc.returncode}")
        return proc.returncode
    print("No new test failures beyond the baseline allowlist.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
