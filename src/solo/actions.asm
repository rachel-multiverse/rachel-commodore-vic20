; =============================================================================
; SOLO ACTION CATALOGUE AND APPLICATION
; =============================================================================

; In: A=zero-based action index. Out: C clear and action fields populated;
; C set if out of range. Clobbers: A, X and action-enumeration temporaries.
solo_get_action_at:
        sta solo_action_wanted
        lda #0
        sta solo_action_seen
        lda #2
        sta solo_scan_rank
sgaa_rank:
        lda #1
        sta solo_scan_mask
sgaa_mask:
        jsr solo_mask_is_action
        bcs sgaa_next_mask
        lda solo_scan_rank
        cmp #14
        bne sgaa_one_action
        lda #0
        sta solo_scan_nomination
sgaa_ace:
        jsr solo_offer_action
        bcc sgaa_found
        inc solo_scan_nomination
        lda solo_scan_nomination
        cmp #4
        bcc sgaa_ace
        bcs sgaa_next_mask
sgaa_one_action:
        lda #SOLO_NO_SUIT
        sta solo_scan_nomination
        jsr solo_offer_action
        bcc sgaa_found
sgaa_next_mask:
        inc solo_scan_mask
        lda solo_scan_mask
        cmp #16
        bcc sgaa_mask
        inc solo_scan_rank
        lda solo_scan_rank
        cmp #15
        bcc sgaa_rank

        ; DRAW exists precisely when no play exists.
        lda solo_action_seen
        bne sgaa_missing
        lda solo_action_wanted
        bne sgaa_missing
        lda #SOLO_ACTION_DRAW
        sta solo_action_kind
        lda #0
        sta solo_action_rank
        sta solo_action_suit_mask
        lda #SOLO_NO_SUIT
        sta solo_action_nomination
        clc
        rts
sgaa_missing:
        sec
        rts
sgaa_found:
        clc
        rts

; Input A = indexed catalogue action. C=0 on success, C=1 on rejection.
; Validation completes before the first workspace write, so rejected actions
; cannot partially mutate state.
; In: A=zero-based action index. Out: C clear if applied, C set if invalid.
; Clobbers: A, X, Y, action fields and gameplay temporaries.
solo_apply_action:
        jsr solo_get_action_at
        bcs saa_reject
        lda solo_action_kind
        cmp #SOLO_ACTION_DRAW
        beq saa_draw
        jsr solo_apply_play
        clc
        rts
saa_draw:
        jsr solo_apply_draw
        clc
        rts
saa_reject:
        sec
        rts

solo_apply_play:
        jsr solo_find_action_leader
        jsr solo_archive_played_cards
        ; Remove every selected suit from the acting player's hand.
        ldx #0
sap_remove:
        lda solo_bit_table,x
        and solo_action_suit_mask
        beq sap_remove_next
        stx solo_scan_suit
        jsr solo_hand_clear_card
        ldx solo_scan_suit
sap_remove_next:
        inx
        cpx #4
        bcc sap_remove

        ; Effects run in canonical card order: the lowest legal leader first,
        ; then remaining selected suits ascending. This matters for red/black
        ; Jack counter stacks.
        lda solo_action_rank
        cmp #11
        bne sap_simple_effects
        jsr solo_apply_jack_effects
        jmp sap_nomination
sap_simple_effects:
        lda solo_action_suit_mask
        jsr solo_popcount4
        sta solo_action_card_count
        lda solo_action_rank
        cmp #2
        bne sap_seven
sap_twos:
        lda solo_workspace+SW_PENDING_DRAWS
        clc
        adc #2
        sta solo_workspace+SW_PENDING_DRAWS
        dec solo_action_card_count
        bne sap_twos
        beq sap_nomination
sap_seven:
        cmp #7
        bne sap_queen
        lda solo_workspace+SW_PENDING_SKIPS
        clc
        adc solo_action_card_count
        sta solo_workspace+SW_PENDING_SKIPS
        jmp sap_nomination
sap_queen:
        cmp #12
        bne sap_nomination
        lda solo_action_card_count
        and #1
        beq sap_nomination
        lda solo_workspace+SW_PACKED_FLAGS
        eor #1
        sta solo_workspace+SW_PACKED_FLAGS

sap_nomination:
        lda solo_workspace+SW_PACKED_FLAGS
        and #1
        sta solo_workspace+SW_PACKED_FLAGS
        lda solo_action_rank
        cmp #14
        bne sap_top
        lda solo_action_nomination
        clc
        adc #1
        asl
        ora solo_workspace+SW_PACKED_FLAGS
        sta solo_workspace+SW_PACKED_FLAGS

sap_top:
        jsr solo_last_action_suit
        asl
        asl
        asl
        asl
        asl
        asl
        ora solo_action_rank
        sta solo_workspace+SW_TOP_DISCARD
        lda solo_action_suit_mask
        jsr solo_popcount4
        clc
        adc solo_workspace+SW_DISCARD_COUNT
        sta solo_workspace+SW_DISCARD_COUNT
        jsr solo_mark_out_if_empty
        jsr solo_advance_turn
        rts

solo_apply_jack_effects:
        ; Apply the canonical leader captured before mutation.
        ldx solo_effect_leader
        jsr solo_apply_one_jack
        ldx #0
saje_rest:
        cpx solo_effect_leader
        beq saje_rest_next
        lda solo_bit_table,x
        and solo_action_suit_mask
        beq saje_rest_next
        jsr solo_apply_one_jack
saje_rest_next:
        inx
        cpx #4
        bcc saje_rest
        rts

; X=suit. Hearts/diamonds reduce five; clubs/spades add five.
solo_apply_one_jack:
        cpx #2
        bcs saoj_black
        lda solo_workspace+SW_PENDING_DRAWS
        cmp #5
        bcc saoj_zero
        sec
        sbc #5
        sta solo_workspace+SW_PENDING_DRAWS
        rts
saoj_zero:
        lda #0
        sta solo_workspace+SW_PENDING_DRAWS
        rts
saoj_black:
        lda solo_workspace+SW_PENDING_DRAWS
        clc
        adc #5
        sta solo_workspace+SW_PENDING_DRAWS
        rts

solo_apply_draw:
        lda solo_workspace+SW_PENDING_DRAWS
        bne sad_count
        lda #1
sad_count:
        sta solo_draw_remaining
sad_loop:
        lda solo_workspace+SW_DECK_COUNT
        bne sad_pop
        jsr solo_recycle_discards
        lda solo_workspace+SW_DECK_COUNT
        beq sad_done
sad_pop:
        jsr solo_deck_pop
        jsr solo_hand_set_ordinal
        dec solo_draw_remaining
        bne sad_loop
sad_done:
        lda #0
        sta solo_workspace+SW_PENDING_DRAWS
        jsr solo_advance_turn
        rts

; Preserve the complete discard order in the packed area after the live deck.
; Append the old top, then every played card except the new (last) top.
solo_archive_played_cards:
        lda solo_workspace+SW_DECK_COUNT
        clc
        adc solo_workspace+SW_DISCARD_COUNT
        sec
        sbc #1
        sta solo_archive_index
        lda solo_workspace+SW_TOP_DISCARD
        jsr solo_card_to_ordinal
        jsr solo_archive_ordinal
        ldx solo_effect_leader
        jsr solo_archive_suit_unless_last
        ldx #0
sapc_rest:
        cpx solo_effect_leader
        beq sapc_next
        lda solo_bit_table,x
        and solo_action_suit_mask
        beq sapc_next
        jsr solo_archive_suit_unless_last
sapc_next:
        inx
        cpx #4
        bcc sapc_rest
        rts

solo_archive_suit_unless_last:
        stx solo_scan_suit
        jsr solo_last_action_suit
        cmp solo_scan_suit
        beq sasu_done
        lda solo_scan_suit
        asl
        asl
        asl
        clc
        adc solo_scan_suit
        adc solo_scan_suit
        adc solo_scan_suit
        adc solo_scan_suit
        adc solo_scan_suit       ; suit * 13
        clc
        adc solo_action_rank
        sec
        sbc #2
        jsr solo_archive_ordinal
sasu_done:
        ldx solo_scan_suit
        rts

solo_archive_ordinal:
        ldx solo_archive_index
        jsr solo_deck_set_at
        inc solo_archive_index
        rts

; When the draw boundary reaches zero, the packed prefix is exactly the buried
; discard pile in chronological order. Shuffle it and retain only the top.
solo_recycle_discards:
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #2
        bcc srd_done
        sec
        sbc #1
        sta solo_workspace+SW_DECK_COUNT
        sta solo_shuffle_count
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda solo_shuffle_count
        cmp #2
        bcc srd_done
        sec
        sbc #1
        sta solo_shuffle_index
srd_shuffle:
        jsr solo_rng_next
        lda solo_shuffle_index
        clc
        adc #1
        jsr solo_rng_mod
        sta solo_swap_index
        ldx solo_shuffle_index
        jsr solo_deck_get_at
        sta solo_swap_card
        ldx solo_swap_index
        jsr solo_deck_get_at
        pha
        ldx solo_shuffle_index
        pla
        jsr solo_deck_set_at
        lda solo_swap_card
        ldx solo_swap_index
        jsr solo_deck_set_at
        dec solo_shuffle_index
        bne srd_shuffle
srd_done:
        rts

; A=RUBP card encoding -> A=ordinal.
