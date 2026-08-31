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
        jsr sound_init
        jsr net_init
        jsr rubp_init
.ifdef SOLO_KERNEL_TEST
        jsr solo_fixture_load
        jsr solo_fixture_validate
        bcs skt_fail
        jsr solo_apply_fixture_validate
        bcs skt_fail
        jsr solo_draw_fixture_validate
        bcs skt_fail
        jsr solo_rng_fixture_validate
        bcs skt_fail
        jsr solo_recycle_fixture_validate
        bcs skt_fail
        jsr solo_new_game_fixture_validate
        bcs skt_fail
        jsr solo_persistence_fixture_validate
        bcc skt_ok
skt_fail:
        lda #$ff
        bne skt_store
skt_ok:
        lda #$a5
skt_store:
        sta solo_fixture_result
.endif
        jsr display_title

        ; GETIN is fed by the KERNAL IRQ keyboard scanner. Keep interrupts
        ; enabled during UI/gameplay; the serial byte routines mask them only
        ; for the duration of each timing-critical 8N1 transfer.
        cli

        ; Wait for keypress
        jsr wait_key

connect_details:
        ; Get server address and optional private-room code.
        jsr input_ip_address
        jsr input_room_code

connect_retry:
        ; Connect to server
        jsr do_connect
        bcc conn_ok
        jmp conn_failed
conn_ok:

        ; Send HELLO with player name and platform ID
        jsr send_hello

        ; Complete the handshake before waiting for the private initial deal.
        jsr wait_for_welcome
        bcc welcome_ok
        jsr net_close
        jmp conn_failed
welcome_ok:

        ; Wait for game to start
        jsr wait_for_game
        bcc game_started
        jmp reconnect_active

        ; Main game loop
game_started:
main_loop:
        jsr sound_update
        jsr net_recv
        bcs ml_no_msg

        jsr rubp_validate
        bcs ml_no_msg

        lda rx_buffer+HDR_TYPE
        cmp #MSG_GAME_STATE
        bne ml_check_drawn

        jsr process_game_state
        jsr render_game
        lda game_over_flag
        beq ml_input
        jmp game_over

ml_check_drawn:
        cmp #MSG_CARD_DRAWN
        bne ml_check_sync
        jsr process_card_drawn
        jsr render_hand
        jmp ml_input

ml_check_sync:
        cmp #MSG_HAND_SYNC
        bne ml_check_turn
        jsr process_hand_sync
        jsr render_hand
        lda server_sync_ack
        beq ml_sync_no_ack
        jsr send_sync_ack
ml_sync_no_ack:
        jmp ml_input

ml_check_turn:
        cmp #MSG_TURN_START
        bne ml_check_error
        jsr process_turn_start
        jsr render_game
.ifdef E2E_AUTOPLAY
        lda #0
        sta autoplay_waiting
.endif
        jmp ml_input

ml_check_error:
        cmp #MSG_ERROR
        bne ml_check_end
        jsr sound_error
        jsr render_rejected
        jsr send_sync_request
        jmp main_loop

ml_check_end:
        cmp #MSG_PLAYER_WON
        bne ml_no_msg
        jsr process_player_won
        jmp player_won

ml_no_msg:
        lda net_status
        and #NET_ERROR
        bne reconnect_active
ml_input:
        ; Check if it's our turn
        lda current_turn
        cmp my_index
        beq ml_our_turn
        jmp main_loop

reconnect_active:
        lda #3
        sta reconnect_attempts
ra_try:
        jsr display_clear
        lda #<msg_reconnecting
        sta ZP_PTR1
        lda #>msg_reconnecting
        sta ZP_PTR1+1
        lda #7
        jsr print_centered
        jsr do_connect
        bcs ra_failed
        jsr send_hello
        jsr wait_for_welcome
        bcs ra_failed
        jsr send_sync_request
        jmp main_loop
ra_failed:
        dec reconnect_attempts
        bne ra_try
        jsr display_clear
        lda #<msg_reconnect_failed
        sta ZP_PTR1
        lda #>msg_reconnect_failed
        sta ZP_PTR1+1
        lda #6
        jsr print_centered
        lda #<msg_reconnect_choice
        sta ZP_PTR1
        lda #>msg_reconnect_choice
        sta ZP_PTR1+1
        lda #9
        jsr print_centered
ra_wait:
        jsr wait_key
        cmp #'R'
        beq reconnect_active
        cmp #'r'
        beq reconnect_active
        cmp #'Q'
        beq ra_quit
        cmp #'q'
        beq ra_quit
        jmp ra_wait
ra_quit:
        jmp quit_game
ml_our_turn:

.ifdef E2E_AUTOPLAY
        jsr autoplay_turn
        jmp main_loop
.endif

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
        cmp #KEY_UP
        beq ml_suit_next
        cmp #KEY_DOWN
        beq ml_suit_prev
        cmp #KEY_RETURN
        beq ml_play
        cmp #'D'
        beq ml_draw
        cmp #'d'
        beq ml_draw
        jmp main_loop

ml_left:
        jsr sound_move
        jsr cursor_left
        jsr render_hand
        jmp main_loop

ml_right:
        jsr sound_move
        jsr cursor_right
        jsr render_hand
        jmp main_loop

ml_select:
        jsr sound_select
        jsr toggle_select
        jsr render_hand
        jmp main_loop

ml_suit_next:
        jsr sound_move
        lda chosen_suit
        clc
        adc #1
        and #3
        sta chosen_suit
        jsr render_help
        jsr render_hand
        jmp main_loop

ml_suit_prev:
        jsr sound_move
        lda chosen_suit
        sec
        sbc #1
        and #3
        sta chosen_suit
        jsr render_help
        jsr render_hand
        jmp main_loop

ml_play:
        jsr count_selected
        bne ml_play_selected
        jsr render_no_selection
        jmp main_loop           ; Nothing selected
ml_play_selected:
        jsr selected_has_ace
        bcc ml_no_nomination
        lda chosen_suit
        bcs ml_send_play
ml_no_nomination:
        lda #$FF
ml_send_play:
        pha
        jsr sound_action
        jsr render_play_sent
        pla
        jsr send_play_cards
        jmp main_loop

ml_draw:
        jsr sound_action
        jsr render_draw_sent
        jsr send_draw
        jmp main_loop

conn_failed:
        jsr display_clear
        lda #<msg_conn_fail
        sta ZP_PTR1
        lda #>msg_conn_fail
        sta ZP_PTR1+1
        lda #5
        jsr print_centered
        lda #<msg_retry
        sta ZP_PTR1
        lda #>msg_retry
        sta ZP_PTR1+1
        lda #8
        jsr print_centered
        jsr wait_key
        cmp #'R'
        beq cf_retry
        cmp #'r'
        beq cf_retry
        cmp #'E'
        beq cf_edit
        cmp #'e'
        beq cf_edit
        jmp quit_game
cf_retry:
        jmp connect_retry
cf_edit:
        jmp connect_details

game_over:
        jsr sound_finish
        jsr display_clear
        lda winner_index
        cmp my_index
        bne go_finished
        lda #<msg_you_lose
        sta ZP_PTR1
        lda #>msg_you_lose
        sta ZP_PTR1+1
        lda #6
        jsr print_centered
        jmp go_loser
go_finished:
        lda #4
        sta ZP_CURSOR_X
        lda #6
        sta ZP_CURSOR_Y
        lda #<msg_you_finish
        sta ZP_PTR1
        lda #>msg_you_finish
        sta ZP_PTR1+1
        jsr print_string
        lda local_finish_position
        clc
        adc #'0'
        jsr print_char
go_loser:
        lda #2
        sta ZP_CURSOR_X
        lda #9
        sta ZP_CURSOR_Y
        lda #<msg_player
        sta ZP_PTR1
        lda #>msg_player
        sta ZP_PTR1+1
        jsr print_string
        lda winner_index
        clc
        adc #'1'
        jsr print_char
        lda #<msg_holds_cards
        sta ZP_PTR1
        lda #>msg_holds_cards
        sta ZP_PTR1+1
        jsr print_string
go_turns:
        lda #6
        sta ZP_CURSOR_X
        lda #12
        sta ZP_CURSOR_Y
        lda #<msg_turns
        sta ZP_PTR1
        lda #>msg_turns
        sta ZP_PTR1+1
        jsr print_string
        lda turn_number+3
        jsr print_hex
        lda #1
        sta ZP_CURSOR_X
        lda #16
        sta ZP_CURSOR_Y
        lda #<msg_press_key
        sta ZP_PTR1
        lda #>msg_press_key
        sta ZP_PTR1+1
        jsr print_string
        jsr wait_key

quit_game:
        jsr net_close
        cli
        rts

.endproc

; Returns carry set if any selected card is an ace.
.proc selected_has_ace
        ldx #0
sha_loop:
        cpx hand_count
        bcs sha_none
        lda selected_cards,x
        beq sha_next
        lda my_hand,x
        and #$0f
        cmp #RANK_ACE
        beq sha_yes
sha_next:
        inx
        bne sha_loop
sha_none:
        clc
        rts
sha_yes:
        sec
        rts
.endproc

; -----------------------------------------------------------------------------
; Wait for game to start
; -----------------------------------------------------------------------------
.proc wait_for_welcome
wfw_loop:
        jsr net_recv
        bcc wfw_frame
        lda net_status
        and #NET_ERROR
        bne wfw_error
        jmp wfw_loop
wfw_frame:
        jsr rubp_validate
        bcs wfw_loop
        lda rx_buffer+HDR_TYPE
        cmp #MSG_WELCOME
        beq wfw_welcome
        ; PLAYER_LIST is sent after WELCOME and carries enough authoritative
        ; header state to recover if the one-shot WELCOME frame was lost while
        ; the modem transitioned out of CIPSEND mode.
        cmp #MSG_PLAYER_LIST
        beq wfw_player_list
        cmp #MSG_ERROR
        beq wfw_error
        jmp wfw_loop
wfw_player_list:
        jsr process_player_list_welcome
        clc
        rts
wfw_welcome:
        jsr process_welcome
        clc
        rts
wfw_error:
        sec
        rts
.endproc

; -----------------------------------------------------------------------------
; Wait for game to start
; -----------------------------------------------------------------------------
.proc wait_for_game
        lda #0
        sta wait_game_lo
        sta wait_game_hi
        jsr render_waiting

wfg_loop:
        jsr net_recv
        bcc wfg_message
        lda net_status
        and #NET_ERROR
        bne wfg_link_lost
        inc wait_game_lo
        bne wfg_loop
        inc wait_game_hi
        lda wait_game_hi
        cmp #$08
        bcc wfg_loop
        ; Pull a quiet authoritative snapshot if the initial unsolicited burst
        ; crossed a software-UART boundary badly enough to lose GAME_STATE.
        lda #0
        sta wait_game_lo
        sta wait_game_hi
        jsr send_sync_request
        jmp wfg_loop
wfg_message:
        lda #0
        sta wait_game_lo
        sta wait_game_hi

        jsr rubp_validate
        bcs wfg_loop

        lda rx_buffer+HDR_TYPE
        cmp #MSG_GAME_START
        beq wfg_start
        cmp #MSG_HAND_SYNC
        beq wfg_sync
        cmp #MSG_GAME_STATE
        beq wfg_state
        cmp #MSG_PLAYER_LIST
        bne wfg_loop
        jsr process_player_list_welcome
        jsr render_waiting
        jmp wfg_loop

wfg_state:
        jsr process_game_state
        clc
        rts
wfg_start:
        jsr process_game_start
        ; A public GAME_STATE follows and supplies turn/table state.
        jmp wfg_loop
wfg_sync:
        jsr process_hand_sync
        jmp wfg_loop
wfg_link_lost:
        sec
        rts
.endproc

render_waiting:
        jsr display_clear
        lda #<msg_waiting
        sta ZP_PTR1
        lda #>msg_waiting
        sta ZP_PTR1+1
        lda #5
        jsr print_centered
        lda #6
        sta ZP_CURSOR_X
        lda #8
        sta ZP_CURSOR_Y
        lda #<msg_players
        sta ZP_PTR1
        lda #>msg_players
        sta ZP_PTR1+1
        jsr print_string
        lda player_count
        clc
        adc #'0'
        jsr print_char
        rts

render_play_sent:
        lda #<msg_play_sent
        ldx #>msg_play_sent
        bne render_status
render_draw_sent:
        lda #<msg_draw_sent
        ldx #>msg_draw_sent
        bne render_status
render_rejected:
        lda #<msg_rejected
        ldx #>msg_rejected
        bne render_status
render_no_selection:
        lda #<msg_select_card
        ldx #>msg_select_card
render_status:
        sta ZP_PTR1
        stx ZP_PTR1+1
        lda #0
        sta ZP_CURSOR_X
        lda #12
        sta ZP_CURSOR_Y
        jsr print_string
        rts

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
msg_waiting:
        .byte "WAITING FOR GAME", 0
msg_players:
        .byte "PLAYERS: ", 0
msg_conn_fail:
        .byte "CONNECTION FAILED", 0
msg_retry:
        .byte "R RETRY E EDIT Q QUIT", 0
msg_reconnecting:
        .byte "LINK LOST-RECONNECT", 0
msg_reconnect_failed:
        .byte "RECONNECT FAILED", 0
msg_reconnect_choice:
        .byte "R RETRY Q QUIT", 0
msg_you_lose:
        .byte "YOU LOSE!", 0
msg_you_finish:
        .byte "YOU FINISH: ", 0
msg_player:
        .byte "P", 0
msg_holds_cards:
        .byte " HOLDS THE CARDS", 0
msg_turns:
        .byte "TURNS: ", 0
msg_press_key:
        .byte "PRESS KEY TO FINISH", 0
msg_play_sent:
        .byte "PLAY SENT           ", 0
msg_draw_sent:
        .byte "DRAW SENT           ", 0
msg_rejected:
        .byte "MOVE REJECTED-RETRY ", 0
msg_select_card:
        .byte "SELECT A CARD FIRST ", 0
wait_game_lo:
        .byte 0
wait_game_hi:
        .byte 0
reconnect_attempts:
        .byte 0

; -----------------------------------------------------------------------------
; Include modules
; -----------------------------------------------------------------------------
.include "display.asm"
.include "input.asm"
.include "sound.asm"
.include "net/wifi.asm"
.include "rubp.asm"
.include "solo.asm"
.include "game.asm"
.include "connect.asm"

player_won:
        lda #1
        sta game_over_flag
        jmp main::game_over

.ifdef E2E_AUTOPLAY
; Test-build policy that drives the ordinary action encoders through a complete
; server-authoritative game. It deliberately plays only one card at a time.
; Production builds contain none of this code.
autoplay_turn:
        lda autoplay_waiting
        beq ap_ready
        jmp ap_done
ap_ready:
        lda #1
        sta autoplay_waiting

        ; An active draw/skip attack can only be countered by the rank on top.
        lda pending_draws
        ora pending_skips
        beq ap_normal
        lda discard_top
        and #$0f
        sta ZP_TEMP1
        jmp ap_find_rank

ap_normal:
        ldx #0
ap_scan:
        cpx hand_count
        bcc ap_have_card
        jmp ap_draw
ap_have_card:
        lda my_hand,x
        and #$0f
        cmp #RANK_ACE
        beq ap_ace
        sta ZP_TEMP1
        lda nominated_suit_recv
        cmp #$ff
        bne ap_match_nomination
        lda discard_top
        and #$0f
        cmp ZP_TEMP1
        beq ap_play
        lda my_hand,x
        jsr autoplay_card_suit
        sta ZP_TEMP1
        lda discard_top
        jsr autoplay_card_suit
        cmp ZP_TEMP1
        beq ap_play
        inx
        bne ap_scan

ap_match_nomination:
        sta ZP_TEMP1
        lda my_hand,x
        jsr autoplay_card_suit
        cmp ZP_TEMP1
        beq ap_play
        inx
        bne ap_scan

ap_ace:
        ; An Ace is a wildcard only while a previous Ace's nomination is live;
        ; otherwise it must match the top card's suit or rank like any card.
        lda nominated_suit_recv
        cmp #$ff
        bne ap_play_ace
        lda discard_top
        and #$0f
        cmp #RANK_ACE
        beq ap_play_ace
        lda my_hand,x
        jsr autoplay_card_suit
        sta ZP_TEMP1
        lda discard_top
        jsr autoplay_card_suit
        cmp ZP_TEMP1
        bne ap_next
ap_play_ace:
        lda #SUIT_HEARTS
        sta chosen_suit
        jmp ap_play
ap_next:
        inx
        bne ap_scan

ap_find_rank:
        ldx #0
ap_rank_scan:
        cpx hand_count
        bcs ap_draw
        lda my_hand,x
        and #$0f
        cmp ZP_TEMP1
        beq ap_play
        inx
        bne ap_rank_scan

ap_play:
        lda #1
        sta selected_cards,x
        lda my_hand,x
        and #$0f
        cmp #RANK_ACE
        beq ap_nominate
        lda #$ff
        bne ap_send_play
ap_nominate:
        lda chosen_suit
ap_send_play:
        jsr send_play_cards
        rts
ap_draw:
        jsr send_draw
ap_done:
        rts

autoplay_card_suit:
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        and #$03
        rts

autoplay_waiting:
        .byte 0
.endif
