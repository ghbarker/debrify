#!/usr/bin/env python3
"""Invoke Qwen Code headless when the CLI and auth are available.

Exit codes:
  0  success (probe available, or qwen finished successfully)
  1  usage error, or qwen ran and failed
  2  unavailable — caller should continue without Qwen
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent

AUTH_ENV_VARS: tuple[str, ...] = (
    "BAILIAN_CODING_PLAN_API_KEY",
    "DASHSCOPE_API_KEY",
    "OPENAI_API_KEY",
    "OPENROUTER_API_KEY",
    "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY",
)

GOD_FILES: tuple[str, ...] = (
    "lib/screens/search_screen.dart",
    "lib/screens/settings_screen.dart",
    "lib/services/storage_service.dart",
    "lib/screens/video_player_screen.dart",
    "lib/screens/magic_tv_screen.dart",
    "lib/services/torrent_playback_service.dart",
    "lib/services/remote_control/remote_command_router.dart",
    "lib/services/video_player_launcher.dart",
)

MODES: tuple[str, ...] = ("plan", "auto-edit", "yolo")

DEFAULT_WALL_TIME = {
    "plan": 180,
    "auto-edit": 300,
    "yolo": 300,
}

UNAVAILABLE_EXIT = 2

APPEND_SYSTEM_PROMPT = (
    "Debrify helper run. Grep huge files; never read them end-to-end. "
    "Do not rewrite god files or dart-format them. "
    "Do not rename persisted preference keys, provider ids, backup keys, "
    "ConfigCommand strings, MainTab indices, or Home row ids. "
    "Do not git push, merge, or open PRs. Cursor owns the change."
)


def _auth_file_candidates(home: Path, root: Path) -> tuple[Path, ...]:
    # settings.json may exist without a key (envKey wiring only). .env holds secrets.
    return (
        home / ".qwen" / ".env",
        root / ".qwen" / ".env",
    )


def find_qwen_cli(*, home: Path | None = None, path: str | None = None) -> str | None:
    found = shutil.which("qwen", path=path)
    if found:
        return found
    home = Path.home() if home is None else home
    for directory in (home / ".local" / "bin", Path("/usr/local/bin")):
        candidate = directory / "qwen"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def detect_auth_source(
    env: dict[str, str] | None = None,
    *,
    home: Path | None = None,
    root: Path | None = None,
) -> str | None:
    """Return a non-secret label for the first auth source found."""
    env = os.environ if env is None else env
    for name in AUTH_ENV_VARS:
        if env.get(name):
            return name
    home = Path.home() if home is None else home
    root = REPO_ROOT if root is None else root
    for path in _auth_file_candidates(home, root):
        if path.is_file():
            return str(path)
    return None


def probe(
    env: dict[str, str] | None = None,
    *,
    home: Path | None = None,
    root: Path | None = None,
    which: str | None | object = ...,
) -> dict:
    """Describe whether a headless Qwen run can start. Never includes secrets."""
    env = os.environ if env is None else env
    if which is ...:
        cli = find_qwen_cli(home=home)
    else:
        cli = which
    auth = detect_auth_source(env, home=home, root=root)
    if not cli:
        return {
            "available": False,
            "reason": "qwen CLI not on PATH or ~/.local/bin",
            "cli": None,
            "auth": None,
        }
    if not auth:
        return {
            "available": False,
            "reason": "no Qwen auth in env or ~/.qwen",
            "cli": cli,
            "auth": None,
        }
    return {
        "available": True,
        "reason": None,
        "cli": cli,
        "auth": auth,
        "mode_default": "plan",
    }


def build_argv(
    prompt: str,
    *,
    mode: str = "plan",
    output_format: str = "text",
    max_wall_time: int | None = None,
    cli: str = "qwen",
) -> list[str]:
    if mode not in MODES:
        raise ValueError(f"unknown mode {mode!r}; expected one of {MODES}")
    if not prompt.strip():
        raise ValueError("prompt is empty")
    wall = DEFAULT_WALL_TIME[mode] if max_wall_time is None else max_wall_time
    argv = [
        cli,
        "--prompt",
        prompt,
        "--approval-mode",
        mode,
        "--output-format",
        output_format,
        "--max-wall-time",
        str(wall),
        "--append-system-prompt",
        APPEND_SYSTEM_PROMPT,
    ]
    if mode == "yolo":
        argv.append("--yolo")
    return argv


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Qwen Code headless when available; skip otherwise.",
    )
    parser.add_argument(
        "--probe",
        action="store_true",
        help="Print availability JSON and exit (2 if unavailable).",
    )
    parser.add_argument(
        "--mode",
        choices=MODES,
        default="plan",
        help="Approval mode. Default: plan (read-only).",
    )
    parser.add_argument(
        "--output-format",
        choices=("text", "json"),
        default="text",
    )
    parser.add_argument(
        "--max-wall-time",
        type=int,
        default=None,
        help="Seconds. Defaults: plan 180, auto-edit/yolo 300.",
    )
    parser.add_argument(
        "prompt",
        nargs=argparse.REMAINDER,
        help="Prompt text. Use -- to separate from flags.",
    )
    return parser.parse_args(list(argv) if argv is not None else None)


def _prompt_from_args(ns: argparse.Namespace) -> str:
    parts = list(ns.prompt)
    if parts and parts[0] == "--":
        parts = parts[1:]
    text = " ".join(parts).strip()
    if not text and not sys.stdin.isatty():
        text = sys.stdin.read().strip()
    return text


def main(argv: Iterable[str] | None = None) -> int:
    ns = parse_args(argv)
    info = probe()
    if ns.probe:
        json.dump(info, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0 if info["available"] else UNAVAILABLE_EXIT
    if not info["available"]:
        json.dump(info, sys.stderr, indent=2)
        sys.stderr.write("\n")
        return UNAVAILABLE_EXIT
    if ns.mode == "yolo":
        sys.stderr.write(
            "qwen_assist: --mode yolo requires an explicit user request; "
            "refusing unless QWEN_ASSIST_ALLOW_YOLO=1\n"
        )
        if os.environ.get("QWEN_ASSIST_ALLOW_YOLO") != "1":
            return 1
    prompt = _prompt_from_args(ns)
    try:
        cmd = build_argv(
            prompt,
            mode=ns.mode,
            output_format=ns.output_format,
            max_wall_time=ns.max_wall_time,
            cli=info["cli"] or "qwen",
        )
    except ValueError as exc:
        sys.stderr.write(f"qwen_assist: {exc}\n")
        return 1
    env = os.environ.copy()
    if ns.mode == "yolo":
        env.setdefault("QWEN_CODE_SUPPRESS_YOLO_WARNING", "1")
    result = subprocess.run(cmd, cwd=REPO_ROOT, env=env)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
