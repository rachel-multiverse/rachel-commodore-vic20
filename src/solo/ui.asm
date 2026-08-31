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
        jsr solo_ask_players
        bne sm_begin
        jmp main
; Replaying keeps the table the player already chose.
solo_mode_replay:
        lda #1
        sta solo_ui_active
        lda solo_ui_players
sm_begin:
        sta solo_ui_players
        jsr display_clear
        lda #0
        ldx #7
sm_seed_clear:
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl sm_seed_clear
        ; Seed from the KERNAL clock and the raster. Seed 42 is the fixture
        ; vector from docs/SOLO_MEMORY_BUDGET.md; using it here dealt every
        ; interactive game, and every replay, the identical hand.
        lda JIFFY_LOW
        sta solo_workspace+SW_RANDOM_SEED
        lda JIFFY_MID
        sta solo_workspace+SW_RANDOM_SEED+1
        lda VIC_RASTER
        sta solo_workspace+SW_RANDOM_SEED+2
        lda solo_ui_players
        jsr solo_new_game
        lda #0
        sta cursor_pos
        sta chosen_suit
        sta solo_my_place
sm_loop:
        jsr solo_sync_ui
        jsr render_game
        ; Play continues until one player is left holding cards.
        lda solo_workspace+SW_FINISH_COUNT
        clc
        adc #1
        cmp solo_workspace+SW_PLAYER_COUNT
        bcc sm_not_over
        jmp sm_game_over
sm_not_over:
        ; The first pass after my hand empties is where I finished.
        lda solo_my_place
        bne sm_place_known
        lda hand_count
        bne sm_place_known
        lda solo_workspace+SW_FINISH_COUNT
        sta solo_my_place
sm_place_known:
        lda solo_workspace+SW_CURRENT_PLAYER
        beq sm_human
        jsr solo_ai_pause
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
sm_play:
        lda hand_count
        bne sm_play_have
        jmp sm_rejected
sm_play_have:
        ldx cursor_pos
        lda my_hand,x
        sta solo_ui_card
        ; An Ace nominates a suit. Ask for it at the moment the Ace is played
        ; rather than reading a standing control the player need never have
        ; touched, which silently nominated hearts.
        and #$0f
        cmp #14
        bne sm_play_search
        lda solo_ui_card
        jsr set_card_playability
        lda ZP_TEMP4
        beq sm_ace_ok
        jmp sm_rejected
sm_ace_ok:
        jsr pick_suit_modal
        bcc sm_play_search
        jmp sm_human
sm_play_search:
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
        lda solo_my_place
        bne sm_finished
        ; Never went out, so I am the player left holding the cards.
        lda #<solo_lose_msg
        sta ZP_PTR1
        lda #>solo_lose_msg
        bne sm_result
sm_finished:
        cmp #1
        bne sm_placed
        lda #<solo_win_msg
        sta ZP_PTR1
        lda #>solo_win_msg
        bne sm_result
sm_placed:
        lda #5
        sta ZP_CURSOR_X
        lda #7
        sta ZP_CURSOR_Y
        lda #COLOR_WHITE
        sta ZP_TEMP3
        lda #<solo_place_msg
        sta ZP_PTR1
        lda #>solo_place_msg
        sta ZP_PTR1+1
        jsr print_string_color
        lda solo_my_place
        clc
        adc #'0'
        jsr print_table_char
        jmp sm_replay_prompt
sm_result:
        sta ZP_PTR1+1
        lda #7
        jsr print_centered
sm_replay_prompt:
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
        jmp solo_mode_replay
sm_not_replay_upper:
        cmp #'r'
        bne sm_not_replay_lower
        jmp solo_mode_replay
sm_not_replay_lower:
        cmp #'O'
        beq sm_title
        cmp #'o'
        bne sm_game_wait
        beq sm_title

; Adapt the two bitmask hands and compact public fields to the existing online
; renderer globals. Cards are presented in stable ordinal order.
solo_sync_ui:
        lda solo_workspace+SW_PLAYER_COUNT
        sta player_count
        lda #0
        sta my_index
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
        sta hand_count
        ldx #SOLO_MAX_PLAYERS-1
ssu_clear_counts:
        sta player_counts,x
        dex
        bpl ssu_clear_counts

        ; One seat at a time, walking the hand masks in place. solo_count_bits
        ; needs both index registers, so the mask offset is carried in memory.
        lda #0
        sta solo_seat_index
        sta solo_hand_offset
ssu_seat:
        lda #SOLO_SEAT_BYTES
        sta solo_seat_count
        lda #0
        sta solo_seat_acc
        ldy solo_hand_offset
ssu_seat_byte:
        sty solo_ui_mask_index
        lda solo_workspace+SW_HAND_MASKS,y
        jsr solo_count_bits
        clc
        adc solo_seat_acc
        sta solo_seat_acc
        ldy solo_ui_mask_index
        iny
        dec solo_seat_count
        bne ssu_seat_byte
        sty solo_hand_offset
        ldx solo_seat_index
        lda solo_seat_acc
        sta player_counts,x
        inc solo_seat_index
        lda solo_seat_index
        cmp solo_workspace+SW_PLAYER_COUNT
        bcc ssu_seat

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
        lda #0
        sta player_out_flag
        lda hand_count
        bne ssu_holding
        inc player_out_flag
ssu_holding:
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

; Hold the freshly rendered table before an opponent moves. Seven AI seats
; taking their turns with nothing between them reads as the whole round
; happening at once, and the player never sees what any of them played.
; Clobbers: A. Preserves X and Y.
SOLO_AI_JIFFIES = 20
solo_ai_pause:
        txa
        pha
        ldx #SOLO_AI_JIFFIES
sai_next:
        jsr sound_update
        lda JIFFY_LOW
sai_wait:
        cmp JIFFY_LOW
        beq sai_wait
        dex
        bne sai_next
        pla
        tax
        rts

; Ask how many seats are at the table. Out: A = 2 to 8, or 0 for the title.
; Clobbers: A, X, Y and the shared display scratch.
solo_ask_players:
        jsr display_clear
        lda #<players_msg
        sta ZP_PTR1
        lda #>players_msg
        sta ZP_PTR1+1
        lda #8
        jsr print_centered
        lda #<players_help_msg
        sta ZP_PTR1
        lda #>players_help_msg
        sta ZP_PTR1+1
        lda #10
        jsr print_centered
sap_key:
        jsr wait_key
        cmp #KEY_ESC
        beq sap_title
        cmp #'2'
        bcc sap_key
        cmp #'9'
        bcs sap_key
        sec
        sbc #'0'
        rts
sap_title:
        lda #0
        rts

solo_win_msg:    .byte "YOU WIN!",0
solo_lose_msg:   .byte "YOU LOSE!",0
solo_place_msg:  .byte "YOU FINISH ",0
solo_replay_msg: .byte "R REPLAY  O MENU",0
players_msg:     .byte "HOW MANY PLAYERS?",0
players_help_msg:.byte "PRESS 2 TO 8",0
solo_ui_action:  .byte 0
solo_ui_card:    .byte 0
solo_ui_ordinal: .byte 0
solo_ui_bit:     .byte 0
solo_ui_mask_index: .byte 0
solo_ui_active:  .byte 0
solo_ui_players: .byte 2
solo_my_place:   .byte 0
