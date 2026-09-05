#!/usr/bin/env python3
"""Characterization for tool/analyze_baseline.py matching rules."""

import unittest
import io
import subprocess
import tempfile
from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
from collections import Counter
from unittest.mock import patch

import analyze_baseline

from analyze_baseline import (
    diagnostic_key,
    diff_counts,
    format_analyze_verdict,
    parse_machine,
    repo_relative,
    split_machine_line,
)


class AnalyzeBaselineTest(unittest.TestCase):
    machine = ('WARNING|STATIC_WARNING|UNUSED_ELEMENT|'
               '/workspace/lib/a.dart|1|2|3|Unused element.\n')

    def setUp(self):
        # Process-result tests do not depend on an installed Flutter SDK.
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        native = Path(directory.name) / 'dart.exe'
        native.touch()
        lookup = patch('shutil.which', return_value=str(native))
        lookup.start()
        self.addCleanup(lookup.stop)

    def run_result(self, code, stdout='', stderr=''):
        return patch('analyze_baseline.subprocess.run', return_value=
                     subprocess.CompletedProcess([], code, stdout, stderr))

    def test_run_analyze_parses_diagnostics_for_supported_exit_codes(self):
        for code in (0, 1, 2, 3):
            with self.subTest(code=code), self.run_result(code, self.machine):
                self.assertEqual(analyze_baseline.run_analyze()[0]['code'],
                                 'UNUSED_ELEMENT')

    def test_run_analyze_empty_success(self):
        with self.run_result(0):
            self.assertEqual(analyze_baseline.run_analyze(), [])

    def test_run_analyze_failed_process_cannot_look_clean(self):
        for code, stdout in ((1, ''), (2, 'invalid options'),
                             (3, 'malformed|output'), (9, self.machine)):
            errors = io.StringIO()
            with self.subTest(code=code), self.run_result(code, stdout, 'failed'), \
                    redirect_stderr(errors), self.assertRaises(SystemExit) as raised:
                analyze_baseline.run_analyze()
            self.assertEqual(raised.exception.code, code)
            self.assertIn('failed', errors.getvalue())

    def test_main_rejects_duplicate_occurrence_and_allows_shrink(self):
        record = parse_machine(self.machine)[0]
        for current, expected in (([record, record], 1), ([], 0)):
            with self.subTest(current=current), patch(
                    'analyze_baseline.run_analyze', return_value=current), patch(
                    'analyze_baseline.load_baseline', return_value=[record]), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(analyze_baseline.main([]), expected)

    def test_windows_launch_uses_native_sdk_with_spaces_without_shell(self):
        with tempfile.TemporaryDirectory(prefix='flutter sdk ') as directory:
            bin_dir = Path(directory) / 'bin'
            native = bin_dir / 'cache/dart-sdk/bin/dart.exe'
            native.parent.mkdir(parents=True)
            native.touch()
            for shim in ('dart.bat', 'flutter.bat'):
                with self.subTest(shim=shim), patch(
                        'analyze_baseline.sys.platform', 'win32'), patch(
                        'shutil.which', side_effect=lambda name:
                        str(bin_dir / shim) if name == shim.split('.')[0] else None), \
                        self.run_result(0, self.machine) as run:
                    self.assertEqual(len(analyze_baseline.run_analyze()), 1)
                    run.assert_called_once_with(
                        [str(native), 'analyze', '--format=machine',
                         '--no-fatal-warnings', 'lib', 'test'],
                        cwd=analyze_baseline.ROOT, check=False, text=True,
                        capture_output=True, encoding='utf-8', shell=False)

    def test_windows_native_dart_on_path_is_used_directly(self):
        with tempfile.TemporaryDirectory() as directory:
            native = Path(directory) / 'dart.exe'
            native.touch()
            with patch('analyze_baseline.sys.platform', 'win32'), patch(
                    'shutil.which', return_value=str(native)), \
                    self.run_result(0) as run:
                analyze_baseline.run_analyze()
                self.assertEqual(run.call_args.args[0][0], str(native))

    def test_missing_windows_sdk_fails_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            shim = Path(directory) / 'dart.bat'
            shim.touch()
            for found in (None, str(shim)):
                with self.subTest(found=found), patch(
                        'analyze_baseline.sys.platform', 'win32'), patch(
                        'shutil.which', return_value=found), \
                        self.run_result(0) as run, self.assertRaises(SystemExit) as raised:
                    analyze_baseline.run_analyze()
                run.assert_not_called()
                self.assertIn('native Dart SDK', str(raised.exception))

    def test_posix_command_retains_both_analysis_roots(self):
        with patch('analyze_baseline.sys.platform', 'linux'), self.run_result(0) as run:
            analyze_baseline.run_analyze()
        self.assertEqual(run.call_args.args[0], analyze_baseline.ANALYZE_CMD)

    def test_os_launch_failure_has_actionable_error(self):
        with patch('analyze_baseline.subprocess.run', side_effect=OSError('denied')), \
                redirect_stderr(io.StringIO()) as errors, \
                self.assertRaises(SystemExit) as raised:
            analyze_baseline.run_analyze()
        self.assertEqual(raised.exception.code, 2)
        self.assertIn('Could not launch Dart analyzer', errors.getvalue())
        self.assertIn('denied', errors.getvalue())

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
