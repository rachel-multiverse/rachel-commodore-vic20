; =============================================================================
; TEST-ONLY SOLO KERNEL FIXTURES
; =============================================================================
; This entire include tree is absent from production builds.

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

.include "fixtures/core.asm"
.include "fixtures/actions.asm"
.include "fixtures/deck.asm"
.include "fixtures/persistence.asm"
.include "fixtures/ai.asm"
.include "fixtures/complete_game.asm"
.include "fixtures/data.asm"
.endif
