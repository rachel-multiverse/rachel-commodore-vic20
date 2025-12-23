; =============================================================================
; VIC-20 GAME MODULE
; Game rendering and logic for 22x23 screen
; =============================================================================

; -----------------------------------------------------------------------------
; Render entire game state
; -----------------------------------------------------------------------------
render_game:
        jsr display_clear

        ; Show current turn at top
        lda #0
        sta ZP_CURSOR_X
        sta ZP_CURSOR_Y

        lda #<turn_msg
        sta ZP_PTR1
        lda #>turn_msg
        sta ZP_PTR1+1
        jsr print_string

        lda current_turn
        clc
        adc #'1'
        jsr print_char

        ; Show discard pile
        lda #0
        sta ZP_CURSOR_X
        lda #3
        sta ZP_CURSOR_Y

        lda #<discard_msg
        sta ZP_PTR1
        lda #>discard_msg
        sta ZP_PTR1+1
        jsr print_string

        lda discard_top
        jsr render_card

        ; Show player hand
        jsr render_hand

        rts

turn_msg:
        .byte "TURN: P", 0
discard_msg:
        .byte "TOP: ", 0

; -----------------------------------------------------------------------------
; Render player's hand
; Shows cards at bottom of screen
; -----------------------------------------------------------------------------
render_hand:
        ; Position at row 18
        lda #0
        sta ZP_CURSOR_X
        lda #18
        sta ZP_CURSOR_Y

        lda #<hand_msg
        sta ZP_PTR1
        lda #>hand_msg
        sta ZP_PTR1+1
        jsr print_string

        ; Show hand count
        lda hand_count
        clc
        adc #'0'
        jsr print_char

        lda #':'
        jsr print_char

        ; Next line for cards
        lda #0
        sta ZP_CURSOR_X
        lda #20
        sta ZP_CURSOR_Y

        ; Render each card
        ldx #0
rh_loop:
        cpx hand_count
        bcs rh_done

        ; Check if this is cursor position
        cpx cursor_pos
        bne rh_no_cursor
        lda #'['
        jsr print_char
        jmp rh_card

rh_no_cursor:
        lda #' '
        jsr print_char

rh_card:
        ; Get card value
        lda my_hand,x
        jsr render_card_short

        ; Check if selected
        jsr check_selected
        bcc rh_not_sel
        lda #'*'
        jsr print_char
        jmp rh_next

rh_not_sel:
        lda #' '
        jsr print_char

rh_next:
        inx
        bne rh_loop

rh_done:
        rts

hand_msg:
        .byte "HAND:", 0

; -----------------------------------------------------------------------------
; Check if card X is selected
; Returns: C=1 if selected, C=0 if not
; -----------------------------------------------------------------------------
check_selected:
        txa
        pha

        cpx #8
        bcs cs_high_byte

        ; Low byte
        lda #1
cs_shift_lo:
        cpx #0
        beq cs_test_lo
        asl
        dex
        bne cs_shift_lo
cs_test_lo:
        and selected_lo
        beq cs_not_sel
        sec
        bcs cs_done

cs_high_byte:
        txa
        sec
        sbc #8
        tax
        lda #1
cs_shift_hi:
        cpx #0
        beq cs_test_hi
        asl
        dex
        bne cs_shift_hi
cs_test_hi:
        and selected_hi
        beq cs_not_sel
        sec
        bcs cs_done

cs_not_sel:
        clc

cs_done:
        pla
        tax
        rts

; -----------------------------------------------------------------------------
; Render card (short form: "2H", "KS", etc.)
; Input: A = card byte
; -----------------------------------------------------------------------------
render_card_short:
        pha

        ; Get rank (low nibble)
        and #$0F
        tax
        lda rank_chars,x
        jsr print_char

        ; Get suit (high nibble >> 4)
        pla
        lsr
        lsr
        lsr
        lsr
        and #$03
        tax
        lda suit_chars,x
        jsr print_char

        rts

; -----------------------------------------------------------------------------
; Render card (full form)
; Input: A = card byte
; -----------------------------------------------------------------------------
render_card:
        pha

        ; Get rank
        and #$0F
        tax
        lda rank_chars,x
        jsr print_char

        lda #' '
        jsr print_char

        ; Get suit
        pla
        lsr
        lsr
        lsr
        lsr
        and #$03
        asl
        tax

        ; Print suit name
        lda suit_names,x
        jsr print_char
        lda suit_names+1,x
        jsr print_char

        rts

; Card data
rank_chars:
        .byte '?', 'A', '2', '3', '4', '5', '6', '7'
        .byte '8', '9', 'T', 'J', 'Q', 'K', '?', '?'

suit_chars:
        .byte 'H', 'D', 'C', 'S'

suit_names:
        .byte "HE"              ; Hearts
        .byte "DI"              ; Diamonds
        .byte "CL"              ; Clubs
        .byte "SP"              ; Spades
