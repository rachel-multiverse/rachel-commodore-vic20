#!/usr/bin/env python3
"""Guard the single-PRG solo contingency using ld65's measured CODE segment."""

from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "build/rachel.map"
OUT = ROOT / "build/memory-budget.json"
CODE_CAPACITY = 0x2DF0
CONTINGENCY = 0x0800
FIRST_PLAYABLE_CEILING = CODE_CAPACITY - CONTINGENCY


def main() -> None:
    match = re.search(
        r"^CODE\s+[0-9A-F]+\s+[0-9A-F]+\s+([0-9A-F]+)",
        MAP.read_text(), re.MULTILINE,
    )
    if not match:
        raise SystemExit("CODE segment missing from linker map")
    used = int(match.group(1), 16)
    remaining = CODE_CAPACITY - used
    solo_allowance = FIRST_PLAYABLE_CEILING - used
    report = {
        "codeCapacityBytes": CODE_CAPACITY,
        "codeUsedBytes": used,
        "codeRemainingBytes": remaining,
        "firstPlayableCeilingBytes": FIRST_PLAYABLE_CEILING,
        "soloFirstSliceAllowanceBytes": solo_allowance,
        "requiredContingencyBytes": CONTINGENCY,
        "singlePrgGo": solo_allowance > 0,
    }
    OUT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, sort_keys=True))
    if used > FIRST_PLAYABLE_CEILING:
        raise SystemExit("CODE exceeds the single-PRG ceiling with 2 KiB contingency")


if __name__ == "__main__":
    main()
