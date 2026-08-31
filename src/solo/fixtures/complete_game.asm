; Exercise a complete server-free match through the same enumerated action
; path used by both front-end participants. Seed 42 must reach a winner within
; the byte-sized safety bound.
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
        jsr solo_new_game
        lda #0
        sta solo_complete_remaining
        lda #4
        sta solo_complete_pages
scgfv_turn:
        lda solo_workspace+SW_FINISH_COUNT
        bne scgfv_done
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
        cmp #2
        bcc scgfv_winner_ok
        lda #4
        bne scgfv_fail
scgfv_winner_ok:
scgfv_game_complete:
        inc solo_complete_games_passed
        dec solo_complete_games_remaining
        bne scgfv_new_game
        clc
        rts

