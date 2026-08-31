; =============================================================================
; VIC-20 GAME MODULE
; Game rendering and logic for 22x23 screen
; =============================================================================

; -----------------------------------------------------------------------------
; Render entire game state
; -----------------------------------------------------------------------------
render_game:
        ; Normal state updates are incremental. Clearing the complete 506-cell
        ; screen made the VIC visibly flash and exposed half-rendered frames.
        lda #12
        jsr display_clear_row

        ; Show current turn at top
        lda #7
        sta ZP_CURSOR_X
        lda #0
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

        ; Show discard pile as a PETSCII card.
        lda #<discard_msg
        sta ZP_PTR1
        lda #>discard_msg
        sta ZP_PTR1+1
        lda #2
        jsr print_centered
        lda discard_top
        jsr render_discard_card

        ; Show the whole public table, then this player's controls and hand.
        jsr render_player_table
        jsr render_help
        jsr render_hand

        rts

turn_msg:
        .byte "TURN: P", 0
discard_msg:
        .byte "DISCARD", 0

; -----------------------------------------------------------------------------
; Render all public hand counts in three compact rows (up to eight seats).
; Current player is yellow, this client is green, finished players are purple.
; -----------------------------------------------------------------------------
render_player_table:
        lda #<cards_left_msg
        sta ZP_PTR1
        lda #>cards_left_msg
        sta ZP_PTR1+1
        lda #8
        jsr print_centered
        ldx #0
rpt_loop:
        cpx player_count
        bcs rpt_done
        cpx #8
        bcs rpt_done
        lda player_table_x,x
        sta ZP_CURSOR_X
        lda player_table_y,x
        sta ZP_CURSOR_Y

        lda #COLOR_WHITE
        cpx my_index
        bne rpt_not_me
        lda #COLOR_GREEN
rpt_not_me:
        cpx current_turn
        bne rpt_not_turn
        lda #COLOR_YELLOW
rpt_not_turn:
        ldy player_counts,x
        bne rpt_have_color
        lda #COLOR_PURPLE
rpt_have_color:
        sta ZP_TEMP3

        lda #'P'
        jsr print_table_char
        txa
        clc
        adc #'1'
        jsr print_table_char
        lda #':'
        jsr print_table_char

        lda player_counts,x
        ldy #0
rpt_tens:
        cmp #10
        bcc rpt_digits
        sec
        sbc #10
        iny
        bne rpt_tens
rpt_digits:
        sta ZP_TEMP4
        tya
        clc
        adc #'0'
        jsr print_table_char
        lda ZP_TEMP4
        clc
        adc #'0'
        jsr print_table_char
        inx
        bne rpt_loop
rpt_done:
        rts

print_table_char:
        pha
        lda ZP_TEMP3
        jsr set_cursor_color
        pla
        jsr print_char
        rts

cards_left_msg:
        .byte "CARDS LEFT", 0
player_table_x:
        .byte 0, 7, 14, 0, 7, 14, 0, 7
player_table_y:
        .byte 9, 9, 9, 10, 10, 10, 11, 11

render_help:
        lda #14
        jsr display_clear_row
        lda #15
        jsr display_clear_row
        lda #16
        jsr display_clear_row
        lda player_out_flag
        beq rh_active
        lda #<watching_msg
        sta ZP_PTR1
        lda #>watching_msg
        sta ZP_PTR1+1
        lda #14
        jsr print_centered
        rts
rh_active:
        lda current_turn
        cmp my_index
        bne rh_waiting
        lda #<your_turn_msg
        sta ZP_PTR1
        lda #>your_turn_msg
        bne rh_help_print
rh_waiting:
        lda #<wait_turn_msg
        sta ZP_PTR1
        lda #>wait_turn_msg
rh_help_print:
        sta ZP_PTR1+1
        lda #14
        jsr print_centered
        lda solo_ui_active
        beq rh_online_controls
        lda #<solo_controls_msg
        sta ZP_PTR1
        lda #>solo_controls_msg
        bne rh_controls_ready
rh_online_controls:
        lda #<controls_msg
        sta ZP_PTR1
        lda #>controls_msg
rh_controls_ready:
        sta ZP_PTR1+1
        lda #15
        jsr print_centered
        lda #0
        sta ZP_CURSOR_X
        lda #16
        sta ZP_CURSOR_Y
        lda #<suit_help_msg
        sta ZP_PTR1
        lda #>suit_help_msg
        sta ZP_PTR1+1
        jsr print_string
        ldx chosen_suit
        jsr render_suit
        lda #<play_help_msg
        sta ZP_PTR1
        lda #>play_help_msg
        sta ZP_PTR1+1
        jsr print_string
        rts

your_turn_msg:
        .byte "YOUR TURN - D DRAWS", 0
wait_turn_msg:
        .byte "WAITING FOR TURN", 0
watching_msg:
        .byte "YOU'RE OUT - WATCHING", 0
controls_msg:
        .byte "LR MOVE SP/FIRE SEL", 0
solo_controls_msg:
        .byte "LR MOVE SP/FIRE PLAY", 0
suit_help_msg:
        .byte "UP/DN SUIT:", 0
play_help_msg:
        .byte " RET PLAY", 0

; -----------------------------------------------------------------------------
; Render player's hand
; Shows cards at bottom of screen
; -----------------------------------------------------------------------------
render_hand:
        lda #20
        jsr display_clear_row
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

        ; Show hand count as two decimal digits (hands can contain 52 cards).
        lda hand_count
        ldx #0
rh_tens:
        cmp #10
        bcc rh_digits
        sec
        sbc #10
        inx
        bne rh_tens
rh_digits:
        sta ZP_TEMP2
        txa
        clc
        adc #'0'
        jsr print_char
        lda ZP_TEMP2
        clc
        adc #'0'
        jsr print_char

        lda #':'
        jsr print_char

        lda #' '
        jsr print_char
        lda #'S'
        jsr print_char
        lda #'='
        jsr print_char
        ldx chosen_suit
        jsr render_suit

        ; Next line for cards
        lda #0
        sta ZP_CURSOR_X
        lda #20
        sta ZP_CURSOR_Y

        ; Five compact cards fit on a 22-column row. Show the page containing
        ; the cursor so every one of the possible 52 cards remains reachable.
        lda cursor_pos
rh_page:
        cmp #5
        bcc rh_page_ready
        sec
        sbc #5
        bcs rh_page
rh_page_ready:
        sta ZP_TEMP1
        lda cursor_pos
        sec
        sbc ZP_TEMP1
        sta ZP_TEMP1
        lda cursor_pos
        sec
        sbc ZP_TEMP1
        tax
        txa
        clc
        adc #5
        sta ZP_TEMP2
rh_loop:
        cpx hand_count
        bcs rh_done
        cpx ZP_TEMP2
        bcs rh_done

        ; Check if this is cursor position
        cpx cursor_pos
        bne rh_no_cursor
        lda #COLOR_YELLOW
        jsr set_cursor_color
        lda #'['
        jsr print_char
        jmp rh_card

rh_no_cursor:
        lda #' '
        jsr print_char

rh_card:
        ; Get card value
        txa
        pha
        lda my_hand,x
        jsr render_card_short
        pla
        tax

        ; Check if selected
        jsr check_selected
        bcc rh_not_sel
        lda #COLOR_YELLOW
        jsr set_cursor_color
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
        lda selected_cards,x
        beq cs_not_sel
        sec
        rts

cs_not_sel:
        clc
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
        lda #COLOR_WHITE
        jsr set_cursor_color
        lda rank_chars,x
        jsr print_char

        ; Suit occupies bits 7-6 in the canonical card byte.
        pla
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        and #$03
        tax
        jsr render_suit

        rts

; -----------------------------------------------------------------------------
; Render a five-by-five PETSCII discard card centred on the screen.
; Input: A = card byte
; -----------------------------------------------------------------------------
render_discard_card:
        sta ZP_TEMP4
        lda #8
        sta ZP_CURSOR_X
        lda #3
        sta ZP_CURSOR_Y
        lda #SC_TOP_LEFT
        jsr render_frame_char
        lda #SC_HLINE
        jsr render_frame_char
        lda #SC_HLINE
        jsr render_frame_char
        lda #SC_HLINE
        jsr render_frame_char
        lda #SC_TOP_RIGHT
        jsr render_frame_char

        lda #8
        sta ZP_CURSOR_X
        lda #4
        sta ZP_CURSOR_Y
        lda #SC_VLINE
        jsr render_frame_char
        lda ZP_TEMP4
        and #$0f
        tax
        lda rank_chars,x
        jsr print_char
        lda #' '
        jsr print_char
        lda ZP_TEMP4
        jsr card_suit_index
        jsr render_suit
        lda #SC_VLINE
        jsr render_frame_char

        lda #8
        sta ZP_CURSOR_X
        lda #5
        sta ZP_CURSOR_Y
        lda #SC_VLINE
        jsr render_frame_char
        lda #' '
        jsr print_char
        lda ZP_TEMP4
        jsr card_suit_index
        jsr render_suit
        lda #' '
        jsr print_char
        lda #SC_VLINE
        jsr render_frame_char

        lda #8
        sta ZP_CURSOR_X
        lda #6
        sta ZP_CURSOR_Y
        lda #SC_VLINE
        jsr render_frame_char
        lda ZP_TEMP4
        jsr card_suit_index
        jsr render_suit
        lda #' '
        jsr print_char
        lda ZP_TEMP4
        and #$0f
        tax
        lda rank_chars,x
        jsr print_char
        lda #SC_VLINE
        jsr render_frame_char

        lda #8
        sta ZP_CURSOR_X
        lda #7
        sta ZP_CURSOR_Y
        lda #SC_BOTTOM_LEFT
        jsr render_frame_char
        lda #SC_HLINE
        jsr render_frame_char
        lda #SC_HLINE
        jsr render_frame_char
        lda #SC_HLINE
        jsr render_frame_char
        lda #SC_BOTTOM_RIGHT
        jsr render_frame_char
        rts

card_suit_index:
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        and #$03
        tax
        rts

render_suit:
        lda suit_colors,x
        jsr set_cursor_color
        lda suit_codes,x
        jsr print_screen_code
        rts

render_frame_char:
        pha
        lda #COLOR_WHITE
        jsr set_cursor_color
        pla
        jsr print_screen_code
        rts

; Card data
rank_chars:
        .byte '?', 'A', '2', '3', '4', '5', '6', '7'
        .byte '8', '9', 'T', 'J', 'Q', 'K', 'A', '?'

; Raw VIC screen codes in RUBP suit order: hearts, diamonds, clubs, spades.
suit_codes:
        .byte $53, $5a, $58, $41
suit_colors:
        .byte COLOR_RED, COLOR_RED, COLOR_CYAN, COLOR_CYAN

; Box-drawing glyphs from the VIC-20 uppercase/graphics character ROM.
SC_HLINE        = $40
SC_TOP_RIGHT    = $49
SC_BOTTOM_LEFT  = $4a
SC_BOTTOM_RIGHT = $4b
SC_TOP_LEFT     = $55
SC_VLINE        = $5d
