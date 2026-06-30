#!/usr/bin/env python3
"""Append Set-B quality-reviewed questions into testbank_questions.yaml.

Converts the source JSON (data/.. /ข้อสอบชุดใหม่) into the YAML schema used by
the Hugo site, mapping the descriptive domain name to the numeric domain key
that layouts/_default/testbank.html filters on, and tagging each question with
the competency level it measures (ระดับสมรรถนะที่วัด).
"""

from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
YAML_PATH = ROOT / "data" / "testbank_questions.yaml"
JSON_PATH = ROOT / "ข้อสอบชุดใหม่" / "teacher_professional_exam_100_questions_setB_quality_reviewed.json"

# Descriptive domain (Blueprint หมวด) -> numeric domain key used by the website.
DOMAIN_MAP = {
    "การเปลี่ยนแปลงบริบทของโลก สังคม และปรัชญาเศรษฐกิจพอเพียง": 1,
    "จิตวิทยาพัฒนาการ จิตวิทยาการศึกษา และจิตวิทยาให้คำปรึกษาในการวิเคราะห์และพัฒนาผู้เรียนตามศักยภาพ": 2,
    "หลักสูตร ศาสตร์การสอน และเทคโนโลยีดิจิทัลในการจัดการเรียนรู้": 3,
    "การวัด ประเมินผลการเรียนรู้ และการวิจัยเพื่อแก้ปัญหาและพัฒนาผู้เรียน": 4,
    "การออกแบบและการดำเนินการเกี่ยวกับงานประกันคุณภาพการศึกษา": 6,
}

# Thai difficulty descriptors -> the easy/medium/hard convention used in the YAML.
DIFFICULTY_MAP = {
    "ง่าย": "easy",
    "ปานกลาง": "medium",
    "ปานกลาง-ค่อนข้างยาก": "hard",
    "ค่อนข้างยาก": "hard",
    "ยาก": "hard",
}


def build_entry(src: dict) -> dict:
    domain = DOMAIN_MAP[src["domain"]]
    return {
        "id": src["id"],
        "set_id": src["set_id"],
        "domain": domain,
        "competency_level": src["competency_level"],
        "cognitive_level": src["cognitive_level"],
        "difficulty_level": DIFFICULTY_MAP[src["difficulty_level"]],
        "question_text": src["question_text"],
        "options": list(src["options"]),
        "correct_answer": int(src["correct_answer"]),
        "explanation": src["explanation"],
        "standard_ref": f"มาตรฐานความรู้ ด้านที่ {domain}",
        "status": "published",
    }


def main() -> int:
    src_questions = yaml.safe_load(JSON_PATH.read_text(encoding="utf-8"))
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
