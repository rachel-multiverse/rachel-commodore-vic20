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

; Create the canonical game using the 64-bit seed already stored in
; SW_RANDOM_SEED. Zero is normalised to $00000000DEADBEEF like RachelEngine.
; In: A = seat count, 2 to 8; optional eight-byte seed at SW_RANDOM_SEED (all
;     zero selects the fallback).
; Out: complete deterministic initial state. Clobbers: A, X, Y and deck temps.
solo_new_game:
        sta solo_new_players     ; survives the workspace clear below
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
        lda solo_new_players
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

        ; RachelEngine deals consecutive cards to each seat in turn. The hand
        ; size shrinks as the table fills so eight seats still fit one deck.
        ldx solo_workspace+SW_PLAYER_COUNT
        lda solo_deal_sizes-2,x
        sta solo_deal_size
        lda #0
        sta solo_workspace+SW_CURRENT_PLAYER
sng_seat:
        lda solo_deal_size
        sta solo_deal_remaining
sng_deal:
        jsr solo_deck_pop
        jsr solo_hand_set_ordinal
        dec solo_deal_remaining
        bne sng_deal
        inc solo_workspace+SW_CURRENT_PLAYER
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp solo_workspace+SW_PLAYER_COUNT
        bcc sng_seat
        jsr solo_deck_pop
        jsr solo_ordinal_to_card
        sta solo_workspace+SW_TOP_DISCARD
        lda #1
        sta solo_workspace+SW_DISCARD_COUNT
        lda #0
        sta solo_workspace+SW_CURRENT_PLAYER
        rts

; docs/GAME_RULES.md, indexed by seat count from two.
solo_deal_sizes:
        .byte 7, 7, 7, 7, 6, 6, 5

; Kept at this point in the translation unit so the refactor is byte-identical.
; The include also exercises nested source resolution in both assemblers.
.include "random.asm"

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
        cpx #38
        bcc sdp_shift
        ; 52 six-bit ordinals occupy 39 bytes, so byte 38 is the last one and
        ; shifts in zeros. Running the loop one byte further read and rewrote
        ; SW_PACKED_DECK+39, which is SW_DISCARD_COUNT: every draw crushed the
        ; discard count to zero, so the pile could never be recycled and the
        ; deepest deck slot took its bits.
        lda solo_workspace+SW_PACKED_DECK+38
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta solo_workspace+SW_PACKED_DECK+38
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
        jsr solo_hand_base
        tya
        clc
        adc solo_hand_offset
        tay
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
        jsr solo_hand_base
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
