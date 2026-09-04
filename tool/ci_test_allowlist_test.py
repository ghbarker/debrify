#!/usr/bin/env python3
"""Characterization for tool/ci_test_allowlist.py matching rules."""

import unittest

from ci_test_allowlist import (
    is_allowlisted,
    parse_report,
    repo_test_path,
    unused_allowlist,
)


class AllowlistMatchingTest(unittest.TestCase):
    def test_name_only_match_is_not_enough(self):
        allow = {("test/a_test.dart", "same name")}
        self.assertFalse(is_allowlisted("test/b_test.dart", "same name", allow))

    def test_exact_path_and_name_match(self):
        allow = {("test/a_test.dart", "same name")}
        self.assertTrue(is_allowlisted("test/a_test.dart", "same name", allow))

    def test_suffix_path_match_is_not_enough(self):
        allow = {("test/foo_test.dart", "x")}
        self.assertFalse(is_allowlisted("other/test/foo_test.dart", "x", allow))

    def test_unused_allowlist_entries_are_reported(self):
        allow = {("test/a_test.dart", "x"), ("test/b_test.dart", "y")}
        failed = [("test/a_test.dart", "x")]
        self.assertEqual(
            unused_allowlist(allow, failed),
            [("test/b_test.dart", "y")],
        )

    def test_load_allowlist_rejects_name_only_lines(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory

        import ci_test_allowlist as mod

        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "BASELINE_ALLOWLIST.txt"
            path.write_text("orphan name without path\n", encoding="utf-8")
            old = mod.ALLOWLIST
            mod.ALLOWLIST = path
            try:
                with self.assertRaises(SystemExit):
                    mod.load_allowlist()
            finally:
                mod.ALLOWLIST = old

    def test_repo_test_path_strips_to_test_relative(self):
        self.assertEqual(
            repo_test_path("file:///home/runner/work/debrify/debrify/test/widget_test.dart"),
            "test/widget_test.dart",
        )


if __name__ == "__main__":
    unittest.main()
