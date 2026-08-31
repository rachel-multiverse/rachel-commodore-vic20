solo_save_fixture_a:
        .res SOLO_SAVE_BYTES,0
solo_save_fixture_b:
        .res SOLO_SAVE_BYTES,0
solo_info_fixture:
        .res SOLO_INFO_BYTES,0

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
