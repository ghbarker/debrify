"""Gate (i): reject added import-layering occurrences against the base tree.

Reads two JSON dumps from the same checker. Duplicate identities retain their
multiplicity: removing a different violation cannot pay for a new occurrence.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


def _occurrences(payload: dict) -> Counter[str]:
    out: Counter[str] = Counter()
    for row in payload.get("violations") or []:
        ident = row.get("id")
        if not ident:
            ident = f"{row.get('file')}|{row.get('rule')}|{row.get('import')}"
        out[str(ident)] += 1
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: ci_layering_delta.py <parent.json> <head.json>", file=sys.stderr)
        return 2
    parent = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    head = json.loads(Path(argv[2]).read_text(encoding="utf-8"))
    parent_ids = _occurrences(parent)
    head_ids = _occurrences(head)
    added = head_ids - parent_ids
    removed = parent_ids - head_ids
    parent_n = sum(parent_ids.values())
    head_n = sum(head_ids.values())
    print(f"layering count: parent {parent_n} -> head {head_n}")
    print(f"layering delta: +{sum(added.values())} / -{sum(removed.values())}")
    if added:
        print("NEW violation occurrences (gate i red):")
        for ident, count in sorted(added.items()):
            print(f"  +{count} {ident}")
        return 1
    print("gate (i) pass: no added layering occurrences")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
