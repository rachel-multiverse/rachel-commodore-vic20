; Asm198x compatibility root. This is not a second implementation: it selects
; a flat layout, then walks the exact production include graph from main.asm.
ASM198X_FLAT = 1
; The release build takes these defaults inside wifi.asm. Defining them here
; works around Asm198x's current loss of conditional definitions across an
; include boundary while still compiling the same effective timing constants.
RX_BIT_DELAY_COUNT = 16
RX_HALF_DELAY_COUNT = 7
RX_SLOW_BIT_DELAY_COUNT = 85
RX_SLOW_HALF_DELAY_COUNT = 45
.include "main.asm"
