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
SOLO_SAVE_BYTES    = 87

; Tiny deterministic opponent: choose canonical action zero. The catalogue
; sorts every legal play before DRAW, so this is "first legal play, otherwise
; draw" without duplicating a single legality rule.
solo_ai_take_turn:
        lda #0
        jsr solo_get_action_at
        bcs sait_bad
        lda #0
        jmp solo_apply_action
sait_bad:
        sec
        rts

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

; Compact persistence image at ZP_PTR1: "RKS2", version, payload length,
; 80-byte workspace and XOR checksum. The caller owns the external buffer.
solo_save_state:
        ldy #0
        lda #'R'
        sta (ZP_PTR1),y
        iny
        lda #'K'
        sta (ZP_PTR1),y
        iny
        lda #'S'
        sta (ZP_PTR1),y
        iny
        lda #'2'
        sta (ZP_PTR1),y
        iny
        lda #1
        sta (ZP_PTR1),y
        iny
        lda #SOLO_WS_SIZE
        sta (ZP_PTR1),y
        lda #0
        sta solo_save_checksum
        ldx #0
        ldy #6
sss_copy:
        lda solo_workspace,x
        sta (ZP_PTR1),y
        eor solo_save_checksum
        sta solo_save_checksum
        inx
        iny
        cpx #SOLO_WS_SIZE
        bcc sss_copy
        lda solo_save_checksum
        sta (ZP_PTR1),y
        rts

; Load only after the entire image, checksum and structural bounds validate.
; C=1 rejects without touching the live workspace.
solo_load_state:
        ldy #0
        lda (ZP_PTR1),y
        cmp #'R'
        bne sls_bad_early
        iny
        lda (ZP_PTR1),y
        cmp #'K'
        bne sls_bad_early
        iny
        lda (ZP_PTR1),y
        cmp #'S'
        beq sls_magic_s
sls_bad_early:
        jmp sls_bad
sls_magic_s:
        iny
        lda (ZP_PTR1),y
        cmp #'2'
        bne sls_bad
        iny
        lda (ZP_PTR1),y
        cmp #1
        bne sls_bad
        iny
        lda (ZP_PTR1),y
        cmp #SOLO_WS_SIZE
        bne sls_bad
        lda #0
        sta solo_save_checksum
        ldx #0
        ldy #6
sls_checksum:
        lda (ZP_PTR1),y
        eor solo_save_checksum
        sta solo_save_checksum
        inx
        iny
        cpx #SOLO_WS_SIZE
        bcc sls_checksum
        lda (ZP_PTR1),y
        cmp solo_save_checksum
        bne sls_bad

        ; Structural checks are sufficient for safe compact-kernel indexing.
        ldy #6+SW_LAYOUT_VERSION
        lda (ZP_PTR1),y
        cmp #1
        bne sls_bad
        ldy #6+SW_PLAYER_COUNT
        lda (ZP_PTR1),y
        cmp #2
        bne sls_bad
        ldy #6+SW_CURRENT_PLAYER
        lda (ZP_PTR1),y
        cmp #2
        bcs sls_bad
        ldy #6+SW_DECK_COUNT
        lda (ZP_PTR1),y
        cmp #53
        bcs sls_bad
        sta solo_load_total
        ldy #6+SW_DISCARD_COUNT
        lda (ZP_PTR1),y
        beq sls_bad
        cmp #53
        bcs sls_bad
        clc
        adc solo_load_total
        sec
        sbc #1
        cmp #53
        bcs sls_bad

        ldx #0
        ldy #6
sls_copy:
        lda (ZP_PTR1),y
        sta solo_workspace,x
        inx
        iny
        cpx #SOLO_WS_SIZE
        bcc sls_copy
        clc
        rts
sls_bad:
        sec
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
solo_card_to_ordinal:
        pha
        and #$3f
        sec
        sbc #2
        sta solo_pack_temp
        pla
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta solo_scan_suit
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
        adc solo_pack_temp
        rts

; Create the canonical two-player game using the 64-bit seed already stored in
; SW_RANDOM_SEED. Zero is normalised to $00000000DEADBEEF like RachelEngine.
solo_new_game:
        ldx #7
sng_save_seed:
        lda solo_workspace+SW_RANDOM_SEED,x
        sta solo_scratch,x
        dex
        bpl sng_save_seed
        lda #0
        ldx #0
sng_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sng_clear
        ldx #7
sng_restore_seed:
        lda solo_scratch,x
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl sng_restore_seed
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        jsr solo_seed_normalize

        ; Packed standard deck: ordinals 0...51.
        lda #52
        sta solo_workspace+SW_DECK_COUNT
        lda #0
        sta solo_deck_index
sng_deck:
        lda solo_deck_index
        ldx solo_deck_index
        jsr solo_deck_set_at
        inc solo_deck_index
        lda solo_deck_index
        cmp #52
        bcc sng_deck

        ; Canonical Fisher-Yates, consuming one xorshift64 output per swap.
        lda #51
        sta solo_shuffle_index
sng_shuffle:
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
        bne sng_shuffle

        ; RachelEngine deals seven consecutive cards to each player.
        lda #0
        sta solo_workspace+SW_CURRENT_PLAYER
        lda #7
        sta solo_deal_remaining
sng_deal0:
        jsr solo_deck_pop
        jsr solo_hand_set_ordinal
        dec solo_deal_remaining
        bne sng_deal0
        lda #1
        sta solo_workspace+SW_CURRENT_PLAYER
        lda #7
        sta solo_deal_remaining
sng_deal1:
        jsr solo_deck_pop
        jsr solo_hand_set_ordinal
        dec solo_deal_remaining
        bne sng_deal1
        jsr solo_deck_pop
        jsr solo_ordinal_to_card
        sta solo_workspace+SW_TOP_DISCARD
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda #0
        sta solo_workspace+SW_CURRENT_PLAYER
        rts

solo_seed_normalize:
        lda #0
        ldx #7
ssn_check:
        ora solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl ssn_check
        bne ssn_done
        lda #$ef
        sta solo_workspace+SW_RANDOM_SEED
        lda #$be
        sta solo_workspace+SW_RANDOM_SEED+1
        lda #$ad
        sta solo_workspace+SW_RANDOM_SEED+2
        lda #$de
        sta solo_workspace+SW_RANDOM_SEED+3
ssn_done:
        rts

; xorshift64: x ^= x<<13; x ^= x>>7; x ^= x<<17. State is LE.
solo_rng_next:
        lda #13
        jsr solo_rng_shift_left
        lda #7
        jsr solo_rng_shift_right
        lda #17
        jsr solo_rng_shift_left
        rts

; A=bit count. Copy state to scratch, shift, then XOR it into state.
solo_rng_shift_left:
        tay
        jsr solo_rng_copy_scratch
srsl_bits:
        clc
        lda solo_scratch
        rol
        sta solo_scratch
        lda solo_scratch+1
        rol
        sta solo_scratch+1
        lda solo_scratch+2
        rol
        sta solo_scratch+2
        lda solo_scratch+3
        rol
        sta solo_scratch+3
        lda solo_scratch+4
        rol
        sta solo_scratch+4
        lda solo_scratch+5
        rol
        sta solo_scratch+5
        lda solo_scratch+6
        rol
        sta solo_scratch+6
        lda solo_scratch+7
        rol
        sta solo_scratch+7
        dey
        bne srsl_bits
        jmp solo_rng_xor_scratch

solo_rng_shift_right:
        tay
        jsr solo_rng_copy_scratch
srsr_bits:
        clc
        ldx #7
srsr_bytes:
        lda solo_scratch,x
        ror
        sta solo_scratch,x
        dex
        bpl srsr_bytes
        dey
        bne srsr_bits
        jmp solo_rng_xor_scratch

solo_rng_copy_scratch:
        ldx #7
srcs_loop:
        lda solo_workspace+SW_RANDOM_SEED,x
        sta solo_scratch,x
        dex
        bpl srcs_loop
        rts

solo_rng_xor_scratch:
        ldx #7
srxs_loop:
        lda solo_workspace+SW_RANDOM_SEED,x
        eor solo_scratch,x
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl srxs_loop
        rts

; A=divisor (2...52), return A=64-bit state modulo divisor.
solo_rng_mod:
        sta solo_mod_divisor
        lda #0
        sta solo_mod_remainder
        ldx #7
srm_byte:
        lda solo_workspace+SW_RANDOM_SEED,x
        sta solo_mod_source
        ldy #8
srm_bit:
        asl solo_mod_source
        rol solo_mod_remainder
        lda solo_mod_remainder
        cmp solo_mod_divisor
        bcc srm_next
        sec
        sbc solo_mod_divisor
        sta solo_mod_remainder
srm_next:
        dey
        bne srm_bit
        dex
        bpl srm_byte
        lda solo_mod_remainder
        rts

; X=index, return A=6-bit ordinal.
solo_deck_get_at:
        jsr solo_deck_bit_address
        lda #0
        sta solo_pack_value
        lda #1
        sta solo_value_mask
        ldx #6
sdga_bit:
        lda solo_workspace+SW_PACKED_DECK,y
        and solo_deck_mask
        beq sdga_next
        lda solo_pack_value
        ora solo_value_mask
        sta solo_pack_value
sdga_next:
        asl solo_value_mask
        asl solo_deck_mask
        bne sdga_same_byte
        lda #1
        sta solo_deck_mask
        iny
sdga_same_byte:
        dex
        bne sdga_bit
        lda solo_pack_value
        rts

; X=index, A=6-bit ordinal.
solo_deck_set_at:
        sta solo_pack_value
        jsr solo_deck_bit_address
        ldx #6
sdsa_bit:
        lda solo_deck_mask
        eor #$ff
        and solo_workspace+SW_PACKED_DECK,y
        sta solo_pack_temp
        lsr solo_pack_value
        bcc sdsa_store
        lda solo_pack_temp
        ora solo_deck_mask
        sta solo_pack_temp
sdsa_store:
        lda solo_pack_temp
        sta solo_workspace+SW_PACKED_DECK,y
        asl solo_deck_mask
        bne sdsa_same_byte
        lda #1
        sta solo_deck_mask
        iny
sdsa_same_byte:
        dex
        bne sdsa_bit
        rts

; X=index -> Y=packed byte, deck_mask=first bit.
solo_deck_bit_address:
        txa
        asl
        sta solo_bit_position
        asl
        clc
        adc solo_bit_position     ; index * 6, 16-bit
        sta solo_bit_position
        lda #0
        adc #0
        sta solo_bit_position+1
        lda solo_bit_position
        and #7
        tax
        lda solo_bit_table,x
        sta solo_deck_mask
        lda solo_bit_position
        lsr
        lsr
        lsr
        sta solo_pack_byte
        lda solo_bit_position+1
        asl
        asl
        asl
        asl
        asl
        ora solo_pack_byte
        tay
        rts

; A=ordinal -> A=RUBP card encoding.
solo_ordinal_to_card:
        ldx #0
sotc_suit:
        cmp #13
        bcc sotc_rank
        sec
        sbc #13
        inx
        bne sotc_suit
sotc_rank:
        clc
        adc #2
        sta solo_pack_temp
        txa
        asl
        asl
        asl
        asl
        asl
        asl
        ora solo_pack_temp
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

.ifdef SOLO_KERNEL_TEST
.export solo_fixture_result, solo_fixture_stage, solo_apply_fixture_stage
.export solo_new_game_fixture_stage
.export solo_rng_fixture_stage
.export solo_action_count, solo_action_kind
.export solo_action_rank, solo_action_suit_mask, solo_action_nomination
.export solo_group_mask, solo_valid_mask, solo_scan_rank
.export solo_debug_hand0, solo_debug_hand1, solo_debug_hand4, solo_debug_hand5
.export solo_debug_top, solo_debug_deck0, solo_debug_seed
solo_debug_hand0 = solo_workspace+SW_HAND_MASKS
solo_debug_hand1 = solo_workspace+SW_HAND_MASKS+1
solo_debug_hand4 = solo_workspace+SW_HAND_MASKS+4
solo_debug_hand5 = solo_workspace+SW_HAND_MASKS+5
solo_debug_top = solo_workspace+SW_TOP_DISCARD
solo_debug_deck0 = solo_workspace+SW_PACKED_DECK
solo_debug_seed = solo_workspace+SW_RANDOM_SEED
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
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #3
        bne safv_bad
        ldx #0
        jsr solo_deck_get_at
        cmp #3                    ; former five hearts top
        bne safv_bad
        ldx #1
        jsr solo_deck_get_at
        cmp #7                    ; intermediate nine hearts
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

solo_new_game_fixture_validate:
        lda #0
        sta solo_new_game_fixture_stage
        ldx #0
sngfv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne sngfv_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        jsr solo_new_game
        lda solo_workspace+SW_DECK_COUNT
        cmp #37
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #1
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$cc                  ; queen spades
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_PACKED_DECK
        and #$3f
        cmp #15                   ; four diamonds is first remaining card
        bne sngfv_bad
        inc solo_new_game_fixture_stage
        lda solo_workspace+SW_HAND_MASKS+2
        cmp #$30
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+3
        cmp #$08
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+4
        cmp #$04
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+5
        cmp #$52
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+7
        cmp #$20
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+8
        cmp #$7c
        bne sngfv_bad
        lda solo_workspace+SW_HAND_MASKS+10
        cmp #$20
        bne sngfv_bad
        ldx #7
sngfv_seed:
        lda solo_workspace+SW_RANDOM_SEED,x
        cmp solo_seed42_final,x
        bne sngfv_bad
        dex
        bpl sngfv_seed
        clc
        rts
sngfv_bad:
        sec
        rts

solo_seed42_final:
        .byte $e3,$e3,$25,$26,$72,$85,$8c,$06

solo_rng_fixture_validate:
        lda #0
        sta solo_rng_fixture_stage
        ldx #7
srfv_clear:
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl srfv_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        inc solo_rng_fixture_stage
        jsr solo_rng_next
        inc solo_rng_fixture_stage
        ldx #7
srfv_compare:
        lda solo_workspace+SW_RANDOM_SEED,x
        cmp solo_seed42_first,x
        bne srfv_bad
        dex
        bpl srfv_compare
        clc
        rts
srfv_bad:
        sec
        rts

solo_seed42_first:
        .byte $aa,$4a,$51,$95,$0a,0,0,0

solo_recycle_fixture_validate:
        lda #0
        ldx #0
srv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne srv_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #4
        sta solo_workspace+SW_DISCARD_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        lda #0
        ldx #0
        jsr solo_deck_set_at
        lda #1
        ldx #1
        jsr solo_deck_set_at
        lda #2
        ldx #2
        jsr solo_deck_set_at
        jsr solo_recycle_discards
        lda solo_workspace+SW_DECK_COUNT
        cmp #3
        bne srv_bad
        lda solo_workspace+SW_DISCARD_COUNT
        cmp #1
        bne srv_bad
        ldx #0
        jsr solo_deck_get_at
        cmp #0
        bne srv_bad
        ldx #1
        jsr solo_deck_get_at
        cmp #2
        bne srv_bad
        ldx #2
        jsr solo_deck_get_at
        cmp #1
        bne srv_bad
        ldx #7
srv_seed:
        lda solo_workspace+SW_RANDOM_SEED,x
        cmp solo_seed42_recycled,x
        bne srv_bad
        dex
        bpl srv_seed
        clc
        rts
srv_bad:
        sec
        rts

solo_seed42_recycled:
        .byte $bf,$02,$02,$f8,$fd,$aa,$0a,$a0

solo_persistence_fixture_validate:
        lda #<solo_save_fixture_a
        sta ZP_PTR1
        lda #>solo_save_fixture_a
        sta ZP_PTR1+1
        jsr solo_save_state
        lda #0
        ldx #0
spfv_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne spfv_clear
        jsr solo_load_state
        bcs spfv_bad
        lda #<solo_save_fixture_b
        sta ZP_PTR1
        lda #>solo_save_fixture_b
        sta ZP_PTR1+1
        jsr solo_save_state
        ldx #0
spfv_compare:
        lda solo_save_fixture_a,x
        cmp solo_save_fixture_b,x
        bne spfv_bad
        inx
        cpx #SOLO_SAVE_BYTES
        bcc spfv_compare

        ; Corruption is rejected before any workspace byte changes.
        lda solo_save_fixture_a+SOLO_SAVE_BYTES-1
        eor #1
        sta solo_save_fixture_a+SOLO_SAVE_BYTES-1
        lda #1
        sta solo_workspace+SW_CURRENT_PLAYER
        lda #<solo_save_fixture_a
        sta ZP_PTR1
        lda #>solo_save_fixture_a
        sta ZP_PTR1+1
        jsr solo_load_state
        bcc spfv_bad
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne spfv_bad
        clc
        rts
spfv_bad:
        sec
        rts

solo_ai_fixture_validate:
        ; A playable catalogue chooses its first play, not DRAW.
        jsr solo_catalogue_fixture_load
        jsr solo_ai_take_turn
        bcs saifv_bad_early
        lda solo_workspace+SW_TOP_DISCARD
        cmp #9                    ; first action is nine hearts
        beq saifv_play_ok
saifv_bad_early:
        jmp saifv_bad
saifv_play_ok:

        ; With no legal play, the same policy takes the sole DRAW action.
        lda #0
        ldx #0
saifv_draw_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne saifv_draw_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #1
        sta solo_workspace+SW_DECK_COUNT
        sta solo_workspace+SW_DISCARD_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #$01                  ; three spades cannot match five hearts
        sta solo_workspace+SW_HAND_MASKS+5
        lda #12                   ; ace hearts is the only deck card
        sta solo_workspace+SW_PACKED_DECK
        jsr solo_ai_take_turn
        bcs saifv_bad
        lda solo_workspace+SW_DECK_COUNT
        bne saifv_bad
        lda solo_workspace+SW_HAND_MASKS+1
        cmp #$10
        bne saifv_bad

        ; Ace expansion is deterministic: action zero nominates hearts.
        lda #0
        ldx #0
saifv_ace_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne saifv_ace_clear
        lda #1
        sta solo_workspace+SW_LAYOUT_VERSION
        sta solo_workspace+SW_DISCARD_COUNT
        lda #2
        sta solo_workspace+SW_PLAYER_COUNT
        lda #5
        sta solo_workspace+SW_TOP_DISCARD
        lda #$10                  ; ace hearts
        sta solo_workspace+SW_HAND_MASKS+1
        lda #$01                  ; two clubs keeps the player in the game
        sta solo_workspace+SW_HAND_MASKS+3
        jsr solo_ai_take_turn
        bcs saifv_bad
        lda solo_workspace+SW_PACKED_FLAGS
        lsr
        and #7
        cmp #1                    ; nominated hearts encoding
        bne saifv_bad

        ; Repeated turns are bounded calls and advance the state every time.
        lda #0
        ldx #0
saifv_soak_clear:
        sta solo_workspace,x
        inx
        cpx #SOLO_WS_SIZE
        bne saifv_soak_clear
        lda #42
        sta solo_workspace+SW_RANDOM_SEED
        jsr solo_new_game
        lda #8
        sta solo_ai_soak_remaining
saifv_soak:
        jsr solo_ai_take_turn
        bcs saifv_bad
        dec solo_ai_soak_remaining
        bne saifv_soak
        lda solo_workspace+SW_TURN_NUMBER
        cmp #8
        bne saifv_bad
        clc
        rts
saifv_bad:
        sec
        rts

solo_save_fixture_a:
        .res SOLO_SAVE_BYTES,0
solo_save_fixture_b:
        .res SOLO_SAVE_BYTES,0

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
solo_new_game_fixture_stage:
        .byte 0
solo_rng_fixture_stage:
        .byte 0
.endif
