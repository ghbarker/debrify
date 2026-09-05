import json
import tempfile
import unittest
from pathlib import Path

import ci_layering_delta


def _dump(payload: dict) -> str:
    path = Path(tempfile.mkstemp(suffix=".json")[1])
    path.write_text(json.dumps(payload), encoding="utf-8")
    return str(path)


class LayeringDeltaTest(unittest.TestCase):
    def test_pass_when_head_is_subset(self) -> None:
        parent = _dump(
            {
                "count": 2,
                "violations": [
                    {"id": "a|r|i"},
                    {"id": "b|r|i"},
                ],
            }
        )
        head = _dump({"count": 1, "violations": [{"id": "a|r|i"}]})
        self.assertEqual(ci_layering_delta.main(["x", parent, head]), 0)

    def test_fail_on_new_id(self) -> None:
        parent = _dump({"count": 0, "violations": []})
        head = _dump(
            {
                "count": 1,
                "violations": [
                    {
                        "file": "lib/services/x.dart",
                        "rule": "services: no screens",
                        "import": "package:debrify/screens/a.dart",
                    }
                ],
            }
        )
        self.assertEqual(ci_layering_delta.main(["x", parent, head]), 1)


if __name__ == "__main__":
    unittest.main()
