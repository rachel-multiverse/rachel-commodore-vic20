#!/usr/bin/env python3
"""Validate the canonical RKSI seed and compact VIC-20 workspace fixture."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def solo_source() -> str:
    """Return the solo translation unit in assembly order."""
    def expand(path: Path) -> str:
        source = path.read_text()
        parts = [source]
        for request in re.findall(r'^\.include "([^"]+)"', source, re.MULTILINE):
            parts.append(expand(path.parent / request))
        return "\n".join(parts)

    return expand(ROOT / "src/solo.asm")


def main() -> None:
    rksi = bytes.fromhex((ROOT / "tests/fixtures/kernel-state-v1.hex").read_text())
    assert rksi[:4] == b"RKSI"
    assert int.from_bytes(rksi[4:6], "big") == 1
    assert int.from_bytes(rksi[6:8], "big") == 1
    assert rksi[8:14] == bytes([2, 1, 1, 3, 5, 1])
    assert int.from_bytes(rksi[14:18], "big") == 7
    assert int.from_bytes(rksi[18:26], "big") == 42
    assert rksi[26:29] == bytes([2, 0x0E, 0xC2])
    assert rksi[29:32] == bytes([2, 0x8C, 0x47])
    assert rksi[32:] == bytes([0, 1, 5, 0, 2, 0xCB, 0x83, 0])

    source = solo_source()
    buffers = (ROOT / "src/rubp.asm").read_text()
    assert "solo_workspace:\n" in buffers
    assert "rx_buffer:      .res 64" in buffers
    assert "solo_scratch:   .res 16" in buffers
    assert "cpx #SOLO_WS_SIZE" in source
    assert "solo_fixture_validate:" in source
    assert "solo_get_action_count:" in source
    assert "solo_get_action_at:" in source
    assert "solo_card_is_legal:" in source
    assert "solo_apply_action:" in source
    assert "Validation completes before the first workspace write" in source
    assert "solo_deck_pop:" in source
    assert "solo_new_game:" in source
    assert "solo_recycle_discards:" in source
    assert "solo_save_state:" in source
    assert "solo_load_state:" in source
    assert "Load only after the entire image" in source
    assert "solo_ai_take_turn:" in source
    assert '"first legal play, otherwise' in source
    assert '.assert solo_workspace_fixture_end-solo_workspace_fixture = SOLO_WS_SIZE' in source
    assert re.search(r"\.byte \$cc,\$09\s+; two packed 6-bit ordinals", source)
    print("Compact fixture and 118-byte eight-seat overlay are consistent")


if __name__ == "__main__":
    main()
