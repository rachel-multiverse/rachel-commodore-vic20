#!/usr/bin/env python3
"""Validate the canonical RKSI seed and compact VIC-20 workspace fixture."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


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

    source = (ROOT / "src/solo.asm").read_text()
    assert "solo_workspace     = tx_buffer" in source
    assert "solo_scratch       = rx_buffer+16" in source
    assert "cpx #SOLO_WS_SIZE" in source
    assert "solo_fixture_validate:" in source
    assert "solo_get_action_count:" in source
    assert "solo_get_action_at:" in source
    assert "solo_card_is_legal:" in source
    assert '.assert solo_workspace_fixture_end-solo_workspace_fixture = SOLO_WS_SIZE' in source
    assert re.search(r"\.byte \$cc,\$09\s+; two packed 6-bit ordinals", source)
    print("Compact two-player fixture and 80+16-byte overlay are consistent")


if __name__ == "__main__":
    main()
