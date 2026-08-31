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
        ; render_table_state owns rows 12 and 13 and clears them itself.

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
        jsr render_direction

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
        jsr render_table_state
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

        txa
        pha                     ; print_two_digits needs X for its own division
        lda player_counts,x
        jsr print_two_digits
        pla
        tax
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

; Print a null-terminated string in ZP_TEMP3's colour. set_cursor_color does
; not preserve Y, so the index is carried across each character by hand.
; Input: ZP_PTR1 = string address.
print_string_color:
        ldy #0
psc_loop:
        lda (ZP_PTR1),y
        beq psc_done
        tya
        pha
        lda (ZP_PTR1),y
        jsr print_table_char
        pla
        tay
        iny
        bne psc_loop
psc_done:
        rts

; Print A as two decimal digits in ZP_TEMP3's colour. Counts reach 52.
; Clobbers A, X and ZP_TEMP4.
print_two_digits:
        ldx #0
ptd_tens:
        cmp #10
        bcc ptd_ones
        sec
        sbc #10
        inx
        bne ptd_tens
ptd_ones:
        sta ZP_TEMP4
        txa
        clc
        adc #'0'
        jsr print_table_char
        lda ZP_TEMP4
        clc
        adc #'0'
        jmp print_table_char

cards_left_msg:
        .byte "CARDS LEFT", 0
player_table_x:
        .byte 0, 7, 14, 0, 7, 14, 0, 7
player_table_y:
        .byte 9, 9, 9, 10, 10, 10, 11, 11

; -----------------------------------------------------------------------------
; Play direction, beside the turn indicator on row 0. Solo keeps it in the
; workspace's packed flags and online in the field the host sends; until now
; neither was drawn anywhere.
; -----------------------------------------------------------------------------
render_direction:
        lda #COLOR_GREEN
        sta ZP_TEMP3
        lda #16
        sta ZP_CURSOR_X
        lda solo_ui_active
        beq rd_online
        lda solo_workspace+SW_PACKED_FLAGS
        and #1
        jmp rd_glyph
rd_online:
        lda direction
rd_glyph:
        beq rd_forward
        lda #'<'
        bne rd_draw
rd_forward:
        lda #'>'
rd_draw:
        jmp print_table_char

; -----------------------------------------------------------------------------
; Rows 12 and 13: the pending attack, then the deck size and any live Ace
; nomination. Every value here was already tracked for both solo and online
; play and none of it had ever reached the screen.
;
; All three attack lines are nineteen columns wide, so they share column 1.
; -----------------------------------------------------------------------------
render_table_state:
        lda #12
        jsr display_clear_row
        lda #13
        jsr display_clear_row
        lda #19                 ; transient feedback from main.asm
        jsr display_clear_row

        lda #1
        sta ZP_CURSOR_X
        lda #12
        sta ZP_CURSOR_Y

        lda pending_draws
        beq rs_skips
        lda #COLOR_RED
        sta ZP_TEMP3
        lda #<draw_msg
        sta ZP_PTR1
        lda #>draw_msg
        sta ZP_PTR1+1
        jsr print_string_color
        lda pending_draws
        jsr print_two_digits
        ; A twos attack is answered only by another 2; a black Jack attack by
        ; either colour of Jack, the red one to cancel five of it.
        lda discard_top
        and #$0f
        cmp #2
        bne rs_jack_attack
        lda #<answer_two_msg
        sta ZP_PTR1
        lda #>answer_two_msg
        bne rs_answer
rs_jack_attack:
        lda #<answer_jack_msg
        sta ZP_PTR1
        lda #>answer_jack_msg
rs_answer:
        sta ZP_PTR1+1
        jsr print_string_color
        jmp rs_deck
rs_skips:
        lda pending_skips
        beq rs_deck
        lda #COLOR_YELLOW
        sta ZP_TEMP3
        lda #<skip_msg
        sta ZP_PTR1
        lda #>skip_msg
        sta ZP_PTR1+1
        jsr print_string_color
        lda pending_skips
        jsr print_two_digits
        lda #<answer_seven_msg
        sta ZP_PTR1
        lda #>answer_seven_msg
        sta ZP_PTR1+1
        jsr print_string_color

rs_deck:
        lda #0
        sta ZP_CURSOR_X
        lda #13
        sta ZP_CURSOR_Y
        lda #COLOR_WHITE
        sta ZP_TEMP3
        lda #<deck_msg
        sta ZP_PTR1
        lda #>deck_msg
        sta ZP_PTR1+1
        jsr print_string_color
        lda deck_count
        jsr print_two_digits

        lda nominated_suit_recv
        cmp #SOLO_NO_SUIT
        beq rs_done
        and #$03
        sta ZP_TEMP4
        lda #16
        sta ZP_CURSOR_X
        lda #COLOR_YELLOW
        sta ZP_TEMP3
        lda #<suit_msg
        sta ZP_PTR1
        lda #>suit_msg
        sta ZP_PTR1+1
        jsr print_string_color
        ldx ZP_TEMP4
        jsr render_suit
rs_done:
        lda #COLOR_WHITE
        sta ZP_TEMP3
        rts

draw_msg:
        .byte "DRAW ", 0
skip_msg:
        .byte "SKIP ", 0
answer_two_msg:
        .byte " OR PLAY A 2", 0
answer_jack_msg:
        .byte " OR RED JACK", 0
answer_seven_msg:
        .byte " OR PLAY A 7", 0
deck_msg:
        .byte "DECK ", 0
suit_msg:
        .byte "SUIT ", 0

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
        ; Both modes nominate through a prompt at the moment the Ace is played,
        ; so neither has a standing suit control to explain. Online play takes
        ; the spare row to say what RETURN does with a multi-card selection.
        lda solo_ui_active
        bne rh_help_done
        lda #<select_help_msg
        sta ZP_PTR1
        lda #>select_help_msg
        sta ZP_PTR1+1
        lda #16
        jsr print_centered
rh_help_done:
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
select_help_msg:
        .byte "RET PLAYS SELECTION", 0

; -----------------------------------------------------------------------------
; Render player's hand
; Shows cards at bottom of screen
; -----------------------------------------------------------------------------
render_hand:
        lda #18
        jsr display_clear_row
        lda #20
        jsr display_clear_row

        ; Five compact cards fit on a 22-column row. Work out which page holds
        ; the cursor before drawing anything: row 18 reports the page and row
        ; 20 draws it, so every one of the possible 52 cards stays reachable.
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
        sta ZP_TEMP1            ; first card on the cursor's page
        clc
        adc #5
        sta ZP_TEMP2            ; one past the last card on the page

        lda #0
        sta ZP_CURSOR_X
        lda #18
        sta ZP_CURSOR_Y
        lda #COLOR_WHITE
        sta ZP_TEMP3
        lda #<hand_msg
        sta ZP_PTR1
        lda #>hand_msg
        sta ZP_PTR1+1
        jsr print_string_color
        lda hand_count
        jsr print_two_digits
        jsr render_hand_page

        ; Next line for cards
        lda #0
        sta ZP_CURSOR_X
        lda #20
        sta ZP_CURSOR_Y
        ldx ZP_TEMP1
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
        ; ASCII '[' is $5b, which is a graphics glyph in VIC screen codes. The
        ; bracket itself is $1b, so it has to bypass the PETSCII path.
        lda #SC_LBRACKET
        jsr print_screen_code
        jmp rh_card

rh_no_cursor:
        lda #' '
        jsr print_char

rh_card:
        ; Get card value
        txa
        pha
        lda my_hand,x
        jsr set_card_playability
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

; Modal suit nomination on row 17, shared by both modes. Left/right or up/down
; choose, RETURN or SPACE confirms, RUN/STOP abandons the play.
; Out: C=0 with chosen_suit set, C=1 when the player backed out of the play.
; Clobbers: A, X, Y and the shared display scratch.
pick_suit_modal:
sps_draw:
        lda #17
        jsr display_clear_row
        lda #2
        sta ZP_CURSOR_X
        lda #17
        sta ZP_CURSOR_Y
        lda #COLOR_YELLOW
        sta ZP_TEMP3
        lda #<nominate_msg
        sta ZP_PTR1
        lda #>nominate_msg
        sta ZP_PTR1+1
        jsr print_string_color
        ldx chosen_suit
        jsr render_suit
        lda #COLOR_YELLOW
        sta ZP_TEMP3
        lda #<nominate_help_msg
        sta ZP_PTR1
        lda #>nominate_help_msg
        sta ZP_PTR1+1
        jsr print_string_color
sps_key:
        jsr sound_update
        jsr get_input
        beq sps_key
        cmp #KEY_LEFT
        beq sps_prev
        cmp #KEY_DOWN
        beq sps_prev
        cmp #KEY_RIGHT
        beq sps_next
        cmp #KEY_UP
        beq sps_next
        cmp #KEY_RETURN
        beq sps_confirm
        cmp #KEY_SPACE
        beq sps_confirm
        cmp #KEY_ESC
        beq sps_cancel
        bne sps_key
sps_next:
        jsr sound_move
        inc chosen_suit
        lda chosen_suit
        and #3
        sta chosen_suit
        jmp sps_draw
sps_prev:
        jsr sound_move
        lda chosen_suit
        sec
        sbc #1
        and #3
        sta chosen_suit
        jmp sps_draw
sps_confirm:
        jsr sound_action
        lda #17
        jsr display_clear_row
        clc
        rts
sps_cancel:
        jsr sound_error
        lda #17
        jsr display_clear_row
        sec
        rts

nominate_msg:      .byte "NOMINATE ", 0
nominate_help_msg: .byte "  LR RET", 0

; -----------------------------------------------------------------------------
; Row 18 page indicator. A hand of five or fewer never pages, so it says
; nothing; longer hands report the visible slice and which way more cards lie.
; Reads the page bounds left in ZP_TEMP1/ZP_TEMP2 by render_hand.
; -----------------------------------------------------------------------------
render_hand_page:
        lda hand_count
        cmp #6
        bcc rhp_done
        lda #8
        sta ZP_CURSOR_X
        lda #COLOR_YELLOW
        sta ZP_TEMP3
        ldx ZP_TEMP1
        lda #'<'
        cpx #0
        bne rhp_left
        lda #' '
rhp_left:
        jsr print_table_char
        lda ZP_TEMP1
        clc
        adc #1                  ; report card numbers from one, not zero
        jsr print_two_digits
        lda #'-'
        jsr print_table_char
        lda ZP_TEMP2
        cmp hand_count
        bcc rhp_last
        lda hand_count
rhp_last:
        jsr print_two_digits
        lda ZP_TEMP2
        cmp hand_count
        bcs rhp_no_more
        lda #'>'
        bne rhp_more
rhp_no_more:
        lda #' '
rhp_more:
        jsr print_table_char
rhp_done:
        lda #COLOR_WHITE
        sta ZP_TEMP3
        rts

; -----------------------------------------------------------------------------
; Decide whether the card in A can be played right now, leaving the answer in
; ZP_TEMP4 for render_card_short (0 = playable, 1 = dim it).
;
; Only solo play answers this. Online play is render-only and the host owns
; legality, so it never dims a card: see
; docs/knowledge/decisions/0003-clients-render-the-host-decides.md.
; The solo answer comes from solo_card_is_legal, the same predicate the action
; enumerator uses, so the display cannot disagree with what the kernel accepts.
; Preserves X and Y.
; -----------------------------------------------------------------------------
set_card_playability:
        pha
        lda #0
        sta ZP_TEMP4
        lda solo_ui_active
        beq scp_done
        lda current_turn
        cmp my_index
        bne scp_done
        pla
        pha
        and #$0f
        sta solo_scan_rank
        pla
        pha
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        and #$03
        sta solo_scan_suit
        jsr solo_card_is_legal
        bcc scp_done
        lda #1
        sta ZP_TEMP4
scp_done:
        pla
        rts

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
; ZP_TEMP4 selects the treatment: a playable card keeps a white rank and its
; suit's own red or cyan, an unplayable one drops to blue. Blue on the black
; background reads as dim without costing a colour the suits already use.
render_card_short:
        pha

        ; Get rank (low nibble)
        and #$0F
        tax
        lda #COLOR_WHITE
        ldy ZP_TEMP4
        beq rcs_rank_color
        lda #COLOR_BLUE
rcs_rank_color:
        jsr set_cursor_color
        lda rank_chars,x
        jsr print_char

        ; Suit occupies bits 7-6 in the canonical card byte.
        pla
        jsr card_suit_index
        lda ZP_TEMP4
        beq rcs_suit_normal
        lda #COLOR_BLUE
        jsr set_cursor_color
        lda suit_codes,x
        jmp print_screen_code
rcs_suit_normal:
        jmp render_suit

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
SC_LBRACKET     = $1b
