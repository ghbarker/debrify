import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
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
