; I2C DS1307 Read: bit-bang i2c demo against the emulator's DS1307 RTC.
;
; Reads seconds / minutes / hours from registers 0x00..0x02 of the DS1307
; at i2c address 0x68, formats them as "HH:MM:SS\n" and prints to UART.
; Halts after one read.
;
; CLI one-liners (per sw-cor24-emulator's ds1307-initial-time-and-system-preset
; saga, shipped on origin/dev 07a0b69):
;
;   # show the host clock (registry reads SystemTime::now() at attach time):
;   cor24-asm src/examples/assembler/i2c_ds1307_read.s -o /tmp/r.lgo
;   cor24-emu --lgo /tmp/r.lgo --i2c-device 'ds1307@0x68?preset=system'
;
;   # show a specific time (explicit BCD register values):
;   cor24-emu --lgo /tmp/r.lgo \
;       --i2c-device 'ds1307@0x68?hour=12&minute=34&second=56'
;
;   # default (no params): device boots at 00:00:00 and the demo prints that:
;   cor24-emu --lgo /tmp/r.lgo --i2c-device ds1307@0x68
;
; The web RTC panel uses the runtime `Ds1307HandleExt::set_*` API to drive
; mid-session updates via its slider; the CLI params above are the
; equivalent at attach time.
;
; Without any i2c device attached, the emulator's bus returns 0 for SDA reads,
; so the output is indistinguishable from the all-zero device case
; ("00:00:00\n"). Either way the program halts cleanly after one read.
;
; MMIO:
;     0xFF0020 = SCL  (bit 0 significant; open-drain: 1 = release, 0 = pull)
;     0xFF0021 = SDA  (same)
;     0xFF0100 = UART data; 0xFF0101 = UART status (bit 7 = TX busy)
;
; DS1307 register layout (per sw-cor24-emulator/src/peripherals/i2c/devices/ds1307.rs):
;     0x00  Seconds   BCD;  bit 7 = CH (Clock Halt) — mask read with 0x7F
;     0x01  Minutes   BCD;  0-59
;     0x02  Hours     BCD;  bit 6 = 12/24-hour mode — mask read with 0x3F
;     0x03  DoW       (not used)
;     0x04  Date      (not used)
;     0x05  Month     (not used)
;     0x06  Year      (not used)
;     0x07  Control   (not used)
;
; Read sequence: i2cstart → write 0xD0 (addr+W) → write 0x00 (pointer) →
; restart → write 0xD1 (addr+R) → read S → read M → read H → i2cstop.
; The DS1307's pointer auto-increments per read.
;
; The bit-bang i2c primitives (i2cstart / i2cstop / i2cwrite / i2cread)
; and putc / print_hex_nibble helpers are copied verbatim from
; i2c_add1_ping.s — this assembler has no .include or macro mechanism.

        ; --- main ---
        la      r0, 0FEEC00h    ; top of EBR stack
        mov     sp, r0

        ; START + write pointer = 0
        la      r1, .ret_s1
        la      r2, i2cstart
        jal     r1, (r2)
.ret_s1:
        lcu     r0, 0D0h        ; addr 0x68 << 1, W
        la      r1, .ret_w1
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_w1:
        lc      r0, 0           ; pointer = 0 (Seconds)
        la      r1, .ret_w2
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_w2:

        ; RESTART + read 3 bytes (S, M, H)
        la      r1, .ret_s2
        la      r2, i2cstart
        jal     r1, (r2)
.ret_s2:
        lcu     r0, 0D1h        ; addr 0x68 << 1, R
        la      r1, .ret_w3
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_w3:
        la      r1, .ret_rs
        la      r2, i2cread
        jal     r1, (r2)        ; r0 = seconds
.ret_rs:
        push    r0              ; sp+0 = seconds (after the next pushes, shifts)
        la      r1, .ret_rm
        la      r2, i2cread
        jal     r1, (r2)        ; r0 = minutes
.ret_rm:
        push    r0              ; sp+0 = minutes; sp+3 = seconds
        la      r1, .ret_rh
        la      r2, i2cread
        jal     r1, (r2)        ; r0 = hours
.ret_rh:
        push    r0              ; sp+0 = hours; sp+3 = minutes; sp+6 = seconds

        ; STOP
        la      r1, .ret_st
        la      r2, i2cstop
        jal     r1, (r2)
.ret_st:

        ; --- format & print "HH:MM:SS\n" ---
        ; (sp+0=H, sp+3=M, sp+6=S — we pop each in reverse order through fp)
        ; We'll use fp as the frame anchor so the stack offsets stay stable
        ; even as putc/print_hex_nibble push their own state.
        push    fp
        mov     fp, sp          ; fp+0 = saved fp; +3=H, +6=M, +9=S

        ; --- print hours (mask 0x3F for 24-hour) ---
        lw      r0, 3(fp)
        lcu     r2, 3Fh
        and     r0, r2
        la      r1, .ret_ph
        la      r2, print_bcd_byte
        jal     r1, (r2)
.ret_ph:
        lc      r0, 58          ; ':'
        la      r1, .ret_c1
        la      r2, putc
        jal     r1, (r2)
.ret_c1:

        ; --- print minutes ---
        lw      r0, 6(fp)
        la      r1, .ret_pm
        la      r2, print_bcd_byte
        jal     r1, (r2)
.ret_pm:
        lc      r0, 58          ; ':'
        la      r1, .ret_c2
        la      r2, putc
        jal     r1, (r2)
.ret_c2:

        ; --- print seconds (mask 0x7F to drop CH bit) ---
        lw      r0, 9(fp)
        lcu     r2, 7Fh
        and     r0, r2
        la      r1, .ret_ps
        la      r2, print_bcd_byte
        jal     r1, (r2)
.ret_ps:

        ; '\n'
        lc      r0, 10
        la      r1, .ret_nl
        la      r2, putc
        jal     r1, (r2)
.ret_nl:

        ; --- teardown the frame + 3 register slots, then halt ---
        mov     sp, fp
        pop     fp
        add     sp, 9           ; discard H, M, S slots (3 × 3 bytes)

halt:
        bra     halt

; ============================================================================
; print_bcd_byte(r0): emit r0 (low 8 bits) as 2 BCD digits.
; ============================================================================

print_bcd_byte:
        push    r1
        push    r0              ; preserve full byte for the low nibble
        ; upper nibble: r0 >> 4
        lc      r1, 4
        srl     r0, r1
        la      r1, .pbb_ret1
        la      r2, print_hex_nibble
        jal     r1, (r2)
.pbb_ret1:
        pop     r0
        ; lower nibble: r0 & 0x0F
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .pbb_ret2
        la      r2, print_hex_nibble
        jal     r1, (r2)
.pbb_ret2:
        pop     r1
        jmp     (r1)

; ============================================================================
; UART helpers  (copied verbatim from i2c_add1_ping.s)
; ============================================================================

putc:
        push    r1
        push    r0
        la      r1, -65280      ; UART base = 0xFF0100
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
; I2C bit-bang primitives  (copied verbatim from i2c_add1_ping.s)
;   cf. sw-cor24-emulator/examples/i2c/tmp101/libi2c.c
; ============================================================================

i2cstart:
        push    r1
        la      r1, -65504      ; I2C base = 0xFF0020 (SCL @ +0, SDA @ +1)
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
        push    r0              ; byte at 0(fp)
        mov     fp, sp
        lcu     r2, 80h         ; mask
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
        ; slave ACK
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
        add     sp, 3           ; discard byte local
        pop     fp
        pop     r1
        jmp     (r1)

i2cread:
        push    r1
        push    fp
        lc      r0, 0
        push    r0              ; acc at 0(fp)
        mov     fp, sp
        lcu     r2, 8           ; counter
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
        ; master ACK
        la      r1, -65504
        lc      r0, 0
        sb      r0, 1(r1)
        lcu     r0, 1
        sb      r0, 0(r1)
        lc      r0, 0
        sb      r0, 0(r1)
        pop     r0              ; acc = return value
        pop     fp
        pop     r1
        jmp     (r1)
