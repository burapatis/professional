#!/usr/bin/env python3
"""Add aria-hidden/focusable to decorative inline <svg> tags in layouts.

All inline SVGs on the site are decorative (logos and card icons that sit
beside text labels), so they should be hidden from assistive technology.
This inserts aria-hidden="true" focusable="false" into any <svg ...> opening
tag that does not already declare aria-hidden. Idempotent.
"""

from __future__ import annotations

import glob
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUTS = ROOT / "layouts"

SVG_OPEN = re.compile(r"<svg\b([^>]*)>")


def patch(attrs: str) -> str:
    if "aria-hidden" in attrs:
        return None  # already accessible-hidden
    insert = ' aria-hidden="true" focusable="false"'
    return "<svg" + insert + attrs + ">"


def process(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        new = patch(m.group(1))
        if new is None:
            return m.group(0)
        count += 1
        return new

    new_text = SVG_OPEN.sub(repl, text)
    if count:
        path.write_text(new_text, encoding="utf-8")
    return count


def main() -> int:
    total = 0
    for f in sorted(glob.glob(str(LAYOUTS / "**" / "*.html"), recursive=True)):
        n = process(Path(f))
        if n:
            print(f"{Path(f).relative_to(ROOT)}: +{n}")
            total += n
    print(f"Total svg tags patched: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
