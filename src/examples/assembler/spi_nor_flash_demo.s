; SPI NOR Flash Program: full read-erase-program-read cycle on the W25Q32.
;
; Pair with `cor24-emu --spi-device 'w25q32@cs=3[?file=<path>]'`:
;     cor24-asm src/examples/assembler/spi_nor_flash_demo.s -o /tmp/nor.lgo
;     cor24-emu --lgo /tmp/nor.lgo --spi-device 'w25q32@cs=3?file=/tmp/w25q32.bin'
;
; Without --file the chip is an in-memory 4 MiB 0xFF scratch; writes survive
; the run but are discarded on exit. Without --spi-device the demo hangs in
; the WIP poll loop reading 0xFF and never seeing bit 0 clear; the
; integration test sidesteps that by attaching a W25q32Device directly.
;
; MMIO (per sw-cor24-emulator/src/cpu/state.rs:45-51):
;     0xFF0030 SPI_DATA — write = MOSI bit (bit 0); read = last MISO bit
;     0xFF0031 SPI_SCLK — bit 0 drives SCLK
;     0xFF0032 SPI_SELN — bit 0 drives CS (active-low; 1 = idle, 0 = selected)
;
; Sequence (per dcxas-spi-sdcard-and-nor-flash-demos.md §Step 2):
;     1. CS low → 0x9F (JEDEC ID) → read 3 ID bytes (expect EF 40 16)
;        → CS high.  Print "JEDEC: EF 40 16\n".
;     2. CS low → 0x03 0x00 0x00 0x00 (Read Data, 3-byte addr 0) →
;        read 4 bytes → CS high.  Print "BEFORE: XX XX XX XX\n".
;        (Fresh / erased flash reads as FF FF FF FF.)
;     3. CS low → 0x06 (Write Enable) → CS high.
;     4. CS low → 0x20 0x00 0x00 0x00 (Sector Erase) → CS high.
;     5. Poll status (0x05) until WIP bit (bit 0) clears
;        (~4096 byte-clocks per the device's WIP timing model).
;     6. CS low → 0x06 again (WEL is auto-cleared after each erase/program).
;     7. CS low → 0x02 0x00 0x00 0x00 0xDE 0xAD 0xBE 0xEF (Page Program at 0)
;        → CS high.
;     8. Poll WIP again (~1024 byte-clocks for Page Program).
;     9. Read 4 bytes from 0x000000 → "AFTER: DE AD BE EF\n".
;    10. Halt.
;
; SPI primitives (cs_low / cs_high / spi_xchg_byte) and print helpers
; (putc / print_hex_nibble / print_hex_byte) are copied verbatim from
; spi_sdcard_read.s — this assembler has no .include or macro mechanism.

        ; --- main ---
        la      r0, 0FEEC00h    ; top of EBR
        mov     sp, r0

        ; ===== 1. JEDEC ID =====
        la      r1, .ret_jid_cs1
        la      r2, cs_low
        jal     r1, (r2)
.ret_jid_cs1:
        lcu     r0, 9Fh         ; JEDEC ID opcode
        la      r1, .ret_jid_op
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_jid_op:
        ; read 3 ID bytes into read_buf[0..2]
        lcu     r0, 0FFh
        la      r1, .ret_jid_b0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_jid_b0:
        la      r1, read_buf
        sb      r0, 0(r1)
        lcu     r0, 0FFh
        la      r1, .ret_jid_b1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_jid_b1:
        la      r1, read_buf
        sb      r0, 1(r1)
        lcu     r0, 0FFh
        la      r1, .ret_jid_b2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_jid_b2:
        la      r1, read_buf
        sb      r0, 2(r1)
        la      r1, .ret_jid_cs2
        la      r2, cs_high
        jal     r1, (r2)
.ret_jid_cs2:

        ; "JEDEC: "
        la      r1, .ret_jl
        la      r2, print_jedec_label
        jal     r1, (r2)
.ret_jl:
        ; 3 bytes from buffer, space-separated
        lc      r0, 0
        la      r1, .ret_jp0
        la      r2, print_buf_byte
        jal     r1, (r2)
.ret_jp0:
        lc      r0, 32          ; ' '
        la      r1, .ret_jsp0
        la      r2, putc
        jal     r1, (r2)
.ret_jsp0:
        lc      r0, 1
        la      r1, .ret_jp1
        la      r2, print_buf_byte
        jal     r1, (r2)
.ret_jp1:
        lc      r0, 32
        la      r1, .ret_jsp1
        la      r2, putc
        jal     r1, (r2)
.ret_jsp1:
        lc      r0, 2
        la      r1, .ret_jp2
        la      r2, print_buf_byte
        jal     r1, (r2)
.ret_jp2:
        lc      r0, 10          ; '\n'
        la      r1, .ret_jnl
        la      r2, putc
        jal     r1, (r2)
.ret_jnl:

        ; ===== 2. Read 4 bytes from 0x000000 (BEFORE) =====
        la      r1, .ret_rb_cs1
        la      r2, cs_low
        jal     r1, (r2)
.ret_rb_cs1:
        lcu     r0, 03h         ; Read Data
        la      r1, .ret_rb_op
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_rb_op:
        lc      r0, 0           ; addr byte 2
        la      r1, .ret_rb_a2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_rb_a2:
        lc      r0, 0           ; addr byte 1
        la      r1, .ret_rb_a1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_rb_a1:
        lc      r0, 0           ; addr byte 0
        la      r1, .ret_rb_a0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_rb_a0:
        la      r1, .ret_rb_4
        la      r2, read_four_bytes_to_buf
        jal     r1, (r2)
.ret_rb_4:
        la      r1, .ret_rb_cs2
        la      r2, cs_high
        jal     r1, (r2)
.ret_rb_cs2:

        ; "BEFORE: " + 4 bytes + '\n'
        la      r1, .ret_bl
        la      r2, print_before_label
        jal     r1, (r2)
.ret_bl:
        la      r1, .ret_bp
        la      r2, print_four_buf_bytes
        jal     r1, (r2)
.ret_bp:

        ; ===== 3. Write Enable =====
        la      r1, .ret_we1
        la      r2, nor_write_enable
        jal     r1, (r2)
.ret_we1:

        ; ===== 4. Sector Erase (0x20 + 3-byte addr 0) =====
        la      r1, .ret_se_cs1
        la      r2, cs_low
        jal     r1, (r2)
.ret_se_cs1:
        lcu     r0, 20h
        la      r1, .ret_se_op
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_se_op:
        lc      r0, 0
        la      r1, .ret_se_a2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_se_a2:
        lc      r0, 0
        la      r1, .ret_se_a1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_se_a1:
        lc      r0, 0
        la      r1, .ret_se_a0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_se_a0:
        la      r1, .ret_se_cs2
        la      r2, cs_high
        jal     r1, (r2)
.ret_se_cs2:

        ; ===== 5. Poll WIP =====
        la      r1, .ret_wip1
        la      r2, nor_poll_wip
        jal     r1, (r2)
.ret_wip1:

        ; ===== 6. Write Enable again =====
        la      r1, .ret_we2
        la      r2, nor_write_enable
        jal     r1, (r2)
.ret_we2:

        ; ===== 7. Page Program (0x02 + 3-byte addr + 4 data bytes) =====
        la      r1, .ret_pp_cs1
        la      r2, cs_low
        jal     r1, (r2)
.ret_pp_cs1:
        lcu     r0, 02h
        la      r1, .ret_pp_op
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_op:
        lc      r0, 0
        la      r1, .ret_pp_a2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_a2:
        lc      r0, 0
        la      r1, .ret_pp_a1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_a1:
        lc      r0, 0
        la      r1, .ret_pp_a0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_a0:
        lcu     r0, 0DEh
        la      r1, .ret_pp_d0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_d0:
        lcu     r0, 0ADh
        la      r1, .ret_pp_d1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_d1:
        lcu     r0, 0BEh
        la      r1, .ret_pp_d2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_d2:
        lcu     r0, 0EFh
        la      r1, .ret_pp_d3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_pp_d3:
        la      r1, .ret_pp_cs2
        la      r2, cs_high
        jal     r1, (r2)
.ret_pp_cs2:

        ; ===== 8. Poll WIP =====
        la      r1, .ret_wip2
        la      r2, nor_poll_wip
        jal     r1, (r2)
.ret_wip2:

        ; ===== 9. Read 4 bytes from 0x000000 (AFTER) =====
        la      r1, .ret_ra_cs1
        la      r2, cs_low
        jal     r1, (r2)
.ret_ra_cs1:
        lcu     r0, 03h
        la      r1, .ret_ra_op
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_ra_op:
        lc      r0, 0
        la      r1, .ret_ra_a2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_ra_a2:
        lc      r0, 0
        la      r1, .ret_ra_a1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_ra_a1:
        lc      r0, 0
        la      r1, .ret_ra_a0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.ret_ra_a0:
        la      r1, .ret_ra_4
        la      r2, read_four_bytes_to_buf
        jal     r1, (r2)
.ret_ra_4:
        la      r1, .ret_ra_cs2
        la      r2, cs_high
        jal     r1, (r2)
.ret_ra_cs2:

        ; "AFTER: " + 4 bytes + '\n'
        la      r1, .ret_al
        la      r2, print_after_label
        jal     r1, (r2)
.ret_al:
        la      r1, .ret_ap
        la      r2, print_four_buf_bytes
        jal     r1, (r2)
.ret_ap:

halt:
        bra     halt

; ============================================================================
; nor_write_enable: CS low → 0x06 → CS high
; ============================================================================

nor_write_enable:
        push    r1
        la      r1, .nwe_cs1
        la      r2, cs_low
        jal     r1, (r2)
.nwe_cs1:
        lcu     r0, 06h
        la      r1, .nwe_x
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.nwe_x:
        la      r1, .nwe_cs2
        la      r2, cs_high
        jal     r1, (r2)
.nwe_cs2:
        pop     r1
        jmp     (r1)

; ============================================================================
; nor_poll_wip: CS low → 0x05 → loop reading status until bit 0 (WIP) is 0
; → CS high. Bounded to ~20_000 iterations (Sector Erase = 4096 byte-clocks
; per the device's WIP model, so 20k is well above worst-case).
; ============================================================================

nor_poll_wip:
        push    r1
        la      r1, .pwip_cs1
        la      r2, cs_low
        jal     r1, (r2)
.pwip_cs1:
        lcu     r0, 05h
        la      r1, .pwip_op
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.pwip_op:
        la      r2, 20000       ; bound
.pwip_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .pwip_rd
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.pwip_rd:
        ; r0 = status; if bit 0 (WIP) clear → done
        pop     r2
        push    r0
        lcu     r1, 1
        and     r0, r1
        ceq     r0, z
        brt     .pwip_done
        pop     r0              ; not done, discard status
        add     r2, -1
        ceq     r2, z
        brf     .pwip_loop
        bra     .pwip_finish    ; timeout (still keep going to CS-high)
.pwip_done:
        pop     r0              ; discard saved status
.pwip_finish:
        la      r1, .pwip_cs2
        la      r2, cs_high
        jal     r1, (r2)
.pwip_cs2:
        pop     r1
        jmp     (r1)

; ============================================================================
; read_four_bytes_to_buf: clock 4 0xFF bytes, store responses to read_buf[0..3].
; Caller has already CS-low'd, sent the read opcode + 3 addr bytes; caller
; will CS-high afterwards.
; ============================================================================

read_four_bytes_to_buf:
        push    r1
        ; b0
        lcu     r0, 0FFh
        la      r1, .r4_b0
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.r4_b0:
        la      r1, read_buf
        sb      r0, 0(r1)
        ; b1
        lcu     r0, 0FFh
        la      r1, .r4_b1
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.r4_b1:
        la      r1, read_buf
        sb      r0, 1(r1)
        ; b2
        lcu     r0, 0FFh
        la      r1, .r4_b2
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.r4_b2:
        la      r1, read_buf
        sb      r0, 2(r1)
        ; b3
        lcu     r0, 0FFh
        la      r1, .r4_b3
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.r4_b3:
        la      r1, read_buf
        sb      r0, 3(r1)
        pop     r1
        jmp     (r1)

; ============================================================================
; print_buf_byte(r0 = index 0..3): print read_buf[idx] as 2 hex chars.
; ============================================================================

print_buf_byte:
        push    r1
        la      r1, read_buf
        add     r1, r0          ; r1 = &read_buf[idx]
        lbu     r0, 0(r1)
        la      r1, .pbb_ret
        la      r2, print_hex_byte
        jal     r1, (r2)
.pbb_ret:
        pop     r1
        jmp     (r1)

; ============================================================================
; print_four_buf_bytes: print read_buf[0..3] as "XX XX XX XX\n".
; ============================================================================

print_four_buf_bytes:
        push    r1
        lc      r0, 0
        la      r1, .p4_0
        la      r2, print_buf_byte
        jal     r1, (r2)
.p4_0:
        lc      r0, 32
        la      r1, .p4_s0
        la      r2, putc
        jal     r1, (r2)
.p4_s0:
        lc      r0, 1
        la      r1, .p4_1
        la      r2, print_buf_byte
        jal     r1, (r2)
.p4_1:
        lc      r0, 32
        la      r1, .p4_s1
        la      r2, putc
        jal     r1, (r2)
.p4_s1:
        lc      r0, 2
        la      r1, .p4_2
        la      r2, print_buf_byte
        jal     r1, (r2)
.p4_2:
        lc      r0, 32
        la      r1, .p4_s2
        la      r2, putc
        jal     r1, (r2)
.p4_s2:
        lc      r0, 3
        la      r1, .p4_3
        la      r2, print_buf_byte
        jal     r1, (r2)
.p4_3:
        lc      r0, 10          ; '\n'
        la      r1, .p4_nl
        la      r2, putc
        jal     r1, (r2)
.p4_nl:
        pop     r1
        jmp     (r1)

; ============================================================================
; print_jedec_label: emit "JEDEC: "
; ============================================================================

print_jedec_label:
        push    r1
        lc      r0, 74          ; 'J'
        la      r1, .jl0
        la      r2, putc
        jal     r1, (r2)
.jl0:
        lc      r0, 69          ; 'E'
        la      r1, .jl1
        la      r2, putc
        jal     r1, (r2)
.jl1:
        lc      r0, 68          ; 'D'
        la      r1, .jl2
        la      r2, putc
        jal     r1, (r2)
.jl2:
        lc      r0, 69          ; 'E'
        la      r1, .jl3
        la      r2, putc
        jal     r1, (r2)
.jl3:
        lc      r0, 67          ; 'C'
        la      r1, .jl4
        la      r2, putc
        jal     r1, (r2)
.jl4:
        lc      r0, 58          ; ':'
        la      r1, .jl5
        la      r2, putc
        jal     r1, (r2)
.jl5:
        lc      r0, 32          ; ' '
        la      r1, .jl6
        la      r2, putc
        jal     r1, (r2)
.jl6:
        pop     r1
        jmp     (r1)

; ============================================================================
; print_before_label: emit "BEFORE: "
; ============================================================================

print_before_label:
        push    r1
        lc      r0, 66          ; 'B'
        la      r1, .bl0
        la      r2, putc
        jal     r1, (r2)
.bl0:
        lc      r0, 69          ; 'E'
        la      r1, .bl1
        la      r2, putc
        jal     r1, (r2)
.bl1:
        lc      r0, 70          ; 'F'
        la      r1, .bl2
        la      r2, putc
        jal     r1, (r2)
.bl2:
        lc      r0, 79          ; 'O'
        la      r1, .bl3
        la      r2, putc
        jal     r1, (r2)
.bl3:
        lc      r0, 82          ; 'R'
        la      r1, .bl4
        la      r2, putc
        jal     r1, (r2)
.bl4:
        lc      r0, 69          ; 'E'
        la      r1, .bl5
        la      r2, putc
        jal     r1, (r2)
.bl5:
        lc      r0, 58          ; ':'
        la      r1, .bl6
        la      r2, putc
        jal     r1, (r2)
.bl6:
        lc      r0, 32          ; ' '
        la      r1, .bl7
        la      r2, putc
        jal     r1, (r2)
.bl7:
        pop     r1
        jmp     (r1)

; ============================================================================
; print_after_label: emit "AFTER: "
; ============================================================================

print_after_label:
        push    r1
        lc      r0, 65          ; 'A'
        la      r1, .al0
        la      r2, putc
        jal     r1, (r2)
.al0:
        lc      r0, 70          ; 'F'
        la      r1, .al1
        la      r2, putc
        jal     r1, (r2)
.al1:
        lc      r0, 84          ; 'T'
        la      r1, .al2
        la      r2, putc
        jal     r1, (r2)
.al2:
        lc      r0, 69          ; 'E'
        la      r1, .al3
        la      r2, putc
        jal     r1, (r2)
.al3:
        lc      r0, 82          ; 'R'
        la      r1, .al4
        la      r2, putc
        jal     r1, (r2)
.al4:
        lc      r0, 58          ; ':'
        la      r1, .al5
        la      r2, putc
        jal     r1, (r2)
.al5:
        lc      r0, 32          ; ' '
        la      r1, .al6
        la      r2, putc
        jal     r1, (r2)
.al6:
        pop     r1
        jmp     (r1)

; ============================================================================
; 4-byte read buffer (reused across the BEFORE / AFTER reads + JEDEC ID,
; though we only ever use bytes 0..2 for JEDEC and 0..3 for the data reads)
; ============================================================================

read_buf:
        .zero 4

; ============================================================================
; SPI primitives (copied verbatim from spi_sdcard_read.s)
; ============================================================================

cs_low:
        push    r1
        la      r1, -65486      ; 0xFF0032 SPI_SELN
        lc      r0, 0
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

cs_high:
        push    r1
        la      r1, -65486
        lcu     r0, 1
        sb      r0, 0(r1)
        pop     r1
        jmp     (r1)

spi_xchg_byte:
        push    r1
        push    fp
        push    r0
        lc      r0, 0
        push    r0
        mov     fp, sp
        lcu     r2, 80h
.xchg_loop:
        lbu     r0, 3(fp)
        and     r0, r2
        ceq     r0, z
        brt     .xchg_zero
        lc      r0, 1
        bra     .xchg_drive
.xchg_zero:
        lc      r0, 0
.xchg_drive:
        la      r1, -65488      ; SPI_DATA
        sb      r0, 0(r1)
        la      r1, -65487      ; SPI_SCLK
        lcu     r0, 1
        sb      r0, 0(r1)
        la      r1, -65488
        lbu     r0, 0(r1)       ; MISO bit
        lw      r1, 0(fp)
        add     r1, r1
        or      r1, r0
        sw      r1, 0(fp)
        la      r1, -65487
        lc      r0, 0
        sb      r0, 0(r1)
        lc      r1, 1
        srl     r2, r1
        ceq     r2, z
        brf     .xchg_loop
        pop     r0              ; acc → return
        add     sp, 3
        pop     fp
        pop     r1
        jmp     (r1)

; ============================================================================
; UART helpers (copied verbatim from spi_sdcard_read.s)
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

print_hex_byte:
        push    r1
        push    r0
        lc      r1, 4
        srl     r0, r1
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .phb_h
        la      r2, print_hex_nibble
        jal     r1, (r2)
.phb_h:
        pop     r0
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .phb_l
        la      r2, print_hex_nibble
        jal     r1, (r2)
.phb_l:
        pop     r1
        jmp     (r1)
