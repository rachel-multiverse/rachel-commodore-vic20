; =============================================================================
; VIC-20 WIFI/SERIAL MODULE
; Uses user port for serial communication with WiFi modem
; =============================================================================

; Serial port settings for user port
BAUD_RATE       = 9600

.ifndef RX_BIT_DELAY_COUNT
RX_BIT_DELAY_COUNT = 16
.endif
.ifndef RX_HALF_DELAY_COUNT
RX_HALF_DELAY_COUNT = 7
.endif
.ifndef RX_SLOW_BIT_DELAY_COUNT
RX_SLOW_BIT_DELAY_COUNT = 85
.endif
.ifndef RX_SLOW_HALF_DELAY_COUNT
RX_SLOW_HALF_DELAY_COUNT = 45
.endif

NTSC_TX_BIT_DELAY_COUNT       = 11
NTSC_RX_BIT_DELAY_COUNT       = 14
NTSC_RX_HALF_DELAY_COUNT      = 6
NTSC_TX_SLOW_DELAY_COUNT      = 75
NTSC_RX_SLOW_DELAY_COUNT      = 78
NTSC_RX_SLOW_HALF_DELAY_COUNT = 41

; Status flags
NET_CONNECTED   = $01
NET_ERROR       = $80

; -----------------------------------------------------------------------------
; Initialize network interface
; -----------------------------------------------------------------------------
net_init:
        ; The real C64 user-port WiFi modem maps receive to PB0 (pin C)
        ; and transmit to the physical pin M. On a VIC-20 pin M is CB2,
        ; not PA2, so drive it through the VIA peripheral-control register.
        lda #$00
        sta VIA1_DDRB
        jsr tx_high

        ; Initial state
        lda #0
        sta net_status
        sta bytes_pending

        jsr detect_video_standard
        ldx video_standard
        lda tx_fast_delay_table,x
        sta tx_bit_delay_count
        lda rx_fast_delay_table,x
        sta rx_bit_delay_count
        lda rx_fast_half_table,x
        sta rx_half_delay_count

        rts

; -----------------------------------------------------------------------------
; Connect to server
; Uses AT commands for ESP8266/ESP32 modem
; Returns: C=0 success, C=1 failure
; -----------------------------------------------------------------------------
net_connect:
        ; Configure a conservative physical rate before TCP traffic begins.
        ; 2400 baud gives the 6502 software receiver enough time to return to
        ; start-bit polling between continuous bytes.
        lda #<at_uart_2400
        sta ZP_PTR1
        lda #>at_uart_2400
        sta ZP_PTR1+1
        jsr send_string
        jsr wait_response
        bcs nc_fail
        ; Let the modem finish the trailing CR/LF at the old rate.
        ldx #$10
nc_uart_drain_outer:
        ldy #0
nc_uart_drain_inner:
        dey
        bne nc_uart_drain_inner
        dex
        bne nc_uart_drain_outer
        ldx video_standard
        lda tx_slow_delay_table,x
        sta tx_bit_delay_count
        lda rx_slow_delay_table,x
        sta rx_bit_delay_count
        lda rx_slow_half_table,x
        sta rx_half_delay_count

        ; Send AT command to connect
        ; AT+CIPSTART="TCP","ip",port

        lda #<at_cipstart
        sta ZP_PTR1
        lda #>at_cipstart
        sta ZP_PTR1+1
        jsr send_string

        ; Send IP address
        lda #<ip_addr
        sta ZP_PTR1
        lda #>ip_addr
        sta ZP_PTR1+1
        jsr send_ip

        ; Send port
        lda #<at_port
        sta ZP_PTR1
        lda #>at_port
        sta ZP_PTR1+1
        jsr send_string

        ; Wait for response
        jsr wait_response
        ; CONNECT/OK is advisory: after a baud change a software UART may miss
        ; the text even though TCP is ready. The following CIPSEND prompt and
        ; CRC-valid WELCOME are the authoritative connection checks.
        lda #NET_CONNECTED
        sta net_status
        lda #0
        sta close_match
        clc
        rts

nc_fail:
        lda #NET_ERROR
        sta net_status
        sec
        rts

at_cipstart:
        ; Wire strings must be explicit ASCII: ca65's VIC-20 charmap encodes
        ; quoted uppercase text as high-bit PETSCII.
        .byte $41,$54,$2b,$43,$49,$50,$53,$54,$41,$52,$54,$3d
        .byte $22,$54,$43,$50,$22,$2c,$22,0
at_uart_2400:
        .byte $41,$54,$2b,$55,$41,$52,$54,$5f,$43,$55,$52,$3d
        .byte $32,$34,$30,$30,$2c,$38,$2c,$31,$2c,$30,$2c,$30,13,0
at_port:
        .byte $22, ",6502", 13, 0

; Observe one VIC-I raster wrap. $9004 exposes scanline/2, reaching about 155
; on 312-line PAL and 130 on 261-line NTSC. Result: 0 PAL, 1 NTSC. This runs
; before serial traffic and does not depend on the IRQ-driven jiffy clock.
detect_video_standard:
        lda VIC_RASTER
        sta video_raster_previous
        sta video_raster_maximum
dvs_wait:
        lda VIC_RASTER
        cmp video_raster_maximum
        bcc dvs_check_wrap
        sta video_raster_maximum
dvs_check_wrap:
        cmp video_raster_previous
        bcc dvs_wrapped
        sta video_raster_previous
        bcs dvs_wait
dvs_wrapped:
        lda #0
        ldx video_raster_maximum
        cpx #140
        bcs dvs_store
        lda #1
dvs_store:
        sta video_standard
        rts

; -----------------------------------------------------------------------------
; Send IP address (4 octets separated by dots)
; -----------------------------------------------------------------------------
send_ip:
        ldx #0
si_loop:
        lda ip_addr,x
        jsr send_decimal
        cpx #3
        bcs si_done
        lda #$2e                 ; ASCII '.'
        jsr serial_send
        inx
        bne si_loop
si_done:
        rts

; Send decimal number (0-255)
send_decimal:
        sta ZP_TEMP1
        lda #0
        sta ZP_TEMP2            ; Hundreds
        sta ZP_TEMP3            ; Tens

sd_hundreds:
        lda ZP_TEMP1
        cmp #100
        bcc sd_tens
        sec
        sbc #100
        sta ZP_TEMP1
        inc ZP_TEMP2
        bne sd_hundreds

sd_tens:
        lda ZP_TEMP1
        cmp #10
        bcc sd_units
        sec
        sbc #10
        sta ZP_TEMP1
        inc ZP_TEMP3
        bne sd_tens

sd_units:
        ; Print hundreds if non-zero
        lda ZP_TEMP2
        beq sd_skip_h
        clc
        adc #$30                 ; ASCII '0'
        jsr serial_send
sd_skip_h:

        ; Print tens if non-zero or had hundreds
        lda ZP_TEMP2
        ora ZP_TEMP3
        beq sd_skip_t
        lda ZP_TEMP3
        clc
        adc #$30                 ; ASCII '0'
        jsr serial_send
sd_skip_t:

        ; Always print units
        lda ZP_TEMP1
        clc
        adc #$30                 ; ASCII '0'
        jsr serial_send
        rts

; -----------------------------------------------------------------------------
; Send string via serial
; Input: ZP_PTR1 = string address
; -----------------------------------------------------------------------------
send_string:
        ldy #0
ss_loop:
        lda (ZP_PTR1),y
        beq ss_done
        jsr serial_send
        iny
        bne ss_loop
ss_done:
        rts

; -----------------------------------------------------------------------------
; Wait for modem response
; Returns: C=0 OK, C=1 timeout/error
; -----------------------------------------------------------------------------
wait_response:
        lda #0
        sta timeout_lo
        sta timeout_hi

wr_loop:
        jsr serial_recv
        bcs wr_check_timeout

        ; Scan the response as a stream. K terminates OK and N occurs in the
        ; successful CONNECT status; accepting either independently avoids
        ; requiring adjacent software-UART reads to preserve their prefixes.
        ; Neither marker occurs in ERROR.
        cmp #$4b                 ; ASCII 'K'
        beq wr_success
        cmp #$4e                 ; ASCII 'N'
        bne wr_loop
wr_success:
        clc
        rts

wr_check_timeout:
        inc timeout_lo
        bne wr_loop
        inc timeout_hi
        lda timeout_hi
        cmp #$10                ; Timeout threshold
        bcc wr_loop
        sec
        rts

timeout_lo:     .byte 0
timeout_hi:     .byte 0

; -----------------------------------------------------------------------------
; Send byte via serial (bit-banged)
; Input: A = byte
; -----------------------------------------------------------------------------
serial_send:
        php
        sei
        sta ZP_TEMP4
        txa
        pha
        tya
        pha

        ; Start bit (low on CB2/user-port pin M)
        jsr tx_low
        jsr bit_delay

        ; 8 data bits
        ldx #8
ss_bit:
        lsr ZP_TEMP4
        bcc ss_low
        jsr tx_high
        jmp ss_out_done
ss_low:
        jsr tx_low
ss_out:
ss_out_done:
        jsr bit_delay
        dex
        bne ss_bit

        ; Stop bit (high)
        jsr tx_high
        jsr bit_delay

        pla
        tay
        pla
        tax
        plp
        rts

; -----------------------------------------------------------------------------
; Receive byte via serial (bit-banged)
; Returns: A = byte, C=0 success, C=1 no data
; -----------------------------------------------------------------------------
serial_recv:
        php
        sei
        txa
        pha
        tya
        pha

        ; Check for start bit (low on PB0/user-port pin C)
        lda VIA1_PORTB
        and #$01
        bne sr_none

        ; Wait half bit time to sample in middle
        jsr rx_half_bit_delay

        ; Read 8 data bits
        lda #0
        sta ZP_TEMP4
        ldx #8

sr_bit:
        jsr rx_bit_delay
        lda VIA1_PORTB
        and #$01
        beq sr_zero
        sec
        bcs sr_shift
sr_zero:
        clc
sr_shift:
        ror ZP_TEMP4
        dex
        bne sr_bit

        ; Do not return while a zero most-significant data bit is still on the
        ; wire: the caller would mistake that low level for the next start bit
        ; and decode the following byte one bit out of phase. Wait only until
        ; the stop bit becomes high, then let the caller poll for the next
        ; falling edge. At 2400 baud there is ample stop-bit time remaining.
        ldy #0
sr_wait_stop:
        lda VIA1_PORTB
        and #$01
        bne sr_stop_ready
        dey
        bne sr_wait_stop
        jmp sr_none             ; Framing error: line stayed low.
sr_stop_ready:

        lda ZP_TEMP4
        sta ZP_TEMP3
        pla
        tay
        pla
        tax
        lda ZP_TEMP3
        plp
        clc
        rts

sr_none:
        pla
        tay
        pla
        tax
        plp
        sec
        rts

; PAL VIC-20 timing for approximately 9600 baud. Counting the surrounding
; transmit loop as well as this delay gives about 114-115 CPU cycles between
; output transitions at the PAL machine's ~1.1 MHz CPU clock.
bit_delay:
        ldy tx_bit_delay_count
bd_loop:
        dey
        bne bd_loop
        rts

; Receive has less work between samples than transmit has between transitions,
; so it needs its own calibrated delays. These values put successive samples
; approximately 114-118 cycles apart and the first data sample near 1.5 bit
; cells once the VIA read and sampling-loop instructions are included.
rx_bit_delay:
        ldy rx_bit_delay_count
rbd_loop:
        dey
        bne rbd_loop
        rts

rx_half_bit_delay:
        ldy rx_half_delay_count
rhbd_loop:
        dey
        bne rhbd_loop
        rts

; CB2 manual output modes occupy PCR bits 7..5: 110=low, 111=high.
tx_low:
        lda VIA1_PCR
        and #$1f
        ora #$c0
        sta VIA1_PCR
        rts

tx_high:
        lda VIA1_PCR
        and #$1f
        ora #$e0
        sta VIA1_PCR
        rts

; -----------------------------------------------------------------------------
; Send 64-byte buffer
; -----------------------------------------------------------------------------
net_send:
        ; RUBP v2 protects the complete frame before it crosses the bit-banged
        ; user-port UART.
        jsr rubp_finalize

        ; Send CIPSEND command first
        lda #<at_cipsend
        sta ZP_PTR1
        lda #>at_cipsend
        sta ZP_PTR1+1
        jsr send_string

        ; The ESP-AT modem does not accept payload bytes until it has emitted
        ; its '>' prompt. The bounded scan also provides the required delay;
        ; after the baud reduction the prompt text itself is advisory because
        ; sampling it is less reliable than the CRC-protected payload exchange.
        jsr wait_send_prompt
        lda net_status
        and #NET_ERROR
        beq ns_send_payload
        sec
        rts
ns_send_payload:

        ; Send 64 bytes from tx_buffer
        ldx #0
ns_loop:
        lda tx_buffer,x
        jsr serial_send
        inx
        cpx #64
        bne ns_loop

        clc
        rts

at_cipsend:
        .byte $41,$54,$2b,$43,$49,$50,$53,$45,$4e,$44,$3d,$36,$34,13,0

; -----------------------------------------------------------------------------
; Receive into 64-byte buffer
; Returns: C=0 data received, C=1 no data
; -----------------------------------------------------------------------------
net_recv:
        ; ESP-AT wraps passive TCP data in +IPD metadata. Synchronise on the
        ; RUBP magic so modem status text can never be mistaken for a frame.
nr_find_r:
        jsr serial_recv
        bcs nr_none
        jsr track_closed_status
        bcs nr_none
        cmp #$52                 ; ASCII 'R'
        bne nr_find_r
        lda #$52                 ; ASCII 'R'
        sta rx_buffer
        ldx #1

nr_magic:
        jsr recv_with_timeout
        bcs nr_none
        ; Retain a mismatched byte as well. This makes a failed physical-link
        ; receive diagnosable in a monitor without changing stream recovery.
        sta rx_buffer,x
        cmp rubp_magic,x
        bne nr_find_r
        inx
        cpx #4
        bne nr_magic

nr_loop:
        jsr recv_with_timeout
        bcs nr_none
        sta rx_buffer,x
        inx
        cpx #64
        bne nr_loop

        clc
        rts

; Wait long enough for a byte within an in-progress 64-byte frame.
recv_with_timeout:
        ldy #0
nr_wait_byte:
        jsr serial_recv
        bcc nr_byte_ready
        iny
        bne nr_wait_byte
        sec
        rts
nr_byte_ready:
        clc
        rts

nr_none:
        sec
        rts

; Track the unsolicited ASCII "CLOSED" status emitted by real ESP-AT modems.
; Called only while scanning outside a RUBP frame. Returns C=1 on link loss.
track_closed_status:
        pha
        ldx close_match
        cmp closed_text,x
        beq tcs_match
        cmp #$43                 ; ASCII 'C'
        bne tcs_reset
        lda #1
        bne tcs_store
tcs_reset:
        lda #0
tcs_store:
        sta close_match
        pla
        clc
        rts
tcs_match:
        inx
        cpx #6
        beq tcs_closed
        stx close_match
        pla
        clc
        rts
tcs_closed:
        lda #0
        sta close_match
        lda #NET_ERROR
        sta net_status
        pla
        sec
        rts

closed_text:
        .byte $43,$4c,$4f,$53,$45,$44

rubp_magic:
        .byte $52,$41,$43,$48

; Wait for the ESP-AT CIPSEND prompt.
wait_send_prompt:
        lda #0
        sta send_error_match
        ldy #0
wsp_loop:
        jsr serial_recv
        bcc wsp_byte
        iny
        bne wsp_loop
        sec
        rts
wsp_byte:
        jsr track_send_error
        bcs wsp_error
        cmp #$3e                 ; ASCII '>'
        beq wsp_ready
        iny
        bne wsp_loop
        sec
        rts
wsp_ready:
        clc
        rts
wsp_error:
        lda #NET_ERROR
        sta net_status
        sec
        rts

; Return C=1 after the explicit ASCII "ERROR" rejection from ESP-AT.
; Timeout alone remains advisory because the software receiver can miss `>`.
track_send_error:
        pha
        ldx send_error_match
        cmp send_error_text,x
        beq tse_match
        cmp #$45                 ; ASCII 'E'
        bne tse_reset
        lda #1
        bne tse_store
tse_reset:
        lda #0
tse_store:
        sta send_error_match
        pla
        clc
        rts
tse_match:
        inx
        cpx #5
        beq tse_error
        stx send_error_match
        pla
        clc
        rts
tse_error:
        lda #0
        sta send_error_match
        pla
        sec
        rts

send_error_text:
        .byte $45,$52,$52,$4f,$52

; -----------------------------------------------------------------------------
; Close network connection
; -----------------------------------------------------------------------------
net_close:
        lda #<at_cipclose
        sta ZP_PTR1
        lda #>at_cipclose
        sta ZP_PTR1+1
        jsr send_string
        rts

at_cipclose:
        .byte $41,$54,$2b,$43,$49,$50,$43,$4c,$4f,$53,$45,13,0

; Status
net_status:     .byte 0
bytes_pending:  .byte 0
close_match:    .byte 0
send_error_match: .byte 0
tx_bit_delay_count: .byte 13
rx_bit_delay_count: .byte RX_BIT_DELAY_COUNT
rx_half_delay_count: .byte RX_HALF_DELAY_COUNT
video_standard:     .byte 0
video_raster_previous: .byte 0
video_raster_maximum: .byte 0
tx_fast_delay_table:
        .byte 13,NTSC_TX_BIT_DELAY_COUNT
rx_fast_delay_table:
        .byte RX_BIT_DELAY_COUNT,NTSC_RX_BIT_DELAY_COUNT
rx_fast_half_table:
        .byte RX_HALF_DELAY_COUNT,NTSC_RX_HALF_DELAY_COUNT
tx_slow_delay_table:
        .byte 82,NTSC_TX_SLOW_DELAY_COUNT
rx_slow_delay_table:
        .byte RX_SLOW_BIT_DELAY_COUNT,NTSC_RX_SLOW_DELAY_COUNT
rx_slow_half_table:
        .byte RX_SLOW_HALF_DELAY_COUNT,NTSC_RX_SLOW_HALF_DELAY_COUNT
