Write `src/examples/assembler/spi_sdcard_read.s`: SD-SPI init,
read sector 0, print first 16 bytes hex+space+newline. Halt.

## Sequence (per brief)

1. CS high, send ≥80 dummy clocks (10 0xFF bytes via spi_xchg_byte).
2. CS low. Send CMD0 (`0x40 00 00 00 00 0x95`). Poll R1 until 0x01
   (idle).
3. CMD8 (`0x48 00 00 01 AA 0x87`). Read 5 byte R7 (R1 + 4 echo).
   Accept any echo.
4. Loop: CMD55 (`0x77 00 00 00 00 0x01`); read R1 (any).
   ACMD41 (`0x69 0x40 00 00 00 0x01`); read R1; if R1 == 0x00
   exit loop, else retry. Bound the loop to e.g. 10 tries.
5. CMD16 (`0x50 00 00 02 00 0x01`). Read R1.
6. CMD17 (`0x51 00 00 00 00 0x01`). Read R1 (expect 0x00). Wait
   for data token: clock 0xFF until response = 0xFE.
7. Read 512 bytes (clock 0xFF, capture MISO). Discard 2 CRC bytes
   (clock 0xFF twice).
8. CS high. Send 1 trailing 0xFF (clock pulses to release).
9. Print first 16 bytes of the sector: `XX XX XX ... XX\n` (15
   `XX ` pairs + 1 final `XX\n`).
10. Halt.

## SPI MMIO

- 0xFF0030 SPI_DATA: write = MOSI bit (bit 0); read = last MISO bit
- 0xFF0031 SPI_SCLK: bit 0 drives clock
- 0xFF0032 SPI_SELN: bit 0 drives CS (active-low: 1=idle, 0=selected)

## SPI primitives (inline at the bottom of the file)

```asm
; cs_low / cs_high: write SELN
cs_low:
        push    r1
        la      r1, -65486      ; 0xFF0032 SELN
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

; spi_xchg_byte(r0 = MOSI byte) → r0 = MISO byte
; 8 bit-clocks MSB-first; per bit: write MOSI bit, SCLK=1, sample
; MISO, SCLK=0; assemble MISO bits into output byte.
spi_xchg_byte:
        push    r1
        push    fp
        push    r0              ; byte at 0(fp)
        mov     fp, sp
        lc      r0, 0
        push    r0              ; acc at 0(fp -3?? no, push moves sp)
        ; Actually use sp-relative via fp: byte at 0(fp), acc at -3(fp)
        ; But we can't do lw with negative offset cleanly; restructure.
        ...
```

(Use the same fp-frame addressing pattern as the i2c primitives —
push r1, push fp, push the byte, push the accumulator, mov fp to
the accumulator slot, access byte at 3(fp), acc at 0(fp).)

For each bit (8 iterations, mask in r2 walking 0x80 → 0x01):
- byte = lbu 3(fp)
- bit = (byte & mask) != 0 ? 1 : 0
- write MOSI bit, write SCLK=1, read MISO bit, write SCLK=0
- acc = (acc << 1) | miso_bit (stored back via sw 0(fp))
- mask >>= 1; loop while non-zero

Then return acc in r0.

## SD-specific helpers

```asm
; sd_send_cmd: send 6-byte command, return R1 in r0
; args (on stack at fp+3..fp+8): opcode_byte, arg3, arg2, arg1, arg0, crc
; Alternative: encode each command inline (avoids stack-passing
; complexity given the small number of commands).
```

Simpler approach for commands: inline each command's 6 bytes
directly. No sd_send_cmd routine — just six spi_xchg_byte calls
per command, then poll R1 inline.

```asm
; sd_read_r1: clock 0xFF until response with bit 7 clear, return in r0
sd_read_r1:
        push    r1
        lc      r2, 16          ; bound the wait
.r1_loop:
        push    r2
        lcu     r0, 0FFh
        la      r1, .r1_xchg
        la      r2, spi_xchg_byte
        jal     r1, (r2)
.r1_xchg:
        pop     r2
        ; if (r0 & 0x80) == 0: done
        push    r0
        lcu     r1, 80h
        and     r0, r1
        ceq     r0, z
        brt     .r1_done
        pop     r0              ; discard
        add     r2, -1
        ceq     r2, z
        brf     .r1_loop
        ; timeout — return whatever was last seen
        bra     .r1_done_pop
.r1_done:
        pop     r0              ; the R1 value
.r1_done_pop:
        pop     r1
        jmp     (r1)
```

## Print helpers (inline same as prior i2c demos)

```asm
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
```

## Storage for the 16 bytes

Need to capture the first 16 bytes from the 512-byte sector read
into RAM, then print after the read completes (UART writes during
read would slow it down but not break it; either works).

Simpler: read 512 bytes, store first 16 in a fixed buffer at e.g.
`buf_at_0x1000` (any RAM address). Skip the remaining 496 bytes
(just clock them). Discard 2 CRC bytes.

```asm
buf:
        .zero 16
```

Or just declare via `.zero 16` at the bottom.

Read loop:
- Counter r2 = 512 (use .word at top? or load as 24-bit via la)
- For each of 512:
  - clock 0xFF, get MISO byte
  - if byte_idx < 16: store to buf[idx]
  - byte_idx++

For storage: byte_idx in stack slot, buf address in fp+offset.

Print loop:
- Counter r2 = 16
- For i=0..15:
  - byte = lbu buf+i
  - print_hex_byte
  - if i < 15: putc(' ')

## CLI verification

```bash
target/release/cor24-asm src/examples/assembler/spi_sdcard_read.s -o /tmp/dcxas_sd.lgo

# Create test fixture: 512 bytes of 0x00..0x1F repeated 16 times
python3 -c "
import sys
buf = bytes(range(32)) * 16
sys.stdout.buffer.write(buf)
" > /tmp/dcxas_sdtest.img

EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu
$EMU --lgo /tmp/dcxas_sd.lgo --spi-device 'sdcard@cs=2?file=/tmp/dcxas_sdtest.img' \
     --quiet --time 5 -n 500000
# expect: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\n
```

## Integration test

Create `tests/programs/sdcard-test.img` (512 bytes, `bytes(range(32)) * 16`).

In `tests/integration_tests.rs`:
- Register `("SPI SD Card Read", include_str!("../src/examples/assembler/spi_sdcard_read.s"))`
  in `examples()` alphabetically. Current ordering has no SPI yet;
  insert after "Stack Variables", before "UART Hello".
- The example halts; do NOT add to non_halting.
- Add a new integration test that:
  - Assembles the demo
  - Loads into CpuState
  - Attaches an Sdcard slave via the emulator's handle API with
    the test image
  - Runs it
  - Asserts UART contains `00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\n`

## Commit

```
feat(examples): SPI SD Card Read demo

Hand-bit-bangs the SD-SPI init handshake (CMD0/CMD8/CMD55+ACMD41/
CMD16/CMD17), reads sector 0 (512 bytes + 2 CRC), and prints the
first 16 bytes to UART as `XX XX XX ... XX\n`. Halts.

Inlines SPI primitives (cs_low, cs_high, spi_xchg_byte) and
print helpers. Buffers the first 16 bytes in RAM during the read;
clocks the remaining 496 bytes + CRC pair without storage.

Pair with cor24-emu --spi-device 'sdcard@cs=2?file=<path>'.
Without the device or without --file, the demo hangs in the
CMD0-wait loop (no slave responds).

Registered in tests/integration_tests.rs::examples() alphabetically
(after "Stack Variables"). New integration test asserts
"00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\n" against
tests/programs/sdcard-test.img (512 bytes = 0x00..0x1F × 16).

Refs: dcxas-spi-sdcard-and-nor-flash-demos.md (mike, 2026-05-18).
Step 1 of 2. Upstream: dcemu-spi-sdcard-and-nor-flash.md (shipped
on sw-cor24-emulator/main c4ddb55).
```

After step 1 commit: `agentrail complete --next-slug spi-nor-flash-demo --next-prompt /tmp/spi-nor-prompt.md`. Do NOT dg-mark-pr — step 2 still ahead.
