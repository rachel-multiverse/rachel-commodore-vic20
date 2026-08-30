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
        lda hand_count
        beq cr_done
        sec
        sbc #1
        sta ZP_TEMP1
        lda cursor_pos
        cmp ZP_TEMP1
        bcs cr_done
        inc cursor_pos
cr_done:
        rts

; -----------------------------------------------------------------------------
; Toggle card selection
; -----------------------------------------------------------------------------
toggle_select:
        ldx cursor_pos
        lda selected_cards,x
        bne ts_toggle
        jsr count_selected
        cmp #4
        bcs ts_done
ts_toggle:
        ldx cursor_pos
        lda #1
        eor selected_cards,x
        sta selected_cards,x
ts_done:
        rts

; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------
cursor_pos:
        .byte 0
hand_count:
        .byte 0
selected_cards:
        .res 32, 0
