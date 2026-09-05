"""Gate (i): reject added import-layering occurrences against the base tree.

Reads two JSON dumps from the same checker. Duplicate identities retain their
multiplicity: removing a different violation cannot pay for a new occurrence.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


def _occurrences(payload: object) -> Counter[str]:
    if not isinstance(payload, dict):
        raise ValueError("expected a JSON object")
    rows = payload.get("violations")
    if not isinstance(rows, list):
        raise ValueError("violations must be a list")
    count = payload.get("count")
    if type(count) is not int or count < 0:
        raise ValueError("count must be a nonnegative integer")
    if count != len(rows):
        raise ValueError("count must equal the number of violations")
    out: Counter[str] = Counter()
    fields = ("file", "rule", "import")
    for index, row in enumerate(rows):
        prefix = f"violations[{index}]"
        if not isinstance(row, dict):
            raise ValueError(f"{prefix} must be an object")
        has_fields = any(field in row for field in fields)
        fallback = None
        if has_fields or "id" not in row:
            if any(not isinstance(row.get(field), str) or not row[field].strip()
                   for field in fields):
                raise ValueError(f"{prefix} requires nonempty file, rule and import strings")
            fallback = "|".join(row[field] for field in fields)
        if "id" in row:
            ident = row["id"]
            if (not isinstance(ident, str)
                    or len(ident.split("|", 2)) != 3
                    or any(not part.strip() for part in ident.split("|", 2))):
                raise ValueError(f"{prefix}.id must contain nonempty file|rule|import")
            if fallback is not None and ident != fallback:
                raise ValueError(f"{prefix}.id does not match file|rule|import")
        else:
            ident = fallback
        out[ident] += 1
    return out


def _read_occurrences(path: str) -> Counter[str]:
    try:
        return _occurrences(json.loads(Path(path).read_text(encoding="utf-8")))
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError(f"Invalid layering report {path}: {error}") from error


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: ci_layering_delta.py <parent.json> <head.json>", file=sys.stderr)
        return 2
    try:
        parent_ids = _read_occurrences(argv[1])
        head_ids = _read_occurrences(argv[2])
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
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
