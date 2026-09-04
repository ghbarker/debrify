#!/usr/bin/env python3
"""Characterization for tool/qwen_assist.py — availability and argv only."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from qwen_assist import (
    AUTH_ENV_VARS,
    GOD_FILES,
    UNAVAILABLE_EXIT,
    build_argv,
    detect_auth_source,
    find_qwen_cli,
    probe,
)

REPO = Path(__file__).resolve().parent.parent


class ProbeTest(unittest.TestCase):
    def test_missing_cli_is_unavailable_without_leaking_keys(self):
        env = {name: "sk-secret" for name in AUTH_ENV_VARS}
        info = probe(env, home=Path("/tmp/no-qwen-home"), root=REPO, which=None)
        self.assertFalse(info["available"])
        self.assertEqual(info["reason"], "qwen CLI not on PATH or ~/.local/bin")
        self.assertIsNone(info["cli"])
        dumped = str(info)
        self.assertNotIn("sk-secret", dumped)

    def test_cli_without_auth_is_unavailable(self):
        env = {k: v for k, v in os.environ.items() if k not in AUTH_ENV_VARS}
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            info = probe(env, home=home, root=REPO, which="/usr/bin/qwen")
        self.assertFalse(info["available"])
        self.assertEqual(info["reason"], "no Qwen auth in env or ~/.qwen")
        self.assertEqual(info["cli"], "/usr/bin/qwen")
        self.assertIsNone(info["auth"])

    def test_cli_plus_dashscope_key_is_available(self):
        env = {"DASHSCOPE_API_KEY": "sk-not-for-output"}
        info = probe(env, home=Path("/tmp/no-qwen-home"), root=REPO, which="/opt/qwen")
        self.assertTrue(info["available"])
        self.assertEqual(info["auth"], "DASHSCOPE_API_KEY")
        self.assertEqual(info["cli"], "/opt/qwen")
        self.assertEqual(info["mode_default"], "plan")
        self.assertNotIn("sk-not-for-output", str(info))

    def test_settings_json_alone_is_not_auth(self):
        env = {}
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".qwen").mkdir()
            (home / ".qwen" / "settings.json").write_text(
                '{"security":{"auth":{"selectedType":"openai"}}}\n'
            )
            self.assertIsNone(detect_auth_source(env, home=home, root=REPO))
            info = probe(env, home=home, root=REPO, which="/opt/qwen")
        self.assertFalse(info["available"])

    def test_local_bin_qwen_is_found_without_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            bindir = home / ".local" / "bin"
            bindir.mkdir(parents=True)
            cli = bindir / "qwen"
            cli.write_text("#!/bin/sh\nexit 0\n")
            cli.chmod(0o755)
            found = find_qwen_cli(home=home, path="/usr/bin:/bin")
        self.assertEqual(found, str(cli))

    def test_home_env_file_counts_as_auth(self):
        env = {}
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".qwen").mkdir()
            (home / ".qwen" / ".env").write_text("DASHSCOPE_API_KEY=sk-file\n")
            source = detect_auth_source(env, home=home, root=REPO)
            info = probe(env, home=home, root=REPO, which="/opt/qwen")
        self.assertTrue(str(source).endswith(".qwen/.env"))
        self.assertTrue(info["available"])
        self.assertNotIn("sk-file", str(info))


class ArgvTest(unittest.TestCase):
    def test_plan_is_read_only_and_not_yolo(self):
        argv = build_argv("find CloudProviderRegistry", mode="plan", cli="/opt/qwen")
        self.assertEqual(argv[0], "/opt/qwen")
        self.assertIn("--approval-mode", argv)
        self.assertEqual(argv[argv.index("--approval-mode") + 1], "plan")
        self.assertEqual(argv[argv.index("--max-wall-time") + 1], "180")
        self.assertNotIn("--yolo", argv)

    def test_auto_edit_raises_wall_time_and_still_not_yolo(self):
        argv = build_argv("draft a pinning test", mode="auto-edit")
        self.assertEqual(argv[argv.index("--approval-mode") + 1], "auto-edit")
        self.assertEqual(argv[argv.index("--max-wall-time") + 1], "300")
        self.assertNotIn("--yolo", argv)

    def test_empty_prompt_is_rejected(self):
        with self.assertRaises(ValueError):
            build_argv("   ")

    def test_unknown_mode_is_rejected(self):
        with self.assertRaises(ValueError):
            build_argv("x", mode="danger")

    def test_god_file_list_matches_refactor_rules(self):
        self.assertIn("lib/screens/search_screen.dart", GOD_FILES)
        self.assertIn("lib/services/storage_service.dart", GOD_FILES)
        self.assertEqual(len(GOD_FILES), 8)


class ProbeCliTest(unittest.TestCase):
    def test_probe_flag_exits_2_when_unavailable(self):
        env = {k: v for k, v in os.environ.items() if k not in AUTH_ENV_VARS}
        env["PATH"] = "/usr/bin:/bin"
        with tempfile.TemporaryDirectory() as tmp:
            env["HOME"] = tmp
            proc = subprocess.run(
                [sys.executable, str(REPO / "tool" / "qwen_assist.py"), "--probe"],
                cwd=REPO,
                env=env,
                capture_output=True,
                text=True,
            )
        self.assertEqual(proc.returncode, UNAVAILABLE_EXIT)
        self.assertIn('"available": false', proc.stdout)


if __name__ == "__main__":
    unittest.main()
