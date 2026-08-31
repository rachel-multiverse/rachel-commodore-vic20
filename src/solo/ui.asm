; =============================================================================
; SOLO OFFLINE USER INTERFACE
; =============================================================================
;
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
