Write `src/examples/assembler/i2c_ds1307_read.s`: bit-bang i2c
master that reads seconds/minutes/hours from the DS1307 at addr
0x68 and prints `HH:MM:SS\n` to UART. Halt.

## Protocol

DS1307 (per emulator docs):
- I2C addr 0x68 → write byte 0xD0, read byte 0xD1
- 8 BCD registers behind auto-incrementing pointer
- Register 0 = Seconds (mask bit 7 = CH on read with 0x7F)
- Register 1 = Minutes (BCD)
- Register 2 = Hours (24-hour; mask bit 6 = 12/24 mode with 0x3F)

Read sequence:
1. i2cstart
2. i2cwrite(0xD0)            ; addr + W
3. i2cwrite(0x00)            ; set pointer to seconds
4. i2cstart                  ; restart
5. i2cwrite(0xD1)            ; addr + R
6. r_seconds = i2cread()
7. r_minutes = i2cread()
8. r_hours   = i2cread()
9. i2cstop
10. mask + format + print "HH:MM:SS\n"
11. halt

## Reuse from i2c_add1_ping.s

Copy verbatim (this assembler has no `.include`):
- `putc` (UART poll-and-write)
- `print_hex_nibble` (works correctly for BCD 0-9 digits via
  the +'0' path)
- `i2cstart`, `i2cstop`, `i2cwrite`, `i2cread` (the bit-bang
  primitives, including the fp-frame addressing pattern)

Make sure to copy them EXACTLY — they took several rounds to get
right (sp can't be load/store base, only fp can; shifts need
register operands, not immediates; lc/add/ceq don't accept fp as
LHS).

## New: `print_bcd_byte(r0)` helper

Format a single BCD byte as 2 ASCII digits:

```
print_bcd_byte:
        push    r1
        push    r0              ; preserve byte across nibble prints
        ; upper nibble
        lc      r1, 4
        srl     r0, r1
        ; (low 4 bits of shifted result, since BCD digits are 0-9)
        la      r1, .pbb_ret1
        la      r2, print_hex_nibble
        jal     r1, (r2)
.pbb_ret1:
        pop     r0
        ; lower nibble
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .pbb_ret2
        la      r2, print_hex_nibble
        jal     r1, (r2)
.pbb_ret2:
        pop     r1
        jmp     (r1)
```

## Main flow

Save the 3 read bytes (s, m, h) on the stack as they come in (the
register file is too small to hold them concurrently with the
print calls). Print order is `H : M : S \n`. Mask before printing:
- hours: AND with 0x3F
- minutes: AND with 0x7F (or no mask — minutes is always 0-59 in
  emulator)
- seconds: AND with 0x7F

## Verify

```bash
cargo build --workspace --release
target/release/cor24-asm src/examples/assembler/i2c_ds1307_read.s -o /tmp/ds.lgo
EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu
$EMU --lgo /tmp/ds.lgo --i2c-device ds1307@0x68 --quiet --time 5
# expect "00:00:00\n" (CLI ds1307 spec accepts no params; defaults
# to all-zero registers)
```

Also run:
```bash
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
```

The example doesn't go in `non_halting`; it halts after one read
even with no device attached (reads return 0xFF, BCD-decode produces
"FF:FF:FF\n" via the A-F fallback in print_hex_nibble; still halts).

## Register in tests

Edit `tests/integration_tests.rs::examples()` — add entry
`("I2C DS1307 Read", include_str!("../src/examples/assembler/i2c_ds1307_read.s"))`
between "I2C Add1 Ping" and "Literals" (alphabetical position).

## Commit

```
feat(examples): add I2C DS1307 Read demo

Bit-bang i2c master reads seconds/minutes/hours from the DS1307
real-time clock at addr 0x68 and prints "HH:MM:SS\n" to UART.
Inlines i2c primitives (same shape as i2c_add1_ping.s) and adds
print_bcd_byte for BCD → ASCII formatting; CH (sec bit 7) and
12/24-mode (hr bit 6) masked before decode.

Pair with cor24-emu --i2c-device ds1307@0x68 (no params; defaults
to all-zero registers → prints 00:00:00\n). The web side's planned
i2c-rtc-panel will pair with this .s to provide an interactive
clock-setting UI.

Registered in tests/integration_tests.rs::examples() between
"I2C Add1 Ping" and "Literals".
```

Include the .agentrail/ deltas (saga init + step complete) in the
same commit, per the established pattern.

## Wrap

`agentrail complete --done`. `dg-mark-pr` → `pr/i2c-ds1307-read`.
Then the post-complete bookkeeping branch
`pr/i2c-ds1307-read-saga-complete`. STOP.
