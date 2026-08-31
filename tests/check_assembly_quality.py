#!/usr/bin/env python3
"""Cheap structural checks for the hand-written assembly include graph."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOLO_ROOT = ROOT / "src/solo.asm"
EXPECTED_MODULES = [
    "solo/layout.asm",
    "solo/ui.asm",
    "solo/api.asm",
    "solo/actions.asm",
    "solo/deck.asm",
    "solo/rules.asm",
    "solo/state.asm",
    "solo/fixtures.asm",
]
EXPECTED_FIXTURES = [
    "fixtures/core.asm",
    "fixtures/actions.asm",
    "fixtures/deck.asm",
    "fixtures/persistence.asm",
    "fixtures/ai.asm",
    "fixtures/complete_game.asm",
    "fixtures/data.asm",
]


def main() -> None:
    root = SOLO_ROOT.read_text()
    includes = re.findall(r'^\.include "([^"]+)"', root, re.MULTILINE)
    assert includes == EXPECTED_MODULES, includes

    source_paths = [ROOT / "src" / name for name in includes]
    assert all(path.is_file() for path in source_paths)
    fixture_root = ROOT / "src/solo/fixtures.asm"
    fixture_includes = re.findall(
        r'^\.include "([^"]+)"', fixture_root.read_text(), re.MULTILINE
    )
    assert fixture_includes == EXPECTED_FIXTURES, fixture_includes
    nested_paths = [fixture_root.parent / name for name in fixture_includes]
    assert all(path.is_file() for path in nested_paths)
    source = "\n".join(path.read_text() for path in source_paths + nested_paths)

    assert "docs/ASSEMBLY_CONVENTIONS.md" in source
    assert "RUBP buffers must remain contiguous" in source
    assert "solo workspace must end at scratch" in source

    previous_jsr = None
    for line_number, line in enumerate(source.splitlines(), start=1):
        match = re.match(r"\s*jsr\s+([A-Za-z_][A-Za-z0-9_:]*)\s*(?:;.*)?$", line)
        if match:
            target = match.group(1)
            assert target != previous_jsr, f"duplicate consecutive jsr {target} near line {line_number}"
            previous_jsr = target
        elif line.strip() and not line.lstrip().startswith(";"):
            previous_jsr = None

    print("Assembly module graph, layout assertions and local call hygiene passed")


if __name__ == "__main__":
    main()
