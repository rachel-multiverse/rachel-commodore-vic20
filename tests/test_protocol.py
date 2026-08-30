#!/usr/bin/env python3
"""Dependency-free RUBP and PRG-format regression checks."""

from pathlib import Path
import json
import os
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


def test_real_vic20_user_port_pins() -> None:
    source = (ROOT / "src/net/wifi.asm").read_text()
    assert "VIA1_PORTB" in source
    assert "and #$01" in source
    assert "ora #$c0" in source
    assert "ora #$e0" in source
    assert "bit_delay:\n        ldy #14" in source
    assert "PA7 as output" not in source


def test_recovery_and_action_metadata_are_wired() -> None:
    protocol = (ROOT / "src/rubp.asm").read_text()
    main = (ROOT / "src/main.asm").read_text()
    input_source = (ROOT / "src/input.asm").read_text()

    # HELLO must use the unassigned sender ID, not accidentally claim seat 0.
    init = protocol[protocol.index("rubp_init:"):protocol.index("build_header:")]
    assert "lda #$ff" in init
    assert "sta player_id_lo" in init
    assert "sta player_id_hi" in init

    # Both actions carry the last authoritative state hash when available.
    assert "tx_buffer+PAYLOAD_START+36" in protocol
    assert "tx_buffer+PAYLOAD_START+37,x" in protocol
    assert "tx_buffer+PAYLOAD_START+4" in protocol
    assert "tx_buffer+PAYLOAD_START+5,x" in protocol

    # Recovery metadata is not discarded and ERROR requests a fresh pair.
    assert "process_hand_sync:" in protocol
    assert "rx_buffer+PAYLOAD_START+33,x" in protocol
    assert "rx_buffer+PAYLOAD_START+40,x" in protocol
    assert "jsr send_sync_request" in main

    # The wire format permits at most four cards in one play action.
    assert "cmp #4" in input_source
    assert "bcs ts_done" in input_source


def test_canonical_fixture_when_supplied_by_ci() -> None:
    path = os.environ.get("RUBP_FIXTURE")
    if not path:
        return
    fixture = json.loads(Path(path).read_text())
    messages = {message["name"]: message for message in fixture["messages"]}
    for name in ("hello", "play_card", "draw_card", "game_state", "hand_sync", "sync_request"):
        encoded = bytes.fromhex(messages[name]["hex"])
        assert len(encoded) == 64
        assert encoded[:5] == b"RACH\x01"


if __name__ == "__main__":
    test_wire_constants()
    test_prg_run_trampoline()
    test_real_vic20_user_port_pins()
    test_recovery_and_action_metadata_are_wired()
    test_canonical_fixture_when_supplied_by_ci()
    print("VIC-20 RUBP/PRG conformance checks passed")
