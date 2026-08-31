; =============================================================================
; SOLO DETERMINISTIC RANDOMNESS
; =============================================================================

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
