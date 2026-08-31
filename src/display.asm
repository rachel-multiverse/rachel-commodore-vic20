; =============================================================================
; VIC-20 DISPLAY MODULE
; 22x23 character display
; =============================================================================

; -----------------------------------------------------------------------------
; Initialize display
; -----------------------------------------------------------------------------
display_init:
        ; Set background to black, border to blue
        lda #$08                ; Blue border, black background
        sta VIC_BKGND
        lda #$00                ; Aux color
        sta VIC_AUX
        ; Direct screen writes do not pass through KERNAL, so initialise the
        ; matching colour RAM explicitly instead of inheriting arbitrary
        ; editor colours. Colour 1 is white.
        ldy #0
        lda #$01
di_color:
        sta COLOR_BASE,y
        sta COLOR_BASE+$100,y
        iny
        bne di_color
        jsr display_clear
        rts

; -----------------------------------------------------------------------------
; Clear screen
; -----------------------------------------------------------------------------
display_clear:
        ldy #0
        lda #' '                ; Space character
dc_loop:
        sta SCREEN_BASE,y
        sta SCREEN_BASE+$100,y
        iny
        bne dc_loop

        ; Colour RAM is independent of screen RAM. Reset it as well so colour
        ; applied to an old card cannot leak into later text at the same cell.
        ldy #0
        lda #COLOR_WHITE
dc_color_loop:
        sta COLOR_BASE,y
        sta COLOR_BASE+$100,y
        iny
        bne dc_color_loop

        ; Reset cursor
        lda #0
        sta ZP_CURSOR_X
        sta ZP_CURSOR_Y
        rts

; -----------------------------------------------------------------------------
; Display title screen
; -----------------------------------------------------------------------------
display_title:
        jsr display_clear
        lda #<title_msg
        sta ZP_PTR1
        lda #>title_msg
        sta ZP_PTR1+1
        lda #2
        jsr print_centered

        lda #<subtitle_msg
        sta ZP_PTR1
        lda #>subtitle_msg
        sta ZP_PTR1+1
        lda #4
        jsr print_centered
        lda #<start_msg
        sta ZP_PTR1
        lda #>start_msg
        sta ZP_PTR1+1
        lda #8
        jsr print_centered
        rts

title_msg:
        .byte "RACHEL", 0
subtitle_msg:
        .byte "VIC-20 CLIENT", 0
start_msg:
        .byte "PRESS A KEY TO START", 0

; -----------------------------------------------------------------------------
; Print string at current cursor position
; Input: ZP_PTR1 = string address
; -----------------------------------------------------------------------------
print_string:
        ldy #0
ps_loop:
        lda (ZP_PTR1),y
        beq ps_done
        jsr print_char
        iny
        bne ps_loop
ps_done:
        rts

; -----------------------------------------------------------------------------
; Print a null-terminated string centred on a screen row
; Input: ZP_PTR1 = string address, A = row
; Strings at least SCREEN_WIDTH characters wide start at column zero.
; -----------------------------------------------------------------------------
print_centered:
        sta ZP_CURSOR_Y
        ldy #0
pc_count:
        lda (ZP_PTR1),y
        beq pc_length
        iny
        cpy #SCREEN_WIDTH
        bcs pc_too_wide
        bne pc_count
pc_length:
        tya
        sta ZP_TEMP1
        lda #SCREEN_WIDTH
        sec
        sbc ZP_TEMP1
        lsr
        sta ZP_CURSOR_X
        jmp print_string
pc_too_wide:
        lda #0
        sta ZP_CURSOR_X
        jmp print_string

; -----------------------------------------------------------------------------
; Print character at current cursor position
; Input: A = character
; -----------------------------------------------------------------------------
print_char:
        pha
        txa
        pha
        tya
        pha

        ; Calculate screen address
        lda ZP_CURSOR_Y
        tax
        lda screen_lo,x
        sta ZP_PTR2
        lda screen_hi,x
        sta ZP_PTR2+1

        ; Add X offset
        ldy ZP_CURSOR_X
        sty ZP_PTR3
        pla
        sta ZP_PTR3+1
        pla
        tax
        pla
        ; Direct screen RAM uses VIC screen codes, not PETSCII. Uppercase
        ; letters occupy $01-$1A rather than PETSCII $41-$5A.
        cmp #'A'
        bcc pc_store
        cmp #'Z'+1
        bcs pc_store
        and #$1f
pc_store:
        ldy ZP_PTR3
        sta (ZP_PTR2),y
        ldy ZP_PTR3+1

        ; Advance cursor
        inc ZP_CURSOR_X
        lda ZP_CURSOR_X
        cmp #SCREEN_WIDTH
        bcc pc_done
        lda #0
        sta ZP_CURSOR_X
        inc ZP_CURSOR_Y
pc_done:
        rts

; Print a raw VIC screen code without PETSCII/ASCII conversion.
; Input: A = screen code
print_screen_code:
        pha
        txa
        pha
        tya
        pha

        lda ZP_CURSOR_Y
        tax
        lda screen_lo,x
        sta ZP_PTR2
        lda screen_hi,x
        sta ZP_PTR2+1
        ldy ZP_CURSOR_X
        sty ZP_PTR3
        pla
        sta ZP_PTR3+1
        pla
        tax
        pla
        jmp pc_store

; Set the colour of the character at the current cursor without advancing it.
; Input: A = VIC colour RAM value (0-7)
set_cursor_color:
        pha
        txa
        pha
        lda ZP_CURSOR_Y
        tax
        lda color_lo,x
        sta ZP_PTR2
        lda color_hi,x
        sta ZP_PTR2+1
        ldy ZP_CURSOR_X
        pla
        tax
        pla
        sta (ZP_PTR2),y
        rts

; -----------------------------------------------------------------------------
; Print newline
; -----------------------------------------------------------------------------
print_newline:
        lda #0
        sta ZP_CURSOR_X
        inc ZP_CURSOR_Y
        rts

; -----------------------------------------------------------------------------
; Print hex byte
; Input: A = value
; -----------------------------------------------------------------------------
print_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr print_nibble
        pla
        and #$0F
        jsr print_nibble
        rts

print_nibble:
        cmp #10
        bcc pn_digit
        adc #6                  ; 'A'-'0'-10-1
pn_digit:
        adc #'0'
        jsr print_char
        rts

; -----------------------------------------------------------------------------
; Screen line address lookup tables
; 22 bytes per line
; -----------------------------------------------------------------------------
screen_lo:
        .byte <(SCREEN_BASE+0*22), <(SCREEN_BASE+1*22)
        .byte <(SCREEN_BASE+2*22), <(SCREEN_BASE+3*22)
        .byte <(SCREEN_BASE+4*22), <(SCREEN_BASE+5*22)
        .byte <(SCREEN_BASE+6*22), <(SCREEN_BASE+7*22)
        .byte <(SCREEN_BASE+8*22), <(SCREEN_BASE+9*22)
        .byte <(SCREEN_BASE+10*22), <(SCREEN_BASE+11*22)
        .byte <(SCREEN_BASE+12*22), <(SCREEN_BASE+13*22)
        .byte <(SCREEN_BASE+14*22), <(SCREEN_BASE+15*22)
        .byte <(SCREEN_BASE+16*22), <(SCREEN_BASE+17*22)
        .byte <(SCREEN_BASE+18*22), <(SCREEN_BASE+19*22)
        .byte <(SCREEN_BASE+20*22), <(SCREEN_BASE+21*22)
        .byte <(SCREEN_BASE+22*22)

screen_hi:
        .byte >(SCREEN_BASE+0*22), >(SCREEN_BASE+1*22)
        .byte >(SCREEN_BASE+2*22), >(SCREEN_BASE+3*22)
        .byte >(SCREEN_BASE+4*22), >(SCREEN_BASE+5*22)
        .byte >(SCREEN_BASE+6*22), >(SCREEN_BASE+7*22)
        .byte >(SCREEN_BASE+8*22), >(SCREEN_BASE+9*22)
        .byte >(SCREEN_BASE+10*22), >(SCREEN_BASE+11*22)
        .byte >(SCREEN_BASE+12*22), >(SCREEN_BASE+13*22)
        .byte >(SCREEN_BASE+14*22), >(SCREEN_BASE+15*22)
        .byte >(SCREEN_BASE+16*22), >(SCREEN_BASE+17*22)
        .byte >(SCREEN_BASE+18*22), >(SCREEN_BASE+19*22)
        .byte >(SCREEN_BASE+20*22), >(SCREEN_BASE+21*22)
        .byte >(SCREEN_BASE+22*22)

color_lo:
        .byte <(COLOR_BASE+0*22), <(COLOR_BASE+1*22)
        .byte <(COLOR_BASE+2*22), <(COLOR_BASE+3*22)
        .byte <(COLOR_BASE+4*22), <(COLOR_BASE+5*22)
        .byte <(COLOR_BASE+6*22), <(COLOR_BASE+7*22)
        .byte <(COLOR_BASE+8*22), <(COLOR_BASE+9*22)
        .byte <(COLOR_BASE+10*22), <(COLOR_BASE+11*22)
        .byte <(COLOR_BASE+12*22), <(COLOR_BASE+13*22)
        .byte <(COLOR_BASE+14*22), <(COLOR_BASE+15*22)
        .byte <(COLOR_BASE+16*22), <(COLOR_BASE+17*22)
        .byte <(COLOR_BASE+18*22), <(COLOR_BASE+19*22)
        .byte <(COLOR_BASE+20*22), <(COLOR_BASE+21*22)
        .byte <(COLOR_BASE+22*22)

color_hi:
        .byte >(COLOR_BASE+0*22), >(COLOR_BASE+1*22)
        .byte >(COLOR_BASE+2*22), >(COLOR_BASE+3*22)
        .byte >(COLOR_BASE+4*22), >(COLOR_BASE+5*22)
        .byte >(COLOR_BASE+6*22), >(COLOR_BASE+7*22)
        .byte >(COLOR_BASE+8*22), >(COLOR_BASE+9*22)
        .byte >(COLOR_BASE+10*22), >(COLOR_BASE+11*22)
        .byte >(COLOR_BASE+12*22), >(COLOR_BASE+13*22)
        .byte >(COLOR_BASE+14*22), >(COLOR_BASE+15*22)
        .byte >(COLOR_BASE+16*22), >(COLOR_BASE+17*22)
        .byte >(COLOR_BASE+18*22), >(COLOR_BASE+19*22)
        .byte >(COLOR_BASE+20*22), >(COLOR_BASE+21*22)
        .byte >(COLOR_BASE+22*22)
