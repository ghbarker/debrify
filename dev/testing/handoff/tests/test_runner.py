import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[1] / 'run.py'


class RunnerContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='handoff space ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'test').mkdir()
        (self.root / 'test' / 'one test_test.dart').write_text('// fixture')
        self.record = self.root / 'child.json'
        fixture = self.root / 'fake flutter.py'
        fixture.write_text('''import json, os, pathlib, sys
if '--version' in sys.argv:
    print(json.dumps({'frameworkVersion': os.environ.get('FAKE_VERSION', '3.44.8')}))
    sys.exit(int(os.environ.get('VERSION_EXIT', '0')))
else:
    pathlib.Path(os.environ['CHILD_RECORD']).write_text(json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd()}))
    print('raw child stdout')
    print('raw child stderr', file=sys.stderr)
    sys.exit(int(os.environ.get('CHILD_EXIT', '0')))
''')
        self.flutter = self.root / ('flutter.bat' if os.name == 'nt' else 'flutter')
        if os.name == 'nt':
            self.flutter.write_text(f'@echo off\n"{sys.executable}" "{fixture}" %*\nexit /b %errorlevel%\n')
        else:
            import shlex
            self.flutter.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(fixture)) + ' "$@"\n')
            self.flutter.chmod(0o755)
        self.manifest = self.root / 'suites.json'
        self.data = {'flutter_version': '3.44.8', 'suites': {'small': {
            'engine': 'flutter', 'cwd': '.', 'selectors': ['test/one test_test.dart']}}}
        self.env = dict(os.environ, CHILD_RECORD=str(self.record), PYTHONDONTWRITEBYTECODE='1')

    def run_kit(self, *args):
        self.manifest.write_text(json.dumps(self.data))
        return subprocess.run([sys.executable, str(RUNNER), '--root', str(self.root),
            '--manifest', str(self.manifest), '--flutter', str(self.flutter), *args],
            cwd=self.root.parent, env=self.env, text=True, capture_output=True)

    def test_child_failure_and_streams_survive_spaces(self):
        self.env['CHILD_EXIT'] = '7'
        result = self.run_kit('small')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn('raw child stdout', result.stdout)
        self.assertIn('raw child stderr', result.stderr)
        record = json.loads(self.record.read_text())
        self.assertEqual(Path(record['cwd']), self.root)
        self.assertIn('test/one test_test.dart', record['args'])
        self.assertIn('--no-pub', record['args'])

    def test_success_executes_child(self):
        result = self.run_kit('small')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.record.exists())

    def test_bad_selection_never_executes_child(self):
        for selector in ('test/missing_test.dart', 'test/empty', '../escape_test.dart'):
            with self.subTest(selector=selector):
                self.data['suites']['small']['selectors'] = [selector]
                result = self.run_kit('small')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.record.exists())

    def test_unknown_suite_never_executes_child(self):
        self.assertNotEqual(self.run_kit('typo').returncode, 0)
        self.assertFalse(self.record.exists())

    def test_version_command_failure_is_propagated(self):
        self.env['VERSION_EXIT'] = '9'
        self.assertEqual(self.run_kit('small').returncode, 9)
        self.assertFalse(self.record.exists())

    def test_missing_executable_is_error(self):
        self.flutter = self.root / 'not installed'
        self.assertEqual(self.run_kit('small').returncode, 2)
        self.assertFalse(self.record.exists())

    def test_wrong_sdk_never_runs_tests(self):
        self.env['FAKE_VERSION'] = '3.47.0'
        self.assertNotEqual(self.run_kit('small').returncode, 0)
        self.assertFalse(self.record.exists())

    def test_directory_discovery_and_dry_run(self):
        self.data['suites']['small']['selectors'] = ['test']
        result = self.run_kit('small', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('test/one test_test.dart', result.stdout)
        self.assertFalse(self.record.exists())

    def test_empty_directory_is_error(self):
        (self.root / 'test' / 'empty').mkdir()
        self.data['suites']['small']['selectors'] = ['test/empty']
        self.assertNotEqual(self.run_kit('small').returncode, 0)

    def test_python_suite_propagates_real_failure(self):
        (self.root / 'tool').mkdir()
        (self.root / 'tool' / 'fixture_test.py').write_text('import unittest\nclass Broken(unittest.TestCase):\n def test_failure(self): self.fail("fixture failure")\n')
        self.data['suites']['small'] = {'engine': 'python', 'cwd': 'tool', 'selectors': ['tool/fixture_test.py']}
        result = self.run_kit('small')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('fixture failure', result.stderr)


if __name__ == '__main__':
    unittest.main()
