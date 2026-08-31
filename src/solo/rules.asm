; =============================================================================
; SOLO RULE QUERIES, ACTION ENUMERATION AND PRIVATE STORAGE
; =============================================================================

solo_last_action_suit:
        ldx solo_effect_leader
        stx solo_last_suit
        ldx #0
slas_loop:
        cpx solo_effect_leader
        beq slas_next
        lda solo_bit_table,x
        and solo_action_suit_mask
        beq slas_next
        stx solo_last_suit
slas_next:
        inx
        cpx #4
        bcc slas_loop
        lda solo_last_suit
        rts

solo_find_action_leader:
        ldx #0
sfal_loop:
        lda solo_bit_table,x
        and solo_action_suit_mask
        beq sfal_next
        stx solo_scan_suit
        jsr solo_card_is_legal
        bcc sfal_found
sfal_next:
        inx
        cpx #4
        bcc sfal_loop
sfal_found:
        stx solo_effect_leader
        rts

solo_mark_out_if_empty:
        ldy #7
        lda solo_workspace+SW_CURRENT_PLAYER
        beq smo_player
        ldx #7
        bne smo_scan
smo_player:
        ldx #0
smo_scan:
        lda solo_workspace+SW_HAND_MASKS,x
        bne smo_not_empty
        inx
        dey
        bne smo_scan
        lda #1
        sta solo_workspace+SW_FINISH_COUNT
        lda solo_workspace+SW_CURRENT_PLAYER
        sta solo_workspace+SW_FINISH_ORDER
smo_not_empty:
        rts

; Compact two-player turn advancement, including chained seven responses.
solo_advance_turn:
        inc solo_workspace+SW_TURN_NUMBER
        bne sat_turn_ok
        inc solo_workspace+SW_TURN_NUMBER+1
        bne sat_turn_ok
        inc solo_workspace+SW_TURN_NUMBER+2
        bne sat_turn_ok
        inc solo_workspace+SW_TURN_NUMBER+3
sat_turn_ok:
        lda solo_workspace+SW_PENDING_SKIPS
        beq sat_move
sat_skip:
        lda solo_workspace+SW_CURRENT_PLAYER
        eor #1
        sta solo_workspace+SW_CURRENT_PLAYER
        jsr solo_has_seven
        bcc sat_done
        dec solo_workspace+SW_PENDING_SKIPS
        bne sat_skip
sat_move:
        lda solo_workspace+SW_CURRENT_PLAYER
        eor #1
        sta solo_workspace+SW_CURRENT_PLAYER
sat_done:
        rts

; C=0 if the current player can answer a pending skip with any seven.
solo_has_seven:
        lda #7
        sta solo_scan_rank
        ldx #0
shs_loop:
        stx solo_scan_suit
        jsr solo_hand_has_card
        bcc shs_yes
        ldx solo_scan_suit
        inx
        cpx #4
        bcc shs_loop
        sec
        rts
shs_yes:
        clc
        rts

; Offer the current rank/mask/nomination. C=0 if it is the requested action;
; C=1 asks the enumerator to continue.
solo_offer_action:
        lda solo_action_seen
        cmp solo_action_wanted
        beq soa_match
        inc solo_action_seen
        sec
        rts
soa_match:
        lda #SOLO_ACTION_PLAY
        sta solo_action_kind
        lda solo_scan_rank
        sta solo_action_rank
        lda solo_scan_mask
        sta solo_action_suit_mask
        lda solo_scan_nomination
        sta solo_action_nomination
        clc
        rts

; C=0 if scan_mask is one canonical play for scan_rank. Singles must
; independently be legal. Multi-card stacks are the canonical valid leader
; followed by the remaining held suits in ascending order.
solo_mask_is_action:
        lda #0
        sta solo_group_mask
        sta solo_valid_mask
        ldx #0
smia_suits:
        stx solo_scan_suit
        jsr solo_hand_has_card
        ldx solo_scan_suit
        bcs smia_no_card
        lda solo_bit_table,x
        ora solo_group_mask
        sta solo_group_mask
        jsr solo_card_is_legal
        bcs smia_no_card
        lda solo_bit_table,x
        ora solo_valid_mask
        sta solo_valid_mask
smia_no_card:
        ldx solo_scan_suit
        inx
        cpx #4
        bcc smia_suits

        lda solo_scan_mask
        jsr solo_popcount4
        cmp #1
        bne smia_stack
        lda solo_scan_mask
        and solo_valid_mask
        beq smia_bad
        lda solo_scan_mask
        and solo_group_mask
        cmp solo_scan_mask
        bne smia_bad
        clc
        rts
smia_stack:
        ; Build each canonical prefix and accept when it equals scan_mask.
        lda solo_valid_mask
        beq smia_bad
        ldx #0
smia_find_leader:
        lda solo_bit_table,x
        and solo_valid_mask
        bne smia_leader
        inx
        cpx #4
        bcc smia_find_leader
        bcs smia_bad
smia_leader:
        lda solo_bit_table,x
        sta solo_prefix_mask
        ldy #1
        ldx #0
smia_prefix:
        lda solo_bit_table,x
        and solo_group_mask
        beq smia_prefix_next
        lda solo_bit_table,x
        and solo_prefix_mask
        bne smia_prefix_next
        lda solo_bit_table,x
        ora solo_prefix_mask
        sta solo_prefix_mask
        iny
        cpy #2
        bcc smia_prefix_next
        lda solo_prefix_mask
        cmp solo_scan_mask
        beq smia_good
smia_prefix_next:
        inx
        cpx #4
        bcc smia_prefix
smia_bad:
        sec
        rts
smia_good:
        clc
        rts

; X=suit, scan_rank=2...14. C=0 when current player's mask contains it.
solo_hand_has_card:
        lda solo_workspace+SW_CURRENT_PLAYER
        beq shhc_player
        lda #7
shhc_player:
        sta solo_hand_offset
        txa
        asl
        asl
        asl
        clc
        adc solo_scan_suit       ; suit * 9
        adc solo_scan_suit       ; suit * 10
        adc solo_scan_suit       ; suit * 11
        adc solo_scan_suit       ; suit * 12
        adc solo_scan_suit       ; suit * 13
        clc
        adc solo_scan_rank
        sec
        sbc #2
        tay
        and #7
        tax
        tya
        lsr
        lsr
        lsr
        clc
        adc solo_hand_offset
        tay
        lda solo_workspace+SW_HAND_MASKS,y
        and solo_bit_table,x
        beq shhc_absent
        clc
        rts
shhc_absent:
        sec
        rts

; scan_suit/scan_rank against attacks, nomination, and top discard. C=0 legal.
solo_card_is_legal:
        lda solo_workspace+SW_PENDING_SKIPS
        beq scil_draw
        lda solo_scan_rank
        cmp #7
        beq scil_good
        bne scil_bad
scil_draw:
        lda solo_workspace+SW_PENDING_DRAWS
        beq scil_normal
        lda solo_workspace+SW_TOP_DISCARD
        and #$3f
        cmp #2
        bne scil_jack_attack
        lda solo_scan_rank
        cmp #2
        beq scil_good
        bne scil_bad
scil_jack_attack:
        cmp #11
        bne scil_bad
        lda solo_workspace+SW_TOP_DISCARD
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        cmp #2
        bcc scil_bad             ; only a black Jack starts this attack
        lda solo_scan_rank
        cmp #11                  ; either black stack or red counter
        beq scil_good
        bne scil_bad
scil_normal:
        lda solo_workspace+SW_PACKED_FLAGS
        lsr
        and #7
        beq scil_top
        sec
        sbc #1
        cmp solo_scan_suit
        beq scil_good
        lda solo_scan_rank
        cmp #14                  ; Ace on Ace while nomination is active
        beq scil_good
        bne scil_bad
scil_top:
        lda solo_workspace+SW_TOP_DISCARD
        and #$3f
        cmp solo_scan_rank
        beq scil_good
        lda solo_workspace+SW_TOP_DISCARD
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        cmp solo_scan_suit
        beq scil_good
scil_bad:
        sec
        rts
scil_good:
        clc
        rts

solo_popcount4:
        ldx #0
        ldy #4
solo_pc_loop:
        lsr
        bcc solo_pc_next
        inx
solo_pc_next:
        dey
        bne solo_pc_loop
        txa
        rts

solo_bit_table:
        .byte 1,2,4,8,16,32,64,128

solo_action_count:      .byte 0
solo_action_query:      .byte 0
solo_action_wanted:     .byte 0
solo_action_seen:       .byte 0
solo_action_kind:       .byte 0
solo_action_rank:       .byte 0
solo_action_suit_mask:  .byte 0
solo_action_nomination: .byte 0
solo_scan_rank:         .byte 0
solo_scan_mask:         .byte 0
solo_scan_nomination:   .byte 0
solo_scan_suit:         .byte 0
solo_group_mask:        .byte 0
solo_valid_mask:        .byte 0
solo_prefix_mask:       .byte 0
solo_hand_offset:       .byte 0
solo_action_card_count: .byte 0
solo_effect_leader:     .byte 0
solo_draw_remaining:    .byte 0
solo_drawn_ordinal:     .byte 0
solo_pack_temp:         .byte 0
solo_last_suit:         .byte 0
solo_deck_index:        .byte 0
solo_shuffle_index:     .byte 0
solo_swap_index:        .byte 0
solo_swap_card:         .byte 0
solo_deal_remaining:    .byte 0
solo_mod_divisor:       .byte 0
solo_mod_remainder:     .byte 0
solo_mod_source:        .byte 0
solo_pack_value:        .byte 0
solo_value_mask:        .byte 0
solo_deck_mask:         .byte 0
solo_bit_position:      .word 0
solo_pack_byte:         .byte 0
solo_archive_index:     .byte 0
solo_shuffle_count:     .byte 0
solo_save_checksum:     .byte 0
solo_load_total:        .byte 0
solo_ai_soak_remaining: .byte 0
solo_complete_remaining: .byte 0
solo_complete_pages:    .byte 0
solo_complete_action_count: .byte 0
solo_complete_games_remaining: .byte 0
solo_complete_games_passed: .byte 0
solo_complete_games_bounded: .byte 0
solo_complete_failure:  .byte 0
