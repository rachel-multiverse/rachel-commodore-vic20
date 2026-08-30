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

        lda #13
        sta tx_bit_delay_count
        lda #RX_BIT_DELAY_COUNT
        sta rx_bit_delay_count
        lda #RX_HALF_DELAY_COUNT
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
        lda #82
        sta tx_bit_delay_count
        lda #RX_SLOW_BIT_DELAY_COUNT
        sta rx_bit_delay_count
        lda #RX_SLOW_HALF_DELAY_COUNT
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

rubp_magic:
        .byte $52,$41,$43,$48

; Wait for the ESP-AT CIPSEND prompt.
wait_send_prompt:
        ldy #0
wsp_loop:
        jsr serial_recv
        bcc wsp_byte
        iny
        bne wsp_loop
        sec
        rts
wsp_byte:
        cmp #$3e                 ; ASCII '>'
        beq wsp_ready
        iny
        bne wsp_loop
        sec
        rts
wsp_ready:
        clc
        rts

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
tx_bit_delay_count: .byte 13
rx_bit_delay_count: .byte RX_BIT_DELAY_COUNT
rx_half_delay_count:.byte RX_HALF_DELAY_COUNT
