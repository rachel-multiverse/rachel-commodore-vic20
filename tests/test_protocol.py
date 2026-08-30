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
        "MAGIC_0": 0x52, "MAGIC_1": 0x41, "MAGIC_2": 0x43, "MAGIC_3": 0x48,
        "MSG_HELLO": 1, "MSG_WELCOME": 2, "MSG_GAME_START": 3,
        "MSG_PLAY_CARDS": 4, "MSG_DRAW_CARD": 5, "MSG_CARD_DRAWN": 6,
        "MSG_GAME_STATE": 7, "MSG_TURN_START": 8, "MSG_TURN_END": 9,
        "MSG_PLAYER_WON": 10, "MSG_ERROR": 11, "MSG_HAND_SYNC": 15,
        "HDR_VERSION": 4, "HDR_TYPE": 5, "HDR_SEQ": 6,
        "HDR_PLAYER_ID": 8, "HDR_GAME_ID": 10, "HDR_TIMESTAMP": 12,
        "HDR_CRC": 14, "PAYLOAD_START": 16, "PAYLOAD_SIZE": 48,
        "PROTOCOL_VER": 2, "RACHEL_SPEC_VER": 1,
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
    assert "bit_delay:\n        ldy tx_bit_delay_count" in source
    assert "RX_BIT_DELAY_COUNT = 16" in source
    assert "RX_HALF_DELAY_COUNT = 7" in source


def test_keyboard_irqs_and_serial_critical_sections() -> None:
    main = (ROOT / "src/main.asm").read_text()
    serial = (ROOT / "src/net/wifi.asm").read_text()
    assert "jsr display_title\n\n        ; GETIN" in main
    assert "; for the duration of each timing-critical 8N1 transfer.\n        cli" in main
    assert "serial_send:\n        php\n        sei" in serial
    assert "serial_recv:\n        php\n        sei" in serial
    assert "rx_bit_delay:\n        ldy rx_bit_delay_count" in serial
    assert "rx_half_bit_delay:\n        ldy rx_half_delay_count" in serial
    assert "at_uart_2400:" in serial
    assert "sta tx_bit_delay_count" in serial
    assert "sta rx_bit_delay_count" in serial
    assert "sr_wait_stop:" in serial
    assert "bne sr_wait_stop" in serial
    assert "Framing error" in serial
    assert serial.count("        plp") >= 3
    input_source = (ROOT / "src/input.asm").read_text()
    connect = (ROOT / "src/connect.asm").read_text()
    assert "jsr wait_key\n        tax\n        pla\n        tay\n        txa" in input_source
    assert "sta ip_buffer,y" in input_source
    assert "parse_ip:\n        php\n        sei" in connect


def test_wire_literals_are_ascii_not_vic_petscii() -> None:
    source = (ROOT / "src/net/wifi.asm").read_text()
    rubp = (ROOT / "src/rubp.asm").read_text()
    assert '.byte "AT+' not in source
    assert '.byte "RACH"' not in source
    assert '.byte "VIC-20"' not in rubp

    data = (ROOT / "build/rachel.prg").read_bytes()
    assert bytes.fromhex("41 54 2b 43 49 50 53 54 41 52 54 3d") in data
    assert bytes.fromhex("41 54 2b 43 49 50 53 45 4e 44 3d 36 34 0d") in data
    assert b"RACH" in data
    assert b"VIC-20\x00" in data


def test_connect_response_uses_unambiguous_stream_terminator() -> None:
    source = (ROOT / "src/net/wifi.asm").read_text()
    wait = source[source.index("wait_response:"):source.index("timeout_lo:")]
    assert "cmp #$4b" in wait
    assert "cmp #$4e" in wait
    assert "cmp #$4f" not in wait
    assert "wr_maybe_err" not in wait
    assert "accepting either independently" in wait
    assert "wr_wait_k_timeout" not in wait
    assert "wr_success:" in wait


def test_screen_clear_terminates_and_text_uses_screen_codes() -> None:
    source = (ROOT / "src/display.asm").read_text()
    clear = source[source.index("display_clear:"):source.index("display_title:")]
    assert "sta SCREEN_BASE,y" in clear
    assert "sta SCREEN_BASE+$100,y" in clear
    assert "ldx ZP_PTR1+1" not in clear
    assert "and #$1f" in source
    assert "sta COLOR_BASE,y" in source
    assert "sta COLOR_BASE+$100,y" in source
    calculate = source[source.index("; Calculate screen address"):source.index("; Add X offset")]
    assert "asl" not in calculate
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
    assert "rx_buffer+PAYLOAD_START+10,x" in protocol
    assert "sta pending_draws" in protocol[protocol.index("process_turn_start:"):]
    assert "sta pending_skips" in protocol[protocol.index("process_turn_start:"):]
    assert "jsr send_sync_request" in main
    assert "cmp #MSG_PLAYER_LIST" in main
    assert "jsr process_player_list_welcome" in main
    assert "process_player_list_welcome:" in protocol
    assert "cmp #MSG_HAND_SYNC" in main
    assert "wfg_sync:" in main
    assert "cmp #$40" in main
    assert "jsr send_sync_request" in main[main.index("wfg_loop:"):]
    assert "sta tx_buffer+PAYLOAD_START+36" in protocol
    assert "send_sync_ack:" in protocol
    assert "#(SYNC_FLAG_HASH | SYNC_FLAG_ACK)" in protocol
    assert "lda server_sync_ack" in main

    # The wire format permits at most four cards in one play action.
    assert "cmp #4" in input_source
    assert "bcs ts_done" in input_source


def test_card_suits_use_the_wire_format_high_bits() -> None:
    game = (ROOT / "src/game.asm").read_text()
    short = game[game.index("render_card_short:"):game.index("render_card:")]
    full = game[game.index("render_card:"):game.index("rank_chars:")]
    assert short.count("        lsr") == 6
    assert full.count("        lsr") >= 6


def test_rubp_v2_crc_is_generated_and_required() -> None:
    protocol = (ROOT / "src/rubp.asm").read_text()
    network = (ROOT / "src/net/wifi.asm").read_text()
    assert "rubp_finalize:" in protocol
    assert "eor #$21" in protocol
    assert "eor #$10" in protocol
    assert "cpy #64" in protocol
    assert "crc_expected_hi" in protocol
    assert "cmp crc_hi" in protocol
    assert "cmp crc_lo" in protocol
    assert "net_send:\n        ; RUBP v2" in network
    assert "jsr rubp_finalize" in network


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
    test_keyboard_irqs_and_serial_critical_sections()
    test_wire_literals_are_ascii_not_vic_petscii()
    test_connect_response_uses_unambiguous_stream_terminator()
    test_screen_clear_terminates_and_text_uses_screen_codes()
    test_recovery_and_action_metadata_are_wired()
    test_card_suits_use_the_wire_format_high_bits()
    test_rubp_v2_crc_is_generated_and_required()
    test_canonical_fixture_when_supplied_by_ci()
    print("VIC-20 RUBP/PRG conformance checks passed")
