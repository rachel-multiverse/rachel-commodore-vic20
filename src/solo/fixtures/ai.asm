solo_ai_fixture_validate:
        ; A playable catalogue chooses its first play, not DRAW.
        jsr solo_catalogue_fixture_load
        jsr solo_ai_take_turn
        bcs saifv_bad_early
        lda solo_workspace+SW_TOP_DISCARD
        cmp #9                    ; first action is nine hearts
        beq saifv_play_ok
saifv_bad_early:
        jmp saifv_bad
saifv_play_ok:

        ; With no legal play, the same policy takes the sole DRAW action.
        lda #0
        ldx #0
saifv_draw_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne saifv_draw_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #1
        sta solo_workspace+SW_DECK_COUNT
        sta solo_workspace+SW_DISCARD_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #$01                  ; three spades cannot match five hearts
        sta solo_workspace+SW_HAND_MASKS+5
        lda #12                   ; ace hearts is the only deck card
        sta solo_workspace+SW_PACKED_DECK
        jsr solo_ai_take_turn
        bcs saifv_bad
        lda solo_workspace+SW_DECK_COUNT
        bne saifv_bad
        lda solo_workspace+SW_HAND_MASKS+1
        cmp #$10
        bne saifv_bad

        ; Ace expansion is deterministic: action zero nominates hearts.
        lda #0
        ldx #0
saifv_ace_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne saifv_ace_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        sta solo_workspace+SW_DISCARD_COUNT
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #$10                  ; ace hearts
        sta solo_workspace+SW_HAND_MASKS+1
        lda #$01                  ; two clubs keeps the player in the game
        sta solo_workspace+SW_HAND_MASKS+3
        jsr solo_ai_take_turn
        bcs saifv_bad
        lda solo_workspace+SW_PACKED_FLAGS
        lsr
        and #7
        cmp #1                    ; nominated hearts encoding
        bne saifv_bad

        ; Repeated turns are bounded calls and advance the state every time.
        lda #0
        ldx #0
saifv_soak_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne saifv_soak_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        lda #2
        jsr solo_new_game
        lda #8
        sta solo_ai_soak_remaining
saifv_soak:
        jsr solo_ai_take_turn
        bcs saifv_bad
        dec solo_ai_soak_remaining
        bne saifv_soak
        lda solo_workspace+SW_TURN_NUMBER
        cmp #8
        bne saifv_bad
        clc
        rts
saifv_bad:
        sec
        rts

