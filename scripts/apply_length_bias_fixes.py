#!/usr/bin/env python3
"""Apply balanced option rewrites from length_bias_edits.json to testbank YAML."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_YAML = ROOT / "data" / "testbank_questions.yaml"
DEFAULT_EDITS = ROOT / "scripts" / "length_bias_edits.json"


def load_edits(path: Path) -> dict[str, list[str]]:
    with path.open(encoding="utf-8") as f:
        edits = json.load(f)
    for qid, opts in edits.items():
        if not isinstance(opts, list) or len(opts) != 4:
            raise ValueError(f"{qid}: expected exactly 4 options, got {opts!r}")
    return edits


def apply_edits(yaml_path: Path, edits: dict[str, list[str]], dry_run: bool = False) -> int:
    with yaml_path.open(encoding="utf-8") as f:
        questions = yaml.safe_load(f)

    by_id = {q["id"]: q for q in questions}
    missing = [qid for qid in edits if qid not in by_id]
    if missing:
        raise KeyError(f"IDs not found in YAML: {missing}")

    changed = 0
    for qid, new_options in edits.items():
        q = by_id[qid]
        if q["options"] != new_options:
            q["options"] = new_options
            changed += 1

    print(f"Updated {changed}/{len(edits)} questions in {yaml_path}")

    if dry_run:
        print("Dry run — YAML not written")
        return changed

    out = yaml.dump(
        questions,
        Dumper=yaml.SafeDumper,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
        width=4096,
    )
    yaml_path.write_text(out, encoding="utf-8")
    print(f"Wrote {yaml_path}")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yaml", type=Path, default=DEFAULT_YAML)
    parser.add_argument("--edits", type=Path, default=DEFAULT_EDITS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    edits = load_edits(args.edits)
    print(f"Loaded {len(edits)} option rewrites from {args.edits}")
    apply_edits(args.yaml, edits, dry_run=args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
