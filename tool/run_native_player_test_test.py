import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run_native_player_test as gate


def report():
    return [
        {"type": "testStart", "test": {"id": 1, "name": gate.CASE}},
        {"type": "testDone", "testID": 1, "result": "success", "hidden": False, "skipped": False},
        {"type": "done", "success": True},
    ]


class NativeGateTests(unittest.TestCase):
    def validate(self, events, code=0):
        gate.validate_report("\n".join(map(json.dumps, events)), code)

    def test_real_case_passes(self):
        self.validate(report())

    def test_fail_closed_reports(self):
        variants = [[], report()[:-1], [report()[-1]], report() * 2]
        for field, value in (("skipped", True), ("result", "failure"), ("hidden", True)):
            events = report()
            events[1][field] = value
            variants.append(events)
        events = report()
        events.insert(1, {"type": "error"})
        variants.append(events)
        events = report()
        events[0]["test"]["metadata"] = {"skip": True}
        variants.append(events)
        for events in variants:
            with self.subTest(events=events), self.assertRaises(ValueError):
                self.validate(events)
        with self.assertRaises(ValueError):
            self.validate(report(), 1)
        with self.assertRaises(ValueError):
            gate.validate_report("not JSON", 0)

    def test_generic_delegates_verdict_and_retries(self):
        def existing_main(args):
            self.assertEqual(args, ["--tags", "golden", "--retries", "2"])
            cmd = gate.allowlist.flutter_test_command(golden=True, report=Path("r"))
            self.assertEqual(cmd[3:7], ["--exclude-tags", "native", "--tags", "golden"])
            return 17
        original = gate.allowlist.flutter_test_command
        with patch.object(gate.allowlist, "main", side_effect=existing_main):
            self.assertEqual(gate.main(["generic", "--tags", "golden", "--retries", "2"]), 17)
        self.assertIs(gate.allowlist.flutter_test_command, original)
        self.assertIn("golden || native", gate.generic_command(golden=False, report=Path("r")))

    def test_missing_runtime_fails_before_launch(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(gate.subprocess, "run") as launch:
            root = Path(temp)
            with self.assertRaisesRegex(ValueError, "Missing native library"):
                gate.run_pair(root, root, root, root / "missing", root)
            launch.assert_not_called()

    def test_pair_launches_actual_constructed_command_and_rejects_missing_report(self):
        with tempfile.TemporaryDirectory(prefix="native gate ") as temp:
            root = Path(temp)
            current, origin, sdk, output = (root / n for n in ("current", "origin", "SDK space", "reports"))
            for checkout in (current, origin):
                (checkout / gate.TEST).parent.mkdir(parents=True)
                (checkout / gate.TEST).write_text("identical test bytes")
            dart = sdk / "bin/cache/dart-sdk/bin" / ("dart.exe" if os.name == "nt" else "dart")
            dart.parent.mkdir(parents=True)
            dart.touch()
            (sdk / "bin/cache/flutter_tools.snapshot").touch()
            (sdk / "bin/cache/flutter.version.json").write_text('{"frameworkVersion":"3.44.8"}')
            library = root / "native library"
            library.touch()
            seen = []

            def launch(cmd, **kwargs):
                seen.append(kwargs["cwd"])
                self.assertEqual(cmd[:2], [str(dart), str(sdk / "bin/cache/flutter_tools.snapshot")])
                self.assertEqual(cmd[2:7], ["test", str(gate.TEST), "--no-pub", "--tags", "native"])
                self.assertEqual(kwargs["env"]["LIBMPV_LIBRARY_PATH"], str(library))
                if kwargs["cwd"] == current:
                    Path(cmd[-1][5:]).write_text("\n".join(map(json.dumps, report())))
                return subprocess.CompletedProcess(cmd, 0)

            with patch.object(gate, "git", return_value=gate.ORIGIN), patch.object(gate.subprocess, "run", side_effect=launch):
                self.assertEqual(gate.run_pair(current, origin, sdk, library, output), 1)
            self.assertEqual(seen, [origin, current])
            evidence = json.loads((output / "evidence.json").read_text())
            self.assertEqual(evidence["runs"]["current"]["verdict"], "passed")
            (origin / gate.TEST).write_text("different")
            with patch.object(gate, "git", return_value=gate.ORIGIN), self.assertRaisesRegex(ValueError, "bytes differ"):
                gate.run_pair(current, origin, sdk, library, output)


if __name__ == "__main__":
    unittest.main()
