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

.ifdef SOLO_KERNEL_TEST
.export solo_fixture_result
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
        lda solo_workspace+SW_LAYOUT_VERSION
        cmp #1
        bne sfv_bad
        lda solo_workspace+SW_PLAYER_COUNT
        cmp #2
        bne sfv_bad
        lda solo_workspace+SW_CURRENT_PLAYER
        cmp #1
        bne sfv_bad
        lda solo_workspace+SW_DECK_COUNT
        cmp #2
        bne sfv_bad
        lda solo_workspace+SW_TOP_DISCARD
        cmp #$47
        bne sfv_bad
        clc
        rts
sfv_bad:
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
.endif
