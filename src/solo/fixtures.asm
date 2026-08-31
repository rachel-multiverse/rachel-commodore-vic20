; =============================================================================
; TEST-ONLY SOLO KERNEL FIXTURES
; =============================================================================
; This entire module is absent from production builds.

.ifdef SOLO_KERNEL_TEST
.export solo_fixture_result, solo_fixture_stage, solo_apply_fixture_stage
.export solo_new_game_fixture_stage
.export solo_rng_fixture_stage
.export solo_complete_remaining, solo_complete_pages
.export solo_complete_games_passed, solo_complete_games_bounded
.export solo_complete_failure
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

solo_info_fixture_validate:
        lda #<solo_info_fixture
        sta ZP_PTR1
        lda #>solo_info_fixture
        sta ZP_PTR1+1
        jsr solo_get_info
        ldx #0
sifv_compare:
        lda solo_info_fixture,x
        cmp solo_info_data,x
        bne sifv_bad
        inx
        cpx #SOLO_INFO_BYTES
        bcc sifv_compare
        clc
        rts
sifv_bad:
        sec
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

; Exercise a complete server-free match through the same enumerated action
; path used by both front-end participants. Seed 42 must reach a winner within
; the byte-sized safety bound.
solo_complete_game_fixture_validate:
        lda #16
        sta solo_complete_games_remaining
        lda #0
        sta solo_complete_games_passed
        sta solo_complete_games_bounded
        sta solo_complete_failure
scgfv_new_game:
        lda #0
        ldx #7
scgfv_seed_clear:
        sta solo_workspace+SW_RANDOM_SEED,x
        dex
        bpl scgfv_seed_clear
        lda solo_complete_games_passed
        clc
        adc #1
        sta solo_workspace+SW_RANDOM_SEED
        jsr solo_new_game
        lda #0
        sta solo_complete_remaining
        lda #4
        sta solo_complete_pages
scgfv_turn:
        lda solo_workspace+SW_FINISH_COUNT
        bne scgfv_done
        jsr solo_get_action_count
        bne scgfv_have_action
        lda #1
        bne scgfv_fail
scgfv_have_action:
        sta solo_complete_action_count
        jsr solo_rng_next
        lda solo_complete_action_count
        jsr solo_rng_mod
        jsr solo_apply_action
        bcc scgfv_applied
        lda #2
        bne scgfv_fail
scgfv_applied:
        dec solo_complete_remaining
        bne scgfv_turn
        dec solo_complete_pages
        bne scgfv_turn
        inc solo_complete_games_bounded
        jmp scgfv_game_complete
scgfv_fail:
        sta solo_complete_failure
        sec
        rts
scgfv_done:
        lda solo_workspace+SW_FINISH_ORDER
        cmp #2
        bcc scgfv_winner_ok
        lda #4
        bne scgfv_fail
scgfv_winner_ok:
scgfv_game_complete:
        inc solo_complete_games_passed
        dec solo_complete_games_remaining
        bne scgfv_new_game
        clc
        rts

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
        .byte 0
.endif
