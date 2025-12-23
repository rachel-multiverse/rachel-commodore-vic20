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
        sta player_id_lo
        sta player_id_hi
        sta game_id_lo
        sta game_id_hi
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

        ; Flags and reserved
        lda #0
        sta tx_buffer+HDR_FLAGS
        sta tx_buffer+HDR_RESERVED

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

        ; Checksum (placeholder)
        lda #0
        sta tx_buffer+HDR_CHECKSUM
        sta tx_buffer+HDR_CHECKSUM+1

        rts

; -----------------------------------------------------------------------------
; Send HELLO message with player name and platform ID
; -----------------------------------------------------------------------------
send_hello:
        lda #MSG_HELLO
        jsr build_header

        ; Clear payload first
        ldx #PAYLOAD_START
        lda #0
sh_clear:
        sta tx_buffer,x
        inx
        cpx #64
        bne sh_clear

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

        jsr net_send
        rts

player_name:
        .byte "VIC-20", 0
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
        sta tx_buffer+PAYLOAD_START+1  ; Nominated suit

        ; Copy selected cards to payload
        ldx #0
        ldy #2                  ; Start at payload+2
        lda selected_lo
        sta ZP_TEMP1
        lda selected_hi
        sta ZP_TEMP2

spc_loop:
        lda ZP_TEMP1
        and #1
        beq spc_next

        ; This card is selected
        lda my_hand,x
        sta tx_buffer+PAYLOAD_START,y
        iny

spc_next:
        ; Shift selection bits right
        lsr ZP_TEMP2
        ror ZP_TEMP1
        inx
        cpx hand_count
        bcc spc_loop

        ; Clear selection
        lda #0
        sta selected_lo
        sta selected_hi

        jsr net_send
        rts

; -----------------------------------------------------------------------------
; Count selected cards
; Returns: A = count
; -----------------------------------------------------------------------------
count_selected:
        lda #0
        sta ZP_TEMP4

        lda selected_lo
        sta ZP_TEMP1
        lda selected_hi
        sta ZP_TEMP2

        ldx #16
cs_loop:
        lsr ZP_TEMP2
        ror ZP_TEMP1
        bcc cs_skip
        inc ZP_TEMP4
cs_skip:
        dex
        bne cs_loop

        lda ZP_TEMP4
        rts

; -----------------------------------------------------------------------------
; Send DRAW_CARD message
; -----------------------------------------------------------------------------
send_draw:
        lda #MSG_DRAW_CARD
        jsr build_header

        ; Clear payload
        ldx #PAYLOAD_START
        lda #0
sd_clear:
        sta tx_buffer,x
        inx
        cpx #64
        bne sd_clear

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

        ; Copy player counts
        ldx #0
pgs_counts:
        lda rx_buffer+PAYLOAD_START+6,x
        sta player_counts,x
        inx
        cpx #8
        bne pgs_counts

        ; My index and hand count
        lda rx_buffer+PAYLOAD_START+14
        sta my_index

        lda rx_buffer+PAYLOAD_START+15
        sta hand_count

        ; Copy hand
        ldx #0
pgs_hand:
        cpx hand_count
        bcs pgs_done
        lda rx_buffer+PAYLOAD_START+16,x
        sta my_hand,x
        inx
        bne pgs_hand

pgs_done:
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
nominated_suit: .byte $FF

; Game state
current_turn:       .byte 0
direction:          .byte 0
discard_top:        .byte 0
nominated_suit_recv:.byte $FF
pending_draws:      .byte 0
pending_skips:      .byte 0
my_index:           .byte 0
player_counts:      .res 8, 0
my_hand:            .res 16, 0

; Buffers
tx_buffer:      .res 64, 0
rx_buffer:      .res 64, 0
