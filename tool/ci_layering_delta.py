"""Gate (i): fail when the PR adds import-layering violations vs its parent.

Reads two JSON dumps from `dart run tool/check_layering.dart --json`.
Exit 1 if any violation id exists on HEAD that did not exist on the parent.
Prints the HEAD count for the Leaves table.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def _ids(payload: dict) -> set[str]:
    out: set[str] = set()
    for row in payload.get("violations") or []:
        ident = row.get("id")
        if ident:
            out.add(str(ident))
            continue
        out.add(f"{row.get('file')}|{row.get('rule')}|{row.get('import')}")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(
            "usage: ci_layering_delta.py <parent.json> <head.json>",
            file=sys.stderr,
        )
        return 2
    parent = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    head = json.loads(Path(argv[2]).read_text(encoding="utf-8"))
    parent_ids = _ids(parent)
    head_ids = _ids(head)
    added = sorted(head_ids - parent_ids)
    removed = sorted(parent_ids - head_ids)
    parent_n = int(parent.get("count") or len(parent_ids))
    head_n = int(head.get("count") or len(head_ids))
    print(f"layering count: parent {parent_n} -> head {head_n}")
    print(f"layering delta: +{len(added)} / -{len(removed)}")
    if added:
        print("NEW violations (gate i red):")
        for ident in added:
            print(f"  {ident}")
        return 1
    print("gate (i) pass: no new layering violations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
