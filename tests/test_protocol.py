#!/usr/bin/env python3
"""Dependency-free RUBP and PRG-format regression checks."""

from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]


def constants() -> dict[str, int]:
    values: dict[str, int] = {}
    for line in (ROOT / "src/equates.asm").read_text().splitlines():
        match = re.match(r"^([A-Z][A-Z0-9_]*)\s*=\s*\$([0-9A-Fa-f]+)\s*(?:;.*)?$", line)
        if match:
            values[match.group(1)] = int(match.group(2), 16)
            continue
        match = re.match(r"^([A-Z][A-Z0-9_]*)\s*=\s*([0-9]+)\s*(?:;.*)?$", line)
        if match:
            values[match.group(1)] = int(match.group(2))
    return values


def test_wire_constants() -> None:
    actual = constants()
    expected = {
        "MSG_HELLO": 1, "MSG_WELCOME": 2, "MSG_GAME_START": 3,
        "MSG_PLAY_CARDS": 4, "MSG_DRAW_CARD": 5, "MSG_CARD_DRAWN": 6,
        "MSG_GAME_STATE": 7, "MSG_TURN_START": 8, "MSG_TURN_END": 9,
        "MSG_PLAYER_WON": 10, "MSG_ERROR": 11, "MSG_HAND_SYNC": 15,
        "HDR_VERSION": 4, "HDR_TYPE": 5, "HDR_SEQ": 6,
        "HDR_PLAYER_ID": 8, "HDR_GAME_ID": 10, "HDR_TIMESTAMP": 12,
        "PAYLOAD_START": 16, "PAYLOAD_SIZE": 48, "RACHEL_SPEC_VER": 1,
    }
    assert {key: actual[key] for key in expected} == expected


def test_prg_run_trampoline() -> None:
    data = (ROOT / "build/rachel.prg").read_bytes()
    assert struct.unpack_from("<H", data)[0] == 0x1201
    # BASIC line 10: SYS 4624, terminated by an empty next-line pointer.
    assert data[2:14] == bytes.fromhex("0b120a009e34363234000000")
    # The linker pads through $120F; machine code begins with SEI at $1210.
    assert data[17] == 0x78


if __name__ == "__main__":
    test_wire_constants()
    test_prg_run_trampoline()
    print("VIC-20 RUBP/PRG conformance checks passed")
