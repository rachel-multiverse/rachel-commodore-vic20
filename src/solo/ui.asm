; =============================================================================
; RACHEL COMPACT TWO-PLAYER SOLO WORKSPACE BINDING
; =============================================================================
;
; Offline lifetime only: the 80-byte constrained_2p_v2 workspace overlays the
; first 80 bytes of the contiguous RUBP TX/RX buffers. Its 16 scratch bytes use
; RX offsets 16-31. Online code and solo code must never be live together.
;
; Public entry points in this module follow docs/ASSEMBLY_CONVENTIONS.md.

SOLO_WS_SIZE       = 80
SOLO_SCRATCH_SIZE  = 16

SW_LAYOUT_VERSION  = 0
SW_PLAYER_COUNT    = 1
SW_CURRENT_PLAYER  = 2
SW_PACKED_FLAGS    = 3
SW_PENDING_DRAWS   = 4
SW_PENDING_SKIPS   = 5
SW_TURN_NUMBER     = 6
SW_RANDOM_SEED     = 10
SW_FINISH_COUNT    = 18
SW_FINISH_ORDER    = 19
SW_DECK_COUNT      = 20
SW_PACKED_DECK     = 21
SW_DISCARD_COUNT   = 60
SW_TOP_DISCARD     = 61
SW_HAND_MASKS      = 62

SOLO_ACTION_PLAY   = 0
SOLO_ACTION_DRAW   = 1
SOLO_NO_SUIT       = $ff
SOLO_SAVE_BYTES    = 87
SOLO_INFO_BYTES    = 19

.assert rx_buffer-tx_buffer = 64, error, "RUBP buffers must remain contiguous"
.assert tx_buffer+SOLO_WS_SIZE = solo_scratch, error, "solo workspace must end at scratch"
.assert solo_scratch+SOLO_SCRATCH_SIZE <= rx_buffer+64, error, "solo scratch exceeds RX overlay"
.assert SW_HAND_MASKS+14 <= SOLO_WS_SIZE, error, "two hand masks exceed solo workspace"

; GET_INFO-compatible compact-port descriptor at ZP_PTR1. It uses the shared
; RHKI envelope but advertises only what this allocation-free two-player port
; actually exposes: deterministic indexed actions, opaque workspace and no
; dynamic allocation. Full action tables and binary apply summaries are zero.
; In:  ZP_PTR1 -> at least SOLO_INFO_BYTES writable bytes.
; Out: descriptor copied; A=SOLO_INFO_BYTES, Y=SOLO_INFO_BYTES.
; Clobbers: A, Y and memory at ZP_PTR1. Preserves: X.
solo_get_info:
        ldy #0
sgi_copy:
        lda solo_info_data,y
        sta (ZP_PTR1),y
        iny
        cpy #SOLO_INFO_BYTES
        bcc sgi_copy
        rts

solo_info_data:
        .byte "RHKI"
        .word 1                  ; kernel ABI
        .word 1                  ; RachelSpec
        .byte 2,2                ; fixed two-player profile
        .byte 112,7              ; action count / portable action bytes
        .word 0                  ; no resident full action table
        .word 0                  ; no binary apply-summary buffer
        .byte 53                 ; count + maximum hand
        .word $000d              ; order, opaque workspace, no allocation

; Complete offline front end. The compact kernel remains the sole authority:
; keyboard/joystick input is accepted only by finding its exact catalogue
; action. Human play is deliberately one card at a time.
; In: none. Does not return; exits to main through the mode menu.
; Clobbers: A, X, Y, shared UI state and the complete solo workspace.
solo_mode_start:
        lda #1
        sta solo_ui_active
        jsr display_clear
        lda #0
        ldx #7
sm_seed_clear:
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl sm_seed_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        jsr solo_new_game
        lda #0
        sta cursor_pos
        sta chosen_suit
sm_loop:
        jsr solo_sync_ui
        jsr render_game
        lda solo_workspace+SW_FINISH_COUNT
        beq sm_not_over
        jmp sm_game_over
sm_not_over:
        lda solo_workspace+SW_CURRENT_PLAYER
        beq sm_human
        jsr solo_ai_take_turn
        bcc sm_loop
        jmp sm_rejected
sm_human:
        jsr sound_update
        jsr get_input
        beq sm_human
        cmp #KEY_ESC
        bne sm_not_title
        jmp sm_title
sm_not_title:
        cmp #KEY_LEFT
        beq sm_left
        cmp #KEY_RIGHT
        beq sm_right
        cmp #KEY_UP
        beq sm_suit_next
        cmp #KEY_DOWN
        beq sm_suit_prev
        cmp #KEY_RETURN
        beq sm_play
        cmp #KEY_SPACE
        beq sm_play
        cmp #'D'
        bne sm_not_draw_upper
        jmp sm_draw
sm_not_draw_upper:
        cmp #'d'
        bne sm_unknown_key
        jmp sm_draw
sm_unknown_key:
        jmp sm_human
sm_left:
        jsr sound_move
        jsr cursor_left
        jsr render_hand
        jmp sm_human
sm_right:
        jsr sound_move
        jsr cursor_right
        jsr render_hand
        jmp sm_human
sm_suit_next:
        jsr sound_move
        inc chosen_suit
        lda chosen_suit
        and #3
        sta chosen_suit
        jsr render_help
        jsr render_hand
        jmp sm_human
sm_suit_prev:
        jsr sound_move
        lda chosen_suit
        sec
        sbc #1
        and #3
        sta chosen_suit
        jsr render_help
        jsr render_hand
        jmp sm_human
sm_play:
        lda hand_count
        beq sm_rejected
        ldx cursor_pos
        lda my_hand,x
        sta solo_ui_card
        lda #0
        sta solo_ui_action
sm_find_play:
        lda solo_ui_action
        jsr solo_get_action_at
        bcs sm_rejected
        lda solo_action_kind
        bne sm_next_action
        lda solo_ui_card
        and #$0f
        cmp solo_action_rank
        bne sm_next_action
        lda solo_ui_card
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        tax
        lda solo_bit_table,x
        cmp solo_action_suit_mask
        bne sm_next_action
        lda solo_action_rank
        cmp #14
        bne sm_non_ace
        lda solo_action_nomination
        cmp chosen_suit
        bne sm_next_action
        beq sm_apply
sm_non_ace:
        lda solo_action_nomination
        cmp #SOLO_NO_SUIT
        bne sm_next_action
sm_apply:
        lda solo_ui_action
        jsr solo_apply_action
        bcs sm_rejected
        jsr sound_action
        jmp sm_loop
sm_next_action:
        inc solo_ui_action
        bne sm_find_play
sm_draw:
        lda #0
        sta solo_ui_action
sm_find_draw:
        lda solo_ui_action
        jsr solo_get_action_at
        bcs sm_rejected
        lda solo_action_kind
        cmp #SOLO_ACTION_DRAW
        beq sm_apply
        inc solo_ui_action
        bne sm_find_draw
sm_rejected:
        jsr sound_error
        jsr render_rejected
        jmp sm_human
sm_title:
        jmp main

sm_game_over:
        jsr sound_finish
        jsr display_clear
        lda solo_workspace+SW_FINISH_ORDER
        bne sm_lost
        lda #<solo_win_msg
        sta ZP_PTR1
        lda #>solo_win_msg
        bne sm_result
sm_lost:
        lda #<solo_lose_msg
        sta ZP_PTR1
        lda #>solo_lose_msg
sm_result:
        sta ZP_PTR1+1
        lda #7
        jsr print_centered
        lda #<solo_replay_msg
        sta ZP_PTR1
        lda #>solo_replay_msg
        sta ZP_PTR1+1
        lda #10
        jsr print_centered
sm_game_wait:
        jsr wait_key
        cmp #'R'
        bne sm_not_replay_upper
        jmp solo_mode_start
sm_not_replay_upper:
        cmp #'r'
        bne sm_not_replay_lower
        jmp solo_mode_start
sm_not_replay_lower:
        cmp #'O'
        beq sm_title
        cmp #'o'
        bne sm_game_wait
        beq sm_title

; Adapt the two bitmask hands and compact public fields to the existing online
; renderer globals. Cards are presented in stable ordinal order.
solo_sync_ui:
        lda #2
        sta player_count
        lda #0
        sta my_index
        sta player_out_flag
        lda solo_workspace+SW_CURRENT_PLAYER
        sta current_turn
        lda solo_workspace+SW_TOP_DISCARD
        sta discard_top
        lda solo_workspace+SW_PENDING_DRAWS
        sta pending_draws
        lda solo_workspace+SW_PENDING_SKIPS
        sta pending_skips
        lda solo_workspace+SW_DECK_COUNT
        sta deck_count
        lda solo_workspace+SW_PACKED_FLAGS
        lsr
        and #7
        beq ssu_no_nomination
        sec
        sbc #1
        bcs ssu_nomination
ssu_no_nomination:
        lda #SOLO_NO_SUIT
ssu_nomination:
        sta nominated_suit_recv

        lda #0
        sta player_counts
        sta player_counts+1
        sta hand_count
        ldx #0
ssu_mask_byte:
        stx solo_ui_mask_index
        lda solo_workspace+SW_HAND_MASKS,x
        jsr solo_count_bits
        clc
        adc player_counts
        sta player_counts
        ldx solo_ui_mask_index
        lda solo_workspace+SW_HAND_MASKS+7,x
        jsr solo_count_bits
        clc
        adc player_counts+1
        sta player_counts+1
        ldx solo_ui_mask_index
        inx
        cpx #7
        bcc ssu_mask_byte

        lda #0
        sta solo_ui_ordinal
ssu_card:
        lda solo_ui_ordinal
        and #7
        tax
        lda solo_bit_table,x
        sta solo_ui_bit
        lda solo_ui_ordinal
        lsr
        lsr
        lsr
        tax
        lda solo_workspace+SW_HAND_MASKS,x
        and solo_ui_bit
        beq ssu_next_card
        lda solo_ui_ordinal
        jsr solo_ordinal_to_card
        ldx hand_count
        sta my_hand,x
        inc hand_count
ssu_next_card:
        inc solo_ui_ordinal
        lda solo_ui_ordinal
        cmp #52
        bcc ssu_card
        lda hand_count
        beq ssu_zero_cursor
        sec
        sbc #1
        cmp cursor_pos
        bcs ssu_clear_selected
        sta cursor_pos
        bcc ssu_clear_selected
ssu_zero_cursor:
        sta cursor_pos
ssu_clear_selected:
        lda #0
        ldx #51
ssu_clear_loop:
        sta selected_cards,x
        dex
        bpl ssu_clear_loop
        rts

solo_count_bits:
        ldy #8
        ldx #0
scb_loop:
        lsr
        bcc scb_next
        inx
scb_next:
        dey
        bne scb_loop
        txa
        rts

solo_win_msg:    .byte "YOU WIN!",0
solo_lose_msg:   .byte "COMPUTER WINS",0
solo_replay_msg: .byte "R REPLAY  O MENU",0
solo_ui_action:  .byte 0
solo_ui_card:    .byte 0
solo_ui_ordinal: .byte 0
solo_ui_bit:     .byte 0
solo_ui_mask_index: .byte 0
solo_ui_active:  .byte 0

; Tiny deterministic opponent: choose canonical action zero. The catalogue
; sorts every legal play before DRAW, so this is "first legal play, otherwise
; draw" without duplicating a single legality rule.
