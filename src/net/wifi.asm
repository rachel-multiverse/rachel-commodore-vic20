; =============================================================================
; VIC-20 WIFI/SERIAL MODULE
; Uses user port for serial communication with WiFi modem
; =============================================================================

; Serial port settings for user port
BAUD_RATE       = 9600

; Status flags
NET_CONNECTED   = $01
NET_ERROR       = $80

; -----------------------------------------------------------------------------
; Initialize network interface
; -----------------------------------------------------------------------------
net_init:
        ; Configure VIA for serial communication
        ; Port B for data, control lines on Port A

        ; Set data direction - PB0-7 as input initially
        lda #$00
        sta VIA1_DDRB

        ; PA7 as output (TX), PA6 as input (RX)
        lda #$80
        sta VIA1_DDRA

        ; Initial state
        lda #0
        sta net_status
        sta bytes_pending

        rts

; -----------------------------------------------------------------------------
; Connect to server
; Uses AT commands for ESP8266/ESP32 modem
; Returns: C=0 success, C=1 failure
; -----------------------------------------------------------------------------
net_connect:
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
        bcs nc_fail

        ; Check for "CONNECT" or "OK"
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
        .byte "AT+CIPSTART=", $22, "TCP", $22, ",", $22, 0
at_port:
        .byte $22, ",8765", 13, 0

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
        lda #'.'
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
        adc #'0'
        jsr serial_send
sd_skip_h:

        ; Print tens if non-zero or had hundreds
        lda ZP_TEMP2
        ora ZP_TEMP3
        beq sd_skip_t
        lda ZP_TEMP3
        clc
        adc #'0'
        jsr serial_send
sd_skip_t:

        ; Always print units
        lda ZP_TEMP1
        clc
        adc #'0'
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

        ; Got a byte - check for "OK" or "ERROR"
        cmp #'O'
        beq wr_maybe_ok
        cmp #'E'
        beq wr_maybe_err
        jmp wr_loop

wr_maybe_ok:
        jsr serial_recv
        bcs wr_loop
        cmp #'K'
        bne wr_loop
        clc
        rts

wr_maybe_err:
        ; Assume error
        sec
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
        sta ZP_TEMP4
        txa
        pha
        tya
        pha

        ; Start bit (low)
        lda VIA1_PORTA
        and #$7F
        sta VIA1_PORTA
        jsr bit_delay

        ; 8 data bits
        ldx #8
ss_bit:
        lsr ZP_TEMP4
        bcc ss_low
        lda VIA1_PORTA
        ora #$80
        bne ss_out
ss_low:
        lda VIA1_PORTA
        and #$7F
ss_out:
        sta VIA1_PORTA
        jsr bit_delay
        dex
        bne ss_bit

        ; Stop bit (high)
        lda VIA1_PORTA
        ora #$80
        sta VIA1_PORTA
        jsr bit_delay

        pla
        tay
        pla
        tax
        rts

; -----------------------------------------------------------------------------
; Receive byte via serial (bit-banged)
; Returns: A = byte, C=0 success, C=1 no data
; -----------------------------------------------------------------------------
serial_recv:
        txa
        pha
        tya
        pha

        ; Check for start bit (low on PA6)
        lda VIA1_PORTA
        and #$40
        bne sr_none

        ; Wait half bit time to sample in middle
        jsr half_bit_delay

        ; Read 8 data bits
        lda #0
        sta ZP_TEMP4
        ldx #8

sr_bit:
        jsr bit_delay
        lda VIA1_PORTA
        and #$40
        beq sr_zero
        sec
        bcs sr_shift
sr_zero:
        clc
sr_shift:
        ror ZP_TEMP4
        dex
        bne sr_bit

        ; Wait for stop bit
        jsr bit_delay

        lda ZP_TEMP4
        sta ZP_TEMP3
        pla
        tay
        pla
        tax
        lda ZP_TEMP3
        clc
        rts

sr_none:
        pla
        tay
        pla
        tax
        sec
        rts

; Bit timing delays for ~9600 baud at 1MHz
bit_delay:
        ldy #16
bd_loop:
        dey
        bne bd_loop
        rts

half_bit_delay:
        ldy #8
hbd_loop:
        dey
        bne hbd_loop
        rts

; -----------------------------------------------------------------------------
; Send 64-byte buffer
; -----------------------------------------------------------------------------
net_send:
        ; Send CIPSEND command first
        lda #<at_cipsend
        sta ZP_PTR1
        lda #>at_cipsend
        sta ZP_PTR1+1
        jsr send_string

        ; The ESP-AT modem does not accept payload bytes until it has emitted
        ; its '>' prompt. Sending immediately races the command parser.
        jsr wait_send_prompt
        bcs ns_failed

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

ns_failed:
        sec
        rts

at_cipsend:
        .byte "AT+CIPSEND=64", 13, 0

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
        cmp #'R'
        bne nr_find_r
        lda #'R'
        sta rx_buffer
        ldx #1

nr_magic:
        jsr recv_with_timeout
        bcs nr_none
        cmp rubp_magic,x
        bne nr_find_r
        sta rx_buffer,x
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
        .byte "RACH"

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
        cmp #'>'
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
        .byte "AT+CIPCLOSE", 13, 0

; Status
net_status:     .byte 0
bytes_pending:  .byte 0
