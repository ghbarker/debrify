import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import ci_layering_delta


class LayeringDeltaTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="layering-delta-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def compare(self, parent_ids: list[str], head_ids: list[str], *, fallback=False):
        def payload(ids):
            rows = []
            for ident in ids:
                file, rule, spec = ident.split("|")
                rows.append({"file": file, "rule": rule, "import": spec}
                            if fallback else {"id": ident})
            return {"count": len(rows), "violations": rows}

        paths = [self.root / "parent.json", self.root / "head.json"]
        for path, ids in zip(paths, [parent_ids, head_ids]):
            path.write_text(json.dumps(payload(ids)), encoding="utf-8")
        output = io.StringIO()
        with redirect_stdout(output):
            result = ci_layering_delta.main(["x", *map(str, paths)])
        # Prove the readers have released both files on Windows before cleanup.
        for path in paths:
            path.unlink()
        return result, output.getvalue()

    def compare_payloads(self, parent, head):
        paths = [self.root / "parent.json", self.root / "head.json"]
        output, errors = io.StringIO(), io.StringIO()
        try:
            for path, payload in zip(paths, [parent, head]):
                path.write_text(json.dumps(payload), encoding="utf-8")
            with redirect_stdout(output), redirect_stderr(errors):
                result = ci_layering_delta.main(["x", *map(str, paths)])
            return result, output.getvalue(), errors.getvalue()
        finally:
            # Unlink even on rejection: open handles would fail here on Windows.
            for path in paths:
                path.unlink(missing_ok=True)

    def assert_invalid(self, payload):
        valid = {"count": 0, "violations": []}
        for side in ("parent", "head"):
            with self.subTest(side=side, payload=payload):
                result, output, errors = self.compare_payloads(
                    payload if side == "parent" else valid,
                    payload if side == "head" else valid,
                )
                self.assertEqual(result, 2, output)
                self.assertIn(f"{side}.json", errors)
                self.assertIn("Invalid layering report", errors)
                self.assertNotIn("gate (i) pass", output)

    def test_reject_non_object_report(self):
        for payload in (None, [], "", 1):
            self.assert_invalid(payload)

    def test_reject_missing_or_wrong_typed_violations(self):
        self.assert_invalid({"count": 0})
        for rows in (None, {}, "", False, 0):
            self.assert_invalid({"count": 0, "violations": rows})

    def test_reject_missing_noninteger_or_negative_count(self):
        self.assert_invalid({"violations": []})
        for count in (None, True, False, "0", 0.0, -1):
            self.assert_invalid({"count": count, "violations": []})

    def test_reject_inconsistent_count(self):
        self.assert_invalid({"count": 1, "violations": []})
        self.assert_invalid({"count": 0, "violations": [{"id": "a|r|i"}]})

    def test_reject_non_object_rows(self):
        for row in (None, [], "", 1):
            self.assert_invalid({"count": 1, "violations": [row]})

    def test_reject_malformed_explicit_identity(self):
        for ident in (None, "", " ", False, 1, [], {}, "a", "a||i", "|r|i", "a|r|"):
            self.assert_invalid({"count": 1, "violations": [{"id": ident}]})

    def test_reject_incomplete_or_malformed_fallback_identity(self):
        self.assert_invalid({"count": 1, "violations": [{}]})
        for field in ("file", "rule", "import"):
            row = {"file": "a", "rule": "r", "import": "i"}
            del row[field]
            self.assert_invalid({"count": 1, "violations": [row]})
            for value in (None, "", " ", False, 1, []):
                self.assert_invalid({"count": 1, "violations": [
                    {**row, field: value}
                ]})

    def test_reject_inconsistent_or_partial_identity_fields(self):
        self.assert_invalid({"count": 1, "violations": [
            {"id": "a|r|i", "file": "b", "rule": "r", "import": "i"}
        ]})
        self.assert_invalid({"count": 1, "violations": [
            {"id": "a|r|i", "file": "a"}
        ]})

    def test_exact_checker_schema_and_empty_reports_pass(self):
        row = {"file": "lib/a.dart", "import": "package:flutter/widgets.dart",
               "rule": "services: no Flutter", "detail": "imports Flutter",
               "id": "lib/a.dart|services: no Flutter|package:flutter/widgets.dart"}
        for payload in ({"count": 0, "ceiling": 90, "violations": []},
                        {"count": 1, "ceiling": 90, "violations": [row]}):
            result, output, errors = self.compare_payloads(payload, payload)
            self.assertEqual(result, 0, errors)
            self.assertIn("gate (i) pass", output)
            self.assertEqual(errors, "")

    def test_missing_and_invalid_json_files_fail_clearly(self):
        parent = self.root / "parent.json"
        head = self.root / "head.json"
        parent.write_text('{"count": 0, "violations": []}', encoding="utf-8")
        try:
            for content in (None, "{"):
                with self.subTest(content=content):
                    if content is not None:
                        head.write_text(content, encoding="utf-8")
                    errors = io.StringIO()
                    with redirect_stderr(errors):
                        result = ci_layering_delta.main(["x", str(parent), str(head)])
                    self.assertEqual(result, 2)
                    self.assertIn("head.json", errors.getvalue())
                    self.assertIn("Invalid layering report", errors.getvalue())
        finally:
            parent.unlink()
            head.unlink(missing_ok=True)

    def test_pass_when_head_is_subset(self):
        self.assertEqual(self.compare(["a|r|i", "b|r|i"], ["a|r|i"])[0], 0)

    def test_fail_on_new_id(self):
        self.assertEqual(self.compare([], ["a|r|i"], fallback=True)[0], 1)

    def test_fail_when_duplicate_replaces_removed_identity_at_same_total(self):
        result, output = self.compare(["a|r|i", "b|r|i"], ["a|r|i", "a|r|i"])
        self.assertEqual(result, 1, output)
        self.assertIn("layering delta: +1 / -1", output)

    def test_fail_when_duplicate_grows_below_ceiling(self):
        result, output = self.compare(["a|r|i"], ["a|r|i"] * 3)
        self.assertEqual(result, 1, output)
        self.assertIn("layering delta: +2 / -0", output)

    def test_duplicate_fallback_identity_also_fails(self):
        self.assertEqual(self.compare(["a|r|i"], ["a|r|i"] * 2, fallback=True)[0], 1)

    def test_equal_multiplicities_pass(self):
        self.assertEqual(self.compare(["a|r|i"] * 2, ["a|r|i"] * 2)[0], 0)

    def test_removing_duplicate_passes_and_counts_occurrences(self):
        result, output = self.compare(["a|r|i"] * 3, ["a|r|i"])
        self.assertEqual(result, 0, output)
        self.assertIn("layering delta: +0 / -2", output)

    def test_empty_head_reports_zero(self):
        result, output = self.compare(["a|r|i"], [])
        self.assertEqual(result, 0, output)
        self.assertIn("parent 1 -> head 0", output)


if __name__ == "__main__":
    unittest.main()
