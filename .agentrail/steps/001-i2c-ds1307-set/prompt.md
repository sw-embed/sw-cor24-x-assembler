Restore `src/examples/assembler/i2c_ds1307_set.s` from
`/tmp/i2c_ds1307_set.s` (saved before the prior pr/ branches
were deleted). Register in tests, verify, commit. Per mike's
`dcxas-finish-ds1307-set-and-document-cli-preset.md` Part 1.

## 1. Restore the .s file

```bash
cp /tmp/i2c_ds1307_set.s src/examples/assembler/i2c_ds1307_set.s
```

(It's the SAME 393-line file we shipped on the prior pr/ branch,
already verified end-to-end against three test inputs.)

## 2. Edit `tests/integration_tests.rs::examples()`

Current dev has:
```
        (
            "I2C Add1 Ping",
            include_str!("../src/examples/assembler/i2c_add1_ping.s"),
        ),
        (
            "I2C RTC Read",
            include_str!("../src/examples/assembler/i2c_ds1307_read.s"),
        ),
        (
            "Literals",
            ...
        ),
```

Insert "I2C RTC Set" between "I2C RTC Read" and "Literals":

```
        (
            "I2C RTC Read",
            include_str!("../src/examples/assembler/i2c_ds1307_read.s"),
        ),
        (
            "I2C RTC Set",
            include_str!("../src/examples/assembler/i2c_ds1307_set.s"),
        ),
        (
            "Literals",
            ...
        ),
```

## 3. Add to `non_halting` in `test_all_examples_halt`

```
    let non_halting = [
        "Blink LED",
        "Button Echo",
        "Button Echo (MakerLisp)",
        "Echo",
        "I2C RTC Set", // busy-polls UART RX waiting for 6 digits
        "Loop Trace",
    ];
```

## 4. Verify

```bash
cargo build --workspace --release
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings

# Spot-check round-trip:
target/release/cor24-asm src/examples/assembler/i2c_ds1307_set.s -o /tmp/dsset.lgo
EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu
$EMU --lgo /tmp/dsset.lgo --uart-input "123456" \
     --i2c-device ds1307@0x68 --quiet --time 5
# expect: "12:34:56\n"
```

## 5. Commit

```
feat(examples): add I2C RTC Set demo (UART-driven time set)

Reads 6 ASCII digits (HHMMSS) from UART RX, parses to BCD,
writes the DS1307 seconds/minutes/hours registers via i2c, then
reads back and prints HH:MM:SS\n. Halt.

Pairs with i2c_ds1307_read.s (already merged): read = observer
that prints the current registers; set = driver that proves the
i2c write path through the same bit-bang library. Together they
exercise both directions of the DS1307 protocol.

Display label uses the device class ("I2C RTC Set") per the
dropdown convention; the chip name (DS1307) stays in code
comments and the filename.

Verified via cor24-emu --uart-input <6-digits> --i2c-device
ds1307@0x68 across three inputs: 12:34:56, 09:30:00, 23:59:59
all round-trip cleanly in ~8K instructions each.

Registered in tests/integration_tests.rs::examples() alphabetically
after "I2C RTC Read", and added to non_halting (uart_getc busy-
polls UART RX forever without input).

This rebuilds the prior pr/i2c-ds1307-set chain off current dev
to resolve the rename/rename conflict where the old chain had a
redundant archive of i2c-examples. Per mike's brief
dcxas-finish-ds1307-set-and-document-cli-preset.md Part 1.
```

Include the `.agentrail/` deltas (saga archive of `i2c-ds1307-
read` + new saga init + step setup) in the same commit, per the
established pattern.

## 6. Wrap (Part 2 discipline — saga-complete is strict superset)

After the work commit:

1. `agentrail complete --done`
2. `dg-mark-pr` → `pr/i2c-ds1307-set`
3. `git switch -c feat/i2c-ds1307-set-saga-complete pr/i2c-ds1307-set`
4. `git add .agentrail/ && git commit -m "saga: record i2c-ds1307-set completion"`
5. `dg-mark-pr` → `pr/i2c-ds1307-set-saga-complete`

**Do not add any follow-up commits to `pr/i2c-ds1307-set` after
creating the saga-complete branch.** If something needs fixing,
rebuild both branches per the discipline. The display label and
non_halting entry are correct from the start in this rebuild —
no fixup needed.
