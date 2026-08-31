; Exercise complete server-free matches through the same enumerated action path
; used by both front-end participants. Each of the sixteen seeds plays a
; different table size, cycling 2 to 8 seats, so directional turn order,
; stepping over finished seats, the per-count deal and finish counting are all
; exercised rather than only the two-player case.
solo_complete_game_fixture_validate:
        lda #16
        sta solo_complete_games_remaining
        lda #0
        sta solo_complete_games_passed
        sta solo_complete_games_bounded
        sta solo_complete_failure
scgfv_new_game:
        lda #0
        ldx #7
scgfv_seed_clear:
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl scgfv_seed_clear
        lda solo_complete_games_passed
        clc
        adc #1
        sta solo_workspace+SW_RANDOM_SEED
        ; Seats cycle 2..8 across the sixteen seeds.
        lda solo_complete_games_passed
scgfv_seat_mod:
        cmp #7
        bcc scgfv_seat_count
        sec
        sbc #7
        bcs scgfv_seat_mod
scgfv_seat_count:
        clc
        adc #2
        jsr solo_new_game
        lda #0
        sta solo_complete_remaining
        lda #4
        sta solo_complete_pages
scgfv_turn:
        ; Play continues until one seat is left holding cards.
        lda solo_workspace+SW_FINISH_COUNT
        clc
        adc #1
        cmp solo_workspace+SW_PLAYER_COUNT
        bcs scgfv_done
        jsr scgfv_cards_conserved
        beq scgfv_total_ok
        lda #5
        bne scgfv_fail
scgfv_total_ok:
        jsr solo_get_action_count
        bne scgfv_have_action
        lda #1
        bne scgfv_fail
scgfv_have_action:
        sta solo_complete_action_count
        jsr solo_rng_next
        lda solo_complete_action_count
        jsr solo_rng_mod
        jsr solo_apply_action
        bcc scgfv_applied
        lda #2
        bne scgfv_fail
scgfv_applied:
        dec solo_complete_remaining
        bne scgfv_turn
        dec solo_complete_pages
        bne scgfv_turn
        inc solo_complete_games_bounded
        jmp scgfv_game_complete
scgfv_fail:
        sta solo_complete_failure
        sec
        rts
scgfv_done:
        lda solo_workspace+SW_FINISH_ORDER
        cmp solo_workspace+SW_PLAYER_COUNT
        bcc scgfv_winner_ok
        lda #4
        bne scgfv_fail
scgfv_winner_ok:
scgfv_game_complete:
        inc solo_complete_games_passed
        dec solo_complete_games_remaining
        beq scgfv_all_played     ; the loop is past branch range now
        jmp scgfv_new_game
scgfv_all_played:
        clc
        rts

; Every one of the 52 cards is in a hand, in the deck, or in the discard pile.
; This is the invariant the packed-deck overrun broke: it wrote through
; SW_PACKED_DECK+39, which is SW_DISCARD_COUNT, and cards silently vanished
; from the accounting until recycling could no longer find them.
; Out: Z set when the count is 52. Clobbers A, X, Y and the fixture counters.
scgfv_cards_conserved:
        lda #0
        sta scgfv_total
        lda solo_workspace+SW_PLAYER_COUNT
        asl
        asl
        clc
        adc solo_workspace+SW_PLAYER_COUNT
        adc solo_workspace+SW_PLAYER_COUNT
        adc solo_workspace+SW_PLAYER_COUNT     ; seats * 7 mask bytes
        sta scgfv_mask_count
        ldy #0
scgfv_total_byte:
        sty scgfv_mask_index
        lda solo_workspace+SW_HAND_MASKS,y
        jsr solo_count_bits
        clc
        adc scgfv_total
        sta scgfv_total
        ldy scgfv_mask_index
        iny
        cpy scgfv_mask_count
        bcc scgfv_total_byte
        lda scgfv_total
        clc
        adc solo_workspace+SW_DECK_COUNT
        clc
        adc solo_workspace+SW_DISCARD_COUNT
        cmp #52
        rts

