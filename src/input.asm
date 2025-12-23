; =============================================================================
; VIC-20 INPUT MODULE
; =============================================================================

; -----------------------------------------------------------------------------
; Initialize input
; -----------------------------------------------------------------------------
input_init:
        rts

; -----------------------------------------------------------------------------
; Wait for keypress
; Returns: A = key code
; -----------------------------------------------------------------------------
wait_key:
wk_loop:
        jsr GETIN
        beq wk_loop
        rts

; -----------------------------------------------------------------------------
; Get input (non-blocking)
; Returns: A = key code (0 if none)
; -----------------------------------------------------------------------------
get_input:
        jsr GETIN
        rts

; -----------------------------------------------------------------------------
; Input line into buffer
; Input: ZP_PTR1 = buffer address, X = max length
; Returns: Y = actual length
; -----------------------------------------------------------------------------
input_line:
        ldy #0
il_loop:
        jsr wait_key
        cmp #KEY_RETURN
        beq il_done
        cmp #KEY_DELETE
        beq il_delete

        ; Regular character
        cpy ZP_TEMP3            ; Max length
        bcs il_loop             ; Buffer full

        sta (ZP_PTR1),y
        jsr print_char
        iny
        jmp il_loop

il_delete:
        cpy #0
        beq il_loop             ; Nothing to delete
        dey
        ; Backspace on screen
        dec ZP_CURSOR_X
        lda #' '
        jsr print_char
        dec ZP_CURSOR_X
        jmp il_loop

il_done:
        lda #0
        sta (ZP_PTR1),y         ; Null terminate
        rts

; -----------------------------------------------------------------------------
; Cursor movement for card selection
; -----------------------------------------------------------------------------
cursor_left:
        lda cursor_pos
        beq cl_done
        dec cursor_pos
cl_done:
        rts

cursor_right:
        lda cursor_pos
        cmp hand_count
        bcs cr_done
        inc cursor_pos
cr_done:
        rts

; -----------------------------------------------------------------------------
; Toggle card selection
; -----------------------------------------------------------------------------
toggle_select:
        ldx cursor_pos
        lda selected_lo
        sta ZP_TEMP1
        lda selected_hi
        sta ZP_TEMP2

        ; Create bit mask
        lda #1
ts_shift:
        cpx #0
        beq ts_toggle
        asl
        rol ZP_TEMP2
        dex
        bne ts_shift

ts_toggle:
        ; Toggle the bit
        ldx cursor_pos
        cpx #8
        bcs ts_high

        ; Low byte
        eor selected_lo
        sta selected_lo
        rts

ts_high:
        ; High byte
        txa
        sec
        sbc #8
        tax
        lda #1
ts_shift2:
        cpx #0
        beq ts_do_hi
        asl
        dex
        bne ts_shift2
ts_do_hi:
        eor selected_hi
        sta selected_hi
        rts

; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------
cursor_pos:
        .byte 0
hand_count:
        .byte 0
selected_lo:
        .byte 0
selected_hi:
        .byte 0
