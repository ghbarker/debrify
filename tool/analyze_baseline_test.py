#!/usr/bin/env python3
"""Characterization for tool/analyze_baseline.py matching rules."""

import unittest
from collections import Counter

from analyze_baseline import (
    diagnostic_key,
    diff_counts,
    format_analyze_verdict,
    parse_machine,
    repo_relative,
    split_machine_line,
)


class AnalyzeBaselineTest(unittest.TestCase):
    def test_split_machine_unescapes_pipes(self):
        line = r"INFO|LINT|FOO|/tmp/a\|b.dart|1|2|3|msg \| more"
        parts = split_machine_line(line)
        self.assertEqual(parts[0], "INFO")
        self.assertEqual(parts[3], "/tmp/a|b.dart")
        self.assertEqual(parts[7], "msg | more")

    def test_parse_machine_to_repo_relative_records(self):
        text = (
            "WARNING|STATIC_WARNING|UNUSED_ELEMENT|"
            "/workspace/lib/screens/search_screen.dart|10|1|4|"
            "The declaration '_x' isn't referenced.\n"
        )
        recs = parse_machine(text)
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]["path"], "lib/screens/search_screen.dart")
        self.assertEqual(recs[0]["code"], "UNUSED_ELEMENT")
        self.assertEqual(recs[0]["line"], 10)

    def test_identity_ignores_line_so_a_move_is_not_new(self):
        a = {
            "path": "lib/a.dart",
            "code": "UNUSED_IMPORT",
            "message": "Unused import: 'x.dart'.",
            "line": 1,
        }
        b = dict(a)
        b["line"] = 40
        self.assertEqual(diagnostic_key(a), diagnostic_key(b))

    def test_new_diagnostic_fails_and_unused_does_not_block_shrink(self):
        baseline = Counter({"lib/a.dart|UNUSED_IMPORT|m": 1, "lib/b.dart|DEAD|m": 1})
        current = Counter({"lib/a.dart|UNUSED_IMPORT|m": 1, "lib/c.dart|NEW|m": 1})
        new, unused = diff_counts(baseline, current)
        self.assertEqual(new, ["lib/c.dart|NEW|m"])
        self.assertEqual(unused, ["lib/b.dart|DEAD|m"])

    def test_count_increase_of_same_key_is_new(self):
        baseline = Counter({"lib/a.dart|UNUSED_ELEMENT|The declaration '_x' isn't referenced.": 1})
        current = Counter({"lib/a.dart|UNUSED_ELEMENT|The declaration '_x' isn't referenced.": 2})
        new, unused = diff_counts(baseline, current)
        self.assertEqual(len(new), 1)
        self.assertEqual(unused, [])

    def test_verdict_prints_unused_then_new(self):
        lines = format_analyze_verdict(["lib/n.dart|X|new"], ["lib/o.dart|Y|old"])
        self.assertEqual(lines[0], "REGRESSION LIST (unused baseline + new diagnostics):")
        unused_i = next(i for i, line in enumerate(lines) if line.startswith("UNUSED"))
        new_i = next(i for i, line in enumerate(lines) if line.startswith("NEW"))
        self.assertLess(unused_i, new_i)

    def test_repo_relative_strips_workspace_prefix(self):
        from pathlib import Path

        self.assertEqual(
            repo_relative("/workspace/lib/foo.dart", Path("/workspace")),
            "lib/foo.dart",
        )


if __name__ == "__main__":
    unittest.main()
