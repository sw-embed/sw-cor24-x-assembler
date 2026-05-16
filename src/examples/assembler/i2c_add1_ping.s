; I2C Add1 Ping: bit-bang i2c demo against the emulator's `add1` test slave.
;
; Writes byte 0x42 to the slave at I2C addr 0x50, reads it back (add1 returns
; byte+1 on read = 0x43), prints the result to UART as two hex chars + '\n'.
; Halts.
;
; Pair with `cor24-emu --i2c-device add1@0x50`:
;     cor24-asm src/examples/assembler/i2c_add1_ping.s -o /tmp/add1.lgo
;     cor24-emu --lgo /tmp/add1.lgo --i2c-device add1@0x50
;     # expect UART output: "43\n"
;
; Without an i2c device attached, SDA reads return 1 (open-drain default), so
; the program completes but prints "FF\n" — expected; this example targets
; the device-attached path.
;
; MMIO:
;     0xFF0020 = SCL  (bit 0 significant; open-drain: 1 = release, 0 = pull)
;     0xFF0021 = SDA  (same)
;     0xFF0100 = UART data; 0xFF0101 = UART status (bit 7 = TX busy)
;
; Calling convention (per existing examples nested_calls.s, uart_hello.s):
;   r0 = first arg / return value; r1 = return address (caller-set via
;   `la r1, label`); r2 = scratch. Callees with deeper calls push r1.
;   Functions with locals push r1, push fp, mov fp,sp; access via fp+offset.
;
; Clock delays from libi2c.c are omitted: the emulator's i2c bus state
; machine reacts atomically to each MMIO write, so the RC-timing delays
; aren't needed for emulator targets. Real hardware would need them.
;
; Register pressure: COR24 has 3 GPRs (r0/r1/r2). fp/sp are not valid as
; ALU targets, and sp can't be a load/store base — only fp can. So
; subroutine locals live above fp, accessed as offset(fp).

        ; --- main ---
        la      r0, 0FEEC00h    ; top of EBR
        mov     sp, r0

        la      r1, .ret_start1
        la      r2, i2cstart
        jal     r1, (r2)
.ret_start1:

        ; i2cwrite(0xA0)  — address 0x50 << 1, write bit (R/W = 0)
        lcu     r0, 0A0h
        la      r1, .ret_write1
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_write1:

        ; i2cwrite(0x42)
        lcu     r0, 42h
        la      r1, .ret_write2
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_write2:

        la      r1, .ret_stop1
        la      r2, i2cstop
        jal     r1, (r2)
.ret_stop1:

        ; restart for read
        la      r1, .ret_start2
        la      r2, i2cstart
        jal     r1, (r2)
.ret_start2:

        ; i2cwrite(0xA1)  — address 0x50 << 1, read bit (R/W = 1)
        lcu     r0, 0A1h
        la      r1, .ret_write3
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_write3:

        ; r0 = i2cread()  — slave returns byte+1 = 0x43
        la      r1, .ret_read
        la      r2, i2cread
        jal     r1, (r2)
.ret_read:
        push    r0              ; save read byte across i2cstop

        la      r1, .ret_stop2
        la      r2, i2cstop
        jal     r1, (r2)
.ret_stop2:

        ; upper nibble
        pop     r0              ; full byte
        push    r0              ; (keep for second nibble)
        lc      r1, 4
        srl     r0, r1
        la      r1, .ret_hi
        la      r2, print_hex_nibble
        jal     r1, (r2)
.ret_hi:

        ; lower nibble
        pop     r0
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .ret_lo
        la      r2, print_hex_nibble
        jal     r1, (r2)
.ret_lo:

        lc      r0, 10          ; '\n'
        la      r1, .ret_nl
        la      r2, putc
        jal     r1, (r2)
.ret_nl:

halt:
        bra     halt

; ============================================================================
; UART
; ============================================================================

; putc(r0): poll TX-busy clear, then write low byte of r0 to UART data.
putc:
        push    r1
        push    r0
        la      r1, -65280      ; UART base = 0xFF0100
.putc_wait:
        lb      r2, 1(r1)       ; status (bit 7 = TX busy, sign-extends to negative)
        cls     r2, z
        brt     .putc_wait
        pop     r0
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

; print_hex_nibble(r0): emit r0 (low 4 bits) as '0'-'9' or 'A'-'F'.
print_hex_nibble:
        push    r1
        lcu     r2, 10
        clu     r0, r2          ; r0 < 10?
        brt     .phn_digit
        add     r0, 55          ; 'A' - 10
        bra     .phn_emit
.phn_digit:
        add     r0, 48          ; '0'
.phn_emit:
        la      r2, putc
        jal     r1, (r2)
        pop     r1
        jmp     (r1)

; ============================================================================
; I2C bit-bang primitives (cf. sw-cor24-emulator/examples/i2c/tmp101/libi2c.c)
; ============================================================================

; i2cstart: SDA hi, SCL hi, SDA lo, SCL lo  — the START condition.
i2cstart:
        push    r1
        la      r1, -65504      ; I2C base = 0xFF0020 (SCL @ +0, SDA @ +1)
        lcu     r0, 1
        sb      r0, 1(r1)       ; SDA = 1
        sb      r0, 0(r1)       ; SCL = 1
        lc      r0, 0
        sb      r0, 1(r1)       ; SDA = 0  (falls while SCL high → START)
        sb      r0, 0(r1)       ; SCL = 0
        pop     r1
        jmp     (r1)

; i2cstop: SDA lo, SCL hi, SDA hi  — the STOP condition.
i2cstop:
        push    r1
        la      r1, -65504
        lc      r0, 0
        sb      r0, 1(r1)       ; SDA = 0
        lcu     r0, 1
        sb      r0, 0(r1)       ; SCL = 1
        sb      r0, 1(r1)       ; SDA = 1  (rises while SCL high → STOP)
        lc      r0, 0
        sb      r0, 0(r1)       ; SCL = 0  (return to idle)
        pop     r1
        jmp     (r1)

; i2cwrite(r0): send low 8 bits of r0 MSB-first; return slave ACK bit in r0.
;   Frame: pushed r1, pushed fp, pushed r0 (= byte). fp = sp after prologue.
;   Locals:  byte at 0(fp).  Mask in r2 walks 0x80 → ... → 0x01.
i2cwrite:
        push    r1
        push    fp
        push    r0              ; byte at 0(fp)
        mov     fp, sp
        lcu     r2, 80h         ; mask
.iw_loop:
        lbu     r0, 0(fp)       ; byte
        and     r0, r2
        ceq     r0, z
        brt     .iw_zero
        lc      r0, 1
        bra     .iw_set
.iw_zero:
        lc      r0, 0
.iw_set:
        la      r1, -65504
        sb      r0, 1(r1)       ; SDA = bit
        lcu     r0, 1
        sb      r0, 0(r1)       ; SCL = 1 (slave samples)
        lc      r0, 0
        sb      r0, 0(r1)       ; SCL = 0
        lc      r1, 1
        srl     r2, r1
        ceq     r2, z
        brf     .iw_loop
        ; --- slave ACK ---
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)       ; SDA = 1 (release for slave)
        sb      r0, 0(r1)       ; SCL = 1
        lbu     r0, 1(r1)       ; r0 = SDA
        lcu     r2, 1
        and     r0, r2          ; mask to bit 0
        push    r0              ; preserve ack across SCL-lo
        lc      r2, 0
        la      r1, -65504
        sb      r2, 0(r1)       ; SCL = 0
        pop     r0              ; r0 = ack (return value)
        ; --- teardown ---
        add     sp, 3           ; discard byte local
        pop     fp
        pop     r1
        jmp     (r1)

; i2cread(): receive 8 bits MSB-first, then master ACK. Returns byte in r0.
;   Frame: pushed r1, pushed fp, pushed (acc = 0). fp = sp.
;   Locals: acc at 0(fp). Counter in r2 (8 → 0).
i2cread:
        push    r1
        push    fp
        lc      r0, 0
        push    r0              ; acc = 0 at 0(fp)
        mov     fp, sp
        lcu     r2, 8           ; counter
.ir_loop:
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)       ; SDA = 1 (release for slave)
        sb      r0, 0(r1)       ; SCL = 1
        lbu     r0, 1(r1)       ; r0 = bit
        ; acc = (acc << 1) | bit
        push    r0              ; bit on stack temporarily
        lw      r0, 0(fp)       ; current acc (fp is unchanged; valid through push)
        add     r0, r0          ; shift left
        pop     r1              ; bit into r1
        or      r0, r1
        sw      r0, 0(fp)       ; updated acc
        ; SCL low
        la      r1, -65504
        lc      r0, 0
        sb      r0, 0(r1)
        add     r2, -1
        ceq     r2, z
        brf     .ir_loop
        ; --- master ACK ---
        la      r1, -65504
        lc      r0, 0
        sb      r0, 1(r1)       ; SDA = 0
        lcu     r0, 1
        sb      r0, 0(r1)       ; SCL = 1
        lc      r0, 0
        sb      r0, 0(r1)       ; SCL = 0
        ; --- teardown ---
        pop     r0              ; r0 = acc (return value); also discards local slot
        pop     fp
        pop     r1
        jmp     (r1)
