; =============================================================================
; VIC-20 RUBP PROTOCOL MODULE
; =============================================================================

; -----------------------------------------------------------------------------
; Initialize RUBP
; -----------------------------------------------------------------------------
rubp_init:
        lda #0
        sta sequence_lo
        sta sequence_hi
        sta game_id_lo
        sta game_id_hi
        sta turn_number
        sta turn_number+1
        sta turn_number+2
        sta turn_number+3
        sta state_hash_present
        sta game_over_flag
        sta chosen_suit
        ldx #7
ri_token:
        sta reconnect_token,x
        dex
        bpl ri_token
        lda #$ff
        sta player_id_lo
        sta player_id_hi
        rts

; -----------------------------------------------------------------------------
; Build message header
; Input: A = message type
; -----------------------------------------------------------------------------
build_header:
        sta ZP_TEMP1

        ; Magic bytes "RACH"
        lda #MAGIC_0
        sta tx_buffer
        lda #MAGIC_1
        sta tx_buffer+1
        lda #MAGIC_2
        sta tx_buffer+2
        lda #MAGIC_3
        sta tx_buffer+3

        ; Version
        lda #PROTOCOL_VER
        sta tx_buffer+HDR_VERSION

        ; Message type
        lda ZP_TEMP1
        sta tx_buffer+HDR_TYPE

        ; Sequence number (big-endian)
        lda sequence_hi
        sta tx_buffer+HDR_SEQ
        lda sequence_lo
        sta tx_buffer+HDR_SEQ+1

        ; Increment sequence
        inc sequence_lo
        bne bh_no_carry
        inc sequence_hi
bh_no_carry:

        ; Player ID
        lda player_id_hi
        sta tx_buffer+HDR_PLAYER_ID
        lda player_id_lo
        sta tx_buffer+HDR_PLAYER_ID+1

        ; Game ID
        lda game_id_hi
        sta tx_buffer+HDR_GAME_ID
        lda game_id_lo
        sta tx_buffer+HDR_GAME_ID+1

        ; No real-time clock is available, so use the canonical zero timestamp.
        lda #0
        sta tx_buffer+HDR_TIMESTAMP
        sta tx_buffer+HDR_TIMESTAMP+1
        sta tx_buffer+HDR_TIMESTAMP+2
        sta tx_buffer+HDR_TIMESTAMP+3

        ; Every message starts with a clean payload; optional metadata must not
        ; leak bytes from the previous frame.
        ldx #PAYLOAD_START
bh_clear:
        sta tx_buffer,x
        inx
        cpx #64
        bne bh_clear

        rts

; -----------------------------------------------------------------------------
; Finalise and validate RUBP v2 CRC-16/CCITT-FALSE frames.
; Polynomial $1021, initial value $FFFF, no reflection, xorout $0000.
; -----------------------------------------------------------------------------
rubp_finalize:
        lda #0
        sta tx_buffer+HDR_CRC
        sta tx_buffer+HDR_CRC+1
        lda #<tx_buffer
        sta ZP_PTR1
        lda #>tx_buffer
        sta ZP_PTR1+1
        jsr rubp_crc16
        lda crc_hi
        sta tx_buffer+HDR_CRC
        lda crc_lo
        sta tx_buffer+HDR_CRC+1
        rts

; ZP_PTR1 points at one 64-byte frame. Result is crc_hi:crc_lo.
rubp_crc16:
        lda #$ff
        sta crc_hi
        sta crc_lo
        ldy #0
rc_byte:
        lda (ZP_PTR1),y
        eor crc_hi
        sta crc_hi
        ldx #8
rc_bit:
        lda crc_hi
        and #$80
        sta crc_msb
        asl crc_lo
        rol crc_hi
        lda crc_msb
        beq rc_no_poly
        lda crc_lo
        eor #$21
        sta crc_lo
        lda crc_hi
        eor #$10
        sta crc_hi
rc_no_poly:
        dex
        bne rc_bit
        iny
        cpy #64
        bne rc_byte
        rts

; -----------------------------------------------------------------------------
; Send HELLO message with player name and platform ID
; -----------------------------------------------------------------------------
send_hello:
        jsr ensure_reconnect_token
        lda #MSG_HELLO
        jsr build_header

        ; Copy player name to payload bytes 0-15
        ldx #0
sh_name:
        lda player_name,x
        beq sh_name_done
        sta tx_buffer+PAYLOAD_START,x
        inx
        cpx #16
        bne sh_name
sh_name_done:

        ; Platform ID at payload bytes 16-17 (big-endian)
        ; VIC-20 = 0x000C
        lda #PLATFORM_ID_HI
        sta tx_buffer+PAYLOAD_START+16
        lda #PLATFORM_ID_LO
        sta tx_buffer+PAYLOAD_START+17

        lda #0
        sta tx_buffer+PAYLOAD_START+18
        lda #RACHEL_SPEC_VER
        sta tx_buffer+PAYLOAD_START+19

        ; The client creates and retains this token for the loaded session.
        ; Reusing it with the assigned game ID reclaims the same server seat.
        ldx #0
sh_token:
        lda reconnect_token,x
        sta tx_buffer+PAYLOAD_START+20,x
        inx
        cpx #8
        bne sh_token

        ; Optional private-room code, eight bytes and null-padded.
        ldx #0
sh_room:
        lda room_code,x
        sta tx_buffer+PAYLOAD_START+28,x
        inx
        cpx #8
        bne sh_room

        ; Advertise the existing SYNC_REQUEST acknowledgement extension.
        lda #CAP_SYNC_ACK
        sta tx_buffer+PAYLOAD_START+36

        jsr net_send
        rts

; Seed an opaque, non-zero session token once. User typing time, raster phase,
; the free-running VIA timer and connection details all contribute; the token
; then remains stable in RAM across link retries.
ensure_reconnect_token:
        lda reconnect_token
        ora reconnect_token+1
        ora reconnect_token+2
        ora reconnect_token+3
        ora reconnect_token+4
        ora reconnect_token+5
        ora reconnect_token+6
        ora reconnect_token+7
        bne ert_done
        lda JIFFY_LOW
        eor VIC_RASTER
        eor VIA1_T1CL
        eor ip_addr
        eor ip_addr+3
        eor room_code
        ora #1
        sta ZP_TEMP1
        ldx #0
ert_loop:
        lda ZP_TEMP1
        asl
        bcc ert_no_poly
        eor #$1d
ert_no_poly:
        eor VIA1_T1CL
        eor VIC_RASTER
        eor room_code,x
        sta reconnect_token,x
        sta ZP_TEMP1
        inx
        cpx #8
        bne ert_loop
ert_done:
        rts

player_name:
        ; RUBP strings are UTF-8/ASCII, not VIC PETSCII.
        .byte $56,$49,$43,$2d,$32,$30,0
        .res 9, 0               ; Pad to 16 bytes

; -----------------------------------------------------------------------------
; Send PLAY_CARDS message
; Input: nominated_suit in A
; -----------------------------------------------------------------------------
send_play_cards:
        sta nominated_suit

        lda #MSG_PLAY_CARDS
        jsr build_header

        ; Count selected cards
        jsr count_selected
        sta tx_buffer+PAYLOAD_START    ; Card count

        lda nominated_suit
        sta tx_buffer+PAYLOAD_START+33 ; Nominated suit

        lda #0
        sta tx_buffer+PAYLOAD_START+34
        lda #RACHEL_SPEC_VER
        sta tx_buffer+PAYLOAD_START+35

        lda state_hash_present
        sta tx_buffer+PAYLOAD_START+36
        beq spc_no_hash
        ldx #0
spc_hash:
        lda state_hash,x
        sta tx_buffer+PAYLOAD_START+37,x
        inx
        cpx #8
        bne spc_hash
spc_no_hash:

        ; Copy selected cards to payload
        ldx #0
        ldy #1                  ; Cards occupy payload bytes 1-32

spc_loop:
        lda selected_cards,x
        beq spc_next

        ; This card is selected
        lda my_hand,x
        sta tx_buffer+PAYLOAD_START,y
        iny

spc_next:
        inx
        cpx hand_count
        bcc spc_loop

        ; Clear selection
        ldx #31
        lda #0
spc_clear_selection:
        sta selected_cards,x
        dex
        bpl spc_clear_selection

        jsr net_send
        rts

; -----------------------------------------------------------------------------
; Count selected cards
; Returns: A = count
; -----------------------------------------------------------------------------
count_selected:
        lda #0
        sta ZP_TEMP4

        ldx #0
cs_loop:
        lda selected_cards,x
        beq cs_skip
        inc ZP_TEMP4
cs_skip:
        inx
        cpx hand_count
        bcc cs_loop

        lda ZP_TEMP4
        rts

; -----------------------------------------------------------------------------
; Send DRAW_CARD message
; -----------------------------------------------------------------------------
send_draw:
        lda #MSG_DRAW_CARD
        jsr build_header

        ; reason=0 (cannot play), count=1, RachelSpec v1
        lda #1
        sta tx_buffer+PAYLOAD_START+1
        lda #0
        sta tx_buffer+PAYLOAD_START+2
        lda #RACHEL_SPEC_VER
        sta tx_buffer+PAYLOAD_START+3

        lda state_hash_present
        sta tx_buffer+PAYLOAD_START+4
        beq sd_no_hash
        ldx #0
sd_hash:
        lda state_hash,x
        sta tx_buffer+PAYLOAD_START+5,x
        inx
        cpx #8
        bne sd_hash
sd_no_hash:

        jsr net_send
        rts

; Ask the host for a paired public/private authoritative snapshot.
send_sync_request:
        lda #MSG_SYNC_REQUEST
        jsr build_header
        ldx #0
ssr_turn:
        lda turn_number,x
        sta tx_buffer+PAYLOAD_START,x
        inx
        cpx #4
        bne ssr_turn
        lda #0
        sta tx_buffer+PAYLOAD_START+4
        lda #RACHEL_SPEC_VER
        sta tx_buffer+PAYLOAD_START+5
        lda state_hash_present
        sta tx_buffer+PAYLOAD_START+6
        beq ssr_no_hash
        ldx #0
ssr_hash:
        lda state_hash,x
        sta tx_buffer+PAYLOAD_START+7,x
        inx
        cpx #8
        bne ssr_hash
ssr_no_hash:
        jsr net_send
        rts

; Acknowledge that both the public state and private hand snapshot were parsed.
; The server validates the echoed hash before allowing this slow client to act.
send_sync_ack:
        lda #MSG_SYNC_REQUEST
        jsr build_header
        ldx #0
ssa_turn:
        lda turn_number,x
        sta tx_buffer+PAYLOAD_START,x
        inx
        cpx #4
        bne ssa_turn
        lda #0
        sta tx_buffer+PAYLOAD_START+4
        lda #RACHEL_SPEC_VER
        sta tx_buffer+PAYLOAD_START+5
        lda #(SYNC_FLAG_HASH | SYNC_FLAG_ACK)
        sta tx_buffer+PAYLOAD_START+6
        ldx #0
ssa_hash:
        lda state_hash,x
        sta tx_buffer+PAYLOAD_START+7,x
        inx
        cpx #8
        bne ssa_hash
        jsr net_send
        rts

; -----------------------------------------------------------------------------
; Validate received message
; Returns: C=0 if valid, C=1 if invalid
; -----------------------------------------------------------------------------
rubp_validate:
        lda rx_buffer
        cmp #MAGIC_0
        bne rv_fail
        lda rx_buffer+1
        cmp #MAGIC_1
        bne rv_fail
        lda rx_buffer+2
        cmp #MAGIC_2
        bne rv_fail
        lda rx_buffer+3
        cmp #MAGIC_3
        bne rv_fail

        lda rx_buffer+HDR_VERSION
        cmp #PROTOCOL_VER
        bne rv_fail

        ; Preserve the received checksum, compute over a zero checksum field,
        ; then restore the frame before any payload parser sees it.
        lda rx_buffer+HDR_CRC
        sta crc_expected_hi
        lda rx_buffer+HDR_CRC+1
        sta crc_expected_lo
        lda #0
        sta rx_buffer+HDR_CRC
        sta rx_buffer+HDR_CRC+1
        lda #<rx_buffer
        sta ZP_PTR1
        lda #>rx_buffer
        sta ZP_PTR1+1
        jsr rubp_crc16
        lda crc_expected_hi
        sta rx_buffer+HDR_CRC
        lda crc_expected_lo
        sta rx_buffer+HDR_CRC+1
        lda crc_expected_hi
        cmp crc_hi
        bne rv_fail
        lda crc_expected_lo
        cmp crc_lo
        bne rv_fail

        clc
        rts

rv_fail:
        sec
        rts

; -----------------------------------------------------------------------------
; Parse GAME_STATE message
; -----------------------------------------------------------------------------
process_game_state:
        lda rx_buffer+PAYLOAD_START
        sta current_turn

        lda rx_buffer+PAYLOAD_START+1
        sta direction

        lda rx_buffer+PAYLOAD_START+2
        sta discard_top

        lda rx_buffer+PAYLOAD_START+3
        sta nominated_suit_recv

        lda rx_buffer+PAYLOAD_START+4
        sta pending_draws

        lda rx_buffer+PAYLOAD_START+5
        sta pending_skips

        lda rx_buffer+PAYLOAD_START+6
        sta deck_count

        ; Copy player counts
        ldx #0
pgs_counts:
        lda rx_buffer+PAYLOAD_START+7,x
        sta player_counts,x
        beq pgs_next_count
        txa
        clc
        adc #1
        cmp player_count
        bcc pgs_next_count
        sta player_count
pgs_next_count:
        inx
        cpx #8
        bne pgs_counts

        lda rx_buffer+PAYLOAD_START+15
        sta game_over_flag
        lda rx_buffer+PAYLOAD_START+16
        sta winner_index
        ldx #0
pgs_turn:
        lda rx_buffer+PAYLOAD_START+17,x
        sta turn_number,x
        inx
        cpx #4
        bne pgs_turn

        lda rx_buffer+PAYLOAD_START+33
        sta player_out_mask
        ldx my_index
        lda player_bit_masks,x
        and player_out_mask
        beq pgs_still_playing
        lda #1
        bne pgs_store_out
pgs_still_playing:
        lda #0
pgs_store_out:
        sta player_out_flag

        lda #$ff
        sta local_finish_position
        ldx #0
pgs_finish:
        lda rx_buffer+PAYLOAD_START+34,x
        sta finish_order,x
        cmp my_index
        bne pgs_next_finish
        txa
        clc
        adc #1
        sta local_finish_position
pgs_next_finish:
        inx
        cpx #8
        bne pgs_finish
        lda game_over_flag
        beq pgs_finish_done
        lda winner_index
        cmp my_index
        bne pgs_finish_done
        lda player_count
        sta local_finish_position
pgs_finish_done:
        lda rx_buffer+PAYLOAD_START+23
        and #1
        sta state_hash_present
        beq pgs_done
        ldx #0
pgs_hash:
        lda rx_buffer+PAYLOAD_START+24,x
        sta state_hash,x
        inx
        cpx #8
        bne pgs_hash
pgs_done:

        rts

; WELCOME assigns the seat and game. Player IDs are canonical seat indices.
process_welcome:
        lda rx_buffer+PAYLOAD_START
        sta player_id_hi
        lda rx_buffer+PAYLOAD_START+1
        sta player_id_lo
        sta my_index
        lda rx_buffer+PAYLOAD_START+2
        sta game_id_hi
        lda rx_buffer+PAYLOAD_START+3
        sta game_id_lo
        lda rx_buffer+PAYLOAD_START+4
        sta player_count
        lda rx_buffer+PAYLOAD_START+8
        and #CAP_SYNC_ACK
        sta server_sync_ack
        rts

; PLAYER_LIST is the repeatable lobby snapshot sent after WELCOME. Its header
; is recipient-specific, so it can restore the same identity fields if the
; initial WELCOME was lost at the serial/modem boundary.
process_player_list_welcome:
        lda rx_buffer+HDR_PLAYER_ID
        sta player_id_hi
        lda rx_buffer+HDR_PLAYER_ID+1
        sta player_id_lo
        sta my_index
        lda rx_buffer+HDR_GAME_ID
        sta game_id_hi
        lda rx_buffer+HDR_GAME_ID+1
        sta game_id_lo
        lda rx_buffer+PAYLOAD_START+47
        and #CAP_SYNC_ACK
        sta server_sync_ack
        lda rx_buffer+PAYLOAD_START
        sta player_count
        rts

; GAME_START replaces the private hand with the initial deal.
process_game_start:
        lda rx_buffer+PAYLOAD_START
        cmp #33
        bcc pstart_count_ok
        lda #32
pstart_count_ok:
        sta hand_count
        ldx #0
pstart_hand:
        cpx hand_count
        bcs pstart_done
        lda rx_buffer+PAYLOAD_START+1,x
        sta my_hand,x
        inx
        bne pstart_hand
pstart_done:
        rts

; CARD_DRAWN appends a private draw without relying on public GAME_STATE.
process_card_drawn:
        lda rx_buffer+PAYLOAD_START
        sta ZP_TEMP1
        ldx #0
pcd_loop:
        cpx ZP_TEMP1
        bcs pcd_done
        lda hand_count
        cmp #32
        bcs pcd_done
        tay
        lda rx_buffer+PAYLOAD_START+1,x
        sta my_hand,y
        inc hand_count
        inx
        bne pcd_loop
pcd_done:
        rts

; HAND_SYNC replaces the hand and carries authoritative recovery metadata.
process_hand_sync:
        jsr process_game_start
        ldx #0
phs_turn:
        lda rx_buffer+PAYLOAD_START+33,x
        sta turn_number,x
        inx
        cpx #4
        bne phs_turn
        lda rx_buffer+PAYLOAD_START+39
        and #1
        sta state_hash_present
        beq phs_done
        ldx #0
phs_hash:
        lda rx_buffer+PAYLOAD_START+40,x
        sta state_hash,x
        inx
        cpx #8
        bne phs_hash
phs_done:
        rts

process_turn_start:
        lda rx_buffer+PAYLOAD_START
        sta current_turn
        ldx #0
pts_turn_number:
        lda rx_buffer+PAYLOAD_START+1,x
        sta turn_number,x
        inx
        cpx #4
        bne pts_turn_number
        lda rx_buffer+PAYLOAD_START+5
        sta pending_draws
        lda rx_buffer+PAYLOAD_START+6
        sta pending_skips
        lda rx_buffer+PAYLOAD_START+9
        and #1
        sta state_hash_present
        beq pts_done
        ldx #0
pts_hash:
        lda rx_buffer+PAYLOAD_START+10,x
        sta state_hash,x
        inx
        cpx #8
        bne pts_hash
pts_done:
        rts

process_player_won:
        lda rx_buffer+PAYLOAD_START
        sta winner_index
        ldx #0
ppw_turn:
        lda rx_buffer+PAYLOAD_START+1,x
        sta turn_number,x
        inx
        cpx #4
        bne ppw_turn
        rts

; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------
sequence_lo:    .byte 0
sequence_hi:    .byte 0
player_id_lo:   .byte 0
player_id_hi:   .byte 0
game_id_lo:     .byte 0
game_id_hi:     .byte 0
reconnect_token: .res 8, 0
nominated_suit: .byte $FF
chosen_suit:     .byte 0

; Game state
current_turn:       .byte 0
direction:          .byte 0
discard_top:        .byte 0
nominated_suit_recv: .byte $FF
pending_draws:      .byte 0
pending_skips:      .byte 0
deck_count:         .byte 0
my_index:           .byte 0
player_count:       .byte 0
player_counts:      .res 8, 0
player_out_mask:    .byte 0
player_out_flag:    .byte 0
finish_order:       .res 8, $ff
local_finish_position: .byte $ff
my_hand:            .res 52, 0
turn_number:        .res 4, 0
state_hash:         .res 8, 0
state_hash_present: .byte 0
server_sync_ack:     .byte 0
game_over_flag:     .byte 0
winner_index:        .byte $ff
player_bit_masks:
        .byte $01, $02, $04, $08, $10, $20, $40, $80
crc_hi:             .byte 0
crc_lo:             .byte 0
crc_msb:            .byte 0
crc_expected_hi:    .byte 0
crc_expected_lo:    .byte 0

; Buffers. Solo mode deliberately aliases these labels: its workspace spans
; both 64-byte frames. The scratch area no longer fits inside them, so it has
; its own storage rather than a split that would overlap the workspace.
solo_workspace:
tx_buffer:      .res 64, 0
rx_buffer:      .res 64, 0
solo_scratch:   .res 16, 0
