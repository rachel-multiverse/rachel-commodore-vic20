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

        ; Position at top center
        lda #6
        sta ZP_CURSOR_X
        lda #2
        sta ZP_CURSOR_Y

        lda #<title_msg
        sta ZP_PTR1
        lda #>title_msg
        sta ZP_PTR1+1
        jsr print_string

        lda #4
        sta ZP_CURSOR_X
        lda #4
        sta ZP_CURSOR_Y

        lda #<subtitle_msg
        sta ZP_PTR1
        lda #>subtitle_msg
        sta ZP_PTR1+1
        jsr print_string
        rts

title_msg:
        .byte "RACHEL", 0
subtitle_msg:
        .byte "VIC-20 CLIENT", 0

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
        asl                     ; Y * 2
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
