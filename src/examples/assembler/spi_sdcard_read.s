; SPI SD Card Read: bit-bang the SD-SPI init handshake, read sector 0,
; print the first 16 bytes to UART as hex pairs.
;
; Pair with `cor24-emu --spi-device 'sdcard@cs=2?file=<path>'`:
;     cor24-asm src/examples/assembler/spi_sdcard_read.s -o /tmp/sd.lgo
;     cor24-emu --lgo /tmp/sd.lgo --spi-device 'sdcard@cs=2?file=/path/to/disk.img'
;     # prints first 16 bytes of sector 0 as "XX XX ... XX\n"
;
; Without --spi-device, the demo hangs in the CMD0-wait loop (no slave
; responds, MISO stays 0xFF forever — bit 7 set means "not ready"). That's
; the no-card fallback. The cor24-emu CLI accepts the @cs=<n> param for
; forward-compat with multi-slave routing, but today the bus is single-
; slave; we just use the one SELN line.
;
; MMIO (per sw-cor24-emulator/src/cpu/state.rs:45-51):
;     0xFF0030 SPI_DATA — write = MOSI bit (bit 0); read = last MISO bit
;     0xFF0031 SPI_SCLK — bit 0 drives SCLK
;     0xFF0032 SPI_SELN — bit 0 drives CS (active-low; 1 = idle, 0 = selected)
;
; Init sequence (per dcxas-spi-sdcard-and-nor-flash-demos.md):
;     CS high, ≥80 dummy clocks (10 × 0xFF byte exchanges)
;     CS low
;     CMD0  (0x40, 0,0,0,0, 0x95) → R1 = 0x01 (idle)
;     CMD8  (0x48, 0,0,1,0xAA, 0x87) → R1 + 4 byte R7 echo
;     loop: CMD55 (0x77, 0,0,0,0, 0x01) → R1 (any)
;           ACMD41 (0x69, 0x40, 0,0,0, 0x01) → R1 (0x00 = ready, else retry)
;     CMD16 (0x50, 0,0,2,0, 0x01) → R1 (set block length 512)
;     CMD17 (0x51, 0,0,0,0, 0x01) → R1
;     poll for 0xFE data token
;     read 512 data bytes (capture first 16 into sector_buf)
;     read 2 CRC bytes (discard)
;     CS high + 1 trailing 0xFF clock
;     print sector_buf as 16 hex pairs separated by spaces + '\n'
;     halt
;
; SPI primitives (cs_low / cs_high / spi_xchg_byte) and print helpers
; (putc / print_hex_nibble / print_hex_byte) are inlined at the bottom —
; this assembler has no .include or macro mechanism.

        ; --- main ---
        la      r0, 0FEEC00h    ; top of EBR
        mov     sp, r0

        ; ===== CS high, ≥80 dummy clocks =====
        la      r1, .ret_cshigh1
        la      r2, cs_high
        jal     r1, (r2)
.ret_cshigh1:
        ; 10 × 0xFF exchanges = 80 clocks
        lc      r2, 10
.dummy_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .ret_dummy
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_dummy:
        pop     r2
        add     r2, -1
        ceq     r2, z
        brf     .dummy_loop

        ; ===== CS low, then CMD0 =====
        la      r1, .ret_cslow1
        la      r2, cs_low
        jal     r1, (r2)
.ret_cslow1:

        ; --- CMD0: 0x40 0x00 0x00 0x00 0x00 0x95 ---
        lcu     r0, 40h
        la      r1, .ret_c0_0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c0_0:
        lc      r0, 0
        la      r1, .ret_c0_1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c0_1:
        lc      r0, 0
        la      r1, .ret_c0_2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c0_2:
        lc      r0, 0
        la      r1, .ret_c0_3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c0_3:
        lc      r0, 0
        la      r1, .ret_c0_4
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c0_4:
        lcu     r0, 95h
        la      r1, .ret_c0_5
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c0_5:
        ; poll R1 until bit 7 clears (expect 0x01)
        la      r1, .ret_c0_r1
        la      r2, sd_read_r1
        jal     r1, (r2)
.ret_c0_r1:

        ; --- CMD8: 0x48 0x00 0x00 0x01 0xAA 0x87 ---
        lcu     r0, 48h
        la      r1, .ret_c8_0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_0:
        lc      r0, 0
        la      r1, .ret_c8_1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_1:
        lc      r0, 0
        la      r1, .ret_c8_2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_2:
        lc      r0, 1
        la      r1, .ret_c8_3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_3:
        lcu     r0, 0AAh
        la      r1, .ret_c8_4
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_4:
        lcu     r0, 87h
        la      r1, .ret_c8_5
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_5:
        ; R1 + 4 echo bytes (just clock 5 0xFF and discard)
        lc      r2, 5
.c8_resp_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .ret_c8_resp
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c8_resp:
        pop     r2
        add     r2, -1
        ceq     r2, z
        brf     .c8_resp_loop

        ; --- CMD55 + ACMD41 loop (bounded retry; body extracted to subroutines
        ;     so the back-branch fits in brf's signed-8-bit range) ---
        lc      r2, 20
.acmd41_loop:
        push    r2
        la      r1, .ret_c55s
        la      r2, sd_send_cmd55
        jal     r1, (r2)
.ret_c55s:
        la      r1, .ret_c55_r1
        la      r2, sd_read_r1
        jal     r1, (r2)
.ret_c55_r1:
        la      r1, .ret_a41s
        la      r2, sd_send_acmd41
        jal     r1, (r2)
.ret_a41s:
        la      r1, .ret_a41_r1
        la      r2, sd_read_r1
        jal     r1, (r2)
.ret_a41_r1:
        pop     r2
        ceq     r0, z
        brt     .acmd41_done
        add     r2, -1
        ceq     r2, z
        brf     .acmd41_loop
.acmd41_done:

        ; --- CMD16: 0x50 0x00 0x00 0x02 0x00 0x01 (set block length = 512) ---
        lcu     r0, 50h
        la      r1, .ret_c16_0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c16_0:
        lc      r0, 0
        la      r1, .ret_c16_1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c16_1:
        lc      r0, 0
        la      r1, .ret_c16_2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c16_2:
        lc      r0, 2
        la      r1, .ret_c16_3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c16_3:
        lc      r0, 0
        la      r1, .ret_c16_4
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c16_4:
        lc      r0, 1
        la      r1, .ret_c16_5
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c16_5:
        la      r1, .ret_c16_r1
        la      r2, sd_read_r1
        jal     r1, (r2)
.ret_c16_r1:

        ; --- CMD17: 0x51 0x00 0x00 0x00 0x00 0x01 (read single block, sector 0) ---
        lcu     r0, 51h
        la      r1, .ret_c17_0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c17_0:
        lc      r0, 0
        la      r1, .ret_c17_1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c17_1:
        lc      r0, 0
        la      r1, .ret_c17_2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c17_2:
        lc      r0, 0
        la      r1, .ret_c17_3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c17_3:
        lc      r0, 0
        la      r1, .ret_c17_4
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c17_4:
        lc      r0, 1
        la      r1, .ret_c17_5
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_c17_5:
        la      r1, .ret_c17_r1
        la      r2, sd_read_r1
        jal     r1, (r2)
.ret_c17_r1:

        ; --- Wait for data token (0xFE) ---
.token_loop:
        lcu     r0, 0FFh
        la      r1, .ret_tok
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_tok:
        lcu     r2, 0FEh
        ceq     r0, r2
        brf     .token_loop

        ; --- Read 512 bytes; store first 16 to sector_buf, discard rest ---
        ; Frame: byte_idx (24-bit counter 0..511) at 0(fp), buf_ptr at 3(fp)
        ; Actually simpler: walk through using a 16-byte counter for the
        ; capture phase (counter r2 = 16), then a 496-byte counter for the
        ; rest (r2 = 496, walks down).
        ;
        ; Phase 1: capture first 16 bytes.
        la      r0, sector_buf
        push    fp
        push    r0              ; ptr at 0(fp)
        mov     fp, sp
        lcu     r2, 16          ; counter
.cap_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .ret_cap_x
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_cap_x:
        ; r0 = byte from slave; store at buf[ptr], advance
        lw      r1, 0(fp)       ; ptr
        sb      r0, 0(r1)       ; *ptr = byte
        add     r1, 1
        sw      r1, 0(fp)
        pop     r2
        add     r2, -1
        ceq     r2, z
        brf     .cap_loop
        ; teardown ptr frame
        mov     sp, fp
        add     sp, 3
        pop     fp

        ; Phase 2: discard remaining 496 bytes.
        la      r2, 496
.discard_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .ret_disc
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_disc:
        pop     r2
        add     r2, -1
        ceq     r2, z
        brf     .discard_loop

        ; Phase 3: 2 CRC bytes (discard).
        lcu     r0, 0FFh
        la      r1, .ret_crc1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_crc1:
        lcu     r0, 0FFh
        la      r1, .ret_crc2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_crc2:

        ; --- CS high + trailing clock ---
        la      r1, .ret_cshigh2
        la      r2, cs_high
        jal     r1, (r2)
.ret_cshigh2:
        lcu     r0, 0FFh
        la      r1, .ret_trail
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_trail:

        ; --- Print first 16 bytes as "XX XX XX ... XX\n" ---
        la      r0, sector_buf
        push    fp
        push    r0              ; ptr at 0(fp)
        mov     fp, sp
        lc      r2, 16          ; counter
.print_loop:
        push    r2
        ; print byte at *ptr
        lw      r1, 0(fp)
        lbu     r0, 0(r1)
        la      r1, .ret_pb
        la      r2, print_hex_byte
        jal     r1, (r2)
.ret_pb:
        ; if counter > 1, print space; if counter == 1, print '\n'
        pop     r2
        push    r2
        lc      r1, 1
        ceq     r1, r2          ; (1, r2) order — encode supports (1,2) not (2,1)
        brt     .print_nl
        lc      r0, 32          ; ' '
        bra     .print_sep
.print_nl:
        lc      r0, 10          ; '\n'
.print_sep:
        la      r1, .ret_sep
        la      r2, putc
        jal     r1, (r2)
.ret_sep:
        ; advance ptr
        lw      r0, 0(fp)
        add     r0, 1
        sw      r0, 0(fp)
        pop     r2
        add     r2, -1
        ceq     r2, z
        brf     .print_loop
        ; teardown
        mov     sp, fp
        add     sp, 3
        pop     fp

halt:
        bra     halt

; ============================================================================
; sd_send_cmd55: push 6 bytes of CMD55 (0x77 0x00 0x00 0x00 0x00 0x01).
;   Caller follows with sd_read_r1 to get the R1 response.
; ============================================================================

sd_send_cmd55:
        push    r1
        lcu     r0, 77h
        la      r1, .c55_b0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.c55_b0:
        lc      r0, 0
        la      r1, .c55_b1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.c55_b1:
        lc      r0, 0
        la      r1, .c55_b2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.c55_b2:
        lc      r0, 0
        la      r1, .c55_b3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.c55_b3:
        lc      r0, 0
        la      r1, .c55_b4
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.c55_b4:
        lc      r0, 1
        la      r1, .c55_b5
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.c55_b5:
        pop     r1
        jmp     (r1)

; ============================================================================
; sd_send_acmd41: push 6 bytes of ACMD41 (0x69 0x40 0x00 0x00 0x00 0x01).
; ============================================================================

sd_send_acmd41:
        push    r1
        lcu     r0, 69h
        la      r1, .a41_b0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.a41_b0:
        lcu     r0, 40h
        la      r1, .a41_b1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.a41_b1:
        lc      r0, 0
        la      r1, .a41_b2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.a41_b2:
        lc      r0, 0
        la      r1, .a41_b3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.a41_b3:
        lc      r0, 0
        la      r1, .a41_b4
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.a41_b4:
        lc      r0, 1
        la      r1, .a41_b5
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.a41_b5:
        pop     r1
        jmp     (r1)

; ============================================================================
; sd_read_r1: clock 0xFF until response with bit 7 clear; return in r0.
; Bounded loop (256 iterations) to avoid hanging if slave never responds.
; ============================================================================

sd_read_r1:
        push    r1
        push    fp
        la      r0, 256
        push    r0              ; bound counter at 0(fp)
        mov     fp, sp
.r1_loop:
        lcu     r0, 0FFh
        la      r1, .r1_xchg
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.r1_xchg:
        ; if (r0 & 0x80) == 0: done — return r0
        push    r0              ; save the response across the test
        lcu     r1, 80h
        and     r0, r1
        ceq     r0, z
        brt     .r1_done
        pop     r0              ; not done, discard
        ; decrement bound
        lw      r0, 0(fp)
        add     r0, -1
        sw      r0, 0(fp)
        ceq     r0, z
        brf     .r1_loop
        ; timeout
        lcu     r0, 0FFh        ; sentinel
        bra     .r1_finish
.r1_done:
        pop     r0              ; r0 = response value
.r1_finish:
        mov     sp, fp
        add     sp, 3
        pop     fp
        pop     r1
        jmp     (r1)

; ============================================================================
; SPI primitives
; ============================================================================

; cs_low: SELN = 0 (slave selected)
cs_low:
        push    r1
        la      r1, -65486      ; 0xFF0032 SPI_SELN
        lc      r0, 0
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

; cs_high: SELN = 1 (slave deselected)
cs_high:
        push    r1
        la      r1, -65486
        lcu     r0, 1
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

; spi_xchg_byte(r0 = MOSI byte) → r0 = MISO byte
;   8 bit-clocks MSB-first. Per bit: write MOSI bit, pulse SCLK 0→1, sample
;   MISO; assemble MISO bits into the output byte.
;   Frame: byte at 3(fp); accumulator at 0(fp); mask in r2 walks 0x80 → 0x01.
;   The mask doesn't need cross-loop save/restore — nothing in the loop body
;   touches r2 except the final mask shift.
spi_xchg_byte:
        push    r1
        push    fp
        push    r0              ; byte at  3(fp) after the next two pushes
        lc      r0, 0
        push    r0              ; acc  at  0(fp); byte now at 3(fp)
        mov     fp, sp
        lcu     r2, 80h         ; mask = bit 7
.xchg_loop:
        ; --- bit = (byte & mask) ? 1 : 0 ---
        lbu     r0, 3(fp)
        and     r0, r2
        ceq     r0, z
        brt     .xchg_zero
        lc      r0, 1
        bra     .xchg_drive
.xchg_zero:
        lc      r0, 0
.xchg_drive:
        ; --- drive MOSI, pulse SCLK 0→1, sample MISO, SCLK=0 ---
        la      r1, -65488      ; 0xFF0030 SPI_DATA
        sb      r0, 0(r1)
        la      r1, -65487      ; 0xFF0031 SPI_SCLK
        lcu     r0, 1
        sb      r0, 0(r1)
        la      r1, -65488
        lbu     r0, 0(r1)       ; MISO bit (bit 0)
        ; --- acc = (acc << 1) | miso_bit ---
        lw      r1, 0(fp)       ; current acc
        add     r1, r1          ; shift left
        or      r1, r0
        sw      r1, 0(fp)
        ; --- SCLK = 0 ---
        la      r1, -65487
        lc      r0, 0
        sb      r0, 0(r1)
        ; --- mask >>= 1; loop while non-zero ---
        lc      r1, 1
        srl     r2, r1
        ceq     r2, z
        brf     .xchg_loop
        ; --- teardown: pop acc into r0 (return value), discard byte, restore fp/r1 ---
        pop     r0              ; r0 = acc = MISO byte
        add     sp, 3           ; discard byte slot
        pop     fp
        pop     r1
        jmp     (r1)
; ============================================================================
; sector buffer: 16 bytes of capture from sector 0
; ============================================================================

sector_buf:
        .zero 16

; ============================================================================
; UART helpers (copied verbatim from prior demos)
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
        clu     r0, r2          ; r0 < 10 ?
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

print_hex_byte:
        push    r1
        push    r0
        lc      r1, 4
        srl     r0, r1          ; high nibble
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .phb_h
        la      r2, print_hex_nibble
        jal     r1, (r2)
.phb_h:
        pop     r0
        lcu     r2, 0Fh
        and     r0, r2          ; low nibble
        la      r1, .phb_l
        la      r2, print_hex_nibble
        jal     r1, (r2)
.phb_l:
        pop     r1
        jmp     (r1)
