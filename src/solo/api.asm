; =============================================================================
; SOLO PUBLIC API, AI POLICY AND PERSISTENCE
; =============================================================================

; Tiny deterministic opponent: choose canonical action zero. The catalogue
; sorts every legal play before DRAW, so this is "first legal play, otherwise
; draw" without duplicating a single legality rule.
; In: current player and workspace state. Out: C clear on applied action.
; Clobbers: A, X, Y and action-query temporaries.
solo_ai_take_turn:
        lda #0
        jsr solo_get_action_at
        bcs sait_bad
        lda #0
        jmp solo_apply_action
sait_bad:
        sec
        rts

; Return A = number of legal actions. The catalogue order is the portable ABI
; order: rank, suit bitmask, nomination; DRAW follows every play. No action
; table is allocated.
; In: current workspace state. Out: A=count; solo_action_count=count.
; Clobbers: A and action-enumeration temporaries. Preserves: X, Y.
solo_get_action_count:
        lda #0
        sta solo_action_count
        sta solo_action_query
sgac_loop:
        lda solo_action_query
        jsr solo_get_action_at
        bcs sgac_done
        inc solo_action_count
        inc solo_action_query
        bne sgac_loop
sgac_done:
        lda solo_action_count
        rts

; Compact persistence image at ZP_PTR1: "RKS2", version, payload length,
; 80-byte workspace and XOR checksum. The caller owns the external buffer.
; In: ZP_PTR1 -> SOLO_SAVE_BYTES writable bytes.
; Out: versioned, checksummed image. Clobbers: A, X, Y, save temporaries.
solo_save_state:
        ldy #0
        lda #'R'
        sta (ZP_PTR1),y
        iny
        lda #'K'
        sta (ZP_PTR1),y
        iny
        lda #'S'
        sta (ZP_PTR1),y
        iny
        lda #'2'
        sta (ZP_PTR1),y
        iny
        lda #1
        sta (ZP_PTR1),y
        iny
        lda #SOLO_WS_SIZE
        sta (ZP_PTR1),y
        lda #0
        sta solo_save_checksum
        ldx #0
        ldy #6
sss_copy:
        lda solo_workspace,x
        sta (ZP_PTR1),y
        eor solo_save_checksum
        sta solo_save_checksum
        inx
        iny
        cpx #SOLO_WS_SIZE
        bcc sss_copy
        lda solo_save_checksum
        sta (ZP_PTR1),y
        rts

; Load only after the entire image, checksum and structural bounds validate.
; C=1 rejects without touching the live workspace.
; In: ZP_PTR1 -> SOLO_SAVE_BYTES-byte image.
; Out: C clear and workspace replaced, or C set with workspace untouched.
; Clobbers: A, X, Y and load temporaries.
solo_load_state:
        ldy #0
        lda (ZP_PTR1),y
        cmp #'R'
        bne sls_bad_early
        iny
        lda (ZP_PTR1),y
        cmp #'K'
        bne sls_bad_early
        iny
        lda (ZP_PTR1),y
        cmp #'S'
        beq sls_magic_s
sls_bad_early:
        jmp sls_bad
sls_magic_s:
        iny
        lda (ZP_PTR1),y
        cmp #'2'
        bne sls_bad
        iny
        lda (ZP_PTR1),y
        cmp #1
        bne sls_bad
        iny
        lda (ZP_PTR1),y
        cmp #SOLO_WS_SIZE
        bne sls_bad
        lda #0
        sta solo_save_checksum
        ldx #0
        ldy #6
sls_checksum:
        lda (ZP_PTR1),y
        eor solo_save_checksum
        sta solo_save_checksum
        inx
        iny
        cpx #SOLO_WS_SIZE
        bcc sls_checksum
        lda (ZP_PTR1),y
        cmp solo_save_checksum
        bne sls_bad

        ; Structural checks are sufficient for safe compact-kernel indexing.
        ldy #6+SW_LAYOUT_VERSION
        lda (ZP_PTR1),y
        cmp #1
        bne sls_bad
        ldy #6+SW_PLAYER_COUNT
        lda (ZP_PTR1),y
        cmp #2
        bne sls_bad
        ldy #6+SW_CURRENT_PLAYER
        lda (ZP_PTR1),y
        cmp #2
        bcs sls_bad
        ldy #6+SW_DECK_COUNT
        lda (ZP_PTR1),y
        cmp #53
        bcs sls_bad
        sta solo_load_total
        ldy #6+SW_DISCARD_COUNT
        lda (ZP_PTR1),y
        beq sls_bad
        cmp #53
        bcs sls_bad
        clc
        adc solo_load_total
        sec
        sbc #1
        cmp #53
        bcs sls_bad

        ldx #0
        ldy #6
sls_copy:
        lda (ZP_PTR1),y
        sta solo_workspace,x
        inx
        iny
        cpx #SOLO_WS_SIZE
        bcc sls_copy
        clc
        rts
sls_bad:
        sec
        rts

; Input A = zero-based action index. C=0 and the solo_action_* fields describe
; the action; C=1 means out of range. Enumeration uses only four bytes of state.
