; I2C OLED RTC Clock: two-device i2c demo combining DS1307 (RTC at 0x68)
; and SSD1306 (OLED at 0x3C). Initializes the OLED, then loops forever
; reading the time registers and rendering "HH:MM:SS" at page 0 column 0
; of the display. Redrawn every ~10k spin iterations.
;
; Pair with both devices attached:
;     cor24-asm src/examples/assembler/i2c_ssd1306_rtc_clock.s -o /tmp/c.lgo
;     cor24-emu --lgo /tmp/c.lgo \
;               --i2c-device 'ds1307@0x68?preset=system' \
;               --i2c-device ssd1306@0x3C --quiet
;     # use --dump-i2c to see the alternating RTC-read / OLED-draw bursts
;
; Without the OLED, the SSD1306 init writes go nowhere and the draw bursts
; are no-ops — the program still loops cleanly.
; Without the RTC, DS1307 reads return 0xFF for each byte; the BCD-decode
; then renders garbage digits (whatever the >9 nibbles map to in the
; font table — which is just zero-pixel columns for 0x0A..0x0F outside the
; range, depending on offset). Demo still loops cleanly either way.
;
; MMIO:
;     0xFF0020 = SCL  (bit 0 significant; open-drain)
;     0xFF0021 = SDA  (same)
;
; SSD1306 (per i2c_ssd1306_hello.s header for full detail):
;   - addr 0x3C → write byte 0x78
;   - control 0x00 = commands stream, 0x40 = data stream
;   - lenient-consume init: only the modeled commands matter
;
; DS1307 (per i2c_ds1307_read.s header for full detail):
;   - addr 0x68 → write byte 0xD0, read byte 0xD1
;   - registers 0x00 = Seconds (mask 0x7F), 0x01 = Minutes,
;     0x02 = Hours (mask 0x3F)
;
; This is loop-forever by design and goes in non_halting in the test
; harness.
;
; Bit-bang primitives copied verbatim from i2c_ds1307_read.s. Init burst
; structure mirrors i2c_ssd1306_hello.s. Digit-glyph mapping is new here.

        ; --- main ---
        la      r0, 0FEEC00h
        mov     sp, r0

        ; ===== SSD1306 init burst =====
        la      r1, .ret_init_st
        la      r2, i2cstart
        jal     r1, (r2)
.ret_init_st:
        lcu     r0, 78h         ; addr 0x3C << 1, W
        la      r1, .ret_init_a
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_init_a:
        lc      r0, 0           ; control: commands
        la      r1, .ret_init_c
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_init_c:
        lcu     r0, 0AEh        ; display off
        la      r1, .ret_i1
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i1:
        lcu     r0, 20h         ; addressing mode setter
        la      r1, .ret_i2
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i2:
        lc      r0, 0           ; horizontal
        la      r1, .ret_i3
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i3:
        lcu     r0, 21h         ; col range setter
        la      r1, .ret_i4
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i4:
        lc      r0, 0           ; col start
        la      r1, .ret_i5
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i5:
        lcu     r0, 7Fh         ; col end = 127
        la      r1, .ret_i6
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i6:
        lcu     r0, 22h         ; page range setter
        la      r1, .ret_i7
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i7:
        lc      r0, 0           ; page start
        la      r1, .ret_i8
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i8:
        lc      r0, 7           ; page end
        la      r1, .ret_i9
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i9:
        lcu     r0, 0AFh        ; display on
        la      r1, .ret_i10
        la      r2, i2cwrite
        jal     r1, (r2)
.ret_i10:
        la      r1, .ret_init_sp
        la      r2, i2cstop
        jal     r1, (r2)
.ret_init_sp:

; ============================================================================
; Forever loop: read DS1307 → reposition OLED ptr → render HH:MM:SS → delay
; ============================================================================

main_loop:
        ; ----- DS1307 read: S, M, H -----
        la      r1, .rl_rs1
        la      r2, i2cstart
        jal     r1, (r2)
.rl_rs1:
        lcu     r0, 0D0h        ; ds1307 addr + W
        la      r1, .rl_rw1
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_rw1:
        lc      r0, 0           ; pointer = Seconds
        la      r1, .rl_rw2
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_rw2:
        la      r1, .rl_rs2
        la      r2, i2cstart
        jal     r1, (r2)        ; restart
.rl_rs2:
        lcu     r0, 0D1h        ; ds1307 addr + R
        la      r1, .rl_rw3
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_rw3:
        la      r1, .rl_rrs
        la      r2, i2cread
        jal     r1, (r2)        ; r0 = seconds
.rl_rrs:
        push    r0              ; S at sp+0
        la      r1, .rl_rrm
        la      r2, i2cread
        jal     r1, (r2)
.rl_rrm:
        push    r0              ; M at sp+0; S at sp+3
        la      r1, .rl_rrh
        la      r2, i2cread_last ; skip the 9th clock — i2cstop's SCL-up
        jal     r1, (r2)         ; doubles as the ACK clock so its SDA-up
.rl_rrh:                         ; fires a real STOP (see i2cread_last doc)
        push    r0              ; H at sp+0; M at sp+3; S at sp+6
        la      r1, .rl_rsp
        la      r2, i2cstop
        jal     r1, (r2)
.rl_rsp:

        ; Pin fp frame so the offsets stay stable through the upcoming
        ; OLED bursts (which push/pop their own state).
        push    fp
        mov     fp, sp          ; fp+0 = saved fp; +3=H, +6=M, +9=S

        ; ----- OLED: reposition pointer to (page 0, col 0) -----
        la      r1, .rl_pos_st
        la      r2, i2cstart
        jal     r1, (r2)
.rl_pos_st:
        lcu     r0, 78h
        la      r1, .rl_pos_a
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_pos_a:
        lc      r0, 0           ; control: commands
        la      r1, .rl_pos_c
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_pos_c:
        lcu     r0, 0B0h        ; page = 0
        la      r1, .rl_pos_p
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_pos_p:
        lc      r0, 0           ; col low = 0
        la      r1, .rl_pos_cl
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_pos_cl:
        lcu     r0, 10h         ; col high = 0
        la      r1, .rl_pos_ch
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_pos_ch:
        la      r1, .rl_pos_sp
        la      r2, i2cstop
        jal     r1, (r2)
.rl_pos_sp:

        ; ----- OLED: data burst, "HH:MM:SS" = 8 glyphs × 5 = 40 bytes -----
        la      r1, .rl_dat_st
        la      r2, i2cstart
        jal     r1, (r2)
.rl_dat_st:
        lcu     r0, 78h
        la      r1, .rl_dat_a
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_dat_a:
        lcu     r0, 40h         ; control: data
        la      r1, .rl_dat_c
        la      r2, i2cwrite
        jal     r1, (r2)
.rl_dat_c:

        ; Hours (mask 0x3F)
        lw      r0, 3(fp)
        lcu     r2, 3Fh
        and     r0, r2
        la      r1, .rl_rh
        la      r2, render_bcd_byte
        jal     r1, (r2)
.rl_rh:
        la      r1, .rl_colon1
        la      r2, render_colon
        jal     r1, (r2)
.rl_colon1:

        ; Minutes
        lw      r0, 6(fp)
        la      r1, .rl_rm
        la      r2, render_bcd_byte
        jal     r1, (r2)
.rl_rm:
        la      r1, .rl_colon2
        la      r2, render_colon
        jal     r1, (r2)
.rl_colon2:

        ; Seconds (mask 0x7F)
        lw      r0, 9(fp)
        lcu     r2, 7Fh
        and     r0, r2
        la      r1, .rl_rs
        la      r2, render_bcd_byte
        jal     r1, (r2)
.rl_rs:

        la      r1, .rl_dat_sp
        la      r2, i2cstop
        jal     r1, (r2)
.rl_dat_sp:

        ; ----- Teardown fp frame + 3 input slots, then loop -----
        mov     sp, fp
        pop     fp
        add     sp, 9           ; discard H, M, S input slots

        ; Delay between updates
        la      r1, .rl_dly
        la      r2, delay
        jal     r1, (r2)
.rl_dly:

        ; main_loop is far back — use absolute jump (bra is signed 8-bit)
        la      r2, main_loop
        jmp     (r2)

; ============================================================================
; render_bcd_byte(r0): writes 10 font bytes (2 digits) through OPEN i2c
; data transaction. Caller has already done start+0x78+0x40.
; ============================================================================

render_bcd_byte:
        push    r1
        push    r0              ; save full byte
        ; high nibble
        lc      r1, 4
        srl     r0, r1
        la      r1, .rbb_r1
        la      r2, render_digit
        jal     r1, (r2)
.rbb_r1:
        pop     r0
        ; low nibble
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .rbb_r2
        la      r2, render_digit
        jal     r1, (r2)
.rbb_r2:
        pop     r1
        jmp     (r1)

; ============================================================================
; render_digit(r0 = digit 0-9): writes 5 font bytes through OPEN i2c data
; transaction. Computes glyph addr = digit_font + r0 * 5, then writes 5
; bytes one by one via i2cwrite.
; ============================================================================

render_digit:
        push    r1
        ; r0 = digit * 5, done via 4 adds (avoid mul in case of side effects)
        mov     r1, r0          ; r1 = digit
        add     r0, r1          ; r0 = 2*digit
        add     r0, r1          ; r0 = 3*digit
        add     r0, r1          ; r0 = 4*digit
        add     r0, r1          ; r0 = 5*digit
        la      r2, digit_font
        add     r0, r2          ; r0 = glyph addr
        push    fp
        push    r0              ; ptr at 0(fp)
        mov     fp, sp
        lc      r2, 5           ; counter
.rd_loop:
        lw      r1, 0(fp)
        lbu     r0, 0(r1)
        push    r2              ; save counter
        la      r1, .rd_ret
        la      r2, i2cwrite
        jal     r1, (r2)
.rd_ret:
        pop     r2
        lw      r0, 0(fp)
        add     r0, 1
        sw      r0, 0(fp)
        add     r2, -1
        ceq     r2, z
        brf     .rd_loop
        mov     sp, fp
        add     sp, 3
        pop     fp
        pop     r1
        jmp     (r1)

; ============================================================================
; render_colon(): writes 5 font bytes of the ':' glyph. Same shape as
; render_digit but with a fixed font pointer (no mul/add).
; ============================================================================

render_colon:
        push    r1
        la      r0, colon_font
        push    fp
        push    r0
        mov     fp, sp
        lc      r2, 5
.rc_loop:
        lw      r1, 0(fp)
        lbu     r0, 0(r1)
        push    r2
        la      r1, .rc_ret
        la      r2, i2cwrite
        jal     r1, (r2)
.rc_ret:
        pop     r2
        lw      r0, 0(fp)
        add     r0, 1
        sw      r0, 0(fp)
        add     r2, -1
        ceq     r2, z
        brf     .rc_loop
        mov     sp, fp
        add     sp, 3
        pop     fp
        pop     r1
        jmp     (r1)

; ============================================================================
; delay: ~10k spin iterations between RTC reads. Tunable for responsiveness
; at the web demo's 100k IPS budget.
; ============================================================================

delay:
        push    r1
        la      r0, 10000
.dly_loop:
        ceq     r0, z
        brt     .dly_done
        add     r0, -1
        bra     .dly_loop
.dly_done:
        pop     r1
        jmp     (r1)

; ============================================================================
; Font tables — 5×8 glyphs, LSB-at-top column encoding.
;   digit_font: 0..9 = 50 bytes
;   colon_font: ':' = 5 bytes
; ============================================================================

digit_font:
        .byte 3Eh, 51h, 49h, 45h, 3Eh   ; 0
        .byte 00h, 42h, 7Fh, 40h, 00h   ; 1
        .byte 42h, 61h, 51h, 49h, 46h   ; 2
        .byte 21h, 41h, 45h, 4Bh, 31h   ; 3
        .byte 18h, 14h, 12h, 7Fh, 10h   ; 4
        .byte 27h, 45h, 45h, 45h, 39h   ; 5
        .byte 3Ch, 4Ah, 49h, 49h, 30h   ; 6
        .byte 01h, 71h, 09h, 05h, 03h   ; 7
        .byte 36h, 49h, 49h, 49h, 36h   ; 8
        .byte 06h, 49h, 49h, 29h, 1Eh   ; 9
colon_font:
        .byte 00h, 36h, 36h, 00h, 00h   ; :

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

; ============================================================================
; i2cread_last: read 8 bits and return WITHOUT emitting the 9th (ACK/NAK)
; clock. Use this for the LAST byte of a multi-byte read sequence; the
; caller must immediately follow with i2cstop, whose own SCL-up doubles as
; the ACK clock (SDA=0 from i2cstop step 1 → device sees ACK) and the
; subsequent SDA-up fires a real STOP condition.
;
; Why this is needed: after the byte's 8th SCL fall, the bus state machine
; is in AckSlaveToMaster phase and slave_sda_pull = false (the fall in that
; phase resets the slave pull). If we then issued a normal master-NAK
; clock, the bus would transition to TxByte{0,0} on the rise, then on the
; following fall recompute slave_sda_pull = (tx_byte MSB == 0) = true
; (tx_byte was shifted to zero during the byte's 8 bits and never refilled
; because master NAKed). With slave pulling SDA low, the wired-AND
; suppresses i2cstop's SDA-up and STOP is never detected — the master
; ends up clocking ghost bytes out of the slave indefinitely. By skipping
; the explicit 9th clock and letting i2cstop's SCL-up act as the ACK
; clock, slave_sda_pull stays false (no intermediate SCL fall in TxByte)
; and the STOP edge fires cleanly. The slave does see a spurious ACK and
; advances its pointer once, but that's harmless because next iteration
; resets the pointer with a fresh START + addr-write + 0x00.
; ============================================================================

i2cread_last:
        push    r1
        push    fp
        lc      r0, 0
        push    r0              ; acc at 0(fp)
        mov     fp, sp
        lcu     r2, 8           ; counter
.irl_loop:
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)       ; SDA = 1 (release for slave)
        sb      r0, 0(r1)       ; SCL = 1 (slave puts bit on line)
        lbu     r0, 1(r1)       ; r0 = bit
        push    r0              ; save bit
        lw      r0, 0(fp)       ; current acc
        add     r0, r0          ; shift left
        pop     r1              ; bit into r1
        or      r0, r1
        sw      r0, 0(fp)       ; updated acc
        la      r1, -65504
        lc      r0, 0
        sb      r0, 0(r1)       ; SCL = 0
        add     r2, -1
        ceq     r2, z
        brf     .irl_loop
        ; No 9th-clock here — caller's i2cstop combines ACK and STOP.
        ; State at return: scl=0, slave_pull=false, phase=AckSlaveToMaster.
        pop     r0              ; acc = return value
        pop     fp
        pop     r1
        jmp     (r1)
