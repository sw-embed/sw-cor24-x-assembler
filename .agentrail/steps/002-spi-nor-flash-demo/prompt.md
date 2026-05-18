Write `src/examples/assembler/spi_nor_flash_demo.s`: full
read-erase-program-read cycle on the W25Q32 NOR flash.

## Sequence (per brief)

1. CS low, send `0x9F` (JEDEC ID), read 3 ID bytes (expect
   `0xEF 0x40 0x16`), CS high. Print `JEDEC: EF 40 16\n`.
2. CS low, send `0x03 0x00 0x00 0x00` (Read Data, 24-bit addr 0),
   read 4 bytes from address 0, CS high. Print `BEFORE: XX XX XX XX\n`.
3. CS low, send `0x06` (Write Enable), CS high.
4. CS low, send `0x20 0x00 0x00 0x00` (Sector Erase), CS high.
5. Poll status: CS low, send `0x05`, read 1 byte (status); loop
   while WIP bit (bit 0) is set. CS high.
6. CS low, send `0x06` (Write Enable again — auto-cleared after
   each erase/program), CS high.
7. CS low, send `0x02 0x00 0x00 0x00 0xDE 0xAD 0xBE 0xEF` (Page
   Program at addr 0 with 4 data bytes), CS high.
8. Poll status WIP again. CS high.
9. CS low, send `0x03 0x00 0x00 0x00`, read 4 bytes, CS high.
   Print `AFTER: DE AD BE EF\n`.
10. Halt.

## Reuse from step 1 (copy verbatim — no .include)

- `cs_low`, `cs_high`, `spi_xchg_byte`
- `putc`, `print_hex_nibble`, `print_hex_byte`

## New helpers

```asm
; nor_write_enable: CS low, send 0x06, CS high
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

; nor_poll_wip: CS low, send 0x05; loop reading status bytes until
;   WIP bit (bit 0) is clear; CS high. Bounded.
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
        ; Loop bound: e.g. 20_000 (sector erase needs ~4096 byte-clocks)
        la      r2, 20000
.pwip_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .pwip_rd
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.pwip_rd:
        ; bit 0 set → still busy
        pop     r2
        push    r0
        lcu     r1, 1
        and     r0, r1
        ceq     r0, z
        brt     .pwip_done
        pop     r0          ; not done, discard
        add     r2, -1
        ceq     r2, z
        brf     .pwip_loop
        ; timeout — fall through
        bra     .pwip_finish
.pwip_done:
        pop     r0
.pwip_finish:
        la      r1, .pwip_cs2
        la      r2, cs_high
        jal     r1, (r2)
.pwip_cs2:
        pop     r1
        jmp     (r1)
```

The body of nor_poll_wip uses brf with conditional check — make
sure the loop body fits in signed-8-bit range (it does — ~30
bytes).

## Storage

Need a 4-byte buffer for the BEFORE and AFTER reads. Use a
`.zero 4` slot. Or store each read separately. Simplest: read
all 4 bytes into a 4-byte buffer, print, reuse the buffer for
the AFTER read.

```asm
read_buf:
        .zero 4
```

## Print helpers

```asm
; print_label_then_bytes(r0 = label addr, r2 = num bytes from read_buf)
;   Prints: "LABEL XX XX XX XX\n"
```

Actually inline the prints — fewer abstractions, easier to debug.

For "JEDEC: EF 40 16\n":
- Print 'J', 'E', 'D', 'E', 'C', ':', ' '
- Print 3 bytes from buffer separated by spaces (or just inline)
- Print '\n'

Probably simplest to inline a putc chain for the literal text and
a small loop for the bytes.

Alternatively define print_str_inline as a helper that takes a
fixed string. But assembler doesn't have a print_str primitive;
easier to spell it out.

For the JEDEC label, just call putc('J'), putc('E'), etc.

For BEFORE/AFTER, ditto.

## Reading the JEDEC + data

The JEDEC sequence is:
1. cs_low
2. spi_xchg_byte(0x9F)         ; opcode
3. r0 = spi_xchg_byte(0xFF)    ; ID byte 1 (manufacturer = 0xEF)
4. r0 = spi_xchg_byte(0xFF)    ; ID byte 2 (memory type = 0x40)
5. r0 = spi_xchg_byte(0xFF)    ; ID byte 3 (capacity = 0x16)
6. cs_high

Store each into the read buffer at offsets 0, 1, 2, then print.

For read-data:
1. cs_low
2. spi_xchg_byte(0x03)
3. spi_xchg_byte(0x00)
4. spi_xchg_byte(0x00)
5. spi_xchg_byte(0x00)
6. spi_xchg_byte(0xFF) → byte 0
7. spi_xchg_byte(0xFF) → byte 1
8. spi_xchg_byte(0xFF) → byte 2
9. spi_xchg_byte(0xFF) → byte 3
10. cs_high

Same for after.

## Sector erase / page program

Just inline the sequences. Each is a short fixed pattern (CS low,
send a few bytes, CS high). Both are followed by nor_poll_wip.

## Verify

```bash
target/release/cor24-asm src/examples/assembler/spi_nor_flash_demo.s -o /tmp/dcxas_nor.lgo
EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu
$EMU --lgo /tmp/dcxas_nor.lgo --spi-device 'w25q32@cs=3' --quiet --time 60 -n 50000000
# expect:
# JEDEC: EF 40 16
# BEFORE: FF FF FF FF    (default erased state)
# AFTER: DE AD BE EF
```

Note the WIP polling can take many cycles — Sector Erase is 4096
byte-clocks ≈ ~50K instructions per byte read in the poll loop.
So overall ~50M instructions easily; pad -n accordingly.

## Integration test

Add:
```rust
#[test]
fn test_spi_nor_flash_demo() {
    let nor = W25q32Device::new_in_memory(3);  // CS=3, in-memory image
    let cpu = assemble_and_run_with_spi::<W25q32Device>(
        example_source("SPI NOR Flash Program"),
        50_000_000,
        nor,
    );
    assert!(cpu.io.uart_output.contains("JEDEC: EF 40 16"));
    assert!(cpu.io.uart_output.contains("AFTER: DE AD BE EF"));
}
```

(Check w25q32.rs for the actual constructor name; might be
`with_image` or similar.)

## Register in examples()

Insert `("SPI NOR Flash Program", include_str!("../src/examples/assembler/spi_nor_flash_demo.s"))`
alphabetically. Per brief: between "SPI Echo Ping" and "SPI SD Card Read".
But "SPI Echo Ping" doesn't exist in this repo. Insert between
"Stack Variables"'s neighbor and "SPI SD Card Read".

Actually current order is: ... Stack Variables ... wait, let me
check after step 1. With "SPI SD Card Read" already inserted:
... "SPI SD Card Read", "Stack Variables" ...

"SPI NOR Flash Program" comes alphabetically BEFORE "SPI SD Card Read"
(N < S). So insert between whatever's before "SPI SD Card Read"
and "SPI SD Card Read" itself.

Same non_halting reasoning — without device, demo hangs. Add to
non_halting; end-to-end via dedicated test.

## Commit

```
feat(examples): SPI NOR Flash Program demo

Demonstrates the full read-erase-program-read cycle on the W25Q32
4 MiB NOR flash. Sequence:
  1. JEDEC ID (0x9F) → expect EF 40 16; print "JEDEC: EF 40 16\n"
  2. Read 4 bytes from 0x000000 → print "BEFORE: XX XX XX XX\n"
     (typically FF FF FF FF for a fresh/erased device)
  3. Write Enable (0x06)
  4. Sector Erase (0x20 0x00 0x00 0x00)
  5. Poll status (0x05) until WIP bit clears (~4096 byte-clocks)
  6. Write Enable again (auto-cleared after each program/erase)
  7. Page Program (0x02 0x00 0x00 0x00 + 4 data bytes)
  8. Poll WIP again
  9. Read 4 bytes from 0x000000 → print "AFTER: DE AD BE EF\n"
 10. Halt

Inlines new nor_write_enable and nor_poll_wip helpers; reuses
cs_low / cs_high / spi_xchg_byte / putc / print_hex_byte /
print_hex_nibble from the SD card demo (no .include mechanism).
A 4-byte read_buf captures each read's data for printing.

Pair with cor24-emu --spi-device 'w25q32@cs=3[?file=<path>]'.
Without --file, an in-memory 4 MiB 0xFF scratch is used (state
lost on exit). Without --spi-device the demo hangs in the WIP
poll loop reading 0xFF and never seeing bit 0 clear; added to
non_halting in test_all_examples_halt. End-to-end coverage in
test_spi_nor_flash_demo which attaches a W25q32Device and
asserts the UART output contains "JEDEC: EF 40 16" and
"AFTER: DE AD BE EF".

Registered in tests/integration_tests.rs::examples() alphabetically
before "SPI SD Card Read".

Refs: dcxas-spi-sdcard-and-nor-flash-demos.md (mike, 2026-05-18).
Step 2 of 2.
```

## After step 2

`agentrail complete --done`. `dg-mark-pr` →
`pr/spi-sdcard-and-nor-flash-demos`. Then bookkeeping branch
(strict superset).
