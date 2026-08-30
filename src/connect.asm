; =============================================================================
; VIC-20 CONNECTION MODULE
; Handles IP input and connection establishment
; =============================================================================

; -----------------------------------------------------------------------------
; Input server address
; -----------------------------------------------------------------------------
input_ip_address:
        jsr display_clear

        lda #0
        sta ZP_CURSOR_X
        lda #2
        sta ZP_CURSOR_Y

        lda #<ip_prompt
        sta ZP_PTR1
        lda #>ip_prompt
        sta ZP_PTR1+1
        jsr print_string

        ; Position for input
        lda #0
        sta ZP_CURSOR_X
        lda #4
        sta ZP_CURSOR_Y

        ; Get input. input_line uses ip_buffer directly so KERNAL keyboard
        ; scanning cannot invalidate a zero-page pointer between keystrokes.
        jsr input_line

        rts

ip_prompt:
        .byte "ENTER SERVER IP:", 0
ip_buffer:
        .res 21, 0

; -----------------------------------------------------------------------------
; Connect to server
; Returns: C=0 success, C=1 failure
; -----------------------------------------------------------------------------
do_connect:
        jsr display_clear

        lda #0
        sta ZP_CURSOR_X
        lda #2
        sta ZP_CURSOR_Y

        lda #<connect_msg
        sta ZP_PTR1
        lda #>connect_msg
        sta ZP_PTR1+1
        jsr print_string

        ; Parse IP address from buffer
        jsr parse_ip

        ; Attempt connection
        jsr net_connect

        rts

connect_msg:
        .byte "CONNECTING...", 0

; -----------------------------------------------------------------------------
; Parse IP address from buffer into ip_addr
; Simple parser for xxx.xxx.xxx.xxx format
; -----------------------------------------------------------------------------
parse_ip:
        php
        sei

        ldx #0                  ; Octet index
        ldy #0                  ; Buffer index

pi_octet:
        lda #0
        sta ZP_TEMP1            ; Current value

pi_digit:
        lda ip_buffer,y
        beq pi_store            ; End of string
        cmp #'.'
        beq pi_store            ; Octet separator

        ; Convert digit
        sec
        sbc #'0'
        sta ZP_TEMP2

        ; Multiply current by 10 and add
        lda ZP_TEMP1
        asl                     ; x2
        asl                     ; x4
        clc
        adc ZP_TEMP1            ; x5
        asl                     ; x10
        clc
        adc ZP_TEMP2
        sta ZP_TEMP1

        iny
        bne pi_digit

pi_store:
        lda ZP_TEMP1
        sta ip_addr,x
        inx
        cpx #4
        bcs pi_done

        iny                     ; Skip separator
        jmp pi_octet

pi_done:
        plp
        rts

; IP address storage
ip_addr:        .res 4, 0
