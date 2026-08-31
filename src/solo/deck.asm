; =============================================================================
; SOLO DECK, HANDS AND DETERMINISTIC RANDOMNESS
; =============================================================================

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
; In: optional eight-byte seed at SW_RANDOM_SEED (all zero selects fallback).
; Out: complete deterministic initial state. Clobbers: A, X, Y and deck temps.
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
; Out: eight-byte xorshift state advanced in place. Clobbers: A, X, scratch.
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
