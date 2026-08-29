; =============================================================================
; RACHEL - VIC-20 MAIN MODULE
; 6502 Assembly (ca65 syntax) - Entry point and main loop
; Requires 8KB+ memory expansion
; =============================================================================

.segment "BASIC"

; BASIC line 10: SYS 4624 ($1210). This makes the documented LOAD/RUN flow
; enter machine code instead of asking BASIC to interpret opcodes as tokens.
        .word basic_end
        .word 10
        .byte $9e
        .byte "4624", 0
basic_end:
        .word 0

.segment "CODE"

.include "equates.asm"

; -----------------------------------------------------------------------------
; Entry Point
; -----------------------------------------------------------------------------
.proc main
        sei

        jsr display_init
        jsr input_init
        jsr net_init
        jsr rubp_init
        jsr display_title

        ; Wait for keypress
        jsr wait_key

        ; Get server address
        jsr input_ip_address

        ; Connect to server
        jsr do_connect
        bcc conn_ok
        jmp conn_failed
conn_ok:

        ; Send HELLO with player name and platform ID
        jsr send_hello

        ; Complete the handshake before waiting for the private initial deal.
        jsr wait_for_welcome

        ; Wait for game to start
        jsr wait_for_game

        ; Main game loop
main_loop:
        jsr net_recv
        bcs ml_no_msg

        jsr rubp_validate
        bcs ml_no_msg

        lda rx_buffer+HDR_TYPE
        cmp #MSG_GAME_STATE
        bne ml_check_drawn

        jsr process_game_state
        jsr render_game
        jmp ml_input

ml_check_drawn:
        cmp #MSG_CARD_DRAWN
        bne ml_check_sync
        jsr process_card_drawn
        jsr render_hand
        jmp ml_input

ml_check_sync:
        cmp #MSG_HAND_SYNC
        bne ml_check_end
        jsr process_game_start
        jsr render_hand
        jmp ml_input

ml_check_end:
        cmp #MSG_PLAYER_WON
        bne ml_no_msg
        jmp game_over

ml_no_msg:
ml_input:
        ; Check if it's our turn
        lda current_turn
        cmp my_index
        bne main_loop

        ; Handle input
        jsr get_input
        cmp #KEY_ESC
        bne ml_not_quit
        jmp quit_game
ml_not_quit:
        cmp #KEY_LEFT
        beq ml_left
        cmp #KEY_RIGHT
        beq ml_right
        cmp #KEY_SPACE
        beq ml_select
        cmp #KEY_RETURN
        beq ml_play
        cmp #'D'
        beq ml_draw
        cmp #'d'
        beq ml_draw
        jmp main_loop

ml_left:
        jsr cursor_left
        jsr render_hand
        jmp main_loop

ml_right:
        jsr cursor_right
        jsr render_hand
        jmp main_loop

ml_select:
        jsr toggle_select
        jsr render_hand
        jmp main_loop

ml_play:
        jsr count_selected
        bne ml_play_selected
        jmp main_loop           ; Nothing selected
ml_play_selected:
        lda #$FF                ; No suit nomination
        jsr send_play_cards
        jmp main_loop

ml_draw:
        jsr send_draw
        jmp main_loop

conn_failed:
        jsr display_clear
        lda #0
        sta ZP_CURSOR_X
        lda #5
        sta ZP_CURSOR_Y
        lda #<msg_conn_fail
        sta ZP_PTR1
        lda #>msg_conn_fail
        sta ZP_PTR1+1
        jsr print_string
        jsr wait_key
        jmp quit_game

game_over:
        jsr display_clear
        lda #0
        sta ZP_CURSOR_X
        lda #10
        sta ZP_CURSOR_Y
        lda #<msg_game_over
        sta ZP_PTR1
        lda #>msg_game_over
        sta ZP_PTR1+1
        jsr print_string
        jsr wait_key

quit_game:
        jsr net_close
        cli
        rts

.endproc

; -----------------------------------------------------------------------------
; Wait for game to start
; -----------------------------------------------------------------------------
.proc wait_for_welcome
wfw_loop:
        jsr net_recv
        bcs wfw_loop
        jsr rubp_validate
        bcs wfw_loop
        lda rx_buffer+HDR_TYPE
        cmp #MSG_WELCOME
        bne wfw_loop
        jsr process_welcome
        rts
.endproc

; -----------------------------------------------------------------------------
; Wait for game to start
; -----------------------------------------------------------------------------
.proc wait_for_game
        jsr display_clear
        lda #0
        sta ZP_CURSOR_X
        lda #5
        sta ZP_CURSOR_Y
        lda #<msg_waiting
        sta ZP_PTR1
        lda #>msg_waiting
        sta ZP_PTR1+1
        jsr print_string

wfg_loop:
        jsr net_recv
        bcs wfg_loop

        jsr rubp_validate
        bcs wfg_loop

        lda rx_buffer+HDR_TYPE
        cmp #MSG_GAME_START
        beq wfg_start
        cmp #MSG_GAME_STATE
        bne wfg_loop

        jsr process_game_state
        rts
wfg_start:
        jsr process_game_start
        ; A public GAME_STATE follows and supplies turn/table state.
        jmp wfg_loop
.endproc

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
msg_waiting:
        .byte "WAITING FOR GAME...", 0
msg_conn_fail:
        .byte "CONNECTION FAILED", 0
msg_game_over:
        .byte "GAME OVER!", 0

; -----------------------------------------------------------------------------
; Include modules
; -----------------------------------------------------------------------------
.include "display.asm"
.include "input.asm"
.include "rubp.asm"
.include "game.asm"
.include "connect.asm"
.include "net/wifi.asm"
