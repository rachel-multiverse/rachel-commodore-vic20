; =============================================================================
; RACHEL COMPACT TWO-PLAYER SOLO WORKSPACE BINDING
; =============================================================================
;
; Offline lifetime only: the 80-byte constrained_2p_v2 workspace overlays the
; first 80 bytes of the contiguous RUBP TX/RX buffers. Its 16 scratch bytes use
; RX offsets 16-31. Online code and solo code must never be live together.

SOLO_WS_SIZE       = 80
SOLO_SCRATCH_SIZE  = 16
solo_workspace     = tx_buffer
solo_scratch       = rx_buffer+16

SW_LAYOUT_VERSION  = 0
SW_PLAYER_COUNT    = 1
SW_CURRENT_PLAYER  = 2
SW_PACKED_FLAGS    = 3
SW_PENDING_DRAWS   = 4
SW_PENDING_SKIPS   = 5
SW_TURN_NUMBER     = 6
SW_RANDOM_SEED     = 10
SW_FINISH_COUNT    = 18
SW_FINISH_ORDER    = 19
SW_DECK_COUNT      = 20
SW_PACKED_DECK     = 21
SW_DISCARD_COUNT   = 60
SW_TOP_DISCARD     = 61
SW_HAND_MASKS      = 62

SOLO_ACTION_PLAY   = 0
SOLO_ACTION_DRAW   = 1
SOLO_NO_SUIT       = $ff

; Return A = number of legal actions. The catalogue order is the portable ABI
; order: rank, suit bitmask, nomination; DRAW follows every play. No action
; table is allocated.
solo_get_action_count:
        lda #0
        sta solo_action_count
        sta solo_action_query
sgac_loop:
        lda solo_action_query
        jsr solo_get_action_at
        bcs sgac_done
        inc solo_action_count
        inc solo_action_query
        bne sgac_loop
sgac_done:
        lda solo_action_count
        rts

; Input A = zero-based action index. C=0 and the solo_action_* fields describe
; the action; C=1 means out of range. Enumeration uses only four bytes of state.
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
        inc solo_workspace+SW_DISCARD_COUNT
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
        beq sad_done
        jsr solo_deck_pop
        jsr solo_hand_set_ordinal
        dec solo_draw_remaining
        bne sad_loop
sad_done:
        lda #0
        sta solo_workspace+SW_PENDING_DRAWS
        jsr solo_advance_turn
        rts

; Return A=front 6-bit ordinal and remove it from the LSB-first packed deck.
solo_deck_pop:
        lda solo_workspace+SW_PACKED_DECK
        and #$3f
        sta solo_drawn_ordinal
        ldx #0
sdp_shift:
        lda solo_workspace+SW_PACKED_DECK,x
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta solo_pack_temp
        lda solo_workspace+SW_PACKED_DECK+1,x
        asl
        asl
        ora solo_pack_temp
        sta solo_workspace+SW_PACKED_DECK,x
        inx
        cpx #39
        bcc sdp_shift
        lda solo_workspace+SW_PACKED_DECK+39
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta solo_workspace+SW_PACKED_DECK+39
        dec solo_workspace+SW_DECK_COUNT
        lda solo_drawn_ordinal
        rts

; A=ordinal, set it in the current player's 7-byte hand mask.
solo_hand_set_ordinal:
        tay
        and #7
        tax
        tya
        lsr
        lsr
        lsr
        tay
        lda solo_workspace+SW_CURRENT_PLAYER
        beq shso_player
        tya
        clc
        adc #7
        tay
shso_player:
        lda solo_workspace+SW_HAND_MASKS,y
        ora solo_bit_table,x
        sta solo_workspace+SW_HAND_MASKS,y
        rts

; scan_suit/scan_rank identify a card in the current player's mask.
solo_hand_clear_card:
        jsr solo_card_mask_address
        lda solo_bit_table,x
        eor #$ff
        and solo_workspace+SW_HAND_MASKS,y
        sta solo_workspace+SW_HAND_MASKS,y
        rts

; Return Y=hand byte offset and X=bit index.
solo_card_mask_address:
        lda solo_workspace+SW_CURRENT_PLAYER
        beq scma_player
        lda #7
scma_player:
        sta solo_hand_offset
        lda solo_scan_suit
        asl
        asl
        asl
        clc
        adc solo_scan_suit
        adc solo_scan_suit
        adc solo_scan_suit
        adc solo_scan_suit
        adc solo_scan_suit
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
        rts

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

.ifdef SOLO_KERNEL_TEST
.export solo_fixture_result, solo_fixture_stage, solo_apply_fixture_stage
.export solo_action_count, solo_action_kind
.export solo_action_rank, solo_action_suit_mask, solo_action_nomination
.export solo_group_mask, solo_valid_mask, solo_scan_rank
.export solo_debug_hand0, solo_debug_hand1, solo_debug_hand4, solo_debug_hand5
solo_debug_hand0 = solo_workspace+SW_HAND_MASKS
solo_debug_hand1 = solo_workspace+SW_HAND_MASKS+1
solo_debug_hand4 = solo_workspace+SW_HAND_MASKS+4
solo_debug_hand5 = solo_workspace+SW_HAND_MASKS+5
; Load the frozen fixture into the real overlay. The fixture is the compact
; representation of the canonical RKSI state checked by tests/solo_kernel.py.
solo_fixture_load:
        ldx #0
sfl_loop:
        lda solo_workspace_fixture,x
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sfl_loop
        rts

; C=0 means the fixture reached the expected fields in the overlay.
solo_fixture_validate:
        lda #1
        sta solo_fixture_stage
        lda solo_workspace+SW_LAYOUT_VERSION
        cmp #1
        bne sfv_bad_early
        lda solo_workspace+SW_PLAYER_COUNT
        cmp #2
        bne sfv_bad_early
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne sfv_bad_early
        lda solo_workspace+SW_DECK_COUNT
        cmp #2
        beq sfv_deck_ok
sfv_bad_early:
        jmp sfv_bad
sfv_deck_ok:
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$47
        bne sfv_bad_early
        jsr solo_get_action_count
        cmp #1
        bne sfv_bad
        lda #0
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_kind
        cmp #SOLO_ACTION_DRAW
        bne sfv_bad
        inc solo_fixture_stage
        jsr solo_catalogue_fixture_load
        jsr solo_get_action_count
        cmp #7
        bne sfv_bad
        inc solo_fixture_stage
        lda #0
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_kind
        bne sfv_bad
        lda solo_action_rank
        cmp #9
        bne sfv_bad
        lda solo_action_suit_mask
        cmp #1
        bne sfv_bad
        inc solo_fixture_stage
        lda #1
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_suit_mask
        cmp #5                    ; hearts + clubs, canonical suit order
        bne sfv_bad
        inc solo_fixture_stage
        lda #2
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_suit_mask
        cmp #13                   ; hearts + clubs + spades
        bne sfv_bad
        inc solo_fixture_stage
        lda #6
        jsr solo_get_action_at
        bcs sfv_bad
        lda solo_action_rank
        cmp #14
        bne sfv_bad
        lda solo_action_nomination
        cmp #3
        bne sfv_bad
        lda #7
        jsr solo_get_action_at
        bcc sfv_bad
        clc
        rts
sfv_bad:
        sec
        rts

solo_catalogue_fixture_load:
        lda #0
        ldx #0
scfl_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne scfl_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #5                    ; five hearts on top
        sta solo_workspace+SW_TOP_DISCARD
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda #$80                  ; nine hearts, ordinal 7
        sta solo_workspace+SW_HAND_MASKS
        lda #$10                  ; ace hearts, ordinal 12
        sta solo_workspace+SW_HAND_MASKS+1
        lda #$02                  ; nine clubs, ordinal 33
        sta solo_workspace+SW_HAND_MASKS+4
        lda #$40                  ; nine spades, ordinal 46
        sta solo_workspace+SW_HAND_MASKS+5
        rts

solo_apply_fixture_validate:
        lda #0
        sta solo_apply_fixture_stage
        jsr solo_catalogue_fixture_load
        ; Index 7 is just beyond the seven-action catalogue. Rejection must
        ; preserve top card, turn and both relevant hand bytes.
        lda #7
        jsr solo_apply_action
        bcc safv_bad
        lda solo_workspace+SW_TOP_DISCARD
        cmp #5
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS
        cmp #$80
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        cmp #$02
        bne safv_bad
        inc solo_apply_fixture_stage

        ; Action 1 is the canonical two-card nine stack: hearts then clubs.
        lda #1
        jsr solo_apply_action
        bcs safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$89                  ; nine clubs is last in canonical order
        bne safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_TURN_NUMBER
        cmp #1
        bne safv_bad
        inc solo_apply_fixture_stage
        lda solo_workspace+SW_HAND_MASKS
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+1
        cmp #$10                  ; ace hearts remains
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        bne safv_bad
        lda solo_workspace+SW_HAND_MASKS+5
        cmp #$40                  ; nine spades remains
        bne safv_bad
        clc
        rts
safv_bad:
        sec
        rts

solo_draw_fixture_validate:
        lda #0
        ldx #0
sdfv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sdfv_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        sta solo_workspace+SW_PENDING_DRAWS
        sta solo_workspace+SW_DECK_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda #$cc                  ; ordinals 12 then 39, LSB-first 6-bit
        sta solo_workspace+SW_PACKED_DECK
        lda #$09
        sta solo_workspace+SW_PACKED_DECK+1
        lda #$01                  ; three spades (ordinal 40)
        sta solo_workspace+SW_HAND_MASKS+5

        lda #0
        jsr solo_apply_action
        bcs sdfv_bad
        lda solo_workspace+SW_DECK_COUNT
        bne sdfv_bad
        lda solo_workspace+SW_PENDING_DRAWS
        bne sdfv_bad
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne sdfv_bad
        lda solo_workspace+SW_TURN_NUMBER
        cmp #1
        bne sdfv_bad
        lda solo_workspace+SW_HAND_MASKS+1
        cmp #$10                  ; ace hearts, ordinal 12
        bne sdfv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        cmp #$80                  ; two spades, ordinal 39
        bne sdfv_bad
        lda solo_workspace+SW_HAND_MASKS+5
        cmp #$01                  ; original three spades remains
        bne sdfv_bad
        clc
        rts
sdfv_bad:
        sec
        rts

; LSB-first 6-bit deck ordinals: ace hearts (12), two spades (39).
; Hands: five hearts; three clubs plus jack spades.
solo_workspace_fixture:
        .byte 1,2,1,$09,5,1             ; layout through pending skips
        .byte 7,0,0,0                   ; turn number
        .byte $2a,0,0,0,0,0,0,0        ; deterministic seed
        .byte 0,$ff,2                   ; finish count/order, deck count
        .byte $cc,$09                   ; two packed 6-bit ordinals
        .res 37,0                       ; remaining packed deck bytes
        .byte 2,$47                     ; discard count and top discard
        .byte $08,0,0,0,0,0,0          ; player 0 hand mask
        .byte 0,0,0,$08,0,0,$01         ; player 1 hand mask
        .res 4,0
solo_workspace_fixture_end:
.assert solo_workspace_fixture_end-solo_workspace_fixture = SOLO_WS_SIZE, error, "solo fixture must be 80 bytes"

solo_fixture_result:
        .byte 0
solo_fixture_stage:
        .byte 0
solo_apply_fixture_stage:
        .byte 0
.endif
