; I2C DS1307 Set: interactive UART-driven RTC time-set demo.
;
; Reads 6 ASCII digits (HHMMSS) from UART RX, parses to BCD, writes the
; DS1307's seconds/minutes/hours registers (0x00-0x02) via i2c, then reads
; the registers back and prints "HH:MM:SS\n" to UART. Halts.
;
; Pair with `cor24-emu --uart-input "<6 digits>" --i2c-device ds1307@0x68`:
;     cor24-asm src/examples/assembler/i2c_ds1307_set.s -o /tmp/dsset.lgo
;     cor24-emu --lgo /tmp/dsset.lgo --uart-input "123456" \
;               --i2c-device ds1307@0x68 --quiet
;     # expect "12:34:56\n"
;
; Without --uart-input the program busy-polls UART RX forever waiting for
; the 6 digits — that's the interactive case (use --terminal). The
; tests/integration_tests.rs harness handles this by adding the example to
; the `non_halting` list.
;
; MMIO:
;     0xFF0020 = SCL ; 0xFF0021 = SDA (open-drain bit-bang)
;     0xFF0100 = UART data (read = RX, write = TX; read auto-clears RX-ready)
;     0xFF0101 = UART status:
;                  bit 0 = RX ready, bit 2 = RX overflow, bit 7 = TX busy
;
; DS1307 register write sequence (auto-incrementing pointer):
;     i2cstart → write 0xD0 (addr+W) → write 0x00 (pointer = Seconds) →
;     write S → write M → write H → i2cstop
;
; Read-back follows the same shape as i2c_ds1307_read.s.
;
; Bit-bang i2c primitives, putc, print_hex_nibble, and print_bcd_byte are
; copied verbatim from i2c_ds1307_read.s — this assembler has no .include
; or macro mechanism.

        ; --- main ---
        la      r0, 0FEEC00h
        mov     sp, r0

        ; Read 3 BCD pairs from UART: H, M, S
        la      r1, .ret_rh
        la      r2, read_bcd_pair
        jal     r1, (r2)
.ret_rh:
        push    r0              ; hours (most-recent push at sp+0)

        la      r1, .ret_rm
        la      r2, read_bcd_pair
        jal     r1, (r2)
.ret_rm:
        push    r0              ; minutes

        la      r1, .ret_rs
        la      r2, read_bcd_pair
        jal     r1, (r2)
.ret_rs:
        push    r0              ; seconds

        ; Stack now: sp+0=S, sp+3=M, sp+6=H
        ; Pin an fp frame so the offsets stay stable through nested calls.
        push    fp
        mov     fp, sp          ; fp+0 = saved fp; +3=S, +6=M, +9=H

        ; --- i2c write: set pointer = 0, then S, M, H ---
        la      r1, .ret_ws1
        la      r2, i2cstart
        jal     r1, (r2)
.ret_ws1:
        lcu     r0, 0D0h        ; addr 0x68 << 1, W
        la      r1, .ret_ww1
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_ww1:
        lc      r0, 0           ; pointer = 0
        la      r1, .ret_ww2
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_ww2:
        lw      r0, 3(fp)       ; seconds
        la      r1, .ret_wws
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_wws:
        lw      r0, 6(fp)       ; minutes
        la      r1, .ret_wwm
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_wwm:
        lw      r0, 9(fp)       ; hours
        la      r1, .ret_wwh
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_wwh:
        la      r1, .ret_ws2
        la      r2, i2cstop
        jal     r1, (r2)
.ret_ws2:

        ; --- i2c read-back: pointer = 0, then read S', M', H' ---
        la      r1, .ret_rs1
        la      r2, i2cstart
        jal     r1, (r2)
.ret_rs1:
        lcu     r0, 0D0h
        la      r1, .ret_rw1
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_rw1:
        lc      r0, 0
        la      r1, .ret_rw2
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_rw2:
        la      r1, .ret_rs2
        la      r2, i2cstart
        jal     r1, (r2)
.ret_rs2:
        lcu     r0, 0D1h        ; addr 0x68 << 1, R
        la      r1, .ret_rw3
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_rw3:
        la      r1, .ret_rrs
        la      r2, i2cread
        jal     r1, (r2)        ; r0 = seconds (read-back)
.ret_rrs:
        push    r0              ; new local: S' at sp+0 (offsets from fp shift)
        la      r1, .ret_rrm
        la      r2, i2cread
        jal     r1, (r2)
.ret_rrm:
        push    r0              ; M' at sp+0; S' at sp+3
        la      r1, .ret_rrh
        la      r2, i2cread
        jal     r1, (r2)
.ret_rrh:
        push    r0              ; H' at sp+0; M' at sp+3; S' at sp+6
        la      r1, .ret_rs3
        la      r2, i2cstop
        jal     r1, (r2)
.ret_rs3:

        ; --- print "HH:MM:SS\n" from the read-back values ---
        ; They're on the stack at sp+0/+3/+6 (H'/M'/S'). Pop them as we print.
        pop     r0              ; H'
        lcu     r2, 3Fh
        and     r0, r2          ; mask 12/24-mode bit
        la      r1, .ret_ph
        la      r2, print_bcd_byte
        jal     r1, (r2)
.ret_ph:
        lc      r0, 58          ; ':'
        la      r1, .ret_c1
        la      r2, putc
        jal     r1, (r2)
.ret_c1:
        pop     r0              ; M'
        la      r1, .ret_pm
        la      r2, print_bcd_byte
        jal     r1, (r2)
.ret_pm:
        lc      r0, 58          ; ':'
        la      r1, .ret_c2
        la      r2, putc
        jal     r1, (r2)
.ret_c2:
        pop     r0              ; S'
        lcu     r2, 7Fh
        and     r0, r2          ; mask CH bit
        la      r1, .ret_ps
        la      r2, print_bcd_byte
        jal     r1, (r2)
.ret_ps:
        lc      r0, 10          ; '\n'
        la      r1, .ret_nl
        la      r2, putc
        jal     r1, (r2)
.ret_nl:

        ; --- teardown: drop the fp frame + the 3 original input slots ---
        mov     sp, fp
        pop     fp
        add     sp, 9           ; discard H, M, S input slots (3 × 3 bytes)

halt:
        bra     halt

; ============================================================================
; uart_getc(): block until UART RX has a byte, then return it in r0.
; ============================================================================

uart_getc:
        push    r1
        la      r1, -65279      ; UART status = 0xFF0101
.ug_wait:
        lbu     r2, 0(r1)
        lcu     r0, 1           ; RX-ready mask (bit 0)
        and     r2, r0
        ceq     r2, z
        brt     .ug_wait
        la      r1, -65280      ; UART data = 0xFF0100  (read clears RX-ready)
        lbu     r0, 0(r1)
        pop     r1
        jmp     (r1)

; ============================================================================
; read_bcd_pair(): read 2 ASCII digits from UART, return BCD byte in r0.
;                  r0 = ((d0 - '0') << 4) | (d1 - '0')
; ============================================================================

read_bcd_pair:
        push    r1
        ; tens digit
        la      r1, .rbp_r1
        la      r2, uart_getc
        jal     r1, (r2)
.rbp_r1:
        add     r0, -48         ; ASCII → 0..9
        push    r0
        ; ones digit
        la      r1, .rbp_r2
        la      r2, uart_getc
        jal     r1, (r2)
.rbp_r2:
        add     r0, -48
        pop     r2              ; r2 = tens
        lc      r1, 4
        shl     r2, r1
        or      r0, r2
        pop     r1
        jmp     (r1)

; ============================================================================
; print_bcd_byte(r0): emit r0 (low 8 bits) as 2 BCD digits.
; ============================================================================

print_bcd_byte:
        push    r1
        push    r0
        lc      r1, 4
        srl     r0, r1          ; upper nibble
        la      r1, .pbb_ret1
        la      r2, print_hex_nibble
        jal     r1, (r2)
.pbb_ret1:
        pop     r0
        lcu     r2, 0Fh
        and     r0, r2          ; lower nibble
        la      r1, .pbb_ret2
        la      r2, print_hex_nibble
        jal     r1, (r2)
.pbb_ret2:
        pop     r1
        jmp     (r1)

; ============================================================================
; UART TX helpers (copied verbatim from i2c_ds1307_read.s)
; ============================================================================

putc:
        push    r1
        push    r0
        la      r1, -65280
.putc_wait:
        lb      r2, 1(r1)
        cls     r2, z
        brt     .putc_wait
        pop     r0
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

print_hex_nibble:
        push    r1
        lcu     r2, 10
        clu     r0, r2
        brt     .phn_digit
        add     r0, 55
        bra     .phn_emit
.phn_digit:
        add     r0, 48
.phn_emit:
        la      r2, putc
        jal     r1, (r2)
        pop     r1
        jmp     (r1)

; ============================================================================
; I2C bit-bang primitives (copied verbatim from i2c_ds1307_read.s)
; ============================================================================

i2cstart:
        push    r1
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)
        sb      r0, 0(r1)
        lc      r0, 0
        sb      r0, 1(r1)
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

i2cstop:
        push    r1
        la      r1, -65504
        lc      r0, 0
        sb      r0, 1(r1)
        lcu     r0, 1
        sb      r0, 0(r1)
        sb      r0, 1(r1)
        lc      r0, 0
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

i2cwrite:
        push    r1
        push    fp
        push    r0
        mov     fp, sp
        lcu     r2, 80h
.iw_loop:
        lbu     r0, 0(fp)
        and     r0, r2
        ceq     r0, z
        brt     .iw_zero
        lc      r0, 1
        bra     .iw_set
.iw_zero:
        lc      r0, 0
.iw_set:
        la      r1, -65504
        sb      r0, 1(r1)
        lcu     r0, 1
        sb      r0, 0(r1)
        lc      r0, 0
        sb      r0, 0(r1)
        lc      r1, 1
        srl     r2, r1
        ceq     r2, z
        brf     .iw_loop
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)
        sb      r0, 0(r1)
        lbu     r0, 1(r1)
        lcu     r2, 1
        and     r0, r2
        push    r0
        lc      r2, 0
        la      r1, -65504
        sb      r2, 0(r1)
        pop     r0
        add     sp, 3
        pop     fp
        pop     r1
        jmp     (r1)

i2cread:
        push    r1
        push    fp
        lc      r0, 0
        push    r0
        mov     fp, sp
        lcu     r2, 8
.ir_loop:
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)
        sb      r0, 0(r1)
        lbu     r0, 1(r1)
        push    r0
        lw      r0, 0(fp)
        add     r0, r0
        pop     r1
        or      r0, r1
        sw      r0, 0(fp)
        la      r1, -65504
        lc      r0, 0
        sb      r0, 0(r1)
        add     r2, -1
        ceq     r2, z
        brf     .ir_loop
        la      r1, -65504
        lc      r0, 0
        sb      r0, 1(r1)
        lcu     r0, 1
        sb      r0, 0(r1)
        lc      r0, 0
        sb      r0, 0(r1)
        pop     r0
        pop     fp
        pop     r1
        jmp     (r1)
