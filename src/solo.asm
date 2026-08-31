; =============================================================================
; RACHEL COMPACT TWO-PLAYER SOLO GAME
; =============================================================================
;
; This is the assembly root for the offline game. The included modules share
; one ca65 translation unit: forward references and private labels therefore
; behave exactly as they did before the source was split. Keep the order stable
; so listings and debug source attribution remain easy to compare.

.include "solo/layout.asm"
.include "solo/ui.asm"
.include "solo/api.asm"
.include "solo/actions.asm"
.include "solo/deck.asm"
.include "solo/rules.asm"
.include "solo/state.asm"
.include "solo/fixtures.asm"
