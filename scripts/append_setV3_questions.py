#!/usr/bin/env python3
"""Append Set-v3 (100 questions) into testbank_questions.yaml.

Source: ข้อสอบชุดใหม่_1/testbank_v3_100questions.yaml
Each question already uses numeric domain keys and competency_level
(ระดับสมรรถนะที่วัด) per the Teacher Test Blueprint.
"""

from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
YAML_PATH = ROOT / "data" / "testbank_questions.yaml"
SRC_PATH = ROOT / "ข้อสอบชุดใหม่_1" / "testbank_v3_100questions.yaml"
SET_ID = "testbank_v3_100"


def build_entry(src: dict) -> dict:
    return {
        "id": src["id"],
        "set_id": SET_ID,
        "domain": int(src["domain"]),
        "subcompetency": src["subcompetency"],
        "competency_level": src["competency_level"],
        "difficulty_level": src["difficulty_level"],
        "question_text": src["question_text"],
        "options": list(src["options"]),
        "correct_answer": int(src["correct_answer"]),
        "explanation": src["explanation"],
        "standard_ref": src["standard_ref"],
        "status": src.get("status", "published"),
    }


def main() -> int:
    src_questions = yaml.safe_load(SRC_PATH.read_text(encoding="utf-8"))
    existing = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8"))
    existing_ids = {q["id"] for q in existing}

    new_entries = []
    for src in src_questions:
        if src["id"] in existing_ids:
            raise SystemExit(f"ID collision: {src['id']} already exists in YAML")
        new_entries.append(build_entry(src))

    chunk = yaml.dump(
        new_entries,
        Dumper=yaml.SafeDumper,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
        width=4096,
    )

    current = YAML_PATH.read_text(encoding="utf-8")
    if not current.endswith("\n"):
        current += "\n"
    YAML_PATH.write_text(current + chunk, encoding="utf-8")

    print(f"Appended {len(new_entries)} questions to {YAML_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
