#!/usr/bin/env python3
"""Quality checks for testbank questions (length-bias, answer distribution)."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = ROOT / "public" / "testbank" / "questions.json"
FIRST_SET_SIZE = 100


def load_questions(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def option_lengths(options: list[str]) -> list[int]:
    return [len(o) for o in options]


def is_unique_longest(lens: list[int], correct_index: int) -> bool:
    mx = max(lens)
    return lens.count(mx) == 1 and lens[correct_index] == mx


def analyze(questions: list[dict], label: str) -> dict:
    unique_longest_ids: list[str] = []
    for q in questions:
        lens = option_lengths(q["options"])
        if is_unique_longest(lens, q["correct_answer"]):
            unique_longest_ids.append(q["id"])

    pos = Counter(q["correct_answer"] for q in questions)
    total = len(questions)
    pct = (len(unique_longest_ids) / total * 100) if total else 0.0

    print(f"\n=== {label} ({total} questions) ===")
    print(f"Unique-longest correct option: {len(unique_longest_ids)}/{total} ({pct:.1f}%)")
    print("correct_answer distribution:", dict(sorted(pos.items())))
    if unique_longest_ids:
        print("Biased IDs:", ", ".join(unique_longest_ids))

    return {
        "total": total,
        "unique_longest": len(unique_longest_ids),
        "unique_longest_pct": pct,
        "biased_ids": unique_longest_ids,
        "answer_distribution": dict(sorted(pos.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--json",
        type=Path,
        default=DEFAULT_JSON,
        help="Path to questions.json",
    )
    parser.add_argument(
        "--first-set-size",
        type=int,
        default=FIRST_SET_SIZE,
        help="Number of questions in the original first batch",
    )
    args = parser.parse_args()

    questions = load_questions(args.json)
    print(f"Loaded {len(questions)} questions from {args.json}")

    analyze(questions, "ALL")
    if len(questions) >= args.first_set_size:
        analyze(questions[: args.first_set_size], f"FIRST {args.first_set_size}")
        analyze(questions[args.first_set_size :], f"REST ({len(questions) - args.first_set_size}+)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
