; =============================================================================
; SOLO PRIVATE TABLES AND STATIC STORAGE
; =============================================================================
; These names are translation-unit private unless explicitly exported by the
; test build. Their order is stable so source-only refactors remain byte-exact.

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
solo_complete_remaining: .byte 0
solo_complete_pages:    .byte 0
solo_complete_action_count: .byte 0
solo_complete_games_remaining: .byte 0
solo_complete_games_passed: .byte 0
solo_complete_games_bounded: .byte 0
solo_complete_failure:  .byte 0
solo_seat_index:        .byte 0
solo_seat_count:        .byte 0
solo_seat_acc:          .byte 0
solo_deal_size:         .byte 0
solo_new_players:       .byte 0
