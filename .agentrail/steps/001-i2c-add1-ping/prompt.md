Write `src/examples/assembler/i2c_add1_ping.s`: a minimal bit-bang
i2c demo that talks to the emulator's `add1` test slave at address
`0x50`, writes byte `0x42`, reads it back (slave returns `0x43`),
and prints the result to UART as two hex digits + newline.

## I2C protocol shape (cribbed from libi2c.c)

MMIO at `0xFF0020` (SCL) and `0xFF0021` (SDA). Both open-drain,
write 1 = release, write 0 = pull low.

Subroutines you'll need (inline in this .s file — no include/macro):

- `hclkdlay`: short busy-wait (~22 loop iterations) — half clock period
- `qclkdlay`: shorter busy-wait (~11) — quarter clock period
- `clkhiw`: SCL=1, then poll SCL waiting for it to read high (slave
  clock-stretching). Bounded loop (100000) so it doesn't hang
  forever.
- `clklo`: SCL=0
- `dathi`: SDA=1
- `datlo`: SDA=0
- `mack`: master ACK — datlo, hclkdlay, clkhiw, hclkdlay, clklo
- `sack`: read slave ACK — dathi, hclkdlay, clkhiw, hclkdlay,
  read SDA, clklo, return value
- `i2cstart`: dathi, hclkdlay, clkhiw, qclkdlay, datlo, qclkdlay, clklo
- `i2cstop`: datlo, hclkdlay, clkhiw, qclkdlay, dathi, qclkdlay, clklo
- `i2cwrite(d)`: 8 bits MSB-first; for each, set SDA = (d >> 7) & 1,
  shift d left, hclkdlay, clkhiw, hclkdlay, clklo. After 8 bits,
  call sack and return its value.
- `i2cread`: 8 bits MSB-first; for each, dathi, hclkdlay, clkhiw,
  hclkdlay, `d = (d << 1) | SDA`, clklo. After 8 bits, call mack,
  return d.

## main flow

1. Init: nothing special. SP not used (no calls into nested stuff
   beyond simple `call`/`ret`).
2. i2cstart
3. i2cwrite(0xA0)  ; addr 0x50 << 1, write bit
4. i2cwrite(0x42)  ; data byte
5. i2cstop
6. i2cstart        ; restart
7. i2cwrite(0xA1)  ; addr 0x50 << 1 | 1, read bit
8. read_byte = i2cread()
9. i2cstop
10. print upper nibble of read_byte as hex char
11. print lower nibble of read_byte as hex char
12. print '\n'
13. halt

## UART

UART data at `0xFF0100`, status at `0xFF0101` (bit 7 = TX busy).
`uart_putc(c)`: poll status until bit 7 clears, then write c to data.

```
uart_putc:
    la r1, 0xFF0100
.uart_wait:
    lb r2, 1(r1)
    cls r2, r2     ; (some way to test bit 7 — use bit mask + brnz)
    brt .uart_wait
    sb r0, 0(r1)
    ret
```

(Adapt to the COR24 instruction set — check existing
`uart_hello.s` for the canonical UART-poll pattern.)

## Calling convention

Look at existing examples (`nested_calls.s`, `stack_variables.s`)
for the COR24 calling convention. Likely: arg in r0, return in r0,
caller-saves what it needs, sp = 0xFEEC00 init.

## Verify

```bash
cargo build --release --workspace
target/release/cor24-asm src/examples/assembler/i2c_add1_ping.s -o /tmp/add1.lgo
cargo run --release --manifest-path /disk1/github/softwarewrighter/devgroup/work/dcxas/github/sw-embed/sw-cor24-emulator/Cargo.toml --bin cor24-run -- --lgo /tmp/add1.lgo --i2c-device add1@0x50
# expect: "43\n"
```

(Or via `cor24-emu` if `cor24-run` doesn't exist — check the emulator
CLI for the right entry point.)

## Register in tests

Add `("Add1 I2C Ping", include_str!("../src/examples/assembler/i2c_add1_ping.s"))`
to `tests/integration_tests.rs::examples()` (alphabetical order
in the list keeps things clean — insert appropriately).

The example halts after one ping, so it does NOT go in
`non_halting`. The test will assemble + run without an i2c device,
and the program will halt (printing wrong data — that's expected;
real verification requires the device attached).

## Wrap

Run full check: `cargo build --workspace --release && cargo test
--workspace && cargo clippy --workspace --all-targets --all-features
-- -D warnings && target/release/cor24-asm -V`.

Commit:
```
feat(examples): add i2c_add1_ping.s — minimal i2c round-trip

Bit-bang i2c demo against the emulator's add1 test slave at
0x50. Writes 0x42, reads back 0x43 (add1 returns byte+1),
prints as "43\n" to UART. Inlines i2c subroutines (no include
mechanism). Halts after one ping.

Verified via cor24-emu --i2c-device add1@0x50.
```

Then `agentrail complete --next-slug i2c-tmp101-read --next-prompt
"<step 2 prompt>"`. Don't dg-mark-pr yet — step 2 still to come.
