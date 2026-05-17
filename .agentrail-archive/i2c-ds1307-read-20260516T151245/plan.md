# Saga: i2c-ds1307-read

## Goal

Add `src/examples/assembler/i2c_ds1307_read.s` — a bit-bang i2c
demo that reads the current time from the emulator's DS1307
real-time-clock device at address `0x68`, formats it as
`HH:MM:SS\n`, and prints to UART. Halts.

This is the assembler-side piece of the RTC live demo. Pairs with
dwxas's planned web `i2c-rtc-panel` (their future saga step) which
will provide a UI to set the time; the .s example will read what
the panel sets and the web demo will show the round-trip.

## What's actually changing

| File | Change |
|---|---|
| `src/examples/assembler/i2c_ds1307_read.s` (new) | bit-bang demo: write pointer=0, read 3 bytes (S/M/H), format BCD → ASCII, print "HH:MM:SS\n" |
| `tests/integration_tests.rs` (2 hunks) | register `("I2C DS1307 Read", ...)` in `examples()` between "I2C Add1 Ping" and "Literals" |

No public-API change. No `Cargo.toml` change. No emulator changes.

## DS1307 protocol shape (per emulator docs in
## `sw-cor24-emulator/src/peripherals/i2c/devices/ds1307.rs`)

- 7-bit i2c addr `0x68` → master write byte `0xD0`, read byte `0xD1`.
- 8 BCD registers behind an auto-incrementing pointer:
    - `0x00` Seconds — high nibble = tens, low = ones; **bit 7 = CH**
      (Clock Halt) — mask on read with `0x7F`.
    - `0x01` Minutes — BCD; valid 0–59.
    - `0x02` Hours — BCD 24-hour; **bit 6 = 12/24 mode** (this device
      stores 24-hour) — mask with `0x3F`.
    - `0x03`–`0x06` — DoW / Date / Month / Year (not used by this demo).
    - `0x07` Control (not used by this demo).
- To read time: i2cstart → write 0xD0 → write 0x00 (pointer) → restart
  → write 0xD1 → read N bytes (pointer auto-increments per read) →
  i2cstop. After reading 3 bytes the pointer sits at `0x03`.

## Architectural note

Inlines its own copy of the bit-bang i2c primitives (i2cstart /
i2cstop / i2cwrite / i2cread), same shape as `i2c_add1_ping.s`,
because this assembler has no `.include` or macro mechanism. The
two examples could be refactored into a shared `i2c_lib.s` once
that gain lands (future saga).

For BCD → ASCII conversion the existing `print_hex_nibble` helper
already does the right thing for 0–9 values (`+'0'` path); A–F
path is dead code for BCD inputs. Reusing it keeps the file small.

Bit 7 of seconds (CH) and bit 6 of hours (12/24 mode) are masked
before BCD conversion so the output is correct even if the device
happens to set those bits in some configuration.

## Out of scope

- No DoW / date / month / year readout (just HH:MM:SS for v1).
- No shared `i2c_lib.s` — each example self-contained.
- No looping daemon variant (halts after one read).
- No `cor24-emulator` changes — the DS1307 device is already
  shipped at origin/main (8d12b75) / origin/dev (0eed0e1).
- No web `i2c-rtc-panel` changes — separate dwxas saga.

## Verification

```bash
cargo build --workspace --release
target/release/cor24-asm src/examples/assembler/i2c_ds1307_read.s -o /tmp/ds.lgo
$EMU --lgo /tmp/ds.lgo --i2c-device ds1307@0x68 --quiet --time 5
# expect output like "00:00:00\n" (DS1307 defaults to all-zero
# registers per the registry's no-params spec)
```

(Setting a non-zero time requires either the web panel's
`Ds1307HandleExt::set_time(...)` API or a future `--i2c-device
ds1307@0x68?hour=12&minute=34&second=56`-style param. The current
CLI registry accepts no params, so the demo will read 00:00:00 in
isolation — that's fine for assembler-side verification.)

Without an i2c device attached, the read returns 0xFF for each
byte, so the BCD-decode produces garbage (e.g. `FF:FF:FF\n` once
masking strips bit 6/7 → masked values still > 9 so the digits
fall through `print_hex_nibble`'s A-F path). Documented in the
file header.

## Steps

1. **i2c-ds1307-read** — single step. Write the .s file, register
   in tests, verify via cor24-emu, commit. Then `dg-mark-pr` →
   `pr/i2c-ds1307-read` and the standard post-complete bookkeeping
   branch.

## When done

Two pr/ branches per the established pattern:
- `pr/i2c-ds1307-read` — the work
- `pr/i2c-ds1307-read-saga-complete` — bookkeeping

dwxas's web `i2c-rtc-panel` brief (when written) will consume this
`.s` file via `include_str!` and pair it with a panel UI that sets
the DS1307 registers in real time.
