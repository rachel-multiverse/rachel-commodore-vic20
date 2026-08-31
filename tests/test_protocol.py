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
    assert "detect_video_standard:" in serial
    assert "cpx #140" in serial
    assert "NTSC_TX_BIT_DELAY_COUNT       = 11" in serial
    assert "NTSC_RX_SLOW_HALF_DELAY_COUNT = 41" in serial
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
    assert "display_clear_row:" in source
    assert "cpy #SCREEN_WIDTH" in source[source.index("display_clear_row:"):source.index("display_title:")]
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
    assert "cmp #$08" in main
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
    short = game[game.index("render_card_short:"):game.index("render_discard_card:")]
    discard = game[game.index("render_discard_card:"):game.index("card_suit_index:")]
    full = game[game.index("card_suit_index:"):game.index("render_suit:")]
    # Both card renderers reach the suit through the same six-shift helper, so
    # neither can drift onto a nibble of its own.
    assert "jsr card_suit_index" in short
    assert "jsr card_suit_index" in discard
    assert full.count("        lsr") >= 6


def test_petscii_cards_use_raw_codes_and_colour() -> None:
    display = (ROOT / "src/display.asm").read_text()
    game = (ROOT / "src/game.asm").read_text()
    assert "print_screen_code:" in display
    assert "set_cursor_color:" in display
    assert "color_lo:" in display and "color_hi:" in display
    assert "print_centered:" in display
    assert ".byte $53, $5a, $58, $41" in game
    assert ".byte COLOR_RED, COLOR_RED, COLOR_CYAN, COLOR_CYAN" in game
    assert "render_discard_card:" in game
    for glyph in ("SC_TOP_LEFT", "SC_TOP_RIGHT", "SC_BOTTOM_LEFT", "SC_BOTTOM_RIGHT"):
        assert glyph in game


def test_public_table_represents_all_eight_players() -> None:
    game = (ROOT / "src/game.asm").read_text()
    protocol = (ROOT / "src/rubp.asm").read_text()
    assert "render_player_table:" in game
    assert "cpx #8" in game[game.index("render_player_table:"):game.index("render_help:")]
    assert '.byte "CARDS LEFT"' in game
    assert ".byte 0, 7, 14, 0, 7, 14, 0, 7" in game
    assert ".byte 9, 9, 9, 10, 10, 10, 11, 11" in game
    for colour in ("COLOR_GREEN", "COLOR_YELLOW", "COLOR_PURPLE"):
        assert colour in game[game.index("render_player_table:"):game.index("render_help:")]
    # A GAME_STATE can recover the occupied-seat count if a lobby list was lost.
    counts = protocol[protocol.index("pgs_counts:"):protocol.index("pgs_turn:")]
    assert "cmp player_count" in counts
    assert "sta player_count" in counts
    render = game[game.index("render_game:"):game.index("turn_msg:")]
    assert "jsr display_clear\n" not in render
    # Row clearing lives with the routine that owns the rows. render_table_state
    # owns 12 and 13; neither it nor render_game may wipe the whole screen.
    assert "jsr render_table_state" in render
    state = game[game.index("render_table_state:"):game.index("draw_msg:")]
    assert "jsr display_clear\n" not in state
    assert "jsr display_clear_row" in state


def test_player_feedback_and_terminal_result_are_wired() -> None:
    main = (ROOT / "src/main.asm").read_text()
    game = (ROOT / "src/game.asm").read_text()
    protocol = (ROOT / "src/rubp.asm").read_text()

    for message in (
        "WAITING FOR GAME", "SELECT A CARD FIRST", "MOVE REJECTED-RETRY",
        "YOU LOSE!", "YOU FINISH: ", "P", " HOLDS THE CARDS",
        "PRESS KEY TO FINISH",
    ):
        assert f'.byte "{message}' in main
    assert '.byte "LR MOVE SP/FIRE SEL"' in game
    assert '.byte "RET PLAYS SELECTION"' in game
    assert '.byte "YOU\'RE OUT - WATCHING"' in game
    # The nomination prompt borrows row 17 and clears it on every exit, so it
    # cannot be left on screen behind whatever renders next.
    modal = game[game.index("pick_suit_modal:"):game.index("render_hand_page:")]
    assert "sps_confirm:" in modal and "sps_cancel:" in modal
    assert modal.count("jsr display_clear_row") == 3
    # GAME_STATE contains terminal winner/turn data even if PLAYER_WON is late.
    assert "lda rx_buffer+PAYLOAD_START+16\n        sta winner_index" in protocol
    assert "local_finish_position" in protocol
    assert "player_out_flag" in protocol
    assert "process_player_won:" in protocol


def test_native_sound_and_joystick_feedback_are_non_blocking() -> None:
    main = (ROOT / "src/main.asm").read_text()
    sound = (ROOT / "src/sound.asm").read_text()
    input_source = (ROOT / "src/input.asm").read_text()
    assert "jsr sound_update\n        jsr net_recv" in main
    assert "sound_ticks:" in sound
    assert "sound_update:" in sound
    assert "sound_delay:" not in sound
    assert "get_joystick_input:" in input_source
    assert "and #$7f\n        sta VIA2_DDRB" in input_source
    assert "sta VIA2_DDRB\n        plp" in input_source
    assert "joystick_previous" in input_source
    assert "lda #KEY_RETURN" in input_source
    assert "lda #'D'" in input_source


def test_private_room_and_connection_retry_are_wired() -> None:
    main = (ROOT / "src/main.asm").read_text()
    connect = (ROOT / "src/connect.asm").read_text()
    protocol = (ROOT / "src/rubp.asm").read_text()
    assert "input_room_code:" in connect
    assert 'ROOM CODE (OPTIONAL)' in connect
    assert "cpx #8" in connect
    assert "sta tx_buffer+PAYLOAD_START+28,x" in protocol
    assert "cmp #MSG_ERROR\n        beq wfw_error" in main
    assert "wfw_error:\n        sec\n        rts" in main
    assert "R RETRY E EDIT Q QUIT" in main
    assert "jmp connect_retry" in main
    assert "jmp connect_details" in main


def test_active_game_reconnect_reclaims_and_resynchronizes() -> None:
    main = (ROOT / "src/main.asm").read_text()
    protocol = (ROOT / "src/rubp.asm").read_text()
    wifi = (ROOT / "src/net/wifi.asm").read_text()
    assert "ensure_reconnect_token:" in protocol
    assert "sta tx_buffer+PAYLOAD_START+20,x" in protocol
    assert "reconnect_token: .res 8" in protocol
    assert "track_closed_status:" in wifi
    assert "$43,$4c,$4f,$53,$45,$44" in wifi
    assert "lda #NET_ERROR\n        sta net_status" in wifi
    assert "track_send_error:" in wifi
    assert "$45,$52,$52,$4f,$52" in wifi
    assert "reconnect_active:" in main
    assert "lda #3\n        sta reconnect_attempts" in main
    assert "jsr send_hello\n        jsr wait_for_welcome" in main
    assert "jsr send_sync_request\n        jmp main_loop" in main
    assert "wfg_link_lost:\n        sec\n        rts" in main
    assert "LINK LOST-RECONNECT" in main


def test_video_capture_workflow_is_reproducible() -> None:
    capture = (ROOT / "tests/capture_video.py").read_text()
    makefile = (ROOT / "Makefile").read_text()
    assert "capture-video: e2e-prg" in makefile
    assert '"--random-seed", str(SEED)' in capture
    assert '"save_screenshot"' in capture
    assert '"libx264"' in capture
    assert '"+faststart"' in capture
    assert '"Game finished" not in server_text' in capture
    full_game = (ROOT / "tests/full_game_e2e.py").read_text()
    makefile = (ROOT / "Makefile").read_text()
    assert "e2e-eight-player: e2e-prg" in makefile
    assert 'RACHEL_E2E_AI_PLAYERS=7' in makefile
    assert "e2e-reconnect: e2e-prg" in makefile
    assert "e2e-full-game-ntsc: e2e-prg" in makefile
    assert "RACHEL_E2E_REGION=ntsc" in makefile
    assert "RACHEL_E2E_DROP_AFTER_SERVER_FRAMES=10" in makefile
    assert 'RACHEL_E2E_MIN_PLAYERS", "2"' in full_game
    assert 'RACHEL_E2E_GAME_FRAMES", "120000"' in full_game
    assert 'RACHEL_E2E_WRITE_INTERVAL", "300ms"' in full_game
    assert 'RACHEL_E2E_REGION", "pal"' in full_game
    assert '"reclaimed player" not in server_text' in full_game


def test_release_bundle_and_physical_checklist_exist() -> None:
    makefile = (ROOT / "Makefile").read_text()
    packager = (ROOT / "scripts/package_release.py").read_text()
    checklist = (ROOT / "docs/HARDWARE_TESTING.md").read_text()
    release_status = (ROOT / "docs/RELEASE_STATUS.md").read_text()
    assert "release: test" in makefile
    assert '"rachel-vic20.prg"' in packager
    assert "sha256(archive.read_bytes())" in packager
    assert "PAL or NTSC VIC-20" in checklist
    assert "Both timing sets complete" in checklist
    assert "eight-player match" in checklist
    assert '"docs/RELEASE_STATUS.md"' in packager
    assert "emulator-verified PAL/NTSC release candidate" in release_status
    assert "does **not** expose disk save/resume" in release_status


def test_sync_ack_certifies_only_state_the_client_holds() -> None:
    main = (ROOT / "src/main.asm").read_text()
    protocol = (ROOT / "src/rubp.asm").read_text()
    # HAND_SYNC carries the same state hash as the GAME_STATE ahead of it, so
    # acknowledging on HAND_SYNC alone certifies that a frame arrived rather
    # than that the public view did. On a link that discards frames routinely
    # that let the server release TURN_START against a stale discard_top.
    sync = main[main.index("ml_check_sync:"):main.index("ml_check_turn:")]
    assert "lda game_state_seen" in sync
    assert "jsr send_sync_ack" in sync
    assert "jsr send_sync_request" in sync      # recover instead of certifying
    # The flag is set where the authoritative view is actually parsed, and
    # nowhere else, or it goes back to attesting to a frame.
    state = protocol[protocol.index("process_game_state:"):protocol.index("process_card_drawn:")]
    assert "sta game_state_seen" in state
    assert protocol.count("sta game_state_seen") == 1
    # discard_top is the field that goes stale: GAME_STATE is its only source.
    assert protocol.count("sta discard_top") == 1
    turn = protocol[protocol.index("process_turn_start:"):protocol.index("pts_done:")]
    assert "discard_top" not in turn


def test_solo_kernel_spike_is_single_prg_budgeted() -> None:
    makefile = (ROOT / "Makefile").read_text()
    main = (ROOT / "src/main.asm").read_text()
    solo = (ROOT / "src/solo.asm").read_text() + "\n" + "\n".join(
        path.read_text() for path in sorted((ROOT / "src/solo").rglob("*.asm"))
    )
    assert "solo-kernel-spike:" in makefile
    assert "solo-kernel-e2e: solo-kernel-spike" in makefile
    assert "-D SOLO_KERNEL_TEST=1" in makefile
    assert '.include "solo.asm"' in main
    assert "solo_get_info:" in solo
    assert '.byte "RHKI"' in solo
    assert ".word $000d" in solo
    assert "SOLO_WS_SIZE       = 118" in solo
    assert "SOLO_MAX_PLAYERS   = 8" in solo
    assert "SOLO_SCRATCH_SIZE  = 16" in solo
    rubp = (ROOT / "src/rubp.asm").read_text()
    assert "solo_workspace:\n" in rubp
    assert "solo_scratch:   .res 16" in rubp
    budget = (ROOT / "docs/SOLO_MEMORY_BUDGET.md").read_text()
    assert "Proceed with one PRG" in budget
    assert "2,048" in budget
    # Match the table row, not a bare number: "15" also occurs inside
    # "125-byte", so the loose form passed for the wrong reason.
    assert "| Remaining first-slice implementation allowance | 286 |" in budget
    assert "RACHEL ONLINE" in budget and "RACHEL SOLO" in budget


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


def test_the_title_banner_uses_rom_glyphs_only() -> None:
    display = (ROOT / "src/display.asm").read_text()
    assert "render_logo:" in display
    logo = display[display.index("render_logo:"):display.index("logo_index:")]
    # Half-block glyphs from the character ROM, two sub-pixels per cell. A
    # redefined set would have to live in RAM below $2000, which is CODE.
    assert ".byte $20, $e1, $61, $a0" in logo
    assert "$9005" not in display and "VIC_COLADDR" not in display
    assert "lda #SCREEN_WIDTH" in logo          # a full 22-cell row
    rows = [l for l in logo[logo.index("logo_bits:"):].splitlines() if ".byte" in l]
    assert len(rows) == 5                       # five banner rows
    assert all(l.count("$") == 6 for l in rows) # six bytes each: 24 cells, 22 drawn
    title = display[display.index("display_title:"):display.index("render_logo:")]
    assert "jsr render_logo" in title and "jsr render_title_suits" in title


def test_hand_paging_keeps_the_cursor_on_screen() -> None:
    game = (ROOT / "src/game.asm").read_text()
    hand = game[game.index("render_hand:"):game.index("hand_msg:")]
    page = hand[hand.index("rh_page_ready:"):hand.index("rh_loop:")]
    # The page base must survive to the draw loop. Subtracting it back off
    # cursor_pos left X holding cursor mod 5, which scrolled the selected card
    # off the row for any hand longer than five cards.
    assert page.count("sbc ZP_TEMP1") == 1
    assert "ldx ZP_TEMP1" in hand
    assert "render_hand_page:" in game
    indicator = game[game.index("render_hand_page:"):game.index("set_card_playability:")]
    for glyph in ("lda #'<'", "lda #'>'"):
        assert glyph in indicator


def test_playability_dimming_is_solo_only() -> None:
    game = (ROOT / "src/game.asm").read_text()
    playable = game[game.index("set_card_playability:"):game.index("render_card_short:")]
    # Online play is render-only and the host owns legality: decision 0003.
    assert "lda solo_ui_active" in playable
    assert "jsr solo_card_is_legal" in playable
    assert "cmp my_index" in playable
    short = game[game.index("render_card_short:"):game.index("render_discard_card:")]
    assert "COLOR_BLUE" in short


def test_pending_attacks_and_nomination_reach_the_screen() -> None:
    game = (ROOT / "src/game.asm").read_text()
    state = game[game.index("render_table_state:"):game.index("render_help:")]
    for field in ("pending_draws", "pending_skips", "deck_count", "nominated_suit_recv"):
        assert field in state
    for message in ("DRAW ", "SKIP ", " OR PLAY A 2", " OR RED JACK",
                    " OR PLAY A 7", "DECK ", "SUIT "):
        assert f'.byte "{message}"' in game
    # Direction is tracked by both modes and now drawn beside the turn.
    direction = game[game.index("render_direction:"):game.index("render_table_state:")]
    assert "SW_PACKED_FLAGS" in direction
    assert "lda direction" in direction
    # Transient feedback must not land on the attack row and hide the one line
    # that says how to answer the attack.
    main = (ROOT / "src/main.asm").read_text()
    feedback = main[main.index("render_status:\n        sta ZP_PTR1"):]
    feedback = feedback[:feedback.index("jsr print_string")]
    assert "lda #19" in feedback and "lda #12" not in feedback
    assert state.count("jsr display_clear_row") == 3
    for row in ("lda #12", "lda #13", "lda #19"):
        assert row in state


def test_ace_nomination_is_asked_for_when_the_ace_is_played() -> None:
    game = (ROOT / "src/game.asm").read_text()
    ui = (ROOT / "src/solo/ui.asm").read_text()
    main = (ROOT / "src/main.asm").read_text()
    # One prompt, shared by both modes.
    assert "pick_suit_modal:" in game
    assert '.byte "NOMINATE ' in game
    play = ui[ui.index("sm_play:"):ui.index("sm_find_play:")]
    assert "cmp #14" in play
    assert "jsr pick_suit_modal" in play
    online = main[main.index("ml_play_selected:"):main.index("ml_send_play:")]
    assert "jsr selected_has_ace" in online
    assert "jsr pick_suit_modal" in online
    # The standing pre-selection is gone from both modes, so no Ace can be
    # nominated on a control the player never touched.
    for gone in ("sm_suit_next:", "sm_suit_prev:"):
        assert gone not in ui
    for gone in ("ml_suit_next:", "ml_suit_prev:"):
        assert gone not in main
    assert "UP/DN SUIT" not in game


def test_solo_seats_are_addressed_by_arithmetic_not_a_two_player_branch() -> None:
    solo = "\n".join(path.read_text() for path in sorted((ROOT / "src/solo").rglob("*.asm")))
    assert "solo_hand_base:" in solo
    # Every site that needs a seat's hand mask goes through the one helper, so
    # none can be left behind on the old "player 0 or player 1" branch.
    for caller in ("solo_hand_has_card:", "solo_card_mask_address:", "solo_hand_set_ordinal:"):
        body = solo[solo.index(caller):]
        assert "jsr solo_hand_base" in body[:body.index("rts")]
    layout = (ROOT / "src/solo/layout.asm").read_text()
    assert "SOLO_MAX_PLAYERS   = 8" in layout
    assert "SOLO_SEAT_BYTES    = 7" in layout


def test_turn_order_follows_direction_and_steps_over_finished_seats() -> None:
    rules = (ROOT / "src/solo/rules.asm").read_text()
    step = rules[rules.index("solo_step_player:"):rules.index("solo_advance_turn:")]
    assert "SW_PACKED_FLAGS" in step            # direction
    assert "SW_PLAYER_COUNT" in step            # wraps on the seat count
    assert "jsr solo_player_is_out" in step     # passes over finished seats
    advance = rules[rules.index("solo_advance_turn:"):rules.index("solo_has_seven:")]
    assert "eor #1" not in advance
    assert advance.count("jsr solo_step_player") == 2


def test_the_packed_deck_stops_at_its_own_last_byte() -> None:
    deck = (ROOT / "src/solo/deck.asm").read_text()
    pop = deck[deck.index("solo_deck_pop:"):deck.index("solo_hand_set_ordinal:")]
    # 52 six-bit ordinals are 39 bytes, indices 0-38. Touching +39 is
    # SW_DISCARD_COUNT, which recycling depends on.
    assert "cpx #38" in pop
    assert "lda solo_workspace+SW_PACKED_DECK+39" not in pop
    assert "sta solo_workspace+SW_PACKED_DECK+39" not in pop
    assert "sta solo_workspace+SW_PACKED_DECK+38" in pop
    layout = (ROOT / "src/solo/layout.asm").read_text()
    assert "SW_PACKED_DECK     = 21" in layout
    assert "SW_DISCARD_COUNT   = 60" in layout


def test_deal_sizes_and_finish_follow_the_rules() -> None:
    deck = (ROOT / "src/solo/deck.asm").read_text()
    # docs/GAME_RULES.md: 7 cards to five players, 6 to six and seven, 5 to eight.
    assert ".byte 7, 7, 7, 7, 6, 6, 5" in deck
    assert "solo_deal_sizes-2,x" in deck
    rules = (ROOT / "src/solo/rules.asm").read_text()
    mark = rules[rules.index("solo_mark_out_if_empty:"):rules.index("solo_step_player:")]
    assert "inc solo_workspace+SW_FINISH_COUNT" in mark
    ui = (ROOT / "src/solo/ui.asm").read_text()
    # The game is over once every seat but one has gone out.
    over = ui[ui.index("jsr render_game"):ui.index("sm_not_over:")]
    assert "SW_FINISH_COUNT" in over and "SW_PLAYER_COUNT" in over
    assert "solo_ask_players:" in ui
    assert '.byte "HOW MANY PLAYERS?"' in ui
    assert '.byte "YOU FINISH "' in ui


def test_solo_games_are_not_dealt_from_the_fixture_seed() -> None:
    ui = (ROOT / "src/solo/ui.asm").read_text()
    start = ui[ui.index("solo_mode_start:"):ui.index("sm_loop:")]
    # 42 is the fixture vector in docs/SOLO_MEMORY_BUDGET.md. Seeding the
    # interactive game with it dealt every game, and every replay, alike.
    assert "lda #42" not in start
    assert "JIFFY_LOW" in start
    assert "VIC_RASTER" in start


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
    test_the_title_banner_uses_rom_glyphs_only()
    test_hand_paging_keeps_the_cursor_on_screen()
    test_playability_dimming_is_solo_only()
    test_pending_attacks_and_nomination_reach_the_screen()
    test_ace_nomination_is_asked_for_when_the_ace_is_played()
    test_solo_games_are_not_dealt_from_the_fixture_seed()
    test_solo_seats_are_addressed_by_arithmetic_not_a_two_player_branch()
    test_turn_order_follows_direction_and_steps_over_finished_seats()
    test_the_packed_deck_stops_at_its_own_last_byte()
    test_deal_sizes_and_finish_follow_the_rules()
    test_petscii_cards_use_raw_codes_and_colour()
    test_public_table_represents_all_eight_players()
    test_player_feedback_and_terminal_result_are_wired()
    test_native_sound_and_joystick_feedback_are_non_blocking()
    test_private_room_and_connection_retry_are_wired()
    test_active_game_reconnect_reclaims_and_resynchronizes()
    test_video_capture_workflow_is_reproducible()
    test_release_bundle_and_physical_checklist_exist()
    test_sync_ack_certifies_only_state_the_client_holds()
    test_solo_kernel_spike_is_single_prg_budgeted()
    test_rubp_v2_crc_is_generated_and_required()
    test_canonical_fixture_when_supplied_by_ci()
    print("VIC-20 RUBP/PRG conformance checks passed")
