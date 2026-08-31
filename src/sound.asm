; =============================================================================
; VIC-20 SOUND FEEDBACK
; Short non-blocking cues on oscillator 3. The main loop advances the lifetime;
; no delay loop can prevent the software UART from polling the modem.
; =============================================================================

sound_init:
        lda #0
        sta VIC_TONE1
        sta VIC_TONE2
        sta VIC_TONE3
        sta VIC_NOISE
        sta sound_ticks
        rts

; Input: A = oscillator pitch ($80-$ff), X = main-loop ticks
sound_start:
        sta VIC_TONE3
        stx sound_ticks
        lda VIC_AUX
        and #$f0
        ora #8
        sta VIC_AUX
        rts

sound_update:
        lda sound_ticks
        beq su_done
        dec sound_ticks
        bne su_done
sound_stop:
        lda #0
        sta VIC_TONE3
        lda VIC_AUX
        and #$f0
        sta VIC_AUX
su_done:
        rts

sound_move:
        lda #$d0
        ldx #2
        bne sound_start
sound_select:
        lda #$e2
        ldx #3
        bne sound_start
sound_action:
        lda #$f0
        ldx #5
        bne sound_start
sound_error:
        lda #$98
        ldx #10
        bne sound_start
sound_finish:
        lda #$c0
        ldx #1
        jsr sound_start
        ; The game is already terminal, so a short six-jiffy flourish can wait
        ; on the IRQ clock without risking protocol receive time.
        ldx #6
sf_next_jiffy:
        lda JIFFY_LOW
sf_wait_jiffy:
        cmp JIFFY_LOW
        beq sf_wait_jiffy
        dex
        bne sf_next_jiffy
        jmp sound_stop

sound_ticks:
        .byte 0
