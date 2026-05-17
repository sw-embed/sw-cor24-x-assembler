# Saga: i2c-ds1307-set (rebuild)

## Goal

Add `src/examples/assembler/i2c_ds1307_set.s` — interactive UART-
driven DS1307 RTC time-set demo. Same content as the previous
attempt; this saga rebuilds the branch chain off current `dev`
(which already has `i2c-ds1307-read` merged) per
`dcxas-finish-ds1307-set-and-document-cli-preset.md` Part 1.

The original `pr/i2c-ds1307-set` and `pr/i2c-ds1307-set-saga-complete`
had a rename/rename conflict against dev: both branches archived
`i2c-examples` to different timestamped directories (T141431 from
read vs T142625 from set), plus a `tests/integration_tests.rs`
content conflict because both inserted "I2C RTC X" at the same
alphabetical slot. Rebuild resolves both by archiving the
NOW-active saga on dev (`i2c-ds1307-read`) instead of redundantly
re-archiving `i2c-examples`, and by inserting "I2C RTC Set"
after the already-merged "I2C RTC Read".

## What's actually changing

Same as the prior attempt:

| File | Change |
|---|---|
| `src/examples/assembler/i2c_ds1307_set.s` (new) | UART RX → 6-digit ASCII parse → BCD → i2c-write registers 0-2 → i2c-read back → print "HH:MM:SS\n". Identical to the file we already verified works (saved to /tmp/i2c_ds1307_set.s before deleting the stale pr/ branches). |
| `tests/integration_tests.rs` (2 hunks) | register `("I2C RTC Set", ...)` alphabetically AFTER `"I2C RTC Read"` (now merged); add `"I2C RTC Set"` to `non_halting` in `test_all_examples_halt`. Display name uses RTC (device class) not DS1307 (chip) from the start — no follow-up rename commit needed. |

## Saga-complete supersets-feat discipline (Part 2)

The work commit will use the final "I2C RTC Set" label from the
start. No follow-up "rename label" commit. `pr/i2c-ds1307-set-
saga-complete` will branch off `pr/i2c-ds1307-set` AFTER `dg-mark-
pr`, so it's a strict superset (= feat + 1 bookkeeping commit).
Restores the earlier discipline per mike's brief Part 2.

## Out of scope

- No new RTC demo .s files beyond the existing two.
- No emulator changes (waits on dcemu's parallel work).
- No demo header updates for `?preset=system` (Part 3 of mike's
  brief — waits on dcemu to ship).
- No "battery" naming.

## Steps

1. **i2c-ds1307-set** — single step. Restore the .s, register in
   tests, verify end-to-end with the same three test inputs that
   passed last time (12:34:56, 09:30:00, 23:59:59), commit.

## When done

`dg-mark-pr` → `pr/i2c-ds1307-set`. Then `feat/i2c-ds1307-set-
saga-complete` off `pr/i2c-ds1307-set`, commit bookkeeping,
`dg-mark-pr` → `pr/i2c-ds1307-set-saga-complete`. Both branches
relay cleanly without rebase next time per Part 2 discipline.
