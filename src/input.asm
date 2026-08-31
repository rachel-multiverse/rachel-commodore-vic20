; =============================================================================
; VIC-20 INPUT MODULE
; =============================================================================

; -----------------------------------------------------------------------------
; Initialize input
; -----------------------------------------------------------------------------
input_init:
        lda #0
        sta joystick_previous
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
        bne gi_done
        jsr get_joystick_input
gi_done:
        rts

; Convert newly pressed joystick controls into the existing keyboard actions.
; Left/right move, up/down choose a suit, fire selects, fire+up plays and
; fire+down draws. Right shares VIA2 PB7 with keyboard scanning, so its DDR bit
; is made input only for the atomic sample and then restored.
get_joystick_input:
        php
        sei
        lda VIA1_PORTA
        sta ZP_TEMP1
        lda VIA2_DDRB
        pha
        and #$7f
        sta VIA2_DDRB
        lda VIA2_PORTB
        sta ZP_TEMP2
        pla
        sta VIA2_DDRB
        plp

        lda #0
        sta ZP_TEMP3
        lda ZP_TEMP1
        and #$04
        bne gj_no_up
        lda ZP_TEMP3
        ora #$01
        sta ZP_TEMP3
gj_no_up:
        lda ZP_TEMP1
        and #$08
        bne gj_no_down
        lda ZP_TEMP3
        ora #$02
        sta ZP_TEMP3
gj_no_down:
        lda ZP_TEMP1
        and #$10
        bne gj_no_left
        lda ZP_TEMP3
        ora #$04
        sta ZP_TEMP3
gj_no_left:
        lda ZP_TEMP2
        and #$80
        bne gj_no_right
        lda ZP_TEMP3
        ora #$08
        sta ZP_TEMP3
gj_no_right:
        lda ZP_TEMP1
        and #$20
        bne gj_edges
        lda ZP_TEMP3
        ora #$10
        sta ZP_TEMP3

gj_edges:
        lda joystick_previous
        eor #$ff
        and ZP_TEMP3
        sta ZP_TEMP4
        lda ZP_TEMP3
        sta joystick_previous
        lda ZP_TEMP4
        and #$10
        beq gj_directions
        lda ZP_TEMP3
        and #$01
        bne gj_play
        lda ZP_TEMP3
        and #$02
        bne gj_draw
        lda #KEY_SPACE
        rts
gj_play:
        lda #KEY_RETURN
        rts
gj_draw:
        lda #'D'
        rts
gj_directions:
        lda ZP_TEMP4
        and #$04
        bne gj_left
        lda ZP_TEMP4
        and #$08
        bne gj_right
        lda ZP_TEMP4
        and #$01
        bne gj_up
        lda ZP_TEMP4
        and #$02
        bne gj_down
        lda #0
        rts
gj_left:
        lda #KEY_LEFT
        rts
gj_right:
        lda #KEY_RIGHT
        rts
gj_up:
        lda #KEY_UP
        rts
gj_down:
        lda #KEY_DOWN
        rts

; -----------------------------------------------------------------------------
; Input one server-address line into ip_buffer.
; Returns: Y = actual length
; -----------------------------------------------------------------------------
input_line:
        ldy #0
il_loop:
        ; GETIN/KERNAL IRQ handling does not promise to preserve our index.
        tya
        pha
        jsr wait_key
        tax
        pla
        tay
        txa
        cmp #KEY_RETURN
        beq il_done
        cmp #KEY_DELETE
        beq il_delete

        ; Regular character
        cpy #20                 ; Max length
        bcs il_loop             ; Buffer full

        sta ip_buffer,y
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
        sta ip_buffer,y         ; Null terminate
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
joystick_previous:
        .byte 0
