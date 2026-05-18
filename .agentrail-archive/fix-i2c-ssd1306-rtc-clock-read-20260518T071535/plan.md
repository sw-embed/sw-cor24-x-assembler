# Saga: fix-i2c-ssd1306-rtc-clock-read

## Goal

Fix `i2c_ssd1306_rtc_clock.s` so the DS1307 read sequence ends
with a clean STOP. Per dwxas's brief
`dcxas-fix-i2c-ssd1306-rtc-clock-read.md`.

## Root cause

The emulator's i2c bus state machine
(`sw-cor24-emulator/src/cpu/i2c_bus.rs:149`) detects STOP only
when SDA rises **on the effective line** while SCL is high. The
effective SDA is `master_sda && !slave_sda_pull` (open-drain
wired-AND).

After the 3rd `i2cread`, master-ACK leaves the slave in "OK,
prepare next byte" state, with `slave_sda_pull = true` (slave is
about to drive bit 7 of the next byte). My `i2cstop`'s SDA-up
write becomes `eff_sda = 1 && !true = 0` — no SDA rising edge,
so STOP never registers. The bus stays in the read transaction
forever, the slave keeps streaming bytes (auto-incrementing
pointer wraps through registers and into RAM), and my
`main_loop` body lands subsequent i2c traffic on a stale state
machine.

Standard i2c protocol fix: **NAK the last byte** of a multi-byte
read instead of ACKing. NAK = master releases SDA (drives high)
on the 9th clock pulse. Slave sees NAK and releases SDA
(`slave_sda_pull = false`). Then `i2cstop`'s SDA-up write
actually rises the effective line → STOP detected.

## What's actually changing

| File | Change |
|---|---|
| `src/examples/assembler/i2c_ssd1306_rtc_clock.s` | add `i2creadnak` subroutine (variant of `i2cread` with master-NAK at end); change the 3rd read call in `main_loop` (for H) to use it |

No changes to:
- The existing `i2cread` primitive (used in `i2c_ds1307_read.s`
  which still works for its halt-after-print use case).
- `i2c_ssd1306_hello.s` (no `i2cread` use).
- The emulator (the bus state machine is correct; my driver was
  violating protocol).
- Test infrastructure or any other example.

## Why not also fix i2c_ds1307_read.s?

Mike's brief explicitly out-of-scopes shared primitives and asks
not to introduce regressions. The read demo halts immediately
after `i2cstop`, so the bus's stuck state has no visible
consequence — UART output is correct because the bytes were
correctly read before the bad-STOP. Worth a future cleanup
(it's still wrong i2c protocol) but not blocking.

## Acceptance (per brief)

- `--dump-i2c` shows exactly **3 RD entries and one STOP** per
  main_loop iteration.
- OLED matches DS1307 register values for any input
  (`?hour=...&minute=...&second=...` or `?preset=system`).
- `i2c_ssd1306_hello.s` and `i2c_ds1307_read.s` still pass
  (no regressions).
- `cargo test` green.

## Steps

1. **fix-i2c-ssd1306-rtc-clock-read** — single step. Add
   `i2creadnak`; retarget the 3rd read; verify with `--dump-i2c`
   and visual byte-decode of the OLED data burst; check
   regressions.

## When done

Two pr/ branches per the strict-superset discipline:
- `pr/fix-i2c-ssd1306-rtc-clock-read` — the fix
- `pr/fix-i2c-ssd1306-rtc-clock-read-saga-complete` — bookkeeping

After mike relays, dwxas refreshes their sibling clone and
rebuilds `pages/`.
