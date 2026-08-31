solo_new_game_fixture_validate:
        lda #0
        sta solo_new_game_fixture_stage
        ldx #0
sngfv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sngfv_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        jsr solo_new_game
        lda solo_workspace+SW_DECK_COUNT
        cmp #37
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #1
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$cc                  ; queen spades
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_PACKED_DECK
        and #$3f
        cmp #15                   ; four diamonds is first remaining card
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_HAND_MASKS+2
        cmp #$30
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+3
        cmp #$08
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        cmp #$04
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+5
        cmp #$52
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+7
        cmp #$20
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+8
        cmp #$7c
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+10
        cmp #$20
        bne sngfv_bad
        ldx #7
sngfv_seed:
        lda solo_workspace+SW_RANDOM_SEED,x
        cmp solo_seed42_final,x
        bne sngfv_bad
        dex
        bpl sngfv_seed
        clc
        rts
sngfv_bad:
        sec
        rts

solo_seed42_final:
        .byte $e3,$e3,$25,$26,$72,$85,$8c,$06

solo_rng_fixture_validate:
        lda #0
        sta solo_rng_fixture_stage
        ldx #7
srfv_clear:
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl srfv_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        inc solo_rng_fixture_stage
        jsr solo_rng_next
        inc solo_rng_fixture_stage
        ldx #7
srfv_compare:
        lda solo_workspace+SW_RANDOM_SEED,x
        cmp solo_seed42_first,x
        bne srfv_bad
        dex
        bpl srfv_compare
        clc
        rts
srfv_bad:
        sec
        rts

solo_seed42_first:
        .byte $aa,$4a,$51,$95,$0a,0,0,0

solo_recycle_fixture_validate:
        lda #0
        ldx #0
srv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne srv_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #4
        sta solo_workspace+SW_DISCARD_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        lda #0
        ldx #0
        jsr solo_deck_set_at
        lda #1
        ldx #1
        jsr solo_deck_set_at
        lda #2
        ldx #2
        jsr solo_deck_set_at
        jsr solo_recycle_discards
        lda solo_workspace+SW_DECK_COUNT
        cmp #3
        bne srv_bad
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #1
        bne srv_bad
        ldx #0
        jsr solo_deck_get_at
        cmp #0
        bne srv_bad
        ldx #1
        jsr solo_deck_get_at
        cmp #2
        bne srv_bad
        ldx #2
        jsr solo_deck_get_at
        cmp #1
        bne srv_bad
        ldx #7
srv_seed:
        lda solo_workspace+SW_RANDOM_SEED,x
        cmp solo_seed42_recycled,x
        bne srv_bad
        dex
        bpl srv_seed
        clc
        rts
srv_bad:
        sec
        rts

solo_seed42_recycled:
        .byte $bf,$02,$02,$f8,$fd,$aa,$0a,$a0

