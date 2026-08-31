; Load the frozen fixture into the real overlay. The fixture is the compact
; representation of the canonical RKSI state checked by tests/solo_kernel.py.
solo_fixture_load:
        ldx #0
sfl_loop:
        lda solo_workspace_fixture,x
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sfl_loop
        rts

solo_info_fixture_validate:
        lda #<solo_info_fixture
        sta ZP_PTR1
        lda #>solo_info_fixture
        sta ZP_PTR1+1
        jsr solo_get_info
        ldx #0
sifv_compare:
        lda solo_info_fixture,x
        cmp solo_info_data,x
        bne sifv_bad
        inx
        cpx #SOLO_INFO_BYTES
        bcc sifv_compare
        clc
        rts
sifv_bad:
        sec
        rts

; C=0 means the fixture reached the expected fields in the overlay.
solo_fixture_validate:
        lda #1
        sta solo_fixture_stage
        lda solo_workspace+SW_LAYOUT_VERSION
        cmp #1
        bne sfv_bad_early
        lda solo_workspace+SW_PLAYER_COUNT
        cmp #2
        bne sfv_bad_early
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne sfv_bad_early
        lda solo_workspace+SW_DECK_COUNT
        cmp #2
        beq sfv_deck_ok
sfv_bad_early:
        jmp sfv_bad
sfv_deck_ok:
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$47
        bne sfv_bad_early
        jsr solo_get_action_count
        cmp #1
        bne sfv_bad_early
        lda #0
        jsr solo_get_action_at
        bcs sfv_bad_early
        lda solo_action_kind
        cmp #SOLO_ACTION_DRAW
        bne sfv_bad_early
        inc solo_fixture_stage
        jsr solo_catalogue_fixture_load
        jsr solo_get_action_count
        cmp #7
        bne sfv_bad_mid
        inc solo_fixture_stage
        lda #0
        jsr solo_get_action_at
        bcs sfv_bad_mid
        lda solo_action_kind
        bne sfv_bad
        lda solo_action_rank
        cmp #9
        bne sfv_bad
        lda solo_action_suit_mask
        cmp #1
        bne sfv_bad
        inc solo_fixture_stage
        lda #1
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_suit_mask
        cmp #5                    ; hearts + clubs, canonical suit order
        bne sfv_bad
        inc solo_fixture_stage
        lda #2
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_suit_mask
        cmp #13                   ; hearts + clubs + spades
        bne sfv_bad
        inc solo_fixture_stage
        lda #6
        jsr solo_get_action_at
        bcs sfv_bad
        inc solo_fixture_stage
        lda solo_action_rank
        cmp #14
        bne sfv_bad
        inc solo_fixture_stage
        lda solo_action_nomination
        cmp #3
        bne sfv_bad
        inc solo_fixture_stage
        lda #7
        jsr solo_get_action_at
        bcc sfv_bad
        clc
        rts
sfv_bad_mid:
        jmp sfv_bad

sfv_bad:
        sec
        rts

solo_catalogue_fixture_load:
        lda #0
        ldx #0
scfl_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne scfl_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #5                    ; five hearts on top
        sta solo_workspace+SW_TOP_DISCARD
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda #$80                  ; nine hearts, ordinal 7
        sta solo_workspace+SW_HAND_MASKS
        lda #$10                  ; ace hearts, ordinal 12
        sta solo_workspace+SW_HAND_MASKS+1
        lda #$02                  ; nine clubs, ordinal 33
        sta solo_workspace+SW_HAND_MASKS+4
        lda #$40                  ; nine spades, ordinal 46
        sta solo_workspace+SW_HAND_MASKS+5
        ; An all-zero hand mask is a seat that has gone out, and turn
        ; advancement steps over it. Give the opponent a card so this synthetic
        ; table is one the kernel could actually reach in play.
        lda #$01                  ; two hearts, ordinal 0
        sta solo_workspace+SW_HAND_MASKS+7
        rts

