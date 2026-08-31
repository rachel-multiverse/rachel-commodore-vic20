solo_persistence_fixture_validate:
        lda #<solo_save_fixture_a
        sta ZP_PTR1
        lda #>solo_save_fixture_a
        sta ZP_PTR1+1
        jsr solo_save_state
        lda #0
        ldx #0
spfv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne spfv_clear
        jsr solo_load_state
        bcs spfv_bad
        lda #<solo_save_fixture_b
        sta ZP_PTR1
        lda #>solo_save_fixture_b
        sta ZP_PTR1+1
        jsr solo_save_state
        ldx #0
spfv_compare:
        lda solo_save_fixture_a,x
        cmp solo_save_fixture_b,x
        bne spfv_bad
        inx
        cpx #SOLO_SAVE_BYTES
        bcc spfv_compare

        ; Corruption is rejected before any workspace byte changes.
        lda solo_save_fixture_a+SOLO_SAVE_BYTES-1
        eor #1
        sta solo_save_fixture_a+SOLO_SAVE_BYTES-1
        lda #1
        sta solo_workspace+SW_CURRENT_PLAYER
        lda #<solo_save_fixture_a
        sta ZP_PTR1
        lda #>solo_save_fixture_a
        sta ZP_PTR1+1
        jsr solo_load_state
        bcc spfv_bad
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne spfv_bad
        clc
        rts
spfv_bad:
        sec
        rts

