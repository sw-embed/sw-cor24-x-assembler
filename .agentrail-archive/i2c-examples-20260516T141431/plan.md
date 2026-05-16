# Saga: i2c-examples

## Goal

Add two i2c assembler examples to `src/examples/assembler/` for
the web live demo (and `cor24-emu --i2c-device` users) to pick up
via the existing auto-discovery in `tests/integration_tests.rs::
examples()`.

- `i2c_add1_ping.s` — minimal round-trip via the `add1` test slave.
  Write byte, read it back (slave returns `byte + 1`), print result
  to UART as two hex chars. Best teaching example for the i2c
  protocol shape.
- `i2c_tmp101_read.s` — practical: setup TMP101 to 10-bit
  resolution, one temperature read, print formatted "DD.DD\n". Pairs
  with the web demo's planned TMP101 panel (step 6 of
  web-sw-cor24-x-assembler's saga).

Briefs / references:
- Emulator i2c reference: `sw-cor24-emulator/examples/i2c/tmp101/libi2c.c`
- Emulator i2c bus + devices: `sw-cor24-emulator/src/cpu/i2c_bus.rs`,
  `sw-cor24-emulator/src/peripherals/i2c/devices/{add1,tmp101}.rs`
- Web demo plan steps 5-6: `web-sw-cor24-x-assembler/.agentrail/plan.md`

## Why two steps, not one

Each example is a substantial chunk of assembly (~150-200 lines
with inlined i2c subroutines, since this assembler has no
`.include` / macros). Committing per example means if tmp101 turns
out tricky, add1 work is already safely landed.

## I2C MMIO contract (per `i2cio.h`)

- `0xFF0020` — SCL (clock line), bit 0 significant, open-drain
- `0xFF0021` — SDA (data line), bit 0 significant, open-drain
- Default device addresses: `add1` at `0x50`, `tmp101` at `0x4A`

## What's actually changing

| File | Change |
|---|---|
| `src/examples/assembler/i2c_add1_ping.s` (new) | minimal bit-bang demo against add1 slave |
| `src/examples/assembler/i2c_tmp101_read.s` (new) | TMP101 setup + one-read + formatted print |
| `tests/integration_tests.rs` (2 hunks) | register both in `examples()`; let `test_all_examples_halt` cover them (both halt after one op even with no device attached) |

No new directives needed. No public-API change. No `Cargo.toml`
change.

## Architectural note

Each `.s` inlines its own copy of i2c subroutines (i2cstart,
i2cstop, i2cwrite, i2cread, plus hclkdlay/qclkdlay/clkhiw helpers)
because this assembler has no include/macro mechanism. Future work:
a shared `i2c_lib.s` once the assembler gains `.include` or the
build pipeline gains a concat step. Out of scope here.

Both examples halt after one operation rather than looping
forever — this keeps the existing `test_all_examples_halt` test
happy without per-example device wiring. Looping daemon variants
can be a future saga.

Without an i2c device attached, SDA reads return 1 (open-drain
default), so the programs run to completion but print "garbage"
data (e.g. add1 reports 0xFF, tmp101 reads zero temperature). Real
verification: `cor24-emu --lgo <out> --i2c-device add1@0x50` or
`tmp101@0x4A?temp=25.0`.

## Out of scope

- No shared `i2c_lib.s` — each example self-contained.
- No looping daemon variants.
- No web-side panel work (separate web saga steps 5-6).
- No new assembler directives or features.
- No changes to `button_echo.s` / other examples.
- No emulator changes.

## Steps

1. **i2c-add1-ping** — write `i2c_add1_ping.s`. Verify byte-bang
   round-trip via `cor24-emu --i2c-device add1@0x50` produces
   expected output. Register in `examples()`. Commit.
2. **i2c-tmp101-read** — write `i2c_tmp101_read.s`. Verify via
   `cor24-emu --i2c-device tmp101@0x4A?temp=25.0` produces
   "25.00\n". Register in `examples()`. Commit.

After step 2: `agentrail complete --done`, `dg-mark-pr` →
`pr/i2c-examples`, then post-complete bookkeeping branch →
`pr/i2c-examples-saga-complete`.
