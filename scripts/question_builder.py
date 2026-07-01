"""Shared helpers for generating testbank question entries."""

L3 = "Level 3: ประยุกต์ใช้และวิเคราะห์"
L4 = "Level 4: ประเมินค่าและสร้างสรรค์"
SET_ID = "testbank_d5_ethics_expansion"


def q(
    qid: str,
    domain,
    subcompetency: str,
    competency_level: str,
    difficulty: str,
    situation: str,
    question: str,
    options: list[str],
    correct: int,
    explanation: str,
    standard_ref: str,
) -> dict:
    return {
        "id": qid,
        "set_id": SET_ID,
        "domain": domain,
        "subcompetency": subcompetency,
        "competency_level": competency_level,
        "difficulty_level": difficulty,
        "question_text": f"สถานการณ์: {situation}\nคำถาม: {question}",
        "options": options,
        "correct_answer": correct,
        "explanation": explanation,
        "standard_ref": standard_ref,
        "status": "published",
    }
