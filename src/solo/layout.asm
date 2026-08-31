; =============================================================================
; RACHEL COMPACT SOLO WORKSPACE BINDING
; =============================================================================
;
; Offline lifetime only: the 118-byte constrained_8p_v3 workspace overlays the
; contiguous RUBP TX/RX buffers, which are 128 bytes together. Online code and
; solo code must never be live together.
;
; Eight seats need 56 bytes of hand mask rather than two seats' 14, which puts
; the workspace past the 80 bytes that used to end where the scratch area
; began. Everything at offsets 0-61 keeps its place, so the portable RKSI state
; image and the canonical fixture are unaffected; only the hand-mask block
; grew, and the scratch area moved out to its own storage.
;
; Public entry points in this module follow docs/ASSEMBLY_CONVENTIONS.md.

SOLO_WS_SIZE       = 118
SOLO_SCRATCH_SIZE  = 16

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
SW_HAND_MASKS      = 62          ; eight seats of seven bytes, 62-117
SOLO_MAX_PLAYERS   = 8
SOLO_SEAT_BYTES    = 7

SOLO_ACTION_PLAY   = 0
SOLO_ACTION_DRAW   = 1
SOLO_NO_SUIT       = $ff
SOLO_SAVE_BYTES    = 125
SOLO_INFO_BYTES    = 19

.assert rx_buffer-tx_buffer = 64, error, "RUBP buffers must remain contiguous"
.assert SOLO_WS_SIZE <= 128, error, "solo workspace must fit inside the RUBP buffers"
.assert solo_scratch >= rx_buffer+64, error, "solo scratch must clear the RUBP buffers"
.assert SW_HAND_MASKS+SOLO_MAX_PLAYERS*SOLO_SEAT_BYTES <= SOLO_WS_SIZE, error, "eight hand masks exceed solo workspace"

; GET_INFO-compatible compact-port descriptor at ZP_PTR1. It uses the shared
; RHKI envelope but advertises only what this allocation-free compact port
; actually exposes: deterministic indexed actions, opaque workspace and no
; dynamic allocation. Full action tables and binary apply summaries are zero.
; In:  ZP_PTR1 -> at least SOLO_INFO_BYTES writable bytes.
; Out: descriptor copied; A=SOLO_INFO_BYTES, Y=SOLO_INFO_BYTES.
; Clobbers: A, Y and memory at ZP_PTR1. Preserves: X.
solo_get_info:
        ldy #0
sgi_copy:
        lda solo_info_data,y
        sta (ZP_PTR1),y
        iny
        cpy #SOLO_INFO_BYTES
        bcc sgi_copy
        rts

solo_info_data:
        .byte "RHKI"
        .word 1                  ; kernel ABI
        .word 1                  ; RachelSpec
        .byte 2,8                ; two to eight seats
        .byte 112,7              ; action count / portable action bytes
        .word 0                  ; no resident full action table
        .word 0                  ; no binary apply-summary buffer
        .byte 53                 ; count + maximum hand
        .word $000d              ; order, opaque workspace, no allocation
