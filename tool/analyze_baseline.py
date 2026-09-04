#!/usr/bin/env python3
"""Compare `dart analyze lib test` to tool/analyze_baseline.json.

Generated at main for lane C0. New diagnostics fail the job. The committed
baseline may only shrink: if a diagnostic disappears, print it as unused so
the JSON can be regenerated. Improvements are allowed (exit 0) — unlike the
test allowlist, fixing an analyzer issue is success. Adding to the JSON is
not; that would hide a regression.
"""

from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tool" / "analyze_baseline.json"
ANALYZE_CMD = [
    "dart",
    "analyze",
    "--format=machine",
    "--no-fatal-warnings",
    "lib",
    "test",
]


def split_machine_line(line: str) -> list[str]:
    """Split SEVERITY|TYPE|CODE|PATH|LINE|COLUMN|LENGTH|MESSAGE with escaped pipes."""
    parts: list[str] = []
    buf: list[str] = []
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            buf.append(line[i + 1])
            i += 2
            continue
        if ch == "|":
            parts.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    parts.append("".join(buf))
    return parts


def repo_relative(path: str, root: Path = ROOT) -> str:
    p = Path(path)
    try:
        return p.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        text = path.replace("\\", "/")
        marker = "/lib/"
        idx = text.find(marker)
        if idx >= 0:
            return text[idx + 1 :]
        marker = "/test/"
        idx = text.find(marker)
        if idx >= 0:
            return text[idx + 1 :]
        return text


def parse_machine(text: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("Analyzing") or "|" not in line:
            continue
        parts = split_machine_line(line)
        if len(parts) < 8:
            continue
        severity, typ, code, path, line_s, col_s, length_s, message = parts[:8]
        if severity not in ("ERROR", "WARNING", "INFO", "HINT"):
            continue
        try:
            rec = {
                "severity": severity,
                "type": typ,
                "code": code,
                "path": repo_relative(path),
                "line": int(line_s),
                "column": int(col_s),
                "length": int(length_s),
                "message": message,
            }
        except ValueError:
            continue
        out.append(rec)
    return out


def diagnostic_key(rec: dict[str, Any]) -> str:
    """Stable identity: path + code + message (not line — moves are not new)."""
    return f"{rec['path']}|{rec['code']}|{rec['message']}"


def key_counts(recs: list[dict[str, Any]]) -> Counter[str]:
    return Counter(diagnostic_key(r) for r in recs)


def diff_counts(
    baseline: Counter[str], current: Counter[str]
) -> tuple[list[str], list[str]]:
    """Return (new_keys_expanded, unused_keys_expanded)."""
    new: list[str] = []
    unused: list[str] = []
    for key, n in sorted(current.items()):
        extra = n - baseline.get(key, 0)
        new.extend([key] * extra)
    for key, n in sorted(baseline.items()):
        extra = n - current.get(key, 0)
        unused.extend([key] * extra)
    return new, unused


def format_analyze_verdict(new: list[str], unused: list[str]) -> list[str]:
    lines: list[str] = []
    if new or unused:
        lines.append("REGRESSION LIST (unused baseline + new diagnostics):")
    if unused:
        lines.append("UNUSED analyze baseline entries (fixed; baseline may shrink):")
        lines.extend(f"  {k}" for k in unused)
    if new:
        lines.append("NEW diagnostics (not in tool/analyze_baseline.json):")
        lines.extend(f"  {k}" for k in new)
    return lines


def load_baseline(path: Path = BASELINE) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    recs = data.get("diagnostics")
    if not isinstance(recs, list):
        raise SystemExit("analyze baseline missing diagnostics list")
    return recs


def record_payload(recs: list[dict[str, Any]], commit: str) -> dict[str, Any]:
    return {
        "commit": commit,
        "command": ANALYZE_CMD,
        "identity": "path|code|message",
        "count": len(recs),
        "diagnostics": recs,
    }


def run_analyze() -> list[dict[str, Any]]:
    proc = subprocess.run(
        ANALYZE_CMD,
        cwd=ROOT,
        check=False,
        text=True,
        capture_output=True,
    )
    text = proc.stdout or ""
    if proc.returncode not in (0, 1, 2, 3):
        print(proc.stderr or proc.stdout, file=sys.stderr)
        raise SystemExit(proc.returncode or 1)
    recs = parse_machine(text)
    if not recs and proc.returncode not in (0,):
        print(proc.stderr or text, file=sys.stderr)
        raise SystemExit(proc.returncode)
    return recs


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if "--record" in args:
        recs = run_analyze()
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip()
        BASELINE.write_text(
            json.dumps(record_payload(recs, commit), indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"recorded {len(recs)} diagnostics -> {BASELINE.relative_to(ROOT)}")
        return 0

    recs = run_analyze()
    baseline = load_baseline()
    new, unused = diff_counts(key_counts(baseline), key_counts(recs))
    verdict = format_analyze_verdict(new, unused)
    for line in verdict:
        print(line)
    print(
        f"Analyzer diagnostics: {len(recs)} current / {len(baseline)} baseline "
        f"({sum(1 for r in recs if r['severity']=='ERROR')} error, "
        f"{sum(1 for r in recs if r['severity']=='WARNING')} warning, "
        f"{sum(1 for r in recs if r['severity']=='INFO')} info)"
    )
    if new:
        print(
            "New analyzer diagnostics vs tool/analyze_baseline.json. "
            "Do not grow the baseline; fix the issue or stop."
        )
        return 1
    if unused:
        print(
            "Baseline has unused entries (issues went away). Allowed — "
            "regenerate with python3 tool/analyze_baseline.py --record to shrink."
        )
    print("No new analyzer diagnostics beyond the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
