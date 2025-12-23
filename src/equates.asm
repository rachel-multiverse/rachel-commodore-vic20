; =============================================================================
; VIC-20 EQUATES
; Assumes 8KB+ memory expansion
; =============================================================================

; -----------------------------------------------------------------------------
; Zero Page Usage ($70-$8F)
; -----------------------------------------------------------------------------
ZP_PTR1         = $70           ; General pointer (2 bytes)
ZP_PTR2         = $72           ; General pointer (2 bytes)
ZP_TEMP1        = $74           ; Temp storage
ZP_TEMP2        = $75           ; Temp storage
ZP_TEMP3        = $76           ; Temp storage
ZP_TEMP4        = $77           ; Temp storage
ZP_CURSOR_X     = $78           ; Cursor X position
ZP_CURSOR_Y     = $79           ; Cursor Y position
ZP_SCREEN_LO    = $7A           ; Screen address low
ZP_SCREEN_HI    = $7B           ; Screen address high

; -----------------------------------------------------------------------------
; VIC-20 Hardware Addresses
; -----------------------------------------------------------------------------
VIC_BASE        = $9000         ; VIC chip base

; VIC registers
VIC_HORZ        = $9000         ; Horizontal origin
VIC_VERT        = $9001         ; Vertical origin
VIC_COLS        = $9002         ; Columns + video address
VIC_ROWS        = $9003         ; Rows + character size
VIC_RASTER      = $9004         ; Raster line
VIC_COLADDR     = $9005         ; Color/char memory location
VIC_AUX         = $900E         ; Auxiliary color
VIC_BKGND       = $900F         ; Background/border color

; Screen memory (with 8KB+ expansion)
SCREEN_BASE     = $1000         ; Screen RAM
COLOR_BASE      = $9400         ; Color RAM
SCREEN_WIDTH    = 22            ; Characters per row
SCREEN_HEIGHT   = 23            ; Rows

; VIA ports (User Port)
VIA1_BASE       = $9110         ; VIA 1 base (user port)
VIA1_PORTB      = $9110         ; Port B data
VIA1_PORTA      = $9111         ; Port A data
VIA1_DDRB       = $9112         ; Data direction B
VIA1_DDRA       = $9113         ; Data direction A
VIA1_T1CL       = $9114         ; Timer 1 counter low
VIA1_T1CH       = $9115         ; Timer 1 counter high
VIA1_ACR        = $911B         ; Auxiliary control
VIA1_PCR        = $911C         ; Peripheral control
VIA1_IFR        = $911D         ; Interrupt flag
VIA1_IER        = $911E         ; Interrupt enable

; KERNAL routines
CHROUT          = $FFD2         ; Output character
CHRIN           = $FFCF         ; Input character
GETIN           = $FFE4         ; Get character (non-blocking)
PLOT            = $FFF0         ; Set/get cursor position
CLRSCR          = $E55F         ; Clear screen

; Key codes
KEY_LEFT        = 157           ; Cursor left
KEY_RIGHT       = 29            ; Cursor right
KEY_UP          = 145           ; Cursor up
KEY_DOWN        = 17            ; Cursor down
KEY_RETURN      = 13
KEY_SPACE       = 32
KEY_ESC         = 3             ; RUN/STOP (Ctrl-C)
KEY_DELETE      = 20

; -----------------------------------------------------------------------------
; RUBP Protocol Constants
; -----------------------------------------------------------------------------
MAGIC_0         = 'R'
MAGIC_1         = 'A'
MAGIC_2         = 'C'
MAGIC_3         = 'H'
PROTOCOL_VER    = 1

; Header offsets
HDR_MAGIC       = 0             ; 4 bytes
HDR_VERSION     = 4             ; 1 byte
HDR_TYPE        = 5             ; 1 byte
HDR_FLAGS       = 6             ; 1 byte
HDR_RESERVED    = 7             ; 1 byte
HDR_SEQ         = 8             ; 2 bytes
HDR_PLAYER_ID   = 10            ; 2 bytes
HDR_GAME_ID     = 12            ; 2 bytes
HDR_CHECKSUM    = 14            ; 2 bytes
PAYLOAD_START   = 16
PAYLOAD_SIZE    = 48

; Message types
MSG_HELLO       = $01
MSG_LEAVE       = $02

; Platform ID (VIC-20 = 0x000C)
PLATFORM_ID_HI  = $00
PLATFORM_ID_LO  = $0C
MSG_READY       = $03
MSG_GAME_START  = $10
MSG_GAME_STATE  = $11
MSG_GAME_END    = $12
MSG_PLAY_CARDS  = $20
MSG_DRAW_CARD   = $21
MSG_NOMINATE    = $22

; -----------------------------------------------------------------------------
; Connection States
; -----------------------------------------------------------------------------
CONN_DISCONNECTED = 0
CONN_HANDSHAKE    = 1
CONN_WAITING      = 2
CONN_PLAYING      = 3

; -----------------------------------------------------------------------------
; Card Constants
; -----------------------------------------------------------------------------
SUIT_HEARTS     = 0
SUIT_DIAMONDS   = 1
SUIT_CLUBS      = 2
SUIT_SPADES     = 3

RANK_ACE        = 1
RANK_JACK       = 11
RANK_QUEEN      = 12
RANK_KING       = 13
