#!/usr/bin/env python3
"""Characterization for tool/ci_test_allowlist.py matching rules."""

import unittest

from ci_test_allowlist import (
    evaluate_failures,
    format_allowlist_verdict,
    flutter_test_command,
    is_allowlisted,
    load_allowlist,
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

    def test_unused_and_new_failures_are_both_reported(self):
        unused = [("test/a_test.dart", "gone")]
        unexpected = [("test/b_test.dart", "new")]
        lines = format_allowlist_verdict(unused, unexpected)
        joined = "\n".join(lines)
        self.assertIn("UNUSED allowlist entries", joined)
        self.assertIn("test/a_test.dart :: gone", joined)
        self.assertIn("NEW failures", joined)
        self.assertIn("test/b_test.dart :: new", joined)

    def test_verdict_prints_regression_list_before_detail_headers(self):
        lines = format_allowlist_verdict(
            [("test/a_test.dart", "gone")],
            [("test/b_test.dart", "new")],
        )
        self.assertEqual(lines[0], "REGRESSION LIST (unused allowlist + new failures):")
        unused_i = next(i for i, line in enumerate(lines) if line.startswith("UNUSED"))
        new_i = next(i for i, line in enumerate(lines) if line.startswith("NEW"))
        self.assertLess(unused_i, new_i)

    def test_evaluate_failures_keeps_unused_and_new_together(self):
        allow = {("test/a_test.dart", "old"), ("test/stale_test.dart", "gone")}
        failed = [("test/a_test.dart", "old"), ("test/b_test.dart", "new")]
        unexpected, matched, unused = evaluate_failures(failed, allow)
        self.assertEqual(unexpected, [("test/b_test.dart", "new")])
        self.assertEqual(matched, [("test/a_test.dart", "old")])
        self.assertEqual(unused, [("test/stale_test.dart", "gone")])

    def test_load_allowlist_default_skips_golden_marker_lines(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory

        import ci_test_allowlist as mod

        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "BASELINE_ALLOWLIST.txt"
            path.write_text(
                "test/a_test.dart :: unit fail\n"
                "[golden] test/theme/goldens_test.dart :: pixels\n",
                encoding="utf-8",
            )
            old = mod.ALLOWLIST
            mod.ALLOWLIST = path
            try:
                self.assertEqual(
                    load_allowlist("default"),
                    {("test/a_test.dart", "unit fail")},
                )
                self.assertEqual(
                    load_allowlist("golden"),
                    {("test/theme/goldens_test.dart", "pixels")},
                )
            finally:
                mod.ALLOWLIST = old

    def test_flutter_test_command_excludes_goldens_by_default(self):
        from pathlib import Path

        cmd = flutter_test_command(golden=False, report=Path("/tmp/r.json"))
        self.assertIn("--exclude-tags", cmd)
        self.assertIn("golden", cmd)
        self.assertNotIn("--tags", cmd)

    def test_flutter_test_command_runs_golden_tag_without_excluding_it(self):
        from pathlib import Path

        cmd = flutter_test_command(golden=True, report=Path("/tmp/r.json"))
        self.assertIn("--tags", cmd)
        self.assertIn("golden", cmd)
        self.assertNotIn("--exclude-tags", cmd)

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
