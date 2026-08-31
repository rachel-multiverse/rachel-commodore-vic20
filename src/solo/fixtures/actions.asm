solo_apply_fixture_validate:
        lda #0
        sta solo_apply_fixture_stage
        jsr solo_catalogue_fixture_load
        ; Index 7 is just beyond the seven-action catalogue. Rejection must
        ; preserve top card, turn and both relevant hand bytes.
        lda #7
        jsr solo_apply_action
        bcc safv_bad
        lda solo_workspace+SW_TOP_DISCARD
        cmp #5
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS
        cmp #$80
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        cmp #$02
        bne safv_bad
        inc solo_apply_fixture_stage

        ; Action 1 is the canonical two-card nine stack: hearts then clubs.
        lda #1
        jsr solo_apply_action
        bcs safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$89                  ; nine clubs is last in canonical order
        bne safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_TURN_NUMBER
        cmp #1
        bne safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_HAND_MASKS
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+1
        cmp #$10                  ; ace hearts remains
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+5
        cmp #$40                  ; nine spades remains
        bne safv_bad
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #3
        bne safv_bad
        ldx #0
        jsr solo_deck_get_at
        cmp #3                    ; former five hearts top
        bne safv_bad
        ldx #1
        jsr solo_deck_get_at
        cmp #7                    ; intermediate nine hearts
        bne safv_bad
        clc
        rts
safv_bad:
        sec
        rts

solo_draw_fixture_validate:
        lda #0
        ldx #0
sdfv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sdfv_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        sta solo_workspace+SW_PENDING_DRAWS
        sta solo_workspace+SW_DECK_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda #$cc                  ; ordinals 12 then 39, LSB-first 6-bit
        sta solo_workspace+SW_PACKED_DECK
        lda #$09
        sta solo_workspace+SW_PACKED_DECK+1
        lda #$01                  ; three spades (ordinal 40)
        sta solo_workspace+SW_HAND_MASKS+5
        ; The opponent must hold something, or it is a finished seat that turn
        ; advancement steps straight over.
        lda #$01                  ; two hearts, ordinal 0
        sta solo_workspace+SW_HAND_MASKS+7

        lda #0
        jsr solo_apply_action
        bcs sdfv_bad
        lda solo_workspace+SW_DECK_COUNT
        bne sdfv_bad
        lda solo_workspace+SW_PENDING_DRAWS
        bne sdfv_bad
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne sdfv_bad
        lda solo_workspace+SW_TURN_NUMBER
        cmp #1
        bne sdfv_bad
        lda solo_workspace+SW_HAND_MASKS+1
        cmp #$10                  ; ace hearts, ordinal 12
        bne sdfv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        cmp #$80                  ; two spades, ordinal 39
        bne sdfv_bad
        lda solo_workspace+SW_HAND_MASKS+5
        cmp #$01                  ; original three spades remains
        bne sdfv_bad
        clc
        rts
sdfv_bad:
        sec
        rts

